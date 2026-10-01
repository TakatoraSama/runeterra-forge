## Tests for MatchSnapshot.for_viewer and the two M4 event additions.
##
## The snapshot is the contract between the engine and the presenter, so these tests are
## about what a viewer may know: the opponent's hand is a count, an unresolved opponent
## card keeps its slot but loses its identity, unrevealed lanes are unnamed, and only
## the viewer's own swaps are listed. Plus the two properties a presenter relies on
## structurally: the whole thing survives JSON and is byte-stable for one state.
extends "res://Tests/test_case.gd"

## Deck.gd.DEFAULT_DECK as plain card ids.
const DECK_0: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Ahri1",
	"Kennen1", "NavoriConspirator", "Janna1", "Draven1", "Rumble1", "Sion1",
]

## BotManager.BOT_DECK.
const DECK_1: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Trundle1",
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk",
]

const VIEWER := 1


# --- Hand visibility ---

func test_own_hand_is_listed_and_the_opponent_hand_is_a_count() -> void:
	var rules := _started_match(4)
	var state := rules.state
	var snap := MatchSnapshot.for_viewer(state, VIEWER)

	var mine: Dictionary = snap["players"][VIEWER]
	var theirs: Dictionary = snap["players"][1 - VIEWER]
	assert_true(mine["hand"] is Array, "the viewer gets its hand as an array")
	assert_eq(mine["hand"].size(), state.players[VIEWER].hand.size(), "one entry per hand card")
	assert_false(theirs["hand"] is Array, "the opponent's hand is not an array")
	assert_eq(int(theirs["hand"]), state.players[1 - VIEWER].hand.size(), "the opponent is a count")

	# The viewer's own hand comes back in hand order, with what the presenter needs to
	# draw the card: which instance it is, what it is and what it costs.
	var hand: Array = mine["hand"]
	var expected_ids: Array = []
	for raw in state.players[VIEWER].hand:
		expected_ids.append(int(raw))
	var seen_ids: Array = []
	for entry: Dictionary in hand:
		assert_true(entry.has("instance_id") and entry.has("card_id") and entry.has("cost"),
			"hand entry carries instance_id, card_id and cost")
		seen_ids.append(int(entry["instance_id"]))
		assert_eq(str(entry["card_id"]), state.card(int(entry["instance_id"])).card_id,
			"hand entry names the right card")
		assert_eq(int(entry["cost"]), state.card(int(entry["instance_id"])).get_current_cost(),
			"hand entry shows the current cost")
	assert_eq(seen_ids, expected_ids, "hand order matches the engine's hand order")


func test_opponent_hand_cards_are_not_anywhere_in_the_snapshot() -> void:
	var rules := _started_match(9)
	var state := rules.state
	# Give the opponent a hand that is not the viewer's, so a leak is unmistakable.
	var only_for_them := state.new_card("HexCoreUpgrade", 0, CardState.Location.DECK)
	state.add_to_hand(0, only_for_them.instance_id)
	state.players[0].deck.erase(only_for_them.instance_id)

	var snap := MatchSnapshot.for_viewer(state, VIEWER)
	var text := JSON.stringify(snap)
	assert_false(text.contains("HexCoreUpgrade"),
		"a card only the opponent holds must not appear anywhere in the snapshot")
	assert_eq(int(snap["players"][0]["hand"]), state.players[0].hand.size(),
		"the opponent's hand is still counted correctly")


# --- Board visibility ---

func test_unresolved_opponent_card_keeps_its_slot_but_loses_its_identity() -> void:
	var rules := _started_match(3)
	var state := rules.state
	var play := _playable(state, 0)
	assert_true(play.has("id"), "player 0 has a card to play on turn 1")
	var id: int = int(play["id"])
	var col: int = int(play["col"])

	var events := rules.submit(0, MatchIntents.play_card(id, col))
	assert_eq(_count_type(events, MatchEvents.CARD_PLAYED), 1, "the card was played")
	assert_false(state.card(id).is_resolved, "a card is not resolved until it flips")

	var snap := MatchSnapshot.for_viewer(state, VIEWER)
	var entry := _board_entry(snap, id)
	assert_false(entry.is_empty(), "the opponent's card is on the board, so it is listed")
	assert_eq(entry["instance_id"], id)
	assert_eq(entry["owner"], 0)
	assert_eq(entry["col"], col)
	assert_eq(entry["slot"], state.card(id).slot, "the slot is public: the board is visible")
	assert_false(entry["resolved"], "not resolved yet")
	assert_eq(entry["card_id"], null, "an unresolved opponent card has no card_id")
	assert_eq(entry["power"], null, "an unresolved opponent card has no power")


