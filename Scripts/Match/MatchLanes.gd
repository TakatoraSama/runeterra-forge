## Lane assignment, reveal timing and lane effects for the pure-data rules engine.
##
## Mirrors the old `Scripts/LaneManager.gd` (reveal order, the five lane effects and
## the Noxkraya placement restriction) plus `BoardGeneration.pick_random_lane_ids`.
## Column `col` indexes `state.lane_ids`; index 0 is revealed at game start, 1 on
## turn 2 and 2 on turn 3. No Node, no scene tree, no autoloads: every effect goes
## through MatchOps (state changes + events) and every random pick through `state.rng`.
class_name MatchLanes extends RefCounted

const NAME_HEXCORE := "Hexcore Foundry"
const NAME_ORNN := "Ornn's Forge"
const NAME_SUNKEN := "Sunken Temple"
const NAME_NOXKRAYA := "Noxkraya Arena"
const NAME_ROCKFALL := "Rockfall Path"

const ROCKFALL_CARD := "Chip"

var state: MatchState
var ops: MatchOps


func _init(p_state: MatchState, p_ops: MatchOps) -> void:
	"""Bind the lanes to an existing MatchState and its MatchOps."""
	state = p_state
	ops = p_ops


## Assigns the three lanes. An empty `lane_ids` picks `MatchState.COLUMNS` appearable
## lanes from LaneDatabase with a Fisher-Yates shuffle over the keys in dictionary
## order, wrapping around if there are fewer lanes than columns. Always emits
## LANE_ASSIGNED; nothing is revealed here (the caller reveals column 0).
func assign(lane_ids: Array = []) -> void:
	var ids: Array[String] = []
	if lane_ids.is_empty():
		ids = _pick_lane_ids()
	else:
		for raw: Variant in lane_ids:
			ids.append(str(raw))
	state.lane_ids = ids
	state.lane_revealed = []
	for col in MatchState.COLUMNS:
		state.lane_revealed.append(false)
	state.noxkraya_col = -1
	ops.emit_event(MatchEvents.lane_assigned(_to_plain(ids)))


## Reveals column `col` and runs its on-reveal effects. Does nothing when the column
## is already revealed or does not exist.
func reveal(col: int) -> void:
	if col < 0 or col >= state.lane_revealed.size():
		return
	if state.lane_revealed[col]:
		return
	state.lane_revealed[col] = true
	ops.emit_event(MatchEvents.lane_revealed(col, lane_id(col)))
	_fire_immediate_effects(col)


## Lane reveals and the round-start effects (Noxkraya Arena on turn 5).
func on_round_start(turn: int) -> void:
	if turn == 2:
		reveal(1)
	elif turn == 3:
		reveal(2)
	for col in MatchState.COLUMNS:
		if not _is_revealed(col):
			continue
		if lane_name(col) == NAME_NOXKRAYA and turn == 5:
			ops.emit_event(MatchEvents.lane_effect(col, lane_id(col), "noxkraya_active"))
			state.noxkraya_col = col


## The timed round-end effects (Sunken Temple on turn 3, Ornn's Forge on turn 4),
## then clears the Noxkraya restriction again.
func on_round_end(turn: int) -> void:
	for col in MatchState.COLUMNS:
		if not _is_revealed(col):
			continue
		match lane_name(col):
			NAME_ORNN:
				if turn == 4:
					_activate_ornns_forge(col)
			NAME_SUNKEN:
				if turn == 3:
					_activate_sunken_temple(col)
	state.noxkraya_col = -1


## True while Noxkraya Arena forbids every column but its own.
func is_restricted(col: int) -> bool:
	return state.noxkraya_col >= 0 and col != state.noxkraya_col


## Returns the LaneDatabase Name of the lane in `col` ("" when there is none).
func lane_name(col: int) -> String:
	return str(LaneDatabase.LANES.get(lane_id(col), {}).get("Name", ""))


## Returns the lane id in `col` ("" when there is none).
func lane_id(col: int) -> String:
	if col < 0 or col >= state.lane_ids.size():
		return ""
	return state.lane_ids[col]


## Picks `MatchState.COLUMNS` distinct-if-possible appearable lanes with a
## Fisher-Yates shuffle drawn from the match RNG, over the keys in dictionary order.
func _pick_lane_ids() -> Array[String]:
	var pool: Array[String] = []
	for key in LaneDatabase.LANES:
		var lane_data: Dictionary = LaneDatabase.LANES.get(str(key), {})
		if bool(lane_data.get("Appearable", false)):
			pool.append(str(key))
	var picked: Array[String] = []
	if pool.is_empty():
		return picked
	for i in range(pool.size() - 1, 0, -1):
		var j: int = state.rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for col in MatchState.COLUMNS:
		picked.append(pool[col % pool.size()])
	return picked


## True when column `col` exists and has been revealed.
func _is_revealed(col: int) -> bool:
	if col < 0 or col >= state.lane_revealed.size():
		return false
	return state.lane_revealed[col]


## The two players in flip-first order (falling back to 0 then 1 before it is known).
func _players_in_order() -> Array[int]:
	if state.flip_first < 0 or state.flip_first > 1:
		return [0, 1]
	return [state.flip_first, 1 - state.flip_first]


## On-reveal effects. LANE_EFFECT is always emitted before the effect runs.
func _fire_immediate_effects(col: int) -> void:
	match lane_name(col):
		NAME_HEXCORE:
			_activate_hexcore_foundry(col)
		NAME_ROCKFALL:
			_activate_rockfall_path(col)


## Hexcore Foundry: every player draws 1.
func _activate_hexcore_foundry(col: int) -> void:
	ops.emit_event(MatchEvents.lane_effect(col, lane_id(col), "hexcore_draw"))
	for p in _players_in_order():
		ops.draw(p)


## Rockfall Path: a Chip is summoned for both players in this column (skipped when
## that player's zone is full).
func _activate_rockfall_path(col: int) -> void:
	ops.emit_event(MatchEvents.lane_effect(col, lane_id(col), "rockfall_chip"))
	for p in _players_in_order():
		ops.summon(ROCKFALL_CARD, p, col)


## Ornn's Forge: +1 Power to every resolved unit (Champion / Follower) in this
## column, both owners.
func _activate_ornns_forge(col: int) -> void:
	ops.emit_event(MatchEvents.lane_effect(col, lane_id(col), "ornn_forge"))
	for owner in 2:
		for id in state.zone_cards(col, owner):
			var c := state.card(id)
			if c == null or not c.is_resolved:
				continue
			var card_type: String = str(c.data().get("Type", ""))
			if card_type != "Champion" and card_type != "Follower":
				continue
			ops.change_power(id, 1)


## Sunken Temple: each player shuffles a random card from their hand back into
## their deck (nothing when the hand is empty) and then draws 1.
func _activate_sunken_temple(col: int) -> void:
	ops.emit_event(MatchEvents.lane_effect(col, lane_id(col), "sunken_temple"))
	for p in _players_in_order():
		var hand: Array[int] = state.players[p].hand
		if not hand.is_empty():
			var idx: int = state.rng.randi_range(0, hand.size() - 1)
			ops.shuffle_into_deck(p, hand[idx])
		ops.draw(p)


## Copies a typed String array into a plain Array for the event payload.
func _to_plain(src: Array[String]) -> Array:
	var out: Array = []
	for v in src:
		out.append(v)
	return out