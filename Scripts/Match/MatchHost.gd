## The host-authoritative session layer around MatchRules (M5a).
## It owns the engine, redacts every batch per viewer and gates the opening of a turn.
##
## WHY a session layer: MatchRules._end_turn emits nothing for the player who did not
## end the turn, so one END_TURN submit returns the resolve AND the next turn's opening
## in a single batch. Over a network the two peers would then animate that batch at
## different speeds, and the faster peer could already be submitting into a turn the
## slower peer has not opened yet. MatchHost owns the extra state that fixes it:
##
##   - it owns MatchState + MatchRules and is the ONLY thing that calls rules.submit();
##   - it redacts every batch per viewer with MatchEvents.redact_for(event, viewer)
##     and delivers it with a monotone `seq`;
##   - it holds back ONLY the play_opened(T) event — see the gating rule below;
##   - it routes an intent_rejected to the sender alone, and an intent that arrives
##     while the session is not accepting one (not_ready) to the sender alone.
##
## GATING RULE — batches are NOT held back. Every batch the engine returns is redacted
## and delivered to every viewer IMMEDIATELY, in the same call that produced it; a
## resolve batch has to be animated by the guest while it is happening, so holding it
## would freeze the match. The ONE thing held back is the play_opened(T) that opens the
## next PLAY phase:
##
##   after a batch has left the engine in PLAY of a new turn T, play_opened(T) is
##   delivered to every viewer — as its own small batch, carrying no other event —
##   only once EVERY player in acks_required has called presentation_done(p, T), or
##   once ack_timeout(T) fires. Until then the session is closed for input: submit()
##   refuses with not_ready (see submit).
##
##   With acks_required == [] (offline) there is nobody to wait for, so play_opened(T)
##   is appended to the SAME batch that left the engine in PLAY of turn T.
##
##   This applies to turn 1 as well: start_match leaves the engine in PLAY of turn 1 and
##   goes through the very same gate, so on LAN both peers finish the opening draws
##   before either may act.
##
## TRANSPORT-AGNOSTIC BY CONTRACT: MatchHost never touches the network and never names
## MatchNet or a Node. It reaches the outside world only through the two Callables given
## to _init, so the same class drives offline (both view = the local presenter) and LAN
## (host's own presenter + MatchNet for the guest):
##
##   deliver_events(viewer: int, events: Array, seq: int)
##       One batch, already redacted for `viewer`. `events` are plain Dictionaries of
##       primitives and `seq` is that viewer's batch counter, incremented once per
##       delivery and starting at 0. A viewer compares seq to tell a gap from a stall.
##   deliver_snapshot(viewer: int, snapshot: Dictionary)
##       A full state for `viewer` from MatchSnapshot.for_viewer(state, viewer), plus a
##       top-level "seq": the number of event batches that viewer has received. One is
##       sent BEFORE any batch (seq 0, so the view can be built before the first event)
##       and one after EVERY batch that viewer received, so a guest with no MatchState
##       can always --verify-view and autoplay from a picture of exactly what it has
##       animated. A viewer outside snapshot_viewers gets events only.
##
## ENGINE RULES (Scripts/Match, mandatory): RefCounted only, no Node, no get_node, no
## await, no timers, no autoload identifiers, no scene-tree access, no global randi()
## / randf() (all randomness through MatchState.rng). It is synchronous: the ack
## timeout is NOT a timer inside this class (that would need await); the session layer
## above calls ack_timeout(turn) from a SceneTreeTimer that ignores time scale.
class_name MatchHost extends RefCounted

## Wire format of the join handshake. The guest's hello carries the same number and the
## host refuses a mismatch (see check_hello), so two different builds never talk.
const PROTOCOL_VERSION := 1

## The authoritative state and the rules that own it. Null until start().
var state: MatchState = null
var rules: MatchRules = null

## Players whose presentation_done is required before a pending play_opened(T) is
## released. Offline is [] (nobody to wait for); the host is [0, 1]. Player ids are
## absolute: 0 = host, 1 = guest.
var acks_required: Array[int] = []

## Viewers that receive snapshots (join, and --verify-view). A viewer outside this list
## only ever gets event batches.
var snapshot_viewers: Array[int] = []

var _deliver_events: Callable
var _deliver_snapshot: Callable

## viewer -> the seq its NEXT batch will carry. Per viewer, starting at 0.
var _seq: Dictionary = {}
## The turn whose play_opened is still waiting for acks, or -1.
var _pending_turn: int = -1
## player -> true, the acks counted for the pending turn.
var _acked: Dictionary = {}
## The last turn whose play_opened was delivered. -1 before the first one.
var _opened_turn: int = -1
## The winner of the finished match, -1 until game_ended arrives.
var _winner: int = -1