func test_own_card_is_visible_before_it_resolves() -> void:
	var rules := _started_match(3)
	var state := rules.state
	var play := _playable(state, VIEWER)
	var id: int = int(play["id"])

	rules.submit(VIEWER, MatchIntents.play_card(id, int(play["col"])))
	var card := state.card(id)
	assert_false(card.is_resolved, "not resolved until it flips")

	var snap := MatchSnapshot.for_viewer(state, VIEWER)
	var entry := _board_entry(snap, id)
	assert_false(entry.is_empty(), "the viewer's own played card is listed")
	assert_eq(entry["card_id"], card.card_id, "the owner sees their own card, resolved or not")
	assert_eq(entry["power"], card.get_current_power(), "own power is public")
	assert_eq(entry["cost"], card.get_current_cost(), "own cost is public")
	assert_eq(entry["owner"], VIEWER)


func test_a_resolved_opponent_card_becomes_visible() -> void:
	var rules := _started_match(3)
	var state := rules.state
	var play := _playable(state, 0)
	var id: int = int(play["id"])
	rules.submit(0, MatchIntents.play_card(id, int(play["col"])))
	assert_eq(_board_entry(MatchSnapshot.for_viewer(state, VIEWER), id)["card_id"], null,
		"hidden while unresolved")

	state.card(id).is_resolved = true
	var entry := _board_entry(MatchSnapshot.for_viewer(state, VIEWER), id)
	assert_eq(entry["card_id"], state.card(id).card_id, "revealed once resolved")
	assert_eq(entry["power"], state.card(id).get_current_power())
	assert_true(entry["resolved"])


func test_board_is_sorted_by_owner_then_col_then_slot() -> void:
	var rules := _started_match(5)
	var state := rules.state
	for player in [0, VIEWER]:
		state.players[player].current_mana = 10
		for play: Dictionary in _playables(state, player, 2):
			rules.submit(player, MatchIntents.play_card(int(play["id"]), int(play["col"])))
		assert_eq(state.players[player].hand.size(), 4 - 2, "two cards left the hand")

	var board: Array = MatchSnapshot.for_viewer(state, VIEWER)["board"]
	var keys: Array = []
	for entry: Dictionary in board:
		var zone: Array = state.zones[Vector2i(int(entry["col"]), int(entry["owner"]))]
		var engine_slot: int = zone.find(int(entry["instance_id"]))
		assert_eq(int(entry["slot"]), engine_slot, "slot is the engine slot, not a guess")
		keys.append([int(entry["owner"]), int(entry["col"]), int(entry["slot"])])
	var sorted_keys := keys.duplicate()
	sorted_keys.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1] != b[1]:
			return a[1] < b[1]
		return a[2] < b[2])
	assert_eq(keys, sorted_keys, "board rows come back sorted by owner, col, slot")


func test_spell_zone_cards_are_listed_with_the_spell_column() -> void:
	var rules := _started_match(2)
	var state := rules.state
	var spell := state.new_card("HexCoreUpgrade", VIEWER, CardState.Location.DECK)
	state.players[VIEWER].deck.erase(spell.instance_id)
	state.add_to_hand(VIEWER, spell.instance_id)
	var events := rules.submit(VIEWER, MatchIntents.play_card(spell.instance_id, MatchState.SPELL_COL))
	assert_eq(_count_type(events, MatchEvents.CARD_PLAYED), 1, "the spell went into the spell zone")

	var entry := _board_entry(MatchSnapshot.for_viewer(state, VIEWER), spell.instance_id)
	assert_eq(entry["col"], MatchState.SPELL_COL, "the spell column is -1, the presenter maps it")
	assert_eq(entry["card_id"], "HexCoreUpgrade")
	assert_eq(entry["power"], 0, "a spell has no power")


func test_deck_and_hand_cards_are_not_on_the_board() -> void:
	var rules := _started_match(6)
	var state := rules.state
	var board: Array = MatchSnapshot.for_viewer(state, VIEWER)["board"]
	for entry: Dictionary in board:
		var card := state.card(int(entry["instance_id"]))
		assert_true(card.location == CardState.Location.BOARD or card.location == CardState.Location.SPELL_ZONE,
			"only cards on a board or in a spell zone are listed")
	# Deck counts, though, are public for both players.
	for player in 2:
		assert_eq(int(MatchSnapshot.for_viewer(state, VIEWER)["players"][player]["deck_count"]),
			state.players[player].deck.size(), "deck counts are public")


