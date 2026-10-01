## Tests for MatchLanes: lane assignment, reveal timing, the five lane effects
## and the Noxkraya placement restriction.
##
## Most tests drive MatchLanes directly on a bare MatchState with a MatchOps that
## collects its events into an Array, so the lane rules can be checked without
## dragging the whole round loop in. The reveal timing through the real
## MatchRules (which calls lanes.on_round_start) is covered at the bottom.
extends "res://Tests/test_case.gd"

const LANE_HEXCORE := "HexcoreFoundry"
const LANE_ORNN := "OrnnsForge"
const LANE_SUNKEN := "SunkenTemple"
const LANE_NOXKRAYA := "NoxkrayaArena"
const LANE_ROCKFALL := "RockfallPath"

## A deck of plain 1-cost followers, cheap enough to keep mana maths out of the way.
const TEST_DECK: Array[String] = [
	"Ahri1", "Kennen1", "Nasus1", "Renekton1", "Xerath1",
	"Tryndamere1", "Draven1", "Rumble1", "Sion1", "Janna1",
]

var _state: MatchState
var _ops: MatchOps
var _lanes: MatchLanes
var _events: Array = []


func before_each() -> void:
	_events = []
	_state = MatchSetup.new_match(TEST_DECK, TEST_DECK, 1234)
	var abilities := MatchAbilities.new()
	_ops = MatchOps.new(_state, _on_event, abilities)
	abilities.bind(_state, _ops)
	_lanes = MatchLanes.new(_state, _ops)


func _on_event(event: Dictionary) -> void:
	_events.append(event)


## Every event of type `type_name` in the collected log.
func _of_type(type_name: StringName) -> Array:
	var out: Array = []
	for e: Dictionary in _events:
		if e["type"] == type_name:
			out.append(e)
	return out


## Index of the first event of type `type_name`, or -1.
func _first_index(type_name: StringName) -> int:
	for i in _events.size():
		if _events[i]["type"] == type_name:
			return i
	return -1


## Puts a card straight onto the board for `owner` in `col`, resolved or not.
func _put_on_board(card_id: String, owner: int, col: int, resolved: bool = true) -> CardState:
	var c := _state.new_card(card_id, owner, CardState.Location.HAND)
	_state.place_card(c.instance_id, col, owner)
	c.is_resolved = resolved
	return c


# --- Assignment ---

func test_assign_empty_picks_three_distinct_appearable_lanes() -> void:
	_lanes.assign([])
	assert_eq(_state.lane_ids.size(), MatchState.COLUMNS, "three lanes assigned")
	var unique: Dictionary = {}
	for lane_id: String in _state.lane_ids:
		unique[lane_id] = true
		assert_true(bool(LaneDatabase.LANES[lane_id].get("Appearable", false)),
			"%s is appearable" % lane_id)
	assert_eq(unique.size(), MatchState.COLUMNS, "the three lanes are distinct")


func test_assign_empty_is_deterministic_per_seed() -> void:
	_lanes.assign([])
	var first: Array = _state.lane_ids.duplicate()
	_state.rng.state = 0
	_state.rng.seed = 1234
	var second_state := MatchSetup.new_match(TEST_DECK, TEST_DECK, 1234)
	var second_ops := MatchOps.new(second_state, Callable(), MatchAbilities.new())
	var second_lanes := MatchLanes.new(second_state, second_ops)
	second_lanes.assign([])
	assert_eq(second_state.lane_ids, first, "same seed, same lanes")


func test_assign_uses_the_given_ids() -> void:
	_lanes.assign([LANE_ORNN, LANE_SUNKEN, LANE_NOXKRAYA])
	assert_eq(_state.lane_ids, [LANE_ORNN, LANE_SUNKEN, LANE_NOXKRAYA], "the given order is kept")
	assert_eq(_state.lane_revealed, [false, false, false], "nothing is revealed by assign")
	assert_eq(_state.noxkraya_col, -1, "no Noxkraya restriction yet")
	assert_eq(_of_type(MatchEvents.LANE_ASSIGNED).size(), 1, "one lane_assigned event")


