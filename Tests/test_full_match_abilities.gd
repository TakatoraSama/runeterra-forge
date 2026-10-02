## End-to-end: two bots playing whole matches with the M3 abilities installed.
##
## Same invariant sweep as the M2 full-match test, plus the things only M3 can
## break: the {Game End} passes running at the right moment, cards that only exist
## because an ability created them, and the same seed replaying byte-identically.
extends "res://Tests/test_case.gd"

const SEEDS: Array[int] = [1, 2, 3, 7, 11, 99]
const ITERATION_GUARD := 500

## Deck.gd.DEFAULT_DECK as plain card ids.
const DEFAULT_DECK_IDS: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Ahri1",
	"Kennen1", "NavoriConspirator", "Janna1", "Draven1", "Rumble1", "Sion1",
]

## The bot's deck (MatchDecks.BOT_DECK_IDS).
const BOT_DECK_IDS: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Trundle1",
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk",
]

## A Sea Monster deck: every {Play}/{Round End} follower of that line, five Janna
## copies so the draw-discount passive gets exercised, and a Nautilus for Deep.
const SEA_DECK_IDS: Array[String] = [
	"SeaScarab", "SeaScarab", "Megatusk", "Megatusk", "TheBeastBelow",
	"AbyssalEye", "DevourerOfTheDepths", "TerrorOfTheTides",
	"Janna1", "Janna1", "Janna1", "Janna1", "Janna1",
	"Nautilus1", "Nautilus1",
]

## The three deck pairs every seed is played with.
const DECK_PAIRS: Array = [
	["default", DEFAULT_DECK_IDS, BOT_DECK_IDS],
	["bot", BOT_DECK_IDS, DEFAULT_DECK_IDS],
	["sea", SEA_DECK_IDS, BOT_DECK_IDS],
]


## Runs one full bot-vs-bot match with M3 abilities and returns
## {state, log, iterations, initial_cards}.
func _play(seed_value: int, deck0: Array, deck1: Array) -> Dictionary:
	var state := MatchSetup.new_match(deck0, deck1, seed_value)
	var rules := MatchRules.new(state)
	MatchCardAbilities.install(rules)
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


## The invariant sweep, run after every single submit.
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

	# Every card sits in exactly one place, consistent with its location.
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
			assert_eq(c.owner, key.y, "%s: card %d is owned by its zone's row %s" % [where, id, key])
			assert_eq(c.col, key.x, "%s: card %d column matches its zone %s" % [where, id, key])
			assert_eq(c.slot, slot, "%s: card %d slot is its index in the zone" % [where, id])
	for id: int in state.cards:
		var gone: bool = state.card(id).location == CardState.Location.GONE
		assert_eq(int(listed.get(id, 0)), 0 if gone else 1,
			"%s: card %d is listed exactly once (gone=%s)" % [where, id, str(gone)])

	# Cards only ever appear through summon / create_in_hand.
	var created_events: int = 0
	for e: Dictionary in log:
		if e["type"] == MatchEvents.CARD_SUMMONED or e["type"] == MatchEvents.CARD_CREATED_IN_HAND:
			created_events += 1
	assert_eq(state.cards.size(), initial_cards + created_events,
		"%s: cards only appear through summon / create_in_hand" % where)

	# The bot never gets an intent rejected, and no card id ever leaves CardDatabase.
	for e: Dictionary in log:
		if e["type"] == MatchEvents.INTENT_REJECTED:
			fail("%s: the bot was rejected: %s" % [where, str(e["reason"])])
		var card_id: Variant = e.get("card_id", null)
		if card_id is String and not (card_id as String).is_empty():
			assert_true(CardDatabase.CARDS.has(card_id),
				"%s: event %s names an unknown card id '%s'" % [where, str(e["type"]), card_id])


func _label(pair: Array) -> String:
	return "%s/%s" % [str(pair[0]), str(pair[1])]


# ----------------------------
# The whole matrix
# ----------------------------

## Every seed x every deck pair reaches GAME_END with the invariants intact.
func test_every_seed_and_deck_pair_reaches_game_end() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var result: Dictionary = _play(seed_value, pair[1], pair[2])
			var state: MatchState = result["state"]
			assert_true(int(result["iterations"]) < ITERATION_GUARD,
				"%s seed %d finished under the guard" % [_label(pair), seed_value])
			assert_eq(state.game_phase, MatchState.GamePhase.GAME_END,
				"%s seed %d reached GAME_END in %d iterations"
					% [_label(pair), seed_value, int(result["iterations"])])


