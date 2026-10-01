## Tests for the protocol layer: MatchEvents, MatchIntents, MatchRules, MatchSetup.
extends "res://Tests/test_case.gd"


# --- MatchEvents: one static constructor per type, with the listed fields ---

func test_event_turn_started() -> void:
	var e := MatchEvents.turn_started(3)
	assert_eq(e["type"], MatchEvents.TURN_STARTED, "type key")
	assert_eq(e["turn"], 3, "turn payload")


func test_event_phase_changed() -> void:
	var e := MatchEvents.phase_changed(1, 2, 4)
	assert_eq(e["type"], MatchEvents.PHASE_CHANGED)
	assert_eq(e["game_phase"], 1)
	assert_eq(e["round_phase"], 2)
	assert_eq(e["turn"], 4)


func test_event_mana_changed() -> void:
	var e := MatchEvents.mana_changed(1, 4, 5)
	assert_eq(e["type"], MatchEvents.MANA_CHANGED)
	assert_eq(e["player"], 1)
	assert_eq(e["current"], 4)
	assert_eq(e["max"], 5)


func test_event_lane_assigned() -> void:
	var e := MatchEvents.lane_assigned(["A", "B", "C"])
	assert_eq(e["type"], MatchEvents.LANE_ASSIGNED)
	assert_eq(e["lane_ids"], ["A", "B", "C"])


func test_event_card_drawn() -> void:
	var e := MatchEvents.card_drawn(0, 7, "Azir1")
	assert_eq(e["type"], MatchEvents.CARD_DRAWN)
	assert_eq(e["player"], 0)
	assert_eq(e["instance_id"], 7)
	assert_eq(e["card_id"], "Azir1")


func test_event_card_created_in_hand() -> void:
	var e := MatchEvents.card_created_in_hand(1, 9, "Nasus1", 4)
	assert_eq(e["type"], MatchEvents.CARD_CREATED_IN_HAND)
	assert_eq(e["player"], 1)
	assert_eq(e["instance_id"], 9)
	assert_eq(e["card_id"], "Nasus1")
	assert_eq(e["creator_instance_id"], 4)


func test_event_card_played() -> void:
	var e := MatchEvents.card_played(1, 12, "Xerath1", 2, 3)
	assert_eq(e["type"], MatchEvents.CARD_PLAYED)
	assert_eq(e["player"], 1)
	assert_eq(e["instance_id"], 12)
	assert_eq(e["card_id"], "Xerath1")
	assert_eq(e["col"], 2)
	assert_eq(e["slot"], 3)


func test_event_play_undone() -> void:
	var e := MatchEvents.play_undone(0, [3, 4])
	assert_eq(e["type"], MatchEvents.PLAY_UNDONE)
	assert_eq(e["player"], 0)
	assert_eq(e["instance_ids"], [3, 4])


func test_event_swap_started() -> void:
	var e := MatchEvents.swap_started(1, 5, 0, 1)
	assert_eq(e["type"], MatchEvents.SWAP_STARTED)
	assert_eq(e["player"], 1)
	assert_eq(e["instance_id"], 5)
	assert_eq(e["from_col"], 0)
	assert_eq(e["to_col"], 1)


func test_event_card_swapped() -> void:
	var e := MatchEvents.card_swapped(0, 5, 2, 0, 1)
	assert_eq(e["type"], MatchEvents.CARD_SWAPPED)
	assert_eq(e["from_col"], 2)
	assert_eq(e["to_col"], 0)
	assert_eq(e["slot"], 1)


func test_event_intent_rejected() -> void:
	var e := MatchEvents.intent_rejected(1, "play_card", "malformed")
	assert_eq(e["type"], MatchEvents.INTENT_REJECTED)
	assert_eq(e["player"], 1)
	assert_eq(e["intent_type"], "play_card")
	assert_eq(e["reason"], "malformed")


func test_event_card_killed() -> void:
	var e := MatchEvents.card_killed(11, 0, 6)
	assert_eq(e["type"], MatchEvents.CARD_KILLED)
	assert_eq(e["instance_id"], 11)
	assert_eq(e["killer_player"], 0)
	assert_eq(e["killer_instance_id"], 6)