func test_assign_resets_a_previous_assignment() -> void:
	_state.noxkraya_col = 1
	_state.lane_revealed = [true, true, true]
	_lanes.assign([LANE_ORNN, LANE_SUNKEN, LANE_NOXKRAYA])
	assert_eq(_state.lane_revealed, [false, false, false], "reveal flags reset")
	assert_eq(_state.noxkraya_col, -1, "Noxkraya cleared")


# --- Reveal ---

func test_reveal_emits_the_lane_and_only_once() -> void:
	_lanes.assign([LANE_ROCKFALL, LANE_ORNN, LANE_SUNKEN])
	_lanes.reveal(0)
	assert_eq(_state.lane_revealed[0], true, "column 0 revealed")
	assert_eq(_of_type(MatchEvents.LANE_REVEALED).size(), 1, "one lane_revealed so far")
	_lanes.reveal(0)
	assert_eq(_of_type(MatchEvents.LANE_REVEALED).size(), 1, "no double reveal")
	assert_eq(_state.lane_revealed, [true, false, false], "only column 0 revealed")


func test_on_round_start_reveals_columns_1_and_2_on_turns_2_and_3() -> void:
	_lanes.assign([LANE_ROCKFALL, LANE_ORNN, LANE_SUNKEN])
	_lanes.reveal(0)
	_lanes.on_round_start(1)
	assert_eq(_state.lane_revealed, [true, false, false], "column 1 waits for turn 2")
	_lanes.on_round_start(2)
	assert_eq(_state.lane_revealed, [true, true, false], "column 1 revealed on turn 2")
	_lanes.on_round_start(4)
	_lanes.on_round_start(5)
	assert_eq(_state.lane_revealed, [true, true, false], "column 2 waits for turn 3")
	_lanes.on_round_start(3)
	assert_eq(_state.lane_revealed, [true, true, true], "column 2 revealed on turn 3")
	var revealed: Array = _of_type(MatchEvents.LANE_REVEALED)
	assert_eq(revealed.size(), 3, "exactly three lane_revealed events")
	assert_eq(revealed[1]["col"], 1, "turn 2 reveals the middle column")
	assert_eq(revealed[2]["col"], 2, "turn 3 reveals the right column")


# --- Hexcore Foundry (on reveal) ---

func test_hexcore_foundry_draws_for_both_players_flip_first_first() -> void:
	_lanes.assign([LANE_HEXCORE, LANE_ORNN, LANE_SUNKEN])
	_state.flip_first = 1
	var hands_before: Array[int] = [_state.players[0].hand.size(), _state.players[1].hand.size()]
	_lanes.reveal(0)
	var drawn: Array = _of_type(MatchEvents.CARD_DRAWN)
	assert_eq(drawn.size(), 2, "both players draw one")
	assert_eq(int(drawn[0]["player"]), 1, "flip-first player draws first")
	assert_eq(int(drawn[1]["player"]), 0, "then the other player")
	assert_eq(_state.players[0].hand.size(), hands_before[0] + 1, "player 0 hand grew")
	assert_eq(_state.players[1].hand.size(), hands_before[1] + 1, "player 1 hand grew")
	assert_eq(_effect_event()[0]["effect"], "hexcore_draw", "effect name")


func test_hexcore_foundry_draw_order_defaults_to_0_then_1() -> void:
	_lanes.assign([LANE_HEXCORE, LANE_ORNN, LANE_SUNKEN])
	_state.flip_first = -1
	_lanes.reveal(0)
	var drawn: Array = _of_type(MatchEvents.CARD_DRAWN)
	assert_eq(int(drawn[0]["player"]), 0, "unset flip-first starts with player 0")


# --- Rockfall Path (on reveal) ---

