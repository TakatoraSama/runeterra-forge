extends "res://Tests/test_case.gd"

## MatchLevelUps — one test per champion condition, each one just below AND at the
## threshold, for both owners, plus the Sun Disc transform / restore and the
## return value of check_all().
##
## Each test builds a tiny MatchState by hand (cards dropped straight into zones /
## hands / decks) and calls MatchLevelUps.check_all() with the real
## MatchCardAbilities dispatcher as `ctx`.

const LEFT := 0
const MID := 1
const RIGHT := 2


var _state: MatchState
var _ctx: MatchCardAbilities


func before_each() -> void:
	_state = MatchState.new()
	_state.rng.seed = 13579246
	_ctx = MatchCardAbilities.install(MatchRules.new(_state))


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


## Records a summon tracker entry without putting a real card on the board, which is
## what the threshold counters actually read.
func _summoned_entry(card_id: String, owner: int, resolved: bool = true, from_hand: bool = false) -> void:
	_state.summoned.append({
		"card_id": card_id,
		"owner_player_id": owner,
		"was_played_from_hand": from_hand,
		"is_resolved": resolved,
		"instance_id": -1,
	})


## Records `count` summon tracker entries of the same card.
func _summon_x(count: int, card_id: String, owner: int, resolved: bool = true, from_hand: bool = false) -> void:
	for _i in count:
		_summoned_entry(card_id, owner, resolved, from_hand)


## Records a discard tracker entry.
func _discarded_entry(card_id: String, owner: int) -> void:
	_state.discarded.append({
		"card_id": card_id,
		"owner_player_id": owner,
		"discarded_by_card_id": "",
		"discarded_at_turn": _state.turn,
		"instance_id": -1,
	})


## Records `count` discard tracker entries.
func _discard_x(count: int, card_id: String, owner: int) -> void:
	for _i in count:
		_discarded_entry(card_id, owner)


## Records a drawn tracker entry.
func _drawn_entry(owner: int) -> void:
	_state.drawn.append({
		"card_id": "Chip",
		"owner_player_id": owner,
		"turn": _state.turn,
		"instance_id": -1,
	})


## Puts a card into the owner's deck.
func _deck(card_id: String, owner: int) -> int:
	var card := _state.new_card(card_id, owner, CardState.Location.DECK)
	_state.players[owner].deck.append(card.instance_id)
	return card.instance_id


## Kills an on-board card for `killer_player`; the real kill flow writes the tracker.
func _kill(victim: int, killer_player: int) -> void:
	_ctx.ops.kill(victim, killer_player)


## The card id a board instance is currently showing.
func _card_id(id: int) -> String:
	return _state.card(id).card_id


# ----------------------------
# Azir
# ----------------------------

func test_azir_waits_for_its_ally_threshold() -> void:
	var azir := _board("Azir1", 0)
	_summon_x(5, "Chip", 0)
	assert_false(MatchLevelUps.check_all(_ctx), "5 summoned allies is one short of 6")
	assert_eq(_card_id(azir), "Azir1")

	_summoned_entry("Chip", 0)
	assert_true(MatchLevelUps.check_all(_ctx), "the 6th ally does it")
	assert_eq(_card_id(azir), "Azir2")


func test_azir_counts_landmarks_but_not_itself_or_the_enemy() -> void:
	var azir := _board("Azir1", 0)
	_summon_x(4, "Chip", 0)
	_summoned_entry("BuriedSunDisc", 0)  # a landmark counts for Azir
	_summoned_entry("Azir1", 0)          # Azir herself does not
	_summoned_entry("Chip", 1)           # and the opponent's summons do not
	assert_false(MatchLevelUps.check_all(_ctx), "5 qualifying allies, one short")
	assert_eq(_card_id(azir), "Azir1")

	_summoned_entry("BuriedSunDisc", 0)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(azir), "Azir2")


func test_azir_levels_up_for_both_owners() -> void:
	var mine := _board("Azir1", 0)
	var theirs := _board("Azir1", 1, RIGHT)
	_summon_x(6, "Chip", 0)
	_summon_x(6, "Chip", 1)
	MatchLevelUps.check_all(_ctx)
	assert_eq(_card_id(mine), "Azir2", "player 0's Azir")
	assert_eq(_card_id(theirs), "Azir2", "and player 1's — there is no owner gating")


# ----------------------------
# Irelia
# ----------------------------

func test_irelia_ignores_landmarks_where_azir_counts_them() -> void:
	var irelia := _board("Irelia1", 0)
	_summon_x(7, "Chip", 0)
	_summoned_entry("BuriedSunDisc", 0)  # 7 followers + 1 landmark
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(irelia), "Irelia2", "only the 7 followers count")


