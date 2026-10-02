## Tests for the room rule "a card swapping out no longer takes room in its old lane".
##
## The contract: while an Elusive card is queued OUT of a lane, that lane may hold
## SLOTS_PER_ZONE + 1 cards, so a full lane whose Ahri is leaving still accepts a new
## unit during PLAY (engine slot 4), and compacts back to slots 0..3 at SWAP_LANE. One
## formula (MatchRules._room_in) decides it for both play_card and swap_card, and
## MatchBot's optional swap planner must only ever queue swaps the engine accepts.
extends "res://Tests/test_case.gd"

## Lanes with no board effect of their own, so nothing but the tested intent changes
## the board. Noxkraya Arena only restricts placement, Sunken Temple only draws.
const LANES := ["SunkenTemple", "SunkenTemple", "NoxkrayaArena"]

const AHRI := "Ahri1"  # Elusive, cost 1
const FILLER := "Chip"  # plain follower, cost 1
const UNIT := "Blade"  # plain follower, cost 1
const IRELIA := "Irelia1"  # Elusive; its {swap} summons a Blade into the lane it leaves


# ----------------------------
# Helpers
# ----------------------------

## A started match with a deep deck, so nothing runs out mid-test.
func _rules() -> MatchRules:
	var pool: Array = [FILLER, UNIT, AHRI, "Tryndamere1", "Valor", "Janna1", "Kennen1", "Nasus1"]
	var deck: Array = []
	for i in 24:
		deck.append(pool[i % pool.size()])
	var rules := MatchRules.new(MatchSetup.new_match(deck, deck.duplicate(), 7))
	rules.start_match(Array(LANES))
	for p in 2:
		rules.state.players[p].base_max_mana = 20
		rules.state.players[p].current_mana = 20
	return rules


## Puts a fresh card of `card_id` into player `p`'s hand and returns it.
func _give(state: MatchState, p: int, card_id: String) -> CardState:
	var card := state.new_card(card_id, p, CardState.Location.HAND)
	state.add_to_hand(p, card.instance_id)
	return card


## Puts a resolved card on the board (as if summoned) and returns it.
func _on_board(state: MatchState, p: int, col: int, card_id: String) -> CardState:
	var card := state.new_card(card_id, p, CardState.Location.BOARD)
	state.place_card(card.instance_id, col, p)
	card.is_resolved = true
	state.play_order.append(card.instance_id)
	return card


## Fills (col, p) up to `count` resolved cards, in that order, and returns them.
func _fill(state: MatchState, p: int, col: int, count: int, card_id: String = FILLER) -> Array[CardState]:
	var placed: Array[CardState] = []
	while state.zone_cards(col, p).size() < count:
		placed.append(_on_board(state, p, col, card_id))
	return placed


## `count` resolved cards in (col, p) in slot order, with an Elusive at `elusive_slot`
## (-1 for a lane with none) and plain followers everywhere else.
func _lane(state: MatchState, p: int, col: int, count: int,
		elusive_slot: int = -1) -> Array[CardState]:
	var placed: Array[CardState] = []
	for i in count:
		placed.append(_on_board(state, p, col, AHRI if i == elusive_slot else FILLER))
	return placed


## The single rejection reason in `events`, or "" when `events` is not one rejection.
func _reason(events: Array) -> String:
	if events.size() != 1 or events[0].get("type", &"") != MatchEvents.INTENT_REJECTED:
		return ""
	return str(events[0]["reason"])


## Submits one intent and asserts it was rejected for `expected`. `note` explains why
## that is the verdict the situation calls for.
func _assert_rejected(rules: MatchRules, player: int, intent: Dictionary, expected: String,
		note: String = "") -> void:
	assert_eq(_reason(rules.submit(player, intent)), expected,
		"%s rejected as %s%s" % [intent.get("type", ""), expected,
		"" if note.is_empty() else " (%s)" % note])


## Submits one intent and asserts it was accepted, returning its events. `note` says why
## the situation calls for acceptance.
func _assert_accepted(rules: MatchRules, player: int, intent: Dictionary,
		note: String = "") -> Array:
	var events := rules.submit(player, intent)
	assert_eq(_reason(events), "", "%s was accepted%s"
		% [intent.get("type", ""), "" if note.is_empty() else " (%s)" % note])
	return events


