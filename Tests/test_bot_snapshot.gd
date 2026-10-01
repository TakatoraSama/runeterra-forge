## MatchBot.decide_from_snapshot must be the SAME bot as MatchBot.decide.
##
## The guest has no MatchState, so its autoplay has to be answered from the snapshot the
## host sent it. If the two paths disagreed by even one rng call, the guest would start
## playing cards its opponent's engine never sees — a desync that only shows up on a
## real LAN match, hours later. So every test here compares BOTH the returned intents
## AND the generator state left behind: same choice, same number of draws.
extends "res://Tests/test_case.gd"

const SEEDS := 40


## A state in PLAY phase where `player` holds `hand_ids` and has `mana`, with `board`
## cards already in the lanes (col -> count) and in the spell zone.
func _state_in_play(hand_ids: Array, mana: int = 5, player: int = 0,
		board: Dictionary = {}, spells: int = 0, noxkraya: int = -1) -> MatchState:
	var state := MatchState.new()
	state.game_phase = MatchState.GamePhase.TURN_LOOP
	state.round_phase = MatchState.RoundPhase.PLAY
	state.turn = 2
	state.noxkraya_col = noxkraya
	for raw: Variant in hand_ids:
		var c := state.new_card(str(raw), player, CardState.Location.HAND)
		state.players[player].hand.append(c.instance_id)
	state.players[player].current_mana = mana
	state.players[player].base_max_mana = maxi(1, mana)
	for col: int in board:
		for _i in int(board[col]):
			var card := state.new_card("Nasus1", player, CardState.Location.BOARD)
			state.place_card(card.instance_id, col, player)
			card.is_resolved = true
	for _i in spells:
		var spell := state.new_card("SpinningAxe", player, CardState.Location.SPELL_ZONE)
		state.place_card(spell.instance_id, MatchState.SPELL_COL, player)
		spell.is_resolved = true
	return state


## The one comparison everything else leans on: same intents, same rng left behind.
func _assert_same_decision(state: MatchState, player: int, seed_value: int, msg: String) -> void:
	var from_engine := RandomNumberGenerator.new()
	from_engine.seed = seed_value
	var from_snapshot := RandomNumberGenerator.new()
	from_snapshot.seed = seed_value
	var engine_side := MatchBot.decide(state, player, from_engine)
	var snapshot_side := MatchBot.decide_from_snapshot(
		MatchSnapshot.for_viewer(state, player), from_snapshot)
	assert_eq(snapshot_side, engine_side, "%s (seed %d)" % [msg, seed_value])
	assert_eq(from_snapshot.state, from_engine.state,
		"%s: both paths must draw the same numbers (seed %d)" % [msg, seed_value])


# --- The equivalence itself ---

func test_snapshot_decision_matches_the_engine_decision_for_many_seeds() -> void:
	var state := _state_in_play(["Ahri1", "Kennen1", "Renekton1", "Nasus1"], 6)
	for seed_value in SEEDS:
		_assert_same_decision(state, 0, seed_value, "player 0 decides the same")


func test_the_decision_matches_for_the_guest_too() -> void:
	# Player 1 is the guest, so its OWN snapshot is what it decides from; the same must
	# hold with the bot's own card ids and a board that is already busy.
	var state := _state_in_play(["Ahri1", "Kennen1", "Renekton1"], 5, 1,
		{0: 2, 1: 1, 2: 4}, 2, 1)
	for seed_value in SEEDS:
		_assert_same_decision(state, 1, seed_value, "player 1 decides the same")


func test_spells_and_units_both_decide_the_same() -> void:
	# The spell path takes the spell zone and makes NO second rng call, so a mismatch
	# there would show up as a different rng state even when the play looks right.
	var state := _state_in_play(["SpinningAxe", "HexCoreUpgrade", "Ahri1"], 4, 1, {0: 1})
	for seed_value in SEEDS:
		_assert_same_decision(state, 1, seed_value, "a spell in hand decides the same")


func test_a_full_zone_decides_the_same() -> void:
	var state := _state_in_play(["Ahri1", "Kennen1"], 9, 0, {0: 4, 1: 4, 2: 4})
	for seed_value in SEEDS:
		_assert_same_decision(state, 0, seed_value, "no room anywhere decides the same")


func test_a_full_spell_zone_falls_through_to_a_lane_the_same() -> void:
	var state := _state_in_play(["SpinningAxe"], 9, 0, {}, MatchState.SPELL_SLOTS)
	for seed_value in SEEDS:
		_assert_same_decision(state, 0, seed_value, "a full spell zone decides the same")


func test_noxkraya_forces_the_same_column() -> void:
	var state := _state_in_play(["Ahri1", "Kennen1"], 9, 0, {}, 0, 2)
	for seed_value in SEEDS:
		_assert_same_decision(state, 0, seed_value, "Noxkraya decides the same")


