extends "res://Tests/test_case.gd"

## PlayAbilities — every {Play} type, {Game Start}, swap-arrive, level-up, on-discard,
## Last Breath, the Janna draw passive and the death-prevention hooks.
##
## Each test builds a tiny MatchState by hand (cards dropped straight into zones / hands /
## decks) and calls PlayAbilities with a real MatchCardAbilities as `ctx`.

const COL := 0
const MID := 1


var _state: MatchState
var _ctx: MatchCardAbilities


func before_each() -> void:
	_state = MatchState.new()
	_state.rng.seed = 987654321
	_ctx = MatchCardAbilities.install(MatchRules.new(_state))


# ----------------------------
# Fixtures
# ----------------------------

## Drops a resolved card into (col, owner) and remembers it in the play order.
func _board(card_id: String, owner: int, col: int = COL, resolved: bool = true) -> int:
	var card := _state.new_card(card_id, owner, CardState.Location.BOARD)
	_state.place_card(card.instance_id, col, owner)
	card.is_resolved = resolved
	_state.play_order.append(card.instance_id)
	return card.instance_id


## Puts a card into the owner's hand. add_to_hand inserts at index 0, so the card added
## last ends up as hand[0] (the newest / leftmost one).
func _hand(card_id: String, owner: int) -> int:
	var card := _state.new_card(card_id, owner, CardState.Location.DECK)
	_state.add_to_hand(owner, card.instance_id)
	return card.instance_id


func _deck(card_id: String, owner: int) -> int:
	var card := _state.new_card(card_id, owner, CardState.Location.DECK)
	_state.players[owner].deck.append(card.instance_id)
	return card.instance_id


func _hand_ids(owner: int) -> Array:
	var out: Array = []
	for id in _state.players[owner].hand:
		out.append(int(id))
	return out


func _card_ids_in_hand(owner: int) -> Array:
	var out: Array = []
	for id in _state.players[owner].hand:
		out.append(str(_state.card(int(id)).card_id))
	return out


func _discarded_ids(owner: int) -> Array:
	var out: Array = []
	for entry in _state.discarded:
		if int(entry.get("owner_player_id", -1)) == owner:
			out.append(str(entry.get("card_id", "")))
	return out


func _triggered(card_id: String, owner: int = 0) -> int:
	return _board(card_id, owner, COL, true)


# ----------------------------
# Play types
# ----------------------------

func test_summon_copy_puts_a_resolved_copy_in_the_same_zone() -> void:
	var kennen := _triggered("Kennen1")
	PlayAbilities.run_play_type(_ctx, kennen, "summon_copy")
	assert_eq(_state.zone_cards(COL, 0).size(), 2, "a second card sits in the lane")
	var copy := _state.card(_state.zone_cards(COL, 0)[1])
	assert_eq(copy.card_id, "Kennen1", "same card id")
	assert_eq(copy.is_resolved, true, "the copy is face-up")
	assert_eq(_state.summoned.size(), 1, "summoned tracker records it")
	assert_eq(_state.created.size(), 1, "created tracker records it")
	assert_eq(str(_state.created[0]["creator_card_id"]), "Kennen1", "the original created it")
	assert_eq(int(_state.created[0]["creator_player_id"]), 0, "creator is the original owner")


func test_buff_allies_and_damage_enemies_are_placeholders() -> void:
	var kennen := _triggered("Kennen1")
	var blade := _board("Blade", 0, COL, true)
	var power_before: int = _state.card(blade).get_current_power()
	PlayAbilities.run_play_type(_ctx, kennen, "buff_allies")
	PlayAbilities.run_play_type(_ctx, kennen, "damage_enemies")
	assert_eq(_state.card(blade).get_current_power(), power_before, "nothing happens")
	assert_eq(_state.card(kennen).is_resolved, true, "the caster stays on the board")


