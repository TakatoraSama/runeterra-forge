## The hidden-information auditor (M5a). It watches ONE viewer's traffic and says
## whether anything the other player must not know got through.
##
## Why it exists: redaction is easy to get subtly wrong in a dozen places at once — a
## new event, a card that is hidden until it resolves, a lane assigned before it is
## revealed. The rules are the only place that knows the truth, so this class is handed
## the state and re-derives, per delivered batch, what the viewer could not possibly
## have been shown. A clean run is zero issues for both viewers of a whole match; the
## host runs it on every batch it sends (see MatchController) and prints [LEAK].
##
## It checks:
##   - an opponent card that is still hidden (hand, deck, or face-down on the board)
##     named by an event that carries its identity or its numbers;
##   - an opponent play, undo, swap or refusal reaching the viewer at all;
##   - the opponent's mana moving during PLAY, in an event or in a snapshot;
##   - a lane_assigned that still carries lane_ids;
##   - a private_to that is not the viewer, not a real player, or not the player the
##     event is about;
##   - a snapshot board row with no card_id that still shows cost or keywords;
##   - an opponent hand that is not a plain count.
##
## What it deliberately does NOT do: judge whether the view is pretty, whether a value
## is plausible, or anything about the viewer's OWN information.
##
## Engine rules: RefCounted, no Node, no scene tree, no autoloads, no signals.
class_name MatchLeakCheck extends RefCounted

## The state the truth is read from. Null makes every check a no-op.
var state: MatchState

## The absolute id of the viewer this checker guards (0 = host, 1 = guest).
var viewer: int = 0

## Every issue found since construction, newest last.
var issues: Array[String] = []

## Opponent instances the viewer has legitimately been shown, learned from the event
## stream: a card_revealed or card_summoned is the moment an opponent's card turns
## face-up. This is tracked rather than read off `state` because a batch is judged as
## it was sent, while `state` has already moved on.
var _public: Dictionary = {}

## The viewer ids this checker has already reported a card as hidden for, so one leak
## is one issue and not one per batch.
var _reported: Dictionary = {}

## The round phase as the STREAM last announced it. A batch describes the moment it was
## sent, while `state` has already run on into the next turn — the resolve re-publishes
## the opponent's mana and then opens the next PLAY inside one batch, so reading the
## phase off the live state would call that re-publish a leak. Phase events are the
## only honest source here.
var _round_phase: int = MatchState.RoundPhase.NONE


func _init(p_state: MatchState, p_viewer: int) -> void:
	state = p_state
	viewer = p_viewer
	if p_state != null:
		_round_phase = p_state.round_phase


## Checks one batch already redacted for `viewer` and returns the issues it added
## (empty when clean). The caller passes what was DELIVERED, not the raw batch: the
## point is to judge what actually left the host.
func check_batch(events: Array) -> Array[String]:
	var found: Array[String] = []
	for raw: Variant in events:
		if not (raw is Dictionary):
			found.append("a batch entry is not a Dictionary")
			continue
		found.append_array(_check_event(raw as Dictionary))
	issues.append_array(found)
	return found


## Checks a full snapshot for `viewer` and returns the issues it added.
func check_snapshot(snapshot: Dictionary) -> Array[String]:
	var found: Array[String] = []
	if snapshot.is_empty():
		return found
	for entry: Variant in snapshot.get("players", []):
		if not (entry is Dictionary):
			continue
		var player_entry: Dictionary = entry
		var player_id: int = int(player_entry.get("player", -1))
		if player_id == viewer:
			_check_own_undo_count(player_entry)
			continue
		if player_entry.get("hand", null) is Array:
			found.append("player %d: the opponent's hand is a list, not a count" % player_id)
		found.append_array(_check_masked_mana(snapshot, player_entry, player_id))
	for row: Variant in snapshot.get("board", []):
		if not (row is Dictionary):
			continue
		found.append_array(_check_board_row(row as Dictionary))
	issues.append_array(found)
	return found


## True when nothing has been flagged so far.
func is_clean() -> bool:
	return issues.is_empty()


# ----------------------------
# Events
# ----------------------------

