## Unit tests for {Round Start}, {Round End} and {Game End}.
##
## The module is driven directly with a MatchCardAbilities as ctx over a tiny state,
## so each gate and each handler is asserted in isolation. The rules' own wiring
## (stun skip, phase order) is asserted end-to-end in test_scenarios.gd.
extends "res://Tests/test_case.gd"


# ----------------------------
# Fixture
# ----------------------------

## Builds a minimal match with the real dispatcher installed, without starting it.
func _fixture(seed_value: int = 7) -> Dictionary:
	var state := MatchSetup.new_match([], [], seed_value)
	var rules := MatchRules.new(state)
	var hooks := MatchCardAbilities.install(rules)
	return {"state": state, "rules": rules, "ctx": hooks, "ops": rules.ops}


## Puts `card_id` on the board for `owner` in `col`, resolved (the state abilities see).
func _on_board(ctx: Dictionary, card_id: String, owner: int, col: int) -> int:
	var state: MatchState = ctx["state"]
	var card := state.new_card(card_id, owner, CardState.Location.BOARD)
	state.place_card(card.instance_id, col, owner)
	card.is_resolved = true
	state.play_order.append(card.instance_id)
	return card.instance_id


## Puts `card_id` into `owner`'s hand.
func _in_hand(ctx: Dictionary, card_id: String, owner: int) -> int:
	var state: MatchState = ctx["state"]
	var card := state.new_card(card_id, owner, CardState.Location.HAND)
	state.add_to_hand(owner, card.instance_id)
	return card.instance_id


## Puts `card_id` at the BOTTOM of `owner`'s deck (next draw).
func _on_deck(ctx: Dictionary, card_id: String, owner: int) -> int:
	var state: MatchState = ctx["state"]
	var card := state.new_card(card_id, owner, CardState.Location.DECK)
	state.players[owner].deck.append(card.instance_id)
	return card.instance_id


func _power(ctx: Dictionary, id: int) -> int:
	return (ctx["state"] as MatchState).card(id).get_current_power()


func _card_id(ctx: Dictionary, id: int) -> String:
	return (ctx["state"] as MatchState).card(id).card_id


# ----------------------------
# Trigger gates
# ----------------------------

## {Round Start} needs the marker ANYWHERE in the Skill text (old code used `in`).
func test_round_start_gate_accepts_the_marker_anywhere() -> void:
	var ctx := _fixture()
	var renekton: int = _on_board(ctx, "Renekton3", 0, 0)  # Skill has {Round Start} ... {Game End}
	var fired: bool = PhaseAbilities.on_round_start(ctx["ctx"], renekton)
	assert_true(fired, "a Skill that contains {Round Start} fires")
	# Renekton3 win_power is 3 and player 0 is winning 0 vs 0? No: 10 > 0, so it buffs.
	assert_eq(_power(ctx, renekton), 13, "Renekton3 gained its lv3 win_power")


## A card with no {Round Start} in its Skill never fires.
func test_round_start_gate_rejects_cards_without_the_marker() -> void:
	var ctx := _fixture()
	var xerath: int = _on_board(ctx, "Xerath1", 0, 0)
	assert_false(PhaseAbilities.on_round_start(ctx["ctx"], xerath),
		"Xerath1 has only a {Play} ability")
	assert_eq(_power(ctx, xerath), 3, "nothing changed")


## {Round End} needs the marker at the START of the Skill text (old code used
## begins_with). A card whose Skill merely mentions {Round End} later does NOT fire.
func test_round_end_gate_requires_the_marker_at_the_front() -> void:
	var ctx := _fixture()
	var galio: int = _on_board(ctx, "Galio1", 0, 0)
	# Galio1's Skill is "I cost 1 less ... [br] {Round End}: ..." — the marker is present
	# but not at the front, so the gate must reject it.
	assert_true(str(CardDatabase.CARDS["Galio1"]["Skill"]).contains("{Round End}"),
		"fixture card really does contain the marker later in the text")
	assert_false(PhaseAbilities.on_round_end(ctx["ctx"], galio),
		"a Skill that only mentions {Round End} later does not fire")

	var nasus: int = _on_board(ctx, "Nasus1", 0, 0)
	assert_true(PhaseAbilities.on_round_end(ctx["ctx"], nasus),
		"a Skill that BEGINS with {Round End} fires")