func test_create_card_creates_the_bracketed_card_in_hand() -> void:
	var trundle := _triggered("Trundle1")
	PlayAbilities.on_play(_ctx, trundle)
	assert_eq(_card_ids_in_hand(0), ["IcePillar"], "Trundle creates an Ice Pillar")


func test_create_card_ignores_skill_without_a_bracket() -> void:
	var spike := _triggered("Chip")
	PlayAbilities.run_play_type(_ctx, spike, "create_card")
	assert_eq(_hand_ids(0), [], "nothing created")


func test_mana_ramp_queues_bonus_mana() -> void:
	var pillar := _triggered("IcePillar")
	PlayAbilities.on_play(_ctx, pillar)
	assert_eq(_state.players[0].pending_bonus_mana, 5, "+5 mana next turn")


func test_drain_power_takes_the_total_actually_drained() -> void:
	var xerath := _triggered("Xerath1")
	_board("Blade", 0, COL, true)  # own ally, power 0
	_board("Kennen1", 1, COL, true)  # enemy, power 1
	_board("BuriedSunDisc", 0, COL, true)  # not a unit, ignored
	PlayAbilities.on_play(_ctx, xerath)
	assert_eq(_state.card(xerath).power_modifier, 4, "Xerath drained 2 from each unit")
	assert_eq(_state.card(xerath).get_current_power(), 7, "3 base + 4 drained")


func test_drain_power_only_drains_the_opposing_lane() -> void:
	var xerath := _triggered("Xerath1")
	var other_lane := _board("Blade", 1, MID, true)
	PlayAbilities.on_play(_ctx, xerath)
	assert_eq(_state.card(xerath).power_modifier, 0, "no units in this lane")
	assert_eq(_state.card(other_lane).get_current_power(), 0, "the other lane is untouched")



func test_stun_enemy_stuns_a_random_enemy_in_the_lane() -> void:
	var kennen := _triggered("Kennen1")
	var enemy := _board("Chip", 1, COL, true)
	_board("Blade", 0, COL, true)  # an ally is never a target
	PlayAbilities.on_play(_ctx, kennen)
	assert_true(_ctx.ops.is_stunned(enemy), "the enemy is stunned")
	assert_eq(_state.card(enemy).power_modifier, 0, "Kennen lv1 takes no Power")


func test_stun_enemy_kennen2_also_removes_power() -> void:
	var kennen := _triggered("Kennen2")
	var enemy := _board("Tryndamere1", 1, COL, true)
	PlayAbilities.on_play(_ctx, kennen)
	assert_true(_ctx.ops.is_stunned(enemy), "stunned")
	assert_eq(_state.card(enemy).power_modifier, -1, "-1 Power")


func test_stun_enemy_skips_face_down_targets() -> void:
	var kennen := _triggered("Kennen1")
	_board("Chip", 1, COL, false)
	PlayAbilities.on_play(_ctx, kennen)
	assert_eq(_state.stuns.size(), 0, "an unresolved card is not a valid target")


func test_recall_allies_same_lane_recalls_resolved_allies() -> void:
	var navori := _triggered("NavoriConspirator")
	var blade := _board("Blade", 0, COL, true)
	var pillar := _board("IcePillar", 0, COL, true)
	_board("Chip", 0, COL, false)  # face-down
	_board("BuriedSunDisc", 0, COL, true)  # landmark
	_board("Blade", 1, COL, true)  # enemy
	PlayAbilities.on_play(_ctx, navori)
	assert_eq(_hand_ids(0), [pillar, blade], "both resolved allies recalled, newest first")


func test_recall_cost_allies_uses_the_base_cost_across_all_lanes() -> void:
	var monk := _triggered("SolitaryMonk")
	var cheap_a := _board("Kennen1", 0, COL, true)  # cost 1
	var cheap_b := _board("Lucian1", 0, MID, true)  # cost 1
	var pricey := _board("Megatusk", 0, 2, true)  # cost 3
	var face_down := _board("Chip", 0, 2, false)  # cost 1, unresolved
	PlayAbilities.on_play(_ctx, monk)
	assert_eq(_hand_ids(0), [cheap_b, cheap_a], "both 1-cost allies recalled")
	assert_eq(_state.players[0].hand.has(pricey), false, "3-cost ally stays on the board")
	assert_eq(_state.players[0].hand.has(face_down), false, "unresolved ally stays")


