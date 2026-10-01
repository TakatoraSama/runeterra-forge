## Tests for MatchBot: the pure-function AI opponent.
extends "res://Tests/test_case.gd"

var _rng := RandomNumberGenerator.new()

const SPELL_CARD := "SpinningAxe"  # Cost 0, Type "Spell"
const OTHER_SPELL := "HexCoreUpgrade"  # Cost 0, Type "Spell"
const CHEAP := "Ahri1"  # Cost 1, Follower
const COSTLY := "NavoriConspirator"  # Cost 2, Follower


func before_each() -> void:
	_rng.seed = 424242


## A state in PLAY phase where `player` holds `hand_ids` and has `mana`.
func _state_in_play(hand_ids: Array, mana: int = 5, player: int = 0) -> MatchState:
	var state := MatchState.new()
	state.game_phase = MatchState.GamePhase.TURN_LOOP
	state.round_phase = MatchState.RoundPhase.PLAY
	state.turn = 2
	for raw: Variant in hand_ids:
		var c := state.new_card(str(raw), player, CardState.Location.HAND)
		state.players[player].hand.append(c.instance_id)
	state.players[player].current_mana = mana
	state.players[player].base_max_mana = maxi(1, mana)
	return state


func test_returns_nothing_outside_play_phase() -> void:
	var state := _state_in_play([CHEAP])
	state.round_phase = MatchState.RoundPhase.RESOLVE
	assert_eq(MatchBot.decide(state, 0, _rng), [], "RESOLVE is not the bot's turn")

	state.round_phase = MatchState.RoundPhase.ROUND_START
	assert_eq(MatchBot.decide(state, 0, _rng), [], "ROUND_START is not the bot's turn")

	state.round_phase = MatchState.RoundPhase.SWAP_LANE
	assert_eq(MatchBot.decide(state, 0, _rng), [], "SWAP_LANE is not the bot's turn")

	state.round_phase = MatchState.RoundPhase.PLAY
	state.game_phase = MatchState.GamePhase.GAME_START
	assert_eq(MatchBot.decide(state, 0, _rng), [], "GAME_START is not the bot's turn")

	state.game_phase = MatchState.GamePhase.GAME_END
	assert_eq(MatchBot.decide(state, 0, _rng), [], "the game is over")


func test_returns_nothing_after_the_player_ended() -> void:
	var state := _state_in_play([CHEAP])
	state.players[0].ended_turn = true
	assert_eq(MatchBot.decide(state, 0, _rng), [], "player already ended its turn")


func test_only_ends_turn_when_nothing_is_affordable() -> void:
	# Both cards cost 2, the bot has 1.
	var state := _state_in_play([COSTLY, "SolitaryMonk"], 1)
	var intents := MatchBot.decide(state, 0, _rng)
	assert_eq(intents.size(), 1, "only end_turn is submitted")
	assert_eq(intents[0]["type"], MatchIntents.END_TURN)


func test_always_ends_with_end_turn() -> void:
	for turn in [1, 3, 6]:
		var state := _state_in_play([CHEAP, "Kennen1"], 6)
		state.turn = turn
		var intents := MatchBot.decide(state, 0, _rng)
		assert_eq(intents.size(), 2, "a play plus end_turn on turn %d" % turn)
		assert_eq(intents[0]["type"], MatchIntents.PLAY_CARD)
		assert_eq(intents[1]["type"], MatchIntents.END_TURN)


func test_plays_at_most_one_card_per_turn() -> void:
	var state := _state_in_play([CHEAP, "Kennen1", "Renekton1", "Nasus1"], 10)
	var intents := MatchBot.decide(state, 0, _rng)
	var plays: int = 0
	for intent: Dictionary in intents:
		if intent["type"] == MatchIntents.PLAY_CARD:
			plays += 1
	assert_eq(plays, 1, "exactly one play at most")


## Across many seeds the played card is always one the bot can afford.
func test_only_plays_affordable_cards() -> void:
	for seed_value in range(30):
		var state := _state_in_play([COSTLY, "SolitaryMonk", CHEAP], 2)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var intents := MatchBot.decide(state, 0, rng)
		if intents.is_empty() or intents[0]["type"] != MatchIntents.PLAY_CARD:
			continue
		var played: int = int(intents[0]["instance_id"])
		var cost: int = state.card(played).get_current_cost()
		assert_true(cost <= 2, "seed %d played a %d-cost card with 2 mana" % [seed_value, cost])