func test_event_card_leveled_up() -> void:
	var e := MatchEvents.card_leveled_up(8, "Azir1", "Azir2")
	assert_eq(e["type"], MatchEvents.CARD_LEVELED_UP)
	assert_eq(e["old_card_id"], "Azir1")
	assert_eq(e["new_card_id"], "Azir2")


func test_event_deep_changed() -> void:
	var e := MatchEvents.deep_changed(1, true)
	assert_eq(e["type"], MatchEvents.DEEP_CHANGED)
	assert_eq(e["player"], 1)
	assert_true(e["is_deep"], "is_deep payload")


func test_event_game_ended() -> void:
	var e := MatchEvents.game_ended(0, [[3, 1, 0], [2, 2, 5]])
	assert_eq(e["type"], MatchEvents.GAME_ENDED)
	assert_eq(e["winner"], 0, "winner")
	assert_eq(e["lane_powers"], [[3, 1, 0], [2, 2, 5]], "lane powers grid")
	var tie := MatchEvents.game_ended(-1, [[0, 0, 0], [0, 0, 0]])
	assert_eq(tie["winner"], -1, "tie uses -1")


# --- MatchEvents.redact_for ---

func test_redact_hides_opponent_plays_entirely() -> void:
	for event: Dictionary in [
		MatchEvents.card_played(1, 5, "Azir1", 0, 0),
		MatchEvents.play_undone(1, [5, 6]),
		MatchEvents.swap_started(1, 5, 0, 2),
	]:
		assert_eq(MatchEvents.redact_for(event, 0), null, "opponent event must not be sent to player 0")


func test_redact_keeps_own_plays() -> void:
	for event: Dictionary in [
		MatchEvents.card_played(0, 5, "Azir1", 0, 0),
		MatchEvents.play_undone(0, [5, 6]),
		MatchEvents.swap_started(0, 5, 0, 2),
	]:
		assert_eq(MatchEvents.redact_for(event, 0), event, "owner sees the event unchanged")


func test_redact_strips_opponent_card_id() -> void:
	var drawn := MatchEvents.card_drawn(1, 5, "Azir1")
	var seen: Variant = MatchEvents.redact_for(drawn, 0)
	assert_true(seen is Dictionary, "draw is still sent, only anonymised")
	assert_false(seen.has("card_id"), "opponent card_id is hidden")
	assert_eq(seen["instance_id"], 5, "instance id stays so counts line up")
	assert_eq(seen["player"], 1, "player stays")

	var created := MatchEvents.card_created_in_hand(1, 5, "Azir1", 3)
	var seen2: Variant = MatchEvents.redact_for(created, 0)
	assert_false(seen2.has("card_id"), "opponent created card_id is hidden")
	assert_eq(seen2["creator_instance_id"], 3, "rest of the payload stays")

	assert_true(MatchEvents.redact_for(drawn, 1).has("card_id"), "owner keeps card_id")
	assert_true(MatchEvents.redact_for(created, 1).has("card_id"), "owner keeps card_id")


func test_redact_passes_other_events_unchanged() -> void:
	for event: Dictionary in [
		MatchEvents.game_ended(0, [[1, 0, 0], [0, 0, 0]]),
		MatchEvents.card_revealed(1, 5, "Azir1", 0, 0),
		MatchEvents.card_killed(5, 1, 6),
		MatchEvents.lane_revealed(0, "A"),
		MatchEvents.turn_started(2),
	]:
		assert_eq(MatchEvents.redact_for(event, 0), event, "unrelated event is passed through as-is")


func test_redact_does_not_mutate_input() -> void:
	var drawn := MatchEvents.card_drawn(1, 5, "Azir1")
	var snapshot := drawn.duplicate(true)
	var out: Variant = MatchEvents.redact_for(drawn, 0)
	assert_eq(drawn, snapshot, "input untouched")
	out["player"] = 999
	assert_eq(drawn, snapshot, "result is a copy, not the input")


# --- MatchIntents.is_well_formed: the happy paths ---

func test_intents_constructors() -> void:
	var play := MatchIntents.play_card(4, 1)
	assert_eq(play["type"], MatchIntents.PLAY_CARD)
	assert_eq(play["instance_id"], 4)
	assert_eq(play["col"], 1)
	assert_eq(play["slot"], -1, "slot defaults to -1 = any free slot")
	var swap := MatchIntents.swap_card(4, 2)
	assert_eq(swap["type"], MatchIntents.SWAP_CARD)
	assert_eq(swap["to_col"], 2)
	assert_eq(MatchIntents.undo()["type"], MatchIntents.UNDO)
	assert_eq(MatchIntents.end_turn()["type"], MatchIntents.END_TURN)


