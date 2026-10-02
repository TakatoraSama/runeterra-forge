## Rule engine entry point for the pure-data match model.
##
## Players submit intents; the engine answers with the events that result. All the
## progress of a match happens inside start_match() and submit(), so advance() never
## does anything on its own.
##
## The rules mirror today's game:
##   start_match    <- GameManager.start_game
##   _begin_turn    <- GameManager.start_next_turn + begin_round_start (+ the mana API)
##   _resolve_round <- GameManager._proceed_to_resolve + SwapLaneManager.execute_swaps
##                     + CardManager.resolve_played_cards + StunManager.on_resolve_start
##                     + GameManager.check_lane_winners_and_update_flip_first
##   _end_game      <- GameManager.end_game + _determine_match_winner_local
##   play / undo / swap / end_turn <- CardManager.finish_drag, _on_undo_button_pressed,
##                     start_drag and _finish_swap_drag
##
## Card abilities are not implemented here: they come in M3 through the MatchAbilities
## hooks, which this class calls at the documented moments and which do nothing in M2.
##
## No Node, no scene tree, no signals, no autoloads, no global RNG — pure data in,
## events out, and every random choice comes from state.rng.
class_name MatchRules extends RefCounted

const MAX_TURNS := 6
const INITIAL_DRAW := 3
const DRAW_PER_TURN := 1

var state: MatchState
var ops: MatchOps
var lanes: MatchLanes
var abilities: MatchAbilities

var _buffer: Array = []
var _started: bool = false


func _init(p_state: MatchState) -> void:
	"""Bind the engine to an existing MatchState and wire the pieces together."""
	state = p_state
	abilities = MatchAbilities.new()
	ops = MatchOps.new(state, _emit, abilities)
	lanes = MatchLanes.new(state, ops)
	abilities.bind(state, ops)


## Replaces the ability hooks (M3 subclass, or a test spy) and rebinds them to this
## match. Must be called before start_match() to see the {Game Start} abilities.
func set_abilities(a: MatchAbilities) -> void:
	abilities = a
	ops.abilities = a
	abilities.bind(state, ops)


# ----------------------------
# Match start
# ----------------------------

## Starts the match on this state and returns every event it produced.
## `lane_ids` is empty to let the engine pick the three lanes itself.
## Calling it twice returns [] and reports the mistake instead of restarting.
func start_match(lane_ids: Array = []) -> Array:
	if _started:
		push_error("MatchRules.start_match: this match was already started")
		return _flush()
	_started = true
	state.game_phase = MatchState.GamePhase.GAME_START
	state.round_phase = MatchState.RoundPhase.NONE
	_emit(MatchEvents.phase_changed(state.game_phase, state.round_phase, state.turn))

	state.flip_first = state.rng.randi_range(0, 1)
	_emit(MatchEvents.priority_changed(state.flip_first))

	for p in 2:
		for card_id in _game_start_card_ids(p):
			abilities.on_game_start(card_id, p)

	lanes.assign(lane_ids)
	lanes.reveal(0)

	for p in _players_in_order():
		for _i in INITIAL_DRAW:
			ops.draw(p)

	_begin_turn()
	return _flush()


## The distinct card ids in player `p`'s deck whose Skill starts with "{Game Start}",
## in deck order. Two copies of the same card fire the ability once.
func _game_start_card_ids(p: int) -> Array[String]:
	var ids: Array[String] = []
	for instance_id in state.players[p].deck:
		var card := state.card(int(instance_id))
		if card == null or ids.has(card.card_id):
			continue
		var skill: String = str(card.data().get("Skill", ""))
		if skill.begins_with("{Game Start}"):
			ids.append(card.card_id)
	return ids


# ----------------------------
# Turn loop
# ----------------------------