func test_discard_by_cost_bracket_takes_one_per_bracket_and_buffs() -> void:
	var rumble := _triggered("Rumble1")
	var low := _hand("Kennen1", 0)  # cost 1
	var mid := _hand("Megatusk", 0)  # cost 3
	var high := _hand("IcePillar", 0)  # cost 5
	PlayAbilities.on_play(_ctx, rumble)
	assert_eq(_state.discarded.size(), 3, "three cards discarded")
	assert_eq(_discarded_ids(0).size(), 3, "all three")
	assert_eq(_state.players[0].hand.size(), 0, "the hand is empty")
	assert_eq(_state.card(rumble).power_modifier, 6, "+2 per discard")
	for gone in [low, mid, high]:
		assert_eq(_state.card(gone).location, CardState.Location.GONE, "gone")


func test_discard_by_cost_bracket_skips_empty_brackets() -> void:
	var rumble := _triggered("Rumble1")
	_hand("Kennen1", 0)
	_hand("Chip", 0)
	PlayAbilities.on_play(_ctx, rumble)
	assert_eq(_state.discarded.size(), 1, "only the cheap bracket had a card")
	assert_eq(_state.card(rumble).power_modifier, 2, "+2")


func test_create_card_if_not_in_hand_creates_once() -> void:
	var draven := _triggered("Draven1")
	PlayAbilities.on_play(_ctx, draven)
	assert_eq(_card_ids_in_hand(0), ["SpinningAxe"], "one axe created")
	PlayAbilities.on_play(_ctx, draven)
	assert_eq(_card_ids_in_hand(0), ["SpinningAxe"], "still only one")


func test_create_multiple_cards_creates_the_configured_count() -> void:
	var draven := _triggered("Draven2")
	PlayAbilities.on_play(_ctx, draven)
	assert_eq(_card_ids_in_hand(0), ["SpinningAxe", "SpinningAxe"], "two axes")


func test_spinning_axe_discards_the_newest_card_and_buffs_draven() -> void:
	var axe := _board("SpinningAxe", 0, MatchState.SPELL_COL, true)
	var draven := _triggered("Draven1")
	_hand("Kennen1", 0)
	var newest := _hand("Chip", 0)  # hand[0], the one the axe discards
	PlayAbilities.on_play(_ctx, axe)
	assert_eq(_discarded_ids(0), ["Chip"], "hand[0] was discarded")
	assert_eq(_state.card(newest).location, CardState.Location.GONE, "gone")
	assert_eq(_state.card(draven).power_modifier, 1, "Draven +1 Power")
	assert_eq(_state.card(draven).axe_play_count, 1, "the axe play is counted")


func test_spinning_axe_only_counts_axes_for_draven_of_that_owner() -> void:
	var axe := _board("SpinningAxe", 0, MatchState.SPELL_COL, true)
	var mine := _triggered("Draven1", 0)
	var theirs := _triggered("Draven1", 1)
	var blade := _board("Blade", 0, COL, true)
	_hand("Chip", 0)
	PlayAbilities.on_play(_ctx, axe)
	assert_eq(_state.card(mine).axe_play_count, 1, "owner Draven counts")
	assert_eq(_state.card(theirs).axe_play_count, 0, "the opponent's Draven does not")
	assert_eq(_state.card(blade).axe_play_count, 0, "only Draven counts")
	assert_eq(_state.card(mine).power_modifier, 1, "only the owner's Draven is buffed")