## `deliver_events(viewer, events, seq)` and `deliver_snapshot(viewer, snapshot)` are
## the two delivery Callables described at the top of this file. Both are required: the
## host always delivers to its own viewer, offline delivers events only.
func _init(deliver_events: Callable, deliver_snapshot: Callable) -> void:
	_deliver_events = deliver_events
	_deliver_snapshot = deliver_snapshot


## Builds the match from `deck0` (host) and `deck1` (guest) and runs MatchRules
## .start_match(lane_ids), delivering the opening snapshot to every snapshot viewer
## before the opening event batch. `seed` is the match seed: the host picks it and it
## never leaves the host. `scramble_ids` (M5a Group A) permutes instance-id creation
## with a separate RNG so the guest cannot map the host's deck from draw ids; the main
## state.rng must stay untouched, or a --seed run stops replaying exactly.
## The real card abilities are installed here: a MatchHost owns the engine, so it is
## the one place that decides the match plays with the real cards.
func start(deck0: Array, deck1: Array, seed: int, scramble_ids: bool = false, lane_ids: Array = []) -> void:
	state = MatchSetup.new_match(deck0, deck1, seed, scramble_ids)
	rules = MatchRules.new(state)
	MatchCardAbilities.install(rules)
	_pending_turn = -1
	_acked.clear()
	_opened_turn = -1
	_winner = -1
	# The snapshot always precedes the events it explains, so it goes out first — and
	# before start_match(), while the board is still empty and nothing has been drawn.
	for viewer in snapshot_viewers:
		_deliver_snapshot_to(viewer, 0)
	_publish(rules.start_match(lane_ids))


## Submits `intent` for absolute `player` and delivers the answer per viewer.
##
## Returns true ONLY when the engine accepted the intent. Every refusal is false:
##   - NOT_READY — the session is not accepting input: before the first play_opened has
##     been delivered, while play_opened(T) is still pending for T, or after the match
##     ended. Nothing is changed and the sender alone gets
##       intent_rejected(player, intent_type, "not_ready", instance_id)
##     carrying private_to = player, so it never reaches the opponent;
##   - a refusal the RULES made (not_in_hand, not_enough_mana, wrong_phase, ...) is
##     likewise false, with the engine's own intent_rejected delivered to `player` alone.
## `instance_id` on the not_ready rejection is the card the intent names, or -1.
func submit(player: int, intent: Dictionary) -> bool:
	if not _accepts_input():
		_refuse(player, intent, "not_ready")
		return false
	var events: Array = rules.submit(player, intent)
	var accepted: bool = not _was_rejected(events, player)
	_publish(events)
	return accepted


## Viewer `player` has animated the batch carrying turn `turn` to completion.
## Counts ONCE per player for the pending turn: the first call from a given player for
## that turn records the ack, any repeat from the same player is ignored, and an ack
## naming a turn that is not the pending one is ignored as well — neither can open a
## turn twice. Once every id in acks_required has acked the pending turn, play_opened(T)
## is delivered to every viewer (its own small batch, or appended to the current batch
## when acks_required is empty) and pending_turn() becomes -1.
func presentation_done(player: int, turn: int) -> void:
	if _pending_turn != turn:
		return
	if _acked.has(player):
		return
	_acked[player] = true
	if not _everyone_acked():
		return
	_release(turn)


## True when this call actually released the pending turn: `turn` must be the pending
## turn, in which case play_opened(turn) is delivered to every viewer and true is
## returned. False when nothing is pending or when `turn` is not the pending turn — a
## late timer for an already-opened turn must not open it a second time.
## The session layer calls this from a SceneTreeTimer that ignores time scale (~10 s),
## so one stuck viewer cannot freeze the match.
func ack_timeout(turn: int) -> bool:
	if _pending_turn != turn:
		return false
	_release(turn)
	return true


## The turn whose play_opened is still waiting for acks, or -1 when nothing is pending.
## Matches the `turn` argument of presentation_done() and ack_timeout().
func pending_turn() -> int:
	return _pending_turn


## True once the match reached GAME_END (or the session ended for another reason).
func is_over() -> bool:
	if _winner >= 0:
		return true
	return state != null and state.game_phase == MatchState.GamePhase.GAME_END