## Opens the next turn: mana, lane reveals, round-start abilities, the draw, then PLAY.
## Ends the match instead when the turn counter already reached MAX_TURNS.
func _begin_turn() -> void:
	if state.turn >= MAX_TURNS:
		_end_game()
		return
	state.turn += 1
	state.game_phase = MatchState.GamePhase.TURN_LOOP
	_emit(MatchEvents.turn_started(state.turn))
	_set_round_phase(MatchState.RoundPhase.ROUND_START)

	for p in 2:
		_refresh_mana(p)

	lanes.on_round_start(state.turn)
	_run_round_hooks(true)
	abilities.after_change()

	for p in _players_in_order():
		for _i in DRAW_PER_TURN:
			ops.draw(p)

	for p in 2:
		state.players[p].ended_turn = false
		state.players[p].undo_stack.clear()

	_set_round_phase(MatchState.RoundPhase.PLAY)


## Temporary-mana lifecycle, turn-based growth and the refill, for one player.
## The temp bonus queued during the previous turn is active for exactly this turn.
func _refresh_mana(p: int) -> void:
	var ps: PlayerState = state.players[p]
	ps.bonus_max_mana -= ps.active_temp_mana
	ps.active_temp_mana = 0
	ps.active_temp_mana += ps.pending_bonus_mana
	ps.bonus_max_mana += ps.pending_bonus_mana
	ps.pending_bonus_mana = 0
	ps.base_max_mana = max(1, state.turn)
	ps.current_mana = clamp(ps.current_mana, 0, ps.get_max_mana())
	ps.current_mana = ps.get_max_mana()
	# The pool nothing else has touched yet, which is what an opponent is shown while
	# PLAY lasts: a spend is private (MatchOps.spend_mana hidden) and only re-published
	# at RESOLVE, so this is the number the two views agree on for the whole turn.
	ps.turn_start_mana = ps.current_mana
	_emit(MatchEvents.mana_changed(p, ps.current_mana, ps.get_max_mana()))


## Runs the {Round Start} ({@code is_round_start}) or {Round End} abilities of every
## card that is still on the board, flip-first player first and in play order.
## Stunned cards are skipped, exactly like CardManager.trigger_round_*_abilities.
func _run_round_hooks(is_round_start: bool) -> void:
	for id in _sort_by_flip_first(state.play_order):
		var card := state.card(id)
		if card == null or not _is_on_board(id):
			continue
		if ops.is_stunned(id):
			continue
		if is_round_start:
			abilities.on_round_start(id)
		else:
			abilities.on_round_end(id)


# ----------------------------
# Intents
# ----------------------------

## Validates one intent from `player` and returns the resulting event Array.
## Every rejection emits intent_rejected and changes nothing.
func submit(player: int, intent: Variant) -> Array:
	var intent_type: String = ""
	var intent_instance: int = -1
	if intent is Dictionary:
		intent_type = str(intent.get("type", ""))
		intent_instance = _intent_instance_id(intent)
	if player != 0 and player != 1:
		_reject(player, intent_type, "bad_player", intent_instance)
		return _flush()
	if not MatchIntents.is_well_formed(intent):
		_reject(player, intent_type, "malformed", intent_instance)
		return _flush()
	if state.game_phase != MatchState.GamePhase.TURN_LOOP or state.round_phase != MatchState.RoundPhase.PLAY:
		_reject(player, intent_type, "wrong_phase", intent_instance)
		return _flush()
	match intent_type:
		MatchIntents.PLAY_CARD:
			_play_card(player, intent)
		MatchIntents.SWAP_CARD:
			_swap_card(player, intent)
		MatchIntents.UNDO:
			_undo(player)
		MatchIntents.END_TURN:
			_end_turn(player)
	return _flush()


