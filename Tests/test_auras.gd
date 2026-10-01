extends "res://Tests/test_case.gd"

## MatchAuras — every aura source applies exactly the right amount to exactly the
## right targets, and a recalculation that changes nothing emits nothing.
##
## Each test builds a tiny MatchState by hand (cards dropped straight into zones /
## hands), installs the real MatchCardAbilities dispatcher and calls
## MatchAuras.recalculate() directly, so no other ability can add noise to the board.

const LEFT := 0
const MID := 1
const RIGHT := 2


var _state: MatchState
var _ctx: MatchCardAbilities
var _log: Array


func before_each() -> void:
	_state = MatchState.new()
	_state.rng.seed = 24681357
	_ctx = MatchCardAbilities.install(MatchRules.new(_state))
	_log = []
	_ctx.ops._emit = _collect


func _collect(event: Dictionary) -> void:
	_log.append(event)


# ----------------------------
# Fixtures
# ----------------------------

## Drops a resolved card into (col, owner) and remembers it in the play order.
func _board(card_id: String, owner: int, col: int = LEFT) -> int:
	var card := _state.new_card(card_id, owner, CardState.Location.BOARD)
	_state.place_card(card.instance_id, col, owner)
	card.is_resolved = true
	_state.play_order.append(card.instance_id)
	return card.instance_id


## Puts a card into the owner's hand without touching the deck.
func _hand(card_id: String, owner: int) -> int:
	var card := _state.new_card(card_id, owner, CardState.Location.DECK)
	_state.add_to_hand(owner, card.instance_id)
	return card.instance_id


## The aura power modifier currently on a card.
func _aura_power(id: int) -> int:
	return _state.card(id).aura_power_modifier


## The aura cost modifier currently on a card.
func _aura_cost(id: int) -> int:
	return _state.card(id).aura_cost_modifier


## The first emitted event of that type, or null.
func _first_event(type: Variant) -> Variant:
	for event: Dictionary in _log:
		if event["type"] == type:
			return event
	return null


## The ids of every emitted event of that type.
func _event_ids(type: Variant) -> Array:
	var out: Array = []
	for event: Dictionary in _log:
		if event["type"] == type:
			out.append(int(event["instance_id"]))
	return out


# ----------------------------
# Azir
# ----------------------------

func test_azir_aura_buffs_other_ascended_allies_in_every_lane() -> void:
	var azir := _board("Azir2", 0, LEFT)
	var ally_left := _board("Nasus1", 0, LEFT)
	var ally_mid := _board("Renekton1", 0, MID)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(azir), 0, "Azir does not buff itself")
	assert_eq(_aura_power(ally_left), 2, "+aura_power to an ally in Azir's lane")
	assert_eq(_aura_power(ally_mid), 2, "the aura reaches every lane, not just its own")


func test_azir_aura_skips_non_ascended_enemy_and_face_down_cards() -> void:
	_board("Azir2", 0, LEFT)
	var non_ascended := _board("Irelia1", 0, LEFT)
	var enemy := _board("Azir2", 1, LEFT)
	var hidden := _board("Nasus1", 0, MID)
	_state.card(hidden).is_resolved = false
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(non_ascended), 0, "a non-Ascended ally gets nothing")
	assert_eq(_aura_power(enemy), 0, "an enemy Ascended is never buffed")
	assert_eq(_aura_power(hidden), 0, "a face-down ally is not a valid target")


func test_azir3_buffs_with_the_same_amount_as_azir2() -> void:
	_board("Azir3", 0, LEFT)
	var ally := _board("Nasus2", 0, MID)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(ally), 2, "aura_power is 2 at every Azir level")


# ----------------------------
# Xerath
# ----------------------------

func test_xerath2_leaves_the_front_row_of_its_lane_alone() -> void:
	_board("Xerath2", 0, LEFT)
	var front_a := _board("Kennen1", 1, LEFT)  # slot 0
	var front_b := _board("Chip", 1, LEFT)     # slot 1
	var other_lane := _board("TheBeastBelow", 1, MID)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(front_a), 0, "slot 0 is front row")
	assert_eq(_aura_power(front_b), 0, "slot 1 is front row")
	assert_eq(_aura_power(other_lane), 0, "lv2 only debuffs its own lane")


func test_xerath2_debuffs_the_third_and_fourth_slot_of_its_lane() -> void:
	_board("Xerath2", 0, LEFT)
	_board("Kennen1", 1, LEFT)              # slot 0
	_board("Chip", 1, LEFT)                 # slot 1
	var third := _board("Megatusk", 1, LEFT)         # slot 2 = back row
	var fourth := _board("TheBeastBelow", 1, LEFT)   # slot 3 = back row
	MatchAuras.recalculate(_ctx)
	assert_eq(_state.card(third).slot, 2, "the third card really is in the back row")
	assert_eq(_aura_power(third), -1, "-aura_debuff")
	assert_eq(_aura_power(fourth), -1, "and so is the fourth")