## Both players end their turn, so SWAP_LANE (and the resolve) runs. Returns the events.
func _end_round(rules: MatchRules) -> Array:
	var events: Array = []
	events.append_array(rules.submit(0, MatchIntents.end_turn()))
	events.append_array(rules.submit(1, MatchIntents.end_turn()))
	return events


## The instance ids in (col, p), in slot order.
func _ids(state: MatchState, p: int, col: int) -> Array[int]:
	return state.zone_cards(col, p)


## The slots the cards in (col, p) hold, in slot order.
func _slots(state: MatchState, p: int, col: int) -> Array[int]:
	var slots: Array[int] = []
	for id in _ids(state, p, col):
		slots.append(state.card(id).slot)
	return slots


## How many events of `type` are in `events`.
func _count(events: Array, type: Variant) -> int:
	var found: int = 0
	for event: Variant in events:
		if event.get("type", &"") == type:
			found += 1
	return found


# ----------------------------
# MatchState: outgoing_swaps / zone_has_space
# ----------------------------

func test_a_lane_with_no_pending_swap_has_no_extra_room() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	_fill(state, 0, 0, MatchState.SLOTS_PER_ZONE)
	assert_eq(state.outgoing_swaps(0, 0), 0, "nothing is leaving the lane")
	assert_false(state.zone_has_space(0, 0), "a full lane is full")


func test_outgoing_swaps_counts_only_the_owners_own_queued_departures() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var mine := _on_board(state, 0, 0, AHRI)
	_on_board(state, 1, 0, AHRI)
	_assert_accepted(rules, 0, MatchIntents.swap_card(mine.instance_id, 1))
	assert_eq(state.outgoing_swaps(0, 0), 1, "player 0's own departure")
	assert_eq(state.outgoing_swaps(0, 1), 0, "not player 1's lane, and player 1 queued nothing")
	assert_eq(state.outgoing_swaps(1, 0), 0, "the departure frees room in the lane it LEAVES")


func test_outgoing_swaps_ignores_a_swap_whose_card_left_its_column() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var card := _on_board(state, 0, 0, AHRI)
	_assert_accepted(rules, 0, MatchIntents.swap_card(card.instance_id, 1))
	assert_eq(state.outgoing_swaps(0, 0), 1)
	# The card leaves the column for another reason: its entry frees nothing now, which
	# is what keeps outgoing_swaps() honest while _execute_swaps walks the queue.
	rules.ops.kill(card.instance_id, 1, -1)
	assert_eq(state.outgoing_swaps(0, 0), 0, "a dead entry frees nothing")
	assert_eq(state.zone_cards(0, 0).size(), 0)


func test_a_full_lane_with_a_departure_queued_takes_one_more_card() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	# Ahri sits in the middle of the lane, exactly like the user's case.
	var before: Array[CardState] = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE, 2)
	var ahri: CardState = before[2]
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	assert_true(state.zone_has_space(0, 0), "the lane frees a slot at once")
	var newcomer := _give(state, 0, UNIT)
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
	assert_eq(state.card(newcomer.instance_id).slot, MatchState.SLOTS_PER_ZONE,
		"the newcomer takes the temporary engine slot 4")
	assert_true(ahri.is_resolved, "and the swapping card is still in its origin lane")


func test_the_spell_zone_never_gets_swap_room() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	_fill(state, 0, MatchState.SPELL_COL, MatchState.SPELL_SLOTS, "HexCoreUpgrade")
	var ahri := _on_board(state, 0, 0, AHRI)
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	assert_eq(state.outgoing_swaps(MatchState.SPELL_COL, 0), 0,
		"a lane swap frees nothing in the spell zone")
	assert_false(state.zone_has_space(MatchState.SPELL_COL, 0), "the spell zone stays full")


# ----------------------------
# The user's case: a full lane that is losing Ahri
# ----------------------------