# --- Lanes ---

func test_only_revealed_lanes_are_named() -> void:
	var rules := _started_match(7)
	var state := rules.state
	var snap := MatchSnapshot.for_viewer(state, VIEWER)
	var lanes: Array = snap["lanes"]
	assert_eq(lanes.size(), MatchState.COLUMNS, "three columns, always")
	for col in MatchState.COLUMNS:
		var entry: Dictionary = lanes[col]
		assert_eq(entry["col"], col)
		assert_eq(bool(entry["revealed"]), bool(state.lane_revealed[col]),
			"revealed flag matches the engine")
		if bool(state.lane_revealed[col]):
			assert_eq(str(entry["lane_id"]), str(state.lane_ids[col]), "a revealed lane is named")
		else:
			assert_eq(str(entry["lane_id"]), "", "an unrevealed lane has no id")


func test_a_match_before_the_lanes_are_assigned_reports_three_unnamed_lanes() -> void:
	# A bare state has no lane_ids and an empty lane_revealed; the snapshot must still
	# be three well-formed columns rather than a crash.
	var lanes: Array = MatchSnapshot.for_viewer(MatchState.new(), VIEWER)["lanes"]
	assert_eq(lanes.size(), 3)
	for col in 3:
		assert_eq(str(lanes[col]["lane_id"]), "")
		assert_false(bool(lanes[col]["revealed"]))


# --- Pending swaps ---

func test_only_the_viewers_own_pending_swaps_are_listed() -> void:
	var rules := _started_match(8)
	var state := rules.state
	state.pending_swaps.clear()
	state.pending_swaps.append({"instance_id": 101, "player": 0, "from_col": 0, "to_col": 2, "turn": 1})
	state.pending_swaps.append({"instance_id": 102, "player": VIEWER, "from_col": 1, "to_col": 0, "turn": 1})
	state.pending_swaps.append({"instance_id": 103, "player": VIEWER, "from_col": 2, "to_col": 1, "turn": 1})

	var mine: Array = MatchSnapshot.for_viewer(state, VIEWER)["pending_swaps_own"]
	assert_eq(mine.size(), 2, "the opponent's queued swap is not listed")
	assert_eq(mine[0], {"instance_id": 102, "to_col": 0}, "queue order, instance and destination only")
	assert_eq(mine[1], {"instance_id": 103, "to_col": 1})

	var theirs: Array = MatchSnapshot.for_viewer(state, 0)["pending_swaps_own"]
	assert_eq(theirs.size(), 1, "the other viewer sees its own")
	assert_eq(int(theirs[0]["instance_id"]), 101)


func test_a_fresh_match_has_no_pending_swaps() -> void:
	var rules := _started_match(10)
	assert_eq(MatchSnapshot.for_viewer(rules.state, VIEWER)["pending_swaps_own"], [])


# --- Shape ---

func test_top_level_fields_track_the_engine() -> void:
	var rules := _started_match(11)
	var state := rules.state
	var snap := MatchSnapshot.for_viewer(state, VIEWER)
	assert_eq(snap["turn"], state.turn)
	assert_eq(snap["game_phase"], state.game_phase)
	assert_eq(snap["round_phase"], state.round_phase)
	assert_eq(snap["flip_first"], state.flip_first)
	assert_eq(snap["local"], VIEWER)
	assert_eq(snap["players"].size(), 2)
	for player in 2:
		var entry: Dictionary = snap["players"][player]
		assert_eq(entry["player"], player)
		assert_eq(int(entry["current_mana"]), state.players[player].current_mana)
		assert_eq(int(entry["max_mana"]), state.players[player].get_max_mana())
		assert_eq(bool(entry["is_deep"]), state.players[player].is_deep)
		assert_eq(bool(entry["ended_turn"]), state.players[player].ended_turn)


