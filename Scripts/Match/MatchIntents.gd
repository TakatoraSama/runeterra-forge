## Player intents for the pure-data rules engine.
##
## An intent is the only thing a player may send to the engine: a plain Dictionary
## with a "type" key plus that intent's payload. Intents are validated with
## is_well_formed() before any rule runs, so the rules layer can assume the shape.
## All values are numbers; JSON produces floats, so integral floats are accepted.
## This class is static only: it holds no state.
class_name MatchIntents

const PLAY_CARD := &"play_card"		# {instance_id, col, slot}  col 0..2 or MatchState.SPELL_COL (-1); slot -1..3 (-1 = any free slot)
const SWAP_CARD := &"swap_card"		# {instance_id, to_col}     to_col 0..2
const UNDO := &"undo"				# {}
const END_TURN := &"end_turn"		# {}


static func play_card(instance_id: int, col: int, slot: int = -1) -> Dictionary:
	"""Play the card `instance_id` into column `col` (MatchState.SPELL_COL for the spell zone), optionally at `slot`."""
	return {"type": PLAY_CARD, "instance_id": instance_id, "col": col, "slot": slot}


static func swap_card(instance_id: int, to_col: int) -> Dictionary:
	"""Move the board card `instance_id` to column `to_col` during SWAP_LANE."""
	return {"type": SWAP_CARD, "instance_id": instance_id, "to_col": to_col}


static func undo() -> Dictionary:
	"""Undo this turn's plays."""
	return {"type": UNDO}


static func end_turn() -> Dictionary:
	"""End this player's turn."""
	return {"type": END_TURN}


## Returns `value` as an int, or null when it is not a number with an integral value.
## JSON turns every int into a float, so 2.0 must be accepted as 2.
static func _as_int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		if not is_finite(value):
			return null
		if value != floor(value):
			return null
		return int(value)
	return null


static func is_well_formed(intent: Variant) -> bool:
	"""True only when `intent` is a Dictionary with a known "type", every required key
	present, every value a number with an integral value, and every value in range."""
	if not (intent is Dictionary):
		return false
	var type_id: Variant = intent.get("type", null)
	if not (type_id is String or type_id is StringName):
		return false
	var known: bool = false
	var instance_id: int = -1
	var col: int = 0
	var slot: int = 0
	var to_col: int = 0
	match type_id:
		PLAY_CARD:
			known = true
			if not (intent.has("instance_id") and intent.has("col") and intent.has("slot")):
				return false
			var v_id: Variant = _as_int(intent["instance_id"])
			var v_col: Variant = _as_int(intent["col"])
			var v_slot: Variant = _as_int(intent["slot"])
			if v_id == null or v_col == null or v_slot == null:
				return false
			instance_id = v_id
			col = v_col
			slot = v_slot
			if instance_id < 0:
				return false
			if not (col == -1 or (col >= 0 and col <= 2)):
				return false
			if slot < -1 or slot > 3:
				return false
		SWAP_CARD:
			known = true
			if not (intent.has("instance_id") and intent.has("to_col")):
				return false
			var v_id: Variant = _as_int(intent["instance_id"])
			var v_to: Variant = _as_int(intent["to_col"])
			if v_id == null or v_to == null:
				return false
			instance_id = v_id
			to_col = v_to
			if instance_id < 0:
				return false
			if to_col < 0 or to_col > 2:
				return false
		UNDO:
			known = true
		END_TURN:
			known = true
	return known