func test_a_full_lane_accepts_a_fifth_card_and_compacts_at_swap_lane() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var before: Array[CardState] = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE, 2)
	var ahri: CardState = before[2]
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	var newcomer := _give(state, 0, UNIT)
	var played := _assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
	assert_eq(_count(played, MatchEvents.CARD_PLAYED), 1, "the play is announced")
	assert_eq(state.card(newcomer.instance_id).col, 0)
	assert_eq(state.card(newcomer.instance_id).slot, 4, "engine slot 4 during PLAY")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE + 1, "the lane holds 5 for now")

	var events := _end_round(rules)
	assert_eq(_count(events, MatchEvents.CARD_SWAPPED), 1, "the swap really happened")
	assert_eq(state.card(ahri.instance_id).col, 1, "Ahri is in the destination")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE, "the origin compacted to 4")
	assert_eq(_slots(state, 0, 0), [0, 1, 2, 3], "slots are 0..3 again")
	assert_eq(state.card(newcomer.instance_id).slot, 3, "the newcomer took Ahri's place in the order")
	assert_true(state.card(newcomer.instance_id).is_resolved, "and resolved like any other play")


func test_a_play_into_a_not_full_lane_lands_after_ahri_and_then_compacts() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var ahri := _on_board(state, 0, 0, AHRI)
	var behind := _on_board(state, 0, 0, UNIT)
	var newcomer := _give(state, 0, UNIT)
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
	assert_eq(state.card(newcomer.instance_id).slot, 2, "appended after Ahri, who is still there")

	_end_round(rules)
	assert_eq(state.card(ahri.instance_id).col, 1, "Ahri moved")
	assert_eq(_ids(state, 0, 0), [behind.instance_id, newcomer.instance_id],
		"the card behind Ahri moved into her slot, the newcomer stayed last")
	assert_eq(_slots(state, 0, 0), [0, 1], "and the lane compacted")


func test_a_play_into_a_full_lane_with_nothing_leaving_is_still_zone_full() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	_fill(state, 0, 0, MatchState.SLOTS_PER_ZONE)
	var newcomer := _give(state, 0, UNIT)
	_assert_rejected(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0), "zone_full")


func test_a_swap_into_an_overflowed_lane_is_rejected() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var lane: Array[CardState] = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE, 2)
	var ahri: CardState = lane[2]
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 2))
	var newcomer := _give(state, 0, UNIT)
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE + 1, "the lane is overflowing")
	# The play took the slot Ahri is freeing; a swap must not be able to double-book it.
	var other: CardState = _lane(state, 0, 2, 2, 1)[1]
	_assert_rejected(rules, 0, MatchIntents.swap_card(other.instance_id, 0), "zone_full")


func test_two_swaps_can_cross_and_both_run() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	# Lane 1 is FULL, so A cannot move into it until B is already queued to leave it.
	# Lane 0 has one free slot, so B's own move is legal right away.
	var lane1: Array[CardState] = _lane(state, 0, 1, MatchState.SLOTS_PER_ZONE, 2)
	var b_card: CardState = lane1[2]
	var lane0: Array[CardState] = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE - 1, 0)
	var a_card: CardState = lane0[0]
	_assert_rejected(rules, 0, MatchIntents.swap_card(a_card.instance_id, 1), "zone_full",
		"nothing leaves lane 1 yet")
	_assert_accepted(rules, 0, MatchIntents.swap_card(b_card.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.swap_card(a_card.instance_id, 1),
		"lane 1 has room now because B is leaving it")
	var events := _end_round(rules)
	assert_eq(_count(events, MatchEvents.CARD_SWAPPED), 2, "both swaps ran")
	assert_eq(state.card(a_card.instance_id).col, 1, "A ended in lane 1")
	assert_eq(state.card(b_card.instance_id).col, 0, "B ended in lane 0")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE - 1,
		"lane 0 lost A and gained B")
	assert_eq(_ids(state, 0, 1).size(), MatchState.SLOTS_PER_ZONE,
		"lane 1 lost B and gained A")
	assert_eq(_slots(state, 0, 0), [0, 1, 2], "lane 0 slots are compact")
	assert_eq(_slots(state, 0, 1), [0, 1, 2, 3], "lane 1 slots are compact")


