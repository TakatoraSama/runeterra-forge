## Multi-step card stories driven through the real rules engine with M3 abilities.
##
## Every scenario builds a tiny match, installs `MatchCardAbilities`, plays cards
## through `MatchRules.submit()` and then lets the round loop run, so the assertions
## cover the whole chain: intent -> resolve -> ability -> aura -> level-up -> settle.
extends "res://Tests/test_case.gd"

const SEED := 21
const LANES: Array[String] = ["HexcoreFoundry", "OrnnsForge", "RockfallPath"]


# ----------------------------
# Fixture
# ----------------------------

## A started match with the M3 abilities installed and fixed lanes, so the shuffle
## and the reveals never get in the way of a scenario.
func _match(deck0: Array, deck1: Array) -> Dictionary:
	var state := MatchSetup.new_match(deck0, deck1, SEED)
	var rules := MatchRules.new(state)
	var hooks := MatchCardAbilities.install(rules)
	rules.start_match(LANES)
	return {"state": state, "rules": rules, "ctx": hooks, "ops": rules.ops}


## Deck filler that can never fire a phase ability (Chip has no Skill marker) and
## that neither bot ever levels up.
func _filler(count: int) -> Array[String]:
	var deck: Array[String] = []
	for _i in count:
		deck.append("Chip")
	return deck


## Clears a hand and hands the player exactly these cards instead.
func _give_hand(ctx: Dictionary, player: int, card_ids: Array) -> Array[int]:
	var state: MatchState = ctx["state"]
	for hand_id in state.players[player].hand.duplicate():
		state.remove_from_hand(player, hand_id)
		state.card(hand_id).location = CardState.Location.GONE
	var ids: Array[int] = []
	for card_id: String in card_ids:
		ids.append((ctx["ops"] as MatchOps).create_in_hand(card_id, player))
	return ids


## Puts a card straight onto the board, resolved — the state an ability sees.
func _put_on_board(ctx: Dictionary, card_id: String, owner: int, col: int) -> int:
	var state: MatchState = ctx["state"]
	var card := state.new_card(card_id, owner, CardState.Location.BOARD)
	state.place_card(card.instance_id, col, owner)
	card.is_resolved = true
	state.play_order.append(card.instance_id)
	return card.instance_id


## Gives the player enough mana to play anything this turn. The engine recomputes
## `base_max_mana` from the turn number at every turn start, so this has to be called
## again before every play a scenario makes.
func _rich(ctx: Dictionary, player: int, mana: int = 20) -> void:
	var ps: PlayerState = (ctx["state"] as MatchState).players[player]
	ps.base_max_mana = mana
	ps.bonus_max_mana = 0
	ps.current_mana = mana


## Ends both players' turns, which runs the whole round:
## SWAP_LANE -> RESOLVE ({Play} + after_change) -> ROUND_END -> next turn.
func _end_round(ctx: Dictionary) -> Array:
	var rules: MatchRules = ctx["rules"]
	var log: Array = []
	log += rules.submit(0, MatchIntents.end_turn())
	log += rules.submit(1, MatchIntents.end_turn())
	return log


## Empties a player's deck and refills it with exactly `card_ids`, in order.
func _set_deck(ctx: Dictionary, player: int, card_ids: Array) -> void:
	var state: MatchState = ctx["state"]
	for deck_id in state.players[player].deck:
		state.card(deck_id).location = CardState.Location.GONE
	state.players[player].deck.clear()
	for card_id: String in card_ids:
		var card := state.new_card(card_id, player, CardState.Location.DECK)
		state.players[player].deck.append(card.instance_id)


## Empties a player's hand, retiring the cards it held.
func _clear_hand(ctx: Dictionary, player: int) -> void:
	var state: MatchState = ctx["state"]
	for hand_id in state.players[player].hand.duplicate():
		state.remove_from_hand(player, hand_id)
		state.card(hand_id).location = CardState.Location.GONE


## Plays `id` for `player` into `col` and ends the round.
func _play_and_resolve(ctx: Dictionary, player: int, id: int, col: int) -> Array:
	_rich(ctx, player)
	var log: Array = []
	log += (ctx["rules"] as MatchRules).submit(player, MatchIntents.play_card(id, col))
	log += _end_round(ctx)
	return log