func test_spinning_axe_with_an_empty_hand_only_counts_the_axe() -> void:
	var axe := _board("SpinningAxe", 0, MatchState.SPELL_COL, true)
	var draven := _triggered("Draven1")
	PlayAbilities.on_play(_ctx, axe)
	assert_eq(_state.discarded.size(), 0, "nothing discarded")
	assert_eq(_state.card(draven).power_modifier, 0, "no buff")
	assert_eq(_state.card(draven).axe_play_count, 1, "the axe still counts")


func test_janna_updraft_draw_reduces_shuffles_and_draws() -> void:
	var janna := _triggered("Janna1")
	_deck("Chip", 0)
	_deck("Kennen1", 0)
	_deck("Megatusk", 0)
	# Added oldest first: the hand ends up newest-first, so the updrafted cards are
	# the last two.
	var oldest := _hand("Kennen1", 0)
	var second_oldest := _hand("Megatusk", 0)
	var newest := _hand("AbyssalEye", 0)
	var middle := _hand("DevourerOfTheDepths", 0)
	var second_newest := _hand("Chip", 0)
	PlayAbilities.on_play(_ctx, janna)
	assert_eq(_state.card(oldest).cost_modifier, -1, "oldest card costs 1 less")
	assert_eq(_state.card(second_oldest).cost_modifier, -1, "second oldest costs 1 less")
	assert_eq(_state.card(newest).cost_modifier, 0, "the newest card is untouched")
	assert_eq(_state.card(middle).cost_modifier, 0, "the middle card is untouched")
	assert_eq(_state.card(second_newest).cost_modifier, 0, "the second newest is untouched")
	assert_eq(_state.players[0].deck.size(), 3, "2 shuffled in, 2 drawn back out")
	assert_eq(_state.players[0].hand.size(), 5, "5 held, 2 updrafted, 2 drawn")


func test_janna_updraft_draw_draws_nothing_with_an_empty_hand() -> void:
	var janna := _triggered("Janna1")
	PlayAbilities.on_play(_ctx, janna)
	assert_eq(_state.players[0].hand.size(), 0, "no cards, no draw")


func test_janna_draw_cost_reduce_as_a_play_ability_draws() -> void:
	var janna := _triggered("Janna2")
	_deck("Chip", 0)
	_deck("Kennen1", 0)
	PlayAbilities.on_play(_ctx, janna)
	assert_eq(_state.players[0].hand.size(), 1, "drew draw_threshold cards")


func test_sea_scarab_draws_and_discards_a_non_champion() -> void:
	var scarab := _triggered("SeaScarab")
	_deck("Chip", 0)
	_deck("Kennen1", 0)
	PlayAbilities.on_play(_ctx, scarab)
	assert_eq(_discarded_ids(0), ["Chip"], "the non-champion was drawn and discarded")
	assert_eq(_state.players[0].hand.size(), 0, "the hand is empty again")
	assert_eq(_state.players[0].deck.size(), 1, "only the champion is left")


func test_sea_scarab_does_nothing_with_only_champions_in_the_deck() -> void:
	var scarab := _triggered("SeaScarab")
	_deck("Kennen1", 0)
	PlayAbilities.on_play(_ctx, scarab)
	assert_eq(_state.discarded.size(), 0, "nothing drawn, nothing discarded")
	assert_eq(_state.players[0].deck.size(), 1, "the deck is untouched")


func test_abyssal_eye_draws_the_configured_count() -> void:
	var eye := _triggered("AbyssalEye")
	_deck("Chip", 0)
	_deck("Kennen1", 0)
	PlayAbilities.on_play(_ctx, eye)
	assert_eq(_state.players[0].hand.size(), 1, "drew draw_count cards")