## Units go to a lane column, spells to the spell zone, always a legal one.
func test_units_go_to_lanes_and_spells_to_the_spell_zone() -> void:
	for seed_value in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value

		var state := _state_in_play([CHEAP], 5)
		var intents := MatchBot.decide(state, 0, rng)
		assert_eq(intents[0]["type"], MatchIntents.PLAY_CARD, "seed %d plays a unit" % seed_value)
		var col: int = int(intents[0]["col"])
		assert_true(col >= 0 and col < MatchState.COLUMNS, "unit col in 0..2 (seed %d)" % seed_value)

		var spell_state := _state_in_play([SPELL_CARD], 5)
		var spell_intents := MatchBot.decide(spell_state, 0, rng)
		if not spell_intents.is_empty() and spell_intents[0]["type"] == MatchIntents.PLAY_CARD:
			assert_eq(int(spell_intents[0]["col"]), MatchState.SPELL_COL,
				"a Spell goes into the spell zone (seed %d)" % seed_value)


func test_never_plays_into_a_full_zone() -> void:
	var state := _state_in_play([CHEAP], 5)
	for col in MatchState.COLUMNS:
		for i in MatchState.SLOTS_PER_ZONE:
			var c := state.new_card("Nasus1", 0, CardState.Location.BOARD)
			state.place_card(c.instance_id, col, 0)
	for seed_value in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var intents := MatchBot.decide(state, 0, rng)
		assert_eq(intents.size(), 1, "all lanes full: only end_turn (seed %d)" % seed_value)
		assert_eq(intents[0]["type"], MatchIntents.END_TURN)


func test_never_plays_outside_the_noxkraya_column() -> void:
	var state := _state_in_play([CHEAP, "Kennen1"], 9)
	state.noxkraya_col = 2
	for seed_value in range(30):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var intents := MatchBot.decide(state, 0, rng)
		if intents.is_empty() or intents[0]["type"] != MatchIntents.PLAY_CARD:
			continue
		assert_eq(int(intents[0]["col"]), 2, "Noxkraya forces column 2 (seed %d)" % seed_value)


func test_skips_the_play_when_the_spell_zone_is_full() -> void:
	var state := _state_in_play([SPELL_CARD], 9)
	for i in MatchState.SPELL_SLOTS:
		var c := state.new_card(OTHER_SPELL, 0, CardState.Location.SPELL_ZONE)
		state.place_card(c.instance_id, MatchState.SPELL_COL, 0)
	for seed_value in range(20):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var intents := MatchBot.decide(state, 0, rng)
		assert_eq(intents.size(), 1, "spell zone full: only end_turn (seed %d)" % seed_value)
		assert_eq(intents[0]["type"], MatchIntents.END_TURN)


func test_same_seed_gives_the_same_choice() -> void:
	var first := _state_in_play([CHEAP, "Kennen1", "Renekton1", "Nasus1"], 7)
	var second := _state_in_play([CHEAP, "Kennen1", "Renekton1", "Nasus1"], 7)
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 99
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 99
	var a := MatchBot.decide(first, 0, rng_a)
	var b := MatchBot.decide(second, 0, rng_b)
	assert_eq(a.size(), b.size(), "same number of intents")
	for i in mini(a.size(), b.size()):
		assert_eq(a[i], b[i], "intent %d identical" % i)


func test_never_swaps_or_undoes() -> void:
	for seed_value in range(20):
		var state := _state_in_play([CHEAP, "Kennen1"], 9)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for intent: Dictionary in MatchBot.decide(state, 0, rng):
			assert_true(intent["type"] == MatchIntents.PLAY_CARD or intent["type"] == MatchIntents.END_TURN,
				"only play_card / end_turn (seed %d)" % seed_value)


func test_decides_for_each_player_separately() -> void:
	var state := _state_in_play([CHEAP, "Kennen1"], 4, 1)
	var intents := MatchBot.decide(state, 1, _rng)
	assert_eq(intents.size(), 2, "player 1 gets a play")
	var played: int = int(intents[0]["instance_id"])
	assert_eq(state.card(played).owner, 1, "the bot plays its own card")