func _card_id(ctx: Dictionary, id: int) -> String:
	return (ctx["state"] as MatchState).card(id).card_id


func _power(ctx: Dictionary, id: int) -> int:
	return (ctx["state"] as MatchState).card(id).get_current_power()


## The instance of `card_id` in `player`'s hand, or -1.
func _in_hand(ctx: Dictionary, player: int, card_id: String) -> int:
	for hand_id: int in (ctx["state"] as MatchState).players[player].hand:
		if (ctx["state"] as MatchState).card(hand_id).card_id == card_id:
			return hand_id
	return -1


## How many events of `type` in `log` carry `key` == `value`.
func _count_events(log: Array, type: Variant, key: String, value: Variant) -> int:
	var count: int = 0
	for event: Dictionary in log:
		if event.get("type", &"") != type:
			continue
		if event.get(key, null) == value:
			count += 1
	return count


# ----------------------------
# Rumble
# ----------------------------

## Rumble lv1 discards one card per cost bracket and gains +2 Power for each. Three
## discards is still under discard_threshold 4, so it stays lv1.
func test_rumble_discards_one_card_per_cost_bracket() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var hand: Array[int] = _give_hand(ctx, 0, ["Rumble1", "Ahri1", "Xerath1", "IcePillar"])
	var rumble: int = hand[0]
	_play_and_resolve(ctx, 0, rumble, 0)
	assert_eq((ctx["state"] as MatchState).discarded.size(), 3,
		"one card from each of the <=2, 3-4 and 5+ brackets")
	assert_eq(_power(ctx, rumble), 9, "Rumble1 (Power 3) gained +2 per discard")
	assert_eq(_card_id(ctx, rumble), "Rumble1", "3 discards is under discard_threshold 4")


## A fourth discard crosses discard_threshold, and Rumble2's {When I level up} then
## creates one card per discard, each 1 cheaper and with the Augment keyword.
func test_rumble_level_up_creates_one_augment_per_discard() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var rumble: int = _put_on_board(ctx, "Rumble1", 0, 0)
	var ops: MatchOps = ctx["ops"]
	# Four discards with four DIFFERENT base costs, so every creation is verifiable.
	for card_id: String in ["Ahri1", "Kennen1", "IcePillar", "AbyssalEye"]:
		ops.discard(ops.create_in_hand(card_id, 0), -1)
	assert_eq((ctx["state"] as MatchState).discarded.size(), 4, "four cards discarded")
	(ctx["ctx"] as MatchCardAbilities).after_change()

	assert_eq(_card_id(ctx, rumble), "Rumble2", "discard_threshold 4 reached")
	var augments: int = 0
	for hand_id: int in (ctx["state"] as MatchState).players[0].hand:
		var created := (ctx["state"] as MatchState).card(hand_id)
		if not created.has_keyword("Augment"):
			continue
		augments += 1
		assert_eq(created.get_current_cost(), int(created.data().get("Cost", 0)) - 1,
			"every created card costs 1 less than its base cost")
	assert_eq(augments, 4, "one created card per discarded card")


# ----------------------------
# Nasus
# ----------------------------

## Nasus lv1 kills the weakest ally in its lane at {Round End}. A Tryndamere lv1
## levels up instead of dying, and a prevented death is never counted as a kill.
func test_nasus_kills_the_weakest_ally_at_round_end() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var nasus: int = _put_on_board(ctx, "Nasus1", 0, 0)
	var trynd: int = _put_on_board(ctx, "Tryndamere1", 0, 0)
	var chip: int = _put_on_board(ctx, "Chip", 0, 0)

	# First round end: the Chip (Power 1) is the weakest ally and dies.
	_play_and_resolve(ctx, 0, _give_hand(ctx, 0, ["Chip"])[0], 2)
	assert_eq((ctx["state"] as MatchState).card(chip).location, CardState.Location.GONE,
		"the weakest ally died at round end")
	assert_eq(_power(ctx, nasus), 4, "Nasus1 (Power 2) gained kill_power 2")
	assert_eq(_card_id(ctx, nasus), "Nasus1", "one kill is below kill_threshold 2")

	# Second round end: Tryndamere is now the weakest, but it levels up instead.
	_play_and_resolve(ctx, 0, _give_hand(ctx, 0, ["Chip"])[0], 2)
	assert_eq(_card_id(ctx, trynd), "Tryndamere2", "Tryndamere levelled up instead of dying")
	assert_eq((ctx["state"] as MatchState).card(trynd).location, CardState.Location.BOARD,
		"it is still on the board")
	assert_eq((ctx["state"] as MatchState).killed.size(), 1,
		"a prevented death is never counted as a kill")