## play_card {instance_id, col, slot}. The slot is a hint and is ignored: the card is
## appended to its zone, so the board can never be desynced by a stale slot number.
func _play_card(player: int, intent: Dictionary) -> void:
	var type_name := str(MatchIntents.PLAY_CARD)
	var id: int = int(intent["instance_id"])
	var col: int = int(intent["col"])
	if state.players[player].ended_turn:
		_reject(player, type_name, "turn_ended", id)
		return
	var card := state.card(id)
	if card == null or not state.players[player].hand.has(id):
		_reject(player, type_name, "not_in_hand", id)
		return
	var is_spell: bool = str(card.data().get("Type", "")) == "Spell"
	if is_spell and col != MatchState.SPELL_COL:
		_reject(player, type_name, "spell_needs_spell_zone", id)
		return
	if not is_spell and (col < 0 or col >= MatchState.COLUMNS):
		_reject(player, type_name, "unit_needs_lane", id)
		return
	if not is_spell and lanes.is_restricted(col):
		_reject(player, type_name, "noxkraya", id)
		return
	if _room_in(col, player) <= 0:
		_reject(player, type_name, "zone_full", id)
		return
	var cost: int = card.get_current_cost()
	if cost > state.players[player].current_mana:
		_reject(player, type_name, "not_enough_mana", id)
		return

	ops.spend_mana(player, cost, true)
	var hand_index: int = state.players[player].hand.find(id)
	state.remove_from_hand(player, id)
	state.place_card(id, col, player)
	card.is_resolved = false
	state.played_this_turn.append(id)
	if not state.play_order.has(id):
		state.play_order.append(id)
	state.summoned.append({
		"card_id": card.card_id,
		"owner_player_id": player,
		"was_played_from_hand": true,
		"is_resolved": false,
		"instance_id": id,
	})
	state.players[player].undo_stack.append({
		"instance_id": id,
		"hand_index": hand_index,
		"cost": cost,
	})
	_emit(MatchEvents.card_played(player, id, card.card_id, card.col, card.slot))


## undo {} — pulls every card this player played this turn back into their hand, the
## last play first, so each card lands in the exact slot it came from; refunds the cost
## and lists the ids in that same reverse play order.
func _undo(player: int) -> void:
	var type_name := str(MatchIntents.UNDO)
	var stack: Array[Dictionary] = state.players[player].undo_stack
	if stack.is_empty():
		_reject(player, type_name, "nothing_to_undo")
		return
	if state.players[player].ended_turn:
		_reject(player, type_name, "turn_ended")
		return

	# LIFO, NOT ascending hand_index: every recorded index refers to the hand as it was
	# at that play, after the earlier plays had already taken their cards out. Replaying
	# the plays backwards puts each card back into the hand it left.
	var entries: Array[Dictionary] = stack.duplicate()
	entries.reverse()
	var refund: int = 0
	var undone: Array = []
	for entry in entries:
		var id: int = int(entry["instance_id"])
		var card := state.card(id)
		if card == null:
			continue
		refund += int(entry["cost"])
		state.remove_from_zone(id)
		state.played_this_turn.erase(id)
		state.play_order.erase(id)
		_drop_unresolved_summoned_entry(id)
		var index: int = mini(int(entry["hand_index"]), state.players[player].hand.size())
		card.location = CardState.Location.HAND
		card.col = -1
		card.slot = -1
		state.players[player].hand.insert(index, id)
		undone.append(id)

	ops.refund_mana(player, refund, true)
	stack.clear()
	var hand_after: Array = []
	for id in state.players[player].hand:
		hand_after.append(int(id))
	_emit(MatchEvents.play_undone(player, undone, hand_after))


## swap_card {instance_id, to_col} — only an Elusive, resolved, unstunned card of the
## player who owns it may queue a lane swap for the SWAP_LANE phase.
func _swap_card(player: int, intent: Dictionary) -> void:
	var type_name := str(MatchIntents.SWAP_CARD)
	var id: int = int(intent["instance_id"])
	var to_col: int = int(intent["to_col"])
	if state.players[player].ended_turn:
		_reject(player, type_name, "turn_ended", id)
		return
	var card := state.card(id)
	if card == null or card.owner != player:
		_reject(player, type_name, "not_your_card", id)
		return
	if card.location != CardState.Location.BOARD or card.col < 0 or card.col >= MatchState.COLUMNS:
		_reject(player, type_name, "not_on_board", id)
		return
	if not card.is_resolved:
		_reject(player, type_name, "not_resolved", id)
		return
	if not card.has_keyword("Elusive"):
		_reject(player, type_name, "not_elusive", id)
		return
	if ops.is_stunned(id):
		_reject(player, type_name, "stunned", id)
		return
	if _pending_swap_for(id) != null:
		_reject(player, type_name, "already_swapping", id)
		return
	if to_col == card.col:
		_reject(player, type_name, "same_column", id)
		return
	if _room_in(to_col, player) <= 0:
		_reject(player, type_name, "zone_full", id)
		return
	state.pending_swaps.append({
		"instance_id": id,
		"player": player,
		"from_col": card.col,
		"to_col": to_col,
		"turn": state.turn,
	})
	_emit(MatchEvents.swap_started(player, id, card.col, to_col))


