extends "res://Tests/test_case.gd"

## CardState — power/cost math, keywords and (de)serialization.
##
## Cards used: Kennen1 (champion, Cost 1, Power 1, no keywords),
## SpinningAxe (spell, Cost 0, Keyword ["Fast"]), BuriedSunDisc
## (landmark, no Power, Keyword ["Landmark"]).

const CHAMPION := "Kennen1"
const SPELL := "SpinningAxe"
const LANDMARK := "BuriedSunDisc"


func before_each() -> void:
	pass


func _card(card_id: String) -> CardState:
	var card := CardState.new()
	card.card_id = card_id
	card.owner = 0
	return card


func test_base_values_come_from_the_database() -> void:
	var card := _card(CHAMPION)
	assert_eq(card.base_power(), 1, "Kennen1 base power")
	assert_eq(card.get_current_cost(), 1, "Kennen1 cost")
	assert_true(card.has_power(), "Kennen1 is a unit")
	assert_eq(card.data().get("Name"), "Kennen", "data() is the database entry")


func test_has_power_is_false_for_spell_and_landmark() -> void:
	assert_false(_card(SPELL).has_power(), "spell has no Power key")
	assert_false(_card(LANDMARK).has_power(), "landmark has no Power key")
	assert_true(_card(CHAMPION).has_power(), "champion has a Power key")


func test_current_power_adds_both_modifier_kinds() -> void:
	var card := _card(CHAMPION)
	card.power_modifier = 2
	card.aura_power_modifier = 3
	assert_eq(card.get_current_power(), 6, "1 + 2 + 3")


func test_current_power_is_zero_without_a_power_key() -> void:
	var card := _card(SPELL)
	card.power_modifier = 5
	card.aura_power_modifier = 5
	assert_eq(card.get_current_power(), 0, "spells have no power at all")

	var landmark := _card(LANDMARK)
	landmark.power_modifier = 4
	assert_eq(landmark.get_current_power(), 0, "landmarks have no power at all")


func test_negative_power_modifier_can_go_below_zero() -> void:
	var card := _card(CHAMPION)
	card.power_modifier = -3
	assert_eq(card.get_current_power(), -2, "no clamp on power")


func test_current_cost_adds_modifiers_and_clamps_at_zero() -> void:
	var card := _card(CHAMPION)
	card.cost_modifier = -1
	card.aura_cost_modifier = 3
	assert_eq(card.get_current_cost(), 3, "1 - 1 + 3")

	var cheap := _card(SPELL)
	cheap.cost_modifier = -4
	cheap.aura_cost_modifier = -1
	assert_eq(cheap.get_current_cost(), 0, "cost clamps at 0")


func test_keywords_merges_static_and_runtime() -> void:
	var card := _card(SPELL)
	card.runtime_keywords = ["Rush"]
	var merged: Array = card.keywords()
	assert_eq(merged.size(), 2, "one static + one runtime keyword")
	assert_true(merged.has("Fast"), "static keyword kept")
	assert_true(merged.has("Rush"), "runtime keyword merged")
	assert_false(_card(CHAMPION).keywords().has("Fast"), "keywords are per card")


func test_keywords_returns_a_copy() -> void:
	var card := _card(SPELL)
	var first: Array = card.keywords()
	first.append("Mutated")
	var second: Array = card.keywords()
	assert_false(second.has("Mutated"), "callers cannot mutate the card")


func test_has_keyword_checks_static_and_runtime() -> void:
	var card := _card(LANDMARK)
	card.runtime_keywords = ["Stunned"]
	assert_true(card.has_keyword("Landmark"), "static keyword")
	assert_true(card.has_keyword("Stunned"), "runtime keyword")
	assert_false(card.has_keyword("Fast"), "absent keyword")
	assert_false(_card(CHAMPION).has_keyword("Landmark"), "no cross-card leakage")


func test_to_dict_from_dict_round_trip() -> void:
	var card := CardState.new()
	card.instance_id = 7
	card.card_id = CHAMPION
	card.owner = 1
	card.location = CardState.Location.BOARD
	card.col = 2
	card.slot = 3
	card.power_modifier = -1
	card.aura_power_modifier = 2
	card.cost_modifier = -1
	card.aura_cost_modifier = 1
	card.runtime_keywords = ["Stunned", "Shield"]
	card.is_resolved = true
	card.axe_play_count = 2

	var restored := CardState.from_dict(card.to_dict())
	assert_eq(restored.instance_id, 7, "instance_id")
	assert_eq(restored.card_id, CHAMPION, "card_id")
	assert_eq(restored.owner, 1, "owner")
	assert_eq(restored.location, CardState.Location.BOARD, "location")
	assert_eq(restored.col, 2, "col")
	assert_eq(restored.slot, 3, "slot")
	assert_eq(restored.power_modifier, -1, "power_modifier")
	assert_eq(restored.aura_power_modifier, 2, "aura_power_modifier")
	assert_eq(restored.cost_modifier, -1, "cost_modifier")
	assert_eq(restored.aura_cost_modifier, 1, "aura_cost_modifier")
	assert_eq(restored.runtime_keywords, ["Stunned", "Shield"], "runtime_keywords")
	assert_eq(restored.is_resolved, true, "is_resolved")
	assert_eq(restored.axe_play_count, 2, "axe_play_count")
	assert_eq(restored.get_current_power(), 2, "power after round trip")
	assert_eq(restored.get_current_cost(), 1, "cost after round trip")


func test_from_dict_survives_json_round_trip() -> void:
	var card := CardState.new()
	card.instance_id = 42
	card.card_id = SPELL
	card.owner = 0
	card.location = CardState.Location.SPELL_ZONE
	card.runtime_keywords = ["Fast"]
	card.aura_cost_modifier = -2

	var json := JSON.stringify(card.to_dict())
	var parsed: Variant = JSON.parse_string(json)
	assert_true(parsed is Dictionary, "to_dict is JSON-safe")
	var restored := CardState.from_dict(parsed as Dictionary)
	assert_eq(restored.instance_id, 42, "instance_id after JSON")
	assert_eq(restored.location, CardState.Location.SPELL_ZONE, "location after JSON")
	assert_eq(restored.runtime_keywords, ["Fast"], "keywords after JSON")
	assert_eq(restored.get_current_cost(), 0, "clamped cost after JSON")


func test_defaults_of_a_fresh_card() -> void:
	var card := CardState.new()
	assert_eq(card.instance_id, -1, "instance_id default")
	assert_eq(card.card_id, "", "card_id default")
	assert_eq(card.owner, -1, "owner default")
	assert_eq(card.location, CardState.Location.DECK, "location default")
	assert_eq(card.col, -1, "col default")
	assert_eq(card.slot, -1, "slot default")
	assert_eq(card.power_modifier, 0, "power_modifier default")
	assert_eq(card.is_resolved, false, "is_resolved default")
	assert_eq(card.axe_play_count, 0, "axe_play_count default")
	assert_true(card.keywords().is_empty(), "no keywords by default")
	assert_eq(card.get_current_power(), 0, "unknown card has no power")
	assert_eq(card.get_current_cost(), 0, "unknown card costs 0")