func test_undo_pulls_the_overflow_play_back_without_touching_the_swap() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var before: Array[CardState] = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE, 2)
	var ahri: CardState = before[2]
	var newcomer := _give(state, 0, UNIT)
	var hand_size: int = state.players[0].hand.size()
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
	assert_eq(state.card(newcomer.instance_id).slot, 4)

	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_true(state.players[0].hand.has(newcomer.instance_id), "the card is back in hand")
	assert_eq(state.players[0].hand.size(), hand_size, "and the hand has exactly the cards it had")
	assert_eq(state.card(newcomer.instance_id).location, CardState.Location.HAND)
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE, "the lane is back to 4")
	assert_eq(_slots(state, 0, 0), [0, 1, 2, 3], "and compact again")
	assert_eq(state.pending_swaps.size(), 1, "undo does not cancel the queued swap")

	_end_round(rules)
	assert_eq(state.card(ahri.instance_id).col, 1, "the swap still ran afterwards")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE - 1, "the origin really lost Ahri")
	assert_eq(_slots(state, 0, 0), [0, 1, 2], "and compacted")


# ----------------------------
# Hidden information during the overflow
# ----------------------------

func test_the_opponent_sees_the_fifth_card_face_down_and_no_moved_slot() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	var before: Array[CardState] = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE, 2)
	var ahri: CardState = before[2]
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	var newcomer := _give(state, 0, UNIT)
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))

	var view: Dictionary = MatchSnapshot.for_viewer(state, 1)
	var rows: Array = []
	for raw: Variant in view["board"]:
		var row: Dictionary = raw
		if int(row["owner"]) == 0 and int(row["col"]) == 0:
			rows.append(row)
	assert_eq(rows.size(), MatchState.SLOTS_PER_ZONE + 1, "every card in the lane is listed")
	var hidden: Dictionary = rows[MatchState.SLOTS_PER_ZONE]
	assert_eq(hidden["instance_id"], newcomer.instance_id, "the new card is the 5th one")
	assert_eq(hidden["slot"], 4, "at the temporary slot 4")
	assert_eq(hidden["card_id"], null, "face-down: no identity")
	assert_eq(hidden["power"], null, "no power")
	assert_eq(hidden["keywords"], null, "and no keywords")
	for i in MatchState.SLOTS_PER_ZONE:
		assert_eq(rows[i]["slot"], i, "revealed card %d kept its slot" % i)
		assert_ne(rows[i]["card_id"], null, "and is still face-up")
	assert_eq(view["pending_swaps_own"], [], "the opponent never learns about the swap")
	assert_eq(int(view["players"][0]["hand"]), state.players[0].hand.size(),
		"the opponent's view of the hand stays a count")


# ----------------------------
# Summons and other place_card callers
# ----------------------------

func test_a_summon_at_resolve_is_not_given_swap_room() -> void:
	var rules := _rules()
	var state: MatchState = rules.state
	# The user's case again, driven through a whole round: lane 0 overflows to 5 during
	# PLAY, and every lane is back within capacity once the round is over.
	var ahri: CardState = _lane(state, 0, 0, MatchState.SLOTS_PER_ZONE, 2)[2]
	_on_board(state, 0, 1, FILLER)
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
	var newcomer := _give(state, 0, UNIT)
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE + 1)
	_end_round(rules)
	assert_eq(state.pending_swaps, [], "the queue is empty after SWAP_LANE")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE, "no lane is left over capacity")
	assert_eq(state.zone_has_space(0, 0), false, "a full lane is full again")
	for col in MatchState.COLUMNS:
		for p in 2:
			assert_true(state.zone_cards(col, p).size() <= MatchState.SLOTS_PER_ZONE,
				"lane %d of player %d is within capacity" % [col, p])


func test_a_new_card_cannot_be_placed_into_a_lane_that_is_overflowed() -> void:
	# MatchState.place_card is the last line of defence and must agree with the rules.
	var rules := _rules()
	var state: MatchState = rules.state
	var ahri := _on_board(state, 0, 0, AHRI)
	_fill(state, 0, 0, MatchState.SLOTS_PER_ZONE)  # 4 cards, Ahri among them
	state.pending_swaps.append({
		"instance_id": ahri.instance_id, "player": 0, "from_col": 0, "to_col": 1, "turn": 1,
	})
	var fifth := state.new_card(UNIT, 0, CardState.Location.HAND)
	assert_true(state.place_card(fifth.instance_id, 0, 0), "the fifth card fits while Ahri leaves")
	var sixth := state.new_card(UNIT, 0, CardState.Location.HAND)
	assert_false(state.place_card(sixth.instance_id, 0, 0), "a sixth does not")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE + 1)