func test_nothing_affordable_decides_the_same() -> void:
	var state := _state_in_play(["NavoriConspirator", "SolitaryMonk"], 1)
	for seed_value in SEEDS:
		_assert_same_decision(state, 0, seed_value, "no affordable card decides the same")


func test_an_ended_turn_decides_the_same() -> void:
	var state := _state_in_play(["Ahri1"], 5, 0)
	state.players[0].ended_turn = true
	for seed_value in SEEDS:
		_assert_same_decision(state, 0, seed_value, "an ended turn decides the same")


func test_a_json_round_tripped_snapshot_still_decides_the_same() -> void:
	# The guest receives the snapshot over the wire, so what it decides from is the
	# parsed copy, not the Dictionary the host built.
	var state := _state_in_play(["Ahri1", "Kennen1", "SpinningAxe"], 7, 1, {0: 1, 2: 3})
	var wire: Dictionary = JSON.parse_string(JSON.stringify(MatchSnapshot.for_viewer(state, 1)))
	for seed_value in SEEDS:
		var from_engine := RandomNumberGenerator.new()
		from_engine.seed = seed_value
		var from_wire := RandomNumberGenerator.new()
		from_wire.seed = seed_value
		assert_eq(MatchBot.decide_from_snapshot(wire, from_wire),
			MatchBot.decide(state, 1, from_engine), "the parsed snapshot decides the same")
		assert_eq(from_wire.state, from_engine.state, "and draws the same numbers")


# --- The refusals, which must not spend an rng number either ---

func test_outside_play_the_snapshot_decides_nothing() -> void:
	for round_phase: int in [MatchState.RoundPhase.NONE, MatchState.RoundPhase.ROUND_START,
			MatchState.RoundPhase.SWAP_LANE, MatchState.RoundPhase.RESOLVE,
			MatchState.RoundPhase.ROUND_END]:
		var state := _state_in_play(["Ahri1"], 5)
		state.round_phase = round_phase
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var before: int = rng.state
		assert_eq(MatchBot.decide_from_snapshot(MatchSnapshot.for_viewer(state, 0), rng), [],
			"round phase %d is not the bot's move" % round_phase)
		assert_eq(rng.state, before, "and nothing was drawn")


func test_after_game_end_the_snapshot_decides_nothing() -> void:
	var state := _state_in_play(["Ahri1"], 5)
	state.game_phase = MatchState.GamePhase.GAME_END
	assert_eq(MatchBot.decide_from_snapshot(MatchSnapshot.for_viewer(state, 0),
		RandomNumberGenerator.new()), [], "the match is over")


func test_a_broken_snapshot_decides_nothing_instead_of_crashing() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_eq(MatchBot.decide_from_snapshot({}, rng), [], "an empty snapshot")
	assert_eq(MatchBot.decide_from_snapshot({"game_phase": MatchState.GamePhase.TURN_LOOP}, rng), [],
		"a snapshot with no players")
	assert_eq(MatchBot.decide_from_snapshot({
		"game_phase": MatchState.GamePhase.TURN_LOOP,
		"round_phase": MatchState.RoundPhase.PLAY,
		"local": 5,
		"players": [{"player": 0}, {"player": 1}],
	}, rng), [], "a local id that is not a player")
	assert_eq(MatchBot.decide_from_snapshot({
		"game_phase": MatchState.GamePhase.TURN_LOOP,
		"round_phase": MatchState.RoundPhase.PLAY,
		"local": 1,
		"players": [{"player": 0, "current_mana": 3, "hand": 2},
			{"player": 1, "current_mana": 3, "hand": 2}],
	}, rng), [], "an opponent-shaped hand (a count, not a list) is not played from")


func test_the_two_paths_agree_at_every_turn_of_a_real_match() -> void:
	var state := MatchSetup.new_match(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, 99)
	var rules := MatchRules.new(state)
	MatchCardAbilities.install(rules)
	rules.start_match()
	var bot := RandomNumberGenerator.new()
	bot.seed = 5
	var rounds: int = 0
	while state.game_phase == MatchState.GamePhase.TURN_LOOP and rounds < 20:
		for player in [0, 1]:
			# A clone of the generator at exactly the position the bot decides from:
			# assigning .seed would restart it, .state continues the same stream.
			var shadow := RandomNumberGenerator.new()
			shadow.state = bot.state
			var from_snapshot := MatchBot.decide_from_snapshot(
				MatchSnapshot.for_viewer(state, player), shadow)
			var intents := MatchBot.decide(state, player, bot)
			assert_eq(from_snapshot, intents, "turn %d player %d: the guest decides the same"
				% [state.turn, player])
			assert_eq(shadow.state, bot.state,
				"turn %d player %d: and draws the same numbers" % [state.turn, player])
			for intent: Variant in intents:
				rules.submit(player, intent)
		rounds += 1
	assert_true(rounds > 3, "the match actually ran several rounds")