## {Game End} needs the marker anywhere in the Skill text.
func test_game_end_gate_accepts_the_marker_anywhere() -> void:
	var ctx := _fixture()
	var trundle: int = _on_board(ctx, "Trundle2", 0, 0)
	# Nothing qualifies for Trundle's behold buff, but the pass must reach it and
	# leave the card untouched rather than erroring.
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_card_id(ctx, trundle), "Trundle2", "a lone Trundle2 just does nothing")


# ----------------------------
# Round Start: Renekton conditional buff
# ----------------------------

## Winning the lane (own resolved power > enemy resolved power) grants win_power.
func test_conditional_buff_fires_only_while_winning_the_lane() -> void:
	var ctx := _fixture()
	var renekton: int = _on_board(ctx, "Renekton1", 0, 0)
	_on_board(ctx, "Chip", 1, 0)  # enemy Power 1, Renekton1 has 4
	PhaseAbilities.on_round_start(ctx["ctx"], renekton)
	assert_eq(_power(ctx, renekton), 6, "Renekton1 won 4 vs 1 and gained its win_power 2")

	# Now the enemy out-scales him: no further buff.
	_on_board(ctx, "IcePillar", 1, 0)  # Power 5, enemy lane total is now 6
	PhaseAbilities.on_round_start(ctx["ctx"], renekton)
	assert_eq(_power(ctx, renekton), 6, "losing 6 vs 6 grants nothing")


## Face-down (unresolved) cards never count towards the lane comparison.
func test_conditional_buff_ignores_unresolved_lane_cards() -> void:
	var ctx := _fixture()
	var renekton: int = _on_board(ctx, "Renekton1", 0, 0)
	var hidden: int = _on_board(ctx, "IcePillar", 1, 0)
	(ctx["state"] as MatchState).card(hidden).is_resolved = false  # face down: Power 5 hidden
	PhaseAbilities.on_round_start(ctx["ctx"], renekton)
	assert_eq(_power(ctx, renekton), 6, "the hidden IcePillar does not beat Renekton's 4")


# ----------------------------
# Round End: Nasus kill + buff
# ----------------------------

## Nasus kills the weakest other ally here and always gains kill_power.
func test_kill_ally_buff_kills_the_weakest_and_always_buffers() -> void:
	var ctx := _fixture()
	var nasus: int = _on_board(ctx, "Nasus1", 0, 0)
	var weakest: int = _on_board(ctx, "Chip", 0, 0)  # Power 1
	_on_board(ctx, "IcePillar", 0, 0)  # Power 5, survives
	PhaseAbilities.on_round_end(ctx["ctx"], nasus)
	assert_eq((ctx["state"] as MatchState).card(weakest).location, CardState.Location.GONE,
		"the weakest ally died")
	assert_eq(_power(ctx, nasus), 4, "Nasus1 (2) gained kill_power 2")
	assert_eq(_card_id(ctx, nasus), "Nasus1", "one kill is below kill_threshold 2, no level-up")


## Ties go to the FIRST card in zone order (the old code used a strict "<" compare).
func test_kill_ally_buff_breaks_power_ties_by_zone_order() -> void:
	var ctx := _fixture()
	var nasus: int = _on_board(ctx, "Nasus1", 0, 0)
	var first: int = _on_board(ctx, "Chip", 0, 0)
	var second: int = _on_board(ctx, "Chip", 0, 0)
	PhaseAbilities.on_round_end(ctx["ctx"], nasus)
	assert_eq((ctx["state"] as MatchState).card(first).location, CardState.Location.GONE,
		"the first of two equal-power allies dies")
	assert_eq((ctx["state"] as MatchState).card(second).location, CardState.Location.BOARD,
		"the second one lives")


## With no other unit in the lane there is nothing to kill — and no buff either,
## exactly like the old early return.
func test_kill_ally_buff_does_nothing_when_alone() -> void:
	var ctx := _fixture()
	var nasus: int = _on_board(ctx, "Nasus1", 0, 0)
	PhaseAbilities.on_round_end(ctx["ctx"], nasus)
	assert_eq(_power(ctx, nasus), 2, "Nasus alone neither kills nor buffs")
	assert_eq((ctx["state"] as MatchState).killed.size(), 0, "nothing died")