## end_turn {} — the round resolves once both players are done.
## turn_ended is public: both sides need it to grey out their own End Turn button while
## the round waits for the other player, and it is announced before the resolve starts.
func _end_turn(player: int) -> void:
	if state.players[player].ended_turn:
		_reject(player, str(MatchIntents.END_TURN), "turn_ended")
		return
	state.players[player].ended_turn = true
	_emit(MatchEvents.turn_ended(player))
	for p in 2:
		if not state.players[p].ended_turn:
			return
	_resolve_round()


## Never drives the loop: every transition happens in start_match() or submit().
func advance() -> Array:
	return _flush()


# ----------------------------
# Resolve
# ----------------------------

## SWAP_LANE -> RESOLVE -> ROUND_END -> priority, then the next turn (or the game end).
func _resolve_round() -> void:
	_set_round_phase(MatchState.RoundPhase.SWAP_LANE)
	_execute_swaps()

	_set_round_phase(MatchState.RoundPhase.RESOLVE)
	_republish_hidden_mana()
	_expire_stuns()
	_resolve_played_cards()

	_set_round_phase(MatchState.RoundPhase.ROUND_END)
	_run_round_hooks(false)
	abilities.after_change()
	lanes.on_round_end(state.turn)

	_update_flip_first()
	state.played_this_turn.clear()
	_begin_turn()


## Moves every queued swap, flip-first player first. A swap is dropped when the card
## left its column in the meantime or when the destination filled up meanwhile.
##
## WHY QUEUE ORDER CANNOT OVERFLOW A DESTINATION (and cannot silently drop one either,
## as long as no ability places a card here, see the caveat below):
##
## For one lane L let free(L) = SLOTS_PER_ZONE - |L| + out(L), where out(L) counts the
## swaps out of L that have NOT run yet and whose card is still in L (exactly what
## MatchState.outgoing_swaps counts while the queue is being walked).
##   * At SWAP_LANE, free(L) = room_L + reservations_L >= 0: a play or a swap into L was
##     only accepted while _room_in(L) >= 1, room_L only ever drops by accepting exactly
##     such an arrival (it starts at SLOTS_PER_ZONE - |L| >= 0) and rises by 1 for every
##     swap queued OUT of L, which is checked against its destination, not against L.
##   * Walking the queue in order keeps free(L) >= 0: a card LEAVING L takes 1 off both
##     |L| and out(L) (free unchanged), a card ARRIVING is only allowed when free >= 1
##     and then lowers free by 1, and a swap that is dropped changes nothing.
##   * When the walk is over out(L) = 0, so |L| <= SLOTS_PER_ZONE: no lane is ever left
##     over capacity, and the lane compacts to slots 0..3 as the cards leave.
##
## That is also why an accepted swap is never dropped for a full destination: arriving
## into a full lane is only possible when free(L) >= 1, i.e. |L| == SLOTS_PER_ZONE and a
## swap OUT of L was already queued — because a swap INTO a full lane with nothing queued
## out has free(L) == 0 and _swap_card rejects it. Such a swap into L was therefore queued
## AFTER that swap out of L (queueing it first would have seen free(L) == 0), and queue
## order runs the departure before the arrival. The arrival finds the slot already free.
##
## The flip-first ordering does not weaken any of this: it only interleaves the two
## PLAYERS, and a swap only ever touches its owner's own zones. Every count above is
## per (col, owner) — _swap_reservations and MatchState.outgoing_swaps both filter on the
## owner — so player 0's swaps can neither fill nor drain player 1's zones, and each
## player's queue is still walked in the order it was queued.
##
## CAVEAT — the argument above covers the SWAP QUEUE only. abilities.on_swap_arrive() runs
## in the middle of the walk and may place a card (Irelia's {swap} summons a Blade into
## the lane it just LEFT), through MatchState.zone_has_space, which folds in the same
## outgoing count. Such a placement may therefore take the very slot a LATER arrival was
## reserved for, and that arrival is then dropped by the space check below. Measured:
## lane 0 = [Irelia, Chip, Chip, Chip], Irelia queued 0->1 and a Zed queued 2->0 — both
## accepted at queue time (lane 0 frees a slot, so room = 4 - 4 + 1 = 1); at SWAP_LANE
## Irelia leaves, the Blade takes the freed slot and the Zed is dropped. No lane ever
## goes over capacity (lane 0 ends at 4); the cost is that one accepted swap is cancelled.
## This is a WIDENING of an existing path, not a new one: the "destination filled up
## meanwhile" drop has always been legal for a swap, but before the outgoing_swaps rule
## no swap could ever be reserved into a FULL lane, so the window was unreachable.
## Tests/test_swap_room.gd pins both halves of this.
func _execute_swaps() -> void:
	var sorted: Array = []
	for p in _players_in_order():
		for entry in state.pending_swaps:
			if int(entry.get("player", -1)) == p:
				sorted.append(entry)
	for entry in sorted:
		var id: int = int(entry["instance_id"])
		var from_col: int = int(entry["from_col"])
		var to_col: int = int(entry["to_col"])
		var card := state.card(id)
		if card == null or card.location != CardState.Location.BOARD or card.col != from_col:
			continue
		if not state.zone_has_space(to_col, card.owner):
			continue
		state.remove_from_zone(id)
		state.place_card(id, to_col, card.owner)
		_emit(MatchEvents.card_swapped(card.owner, id, from_col, to_col, card.slot))
		abilities.on_swap_arrive(id, from_col, to_col)
		state.swap_history.append({
			"card_id": card.card_id,
			"owner_player_id": card.owner,
			"swapped_by_player_id": int(entry["player"]),
			"cause_card_id": card.card_id,
			"from_col": from_col,
			"to_col": to_col,
			"turn_number": int(entry.get("turn", state.turn)),
			"instance_id": id,
		})
	state.pending_swaps.clear()


