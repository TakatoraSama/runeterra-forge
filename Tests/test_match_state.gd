extends "res://Tests/test_case.gd"

## MatchState — zones, hands, drawing and the JSON round trip / checksum.

const CARD := "Kennen1"


func _new_card(state: MatchState, owner: int, location: int = 0) -> CardState:
	# 0 == CardState.Location.DECK (an enum member cannot be a default argument).
	return state.new_card(CARD, owner, location)


func test_init_creates_two_players() -> void:
	var state := MatchState.new()
	assert_eq(state.players.size(), 2, "two players")
	assert_eq(state.next_instance_id, 1, "ids start at 1")
	assert_eq(state.turn, 0, "no turn yet")
	assert_eq(state.game_phase, MatchState.GamePhase.GAME_START, "GAME_START")
	assert_eq(state.round_phase, MatchState.RoundPhase.NONE, "ROUND_PHASE NONE")
	assert_true(_board_is_empty(state), "no card on the board yet")


## Every lane/spell zone of both players holds no cards. (The zones dictionary
## may or may not pre-create its entries; the contract does not say.)
func _board_is_empty(state: MatchState) -> bool:
	for owner in 2:
		for col in 3:
			if not state.zone_cards(col, owner).is_empty():
				return false
		if not state.zone_cards(MatchState.SPELL_COL, owner).is_empty():
			return false
	return true


func test_new_card_assigns_increasing_unique_ids() -> void:
	var state := MatchState.new()
	var ids: Array[int] = []
	for i in 12:
		var card := _new_card(state, i % 2, CardState.Location.DECK)
		assert_eq(card.owner, i % 2, "owner %d" % i)
		assert_eq(card.location, CardState.Location.DECK, "location %d" % i)
		ids.append(card.instance_id)
	assert_eq(ids, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], "sequential ids")
	assert_eq(state.cards.size(), 12, "all registered")
	assert_eq(state.next_instance_id, 13, "next id")
	var unique := {}
	for id in ids:
		unique[id] = true
	assert_eq(unique.size(), 12, "ids are unique")
	assert_eq(state.card(1).instance_id, 1, "card() lookup")
	assert_eq(state.card(999), null, "unknown id")


func test_place_card_appends_and_sets_fields() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	assert_true(state.place_card(a.instance_id, 0, 0), "first place")
	assert_true(state.place_card(b.instance_id, 0, 0), "second place appends")
	assert_eq(state.zone_cards(0, 0), [a.instance_id, b.instance_id], "zone order")
	assert_eq(a.location, CardState.Location.BOARD, "a is on the board")
	assert_eq(a.col, 0, "a col")
	assert_eq(a.slot, 0, "a slot")
	assert_eq(b.slot, 1, "b slot")


func test_place_card_at_a_slot_inserts_and_shifts() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	var c := _new_card(state, 0)
	state.place_card(a.instance_id, 1, 0)
	state.place_card(b.instance_id, 1, 0)
	assert_true(state.place_card(c.instance_id, 1, 0, 0), "insert at front")
	assert_eq(state.zone_cards(1, 0), [c.instance_id, a.instance_id, b.instance_id], "c pushed in front")
	assert_eq(c.slot, 0, "c slot")
	assert_eq(a.slot, 1, "a shifted down")
	assert_eq(b.slot, 2, "b shifted down")
	assert_eq(state.zone_cards(1, 0).size(), 3, "still three cards, no duplicate")


func test_place_card_beyond_the_end_appends() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	state.place_card(a.instance_id, 2, 0)
	assert_true(state.place_card(b.instance_id, 2, 0, 9), "slot clamps to the size")
	assert_eq(state.zone_cards(2, 0), [a.instance_id, b.instance_id], "appended")
	assert_eq(b.slot, 1, "last slot")



## Fills zone (col, owner) with `count` fresh player-`owner` cards and returns
## their instance ids, in slot order.
func _fill_zone(state: MatchState, col: int, owner: int, count: int) -> Array[int]:
	var ids: Array[int] = []
	for _i in count:
		var card := _new_card(state, owner)
		state.place_card(card.instance_id, col, owner)
		ids.append(card.instance_id)
	return ids