# ----------------------------
# MatchBot: allow_swaps
# ----------------------------

## A state in PLAY where `player` holds `hand_ids`, with `board` resolved cards per lane
## column. `board` maps a column to the list of card ids sitting in it, so a test says
## exactly which cards are Elusive.
func _bot_state(hand_ids: Array, board: Dictionary, mana: int = 10,
		player: int = 0) -> MatchState:
	var state := MatchState.new()
	state.game_phase = MatchState.GamePhase.TURN_LOOP
	state.round_phase = MatchState.RoundPhase.PLAY
	state.turn = 3
	for raw: Variant in hand_ids:
		var c := state.new_card(str(raw), player, CardState.Location.HAND)
		state.players[player].hand.append(c.instance_id)
	state.players[player].current_mana = mana
	state.players[player].base_max_mana = 20
	for col: int in board:
		for raw: Variant in board[col]:
			var card := state.new_card(str(raw), player, CardState.Location.BOARD)
			state.place_card(card.instance_id, col, player)
			card.is_resolved = true
	return state


## The swap_card intents in `intents`.
func _swap_intents(intents: Array) -> Array:
	var swaps: Array = []
	for intent: Variant in intents:
		if intent.get("type", &"") == MatchIntents.SWAP_CARD:
			swaps.append(intent)
	return swaps


## The play_card intent in `intents`, or an empty Dictionary.
func _play_intent(intents: Array) -> Dictionary:
	for intent: Variant in intents:
		if intent.get("type", &"") == MatchIntents.PLAY_CARD:
			return intent
	return {}


func test_the_bot_never_queues_a_swap_without_the_flag() -> void:
	for seed_value in 60:
		var state := _bot_state([UNIT, "Kennen1"],
			{0: [AHRI], 1: [FILLER, FILLER, FILLER, FILLER], 2: [FILLER, FILLER]})
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		assert_eq(_swap_intents(MatchBot.decide(state, 0, rng)), [],
			"seed %d: the opponent bot must not swap" % seed_value)


func test_the_plain_decision_is_unchanged_down_to_the_rng_state() -> void:
	# The real opponent bot must be untouched by the planner: same intents AND the same
	# generator state. On a board where no swap is legal the planner bails out before it
	# draws anything, so every turn is such a case and this pins the whole no-swap path.
	# (Where a swap IS queued the two obviously differ: the bot emits an extra intent and
	# spends one more draw preferring the freed lane.)
	for seed_value in 60:
		var state := _bot_state([UNIT, "Kennen1", "Nasus1"],
			{0: [FILLER, FILLER], 1: [FILLER, FILLER], 2: [FILLER, FILLER]}, 6)
		var flagged := RandomNumberGenerator.new()
		flagged.seed = seed_value
		var plain := RandomNumberGenerator.new()
		plain.seed = seed_value
		assert_eq(MatchBot.decide(state, 0, flagged, true),
			MatchBot.decide(state, 0, plain, false),
			"seed %d: same intents with the flag on" % seed_value)
		assert_eq(flagged.state, plain.state, "seed %d: and the same draws" % seed_value)


func test_the_bot_queues_only_legal_swaps_when_the_flag_is_on() -> void:
	var swaps: int = 0
	for seed_value in 60:
		var state := _bot_state([UNIT, "Kennen1"],
			{0: [AHRI], 1: [FILLER, FILLER], 2: [FILLER]})
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var intents := MatchBot.decide(state, 0, rng, true)
		var found := _swap_intents(intents)
		if found.is_empty():
			continue
		swaps += 1
		assert_eq(found.size(), 1, "seed %d: at most one swap per turn" % seed_value)
		var swap: Dictionary = found[0]
		var card := state.card(int(swap["instance_id"]))
		assert_eq(card.owner, 0, "seed %d: its own card" % seed_value)
		assert_true(card.is_resolved, "seed %d: resolved" % seed_value)
		assert_true(card.has_keyword("Elusive"), "seed %d: Elusive" % seed_value)
		assert_ne(int(swap["to_col"]), card.col, "seed %d: another lane" % seed_value)
		assert_true(state.zone_has_space(int(swap["to_col"]), 0),
			"seed %d: the destination has room under the engine's own rule" % seed_value)
		assert_eq(intents[0].get("type", ""), MatchIntents.SWAP_CARD, "the swap comes first")
	assert_true(swaps > 5, "the bot does swap over many seeds (%d of 60)" % swaps)


