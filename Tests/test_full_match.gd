## End-to-end test: two bots playing a whole match with the real engine.
##
## Every `submit` is followed by a full invariant sweep of the state (zones, mana,
## card bookkeeping, card count), the whole event log is checked for JSON-safety and
## redaction, and the match is replayed with the same seed to prove determinism.
extends "res://Tests/test_case.gd"

const SEEDS: Array[int] = [1, 2, 3, 7, 99]
const ITERATION_GUARD := 500

## Deck.gd.DEFAULT_DECK as plain card ids.
const DEFAULT_DECK_IDS: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Ahri1",
	"Kennen1", "NavoriConspirator", "Janna1", "Draven1", "Rumble1", "Sion1",
]

## BotManager.BOT_DECK.
const BOT_DECK_IDS: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Trundle1",
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk",
]


## Runs one full bot-vs-bot match with the given decks and seed.
## Returns {state, log, iterations, initial_cards}.
func _play(seed_value: int, deck0: Array, deck1: Array) -> Dictionary:
	var state := MatchSetup.new_match(deck0, deck1, seed_value)
	var rules := MatchRules.new(state)
	var initial_cards: int = state.cards.size()
	var log: Array = rules.start_match()
	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = seed_value + 1
	var iterations: int = 0
	while state.game_phase != MatchState.GamePhase.GAME_END and iterations < ITERATION_GUARD:
		for p in [0, 1]:
			for intent: Variant in MatchBot.decide(state, p, bot_rng):
				log += rules.submit(p, intent)
				_check_invariants(state, log, seed_value, iterations, initial_cards)
		iterations += 1
	return {"state": state, "log": log, "iterations": iterations, "initial_cards": initial_cards}


## The invariant sweep the task requires after every submit.
func _check_invariants(state: MatchState, log: Array, seed_value: int, iteration: int, initial_cards: int) -> void:
	var where: String = "seed %d, iteration %d" % [seed_value, iteration]

	# Every zone respects its capacity.
	for key: Vector2i in state.zones:
		var zone_list: Array = state.zones[key]
		var limit: int = MatchState.SPELL_SLOTS if key.x == MatchState.SPELL_COL else MatchState.SLOTS_PER_ZONE
		assert_true(zone_list.size() <= limit,
			"%s: zone %s holds %d cards (limit %d)" % [where, key, zone_list.size(), limit])

	# Mana is inside [0, max].
	for p in 2:
		var ps: PlayerState = state.players[p]
		assert_true(ps.current_mana >= 0, "%s: player %d has negative mana" % [where, p])
		assert_true(ps.current_mana <= ps.get_max_mana(),
			"%s: player %d mana %d exceeds max %d" % [where, p, ps.current_mana, ps.get_max_mana()])

	# Every card sits in exactly one place, consistent with its location. A card that
	# left the game (GONE) is in none of the lists, which is exactly one place too.
	var listed: Dictionary = {}
	for p in 2:
		for id: int in state.players[p].deck:
			listed[id] = int(listed.get(id, 0)) + 1
			assert_eq(state.card(id).location, CardState.Location.DECK,
				"%s: card %d is listed in the deck" % [where, id])
			assert_eq(state.card(id).owner, p, "%s: deck card %d belongs to player %d" % [where, id, p])
		for id: int in state.players[p].hand:
			listed[id] = int(listed.get(id, 0)) + 1
			assert_eq(state.card(id).location, CardState.Location.HAND,
				"%s: card %d is listed in the hand" % [where, id])
			assert_eq(state.card(id).owner, p, "%s: hand card %d belongs to player %d" % [where, id, p])
	for key: Vector2i in state.zones:
		var zone_list: Array = state.zones[key]
		for slot in zone_list.size():
			var id: int = int(zone_list[slot])
			listed[id] = int(listed.get(id, 0)) + 1
			var c := state.card(id)
			assert_true(c != null, "%s: zone holds unknown card %d" % [where, id])
			if c == null:
				continue
			var expected: int = CardState.Location.SPELL_ZONE \
				if key.x == MatchState.SPELL_COL else CardState.Location.BOARD
			assert_eq(c.location, expected, "%s: card %d is in zone %s" % [where, id, key])
			assert_eq(c.owner, key.y, "%s: card %d is owned by its zone's row" % [where, id])
			assert_eq(c.col, key.x, "%s: card %d column matches its zone" % [where, id])
			assert_eq(c.slot, slot, "%s: card %d slot is its index in the zone" % [where, id])
	for id: int in state.cards:
		var gone: bool = state.card(id).location == CardState.Location.GONE
		assert_eq(int(listed.get(id, 0)), 0 if gone else 1,
			"%s: card %d is listed exactly once (gone=%s)" % [where, id, str(gone)])

	# The card total only ever grows through summon / create_in_hand.
	var created_events: int = 0
	for e: Dictionary in log:
		if e["type"] == MatchEvents.CARD_SUMMONED or e["type"] == MatchEvents.CARD_CREATED_IN_HAND:
			created_events += 1
	assert_eq(state.cards.size(), initial_cards + created_events,
		"%s: cards only appear through summon / create_in_hand" % where)

	# The bot never gets an intent rejected.
	for e: Dictionary in log:
		if e["type"] == MatchEvents.INTENT_REJECTED:
			fail("%s: the bot was rejected: %s" % [where, str(e["reason"])])