## The winner of the finished match: 0 host, 1 guest, -1 for a tie. -1 while the match
## is still running.
func winner() -> int:
	return _winner


## The full state `viewer` is allowed to see, from MatchSnapshot.for_viewer. Never
## sent to a viewer outside snapshot_viewers. This is the authoritative view --verify-view
## compares the presenter's model against.
##
## It carries NO "seq": that tag belongs to a DELIVERED snapshot, where it says how many
## batches the viewer has received (see _deliver_snapshot_to). Locally the seq is known.
func snapshot_for(viewer: int) -> Dictionary:
	if state == null:
		return {}
	return MatchSnapshot.for_viewer(state, viewer)


## Validates a guest's join payload BEFORE any MatchState exists, so a bad handshake
## cannot start a match. `payload` is what the guest's hello sent:
##   {protocol: int, deck: Array[String], want_snapshots: bool}
## Returns a Dictionary with exactly these keys:
##   ok              bool    - true only when the match may start
##   reason: String  - "" when ok, else a REASON_TEXT key of MatchPresenter
##                       ("bad_protocol", "second_guest", "bad_deck")
##   deck: Array[String] - MatchDecks.sanitize(payload.deck): the validated 12 ids to
##                       start with, or DEFAULT_DECK_IDS when the guest sent none
##   want_snapshots: bool  - echoed back from the payload; false for anything that is
##                       not a real bool, so a hostile payload cannot force snapshots
## The deck is validated with MatchDecks.sanitize, the same rule as an offline saved
## deck. The guest's list never reaches the host's presenter, and the host's own deck
## and seed are never sent back.
##
## Two of the three reasons are decided here:
##   bad_protocol - `protocol` is missing, is not a number, or is another build's number;
##   bad_deck     - `deck` is present and is not an Array at all. A deck that IS an
##                  array but is not a legal one is not a refusal: sanitize() replaces
##                  it with the default deck, which is exactly what an offline saved
##                  deck does, and the contract for both is "12 known ids or default".
##                  "second_guest" is NOT decided here: this function is static and
##                  stateless, so it cannot know who else is connected. The session
##                  layer (MatchNet / LobbyUI, Group C) owns the peer count and refuses
##                  the extra peer itself; REASON_TEXT still needs the key.
static func check_hello(payload: Dictionary) -> Dictionary:
	var want_snapshots: bool = payload.get("want_snapshots", null) is bool \
			and bool(payload["want_snapshots"])
	var protocol: Variant = payload.get("protocol", null)
	if not (protocol is int) or int(protocol) != PROTOCOL_VERSION:
		return _hello_answer(false, "bad_protocol", MatchDecks.DEFAULT_DECK_IDS.duplicate(), false)
	if not payload.has("deck") or payload["deck"] is Array:
		return _hello_answer(true, "", MatchDecks.sanitize(payload.get("deck", null)), want_snapshots)
	return _hello_answer(false, "bad_deck", MatchDecks.DEFAULT_DECK_IDS.duplicate(), false)


## Builds a check_hello answer. The deck is always a usable one, even when the match
## may not start, so a caller that ignores `ok` still cannot build a broken deck.
static func _hello_answer(ok: bool, reason: String, deck: Array[String], want_snapshots: bool) -> Dictionary:
	return {
		"ok": ok,
		"reason": reason,
		"deck": deck,
		"want_snapshots": want_snapshots,
	}


# ----------------------------
# Delivery
# ----------------------------

## Publishes one batch the engine returned: redacted per viewer, delivered immediately,
## with the play_opened gate applied. Nothing is ever held back except play_opened, and
## only when there is somebody to wait for.
func _publish(events: Array) -> void:
	var batch: Array = events.duplicate()
	var opening: int = _turn_awaiting_open()
	if opening >= 0:
		if acks_required.is_empty():
			# Offline: nobody to wait for, so the turn opens in the very same batch.
			batch.append(MatchEvents.play_opened(opening))
			_opened_turn = opening
		else:
			_pending_turn = opening
			_acked.clear()
	if batch.is_empty():
		return
	_note_result(batch)
	for viewer in [0, 1]:
		_deliver_to(viewer, batch)