func test_devourer_only_fires_when_the_owner_is_deep() -> void:
	var devourer := _triggered("DevourerOfTheDepths")
	var enemy := _board("Chip", 1, COL, true)
	PlayAbilities.on_play(_ctx, devourer)
	assert_eq(_state.card(enemy).location, CardState.Location.BOARD, "not Deep, nothing happens")
	_state.players[0].is_deep = true
	PlayAbilities.on_play(_ctx, devourer)
	assert_eq(_state.card(enemy).location, CardState.Location.GONE, "Deep, the weaker enemy dies")
	assert_eq(_state.killed.size(), 1, "kill tracker")
	assert_eq(int(_state.killed[0]["killer_player_id"]), 0, "killed by the owner")


func test_devourer_only_targets_weaker_enemies() -> void:
	var devourer := _triggered("DevourerOfTheDepths")
	_state.players[0].is_deep = true
	var stronger := _board("TerrorOfTheTides", 1, COL, true)  # power 7
	var weaker := _board("Chip", 1, COL, true)  # power 1
	PlayAbilities.on_play(_ctx, devourer)
	assert_eq(_state.card(weaker).location, CardState.Location.GONE, "the weaker enemy dies")
	assert_eq(_state.card(stronger).location, CardState.Location.BOARD, "the stronger one lives")


# ----------------------------
# Game Start
# ----------------------------

func test_game_start_summons_the_sun_disc_in_the_mid_lane() -> void:
	_deck("Azir1", 0)
	PlayAbilities.on_game_start(_ctx, "Azir1", 0)
	assert_eq(_state.zone_cards(MID, 0).size(), 1, "one card in the mid lane")
	var disc := _state.card(_state.zone_cards(MID, 0)[0])
	assert_eq(disc.card_id, "BuriedSunDisc", "it is the Sun Disc")
	assert_eq(disc.is_resolved, true, "face-up")
	assert_eq(_state.zone_cards(COL, 0).size(), 0, "not in the side lane")
	assert_eq(_state.created.size(), 1, "created tracker")
	assert_eq(str(_state.created[0]["creator_card_id"]), "Azir1", "Azir created it")


func test_game_start_summons_the_sun_disc_on_the_owners_side() -> void:
	_deck("Azir1", 1)
	PlayAbilities.on_game_start(_ctx, "Azir1", 1)
	assert_eq(_state.zone_cards(MID, 1).size(), 1, "player 1's own side")
	assert_eq(_state.zone_cards(MID, 0).size(), 0, "player 0 is untouched")


# ----------------------------
# Swap-arrive
# ----------------------------

func test_swap_arrive_recall_recalls_the_weakest_ally() -> void:
	var ahri := _board("Ahri1", 0, MID, true)
	var weak := _board("Blade", 0, MID, true)  # power 0
	var strong := _board("Tryndamere1", 0, MID, true)  # power 3
	_board("BuriedSunDisc", 0, MID, true)  # a landmark is not a unit
	PlayAbilities.on_swap_arrive(_ctx, ahri, COL, MID)
	assert_eq(_hand_ids(0), [weak], "the weakest ally was recalled")
	assert_eq(_state.players[0].hand.has(strong), false, "the strongest ally stays")
	assert_eq(_state.players[0].hand.has(ahri), false, "Ahri does not recall herself")


func test_swap_arrive_recall_breaks_ties_on_the_smaller_card_id() -> void:
	var ahri := _board("Ahri1", 0, MID, true)
	var blade := _board("Blade", 0, MID, true)  # power 0
	var chip := _board("Chip", 0, MID, true)  # power 1
	_state.card(blade).power_modifier = 1  # both now sit at 1 Power
	assert_eq(_state.card(blade).get_current_power(), 1, "tied")
	PlayAbilities.on_swap_arrive(_ctx, ahri, COL, MID)
	assert_eq(_hand_ids(0), [blade], "Blade sorts before Chip")
	assert_eq(_state.players[0].hand.has(chip), false, "Chip stays")