func test_bot_vs_bot_reaches_game_end_for_every_seed() -> void:
	for seed_value in SEEDS:
		var result := _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)
		var state: MatchState = result["state"]
		assert_true(int(result["iterations"]) < ITERATION_GUARD,
			"seed %d finished under the guard" % seed_value)
		assert_eq(state.game_phase, MatchState.GamePhase.GAME_END,
			"seed %d reached GAME_END in %d iterations" % [seed_value, int(result["iterations"])])


func test_exactly_one_game_ended_event() -> void:
	for seed_value in SEEDS:
		var result := _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)
		var count: int = 0
		for e: Dictionary in result["log"]:
			if e["type"] == MatchEvents.GAME_ENDED:
				count += 1
		assert_eq(count, 1, "seed %d emits exactly one game_ended" % seed_value)


func test_game_ended_carries_the_lane_powers() -> void:
	for seed_value in SEEDS:
		var result := _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)
		var found: bool = false
		for e: Dictionary in result["log"]:
			if e["type"] != MatchEvents.GAME_ENDED:
				continue
			found = true
			var powers: Array = e["lane_powers"]
			assert_eq(powers.size(), 2, "lane_powers has one row per player")
			for row: Array in powers:
				assert_eq(row.size(), MatchState.COLUMNS, "lane_powers has one entry per column")
			assert_true(int(e["winner"]) >= -1 and int(e["winner"]) <= 1, "winner is -1, 0 or 1")
		assert_true(found, "seed %d logs game_ended" % seed_value)


func test_the_same_seed_replays_identically() -> void:
	for seed_value in SEEDS:
		var first := _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)
		var second := _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)
		assert_eq(hash(JSON.stringify(first["log"], "", true)),
			hash(JSON.stringify(second["log"], "", true)),
			"seed %d: identical event logs" % seed_value)
		assert_eq((first["state"] as MatchState).checksum(),
			(second["state"] as MatchState).checksum(),
			"seed %d: identical final state" % seed_value)


func test_different_seeds_produce_different_logs() -> void:
	var unique: Dictionary = {}
	for seed_value in SEEDS:
		var result := _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)
		unique[hash(JSON.stringify(result["log"], "", true))] = true
	assert_true(unique.size() >= 2, "at least two of the seeds diverge")


func test_every_event_survives_redaction_and_json() -> void:
	for seed_value in SEEDS:
		var log: Array = _play(seed_value, DEFAULT_DECK_IDS, BOT_DECK_IDS)["log"]
		for e: Dictionary in log:
			# null means "not visible to that viewer", which is legal; anything else
			# must still serialize. JSON.stringify is what catches an Object or a Vector2i.
			for viewer in [0, 1]:
				var seen: Variant = MatchEvents.redact_for(e, viewer)
				if seen == null:
					continue
				assert_true(JSON.stringify(seen, "", true).length() > 0,
					"seed %d: viewer %d can serialize %s" % [seed_value, viewer, str(e["type"])])
		assert_true(JSON.stringify(log, "", true).length() > 0, "seed %d: the whole log serializes" % seed_value)


## Fixed lanes that all have a timed effect, driven through the real round loop.
func _play_fixed_lanes(seed_value: int, lane_ids: Array) -> Dictionary:
	var state := MatchSetup.new_match(DEFAULT_DECK_IDS, BOT_DECK_IDS, seed_value)
	var rules := MatchRules.new(state)
	var initial_cards: int = state.cards.size()
	var log: Array = rules.start_match(lane_ids)
	var bot_rng := RandomNumberGenerator.new()
	bot_rng.seed = seed_value + 1
	var iterations: int = 0
	while state.game_phase != MatchState.GamePhase.GAME_END and iterations < ITERATION_GUARD:
		for p in [0, 1]:
			for intent: Variant in MatchBot.decide(state, p, bot_rng):
				log += rules.submit(p, intent)
				_check_invariants(state, log, seed_value, iterations, initial_cards)
		iterations += 1
	return {"state": state, "log": log, "iterations": iterations}