func test_place_card_rejects_an_owner_mismatch() -> void:
	var state := MatchState.new()
	var on_board := _new_card(state, 0)
	var idle := _new_card(state, 0)
	state.place_card(on_board.instance_id, 0, 0)
	var before := state.zone_cards(0, 0)

	# A card of player 0 must never end up in player 1's zone: remove_from_zone()
	# would look it up in (col, card.owner) and never find it again.
	assert_false(state.place_card(idle.instance_id, 0, 1), "idle card, wrong owner")
	assert_eq(idle.location, CardState.Location.DECK, "rejected card keeps its location")
	assert_eq(idle.col, -1, "rejected card keeps its col")
	assert_eq(idle.slot, -1, "rejected card keeps its slot")

	assert_false(state.place_card(on_board.instance_id, 1, 1), "placed card moved to the wrong owner")
	assert_eq(on_board.location, CardState.Location.BOARD, "still on the board")
	assert_eq(on_board.col, 0, "still in its own column")
	assert_eq(on_board.slot, 0, "still in its own slot")

	assert_eq(state.zone_cards(0, 0), before, "the real zone is untouched")
	assert_eq(state.zone_cards(0, 1).is_empty(), true, "the other player's zone stays empty")
	assert_eq(state.zone_cards(1, 1).is_empty(), true, "no zone was created for the wrong owner")


func test_place_card_rejects_an_invalid_column() -> void:
	var state := MatchState.new()
	var card := _new_card(state, 0)
	assert_false(state.zone_has_space(9, 0), "a column past the board has no space")
	assert_false(state.place_card(card.instance_id, 9, 0), "column 9 rejected")
	assert_eq(card.location, CardState.Location.DECK, "location unchanged")
	assert_eq(card.col, -1, "col unchanged")
	assert_eq(card.slot, -1, "slot unchanged")
	assert_eq(state.zone_cards(9, 0).is_empty(), true, "no zone for column 9")

	var below := _new_card(state, 1)
	assert_false(state.place_card(below.instance_id, -2, 1), "column -2 rejected")
	assert_eq(below.location, CardState.Location.DECK, "location unchanged")
	assert_true(state.zone_has_space(MatchState.SPELL_COL, 1), "the spell column is still usable")


func test_place_card_re_slots_inside_its_own_full_zone() -> void:
	var state := MatchState.new()
	var ids := _fill_zone(state, 0, 0, 4)
	assert_false(state.zone_has_space(0, 0), "the zone is full")

	# The card frees its own slot, so a move inside this zone must still work.
	assert_true(state.place_card(ids[3], 0, 0, 0), "re-slot inside the full zone")
	assert_eq(state.zone_cards(0, 0), [ids[3], ids[0], ids[1], ids[2]], "new order")
	assert_eq(state.zone_cards(0, 0).size(), 4, "no duplicate, none lost")
	assert_eq(state.card(ids[3]).slot, 0, "moved card is at slot 0")
	assert_eq(state.card(ids[0]).slot, 1, "first card shifted back")
	assert_eq(state.card(ids[1]).slot, 2, "second card shifted back")
	assert_eq(state.card(ids[2]).slot, 3, "third card shifted back")
	assert_false(state.zone_has_space(0, 0), "the zone is still full")


func test_place_card_into_a_different_full_zone_keeps_the_card_where_it_is() -> void:
	var state := MatchState.new()
	var source := _fill_zone(state, 0, 0, 4)
	var target := _fill_zone(state, 1, 0, 4)
	assert_false(state.zone_has_space(1, 0), "the target zone is full")

	var moving := state.card(source[1])
	assert_false(state.place_card(source[1], 1, 0), "a different full zone is rejected")
	assert_eq(moving.location, CardState.Location.BOARD, "still on the board")
	assert_eq(moving.col, 0, "still in its own column")
	assert_eq(moving.slot, 1, "still in its own slot")
	assert_eq(state.zone_cards(0, 0), source, "source zone untouched")
	assert_eq(state.zone_cards(1, 0), target, "target zone untouched")


