## Rule engine entry point for the pure-data match model.
##
## Players submit intents; the engine answers with the events that result. In M1 the
## engine is a skeleton: it only rejects obviously impossible intents and otherwise
## accepts everything, so the round loop and card rules land in M2.
## No Node, no scene tree, no signals, no autoloads — pure data in, events out.
class_name MatchRules extends RefCounted

var state: MatchState
var _buffer: Array = []


func _init(p_state: MatchState) -> void:
	"""Bind the engine to an existing MatchState."""
	state = p_state


func submit(player: int, intent: Variant) -> Array:
	"""Validate one intent from `player` and return the resulting event Array.
	M1 rejects only malformed input and wrong moments; the actual card rules are M2."""
	var intent_type: String = ""
	if intent is Dictionary:
		intent_type = str(intent.get("type", ""))
	if player != 0 and player != 1:
		_emit(MatchEvents.intent_rejected(player, intent_type, "bad_player"))
		return _flush()
	if not MatchIntents.is_well_formed(intent):
		_emit(MatchEvents.intent_rejected(player, intent_type, "malformed"))
		return _flush()
	if state.game_phase != MatchState.GamePhase.TURN_LOOP or state.round_phase != MatchState.RoundPhase.PLAY:
		_emit(MatchEvents.intent_rejected(player, intent_type, "wrong_phase"))
		return _flush()
	match intent_type:
		MatchIntents.PLAY_CARD:
			# TODO(M2): validate against CardManager.finish_drag — the card must be in the
			# player's hand, affordable, the column must be open, the zone must have a free
			# slot, the card type must allow that zone (units to board, spells to the spell
			# zone), and static keyword / summon sickness rules must pass. Then call
			# MatchState.place_card(), spend mana and emit CARD_PLAYED.
			pass
		MatchIntents.SWAP_CARD:
			# TODO(M2): validate the card is on the board and owned by `player`, the target
			# column is open and different, and the two columns are swappable (SWAP_LANE
			# rules from SwapLaneManager / GameManager). Then move it and emit CARD_SWAPPED.
			pass
		MatchIntents.UNDO:
			# TODO(M2): roll back everything this player did this turn, restore mana, and
			# emit PLAY_UNDONE with the affected instance ids.
			pass
		MatchIntents.END_TURN:
			# TODO(M2): hand priority to the opponent, move round_phase to RESOLVE and
			# emit PRIORITY_CHANGED / PHASE_CHANGED.
			pass
	return _flush()


func advance() -> Array:
	"""Drive the round loop and return the resulting event Array.
	M1 does nothing at all."""
	# TODO(M2): the ROUND_START -> PLAY -> SWAP_LANE -> RESOLVE -> ROUND_END loop from
	# GameManager: set up the round, reset mana, reveal lanes, resolve abilities in
	# play_order, check the Deep / win conditions and enter GAME_END (GAME_ENDED).
	return _flush()


func _emit(event: Dictionary) -> void:
	"""Queue an event for the next _flush()."""
	_buffer.append(event)


func _flush() -> Array:
	"""Return the buffered events and clear the buffer."""
	var out: Array = _buffer
	_buffer = []
	return out