func test_swap_arrive_recall_ahri2_reduces_the_recalled_cost() -> void:
	var ahri := _board("Ahri2", 0, MID, true)
	var blade := _board("Blade", 0, MID, true)
	PlayAbilities.on_swap_arrive(_ctx, ahri, COL, MID)
	assert_eq(_state.card(blade).location, CardState.Location.HAND, "recalled")
	assert_eq(_state.card(blade).cost_modifier, -1, "1 cost less")


func test_swap_arrive_summon_blade_uses_the_from_column() -> void:
	var irelia := _board("Irelia1", 0, MID, true)
	_board("Chip", 0, COL, true)
	PlayAbilities.on_swap_arrive(_ctx, irelia, COL, MID)
	var blades: Array = []
	for id in _state.zone_cards(COL, 0):
		blades.append(str(_state.card(int(id)).card_id))
	assert_eq(blades, ["Chip", "Blade"], "the Blade lands in the lane Irelia left")
	assert_eq(_state.zone_cards(MID, 0).size(), 1, "nothing lands where she arrived")


# ----------------------------
# Level-up abilities
# ----------------------------

func test_level_up_create_from_discards_creates_one_card_per_discard() -> void:
	var rumble := _triggered("Rumble2")
	_state.discarded.append({"card_id": "Janna1", "owner_player_id": 0})
	_state.discarded.append({"card_id": "NavoriConspirator", "owner_player_id": 0})
	_state.discarded.append({"card_id": "TerrorOfTheTides", "owner_player_id": 1})
	PlayAbilities.on_level_up(_ctx, rumble)
	assert_eq(_state.players[0].hand.size(), 2, "one card per own discard")
	for hand_id in _state.players[0].hand:
		var card := _state.card(int(hand_id))
		assert_eq(card.cost_modifier, -1, "created at cost -1")
		assert_true(card.has_keyword("Augment"), "granted Augment")
		assert_true(bool(CardDatabase.CARDS[card.card_id].get("Collectible", false)), "a collectible")


func test_level_up_create_from_discards_without_discards_creates_nothing() -> void:
	var rumble := _triggered("Rumble2")
	_state.discarded.append({"card_id": "Chip", "owner_player_id": 1})
	PlayAbilities.on_level_up(_ctx, rumble)
	assert_eq(_state.players[0].hand.size(), 0, "only the opponent discarded")


func test_nautilus_levelup_creates_distinct_expensive_sea_monsters() -> void:
	var nautilus := _triggered("Nautilus2")
	PlayAbilities.on_level_up(_ctx, nautilus)
	assert_eq(_state.players[0].hand.size(), 3, "created_count cards")
	var seen: Array = []
	for hand_id in _state.players[0].hand:
		var data: Dictionary = CardDatabase.CARDS[_state.card(int(hand_id)).card_id]
		assert_eq(str(data.get("SubType", "")), "Sea Monster", "a Sea Monster")
		assert_true(int(data.get("Cost", 0)) >= 3, "cost >= created_cost")
		assert_false(seen.has(str(data.get("Name", ""))), "no duplicate")
		seen.append(str(data.get("Name", "")))


# ----------------------------
# On discard / Last Breath
# ----------------------------

func test_on_discard_buffs_a_hand_card_and_creates_a_sion_copy() -> void:
	var sion := _hand("Sion1", 0)
	var ally := _hand("Kennen1", 0)
	_ctx.ops.discard(sion, -1)
	assert_eq(_state.card(sion).location, CardState.Location.GONE, "Sion left the hand")
	assert_eq(_state.card(ally).power_modifier, 2, "the remaining ally got +2 Power")
	assert_eq(_card_ids_in_hand(0), ["Sion1", "Kennen1"], "a Sion copy was created")


func test_on_discard_with_an_empty_hand_still_creates_the_copy() -> void:
	var sion := _hand("Sion1", 0)
	_ctx.ops.discard(sion, -1)
	assert_eq(_card_ids_in_hand(0), ["Sion1"], "a Sion copy was created")