func test_full_zone_rejects_the_card() -> void:
	var state := MatchState.new()
	var ids: Array[int] = []
	for i in 5:
		ids.append(_new_card(state, 0).instance_id)
	for i in 4:
		assert_true(state.place_card(ids[i], 0, 0), "slot %d" % i)
	assert_false(state.zone_has_space(0, 0), "zone is full")
	assert_false(state.place_card(ids[4], 0, 0), "rejected")
	assert_eq(state.zone_cards(0, 0), ids.slice(0, 4), "zone unchanged")
	assert_eq(state.card(ids[4]).slot, -1, "rejected card stays off-board")
	assert_eq(state.card(ids[4]).location, CardState.Location.DECK, "rejected card keeps its location")
	assert_true(state.zone_has_space(1, 0), "the other column is free")
	assert_eq(state.zone_cards(1, 0).is_empty(), true, "unused zone is empty")


func test_spell_zone_uses_its_own_location_and_column() -> void:
	var state := MatchState.new()
	var card := _new_card(state, 1)
	assert_true(state.place_card(card.instance_id, MatchState.SPELL_COL, 1), "spell zone place")
	assert_eq(card.location, CardState.Location.SPELL_ZONE, "SPELL_ZONE")
	assert_eq(card.col, MatchState.SPELL_COL, "col is -1")
	assert_eq(card.slot, 0, "slot 0")
	assert_eq(state.zone_cards(MatchState.SPELL_COL, 1), [card.instance_id], "spell zone list")
	assert_eq(state.zone_cards(MatchState.SPELL_COL, 0).is_empty(), true, "opponent spell zone is separate")

	var others: Array[int] = []
	for i in 4:
		others.append(_new_card(state, 1).instance_id)
	for id in others:
		state.place_card(id, MatchState.SPELL_COL, 1)
	assert_false(state.zone_has_space(MatchState.SPELL_COL, 1), "spell zone holds %d" % MatchState.SPELL_SLOTS)
	assert_false(state.place_card(_new_card(state, 1).instance_id, MatchState.SPELL_COL, 1), "spell zone full")


func test_zone_cards_returns_a_copy() -> void:
	var state := MatchState.new()
	var card := _new_card(state, 0)
	state.place_card(card.instance_id, 0, 0)
	var copy: Array[int] = state.zone_cards(0, 0)
	copy.append(999)
	assert_eq(state.zone_cards(0, 0), [card.instance_id], "state untouched")


func test_remove_from_zone_compacts_and_reindexes() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	var c := _new_card(state, 0)
	state.place_card(a.instance_id, 0, 0)
	state.place_card(b.instance_id, 0, 0)
	state.place_card(c.instance_id, 0, 0)

	state.remove_from_zone(b.instance_id)
	assert_eq(state.zone_cards(0, 0), [a.instance_id, c.instance_id], "gap closed")
	assert_eq(a.slot, 0, "a slot")
	assert_eq(c.slot, 1, "c shifted down")
	assert_eq(b.col, -1, "removed card col")
	assert_eq(b.slot, -1, "removed card slot")
	assert_eq(b.location, CardState.Location.BOARD, "remove_from_zone does not change location")


func test_hand_index_zero_is_the_newest_card() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	var c := _new_card(state, 0)
	state.add_to_hand(0, a.instance_id)
	assert_eq(state.players[0].hand, [a.instance_id], "first card")
	state.add_to_hand(0, b.instance_id)
	state.add_to_hand(0, c.instance_id)
	assert_eq(state.players[0].hand, [c.instance_id, b.instance_id, a.instance_id], "newest first")
	assert_eq(a.location, CardState.Location.HAND, "a is in hand")
	assert_eq(c.col, -1, "col cleared")
	assert_eq(c.slot, -1, "slot cleared")
	assert_eq(state.players[1].hand.size(), 0, "other player's hand untouched")


func test_remove_from_hand() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	state.add_to_hand(0, a.instance_id)
	state.add_to_hand(0, b.instance_id)
	state.remove_from_hand(0, b.instance_id)
	assert_eq(state.players[0].hand, [a.instance_id], "b removed")
	state.remove_from_hand(0, a.instance_id)
	assert_eq(state.players[0].hand.is_empty(), true, "hand empty")
	assert_eq(state.players[0].hand.size(), 0, "no leftovers")