## A prevented death still grants the buff: the card text joins them with "and".
func test_kill_ally_buff_still_buffers_when_the_death_is_prevented() -> void:
	var ctx := _fixture()
	var nasus: int = _on_board(ctx, "Nasus1", 0, 0)
	var trynd: int = _on_board(ctx, "Tryndamere1", 0, 0)  # levelup_on_death
	PhaseAbilities.on_round_end(ctx["ctx"], nasus)
	assert_eq((ctx["state"] as MatchState).card(trynd).location, CardState.Location.BOARD,
		"Tryndamere levelled up instead of dying")
	assert_eq(_card_id(ctx, trynd), "Tryndamere2", "the death-prevention level-up fired")
	assert_eq(_power(ctx, nasus), 4, "Nasus still gained kill_power")
	assert_eq((ctx["state"] as MatchState).killed.size(), 0, "a prevented death is not a kill")


## Nasus never kills itself and never reaches into another lane.
func test_kill_ally_buff_stays_inside_its_own_lane() -> void:
	var ctx := _fixture()
	var nasus: int = _on_board(ctx, "Nasus1", 0, 0)
	var other_lane: int = _on_board(ctx, "Chip", 0, 1)
	PhaseAbilities.on_round_end(ctx["ctx"], nasus)
	assert_eq((ctx["state"] as MatchState).card(other_lane).location, CardState.Location.BOARD,
		"a unit in another lane is untouched")
	assert_eq(_power(ctx, nasus), 2, "with no target in the lane, no buff")


# ----------------------------
# Round End: Megatusk
# ----------------------------

## Megatusk buffs its lane only while its owner is Deep.
func test_megatusk_round_end_needs_its_owner_to_be_deep() -> void:
	var ctx := _fixture()
	var megatusk: int = _on_board(ctx, "Megatusk", 0, 0)
	var ally: int = _on_board(ctx, "Chip", 0, 0)
	PhaseAbilities.on_round_end(ctx["ctx"], megatusk)
	assert_eq(_power(ctx, megatusk), 2, "not Deep: Megatusk itself is unchanged")
	assert_eq(_power(ctx, ally), 1, "not Deep: the ally is unchanged")

	(ctx["state"] as MatchState).players[0].is_deep = true
	PhaseAbilities.on_round_end(ctx["ctx"], megatusk)
	assert_eq(_power(ctx, megatusk), 3, "Deep: Megatusk gained power_bonus 1")
	assert_eq(_power(ctx, ally), 2, "Deep: the ally gained power_bonus 1")


## Megatusk reaches every RESOLVED allied unit in its lane, both rows, and skips
## face-down cards and the enemy lane.
func test_megatusk_round_end_buffs_every_resolved_ally_in_the_lane() -> void:
	var ctx := _fixture()
	(ctx["state"] as MatchState).players[0].is_deep = true
	var megatusk: int = _on_board(ctx, "Megatusk", 0, 0)
	var back_row: int = _on_board(ctx, "TheBeastBelow", 0, 0)
	var hidden: int = _on_board(ctx, "Chip", 0, 0)
	(ctx["state"] as MatchState).card(hidden).is_resolved = false
	var enemy: int = _on_board(ctx, "Chip", 1, 0)
	PhaseAbilities.on_round_end(ctx["ctx"], megatusk)
	assert_eq(_power(ctx, back_row), 6, "the back-row ally gained power_bonus 1")
	assert_eq(_power(ctx, hidden), 1, "a face-down ally is skipped")
	assert_eq(_power(ctx, enemy), 1, "the enemy lane is untouched")


# ----------------------------
# Round End: Terror of the Tides
# ----------------------------

## Terror debuffs every resolved enemy unit in its lane and nothing else.
func test_terror_round_end_debuffs_the_enemy_lane() -> void:
	var ctx := _fixture()
	var terror: int = _on_board(ctx, "TerrorOfTheTides", 0, 0)
	var front: int = _on_board(ctx, "IcePillar", 1, 0)
	var hidden: int = _on_board(ctx, "Chip", 1, 0)
	(ctx["state"] as MatchState).card(hidden).is_resolved = false
	var ally: int = _on_board(ctx, "Chip", 0, 0)
	var other_lane: int = _on_board(ctx, "Chip", 1, 2)
	PhaseAbilities.on_round_end(ctx["ctx"], terror)
	assert_eq(_power(ctx, front), 4, "the resolved front-row enemy lost power_reduction 1")
	assert_eq(_power(ctx, hidden), 1, "the face-down enemy is skipped")
	assert_eq(_power(ctx, ally), 1, "Terror's own ally is untouched")
	assert_eq(_power(ctx, other_lane), 1, "an enemy in another lane is untouched")