## One event, already redacted for `viewer`.
func _check_event(event: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var type_name: StringName = event.get("type", &"")

	if event.has("lane_ids"):
		found.append("%s still carries lane_ids" % str(type_name))

	found.append_array(_check_private_to(event))

	if type_name == MatchEvents.PHASE_CHANGED:
		# The phase has to be read as it was SENT: by the time a batch is judged the
		# engine may already have opened the next turn inside it.
		_round_phase = int(event.get("round_phase", _round_phase))

	# The opponent's own moves are redacted away; seeing one at all is a leak.
	if event.has("player") and int(event["player"]) != viewer:
		match type_name:
			MatchEvents.CARD_PLAYED, MatchEvents.PLAY_UNDONE, MatchEvents.SWAP_STARTED, \
					MatchEvents.INTENT_REJECTED:
				found.append("%s reached the viewer for the opponent (player %d)" % [
					str(type_name), int(event["player"])])

	if type_name == MatchEvents.MANA_CHANGED and event.has("player") \
			and int(event["player"]) != viewer and _in_play():
		found.append("the opponent's mana moved during PLAY (player %d)" % int(event["player"]))

	# A reveal is the moment a hidden card becomes public, so record it before asking
	# whether its payload was allowed to travel.
	if type_name == MatchEvents.CARD_REVEALED or type_name == MatchEvents.CARD_SUMMONED:
		_public[int(event.get("instance_id", -1))] = true

	if event.has("instance_id"):
		found.append_array(_check_identity(event, int(event["instance_id"])))
	return found


## private_to must name a real player, must be this viewer (anything else was supposed
## to be dropped) and, when the event names a player, must be that player.
func _check_private_to(event: Dictionary) -> Array[String]:
	if not event.has("private_to"):
		return []
	var found: Array[String] = []
	var private_to: int = int(event["private_to"])
	if private_to != 0 and private_to != 1:
		found.append("private_to %d is not a player" % private_to)
		return found
	if private_to != viewer:
		found.append("a private_to=%d event reached viewer %d" % [private_to, viewer])
	if event.has("player") and int(event["player"]) != private_to:
		found.append("private_to=%d on an event about player %d" % [
			private_to, int(event["player"])])
	return found


## An event about an opponent card that is still hidden must not carry anything that
## identifies it or gives it away: its card_id, its numbers, its keywords, its levels.
func _check_identity(event: Dictionary, instance_id: int) -> Array[String]:
	if instance_id < 0 or _is_public(instance_id):
		return []
	var leaked: Array[String] = []
	for key: String in ["card_id", "power", "new_power", "cost", "new_cost",
			"keywords", "keyword", "old_card_id", "new_card_id"]:
		if not event.has(key):
			continue
		leaked.append(str(event[key]))
	if leaked.is_empty():
		return []
	if _reported.has(instance_id):
		return []
	_reported[instance_id] = true
	return ["instance %d is still hidden but a %s leaked %s" % [
		instance_id, str(event.get("type", "")), ", ".join(leaked)]]


# ----------------------------
# Snapshot
# ----------------------------

## A board row with no card_id is a face-down card: it may keep its slot, and nothing
## else. Cost and keywords are exactly what a face-down card must not give away.
func _check_board_row(row: Dictionary) -> Array[String]:
	if row.get("card_id", null) != null:
		return []
	var owner: int = int(row.get("owner", -1))
	if owner == viewer:
		return []
	var found: Array[String] = []
	for key: String in ["power", "cost", "keywords"]:
		if row.get(key, null) != null:
			found.append("instance %d is face-down but the snapshot shows its %s" % [
				int(row.get("instance_id", -1)), key])
	return found


## During PLAY the opponent's pool must read as it stood when the turn opened; at any
## other phase the resolve has re-published the real number.
func _check_masked_mana(snapshot: Dictionary, player_entry: Dictionary, player_id: int) -> Array[String]:
	if state == null:
		return []
	if int(snapshot.get("round_phase", -1)) != MatchState.RoundPhase.PLAY:
		return []
	var expected: int = state.players[player_id].turn_start_mana
	var shown: int = int(player_entry.get("current_mana", 0))
	if shown == expected:
		return []
	return ["player %d: mana during PLAY view=%d turn-start=%d" % [player_id, shown, expected]]


## The viewer's own undo_count has to be the real one — a snapshot that understates it
## would let a guest offer an undo it cannot perform.
func _check_own_undo_count(player_entry: Dictionary) -> Array[String]:
	if state == null:
		return []
	var expected: int = state.players[viewer].undo_stack.size()
	var shown: int = int(player_entry.get("undo_count", -1))
	if shown == expected:
		return []
	return ["player %d: undo_count view=%d engine=%d" % [viewer, shown, expected]]


# ----------------------------
# Internals
# ----------------------------

## True when the viewer is entitled to know what this instance is.
func _is_public(instance_id: int) -> bool:
	if _public.has(instance_id):
		return true
	if state == null:
		return false
	var card := state.card(instance_id)
	if card == null:
		return false
	if card.owner == viewer:
		return true
	if card.is_resolved or card.location == CardState.Location.GONE:
		return true
	return false


## True while the stream says the match is in the PLAY phase of a turn.
func _in_play() -> bool:
	return _round_phase == MatchState.RoundPhase.PLAY