func test_xerath3_debuffs_back_row_enemies_in_every_lane() -> void:
	_board("Xerath3", 0, LEFT)
	_board("Kennen1", 1, RIGHT)
	_board("Chip", 1, RIGHT)
	var back := _board("Megatusk", 1, RIGHT)
	var other_lane := _board("AbyssalEye", 1, MID)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(back), -1, "the back row of any lane is debuffed")
	assert_eq(_aura_power(other_lane), 0, "a front-row unit in the other lane stays clean")


func test_xerath_aura_ignores_unresolved_enemies() -> void:
	_board("Xerath3", 0, LEFT)
	_board("Kennen1", 1, LEFT)  # slot 0
	_board("Chip", 1, LEFT)     # slot 1
	var hidden := _board("Megatusk", 1, LEFT)
	_state.card(hidden).is_resolved = false
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(hidden), 0, "a face-down enemy is not a valid aura target")


# ----------------------------
# Irelia
# ----------------------------

func test_irelia2_buffs_own_one_cost_units_only() -> void:
	_board("Irelia2", 0, LEFT)
	var cheap := _board("Kennen1", 0, LEFT)             # cost 1
	var cheap_far := _board("Chip", 0, RIGHT)           # cost 1
	var pricey := _board("Megatusk", 0, LEFT)           # cost 3
	var enemy_cheap := _board("Blade", 1, LEFT)         # cost 1, enemy
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(cheap), 1, "+power_increase on a 1-cost ally")
	assert_eq(_aura_power(cheap_far), 1, "across lanes too")
	assert_eq(_aura_power(pricey), 0, "a 3-cost ally gets nothing")
	assert_eq(_aura_power(enemy_cheap), 0, "enemies are never buffed")


func test_irelia2_uses_the_base_cost_not_the_current_one() -> void:
	_board("Irelia2", 0, LEFT)
	var discounted := _board("Kennen1", 0, LEFT)  # base cost 1
	_ctx.ops.change_cost(discounted, -1)         # now costs 0
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(discounted), 1, "the old code reads Cost, not get_current_cost()")


# ----------------------------
# Blade
# ----------------------------

func test_a_lone_blade_buffes_nobody() -> void:
	var blade := _board("Blade", 0, LEFT)
	_board("Kennen1", 0, MID)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(blade), 0, "a Blade never buffs itself")


func test_blade_aura_buffs_other_own_blades_only() -> void:
	var blade := _board("Blade", 0, LEFT)
	var other := _board("Blade", 0, MID)
	var enemy_blade := _board("Blade", 1, LEFT)
	var not_a_blade := _board("Kennen1", 0, RIGHT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(blade), 1, "+aura_power from the other allied Blade")
	assert_eq(_aura_power(other), 1, "and the same in the other direction")
	assert_eq(_aura_power(enemy_blade), 0, "the opponent's Blades are untouched")
	assert_eq(_aura_power(not_a_blade), 0, "and neither are other followers")


func test_three_blades_each_gain_two() -> void:
	var a := _board("Blade", 0, LEFT)
	var b := _board("Blade", 0, MID)
	var c := _board("Blade", 0, RIGHT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(a), 2, "each Blade is buffed by the other two")
	assert_eq(_aura_power(b), 2)
	assert_eq(_aura_power(c), 2)


# ----------------------------
# Nautilus
# ----------------------------

func test_nautilus2_discounts_the_owners_sea_monsters_in_hand() -> void:
	_board("Nautilus2", 0, LEFT)
	var monster := _hand("Megatusk", 0)
	var plain := _hand("Chip", 0)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_cost(monster), -3, "-cost_reduction on a Sea Monster")
	assert_eq(_aura_cost(plain), 0, "a non Sea Monster hand card is untouched")
	assert_eq(_state.card(monster).get_current_cost(), 0, "3 - 3")


func test_nautilus2_discounts_both_players_sea_monsters() -> void:
	_board("Nautilus2", 0, LEFT)
	_board("Nautilus2", 1, RIGHT)
	var mine := _hand("Megatusk", 0)
	var theirs := _hand("TheBeastBelow", 1)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_cost(mine), -3, "player 0's own Nautilus discounts player 0's hand")
	assert_eq(_aura_cost(theirs), -3, "player 1's own Nautilus discounts player 1's hand")


func test_nautilus2_does_not_reach_the_other_players_hand() -> void:
	_board("Nautilus2", 0, LEFT)
	var theirs := _hand("TheBeastBelow", 1)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_cost(theirs), 0, "the aura is bound to its owner's hand")


func test_nautilus2_does_not_discount_sea_monsters_on_the_board() -> void:
	_board("Nautilus2", 0, LEFT)
	var on_board := _board("Megatusk", 0, LEFT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(on_board), 0, "the aura is a HAND cost discount only")
	assert_eq(_state.card(on_board).get_current_cost(), 3, "and it grants no power")


# ----------------------------
# Deep
# ----------------------------