func test_on_discard_ignores_other_cards() -> void:
	var kennen := _hand("Kennen1", 0)
	var ally := _hand("Chip", 0)
	_ctx.ops.discard(kennen, -1)
	assert_eq(_state.card(ally).power_modifier, 0, "no buff")
	assert_eq(_state.players[0].hand.size(), 1, "no copy created")


func test_last_breath_creates_sion_returned_in_hand() -> void:
	var sion := _triggered("Sion2")
	assert_true(_ctx.ops.kill(sion, 1, -1), "the kill went through")
	assert_eq(_card_ids_in_hand(0), ["SionReturned"], "Sion Returned was created")
	assert_eq(_state.card(sion).location, CardState.Location.GONE, "Sion is gone")


func test_last_breath_ignores_other_cards() -> void:
	var chip := _triggered("Chip")
	assert_true(_ctx.ops.kill(chip, 1, -1), "the kill went through")
	assert_eq(_state.players[0].hand.size(), 0, "nothing created")


# ----------------------------
# Draw passive
# ----------------------------

func test_janna2_passive_stacks_with_two_copies() -> void:
	_board("Janna2", 0, COL, true)
	_board("Janna2", 0, MID, true)
	_deck("Chip", 0)
	_deck("Kennen1", 0)
	var next_id: int = _ctx.ops.draw(0)
	assert_true(next_id > 0, "a card was drawn")
	assert_eq(_state.card(next_id).card_id, "Chip", "the top card of the deck")
	assert_eq(_state.card(next_id).cost_modifier, -2, "two Janna2 each give -1")
	assert_eq(_state.players[0].deck.size(), 1, "the deck shrank by one")
	assert_eq(_state.players[0].hand.size(), 1, "the card is in hand")


func test_janna2_passive_only_counts_resolved_cards() -> void:
	_board("Janna2", 0, COL, true)
	_board("Janna2", 0, MID, false)  # face-down
	_deck("Megatusk", 0)
	var next_id: int = _ctx.ops.draw(0)
	assert_eq(_state.card(next_id).cost_modifier, -1, "only the resolved Janna2 counts")


func test_janna2_passive_ignores_the_opponent() -> void:
	_board("Janna2", 1, COL, true)
	_deck("Megatusk", 0)
	var next_id: int = _ctx.ops.draw(0)
	assert_eq(_state.card(next_id).cost_modifier, 0, "the opponent's Janna2 does nothing")


# ----------------------------
# Death prevention
# ----------------------------

func test_tryndamere1_levels_up_instead_of_dying() -> void:
	var tryndamere := _triggered("Tryndamere1")
	assert_true(PlayAbilities.prevents_death(_ctx, tryndamere), "saves itself")
	assert_false(_ctx.ops.kill(tryndamere, 1, -1), "the kill is refused")
	assert_eq(_state.card(tryndamere).location, CardState.Location.BOARD, "still on the board")
	assert_eq(_state.card(tryndamere).card_id, "Tryndamere2", "it levelled up")


func test_tryndamere2_survives_with_more_power() -> void:
	var tryndamere := _triggered("Tryndamere2")
	assert_true(PlayAbilities.prevents_death(_ctx, tryndamere), "saves itself")
	assert_false(_ctx.ops.kill(tryndamere, 1, -1), "the kill is refused")
	assert_eq(_state.card(tryndamere).location, CardState.Location.BOARD, "still on the board")
	assert_eq(_state.card(tryndamere).card_id, "Tryndamere2", "no level-up")
	assert_eq(_state.card(tryndamere).power_modifier, 2, "+survive_power instead")


func test_ordinary_units_do_not_prevent_death() -> void:
	var chip := _triggered("Chip")
	assert_false(PlayAbilities.prevents_death(_ctx, chip), "no death prevention")
	assert_true(_ctx.ops.kill(chip, 1, -1), "the kill goes through")
	assert_eq(_state.card(chip).location, CardState.Location.GONE, "gone")