class_name PlayerState extends RefCounted
## Pure-data state of one player (absolute id 0 = host, 1 = guest).
## No perspective, no scene tree, no autoloads. Deck/hand hold card instance ids only.

var deck: Array[int] = []  # instance ids; index 0 = top of deck
var hand: Array[int] = []  # instance ids; index 0 = NEWEST card
var base_max_mana: int = 1
var bonus_max_mana: int = 0
var current_mana: int = 1
var pending_bonus_mana: int = 0  # temp bonus queued for next turn
var active_temp_mana: int = 0  # temp bonus active this turn
var is_deep: bool = false
var permanently_leveled_up: Dictionary = {}  # champion Name -> highest card_id
var ended_turn: bool = false
var undo_stack: Array[Dictionary] = []  # {instance_id, hand_index, cost}, one entry per card played from hand this turn


## Returns the current maximum mana (base + bonus), never below 0.
func get_max_mana() -> int:
	return max(0, base_max_mana + bonus_max_mana)


## Returns a JSON-safe Dictionary with every field of this player.
func to_dict() -> Dictionary:
	var deck_out: Array = []
	for id in deck:
		deck_out.append(int(id))
	var hand_out: Array = []
	for id in hand:
		hand_out.append(int(id))
	var level_up_out: Dictionary = {}
	for name in permanently_leveled_up:
		level_up_out[str(name)] = str(permanently_leveled_up[name])
	var undo_out: Array = []
	for entry in undo_stack:
		undo_out.append({
			"instance_id": int(entry.get("instance_id", -1)),
			"hand_index": int(entry.get("hand_index", -1)),
			"cost": int(entry.get("cost", 0)),
		})
	return {
		"deck": deck_out,
		"hand": hand_out,
		"base_max_mana": base_max_mana,
		"bonus_max_mana": bonus_max_mana,
		"current_mana": current_mana,
		"pending_bonus_mana": pending_bonus_mana,
		"active_temp_mana": active_temp_mana,
		"is_deep": is_deep,
		"permanently_leveled_up": level_up_out,
		"ended_turn": ended_turn,
		"undo_stack": undo_out,
	}


## Rebuilds a PlayerState from to_dict() output; numbers are int()-cast because JSON
## turns all integers into floats.
static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	var deck_out: Array[int] = []
	var raw_deck: Array = d.get("deck", [])
	for id in raw_deck:
		deck_out.append(int(id))
	p.deck = deck_out
	var hand_out: Array[int] = []
	var raw_hand: Array = d.get("hand", [])
	for id in raw_hand:
		hand_out.append(int(id))
	p.hand = hand_out
	p.base_max_mana = int(d.get("base_max_mana", 1))
	p.bonus_max_mana = int(d.get("bonus_max_mana", 0))
	p.current_mana = int(d.get("current_mana", 1))
	p.pending_bonus_mana = int(d.get("pending_bonus_mana", 0))
	p.active_temp_mana = int(d.get("active_temp_mana", 0))
	p.is_deep = bool(d.get("is_deep", false))
	var level_up: Dictionary = {}
	var raw_level_up: Dictionary = d.get("permanently_leveled_up", {})
	for name in raw_level_up:
		level_up[str(name)] = str(raw_level_up[name])
	p.permanently_leveled_up = level_up
	p.ended_turn = bool(d.get("ended_turn", false))
	var undo_in: Array[Dictionary] = []
	var raw_undo: Array = d.get("undo_stack", [])
	for raw_entry in raw_undo:
		var entry: Dictionary = raw_entry as Dictionary
		undo_in.append({
			"instance_id": int(entry.get("instance_id", -1)),
			"hand_index": int(entry.get("hand_index", -1)),
			"cost": int(entry.get("cost", 0)),
		})
	p.undo_stack = undo_in
	return p