## Reveals this turn's plays one by one, flip-first player first and in play order,
## fires their {Play} ability and takes the spells back off the board.
func _resolve_played_cards() -> void:
	var order: Array[int] = _sort_by_flip_first(state.played_this_turn)
	var plays: Array = []
	for id in order:
		var card := state.card(id)
		if card == null or not _is_on_board(id):
			continue
		plays.append({"player": card.owner, "instance_id": id, "col": card.col, "slot": card.slot})
	_emit(MatchEvents.resolve_started(plays))

	for id in order:
		var card := state.card(id)
		if card == null or not _is_on_board(id):
			continue
		card.is_resolved = true
		_emit(MatchEvents.card_revealed(card.owner, id, card.card_id, card.col, card.slot,
			card.get_current_power(), card.get_current_cost(), card.keywords()))
		_mark_summoned_entry_resolved(id)
		abilities.on_play(id)
		if str(card.data().get("Type", "")) == "Spell" and _is_on_board(id):
			state.remove_from_zone(id)
			card.location = CardState.Location.GONE
			_emit(MatchEvents.spell_resolved(card.owner, id))
		abilities.after_change()


## Re-publishes, once and publicly, the real mana pool of every player who still has a
## card down this round. A play spends from a private pool and an undo refunds into it,
## so during PLAY the opponent's numbers must not move — this is where they catch up,
## at the same moment the cards they paid for are revealed.
func _republish_hidden_mana() -> void:
	var played: Array[bool] = [false, false]
	for id in state.played_this_turn:
		var card := state.card(id)
		if card != null and card.owner >= 0 and card.owner < played.size():
			played[card.owner] = true
	for p in played.size():
		if not played[p]:
			continue
		var ps: PlayerState = state.players[p]
		_emit(MatchEvents.mana_changed(p, ps.current_mana, ps.get_max_mana()))