func test_rockfall_path_summons_a_chip_for_both_players() -> void:
	_lanes.assign([LANE_ROCKFALL, LANE_ORNN, LANE_SUNKEN])
	_state.flip_first = 0
	_lanes.reveal(0)
	var summoned: Array = _of_type(MatchEvents.CARD_SUMMONED)
	assert_eq(summoned.size(), 2, "one Chip per player")
	assert_eq(int(summoned[0]["player"]), 0, "flip-first player first")
	assert_eq(int(summoned[1]["player"]), 1, "then the other player")
	for e: Dictionary in summoned:
		assert_eq(str(e["card_id"]), "Chip", "it is a Chip")
		assert_eq(int(e["col"]), 0, "in the revealed column")
	var chip0 := _state.card(int(summoned[0]["instance_id"]))
	var chip1 := _state.card(int(summoned[1]["instance_id"]))
	assert_eq(chip0.is_resolved, true, "a lane-summoned Chip is resolved")
	assert_eq(chip1.is_resolved, true, "a lane-summoned Chip is resolved")
	assert_eq(chip0.location, CardState.Location.BOARD, "on the board")
	assert_true(_state.play_order.has(chip0.instance_id), "play_order got the Chip")
	assert_eq(_state.summoned.size(), 2, "two summoned trackers")
	assert_eq(_state.created.size(), 2, "two created trackers")
	assert_eq(int(_state.created[0]["creator_player_id"]), -1, "created by the lane")
	assert_eq(_effect_event()[0]["effect"], "rockfall_chip", "effect name")


func test_rockfall_path_skips_a_full_zone() -> void:
	_lanes.assign([LANE_ROCKFALL, LANE_ORNN, LANE_SUNKEN])
	for i in MatchState.SLOTS_PER_ZONE:
		_put_on_board("Nasus1", 0, 0)
	_lanes.reveal(0)
	assert_eq(_state.zone_cards(0, 0).size(), MatchState.SLOTS_PER_ZONE, "player 0's zone is untouched")
	var summoned: Array = _of_type(MatchEvents.CARD_SUMMONED)
	assert_eq(summoned.size(), 1, "only the player with room gets a Chip")
	assert_eq(int(summoned[0]["player"]), 1, "player 1 has room")


# --- Ornn's Forge (round end, turn 4) ---