# ----------------------------
# Game End: Trundle / Renekton / Xerath / Nasus
# ----------------------------

## Trundle lv2 gains behold_power for every OTHER beheld Champion/Follower whose
## BASE Cost is mana_threshold or more. The threshold is read off the base Cost, not
## the current one, and Trundle never counts himself.
func test_trundle_game_end_counts_beheld_units_over_the_threshold() -> void:
	var ctx := _fixture()
	var trundle: int = _on_board(ctx, "Trundle2", 0, 0)  # Power 4, threshold 5, +2 each
	_in_hand(ctx, "IcePillar", 0)  # Cost 5 in HAND, beheld
	_on_board(ctx, "AbyssalEye", 0, 1)  # Cost 5 on BOARD, beheld
	_in_hand(ctx, "Ahri1", 0)  # Cost 1, too cheap
	_on_board(ctx, "Chip", 1, 0)  # the OPPONENT's unit, not beheld by player 0
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, trundle), 8, "2 qualifying units x behold_power 2")


## Trundle does not count himself even though Trundle2 is a Champion.
func test_trundle_game_end_excludes_itself() -> void:
	var ctx := _fixture()
	var trundle: int = _on_board(ctx, "Trundle2", 0, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, trundle), 4, "Trundle alone beheld nobody else")


## Renekton lv3 takes enemy_debuff off ONE random resolved enemy in its lane.
func test_renekton_game_end_debuffs_one_enemy_in_its_lane() -> void:
	var ctx := _fixture()
	var renekton: int = _on_board(ctx, "Renekton3", 0, 0)
	var first: int = _on_board(ctx, "Chip", 1, 0)
	var second: int = _on_board(ctx, "Chip", 1, 0)
	var other_lane: int = _on_board(ctx, "Chip", 1, 2)
	var hidden: int = _on_board(ctx, "Chip", 1, 0)
	(ctx["state"] as MatchState).card(hidden).is_resolved = false
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, first) + _power(ctx, second), -1, "exactly one of the two lost 3")
	assert_eq(_power(ctx, other_lane), 1, "another lane is untouched")
	assert_eq(_power(ctx, hidden), 1, "a face-down enemy is not a valid target")


## Nasus lv3 kills one random resolved enemy in its lane with STRICTLY less Power.
func test_nasus_game_end_kills_a_strictly_weaker_enemy() -> void:
	var ctx := _fixture()
	_on_board(ctx, "Nasus3", 0, 0)  # Power 10
	var weak: int = _on_board(ctx, "Chip", 1, 0)  # Power 1
	# A second enemy that is NOT weaker, so only one of the two is a legal target.
	var strong: int = _on_board(ctx, "Chip", 1, 0)
	(ctx["state"] as MatchState).card(strong).power_modifier = 11  # 1 + 11 = 12 > 10
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(weak).location, CardState.Location.GONE,
		"the strictly weaker enemy died")
	assert_eq((ctx["state"] as MatchState).card(strong).location, CardState.Location.BOARD,
		"the stronger enemy was never a legal target")


## An enemy exactly as strong as Nasus is NOT a valid target.
func test_nasus_game_end_ignores_an_equal_power_enemy() -> void:
	var ctx := _fixture()
	_on_board(ctx, "Nasus3", 0, 0)
	# Give the enemy exactly Nasus's own Power via a permanent modifier.
	var twin: int = _on_board(ctx, "Chip", 1, 0)
	(ctx["state"] as MatchState).card(twin).power_modifier = 9  # 1 + 9 = 10 = Nasus's 10
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(twin).location, CardState.Location.BOARD,
		"equal power is not 'strictly less', so nothing dies")



# ----------------------------
# Game End: the Azir lv3 double fire
# ----------------------------