func test_draw_top_moves_the_top_of_the_deck_into_hand() -> void:
	var state := MatchState.new()
	var a := _new_card(state, 0)
	var b := _new_card(state, 0)
	state.players[0].deck = [a.instance_id, b.instance_id]

	assert_eq(state.draw_top(0), a.instance_id, "deck[0] is drawn first")
	assert_eq(state.players[0].deck, [b.instance_id], "deck shrank")
	assert_eq(state.players[0].hand, [a.instance_id], "drawn card is the newest hand card")
	assert_eq(a.location, CardState.Location.HAND, "drawn card moved")

	assert_eq(state.draw_top(0), b.instance_id, "second draw")
	assert_eq(state.players[0].hand, [b.instance_id, a.instance_id], "newest first")
	assert_eq(state.players[1].hand.is_empty(), true, "opponent unaffected")


func test_draw_top_on_an_empty_deck_returns_minus_one() -> void:
	var state := MatchState.new()
	assert_eq(state.draw_top(0), -1, "nothing to draw")
	assert_eq(state.draw_top(1), -1, "nothing to draw")
	assert_eq(state.players[0].hand.is_empty(), true, "hand untouched")


func test_opponent() -> void:
	var state := MatchState.new()
	assert_eq(state.opponent(0), 1, "host")
	assert_eq(state.opponent(1), 0, "guest")


func test_checksum_matches_the_sorted_json() -> void:
	var state := MatchState.new()
	var card := _new_card(state, 0)
	state.place_card(card.instance_id, 0, 0)
	assert_eq(state.checksum(), hash(JSON.stringify(state.to_dict(), "", true)), "checksum definition")


func test_checksum_changes_with_a_single_field() -> void:
	var a := _make_state()
	var b := _make_state()
	assert_eq(a.checksum(), b.checksum(), "identical states match")
	b.cards[1].power_modifier = 1
	assert_ne(a.checksum(), b.checksum(), "one power modifier changes the checksum")


## A state with cards in the deck, hand, board and spell zone plus some player
## state, so the round trip covers every array and both dictionary shapes.
func _make_state() -> MatchState:
	var state := MatchState.new()
	state.rng.seed = 20260901
	state.turn = 3
	state.game_phase = MatchState.GamePhase.TURN_LOOP
	state.round_phase = MatchState.RoundPhase.PLAY
	state.flip_first = 1
	var lanes: Array[String] = ["A", "B", "C"]
	state.lane_ids = lanes
	state.lane_revealed = [true, false, true]
	state.noxkraya_col = 1
	state.play_order = [3]
	state.played_this_turn = [3]
	state.killed = [{"instance_id": 4, "player": 0, "slot": 0}]
	state.stuns = [{"instance_id": 3, "stunned_on_turn": 1}]
	state.pending_swaps = [{"instance_id": 3, "to_col": 1}]

	# Two fillers first, so the card under test really lands on slot 2.
	state.place_card(state.new_card(CARD, 0, CardState.Location.HAND).instance_id, 1, 0)
	state.place_card(state.new_card(CARD, 0, CardState.Location.HAND).instance_id, 1, 0)
	var board := state.new_card(CARD, 0, CardState.Location.HAND)
	board.power_modifier = 2
	board.runtime_keywords = ["Stunned"]
	state.place_card(board.instance_id, 1, 0, 2)
	var spell := state.new_card("SpinningAxe", 0, CardState.Location.SPELL_ZONE)
	state.place_card(spell.instance_id, MatchState.SPELL_COL, 0)
	var hand_card := state.new_card(CARD, 1, CardState.Location.HAND)
	state.add_to_hand(1, hand_card.instance_id)
	var decked := state.new_card(CARD, 0, CardState.Location.DECK)
	state.players[0].deck = [decked.instance_id]

	state.players[0].current_mana = 2
	state.players[0].bonus_max_mana = 1
	state.players[0].base_max_mana = 3
	state.players[1].is_deep = true
	state.players[1].permanently_leveled_up = {"Azir": "Azir2"}
	return state


