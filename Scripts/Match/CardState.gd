class_name CardState extends RefCounted
## Pure-data instance of one card in a match.
## Mirrors the stat fields of the old `Scripts/Card.gd` without any Node, visual,
## animation or autoload behaviour. Power/cost maths must stay identical to that script.

enum Location { DECK, HAND, BOARD, SPELL_ZONE, GONE }

var instance_id: int = -1
var card_id: String = ""
var owner: int = -1
var location: int = Location.DECK
var col: int = -1  # lane column 0..2 when on BOARD; -1 for SPELL_ZONE or off-board
var slot: int = -1  # index inside its zone (0-1 = front row, 2-3 = back row); -1 off-board
var power_modifier: int = 0
var aura_power_modifier: int = 0
var cost_modifier: int = 0
var aura_cost_modifier: int = 0
var runtime_keywords: Array[String] = []
var is_resolved: bool = false
var axe_play_count: int = 0


## Returns the CardDatabase entry for this card, or an empty Dictionary if unknown.
func data() -> Dictionary:
	return CardDatabase.CARDS.get(card_id, {})


## Returns true when the card has a base Power (landmarks/spells do not).
func has_power() -> bool:
	return data().has("Power")


## Returns the unmodified base Power from CardDatabase (0 when the card has none).
func base_power() -> int:
	return int(data().get("Power", 0))


## Returns the current Power (base + permanent modifier + aura modifier), 0 when the card has no Power.
func get_current_power() -> int:
	if not has_power():
		return 0
	return base_power() + power_modifier + aura_power_modifier


## Returns the current Cost (base + cost modifier + aura cost modifier), clamped to a minimum of 0.
func get_current_cost() -> int:
	return max(0, int(data().get("Cost", 0)) + cost_modifier + aura_cost_modifier)


## Returns a new Array with the CardDatabase keywords followed by the runtime ones.
func keywords() -> Array:
	var result: Array = []
	result.append_array(data().get("Keyword", []))
	result.append_array(runtime_keywords)
	return result


## Returns true when the card has the given keyword from either source.
func has_keyword(k: String) -> bool:
	return keywords().has(k)


## Returns a JSON-safe Dictionary with every field of this card.
func to_dict() -> Dictionary:
	var keywords_out: Array = []
	for k in runtime_keywords:
		keywords_out.append(str(k))
	return {
		"instance_id": instance_id,
		"card_id": card_id,
		"owner": owner,
		"location": location,
		"col": col,
		"slot": slot,
		"power_modifier": power_modifier,
		"aura_power_modifier": aura_power_modifier,
		"cost_modifier": cost_modifier,
		"aura_cost_modifier": aura_cost_modifier,
		"runtime_keywords": keywords_out,
		"is_resolved": is_resolved,
		"axe_play_count": axe_play_count,
	}


## Rebuilds a CardState from to_dict() output; every number is int()-cast because JSON
## turns all integers into floats.
static func from_dict(d: Dictionary) -> CardState:
	var c := CardState.new()
	c.instance_id = int(d.get("instance_id", -1))
	c.card_id = str(d.get("card_id", ""))
	c.owner = int(d.get("owner", -1))
	c.location = int(d.get("location", Location.DECK))
	c.col = int(d.get("col", -1))
	c.slot = int(d.get("slot", -1))
	c.power_modifier = int(d.get("power_modifier", 0))
	c.aura_power_modifier = int(d.get("aura_power_modifier", 0))
	c.cost_modifier = int(d.get("cost_modifier", 0))
	c.aura_cost_modifier = int(d.get("aura_cost_modifier", 0))
	var kw: Array[String] = []
	var raw_kw: Array = d.get("runtime_keywords", [])
	for k in raw_kw:
		kw.append(str(k))
	c.runtime_keywords = kw
	c.is_resolved = bool(d.get("is_resolved", false))
	c.axe_play_count = int(d.get("axe_play_count", 0))
	return c