func test_the_bot_never_swaps_an_unresolved_unelusive_stunned_or_queued_card() -> void:
	for seed_value in 60:
		# Lane 0 offers nothing swappable: a plain follower, an Elusive that has not
		# resolved, a stunned Elusive and an Elusive that already has a swap queued.
		# Lanes 1 and 2 hold only plain followers, so the bot must queue nothing at all.
		var state := _bot_state([UNIT],
			{0: [FILLER, AHRI, AHRI, AHRI], 1: [FILLER, FILLER], 2: [FILLER, FILLER]}, 5)
		var lane: Array[int] = _ids(state, 0, 0)
		state.card(lane[1]).is_resolved = false
		var stunned: CardState = state.card(lane[2])
		state.stuns.append({"instance_id": stunned.instance_id, "stunned_on_turn": state.turn})
		stunned.runtime_keywords.append("Stun")
		var queued: CardState = state.card(lane[3])
		state.pending_swaps.append({
			"instance_id": queued.instance_id, "player": 0,
			"from_col": queued.col, "to_col": 1, "turn": state.turn,
		})
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		assert_eq(_swap_intents(MatchBot.decide(state, 0, rng, true)), [],
			"seed %d: no lane offers anything the engine would accept" % seed_value)


func test_the_bot_only_emits_intents_the_engine_accepts() -> void:
	# The real thing: a full match driven by the flag-on bot for both players, with
	# every intent checked against the engine and every lane swept for capacity after
	# every submit.
	var swaps: int = 0
	var overflow_plays: int = 0
	for seed_value in [1, 2, 3, 5, 8, 13, 21, 34]:
		var state := MatchSetup.new_match(MatchDecks.DEFAULT_DECK_IDS,
			MatchDecks.BOT_DECK_IDS, seed_value)
		var rules := MatchRules.new(state)
		MatchCardAbilities.install(rules)
		rules.start_match()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var rounds: int = 0
		while state.game_phase == MatchState.GamePhase.TURN_LOOP and rounds < 30:
			for player in [0, 1]:
				for intent: Variant in MatchBot.decide(state, player, rng, true):
					var where: String = "seed %d turn %d player %d" % [seed_value, state.turn, player]
					var events := rules.submit(player, intent)
					assert_eq(_count(events, MatchEvents.INTENT_REJECTED), 0,
						"%s: the engine rejected %s" % [where, intent.get("type", "")])
					if intent.get("type", &"") == MatchIntents.SWAP_CARD:
						swaps += 1
					elif intent.get("type", &"") == MatchIntents.PLAY_CARD:
						var col: int = int(intent["col"])
						if col >= 0 and state.outgoing_swaps(col, player) > 0:
							overflow_plays += 1
					for lane in MatchState.COLUMNS:
						for owner in 2:
							assert_true(
								state.zone_cards(lane, owner).size() <= MatchState.SLOTS_PER_ZONE + 1,
								"%s: lane %d of player %d is within capacity + the one departure"
								% [where, lane, owner])
			rounds += 1
		assert_true(rounds > 3, "seed %d: the match ran several rounds" % seed_value)
	assert_true(swaps > 0, "the flag-on bot swapped during the matches (%d times)" % swaps)
	assert_true(overflow_plays > 0,
		"and it played into a lane that was losing a card (%d times)" % overflow_plays)