## Tryndamere lv2 survives the kill with +survive_power, and Nasus still buffs: the
## two effects are joined by "and" in the card text, so the buff always applies.
func test_nasus_still_gets_its_buff_against_a_surviving_tryndamere() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var nasus: int = _put_on_board(ctx, "Nasus2", 0, 0)  # kill_power 3, Power 3
	var trynd: int = _put_on_board(ctx, "Tryndamere2", 0, 0)  # survive_death, +2
	var trynd_power: int = _power(ctx, trynd)
	var nasus_power: int = _power(ctx, nasus)
	_play_and_resolve(ctx, 0, _give_hand(ctx, 0, ["Chip"])[0], 2)
	assert_eq((ctx["state"] as MatchState).card(trynd).location, CardState.Location.BOARD,
		"Tryndamere lv2 survived the kill")
	assert_eq(_power(ctx, trynd), trynd_power + 2, "it gained survive_power 2 instead")
	assert_eq(_power(ctx, nasus), nasus_power + 3, "Nasus2 gained kill_power 3 anyway")
	assert_eq((ctx["state"] as MatchState).killed.size(), 0, "nothing actually died")


## A stun stops Nasus from acting at {Round End} entirely: the rules skip stunned
## cards before the ability ever runs.
func test_a_stunned_nasus_skips_its_round_end_kill() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var nasus: int = _put_on_board(ctx, "Nasus1", 0, 0)
	var chip: int = _put_on_board(ctx, "Chip", 0, 0)
	var nasus_power: int = _power(ctx, nasus)
	# Stunned during the PLAY phase, so the stun is still live at this round's ROUND_END.
	(ctx["ops"] as MatchOps).stun(nasus)
	_play_and_resolve(ctx, 0, _give_hand(ctx, 0, ["Chip"])[0], 2)
	assert_eq((ctx["state"] as MatchState).card(chip).location, CardState.Location.BOARD,
		"the stunned Nasus killed nothing at round end")
	assert_eq(_power(ctx, nasus), nasus_power, "the stunned Nasus gained no kill_power")
	assert_eq((ctx["state"] as MatchState).killed.size(), 0, "nothing died")


# ----------------------------
# Auras
# ----------------------------

## Renekton's own {Round Start} buffs (power_modifier) are what cross his
## power_threshold; the Azir lv2 aura is a separate modifier and does not count
## towards it, exactly like the old `check_level_up_by_power`.
func test_renekton_levels_up_only_from_its_own_buffs() -> void:
	var ctx := _match(_filler(30), _filler(30))
	_put_on_board(ctx, "Azir2", 0, 0)  # +2 aura to other Ascended allies
	var renekton: int = _put_on_board(ctx, "Renekton1", 0, 0)  # power_threshold 4
	_put_on_board(ctx, "Chip", 0, 0)  # lane power 1, so Renekton (4) is winning

	_play_and_resolve(ctx, 0, _give_hand(ctx, 0, ["Chip"])[0], 2)
	assert_eq((ctx["state"] as MatchState).card(renekton).power_modifier, 2,
		"one {Round Start} win = win_power 2")
	assert_eq((ctx["state"] as MatchState).card(renekton).aura_power_modifier, 2,
		"Azir lv2's aura is a separate +2")
	assert_eq(_card_id(ctx, renekton), "Renekton1", "2 permanent power is under the threshold 4")

	_play_and_resolve(ctx, 0, _give_hand(ctx, 0, ["Chip"])[0], 2)
	assert_eq(_card_id(ctx, renekton), "Renekton2",
		"two wins reach power_modifier 4, which is power_threshold")


# ----------------------------
# Game End
# ----------------------------