## Rockfall Path (reveal), Sunken Temple (round end turn 3), Noxkraya (round start turn 5).
func test_lane_effects_fire_on_the_documented_turns() -> void:
	var result := _play_fixed_lanes(5, ["RockfallPath", "SunkenTemple", "NoxkrayaArena"])
	var turns: Dictionary = {}
	var turn: int = 0
	for e: Dictionary in result["log"]:
		if e["type"] == MatchEvents.TURN_STARTED:
			turn = int(e["turn"])
		elif e["type"] == MatchEvents.LANE_EFFECT:
			turns[str(e["effect"])] = turn
	assert_true(turns.has("rockfall_chip"), "Rockfall Path fired")
	assert_eq(int(turns.get("sunken_temple", -1)), 3, "Sunken Temple fires at turn 3's round end")
	assert_eq(int(turns.get("noxkraya_active", -1)), 5, "Noxkraya Arena fires at turn 5's round start")


## Ornn's Forge fires at turn 4's round end.
func test_ornns_forge_fires_at_turn_four() -> void:
	var result := _play_fixed_lanes(8, ["OrnnsForge", "SunkenTemple", "NoxkrayaArena"])
	var turns: Dictionary = {}
	var turn: int = 0
	for e: Dictionary in result["log"]:
		if e["type"] == MatchEvents.TURN_STARTED:
			turn = int(e["turn"])
		elif e["type"] == MatchEvents.LANE_EFFECT:
			turns[str(e["effect"])] = turn
	assert_eq(int(turns.get("ornn_forge", -1)), 4, "Ornn's Forge fires at turn 4's round end")


## Hexcore Foundry draws on reveal (turn 1), so it happens before turn 1's play phase.
func test_hexcore_foundry_fires_on_the_first_turn() -> void:
	var result := _play_fixed_lanes(13, ["HexcoreFoundry", "OrnnsForge", "RockfallPath"])
	var found: bool = false
	for e: Dictionary in result["log"]:
		if e["type"] == MatchEvents.LANE_EFFECT and str(e["effect"]) == "hexcore_draw":
			found = true
			assert_eq(int(e["col"]), 0, "the left lane's Foundry draws")
	assert_true(found, "Hexcore Foundry fired")


## Fixed lanes including Rockfall + Noxkraya still reach GAME_END with the invariants intact.
func test_bot_vs_bot_with_fixed_lanes_finishes() -> void:
	for lane_set in [["RockfallPath", "SunkenTemple", "NoxkrayaArena"],
			["HexcoreFoundry", "OrnnsForge", "NoxkrayaArena"]]:
		for seed_value in SEEDS:
			var result := _play_fixed_lanes(seed_value, lane_set)
			var state: MatchState = result["state"]
			assert_true(int(result["iterations"]) < ITERATION_GUARD,
				"seed %d (%s) finished under the guard" % [seed_value, lane_set[0]])
			assert_eq(state.game_phase, MatchState.GamePhase.GAME_END,
				"seed %d (%s) reached GAME_END" % [seed_value, lane_set[0]])


## Every lane effect names a real lane, a real column and a non-empty effect.
func test_lane_effects_carry_their_lane_id() -> void:
	var result := _play_fixed_lanes(11, ["HexcoreFoundry", "OrnnsForge", "RockfallPath"])
	var seen_effects: Dictionary = {}
	for e: Dictionary in result["log"]:
		if e["type"] != MatchEvents.LANE_EFFECT:
			continue
		assert_true(int(e["col"]) >= 0 and int(e["col"]) < MatchState.COLUMNS,
			"lane_effect column in range")
		assert_true(LaneDatabase.LANES.has(str(e["lane_id"])),
			"lane_effect names a real lane: %s" % str(e["lane_id"]))
		assert_true(str(e["effect"]) != "", "lane_effect names its effect")
		seen_effects[str(e["effect"])] = true
	assert_true(seen_effects.has("hexcore_draw"), "Hexcore Foundry fired")
	assert_true(seen_effects.has("rockfall_chip"), "Rockfall Path fired")
	assert_true(seen_effects.has("ornn_forge"), "Ornn's Forge fired")


## Noxkraya Arena is turn 5 only: every play the bot submits that turn is in its column.
func test_noxkraya_holds_the_board_on_turn_five() -> void:
	var result := _play_fixed_lanes(5, ["RockfallPath", "SunkenTemple", "NoxkrayaArena"])
	# noxkraya_col is cleared again at every round end, so the column has to be read
	# off the event that activated it, not off the finished state.
	var noxkraya_col: int = -1
	for e: Dictionary in result["log"]:
		if e["type"] == MatchEvents.LANE_EFFECT and str(e["effect"]) == "noxkraya_active":
			noxkraya_col = int(e["col"])
	assert_true(noxkraya_col >= 0, "Noxkraya Arena activated")
	var turn: int = 0
	for e: Dictionary in result["log"]:
		if e["type"] == MatchEvents.TURN_STARTED:
			turn = int(e["turn"])
		elif e["type"] == MatchEvents.CARD_PLAYED and turn == 5:
			assert_eq(int(e["col"]), noxkraya_col,
				"turn 5 plays only happen in the Noxkraya column")
	var final_state: MatchState = result["state"]
	assert_eq(final_state.noxkraya_col, -1, "the restriction is cleared at round end")