func test_deep_aura_buffs_deep_units_of_a_deep_owner() -> void:
	_state.players[0].is_deep = true
	var monster := _board("Megatusk", 0, LEFT)
	var plain := _board("Chip", 0, LEFT)
	var enemy_monster := _board("TheBeastBelow", 1, LEFT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(monster), 3, "+3 for a Deep unit of a Deep player")
	assert_eq(_aura_power(plain), 0, "a unit without the Deep keyword gets nothing")
	assert_eq(_aura_power(enemy_monster), 0, "the other player is not Deep")


func test_deep_aura_reaches_every_lane() -> void:
	_state.players[1].is_deep = true
	var near := _board("SeaScarab", 1, LEFT)
	var far := _board("AbyssalEye", 1, RIGHT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(near), 3)
	assert_eq(_aura_power(far), 3, "the Deep aura is global, not lane-scoped")


func test_deep_aura_disappears_when_the_aura_goes_away() -> void:
	_state.players[0].is_deep = true
	var monster := _board("Megatusk", 0, LEFT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_state.card(monster).get_current_power(), 5, "2 base + 3 aura")

	_log.clear()
	_state.players[0].is_deep = false
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(monster), 0)
	assert_eq(_event_ids(MatchEvents.POWER_CHANGED), [monster], "the drop is published")
	assert_eq(int(_first_event(MatchEvents.POWER_CHANGED)["delta"]), -3)


# ----------------------------
# Emitting only real changes
# ----------------------------

func test_a_recalculation_that_changes_nothing_emits_nothing() -> void:
	var azir := _board("Azir2", 0, LEFT)
	var ally := _board("Nasus1", 0, LEFT)
	MatchAuras.recalculate(_ctx)
	assert_true(_log.size() > 0, "the first pass publishes the buffs it applied")
	assert_eq(_event_ids(MatchEvents.POWER_CHANGED), [ally])

	_log.clear()
	MatchAuras.recalculate(_ctx)
	assert_eq(_log, [], "a second identical recalculation is completely silent")
	assert_eq(_aura_power(azir), 0)
	assert_eq(_aura_power(ally), 2, "and the modifier is not stacked up again")


func test_removing_an_aura_source_drops_the_modifier_and_emits() -> void:
	var azir := _board("Azir2", 0, LEFT)
	var ally := _board("Nasus1", 0, LEFT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_state.card(ally).get_current_power(), 4, "2 base + 2 aura")

	_log.clear()
	_ctx.ops.kill(azir, 0)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(ally), 0, "the modifier is reset")
	assert_eq(_state.card(ally).get_current_power(), 2, "back to the base power")
	assert_eq(_event_ids(MatchEvents.POWER_CHANGED), [ally], "the drop is published")
	var event: Dictionary = _first_event(MatchEvents.POWER_CHANGED)
	assert_eq(int(event["delta"]), -2, "with the -2 delta")
	assert_eq(int(event["new_power"]), 2)


func test_hand_cost_changes_are_private_to_their_owner() -> void:
	_board("Nautilus2", 1, RIGHT)
	var monster := _hand("Megatusk", 1)
	MatchAuras.recalculate(_ctx)
	assert_eq(_event_ids(MatchEvents.COST_CHANGED), [monster])
	var cost_event: Variant = _first_event(MatchEvents.COST_CHANGED)
	assert_true(cost_event != null, "the hand discount was published")
	assert_eq(int(cost_event["private_to"]), 1, "only the owner may see their hand's new cost")
	assert_eq(MatchEvents.redact_for(cost_event, 0), null, "the opponent gets nothing at all")
	assert_ne(MatchEvents.redact_for(cost_event, 1), null, "the owner sees it")


func test_board_power_changes_are_not_private() -> void:
	_board("Azir2", 0, LEFT)
	var ally := _board("Nasus1", 0, LEFT)
	MatchAuras.recalculate(_ctx)
	var event: Variant = _first_event(MatchEvents.POWER_CHANGED)
	assert_eq(int(event["instance_id"]), ally)
	assert_false(event.has("private_to"), "a board card is public information")
	assert_ne(MatchEvents.redact_for(event, 1), null, "both players see a board power change")


func test_two_auras_on_one_card_are_announced_as_one_delta() -> void:
	# Two Azir lv2 on the same side: each buffs the other, so the ally gains +4 in one go.
	var azir_a := _board("Azir2", 0, LEFT)
	var azir_b := _board("Azir2", 0, MID)
	var ally := _board("Nasus1", 0, RIGHT)
	MatchAuras.recalculate(_ctx)
	assert_eq(_aura_power(ally), 4, "both Azirs buff the ally")
	assert_eq(_aura_power(azir_a), 2, "each Azir is buffed by the other one only")
	assert_eq(_aura_power(azir_b), 2)
	assert_eq(_event_ids(MatchEvents.POWER_CHANGED).size(), 3, "one event per changed card")
	assert_eq(int(_first_event(MatchEvents.POWER_CHANGED)["delta"]), 2, "events follow the play order")