func test_irelia_is_short_with_six_followers_and_two_landmarks() -> void:
	var irelia := _board("Irelia1", 0)
	_summon_x(6, "Chip", 0)
	_summon_x(2, "BuriedSunDisc", 0)
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(irelia), "Irelia1", "6 followers is below the 7 threshold")


func test_irelia_skips_itself() -> void:
	var irelia := _board("Irelia1", 0)
	_summon_x(7, "Irelia1", 0)
	assert_false(MatchLevelUps.check_all(_ctx), "Irelia's own summons do not level her up")
	assert_eq(_card_id(irelia), "Irelia1")


# ----------------------------
# Trundle
# ----------------------------

func test_trundle_needs_an_ice_pillar_played_from_hand() -> void:
	var trundle := _board("Trundle1", 0)
	_summoned_entry("IcePillar", 0, true, false)  # summoned, not played
	assert_false(MatchLevelUps.check_all(_ctx), "an Ice Pillar that was not played from hand does not count")
	assert_eq(_card_id(trundle), "Trundle1")

	_summoned_entry("IcePillar", 0, true, true)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(trundle), "Trundle2")


func test_trundle_levels_up_for_both_owners() -> void:
	var mine := _board("Trundle1", 0)
	var theirs := _board("Trundle1", 1, RIGHT)
	_summoned_entry("IcePillar", 0, true, true)
	_summoned_entry("IcePillar", 1, true, true)
	MatchLevelUps.check_all(_ctx)
	assert_eq(_card_id(mine), "Trundle2")
	assert_eq(_card_id(theirs), "Trundle2")


func test_trundle_lv2_has_no_create_card_ability() -> void:
	var trundle2 := _board("Trundle2", 0)
	_summoned_entry("IcePillar", 0, true, true)
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(trundle2), "Trundle2", "only a create_card Trundle qualifies")


# ----------------------------
# Xerath
# ----------------------------

func test_xerath_counts_allies_with_increased_power() -> void:
	var xerath := _board("Xerath1", 0)
	for _i in 3:
		_ctx.ops.change_power(_board("Chip", 0, MID), 1)
	assert_false(MatchLevelUps.check_all(_ctx), "3 buffed allies is below the threshold of 4")
	assert_eq(_card_id(xerath), "Xerath1")

	_ctx.ops.change_power(_board("Chip", 0, RIGHT), 1)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(xerath), "Xerath2")


func test_xerath_ignores_unbuffed_allies_spells_and_enemies() -> void:
	var xerath := _board("Xerath1", 0)
	_board("Chip", 0, MID)  # unbuffed ally: no count
	for _i in 3:
		_ctx.ops.change_power(_board("Chip", 0, MID), 1)
	_ctx.ops.change_power(_board("Chip", 1, MID), 1)   # an enemy buff never counts
	_board("BuriedSunDisc", 0, RIGHT)                 # a landmark is not an ally unit
	assert_false(MatchLevelUps.check_all(_ctx), "3 buffed allies is below the threshold of 4")
	assert_eq(_card_id(xerath), "Xerath1")

	_ctx.ops.change_power(_board("Chip", 0, RIGHT), 1)
	assert_true(MatchLevelUps.check_all(_ctx), "the 4th buffed ally does it")
	assert_eq(_card_id(xerath), "Xerath2")


func test_xerath_counts_the_aura_part_of_the_modifier() -> void:
	var xerath := _board("Xerath1", 0)
	_state.players[0].is_deep = true
	_ctx.ops.change_power(_board("Megatusk", 0, MID), 1)  # a Deep unit: +3 aura Power
	MatchAuras.recalculate(_ctx)
	for _i in 3:
		_ctx.ops.change_power(_board("Chip", 0, MID), 1)
	assert_true(MatchLevelUps.check_all(_ctx), "the aura Power counts as increased power")
	assert_eq(_card_id(xerath), "Xerath2")


# ----------------------------
# Nasus
# ----------------------------

func test_nasus_counts_only_its_owners_kills() -> void:
	var nasus := _board("Nasus1", 0)
	_kill(_board("Chip", 1, MID), 0)
	assert_false(MatchLevelUps.check_all(_ctx), "one kill is below the threshold of 2")

	_kill(_board("Chip", 1, RIGHT), 1)  # killed by the OTHER player: does not count
	_kill(_board("Chip", 0, RIGHT), 0)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(nasus), "Nasus2")