## Every resolved on-board Azir lv3 makes its owner's other Ascended {Game End}
## cards fire a SECOND time — so each of them fires exactly twice in total.
func test_azir_lv3_makes_ascended_game_end_cards_fire_twice() -> void:
	var ctx := _fixture()
	var azir: int = _on_board(ctx, "Azir3", 0, 0)
	# Renekton3 is Ascended with a {Game End}; each fire takes 3 off a random enemy.
	var renekton: int = _on_board(ctx, "Renekton3", 0, 0)
	var first: int = _on_board(ctx, "Chip", 1, 0)
	var second: int = _on_board(ctx, "Chip", 1, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	# The two Chips start at 1 + 1 = 2 and lose 3 each time Renekton fires, so two
	# fires land on -4 (a single fire would be -1).
	assert_eq(_power(ctx, first) + _power(ctx, second), -4, "Renekton fired twice")
	assert_eq(_card_id(ctx, azir), "Azir3", "Azir itself never re-fires its own {Game End}")
	assert_eq(_card_id(ctx, renekton), "Renekton3", "no level-up from a {Game End} buff")


## Without an Azir lv3 the Ascended {Game End} cards fire exactly once.
func test_without_azir_lv3_ascended_game_end_fires_once() -> void:
	var ctx := _fixture()
	_on_board(ctx, "Azir2", 0, 0)  # level 2, not 3
	_on_board(ctx, "Renekton3", 0, 0)
	var first: int = _on_board(ctx, "Chip", 1, 0)
	var second: int = _on_board(ctx, "Chip", 1, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, first) + _power(ctx, second), -1, "one fire debuffs exactly one Chip")


## The bonus fire is per OWNER: Azir lv3 never re-fires the opponent's Ascended cards.
func test_azir_lv3_does_not_refire_the_opponents_cards() -> void:
	var ctx := _fixture()
	_on_board(ctx, "Azir3", 0, 0)
	_on_board(ctx, "Renekton3", 1, 0)  # opponent's
	var chip: int = _on_board(ctx, "Chip", 0, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, chip), -2, "the opponent's Renekton fired once, not twice")


## An Azir lv3 that is FACE DOWN does not trigger the second pass.
func test_an_unresolved_azir_lv3_does_not_double_fire() -> void:
	var ctx := _fixture()
	var azir: int = _on_board(ctx, "Azir3", 0, 0)
	(ctx["state"] as MatchState).card(azir).is_resolved = false
	_on_board(ctx, "Renekton3", 0, 0)
	var first: int = _on_board(ctx, "Chip", 1, 0)
	var second: int = _on_board(ctx, "Chip", 1, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, first) + _power(ctx, second), -1, "only the normal pass ran")


## A card killed during the first pass is not re-fired by an Azir lv3.
func test_a_card_killed_in_pass_one_is_not_refired() -> void:
	var ctx := _fixture()
	_on_board(ctx, "Azir3", 0, 0)
	_on_board(ctx, "Nasus3", 0, 0)  # kills an enemy in pass one
	var victim: int = _on_board(ctx, "Chip", 1, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(victim).location, CardState.Location.GONE,
		"Nasus killed the Chip in pass one")
	# The Chip is GONE, so it is off the board and pass two skips it — the observable
	# invariant is simply that the kill is counted once.
	assert_eq((ctx["state"] as MatchState).killed.size(), 1, "the kill happened exactly once")


## Renekton lv3 reaches BOTH players' boards: the host runs every effect.
func test_renekton_game_end_applies_to_the_opponents_board_too() -> void:
	var ctx := _fixture()
	_on_board(ctx, "Renekton3", 1, 0)
	var enemy: int = _on_board(ctx, "Chip", 0, 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, enemy), -2, "player 1's Renekton debuffed player 0's Chip")


## Xerath lv3 copies the Power of the FRONT ROW only (slot index 0 and 1).
func test_xerath_game_end_copies_the_front_row_only() -> void:
	var ctx := _fixture()
	var xerath: int = _on_board(ctx, "Xerath3", 0, 0)  # Power 7
	_on_board(ctx, "IcePillar", 1, 0)  # slot 0, Power 5
	_on_board(ctx, "Chip", 1, 0)  # slot 1, Power 1
	_on_board(ctx, "TheBeastBelow", 1, 0)  # slot 2 (back row), Power 5 — ignored
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq(_power(ctx, xerath), 13, "Xerath gained 5 + 1 from the front row")