## Drops a stun that was applied on an earlier turn, and every stun whose card left
## the board (StunManager.on_resolve_start).
func _expire_stuns() -> void:
	for i in range(state.stuns.size() - 1, -1, -1):
		var entry: Dictionary = state.stuns[i]
		var id: int = int(entry.get("instance_id", -1))
		if int(entry.get("stunned_on_turn", 0)) >= state.turn and _is_on_board(id):
			continue
		state.stuns.remove_at(i)
		ops.remove_keyword(id, "Stun")


## Hands priority to whoever won more lanes, else to the higher total power, else to a
## seeded coin flip. The absolute player id never depends on a perspective.
func _update_flip_first() -> void:
	var won := [0, 0]
	var total := [0, 0]
	for col in MatchState.COLUMNS:
		var power_0: int = ops.lane_power(col, 0)
		var power_1: int = ops.lane_power(col, 1)
		total[0] += power_0
		total[1] += power_1
		if power_0 > power_1:
			won[0] += 1
		elif power_1 > power_0:
			won[1] += 1
	var winner: int = -1
	if won[0] > won[1]:
		winner = 0
	elif won[1] > won[0]:
		winner = 1
	elif total[0] > total[1]:
		winner = 0
	elif total[1] > total[0]:
		winner = 1
	else:
		winner = state.rng.randi_range(0, 1)
	state.flip_first = winner
	_emit(MatchEvents.priority_changed(winner))


# ----------------------------
# Game end
# ----------------------------

## Closes the match: {Game End} abilities first, then the winner and the lane powers.
## Two lanes win the match; otherwise the higher total power does; otherwise it is a tie.
func _end_game() -> void:
	state.game_phase = MatchState.GamePhase.GAME_END
	state.round_phase = MatchState.RoundPhase.NONE
	_emit(MatchEvents.phase_changed(state.game_phase, state.round_phase, state.turn))
	abilities.on_game_end_phase()
	abilities.after_change()

	var won := [0, 0]
	var total := [0, 0]
	var powers: Array = [[], []]
	for col in MatchState.COLUMNS:
		for p in 2:
			var power: int = ops.lane_power(col, p)
			powers[p].append(power)
			total[p] += power
		if powers[0][col] > powers[1][col]:
			won[0] += 1
		elif powers[1][col] > powers[0][col]:
			won[1] += 1

	var winner: int = -1
	if won[0] >= 2:
		winner = 0
	elif won[1] >= 2:
		winner = 1
	elif total[0] > total[1]:
		winner = 0
	elif total[1] > total[0]:
		winner = 1
	_emit(MatchEvents.game_ended(winner, powers))


# ----------------------------
# Internals
# ----------------------------

## Emits one rejection, tagged with "private_to" so it reaches its sender alone: an
## opponent has no business seeing which card the other player tried to move or why
## the move was refused. Only submit() flushes, so a rejection raised inside an intent
## handler still reaches the caller of submit(). `instance_id` names the card the intent
## was about, or -1 for intents that name none (end_turn, undo), so a presenter can put
## that card back where it came from.
func _reject(player: int, intent_type: String, reason: String, instance_id: int = -1) -> void:
	var event := MatchEvents.intent_rejected(player, intent_type, reason, instance_id)
	event["private_to"] = player
	_emit(event)


## The instance_id an intent names, or -1 when it names none or the value is not a
## number. Read before is_well_formed(), so a half-formed play intent still reports
## which card it was trying to move.
func _intent_instance_id(intent: Dictionary) -> int:
	var raw: Variant = intent.get("instance_id", null)
	if raw is int:
		return raw
	if raw is float and is_finite(raw):
		return int(raw)
	return -1


## Switches the round phase and announces it (GameManager._set_round_phase).
func _set_round_phase(next_round_phase: int) -> void:
	state.round_phase = next_round_phase
	_emit(MatchEvents.phase_changed(state.game_phase, state.round_phase, state.turn))


## The two players in flip-first order ([0, 1] until priority is known).
func _players_in_order() -> Array[int]:
	if state.flip_first < 0 or state.flip_first > 1:
		return [0, 1]
	return [state.flip_first, 1 - state.flip_first]