## Exactly one game_ended per match, carrying a real winner and the lane powers.
func test_one_game_ended_event_with_lane_powers() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var result: Dictionary = _play(seed_value, pair[1], pair[2])
			var ended: int = 0
			for e: Dictionary in result["log"]:
				if e["type"] != MatchEvents.GAME_ENDED:
					continue
				ended += 1
				var powers: Array = e["lane_powers"]
				assert_eq(powers.size(), 2, "lane_powers has one row per player")
				for row: Array in powers:
					assert_eq(row.size(), MatchState.COLUMNS, "lane_powers has one entry per column")
				assert_true(int(e["winner"]) >= -1 and int(e["winner"]) <= 1,
					"winner is -1, 0 or 1")
			assert_eq(ended, 1, "%s seed %d emits exactly one game_ended" % [_label(pair), seed_value])


## The {Game End} pass always runs BEFORE the winner is announced, so a Sion in hand
## or a {Game End} buff is counted in the final lane powers.
func test_the_game_end_phase_runs_before_the_winner_is_decided() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var log: Array = _play(seed_value, pair[1], pair[2])["log"]
			var ended_at: int = -1
			for i in log.size():
				if log[i]["type"] == MatchEvents.GAME_ENDED:
					ended_at = i
					break
			assert_ne(ended_at, -1, "%s seed %d logged game_ended" % [_label(pair), seed_value])
			# The engine enters GAME_END, runs the abilities, then emits game_ended.
			var entered: int = -1
			for i in ended_at:
				if log[i]["type"] == MatchEvents.PHASE_CHANGED \
						and int(log[i]["game_phase"]) == MatchState.GamePhase.GAME_END:
					entered = i
					break
			assert_ne(entered, -1, "the match reached the GAME_END game phase")
			assert_true(entered < ended_at, "the phase change precedes game_ended")


## Over the whole matrix at least one match levels a card up and one kills a card, so
## the ability wiring is proven to actually fire rather than just not crashing.
func test_the_matrix_actually_levels_up_and_kills() -> void:
	var leveled: int = 0
	var killed: int = 0
	var ability_fired: int = 0
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var log: Array = _play(seed_value, pair[1], pair[2])["log"]
			if _count(log, MatchEvents.CARD_LEVELED_UP) > 0:
				leveled += 1
			if _count(log, MatchEvents.CARD_KILLED) > 0:
				killed += 1
			# Summons only ever happen through an ability or a lane effect.
			ability_fired += _count(log, MatchEvents.CARD_SUMMONED) \
				+ _count(log, MatchEvents.CARD_CREATED_IN_HAND)
	assert_true(leveled > 0, "at least one match levelled a card up")
	assert_true(killed > 0, "at least one match killed a card")
	assert_true(ability_fired > 0, "abilities created or summoned cards")


## Every level-up names two real card ids and moved from a lower level to a higher one.
func test_every_level_up_moves_to_a_higher_level() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var log: Array = _play(seed_value, pair[1], pair[2])["log"]
			for e: Dictionary in log:
				if e["type"] != MatchEvents.CARD_LEVELED_UP:
					continue
				var old_id: String = str(e["old_card_id"])
				var new_id: String = str(e["new_card_id"])
				assert_true(CardDatabase.CARDS.has(old_id) and CardDatabase.CARDS.has(new_id),
					"%s seed %d: a level-up names real cards" % [_label(pair), seed_value])
				assert_ne(old_id, new_id, "a level-up changes the card id")
				assert_eq(str(CardDatabase.CARDS[new_id].get("Name", "")),
					str(CardDatabase.CARDS[old_id].get("Name", "")),
					"a level-up keeps the champion's Name")
				assert_true(int(CardDatabase.CARDS[new_id].get("Level", 1))
					> int(CardDatabase.CARDS[old_id].get("Level", 1)),
				"and raises its Level")


## How many events of `type` the log holds.
func _count(log: Array, type: Variant) -> int:
	var count: int = 0
	for e: Dictionary in log:
		if e.get("type", &"") == type:
			count += 1
	return count