func test_well_formed_accepts_valid_intents() -> void:
	assert_true(MatchIntents.is_well_formed(MatchIntents.play_card(0, 0, 0)), "lowest legal play")
	assert_true(MatchIntents.is_well_formed(MatchIntents.play_card(99, 2, 3)), "highest legal play")
	assert_true(MatchIntents.is_well_formed(MatchIntents.play_card(1, MatchState.SPELL_COL, 2)), "spell zone column")
	assert_true(MatchIntents.is_well_formed(MatchIntents.swap_card(3, 0)), "swap to col 0")
	assert_true(MatchIntents.is_well_formed(MatchIntents.swap_card(3, 2)), "swap to col 2")
	assert_true(MatchIntents.is_well_formed(MatchIntents.undo()), "undo")
	assert_true(MatchIntents.is_well_formed(MatchIntents.end_turn()), "end_turn")


func test_well_formed_accepts_integral_floats() -> void:
	# JSON has no int type, so every number arrives as a float.
	assert_true(MatchIntents.is_well_formed({"type": "play_card", "instance_id": 4.0, "col": 1.0, "slot": 2.0}))
	assert_true(MatchIntents.is_well_formed({"type": "swap_card", "instance_id": 4.0, "to_col": 2.0}))


# --- MatchIntents.is_well_formed: every rejection ---

func test_well_formed_rejects_non_dictionaries() -> void:
	for bad: Variant in [null, 5, "play_card", [1, 2, 3], true]:
		assert_false(MatchIntents.is_well_formed(bad), "non-Dictionary rejected")


func test_well_formed_rejects_bad_type() -> void:
	assert_false(MatchIntents.is_well_formed({}), "missing type")
	assert_false(MatchIntents.is_well_formed({"type": "teleport"}), "unknown type")
	assert_false(MatchIntents.is_well_formed({"type": 7}), "non-string type")
	assert_false(MatchIntents.is_well_formed({"type": null}), "null type")


func test_well_formed_rejects_missing_keys() -> void:
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "instance_id": 1, "col": 0}), "play without slot")
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "col": 0, "slot": 0}), "play without instance_id")
	assert_false(MatchIntents.is_well_formed({"type": "swap_card", "instance_id": 1}), "swap without to_col")
	assert_false(MatchIntents.is_well_formed({"type": "swap_card", "to_col": 1}), "swap without instance_id")


func test_well_formed_rejects_non_numbers() -> void:
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "instance_id": "4", "col": 0, "slot": 0}), "string instance_id")
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "instance_id": 4, "col": "0", "slot": 0}), "string col")
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "instance_id": 4, "col": 0, "slot": null}), "null slot")
	assert_false(MatchIntents.is_well_formed({"type": "swap_card", "instance_id": 4, "to_col": false}), "bool to_col")


func test_well_formed_rejects_fractional_floats() -> void:
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "instance_id": 4.5, "col": 0.0, "slot": 0.0}), "fractional id")
	assert_false(MatchIntents.is_well_formed({"type": "play_card", "instance_id": 4.0, "col": 0.5, "slot": 0.0}), "fractional col")
	assert_false(MatchIntents.is_well_formed({"type": "swap_card", "instance_id": 4.0, "to_col": 1.25}), "fractional to_col")


func test_well_formed_rejects_out_of_range() -> void:
	assert_false(MatchIntents.is_well_formed(MatchIntents.play_card(1, 3)), "col 3 is not a lane")
	assert_false(MatchIntents.is_well_formed(MatchIntents.play_card(1, -2)), "col below the spell zone sentinel")
	assert_false(MatchIntents.is_well_formed(MatchIntents.play_card(1, 0, 4)), "slot 4 is not a board slot")
	assert_false(MatchIntents.is_well_formed(MatchIntents.play_card(1, 0, -2)), "slot below -1")
	assert_false(MatchIntents.is_well_formed(MatchIntents.swap_card(1, 3)), "to_col 3 is not a lane")
	assert_false(MatchIntents.is_well_formed(MatchIntents.swap_card(1, -1)), "to_col cannot be the spell column")
	assert_false(MatchIntents.is_well_formed(MatchIntents.play_card(-1, 0)), "negative instance_id")
	assert_false(MatchIntents.is_well_formed(MatchIntents.swap_card(-2, 1)), "negative instance_id")