func test_the_bot_reuses_the_lane_its_card_left_and_the_engine_takes_the_fifth_card() -> void:
	# A full lane whose Elusive leaves: when the bot reuses the freed lane, the engine
	# must accept the resulting 5th card. This is the user's case, end to end.
	var reused: int = 0
	var overflowed: int = 0
	for seed_value in 40:
		var state := _bot_state([UNIT],
			{0: [AHRI, FILLER, FILLER, FILLER], 1: [FILLER],
			2: [FILLER, FILLER, FILLER, FILLER]}, 5)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var intents := MatchBot.decide(state, 0, rng, true)
		var swaps := _swap_intents(intents)
		if swaps.is_empty():
			continue
		var card := state.card(int(swaps[0]["instance_id"]))
		var play := _play_intent(intents)
		if play.is_empty() or int(play["col"]) != card.col:
			continue
		reused += 1
		# Run the same two intents through a real engine in the same situation.
		var rules := _rules()
		var live: MatchState = rules.state
		_lane(live, 0, 0, MatchState.SLOTS_PER_ZONE, 2)
		_on_board(live, 0, 1, FILLER)
		_lane(live, 0, 2, MatchState.SLOTS_PER_ZONE)
		var ahri: CardState = live.card(live.zone_cards(0, 0)[2])
		var newcomer := _give(live, 0, UNIT)
		_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 1))
		_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0))
		overflowed += 1
		assert_eq(live.card(newcomer.instance_id).slot, MatchState.SLOTS_PER_ZONE,
			"seed %d: the reuse is the overflow case" % seed_value)
		_end_round(rules)
		assert_eq(live.card(ahri.instance_id).col, 1, "seed %d: Ahri moved out" % seed_value)
		assert_eq(_slots(live, 0, 0), [0, 1, 2, 3], "seed %d: and the lane compacted" % seed_value)
	assert_true(reused > 0, "the bot reused the freed lane (%d of 40 seeds)" % reused)
	assert_eq(overflowed, reused, "every reuse was a legal overflow")