## Reorders instance ids so the flip-first player's come first, keeping their relative
## order (CardManager._sort_cards_by_flip_first).
func _sort_by_flip_first(ids: Array) -> Array[int]:
	var first: Array[int] = []
	var second: Array[int] = []
	for raw in ids:
		var id: int = int(raw)
		var card := state.card(id)
		if card != null and card.owner == state.flip_first:
			first.append(id)
		else:
			second.append(id)
	return first + second


## True when the card sits in a lane column or in its owner's spell zone.
func _is_on_board(id: int) -> bool:
	var card := state.card(id)
	if card == null:
		return false
	return card.location == CardState.Location.BOARD or card.location == CardState.Location.SPELL_ZONE


## How many more cards could still be put into (col, owner) right now:
##   capacity - zone_cards + outgoing_swaps - reservations
##
## ONE formula for both _play_card and _swap_card, so the two can never disagree about
## whether a lane is free. `outgoing_swaps` is the room a lane frees the moment an
## Elusive card is queued OUT of it (MatchState.outgoing_swaps): that is what lets a
## full lane whose Ahri is leaving take the new unit immediately, as the original game
## did. `reservations` are the slots already spoken for by swaps queued INTO this lane,
## so the play and the swap compete for the same free slot instead of both taking it.
##
## The card being swapped contributes nothing extra: it frees room in its ORIGIN lane,
## not in the destination, and _swap_card rejects same_column before asking.
func _room_in(col: int, owner: int) -> int:
	return _zone_capacity(col) \
		- state.zone_cards(col, owner).size() \
		+ state.outgoing_swaps(col, owner) \
		- _swap_reservations(owner, col)


## How many pending swaps `player` already holds for column `col`; those slots are
## spoken for and count against the zone's room.
func _swap_reservations(player: int, col: int) -> int:
	var count: int = 0
	for entry in state.pending_swaps:
		if int(entry.get("player", -1)) == player and int(entry.get("to_col", -1)) == col:
			count += 1
	return count


## The pending swap entry of that card, or null when it has none.
func _pending_swap_for(id: int) -> Variant:
	for entry in state.pending_swaps:
		if int(entry.get("instance_id", -1)) == id:
			return entry
	return null


## Slots a zone holds: the spell zone uses SPELL_SLOTS, a lane column SLOTS_PER_ZONE.
func _zone_capacity(col: int) -> int:
	return MatchState.SPELL_SLOTS if col == MatchState.SPELL_COL else MatchState.SLOTS_PER_ZONE


## Drops the newest unresolved "played from hand" tracker of that card, which the play
## itself created (CardManager._remove_undone_summoned_entry).
func _drop_unresolved_summoned_entry(id: int) -> void:
	var card := state.card(id)
	if card == null:
		return
	for i in range(state.summoned.size() - 1, -1, -1):
		var entry: Dictionary = state.summoned[i]
		if not bool(entry.get("was_played_from_hand", false)):
			continue
		if bool(entry.get("is_resolved", false)):
			continue
		if not _summoned_entry_is_card(entry, card):
			continue
		state.summoned.remove_at(i)
		return


## Marks that card's newest unresolved "played from hand" tracker resolved when it
## flips at RESOLVE, so power-based level-up conditions only count revealed cards.
func _mark_summoned_entry_resolved(id: int) -> void:
	var card := state.card(id)
	if card == null:
		return
	for i in range(state.summoned.size() - 1, -1, -1):
		var entry: Dictionary = state.summoned[i]
		if not bool(entry.get("was_played_from_hand", false)):
			continue
		if bool(entry.get("is_resolved", false)):
			continue
		if not _summoned_entry_is_card(entry, card):
			continue
		entry["is_resolved"] = true
		return


## Tracker entries carry the instance id; entries without one (older serialized data)
## are matched by card id and owner instead.
func _summoned_entry_is_card(entry: Dictionary, card: CardState) -> bool:
	if entry.has("instance_id"):
		return int(entry["instance_id"]) == card.instance_id
	return str(entry.get("card_id", "")) == card.card_id and int(entry.get("owner_player_id", -1)) == card.owner


## Queues an event for the next _flush().
func _emit(event: Dictionary) -> void:
	_buffer.append(event)


## Returns the buffered events and clears the buffer.
func _flush() -> Array:
	var out: Array = _buffer
	_buffer = []
	return out