# --- MatchRules.submit ---

func test_rules_rejects_bad_player() -> void:
	var rules := MatchRules.new(MatchState.new())
	var events := rules.submit(2, MatchIntents.play_card(1, 0))
	assert_eq(events.size(), 1, "one rejection")
	assert_eq(events[0]["type"], MatchEvents.INTENT_REJECTED)
	assert_eq(events[0]["player"], 2)
	assert_eq(events[0]["intent_type"], "play_card")
	assert_eq(events[0]["reason"], "bad_player")


func test_rules_rejects_malformed() -> void:
	var rules := MatchRules.new(MatchState.new())
	var events := rules.submit(0, {"type": "play_card", "instance_id": 1, "col": 0})
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], MatchEvents.INTENT_REJECTED)
	assert_eq(events[0]["reason"], "malformed")
	var garbage := rules.submit(0, "nonsense")
	assert_eq(garbage.size(), 1, "garbage is rejected, not crashed on")
	assert_eq(garbage[0]["reason"], "malformed")
	assert_eq(garbage[0]["intent_type"], "", "non-dictionary intents report an empty type")


func test_rules_rejects_wrong_phase() -> void:
	var state := MatchState.new()
	assert_eq(state.game_phase, MatchState.GamePhase.GAME_START, "a fresh state is still in GAME_START")
	var rules := MatchRules.new(state)
	var events := rules.submit(0, MatchIntents.play_card(1, 0))
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], MatchEvents.INTENT_REJECTED)
	assert_eq(events[0]["reason"], "wrong_phase")
	assert_eq(events[0]["intent_type"], "play_card")


func test_rules_accepts_valid_intent_in_play_phase() -> void:
	var state := MatchState.new()
	state.game_phase = MatchState.GamePhase.TURN_LOOP
	state.round_phase = MatchState.RoundPhase.PLAY
	var rules := MatchRules.new(state)
	assert_eq(rules.submit(0, MatchIntents.play_card(1, 0)), [], "M1 accepts the play without acting on it")
	assert_eq(rules.submit(1, MatchIntents.end_turn()), [], "M1 accepts end_turn")
	assert_eq(rules.submit(1, MatchIntents.undo()), [], "M1 accepts undo")
	assert_eq(rules.submit(1, MatchIntents.swap_card(1, 1)), [], "M1 accepts swap_card")


func test_rules_advance_is_a_noop_in_m1() -> void:
	var rules := MatchRules.new(MatchState.new())
	assert_eq(rules.advance(), [], "advance does nothing yet")


# --- MatchSetup smoke test ---

func test_setup_builds_two_decks() -> void:
	var deck := ["Azir1", "Nasus1", "Ahri1", "Kennen1"]
	var state := MatchSetup.new_match(deck, deck, 12345)
	assert_true(state is MatchState, "returns a MatchState")
	assert_eq(state.players.size(), 2)
	assert_eq(state.players[0].deck.size(), 4, "player 0 got the whole deck")
	assert_eq(state.players[1].deck.size(), 4, "player 1 got the whole deck")
	assert_eq(state.game_phase, MatchState.GamePhase.GAME_START)
	assert_eq(state.turn, 0)
	# Same decks + same seed must give the same shuffle. The two players hold different
	# instance ids, so compare the card order instead of the raw id lists.
	var again := MatchSetup.new_match(deck, deck, 12345)
	assert_eq(_deck_order(state.players[0].deck, state), _deck_order(again.players[0].deck, again), "same decks and seed shuffle identically")
	# The whole state must be reproducible too, not just the deck order.
	assert_eq(state.checksum(), again.checksum(), "same decks and seed give the same checksum")
	var other_seed := MatchSetup.new_match(deck, deck, 999)
	assert_eq(other_seed.players[0].deck.size(), 4, "a different seed still builds a full deck")


## A deck's order expressed as card ids, which is comparable across two MatchStates.
func _deck_order(deck: Array[int], state: MatchState) -> Array:
	var out: Array = []
	for id in deck:
		out.append(state.card(id).card_id)
	return out