func test_a_pile_of_swaps_never_overflows_a_lane_when_they_run() -> void:
	# The queue-order argument, hammered: fill the board with Elusive cards, queue as
	# many swaps as the engine will take in a random order (with random plays mixed in),
	# then let SWAP_LANE run. No lane may be left over capacity, and every swap the
	# engine accepted must have actually run — a swap silently dropped for a full
	# destination would break both.
	var accepted_swaps: int = 0
	for seed_value in 120:
		var rules := _rules()
		var state: MatchState = rules.state
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		# Spread Elusive cards over all three lanes at random, filling them up.
		var elusives: Array[int] = []
		for col in MatchState.COLUMNS:
			var count: int = rng.randi_range(1, MatchState.SLOTS_PER_ZONE)
			for i in count:
				elusives.append(_lane(state, 0, col, 1, 0)[0].instance_id)
		for _i in rng.randi_range(1, MatchState.SLOTS_PER_ZONE):
			var col: int = rng.randi_range(0, MatchState.COLUMNS - 1)
			if state.zone_cards(col, 0).size() < MatchState.SLOTS_PER_ZONE:
				_on_board(state, 0, col, FILLER)
		# Queue swaps in a random order, accepting whatever the engine takes.
		var order: Array = elusives.duplicate()
		for i in range(order.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Variant = order[i]
			order[i] = order[j]
			order[j] = tmp
		var queued: Array[Dictionary] = []
		for raw: Variant in order:
			var id: int = int(raw)
			var card := state.card(id)
			if card.col < 0 or card.col >= MatchState.COLUMNS:
				continue
			var dest: int = rng.randi_range(0, MatchState.COLUMNS - 1)
			var events := rules.submit(0, MatchIntents.swap_card(id, dest))
			if _reason(events) == "":
				accepted_swaps += 1
				queued.append({"id": id, "from": card.col, "to": dest})
		if queued.is_empty():
			continue
		# And a play or two, which is where the temporary fifth card comes from.
		for _i in 2:
			var card2 := _give(state, 0, UNIT)
			rules.submit(0, MatchIntents.play_card(card2.instance_id,
				rng.randi_range(0, MatchState.COLUMNS - 1)))
		var where: String = "seed %d" % seed_value
		for col2 in MatchState.COLUMNS:
			assert_true(state.zone_cards(col2, 0).size()
				<= MatchState.SLOTS_PER_ZONE + state.outgoing_swaps(col2, 0),
				"%s: lane %d never holds more than capacity plus its departures"
				% [where, col2])
		_end_round(rules)
		for col3 in MatchState.COLUMNS:
			assert_true(state.zone_cards(col3, 0).size() <= MatchState.SLOTS_PER_ZONE,
				"%s: lane %d is back within capacity after SWAP_LANE" % [where, col3])
		for entry: Dictionary in queued:
			assert_eq(state.card(int(entry["id"])).col, int(entry["to"]),
				"%s: an accepted swap may not be dropped at SWAP_LANE" % where)
	assert_true(accepted_swaps > 200,
		"the stress test really queued swaps (%d of them)" % accepted_swaps)


func test_a_swap_ability_cannot_overflow_a_lane_though_it_may_take_a_reserved_slot() -> void:
	# The documented CAVEAT of _execute_swaps, pinned. Irelia's {swap} summons a Blade
	# into the lane it just left, and that placement can take the slot a later arrival was
	# reserved for. It must NOT push the lane over capacity — and the price is that the
	# reserved swap is cancelled, which the rules already allow for a destination that
	# "filled up meanwhile".
	var rules := _rules()
	MatchCardAbilities.install(rules)
	var state: MatchState = rules.state
	var irelia := _on_board(state, 0, 0, IRELIA)  # {swap} -> summon a Blade in the old lane
	_lane(state, 0, 0, MatchState.SLOTS_PER_ZONE - 1)
	_on_board(state, 0, 1, FILLER)
	var incoming: CardState = _lane(state, 0, 2, 1, 0)[0]
	_assert_accepted(rules, 0, MatchIntents.swap_card(irelia.instance_id, 1))
	assert_eq(state.outgoing_swaps(0, 0), 1, "lane 0 frees a slot, so lane 2 -> 0 is legal")
	_assert_accepted(rules, 0, MatchIntents.swap_card(incoming.instance_id, 0))

	var events := _end_round(rules)
	assert_eq(_count(events, MatchEvents.CARD_SWAPPED), 1, "the reserved swap is cancelled")
	assert_eq(state.card(incoming.instance_id).col, 2, "the Zed stayed in lane 2")
	assert_eq(_ids(state, 0, 0).size(), MatchState.SLOTS_PER_ZONE,
		"lane 0 is back within capacity: Irelia left and the Blade took the freed slot")
	var has_blade: bool = false
	for id in _ids(state, 0, 0):
		if state.card(id).card_id == "Blade":
			has_blade = true
	assert_true(has_blade, "Irelia's {swap} summoned the Blade into her old lane")


func test_a_swap_ability_cannot_overflow_a_lane_whose_room_is_being_reused() -> void:
	# Same ability, but TWO cards are queued out of the lane the Blade lands in and plays
	# take the freed room, so the lane sits at capacity + 2 when the Blade arrives. Even
	# then nothing may end up over capacity once the queue has run.
	var rules := _rules()
	MatchCardAbilities.install(rules)
	var state: MatchState = rules.state
	var irelia := _on_board(state, 0, 0, IRELIA)
	var ahri := _on_board(state, 0, 0, AHRI)
	_lane(state, 0, 0, MatchState.SLOTS_PER_ZONE - 2)
	_on_board(state, 0, 1, FILLER)
	_on_board(state, 0, 2, FILLER)
	_assert_accepted(rules, 0, MatchIntents.swap_card(irelia.instance_id, 1))
	_assert_accepted(rules, 0, MatchIntents.swap_card(ahri.instance_id, 2),
		"the lane frees two slots once")
	# Plays may now use the freed room.
	for _i in 2:
		var newcomer := _give(state, 0, UNIT)
		_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 0),
			"a play into a lane with two departures queued")
	assert_eq(state.zone_cards(0, 0).size(), MatchState.SLOTS_PER_ZONE + 2,
		"lane 0 holds capacity plus its two departures")
	_end_round(rules)
	for col in MatchState.COLUMNS:
		assert_true(state.zone_cards(col, 0).size() <= MatchState.SLOTS_PER_ZONE,
			"lane %d is back within capacity after SWAP_LANE" % col)