func test_snapshot_survives_json_and_stays_the_same_after_the_round_trip() -> void:
	var rules := _started_match(12)
	var state := rules.state
	var play := _playable(state, 0)
	rules.submit(0, MatchIntents.play_card(int(play["id"]), int(play["col"])))
	var mine := _playable(state, VIEWER)
	rules.submit(VIEWER, MatchIntents.play_card(int(mine["id"]), int(mine["col"])))

	for viewer in 2:
		var snap := MatchSnapshot.for_viewer(state, viewer)
		var text := JSON.stringify(snap)
		assert_false(text.is_empty(), "viewer %d: the snapshot writes to JSON" % viewer)
		var back: Variant = JSON.parse_string(text)
		assert_true(back is Dictionary, "viewer %d: and reads back as a Dictionary" % viewer)
		assert_eq(back, snap, "viewer %d: a JSON round trip loses nothing" % viewer)


func test_snapshot_is_deterministic() -> void:
	# Same state, twice.
	var rules := _started_match(13)
	var state := rules.state
	for viewer in 2:
		assert_eq(MatchSnapshot.for_viewer(state, viewer), MatchSnapshot.for_viewer(state, viewer),
			"viewer %d: the same state always yields the same snapshot" % viewer)

	# Same seed, twice: two independent matches must agree exactly.
	for viewer in 2:
		var a := MatchSnapshot.for_viewer(_started_match(13).state, viewer)
		var b := MatchSnapshot.for_viewer(_started_match(13).state, viewer)
		assert_eq(a, b, "viewer %d: seed 13 replays to the same snapshot" % viewer)

	# And it does not touch the state it reads.
	var before := state.checksum()
	MatchSnapshot.for_viewer(state, 0)
	MatchSnapshot.for_viewer(state, 1)
	assert_eq(state.checksum(), before, "for_viewer is read-only")


# --- The two M4 event additions ---

func test_intent_rejected_carries_the_card_the_intent_was_about() -> void:
	var rules := _started_match(14)
	var state := rules.state

	# A swap of a card that is still in hand: refused, but the presenter needs to know
	# which card it was so the dragged card can go home.
	var in_hand: int = int(state.players[VIEWER].hand[0])
	var rejected := _rejection(rules.submit(VIEWER, MatchIntents.swap_card(in_hand, 1)))
	assert_eq(rejected["intent_type"], str(MatchIntents.SWAP_CARD))
	assert_ne(rejected["reason"], "")
	assert_eq(int(rejected["instance_id"]), in_hand, "the swap rejection names the card")

	# Same for a play the player cannot afford.
	var too_expensive: int = -1
	for raw in state.players[VIEWER].hand:
		var card := state.card(int(raw))
		if card.get_current_cost() > state.players[VIEWER].current_mana:
			too_expensive = int(raw)
	if too_expensive != -1:
		var play_rejected := _rejection(rules.submit(VIEWER, MatchIntents.play_card(too_expensive, 0)))
		assert_eq(str(play_rejected["reason"]), "not_enough_mana")
		assert_eq(int(play_rejected["instance_id"]), too_expensive)

	# A play the player has no business making: still names the card.
	var not_mine: int = int(state.players[1 - VIEWER].hand[0])
	var wrong_owner := _rejection(rules.submit(VIEWER, MatchIntents.play_card(not_mine, 0)))
	assert_eq(str(wrong_owner["reason"]), "not_in_hand")
	assert_eq(int(wrong_owner["instance_id"]), not_mine)

	# A half-formed play still names the card it was trying to move.
	var malformed := _rejection(rules.submit(VIEWER, {"type": "play_card", "instance_id": not_mine, "col": 0}))
	assert_eq(str(malformed["reason"]), "malformed")
	assert_eq(int(malformed["instance_id"]), not_mine)


func test_intent_rejected_uses_minus_one_for_intents_without_a_card() -> void:
	var rules := _started_match(15)
	assert_eq(int(_rejection(rules.submit(VIEWER, MatchIntents.undo()))["instance_id"]), -1,
		"undo names no card")
	assert_eq(int(_rejection(rules.submit(VIEWER, "garbage"))["instance_id"]), -1,
		"a non-dictionary intent names no card")
	# A first end_turn is legal on its own; the second one is the refusal.
	assert_eq(_count_type(rules.submit(VIEWER, MatchIntents.end_turn()), MatchEvents.INTENT_REJECTED), 0,
		"the first end_turn is accepted")
	assert_eq(int(_rejection(rules.submit(VIEWER, MatchIntents.end_turn()))["instance_id"]), -1,
		"end_turn names no card")
	# The old three-argument call site still works and still means "no card".
	var legacy := MatchEvents.intent_rejected(0, "play_card", "malformed")
	assert_eq(int(legacy["instance_id"]), -1, "the trailing default keeps old call sites working")