## All three {Game End} passes: the board pass, the Azir lv3 double fire and the
## Sion hand summon for BOTH players.
func test_game_end_runs_all_three_passes() -> void:
	var ctx := _match(_filler(30), _filler(30))
	_put_on_board(ctx, "Azir3", 0, 0)
	_put_on_board(ctx, "Renekton3", 0, 0)
	var chip: int = _put_on_board(ctx, "Chip", 1, 0)
	var chip2: int = _put_on_board(ctx, "Chip", 1, 0)
	var ops: MatchOps = ctx["ops"]
	var sion0: int = ops.create_in_hand("SionReturned", 0)
	var sion1: int = ops.create_in_hand("SionReturned", 1)

	(ctx["ctx"] as MatchCardAbilities).on_game_end_phase()

	# Renekton fired once in pass one and once more because of Azir lv3: 1 + 1 - 3 - 3.
	assert_eq(_power(ctx, chip) + _power(ctx, chip2), -4,
		"the Ascended {Game End} card fired exactly twice")
	for sion: int in [sion0, sion1]:
		assert_eq((ctx["state"] as MatchState).card(sion).location, CardState.Location.BOARD,
			"both players' Sion were summoned from hand")
		assert_eq(_card_id(ctx, sion), "SionReturned", "the hand card itself went to the board")


## The rules really do run the {Game End} passes before deciding the winner. The
## double fire is counted from the event log, so it does not depend on which random
## enemy Renekton happened to pick.
func test_the_rules_call_the_game_end_phase_before_the_winner() -> void:
	var ctx := _match(_filler(30), _filler(30))
	_put_on_board(ctx, "Azir3", 0, 0)
	_put_on_board(ctx, "Renekton3", 0, 0)
	_put_on_board(ctx, "Chip", 1, 0)
	_put_on_board(ctx, "Chip", 1, 0)
	var rules: MatchRules = ctx["rules"]
	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = SEED
	var log: Array = []
	var guard: int = 0
	while (ctx["state"] as MatchState).game_phase != MatchState.GamePhase.GAME_END and guard < 200:
		for p in [0, 1]:
			for intent: Variant in MatchBot.decide(ctx["state"], p, bot_rng):
				log += rules.submit(p, intent)
		guard += 1
	assert_eq((ctx["state"] as MatchState).game_phase, MatchState.GamePhase.GAME_END,
		"the match reached GAME_END")
	assert_eq(_count_events(log, MatchEvents.GAME_ENDED, "winner", -1), 0,
		"a winner was actually decided (so the -1 count above is meaningful)")
	# Renekton3's {Game End} is the only source of a -3 power change in this match, and
	# Azir lv3 makes it fire twice.
	assert_eq(_count_events(log, MatchEvents.POWER_CHANGED, "delta", -3), 2,
		"the {Game End} pass ran through the rules, once per fire")



# ----------------------------
# Sun Disc
# ----------------------------

## Two allied lv2 Ascended champions transform the Buried Sun Disc: it draws every
## un-beheld Ascended card from the deck and every lv2 Ascended champion becomes lv3.
func test_sun_disc_restore_draws_and_promotes_to_lv3() -> void:
	var ctx := _match(_filler(20), _filler(20))
	var disc: int = _put_on_board(ctx, "BuriedSunDisc", 0, 1)
	var nasus: int = _put_on_board(ctx, "Nasus2", 0, 1)
	var renekton: int = _put_on_board(ctx, "Renekton2", 0, 1)
	# A known deck and hand, so the restore's draw is the only thing that can change.
	_set_deck(ctx, 0, ["Xerath1", "Chip"])
	_clear_hand(ctx, 0)
	var hand_before: int = (ctx["state"] as MatchState).players[0].hand.size()
	var drawn_before: int = (ctx["state"] as MatchState).drawn.size()

	(ctx["ctx"] as MatchCardAbilities).after_change()

	assert_eq(_card_id(ctx, disc), "RestoredSunDisc", "the Sun Disc transformed")
	assert_eq(_card_id(ctx, nasus), "Nasus3", "Nasus lv2 Ascended became lv3")
	assert_eq(_card_id(ctx, renekton), "Renekton3", "Renekton lv2 Ascended became lv3")
	assert_eq((ctx["state"] as MatchState).drawn.size() - drawn_before, 1,
		"exactly one un-beheld Ascended card (Xerath) was drawn from the deck")
	assert_eq((ctx["state"] as MatchState).players[0].hand.size(), hand_before + 1,
		"and it landed in the owner's hand")
	assert_ne(_in_hand(ctx, 0, "Xerath1"), -1, "the drawn card is an Xerath")