## Sion Returned in hand is summoned for BOTH players, into the lane where its owner
## is losing with the most power.
func test_sion_summons_from_hand_for_both_players() -> void:
	var ctx := _fixture()
	var sion0: int = _in_hand(ctx, "SionReturned", 0)
	var sion1: int = _in_hand(ctx, "SionReturned", 1)
	# Player 0 is losing in column 1 only; player 1 is losing in column 2 only.
	# The two summons run sequentially, so player 1's margin has to survive player 0's
	# Sion (Power 10) landing in column 1 first — hence 3 x IcePillar = 15 over there.
	_on_board(ctx, "Chip", 0, 1)  # p0 ally Power 1 in col 1
	_on_board(ctx, "IcePillar", 1, 1)  # p1 ally Power 5 in col 1
	_on_board(ctx, "IcePillar", 1, 1)  # p1 ally Power 10 in col 1 -> p0 loses col 1
	_on_board(ctx, "IcePillar", 1, 1)  # p1 ally Power 15 in col 1
	_on_board(ctx, "IcePillar", 0, 2)  # p0 ally Power 5 in col 2 -> p1 loses col 2
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(sion0).col, 1, "player 0's Sion went to col 1")
	assert_eq((ctx["state"] as MatchState).card(sion1).col, 2, "player 1's Sion went to col 2")
	for sion: int in [sion0, sion1]:
		assert_eq((ctx["state"] as MatchState).card(sion).location, CardState.Location.BOARD,
			"Sion left the hand")
		assert_true((ctx["state"] as MatchState).card(sion).is_resolved, "Sion landed resolved")


## Sion picks the losing lane with the HIGHEST own power, not the emptiest one.
func test_sion_prefers_the_losing_lane_with_the_most_power() -> void:
	var ctx := _fixture()
	var sion: int = _in_hand(ctx, "SionReturned", 0)
	_on_board(ctx, "Chip", 0, 0)  # ally power 1
	_on_board(ctx, "TheBeastBelow", 0, 0)  # ally power 5 -> lane total 6
	_on_board(ctx, "Chip", 1, 0)  # enemy power 1 -> p0 wins col 0
	_on_board(ctx, "Chip", 1, 1)  # enemy power 1 -> p0 loses col 1 with ally power 0
	_on_board(ctx, "Chip", 1, 2)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(sion).col, 1,
		"the only losing lane is col 1 (col 0 is won and col 2 is empty/tied)")


## Not losing anywhere: fall back to the lane with the LOWEST own power.
func test_sion_falls_back_to_the_emptiest_lane_when_winning_everywhere() -> void:
	var ctx := _fixture()
	var sion: int = _in_hand(ctx, "SionReturned", 0)
	_on_board(ctx, "IcePillar", 0, 2)  # ally power 5 in col 2
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(sion).col, 0,
		"col 0 is empty, so it is the lowest-power lane")


## A full target zone means the card simply stays in hand.
func test_sion_stays_in_hand_when_its_lane_is_full() -> void:
	var ctx := _fixture()
	var sion: int = _in_hand(ctx, "SionReturned", 0)
	# Player 0 is losing in column 0 (4 vs 5) and that zone is the one it would pick.
	for _i in MatchState.SLOTS_PER_ZONE:
		_on_board(ctx, "Chip", 0, 0)  # p0 ally Power 4 in col 0
	_on_board(ctx, "IcePillar", 1, 0)  # p1 ally Power 5 in col 0
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(sion).location, CardState.Location.HAND,
		"no free slot: the card is not summoned and not lost")


## Sion2 (last_breath_create on board, game_end_summon_from_hand in hand) uses its
## HandAbilityType, not its AbilityType.
func test_sion_lv2_uses_its_hand_ability_type() -> void:
	var ctx := _fixture()
	var sion: int = _in_hand(ctx, "Sion2", 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(sion).location, CardState.Location.BOARD,
		"Sion2 in hand summons through HandAbilityType")


## A hand card WITHOUT {Game End} in its Skill never fires.
func test_a_hand_card_without_the_game_end_marker_stays_put() -> void:
	var ctx := _fixture()
	var trundle: int = _in_hand(ctx, "Trundle2", 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(trundle).location, CardState.Location.HAND,
		"Trundle2's Skill has no {Game End}, so nothing happens")


## The hand snapshot is taken per player, so summoning one Sion cannot consume the other.
func test_two_sions_in_one_hand_both_summon() -> void:
	var ctx := _fixture()
	var a: int = _in_hand(ctx, "SionReturned", 0)
	var b: int = _in_hand(ctx, "SionReturned", 0)
	PhaseAbilities.on_game_end_phase(ctx["ctx"])
	assert_eq((ctx["state"] as MatchState).card(a).location, CardState.Location.BOARD,
		"the first Sion summoned")
	assert_eq((ctx["state"] as MatchState).card(b).location, CardState.Location.BOARD,
		"the second Sion was in the snapshot too and also summoned")