func test_nasus_levels_up_for_both_owners() -> void:
	var mine := _board("Nasus1", 0)
	var theirs := _board("Nasus1", 1, RIGHT)
	for _i in 2:
		_kill(_board("Chip", 0, MID), 0)
	for _i in 2:
		_kill(_board("Chip", 1, MID), 1)
	MatchLevelUps.check_all(_ctx)
	assert_eq(_card_id(mine), "Nasus2")
	assert_eq(_card_id(theirs), "Nasus2")


# ----------------------------
# Ahri
# ----------------------------

func test_ahri_counts_only_the_recalls_it_caused() -> void:
	var ahri := _board("Ahri1", 0)
	for _i in 3:
		_ctx.ops.recall(_board("Chip", 0, MID), 0, -1)  # a recall with no source is untracked
	_ctx.ops.recall(_board("Chip", 0, MID), 0, ahri)
	assert_false(MatchLevelUps.check_all(_ctx), "one Ahri recall is below the threshold of 3")
	assert_eq(_card_id(ahri), "Ahri1")

	_ctx.ops.recall(_board("Chip", 0, RIGHT), 0, ahri)
	_ctx.ops.recall(_board("Chip", 0, RIGHT), 0, ahri)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(ahri), "Ahri2")


func test_ahri_only_counts_its_own_instance_as_the_recaller() -> void:
	var ahri := _board("Ahri1", 0)
	var enemy_ahri := _board("Ahri1", 1, RIGHT)
	for _i in 3:
		_ctx.ops.recall(_board("Chip", 0, MID), 0, enemy_ahri)
	assert_false(MatchLevelUps.check_all(_ctx), "the opponent's Ahri recalling is not this Ahri's doing")
	assert_eq(_card_id(ahri), "Ahri1")


func test_ahri_recall_match_survives_its_own_level_up() -> void:
	# DEVIATION from the old code, which compared the recalled tracker's
	# recaller_card_id with Ahri's CURRENT card_id: an Ahri2 could therefore never
	# reach a second threshold. Here the recaller INSTANCE is what counts, so an
	# Ahri that has already levelled up still recognises its own recalls.
	var ahri := _board("Ahri2", 0)
	for _i in 3:
		_ctx.ops.recall(_board("Chip", 0, MID), 0, ahri)
	assert_false(MatchLevelUps.check_all(_ctx), "an lv2 Ahri has no LevelUpTo and stays where it is")
	assert_eq(_card_id(ahri), "Ahri2")
	assert_eq(_state.recalled.size(), 3, "and the recalls were tracked against this instance")


# ----------------------------
# Kennen
# ----------------------------

func test_kennen_needs_the_same_ally_three_times() -> void:
	var kennen := _board("Kennen1", 0)
	_summon_x(2, "Chip", 0)
	_summoned_entry("AbyssalEye", 0)
	assert_false(MatchLevelUps.check_all(_ctx), "2 + 1 is never 3 of the same card")
	assert_eq(_card_id(kennen), "Kennen1")

	_summoned_entry("Chip", 0)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(kennen), "Kennen2")


func test_kennen_only_counts_its_owners_summons() -> void:
	var kennen := _board("Kennen1", 0)
	_summon_x(3, "Chip", 1)
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(kennen), "Kennen1")


# ----------------------------
# Rumble
# ----------------------------

func test_rumble_counts_the_discards_of_both_owners() -> void:
	var mine := _board("Rumble1", 0)
	var theirs := _board("Rumble1", 1, RIGHT)
	_discard_x(3, "Chip", 0)
	_discard_x(3, "Chip", 1)
	assert_false(MatchLevelUps.check_all(_ctx), "3 is below the threshold of 4")
	assert_eq(_card_id(mine), "Rumble1")
	assert_eq(_card_id(theirs), "Rumble1")

	_discard_x(1, "Chip", 0)
	_discard_x(1, "Chip", 1)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(mine), "Rumble2")
	assert_eq(_card_id(theirs), "Rumble2")


# ----------------------------
# Sion
# ----------------------------

func test_sion_sums_discarded_and_resolved_summoned_power() -> void:
	var sion := _board("Sion1", 0)
	_discard_x(5, "IcePillar", 0)  # 5 Power each = 25
	_summon_x(2, "IcePillar", 0)  # + 10 = 35
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(sion), "Sion2")


func test_sion_stops_just_below_the_power_threshold() -> void:
	var sion := _board("Sion1", 0)
	_discard_x(5, "IcePillar", 0)  # 25
	_summon_x(1, "IcePillar", 0)  # 30
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(sion), "Sion1")