## One redacted batch to one viewer, with that viewer's next seq. A batch that is empty
## for this viewer is not delivered at all and does not burn a seq: the numbers a
## viewer sees stay contiguous, which is what makes a missing seq mean a real gap.
## A viewer in snapshot_viewers then gets the state it is allowed to see, tagged with
## the seq of the NEXT batch it will get — see _deliver_snapshot_to.
func _deliver_to(viewer: int, events: Array) -> void:
	var visible: Array = []
	for event: Variant in events:
		var shown: Variant = MatchEvents.redact_for(event, viewer)
		if shown != null:
			visible.append(shown)
	if visible.is_empty():
		return
	var seq: int = int(_seq.get(viewer, 0))
	_seq[viewer] = seq + 1
	if _deliver_events.is_valid():
		_deliver_events.call(viewer, visible, seq)
	if snapshot_viewers.has(viewer):
		_deliver_snapshot_to(viewer, seq + 1)


## The debug snapshot that FOLLOWS a batch: the state `viewer` may see, tagged with
## "seq" = the number of event batches this viewer has now received. That number is the
## whole point: a viewer compares it with the batches it has animated and only trusts a
## snapshot that lines up, so a snapshot can never be read half a turn ahead of the
## board on screen. The opening snapshot, before any batch, is seq 0.
## snapshot_for() itself stays seq-free — only a DELIVERED copy carries the tag.
func _deliver_snapshot_to(viewer: int, seq: int) -> void:
	if not _deliver_snapshot.is_valid():
		return
	var snapshot := snapshot_for(viewer)
	snapshot["seq"] = seq
	_deliver_snapshot.call(viewer, snapshot)


## Remembers the winner, so winner() can answer without replaying the log. A tie is -1,
## which is also the "still running" answer — is_over() is what tells them apart.
func _note_result(events: Array) -> void:
	for event: Variant in events:
		if event is Dictionary and (event as Dictionary).get("type", &"") == MatchEvents.GAME_ENDED:
			_winner = int((event as Dictionary).get("winner", -1))


# ----------------------------
# The play_opened gate
# ----------------------------

## The turn whose PLAY the engine has opened but nobody has been told about yet, or -1.
## Turns only ever move forward, so one counter is enough to know it was announced.
func _turn_awaiting_open() -> int:
	if state == null:
		return -1
	if state.game_phase != MatchState.GamePhase.TURN_LOOP:
		return -1
	if state.round_phase != MatchState.RoundPhase.PLAY:
		return -1
	if state.turn <= _opened_turn:
		return -1
	return state.turn


## True while every player in acks_required has acked the pending turn.
func _everyone_acked() -> bool:
	for player in acks_required:
		if not _acked.has(player):
			return false
	return true


## Opens the turn for good: play_opened(turn) goes out as its own small batch and the
## gate closes behind it. Called by the last ack and by ack_timeout, never twice.
func _release(turn: int) -> void:
	_pending_turn = -1
	_acked.clear()
	_opened_turn = turn
	_deliver_to(0, [MatchEvents.play_opened(turn)])
	_deliver_to(1, [MatchEvents.play_opened(turn)])


## True while the session may take an intent: the match is running, PLAY is open, no
## play_opened is waiting for acks and this turn has already been announced.
func _accepts_input() -> bool:
	if state == null or rules == null:
		return false
	if is_over():
		return false
	if state.game_phase != MatchState.GamePhase.TURN_LOOP:
		return false
	if state.round_phase != MatchState.RoundPhase.PLAY:
		return false
	if _pending_turn != -1:
		return false
	return _opened_turn == state.turn


## Sends one not_ready rejection to its sender alone. Nothing else moves.
func _refuse(player: int, intent: Dictionary, reason: String) -> void:
	var event := MatchEvents.intent_rejected(player, _intent_type(intent), reason, _intent_instance(intent))
	event["private_to"] = player
	_deliver_to(player, [event])


## True when the engine refused: its only refusal is an intent_rejected, and it
## changes nothing else, so its presence in the batch IS the answer.
func _was_rejected(events: Array, player: int) -> bool:
	for event: Variant in events:
		if not (event is Dictionary):
			continue
		var entry: Dictionary = event
		if entry.get("type", &"") != MatchEvents.INTENT_REJECTED:
			continue
		if int(entry.get("player", -1)) == player:
			return true
	return false


## The type a not_ready rejection reports, "" for something that names none.
func _intent_type(intent: Dictionary) -> String:
	if not intent.has("type"):
		return ""
	return str(intent["type"])


## The card a not_ready rejection names, -1 when the intent names none or the value is
## not a number. Read the same lenient way MatchRules reads it, so the sender is told
## about the same card it would have been told about by a rules refusal.
func _intent_instance(intent: Dictionary) -> int:
	var raw: Variant = intent.get("instance_id", null)
	if raw is int:
		return raw
	if raw is float and is_finite(raw):
		return int(raw)
	return -1