func test_ornns_forge_boosts_resolved_units_in_that_column_on_turn_4() -> void:
	_lanes.assign([LANE_ORNN, LANE_SUNKEN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	var hit := _put_on_board("Nasus1", 0, 0, true)
	var hit2 := _put_on_board("Ahri1", 1, 0, true)
	var unresolved := _put_on_board("Kennen1", 0, 0, false)
	var other_col := _put_on_board("Nasus1", 0, 1, true)
	var base: int = hit.get_current_power()
	var base2: int = hit2.get_current_power()
	var base_unresolved: int = unresolved.get_current_power()
	var base_other: int = other_col.get_current_power()
	_lanes.on_round_end(3)
	assert_eq(hit.get_current_power(), base, "nothing happens on turn 3")
	assert_false(_has_effect("ornn_forge"), "Ornn's Forge does not fire on turn 3")
	_lanes.on_round_end(4)
	assert_eq(hit.get_current_power(), base + 1, "resolved unit got +1")
	assert_eq(hit2.get_current_power(), base2 + 1, "the opponent's unit was boosted too")
	assert_eq(int(unresolved.power_modifier), 0, "an unresolved unit gets nothing")
	assert_eq(other_col.get_current_power(), base_other, "units in other columns are untouched")
	assert_true(_has_effect("ornn_forge"), "Ornn's Forge announced itself")
	assert_true(_has_effect("sunken_temple"), "Sunken Temple fired on turn 3 as well")


func test_ornns_forge_ignores_non_units() -> void:
	_lanes.assign([LANE_ORNN, LANE_SUNKEN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	var landmark := _put_on_board("BuriedSunDisc", 0, 0, true)
	var spell := _put_on_board("SpinningAxe", 0, 0, true)
	_lanes.on_round_end(4)
	assert_eq(int(landmark.power_modifier), 0, "a landmark is not a unit")
	assert_eq(int(spell.power_modifier), 0, "a spell is not a unit")


# --- Sunken Temple (round end, turn 3) ---

func test_sunken_temple_keeps_hand_and_deck_size() -> void:
	_lanes.assign([LANE_SUNKEN, LANE_ORNN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	# Give both players a hand.
	_ops.draw(0)
	_ops.draw(0)
	_ops.draw(1)
	var hands: Array[int] = [_state.players[0].hand.size(), _state.players[1].hand.size()]
	var decks: Array[int] = [_state.players[0].deck.size(), _state.players[1].deck.size()]
	assert_true(hands[0] > 0 and hands[1] > 0, "both hands are non-empty")
	_lanes.on_round_end(3)
	for p in 2:
		assert_eq(_state.players[p].hand.size(), hands[p], "player %d hand size unchanged" % p)
		assert_eq(_state.players[p].deck.size(), decks[p], "player %d deck size unchanged" % p)
	assert_eq(_of_type(MatchEvents.CARD_SHUFFLED_INTO_DECK).size(), 2, "one shuffle-in per player")
	var shuffled: Array = _of_type(MatchEvents.CARD_SHUFFLED_INTO_DECK)
	for e: Dictionary in shuffled:
		var id: int = int(e["instance_id"])
		assert_eq(_state.card(id).location, CardState.Location.DECK, "the card went back into the deck")
	assert_eq(_effect_event()[0]["effect"], "sunken_temple", "effect name")


func test_sunken_temple_with_an_empty_hand_only_draws() -> void:
	_lanes.assign([LANE_SUNKEN, LANE_ORNN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	for p in 2:
		_state.players[p].hand.clear()
	var decks: Array[int] = [_state.players[0].deck.size(), _state.players[1].deck.size()]
	_lanes.on_round_end(3)
	assert_eq(_of_type(MatchEvents.CARD_SHUFFLED_INTO_DECK).size(), 0, "nothing to shuffle back")
	assert_eq(_of_type(MatchEvents.CARD_DRAWN).size(), 2, "both players still draw")
	for p in 2:
		assert_eq(_state.players[p].hand.size(), 1, "player %d drew one" % p)
		assert_eq(_state.players[p].deck.size(), decks[p] - 1, "player %d deck shrank by one" % p)


# --- Noxkraya Arena ---

func test_noxkraya_restricts_placement_only_on_turn_5() -> void:
	_lanes.assign([LANE_ROCKFALL, LANE_ORNN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	for turn in [1, 2, 3, 4]:
		_lanes.on_round_start(turn)
		assert_eq(_state.noxkraya_col, -1, "no restriction on turn %d" % turn)
		for col in MatchState.COLUMNS:
			assert_false(_lanes.is_restricted(col), "turn %d column %d is open" % [turn, col])
	_lanes.on_round_start(5)
	assert_eq(_state.noxkraya_col, 2, "Noxkraya is in column 2")
	assert_false(_lanes.is_restricted(2), "its own column stays open")
	assert_true(_lanes.is_restricted(0), "column 0 is restricted")
	assert_true(_lanes.is_restricted(1), "column 1 is restricted")
	_lanes.on_round_end(5)
	assert_eq(_state.noxkraya_col, -1, "cleared at round end")
	for col in MatchState.COLUMNS:
		assert_false(_lanes.is_restricted(col), "column %d is open again" % col)


func test_noxkraya_leaves_other_lanes_alone() -> void:
	_lanes.assign([LANE_ORNN, LANE_NOXKRAYA, LANE_SUNKEN])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	_lanes.on_round_start(5)
	assert_eq(_state.noxkraya_col, 1, "Noxkraya is in column 1")
	assert_true(_lanes.is_restricted(0), "column 0 restricted")
	assert_false(_lanes.is_restricted(1), "column 1 open")
	assert_eq(_effect_event()[0]["effect"], "noxkraya_active", "effect name")


func test_is_restricted_is_false_without_noxkraya() -> void:
	_lanes.assign([LANE_ORNN, LANE_SUNKEN, LANE_ROCKFALL])
	for col in MatchState.COLUMNS:
		assert_false(_lanes.is_restricted(col), "column %d open" % col)


# --- Event order: every effect announces itself first ---

func test_every_effect_emits_lane_effect_before_it_acts() -> void:
	# Hexcore Foundry draws.
	_lanes.assign([LANE_HEXCORE, LANE_ORNN, LANE_SUNKEN])
	_lanes.reveal(0)
	assert_effect_precedes("hexcore_draw", MatchEvents.CARD_DRAWN)

	# Rockfall Path summons.
	_lanes.assign([LANE_ROCKFALL, LANE_ORNN, LANE_SUNKEN])
	_lanes.reveal(0)
	assert_effect_precedes("rockfall_chip", MatchEvents.CARD_SUMMONED)

	# Ornn's Forge changes power.
	_lanes.assign([LANE_ORNN, LANE_SUNKEN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	_put_on_board("Nasus1", 0, 0, true)
	_lanes.on_round_end(4)
	assert_effect_precedes("ornn_forge", MatchEvents.POWER_CHANGED)

	# Sunken Temple shuffles a hand card back.
	_lanes.assign([LANE_SUNKEN, LANE_ORNN, LANE_NOXKRAYA])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	_lanes.on_round_end(3)
	assert_effect_precedes("sunken_temple", MatchEvents.CARD_SHUFFLED_INTO_DECK)

	# Noxkraya Arena announces itself before the restriction applies.
	_lanes.assign([LANE_ORNN, LANE_NOXKRAYA, LANE_SUNKEN])
	for col in MatchState.COLUMNS:
		_lanes.reveal(col)
	_lanes.on_round_start(5)
	# Noxkraya has no follow-up event of its own: the announcement IS the effect, so
	# it must still be logged, with the lane it came from.
	assert_true(_has_effect("noxkraya_active"), "Noxkraya Arena announced itself")


## The lane_effect events emitted so far.
func _effect_event() -> Array:
	return _of_type(MatchEvents.LANE_EFFECT)


## True when a lane_effect carrying `effect` has been emitted.
func _has_effect(effect: String) -> bool:
	for e: Dictionary in _effect_event():
		if str(e.get("effect", "")) == effect:
			return true
	return false


## Fails unless the LANE_EFFECT carrying `effect` is logged before the first
## event of type `acted_with`.
func assert_effect_precedes(effect: String, acted_with: StringName) -> void:
	var effect_index: int = -1
	for i in _events.size():
		if _events[i]["type"] == MatchEvents.LANE_EFFECT and _events[i].get("effect", "") == effect:
			effect_index = i
			break
	assert_true(effect_index >= 0, "a lane_effect '%s' was emitted" % effect)
	var acted: int = _first_index(acted_with)
	if acted < 0:
		return
	assert_true(effect_index < acted, "'%s' is announced before %s" % [effect, acted_with])


func test_lane_name_matches_the_database() -> void:
	_lanes.assign([LANE_HEXCORE, LANE_ORNN, LANE_NOXKRAYA])
	assert_eq(_lanes.lane_name(0), "Hexcore Foundry")
	assert_eq(_lanes.lane_name(1), "Ornn's Forge")
	assert_eq(_lanes.lane_name(2), "Noxkraya Arena")
	assert_eq(_lanes.lane_name(3), "", "no lane in column 3")


# --- Through MatchRules: the reveal timing of the real round loop ---


## The lanes reveal in the documented order when the real round loop drives them.
func test_reveal_timing_through_match_rules() -> void:
	var state := MatchSetup.new_match(TEST_DECK, TEST_DECK, 777)
	var rules := MatchRules.new(state)
	var log: Array = rules.start_match([LANE_ROCKFALL, LANE_ORNN, LANE_SUNKEN])
	assert_eq(state.lane_revealed, [true, false, false], "only the left lane is revealed at the start")
	var revealed_at_start: int = 0
	for e: Dictionary in log:
		if e["type"] == MatchEvents.LANE_REVEALED:
			revealed_at_start += 1
	assert_eq(revealed_at_start, 1, "exactly one reveal during start_match")

	# Both players end their turn -> turn 2 starts and reveals the middle lane.
	log = rules.submit(0, MatchIntents.end_turn())
	log += rules.submit(1, MatchIntents.end_turn())
	assert_eq(state.turn, 2, "turn 2")
	assert_eq(state.lane_revealed, [true, true, false], "middle lane revealed on turn 2")

	# Turn 2 -> 3 reveals the right lane.
	rules.submit(0, MatchIntents.end_turn())
	rules.submit(1, MatchIntents.end_turn())
	assert_eq(state.turn, 3, "turn 3")
	assert_eq(state.lane_revealed, [true, true, true], "right lane revealed on turn 3")

	# No further reveals in the rest of the match.
	var guard: int = 0
	while state.game_phase == MatchState.GamePhase.TURN_LOOP and guard < 40:
		rules.submit(0, MatchIntents.end_turn())
		rules.submit(1, MatchIntents.end_turn())
		guard += 1
	assert_eq(state.turn, MatchRules.MAX_TURNS, "the match ran all rounds")
	assert_eq(state.game_phase, MatchState.GamePhase.GAME_END, "the match ended")