func test_sion_ignores_face_down_summons_and_the_other_owners_cards() -> void:
	var sion := _board("Sion1", 0)
	_summon_x(4, "IcePillar", 0, false)  # face-down in the resolve queue
	_summon_x(2, "IcePillar", 1)         # the opponent's
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(sion), "Sion1")


func test_sion_ignores_cards_without_a_power_stat() -> void:
	var sion := _board("Sion1", 0)
	_discard_x(8, "HexCoreUpgrade", 0)  # a spell, Power 0
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(sion), "Sion1")


# ----------------------------
# Draven
# ----------------------------

func test_draven_counts_the_axe_plays_he_saw() -> void:
	var draven := _board("Draven1", 0)
	_state.card(draven).axe_play_count = 1
	assert_false(MatchLevelUps.check_all(_ctx), "1 axe is below the threshold of 2")
	assert_eq(_card_id(draven), "Draven1")

	_state.card(draven).axe_play_count = 2
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(draven), "Draven2")


func test_draven_levels_up_for_both_owners() -> void:
	var mine := _board("Draven1", 0)
	var theirs := _board("Draven1", 1, RIGHT)
	_state.card(mine).axe_play_count = 2
	_state.card(theirs).axe_play_count = 2
	MatchLevelUps.check_all(_ctx)
	assert_eq(_card_id(mine), "Draven2")
	assert_eq(_card_id(theirs), "Draven2")


# ----------------------------
# Nautilus
# ----------------------------

func test_nautilus_waits_for_its_owner_to_go_deep() -> void:
	var nautilus := _board("Nautilus1", 0)
	assert_false(MatchLevelUps.check_all(_ctx), "not Deep yet")
	assert_eq(_card_id(nautilus), "Nautilus1")

	_state.players[0].is_deep = true
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(nautilus), "Nautilus2")


func test_nautilus_only_levels_the_deep_players_own_copy() -> void:
	var mine := _board("Nautilus1", 0)
	var theirs := _board("Nautilus1", 1, RIGHT)
	_state.players[1].is_deep = true
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(mine), "Nautilus1", "player 0 is not Deep")
	assert_eq(_card_id(theirs), "Nautilus2")


# ----------------------------
# Janna
# ----------------------------

func test_janna_counts_the_cards_her_owner_drew() -> void:
	var janna := _board("Janna1", 0)
	for _i in 11:
		_drawn_entry(0)
	_drawn_entry(1)  # the opponent's draws do not count
	assert_false(MatchLevelUps.check_all(_ctx), "11 is below the threshold of 12")
	assert_eq(_card_id(janna), "Janna1")

	_drawn_entry(0)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(janna), "Janna2")


func test_janna_counts_only_its_owners_draws() -> void:
	var janna := _board("Janna1", 0)
	for _i in 20:
		_drawn_entry(1)
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(janna), "Janna1")


# ----------------------------
# Renekton / power thresholds
# ----------------------------

func test_renekton_levels_up_at_its_power_threshold() -> void:
	var renekton := _board("Renekton1", 0)
	_ctx.ops.change_power(renekton, 3)
	assert_false(MatchLevelUps.check_all(_ctx), "3 is below power_threshold 4")
	assert_eq(_card_id(renekton), "Renekton1")

	_ctx.ops.change_power(renekton, 1)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(renekton), "Renekton2")


func test_power_threshold_ignores_aura_power() -> void:
	var renekton := _board("Renekton1", 0)
	_state.players[0].is_deep = true
	var megatusk := _board("Megatusk", 0, MID)  # +3 aura Power from being Deep
	MatchAuras.recalculate(_ctx)
	assert_eq(_state.card(megatusk).aura_power_modifier, 3, "the Deep aura is up")
	assert_false(MatchLevelUps.check_all(_ctx), "aura Power does not count towards power_threshold")
	assert_eq(_card_id(renekton), "Renekton1")


func test_a_card_without_a_power_threshold_never_levels_on_power() -> void:
	var kennen := _board("Kennen1", 0)
	_ctx.ops.change_power(kennen, 99)
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(kennen), "Kennen1")


# ----------------------------
# Sun Disc
# ----------------------------