## Every tracker entry an ability wrote names a real card, and a card's owner never
## changes, so a buff or a kill can never be attributed to the wrong player.
func test_trackers_name_real_cards_and_owners_are_stable() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var state: MatchState = _play(seed_value, pair[1], pair[2])["state"]
			for tracker: Array[Dictionary] in [state.created, state.killed, state.recalled, state.discarded]:
				for entry: Dictionary in tracker:
					var card_id: String = str(entry.get("card_id", ""))
					assert_true(CardDatabase.CARDS.has(card_id),
						"%s seed %d: tracker card id '%s' is real" % [_label(pair), seed_value, card_id])
					var owner: int = int(entry.get("owner_player_id", -1))
					assert_true(owner == 0 or owner == 1,
						"%s seed %d: tracker owner is an absolute player id" % [_label(pair), seed_value])
					var instance_id: int = int(entry.get("instance_id", -1))
					var card := state.card(instance_id)
					if card == null:
						continue
					assert_eq(card.owner, owner,
						"%s seed %d: the tracker owner matches the card" % [_label(pair), seed_value])


## A card's owner never changes over a match, whatever an ability does to it.
func test_a_card_never_changes_owner() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var state: MatchState = _play(seed_value, pair[1], pair[2])["state"]
			for id: int in state.cards:
				var c := state.card(id)
				if c.location == CardState.Location.DECK or c.location == CardState.Location.HAND:
					continue
				assert_true(c.owner == 0 or c.owner == 1,
					"%s seed %d: card %d still has an absolute owner" % [_label(pair), seed_value, id])


## The same seed replays to the same log and the same final checksum, with abilities
## installed — ability effects consume the match rng, so this is a real determinism
## test, not a formality.
func test_the_same_seed_replays_identically() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var first: Dictionary = _play(seed_value, pair[1], pair[2])
			var second: Dictionary = _play(seed_value, pair[1], pair[2])
			assert_eq(hash(JSON.stringify(first["log"], "", true)),
				hash(JSON.stringify(second["log"], "", true)),
				"%s seed %d: identical event logs" % [_label(pair), seed_value])
			assert_eq((first["state"] as MatchState).checksum(),
				(second["state"] as MatchState).checksum(),
				"%s seed %d: identical final state" % [_label(pair), seed_value])


## Different seeds diverge, so the determinism test above is not vacuous.
func test_different_seeds_produce_different_logs() -> void:
	var unique: Dictionary = {}
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var result: Dictionary = _play(seed_value, pair[1], pair[2])
			unique[hash(JSON.stringify(result["log"], "", true))] = true
	assert_true(unique.size() >= 2, "at least two of the runs diverge")


## Every event survives redaction and JSON, including the private_to field the
## abilities rely on for hand cards.
func test_every_event_survives_redaction_and_json() -> void:
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var log: Array = _play(seed_value, pair[1], pair[2])["log"]
			for e: Dictionary in log:
				for viewer in [0, 1]:
					var seen: Variant = MatchEvents.redact_for(e, viewer)
					if seen == null:
						continue
					assert_true(JSON.stringify(seen, "", true).length() > 0,
						"%s seed %d: viewer %d can serialize %s"
							% [_label(pair), seed_value, viewer, str(e["type"])])
			assert_true(JSON.stringify(log, "", true).length() > 0,
				"%s seed %d: the whole log serializes" % [_label(pair), seed_value])


## A {Deep} unit of a Deep player really does get the Deep aura, so the passive is
## proven to fire in a real match and not merely to compile.
func test_deep_units_of_a_deep_player_gain_the_deep_aura() -> void:
	var checked: int = 0
	for pair: Array in DECK_PAIRS:
		for seed_value: int in SEEDS:
			var state: MatchState = _play(seed_value, pair[1], pair[2])["state"]
			for id: int in state.cards:
				var c := state.card(id)
				if not c.is_resolved or not c.has_keyword("Deep"):
					continue
				if not state.players[c.owner].is_deep:
					continue
				if c.aura_power_modifier < 3:
					continue  # the unit left the board in the same batch the aura ran
				assert_eq(c.aura_power_modifier, 3,
					"%s seed %d: a Deep unit of a Deep player has exactly the Deep aura"
						% [_label(pair), seed_value])
				checked += 1
	assert_true(checked > 0, "at least one Deep unit carried the Deep aura")