func test_json_round_trip_keeps_the_checksum() -> void:
	var state := _make_state()
	var json := JSON.stringify(state.to_dict())
	var parsed: Variant = JSON.parse_string(json)
	assert_true(parsed is Dictionary, "to_dict is JSON-safe")
	var restored := MatchState.from_dict(parsed as Dictionary)
	assert_eq(restored.checksum(), state.checksum(), "same checksum after JSON round trip")


func test_json_round_trip_keeps_the_board_and_hands() -> void:
	var state := _make_state()
	var restored := MatchState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))

	assert_eq(restored.players.size(), 2, "two players")
	assert_eq(restored.turn, 3, "turn")
	assert_eq(restored.game_phase, MatchState.GamePhase.TURN_LOOP, "game_phase")
	assert_eq(restored.round_phase, MatchState.RoundPhase.PLAY, "round_phase")
	assert_eq(restored.flip_first, 1, "flip_first")
	assert_eq(restored.lane_ids, ["A", "B", "C"], "lane_ids")
	assert_eq(restored.lane_revealed, [true, false, true], "lane_revealed")
	assert_eq(restored.noxkraya_col, 1, "noxkraya_col")
	assert_eq(restored.cards.size(), state.cards.size(), "card count")
	assert_eq(restored.next_instance_id, state.next_instance_id, "next_instance_id")
	assert_eq(restored.zone_cards(1, 0), state.zone_cards(1, 0), "board zone")
	assert_eq(restored.zone_cards(MatchState.SPELL_COL, 0), state.zone_cards(MatchState.SPELL_COL, 0), "spell zone")
	assert_eq(restored.players[0].deck, state.players[0].deck, "deck")
	assert_eq(restored.players[1].hand, state.players[1].hand, "hand")
	assert_eq(restored.play_order, [3], "play_order")
	assert_eq(restored.killed, [{"instance_id": 4, "player": 0, "slot": 0}], "killed")
	assert_eq(restored.stuns, [{"instance_id": 3, "stunned_on_turn": 1}], "stuns")
	assert_eq(restored.pending_swaps, [{"instance_id": 3, "to_col": 1}], "pending_swaps")
	assert_eq(restored.players[0].get_max_mana(), 4, "max mana")
	assert_eq(restored.players[0].current_mana, 2, "current mana")
	assert_eq(restored.players[1].is_deep, true, "is_deep")
	assert_eq(restored.players[1].permanently_leveled_up, {"Azir": "Azir2"}, "leveled up")
	assert_eq(restored.card(3).power_modifier, 2, "power_modifier")
	assert_eq(restored.card(3).slot, 2, "slot")
	assert_eq(restored.card(3).col, 1, "col")
	assert_eq(restored.card(3).runtime_keywords, ["Stunned"], "runtime keywords")
	assert_eq(restored.card(4).location, CardState.Location.SPELL_ZONE, "spell location")
	assert_eq(restored.zone_cards(1, 0).size(), 3, "three cards in the lane")


func test_rng_sequence_survives_the_round_trip() -> void:
	var state := MatchState.new()
	state.rng.seed = 20260901
	var saved: Variant = JSON.parse_string(JSON.stringify(state.to_dict()))
	var expected: Array = []
	for _i in 5:
		expected.append(state.rng.randi())

	var restored := MatchState.from_dict(saved as Dictionary)
	var actual: Array = []
	for _i in 5:
		actual.append(restored.rng.randi())
	assert_eq(actual, expected, "same rng stream after the round trip")


func test_from_dict_restores_numbers_as_ints() -> void:
	var state := _make_state()
	var raw: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	var restored := MatchState.from_dict(raw)
	for id in restored.cards:
		assert_true(restored.cards[id] is CardState, "card %s restored" % str(id))
	assert_true(restored.players[0] is PlayerState, "players restored")
	assert_eq(restored.card(3).instance_id, 3, "ints stay ints")
	assert_eq(restored.players[0].current_mana, 2, "mana stays an int")
	assert_eq(restored.zone_cards(1, 0).size(), 3, "zones stay arrays")
	for key in restored.zones:
		assert_true(key is String or key is Vector2i, "zone key %s" % str(key))