## The restore draws one copy per Ascended NAME that is not beheld, so an Xerath that
## is already on the board is never drawn again.
func test_sun_disc_does_not_redraw_an_already_beheld_ascended() -> void:
	var ctx := _match(_filler(20), _filler(20))
	_put_on_board(ctx, "Xerath1", 0, 0)  # Xerath is beheld
	var disc: int = _put_on_board(ctx, "BuriedSunDisc", 0, 1)
	_put_on_board(ctx, "Nasus2", 0, 1)
	_put_on_board(ctx, "Renekton2", 0, 1)
	_set_deck(ctx, 0, ["Xerath1", "Chip"])
	_clear_hand(ctx, 0)
	var drawn_before: int = (ctx["state"] as MatchState).drawn.size()
	(ctx["ctx"] as MatchCardAbilities).after_change()
	assert_eq(_card_id(ctx, disc), "RestoredSunDisc", "the Sun Disc still transformed")
	assert_eq((ctx["state"] as MatchState).drawn.size(), drawn_before,
		"an already-beheld Ascended name is not drawn again")
	assert_eq((ctx["state"] as MatchState).players[0].deck.size(), 2,
		"the Xerath is still in the deck")


# ----------------------------
# Trundle
# ----------------------------

## Trundle lv1 creates an Ice Pillar; playing it from hand levels Trundle up, and the
## Pillar's own {Play} queues +5 mana that becomes active next turn.
func test_trundle_ice_pillar_levels_up_and_ramps_mana() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var trundle: int = _give_hand(ctx, 0, ["Trundle1"])[0]
	_play_and_resolve(ctx, 0, trundle, 0)
	var pillar: int = _in_hand(ctx, 0, "IcePillar")
	assert_ne(pillar, -1, "Trundle created an Ice Pillar in hand")

	# Play the Pillar, then let the round finish WITHOUT re-setting the mana, so the
	# queued +5 is the only thing that can have changed the maximum.
	_rich(ctx, 0)
	var log: Array = []
	log += (ctx["rules"] as MatchRules).submit(0, MatchIntents.play_card(pillar, 0))
	log += _end_round(ctx)

	assert_eq(_card_id(ctx, trundle), "Trundle2", "playing the Ice Pillar levelled Trundle up")
	# The Pillar queued +5 during RESOLVE and the next turn's _refresh_mana moved it from
	# pending to active, on top of the engine's own turn-based base mana.
	var ps: PlayerState = (ctx["state"] as MatchState).players[0]
	assert_eq(ps.bonus_max_mana, 5, "the Ice Pillar's +5 mana is the player's whole bonus")
	assert_eq(ps.active_temp_mana, 5, "and it is the active temp mana, not still pending")
	assert_eq(ps.pending_bonus_mana, 0, "nothing is left queued")
	assert_eq(ps.base_max_mana, (ctx["state"] as MatchState).turn,
		"the base mana is still the engine's turn-based growth")


# ----------------------------
# Deep
# ----------------------------

## Going Deep levels Nautilus up, its {When I level up} creates Sea Monsters, and the
## lv2 aura then discounts those Sea Monsters in the owner's hand.
func test_going_deep_levels_nautilus_and_discounts_its_sea_monsters() -> void:
	var ctx := _match(_filler(40), _filler(30))
	var nautilus: int = _put_on_board(ctx, "Nautilus1", 0, 0)
	var ops: MatchOps = ctx["ops"]

	ops.set_deep(0)
	assert_eq(_card_id(ctx, nautilus), "Nautilus2", "being Deep levelled Nautilus up")

	var sea_monsters_in_hand: int = 0
	for hand_id: int in (ctx["state"] as MatchState).players[0].hand:
		var c := (ctx["state"] as MatchState).card(hand_id)
		if str(c.data().get("SubType", "")) != "Sea Monster":
			continue
		sea_monsters_in_hand += 1
		assert_eq(c.get_current_cost(), maxi(0, int(c.data().get("Cost", 0)) - 3),
			"Nautilus lv2's aura discounts every Sea Monster in the owner's hand")
	assert_eq(sea_monsters_in_hand, 3, "the level-up created created_count Sea Monsters")

	# The Deep aura itself only touches resolved units that are ON the board.
	var scarab: int = ops.create_in_hand("SeaScarab", 0)
	assert_true(ops.put_into_play(scarab, 1), "the Sea Scarab went to the board")
	(ctx["ctx"] as MatchCardAbilities).after_change()
	assert_eq(_power(ctx, scarab), 5, "Deep gives an on-board Deep unit +3 (Sea Scarab 2 -> 5)")