func test_sun_disc_transforms_draws_and_pushes_the_ascended_to_lv3() -> void:
	var disc := _board("BuriedSunDisc", 0)
	var azir2 := _board("Azir2", 0, MID)
	var nasus2 := _board("Nasus2", 0, RIGHT)
	_deck("Renekton1", 0)  # an Ascended champion that is not beheld
	_deck("Azir1", 0)       # Azir is beheld, so this copy stays in the deck
	_deck("Chip", 0)        # not Ascended at all

	assert_true(MatchLevelUps.check_all(_ctx), "the disc transforms")
	assert_eq(_card_id(disc), "RestoredSunDisc")
	assert_eq(_state.players[0].hand.size(), 1, "exactly one un-beheld Ascended card was drawn")
	assert_eq(_card_id(_state.players[0].hand[0]), "Renekton1")
	assert_eq(_state.players[0].deck.size(), 2, "the beheld Azir and the non-Ascended Chip stay")
	assert_eq(_card_id(azir2), "Azir3", "lv2 Ascended champions jump to lv3")
	assert_eq(_card_id(nasus2), "Nasus3")


func test_sun_disc_draws_only_one_copy_per_ascended_name() -> void:
	_board("BuriedSunDisc", 0)
	_board("Azir2", 0, MID)
	_board("Nasus2", 0, RIGHT)
	_deck("Azir2", 0)
	_deck("Azir2", 0)  # a second copy of a champion already on the board
	MatchLevelUps.check_all(_ctx)
	assert_eq(_state.players[0].hand.size(), 0, "Azir is beheld, so neither copy is drawn")


func test_sun_disc_needs_two_lv2_ascended_champions() -> void:
	var disc := _board("BuriedSunDisc", 0)
	_board("Azir2", 0, MID)
	_board("Azir3", 0, RIGHT)   # lv3 does not count
	_board("Irelia2", 0, LEFT)  # not Ascended
	assert_false(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(disc), "BuriedSunDisc")


func test_sun_disc_only_reacts_to_its_own_owners_ascended() -> void:
	var disc := _board("BuriedSunDisc", 0)
	_board("Azir2", 1, MID)
	_board("Nasus2", 1, RIGHT)
	assert_false(MatchLevelUps.check_all(_ctx), "the enemy Ascended do not restore this player's disc")
	assert_eq(_card_id(disc), "BuriedSunDisc")


func test_sun_disc_only_promotes_its_own_owners_ascended_champions() -> void:
	var disc := _board("BuriedSunDisc", 0)
	var enemy_ascended := _board("Azir2", 1, MID)
	_board("Nasus2", 0, RIGHT)
	_board("Renekton2", 0, LEFT)
	MatchLevelUps.check_all(_ctx)
	assert_eq(_card_id(disc), "RestoredSunDisc")
	assert_eq(_card_id(enemy_ascended), "Azir2", "the opponent's lv2 Ascended stays lv2")


func test_ascended_champion_jumps_to_lv3_when_the_disc_is_already_restored() -> void:
	_board("RestoredSunDisc", 0)
	var azir := _board("Azir1", 0, MID)
	_summon_x(6, "Chip", 0)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(azir), "Azir3", "lv1 -> lv2 and straight on to lv3")


func test_ascended_champion_stays_at_lv2_while_the_disc_is_buried() -> void:
	var azir := _board("Azir1", 0, MID)
	_board("BuriedSunDisc", 0)
	_summon_x(6, "Chip", 0)
	assert_true(MatchLevelUps.check_all(_ctx))
	assert_eq(_card_id(azir), "Azir2", "a buried disc does not upgrade anything")


# ----------------------------
# check_all's return value
# ----------------------------

func test_check_all_reports_whether_anything_changed() -> void:
	assert_false(MatchLevelUps.check_all(_ctx), "an empty board changes nothing")

	_board("Chip", 0)
	assert_false(MatchLevelUps.check_all(_ctx), "a plain follower has no level-up condition")

	_summon_x(6, "Chip", 0)
	var azir := _board("Azir1", 0, MID)
	assert_true(MatchLevelUps.check_all(_ctx), "Azir levelled up")
	assert_eq(_card_id(azir), "Azir2")

	assert_false(MatchLevelUps.check_all(_ctx), "and running it again settles down again")


func test_cards_off_the_board_or_face_down_never_level_up() -> void:
	var azir := _board("Azir1", 0)
	_ctx.ops.recall(azir, 0, -1)  # back into the hand, off the board
	assert_eq(_state.card(azir).location, CardState.Location.HAND)
	_summon_x(6, "Chip", 0)
	assert_false(MatchLevelUps.check_all(_ctx), "a card in hand does not level up")
	assert_eq(_card_id(azir), "Azir1")

	var hidden := _board("Azir1", 0, MID)
	_state.card(hidden).is_resolved = false
	assert_false(MatchLevelUps.check_all(_ctx), "a face-down card does not level up either")
	assert_eq(_card_id(hidden), "Azir1")