func test_play_undone_reports_the_hand_after_the_undo() -> void:
	var rules := _started_match(16)
	var state := rules.state
	# Two affordable plays need more than turn 1's single mana.
	state.players[VIEWER].current_mana = 10
	var hand_before: Array = state.players[VIEWER].hand.duplicate()

	var plays := _playables(state, VIEWER, 2)
	assert_eq(plays.size(), 2, "the viewer has two cards it can play this turn")
	var first_id: int = int(plays[0]["id"])
	var second_id: int = int(plays[1]["id"])
	var first_index: int = state.players[VIEWER].hand.find(first_id)
	rules.submit(VIEWER, MatchIntents.play_card(first_id, int(plays[0]["col"])))
	rules.submit(VIEWER, MatchIntents.play_card(second_id, int(plays[1]["col"])))
	assert_eq(state.players[VIEWER].hand.size(), hand_before.size() - 2, "both cards left the hand")

	var undone := _event_of_type(rules.submit(VIEWER, MatchIntents.undo()), MatchEvents.PLAY_UNDONE)
	assert_true(undone.has("hand_after"), "play_undone carries the resulting hand")
	assert_eq(undone["hand_after"], hand_before, "the hand is exactly what it was before the plays")
	assert_eq(state.players[VIEWER].hand, hand_before, "and it matches the engine's hand")
	assert_eq(state.players[VIEWER].hand.find(first_id), first_index,
		"the card went back to the slot it came from")

	# The old two-argument call site still works and still means "no hand listed".
	var legacy := MatchEvents.play_undone(0, [3, 4])
	assert_eq(legacy["hand_after"], [], "the trailing default keeps old call sites working")
	assert_eq(legacy["instance_ids"], [3, 4])


# ----------------------------
# Helpers
# ----------------------------

## A match already in turn 1 PLAY with the real abilities installed.
func _started_match(seed_value: int) -> MatchRules:
	var state := MatchSetup.new_match(DECK_0, DECK_1, seed_value)
	var rules := MatchRules.new(state)
	MatchCardAbilities.install(rules)
	rules.start_match()
	return rules


## The first card `player` could legally play into a lane right now, as {id, col},
## or {} when there is none. Spells are skipped: they need the spell zone, not a lane.
func _playable(state: MatchState, player: int) -> Dictionary:
	var plays := _playables(state, player, 1)
	return plays[0] if not plays.is_empty() else {}


## Up to `count` distinct hand cards `player` could legally play right now, as an Array
## of {id, col}. The mana pool is what it is, so this is what the engine would accept.
func _playables(state: MatchState, player: int, count: int) -> Array:
	var plays: Array = []
	if count <= 0:
		return plays
	for raw in state.players[player].hand:
		var card := state.card(int(raw))
		if card == null or str(card.data().get("Type", "")) == "Spell":
			continue
		if card.get_current_cost() > state.players[player].current_mana:
			continue
		for col in MatchState.COLUMNS:
			if state.noxkraya_col >= 0 and state.noxkraya_col != col:
				continue
			if state.zone_cards(col, player).size() >= MatchState.SLOTS_PER_ZONE:
				continue
			plays.append({"id": int(raw), "col": col})
			break
		if plays.size() >= count:
			break
	return plays


## The snapshot's board row for that instance, or an empty Dictionary when it is absent.
func _board_entry(snapshot: Dictionary, instance_id: int) -> Dictionary:
	for entry: Dictionary in snapshot["board"]:
		if int(entry["instance_id"]) == instance_id:
			return entry
	return {}


## The single event of that type in the batch.
func _event_of_type(events: Array, type_name: StringName) -> Dictionary:
	for event: Dictionary in events:
		if event["type"] == type_name:
			return event
	return {}


## How many events of that type the batch holds.
func _count_type(events: Array, type_name: StringName) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event["type"] == type_name:
			count += 1
	return count


## The single intent_rejected in the batch; fails the test when there is not exactly one.
func _rejection(events: Array) -> Dictionary:
	var found := _event_of_type(events, MatchEvents.INTENT_REJECTED)
	assert_eq(_count_type(events, MatchEvents.INTENT_REJECTED), 1,
		"the batch holds exactly one rejection")
	return found