# ----------------------------
# Draven
# ----------------------------

## Two Spinning Axes played while Draven is on the board take him to lv2.
func test_two_spinning_axes_level_draven_up() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var draven: int = _put_on_board(ctx, "Draven1", 0, 0)
	var ops: MatchOps = ctx["ops"]
	ops.create_in_hand("SpinningAxe", 0)
	ops.create_in_hand("SpinningAxe", 0)

	_play_and_resolve(ctx, 0, _in_hand(ctx, 0, "SpinningAxe"), MatchState.SPELL_COL)
	assert_eq(_card_id(ctx, draven), "Draven1", "one axe is under axe_threshold 2")

	_play_and_resolve(ctx, 0, _in_hand(ctx, 0, "SpinningAxe"), MatchState.SPELL_COL)
	assert_eq(_card_id(ctx, draven), "Draven2", "the second axe crossed axe_threshold 2")


# ----------------------------
# Ahri
# ----------------------------

## Ahri lv1 recalls the weakest ally at her destination lane; three recalls of her own
## levelling her up.
func test_ahri_levels_up_after_recalling_three_allies() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var ahri: int = _put_on_board(ctx, "Ahri1", 0, 0)
	var ops: MatchOps = ctx["ops"]
	# One target per destination lane, so each swap recalls exactly one ally.
	ops.summon("Chip", 0, 1)
	ops.summon("Chip", 0, 2)
	ops.summon("Chip", 0, 1)

	var rules: MatchRules = ctx["rules"]
	for to_col: int in [1, 2, 1]:
		rules.submit(0, MatchIntents.swap_card(ahri, to_col))
		_end_round(ctx)

	assert_eq((ctx["state"] as MatchState).recalled.size(), 3, "three allies were recalled")
	assert_eq(_card_id(ctx, ahri), "Ahri2", "recall_threshold 3 levelled Ahri up")
	for entry: Dictionary in (ctx["state"] as MatchState).recalled:
		assert_eq(int(entry.get("recaller_instance_id", -1)), ahri,
			"every recall names this Ahri instance as the recaller")


# ----------------------------
# Stun, end to end
# ----------------------------

## Kennen lv1 stuns a random ENEMY unit in its lane, and the rules then skip that
## card's {Round End}. Nasus and the Chip are both legal stun targets, so the match
## rng is pinned to the value that makes pick_random take Nasus: the assertion is
## about the stun blocking the kill, not about which card the roll landed on.
func test_a_kennen_stun_blocks_a_nasus_round_end() -> void:
	var ctx := _match(_filler(30), _filler(30))
	var state: MatchState = ctx["state"]
	var nasus: int = _put_on_board(ctx, "Nasus1", 0, 0)
	var chip: int = _put_on_board(ctx, "Chip", 0, 0)
	var nasus_power: int = _power(ctx, nasus)
	# Kennen belongs to player 1: its {Play} stuns an enemy, and Nasus and the Chip are
	# the only enemy units in column 0. Nasus is first in zone order, so a roll of 0
	# picks him.
	var kennen: int = _give_hand(ctx, 1, ["Kennen1"])[0]
	_rich(ctx, 1)
	state.rng.seed = 2  # randi() % 2 == 0 -> pick_random returns the first candidate

	_play_and_resolve(ctx, 1, kennen, 0)

	assert_true((ctx["ops"] as MatchOps).is_stunned(nasus), "Kennen stunned Nasus")
	assert_eq(state.card(chip).location, CardState.Location.BOARD,
		"the stunned Nasus killed nothing at round end")
	assert_eq(_power(ctx, nasus), nasus_power, "and it gained no kill_power")
	assert_eq(state.killed.size(), 0, "nothing died at all")