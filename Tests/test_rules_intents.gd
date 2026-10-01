## Tests for the intent layer of MatchRules: every rejection reason in the contract
## and the success path of each of the four intents.
extends "res://Tests/test_case.gd"

## Lanes with no board effect of their own, so nothing but the tested intent changes
## the board. Noxkraya Arena only restricts placement, Sunken Temple only draws.
const LANES := ["SunkenTemple", "SunkenTemple", "NoxkrayaArena"]

## Records the ability hooks the engine calls.
class SpyAbilities extends MatchAbilities:
	var calls: Array = []

	func on_play(id: int) -> void:
		calls.append(["on_play", id])

	func after_change() -> void:
		calls.append(["after_change"])


var _spy: SpyAbilities


func before_each() -> void:
	_spy = SpyAbilities.new()


# ----------------------------
# Helpers
# ----------------------------

## A started match with a deep deck, so nothing runs out mid-test.
func _rules() -> MatchRules:
	var pool: Array = ["Chip", "Nasus1", "Ahri1", "Tryndamere1", "Blade", "Valor", "Janna1", "Kennen1", "Irelia1", "Renekton1"]
	var deck: Array = []
	for i in 20:
		deck.append(pool[i % pool.size()])
	var rules := MatchRules.new(MatchSetup.new_match(deck, deck.duplicate(), 7))
	rules.set_abilities(_spy)
	rules.start_match(Array(LANES))
	return rules


## A started match in which both players have plenty of mana and headroom to spend it.
func _rich_rules() -> MatchRules:
	var rules := _rules()
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


## The single rejection reason in `events`, or "" when `events` is not one rejection.
func _reason(events: Array) -> String:
	if events.size() != 1 or events[0].get("type", &"") != MatchEvents.INTENT_REJECTED:
		return ""
	return str(events[0]["reason"])


## Submits one intent and asserts it was rejected for `expected`.
func _assert_rejected(rules: MatchRules, player: int, intent: Dictionary, expected: String) -> void:
	var events := rules.submit(player, intent)
	assert_eq(_reason(events), expected, "%s rejected as %s" % [intent.get("type", ""), expected])


## Submits one intent and asserts it was accepted, returning its events.
func _assert_accepted(rules: MatchRules, player: int, intent: Dictionary) -> Array:
	var events := rules.submit(player, intent)
	assert_eq(_reason(events), "", "%s was accepted" % intent.get("type", ""))
	return events


# ----------------------------
# play_card — rejections
# ----------------------------

func test_play_rejected_after_the_player_ended_their_turn() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	rules.state.players[0].ended_turn = true
	_assert_rejected(rules, 0, MatchIntents.play_card(card.instance_id, 0), "turn_ended")


func test_play_rejected_when_the_card_is_not_in_hand() -> void:
	var rules := _rich_rules()
	var theirs := _give(rules.state, 1, "Chip")
	_assert_rejected(rules, 0, MatchIntents.play_card(theirs.instance_id, 0), "not_in_hand")
	_assert_rejected(rules, 0, MatchIntents.play_card(9999, 0), "not_in_hand")


func test_play_rejected_when_the_card_is_in_the_deck() -> void:
	var rules := _rich_rules()
	var deck_id: int = rules.state.players[0].deck[0]
	_assert_rejected(rules, 0, MatchIntents.play_card(deck_id, 0), "not_in_hand")


func test_play_rejected_when_the_card_is_already_on_the_board() -> void:
	var rules := _rich_rules()
	var played := _on_board(rules.state, 0, 0, "Chip")
	_assert_rejected(rules, 0, MatchIntents.play_card(played.instance_id, 1), "not_in_hand")


func test_spell_rejected_outside_the_spell_zone() -> void:
	var rules := _rich_rules()
	var spell := _give(rules.state, 0, "HexCoreUpgrade")
	_assert_rejected(rules, 0, MatchIntents.play_card(spell.instance_id, 1), "spell_needs_spell_zone")
	assert_eq(rules.state.zone_cards(1, 0), [], "and nothing was placed")


func test_unit_rejected_in_the_spell_zone() -> void:
	var rules := _rich_rules()
	var unit := _give(rules.state, 0, "Chip")
	_assert_rejected(rules, 0, MatchIntents.play_card(unit.instance_id, MatchState.SPELL_COL), "unit_needs_lane")
	assert_eq(rules.state.zone_cards(MatchState.SPELL_COL, 0), [], "and nothing was placed")


func test_play_rejected_in_a_restricted_lane() -> void:
	var rules := _rich_rules()
	rules.state.noxkraya_col = 1
	var unit := _give(rules.state, 0, "Chip")
	_assert_rejected(rules, 0, MatchIntents.play_card(unit.instance_id, 0), "noxkraya")
	_assert_rejected(rules, 0, MatchIntents.play_card(unit.instance_id, 2), "noxkraya")
	_assert_accepted(rules, 0, MatchIntents.play_card(unit.instance_id, 1))


func test_play_rejected_in_a_full_zone() -> void:
	var rules := _rich_rules()
	for _i in MatchState.SLOTS_PER_ZONE:
		_on_board(rules.state, 0, 2, "Chip")
	var unit := _give(rules.state, 0, "Chip")
	_assert_rejected(rules, 0, MatchIntents.play_card(unit.instance_id, 2), "zone_full")
	assert_eq(rules.state.zone_cards(2, 0).size(), MatchState.SLOTS_PER_ZONE, "the zone is unchanged")


func test_play_rejected_when_the_spell_zone_is_full() -> void:
	var rules := _rich_rules()
	for _i in MatchState.SPELL_SLOTS:
		_on_board(rules.state, 0, MatchState.SPELL_COL, "HexCoreUpgrade")
	var spell := _give(rules.state, 0, "HexCoreUpgrade")
	_assert_rejected(rules, 0, MatchIntents.play_card(spell.instance_id, MatchState.SPELL_COL), "zone_full")


func test_play_rejected_without_enough_mana() -> void:
	var rules := _rules()
	var card := _give(rules.state, 0, "Nasus1")  # costs 2
	rules.state.players[0].current_mana = 1
	_assert_rejected(rules, 0, MatchIntents.play_card(card.instance_id, 0), "not_enough_mana")
	assert_eq(rules.state.players[0].current_mana, 1, "a refused play costs nothing")
	assert_true(rules.state.players[0].hand.has(card.instance_id), "and the card stays in hand")


func test_cost_modifier_counts_towards_the_mana_check() -> void:
	var rules := _rules()
	var card := _give(rules.state, 0, "Nasus1")  # costs 2
	rules.state.players[0].current_mana = 1
	_assert_rejected(rules, 0, MatchIntents.play_card(card.instance_id, 0), "not_enough_mana")
	rules.ops.change_cost(card.instance_id, -1)
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))


func test_a_rejected_play_changes_nothing() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	rules.submit(0, MatchIntents.play_card(card.instance_id, MatchState.SPELL_COL))
	assert_eq(rules.state.zone_cards(MatchState.SPELL_COL, 0), [], "no zone changed")
	assert_eq(rules.state.played_this_turn, [], "nothing was queued for resolve")
	assert_eq(rules.state.play_order, [], "the play order is untouched")
	assert_eq(rules.state.summoned, [], "no summoned tracker was written")
	assert_eq(rules.state.players[0].undo_stack, [], "no undo record either")
	assert_eq(rules.state.players[0].current_mana, 20, "and no mana was spent")


# ----------------------------
# play_card — success
# ----------------------------

func test_play_spends_mana_and_announces_the_card() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")  # costs 1
	rules.state.players[0].current_mana = 5
	var events := _assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 1))
	assert_eq(events.size(), 2, "the spend and the play are both announced")
	assert_eq(events[0]["type"], MatchEvents.MANA_CHANGED)
	assert_eq(events[0]["current"], 4, "the mana was spent")
	assert_eq(events[1]["type"], MatchEvents.CARD_PLAYED)
	assert_eq(events[1]["player"], 0)
	assert_eq(events[1]["instance_id"], card.instance_id)
	assert_eq(events[1]["card_id"], "Chip")
	assert_eq(events[1]["col"], 1)
	assert_eq(rules.state.players[0].current_mana, 4, "the pool shrank")


func test_play_places_the_card_face_down_in_its_zone() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 2))
	var played: CardState = rules.state.card(card.instance_id)
	assert_eq(played.location, CardState.Location.BOARD)
	assert_eq(played.col, 2)
	assert_eq(rules.state.zone_cards(2, 0), [card.instance_id], "the card is in its owner's zone")
	assert_false(played.is_resolved, "it is face down until resolve")
	assert_false(played.has_keyword("Elusive"), "a card played this round cannot be swapped yet")
	assert_eq(rules.state.played_this_turn, [card.instance_id], "it is queued for this round's resolve")


func test_play_ignores_the_slot_hint_and_appends() -> void:
	var rules := _rich_rules()
	var first := _on_board(rules.state, 0, 0, "Chip")
	var card := _give(rules.state, 0, "Blade")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0, 0))
	assert_eq(rules.state.zone_cards(0, 0), [first.instance_id, card.instance_id], "the play is appended")
	assert_eq(rules.state.card(card.instance_id).slot, 1, "and lands in the slot after the existing cards")


func test_play_writes_the_summoned_tracker_and_the_undo_record() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var hand_before: int = state.players[0].hand.size()
	var card := _give(state, 0, "Chip")
	var hand_index: int = state.players[0].hand.find(card.instance_id)
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	assert_eq(state.summoned.size(), 1)
	var entry: Dictionary = state.summoned[0]
	assert_eq(entry["card_id"], "Chip")
	assert_eq(entry["owner_player_id"], 0)
	assert_true(entry["was_played_from_hand"], "played from hand")
	assert_false(entry["is_resolved"], "not resolved yet")
	assert_eq(entry["instance_id"], card.instance_id)
	assert_eq(state.play_order, [card.instance_id], "the card joins the permanent play order")
	assert_eq(state.players[0].hand.size(), hand_before, "one card left the hand")
	assert_eq(state.players[0].undo_stack.size(), 1)
	assert_eq(state.players[0].undo_stack[0]["instance_id"], card.instance_id)
	assert_eq(state.players[0].undo_stack[0]["hand_index"], hand_index, "the hand slot is remembered")
	assert_eq(state.players[0].undo_stack[0]["cost"], card.get_current_cost())


func test_play_order_holds_each_card_once() -> void:
	var rules := _rich_rules()
	var first := _give(rules.state, 0, "Chip")
	var second := _give(rules.state, 0, "Blade")
	_assert_accepted(rules, 0, MatchIntents.play_card(first.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.play_card(second.instance_id, 1))
	_assert_accepted(rules, 0, MatchIntents.undo())
	_assert_accepted(rules, 0, MatchIntents.play_card(first.instance_id, 2))
	_assert_accepted(rules, 0, MatchIntents.undo())
	_assert_accepted(rules, 0, MatchIntents.play_card(first.instance_id, 2))
	var unique: Array = []
	for id in rules.state.play_order:
		if not unique.has(id):
			unique.append(id)
	assert_eq(rules.state.play_order, unique, "the play order never lists a card twice")


func test_play_can_fill_a_zone_exactly() -> void:
	var rules := _rich_rules()
	for _i in MatchState.SLOTS_PER_ZONE - 1:
		_on_board(rules.state, 0, 0, "Chip")
	var last := _give(rules.state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(last.instance_id, 0))
	var overflow := _give(rules.state, 0, "Chip")
	_assert_rejected(rules, 0, MatchIntents.play_card(overflow.instance_id, 0), "zone_full")


# ----------------------------
# undo
# ----------------------------

func test_undo_rejected_with_an_empty_stack() -> void:
	var rules := _rich_rules()
	_assert_rejected(rules, 0, MatchIntents.undo(), "nothing_to_undo")


func test_undo_rejected_after_the_player_ended_their_turn() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	rules.state.players[0].ended_turn = true
	_assert_rejected(rules, 0, MatchIntents.undo(), "turn_ended")
	assert_true(rules.state.zone_cards(0, 0).has(card.instance_id), "the card stays on the board")


func test_undo_restores_the_hand_order_exactly() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var a := _give(state, 0, "Chip")
	var b := _give(state, 0, "Blade")
	var c := _give(state, 0, "Valor")
	var d := _give(state, 0, "Janna1")
	var before: Array = state.players[0].hand.duplicate()
	assert_eq(before[0], d.instance_id, "the hand is newest first")
	assert_eq(before[1], c.instance_id)
	assert_eq(before[2], b.instance_id)
	assert_eq(before[3], a.instance_id)
	var after_plays: Array = before.duplicate()
	after_plays.erase(b.instance_id)
	after_plays.erase(d.instance_id)
	_assert_accepted(rules, 0, MatchIntents.play_card(b.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.play_card(d.instance_id, 1))
	assert_eq(state.players[0].hand, after_plays, "both plays left the hand")
	var events := _assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(events.size(), 2, "the refund and the undo are both announced")
	assert_eq(events[0]["type"], MatchEvents.MANA_CHANGED)
	assert_eq(events[1]["type"], MatchEvents.PLAY_UNDONE)
	assert_eq(events[1]["player"], 0)
	assert_eq(events[1]["instance_ids"], [d.instance_id, b.instance_id], "both cards are listed")
	assert_eq(state.players[0].hand, before, "the hand is exactly as it was")
	for card: CardState in [b, d]:
		assert_eq(card.location, CardState.Location.HAND, "the card is back in hand")
		assert_eq(card.col, -1)
		assert_eq(card.slot, -1)


func test_undo_refunds_the_total_cost() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var cheap := _give(state, 0, "Chip")  # 1
	var pricier := _give(state, 0, "Nasus1")  # 2
	state.players[0].current_mana = 5
	_assert_accepted(rules, 0, MatchIntents.play_card(pricier.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.play_card(cheap.instance_id, 0))
	assert_eq(state.players[0].current_mana, 2, "3 mana was spent")
	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(state.players[0].current_mana, 5, "every spent mana came back")


func test_undo_cannot_refund_past_the_maximum() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	rules.state.players[0].base_max_mana = 1
	rules.state.players[0].current_mana = 20
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(rules.state.players[0].current_mana, 1, "the pool is clamped to the maximum, like the old refund")


func test_undo_drops_the_unresolved_summoned_entries() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var card := _give(state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	assert_eq(state.summoned.size(), 1, "the play left a tracker behind")
	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(state.summoned, [], "the undone play left no tracker")
	assert_eq(state.played_this_turn, [], "it is no longer queued for resolve")
	assert_eq(state.play_order, [], "and no longer in the play order")
	assert_eq(state.zone_cards(0, 0), [], "the board is empty again")


func test_undo_only_drops_its_own_plays() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var mine := _give(state, 0, "Chip")
	var theirs := _give(state, 1, "Chip")
	_assert_accepted(rules, 1, MatchIntents.play_card(theirs.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.play_card(mine.instance_id, 1))
	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(state.zone_cards(1, 0), [], "the undoing player's play came back")
	assert_eq(state.zone_cards(0, 1), [theirs.instance_id], "the opponent's play is untouched")
	assert_eq(state.summoned.size(), 1, "and only the undone tracker is gone")
	assert_eq(state.summoned[0]["instance_id"], theirs.instance_id)


func test_undo_clears_the_stack_so_it_only_works_once() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(rules.state.players[0].undo_stack, [])
	_assert_rejected(rules, 0, MatchIntents.undo(), "nothing_to_undo")


func test_the_stack_is_cleared_at_the_start_of_every_turn() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	assert_eq(rules.state.players[0].undo_stack.size(), 1)
	rules.submit(0, MatchIntents.end_turn())
	rules.submit(1, MatchIntents.end_turn())
	assert_eq(rules.state.turn, 2, "the round resolved")
	assert_eq(rules.state.players[0].undo_stack, [], "the new turn reset the undo stack")
	_assert_rejected(rules, 0, MatchIntents.undo(), "nothing_to_undo")


# ----------------------------
# swap_card
# ----------------------------

func test_swap_rejected_after_the_player_ended_their_turn() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 0, "Ahri1")
	rules.state.players[0].ended_turn = true
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "turn_ended")


func test_swap_rejected_for_someone_elses_card() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 1, 0, "Ahri1")
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "not_your_card")
	assert_eq(rules.state.pending_swaps, [], "no swap was queued")


func test_swap_rejected_for_an_unknown_card() -> void:
	var rules := _rich_rules()
	_assert_rejected(rules, 0, MatchIntents.swap_card(9999, 1), "not_your_card")


func test_swap_rejected_for_a_card_that_is_not_on_the_board() -> void:
	var rules := _rich_rules()
	var in_hand := _give(rules.state, 0, "Ahri1")
	_assert_rejected(rules, 0, MatchIntents.swap_card(in_hand.instance_id, 1), "not_on_board")
	var in_spell_zone := _on_board(rules.state, 0, MatchState.SPELL_COL, "HexCoreUpgrade")
	_assert_rejected(rules, 0, MatchIntents.swap_card(in_spell_zone.instance_id, 1), "not_on_board")


func test_swap_rejected_for_a_card_played_this_round() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Ahri1")
	_assert_accepted(rules, 0, MatchIntents.play_card(card.instance_id, 0))
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "not_resolved")


func test_swap_rejected_without_the_elusive_keyword() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 0, "Chip")
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "not_elusive")


func test_swap_rejected_while_stunned() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 0, "Ahri1")
	rules.state.stuns.append({"instance_id": card.instance_id, "stunned_on_turn": rules.state.turn})
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "stunned")


func test_swap_rejected_when_a_swap_is_already_queued() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 0, "Ahri1")
	_assert_accepted(rules, 0, MatchIntents.swap_card(card.instance_id, 1))
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 2), "already_swapping")
	assert_eq(rules.state.pending_swaps.size(), 1, "the first swap stands")


func test_swap_rejected_into_its_own_column() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 2, "Ahri1")
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 2), "same_column")


func test_swap_rejected_into_a_full_column() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 0, "Ahri1")
	for _i in MatchState.SLOTS_PER_ZONE:
		_on_board(rules.state, 0, 1, "Chip")
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "zone_full")


func test_swap_queued_records_origin_and_destination() -> void:
	var rules := _rich_rules()
	var card := _on_board(rules.state, 0, 0, "Ahri1")
	var events := _assert_accepted(rules, 0, MatchIntents.swap_card(card.instance_id, 2))
	assert_eq(events.size(), 1, "one event")
	assert_eq(events[0]["type"], MatchEvents.SWAP_STARTED)
	assert_eq(events[0]["player"], 0)
	assert_eq(events[0]["instance_id"], card.instance_id)
	assert_eq(events[0]["from_col"], 0)
	assert_eq(events[0]["to_col"], 2)
	assert_eq(rules.state.card(card.instance_id).col, 0, "the card waits for SWAP_LANE")
	assert_eq(rules.state.pending_swaps.size(), 1)
	var entry: Dictionary = rules.state.pending_swaps[0]
	assert_eq(entry["instance_id"], card.instance_id)
	assert_eq(entry["player"], 0)
	assert_eq(entry["from_col"], 0)
	assert_eq(entry["to_col"], 2)
	assert_eq(entry["turn"], rules.state.turn)


func test_a_queued_swap_reserves_its_destination_slot() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var swapper := _on_board(state, 0, 0, "Ahri1")
	for _i in MatchState.SLOTS_PER_ZONE - 1:
		_on_board(state, 0, 2, "Chip")
	_assert_accepted(rules, 0, MatchIntents.swap_card(swapper.instance_id, 2))
	var newcomer := _give(state, 0, "Blade")
	_assert_rejected(rules, 0, MatchIntents.play_card(newcomer.instance_id, 2), "zone_full")
	assert_eq(state.zone_cards(2, 0).size(), MatchState.SLOTS_PER_ZONE - 1, "the reserved slot stayed empty")


func test_two_swaps_into_the_same_column_both_reserve_a_slot() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var first := _on_board(state, 0, 0, "Ahri1")
	var second := _on_board(state, 0, 1, "Ahri1")
	for _i in MatchState.SLOTS_PER_ZONE - 2:
		_on_board(state, 0, 2, "Chip")
	_assert_accepted(rules, 0, MatchIntents.swap_card(first.instance_id, 2))
	_assert_accepted(rules, 0, MatchIntents.swap_card(second.instance_id, 2))
	assert_eq(rules.state.pending_swaps.size(), 2, "both swaps are queued")
	var newcomer := _give(state, 0, "Blade")
	_assert_rejected(rules, 0, MatchIntents.play_card(newcomer.instance_id, 2), "zone_full")


func test_a_reservation_does_not_block_the_column_the_card_is_leaving() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var swapper := _on_board(state, 0, 0, "Ahri1")
	for _i in MatchState.SLOTS_PER_ZONE - 1:
		_on_board(state, 0, 2, "Chip")
	_assert_accepted(rules, 0, MatchIntents.swap_card(swapper.instance_id, 2))
	var newcomer := _give(state, 0, "Blade")
	_assert_accepted(rules, 0, MatchIntents.play_card(newcomer.instance_id, 1))


func test_a_reservation_only_binds_its_own_player() -> void:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	var swapper := _on_board(state, 0, 0, "Ahri1")
	for _i in MatchState.SLOTS_PER_ZONE - 1:
		_on_board(state, 0, 1, "Chip")
	_on_board(state, 1, 1, "Chip")
	_assert_accepted(rules, 0, MatchIntents.swap_card(swapper.instance_id, 1))
	var theirs := _give(state, 1, "Blade")
	_assert_accepted(rules, 1, MatchIntents.play_card(theirs.instance_id, 1))


# ----------------------------
# Noxkraya Arena
# ----------------------------

func test_noxkraya_restricts_units_but_not_spells() -> void:
	var rules := _rich_rules()
	rules.state.noxkraya_col = 1
	var unit := _give(rules.state, 0, "Chip")
	var spell := _give(rules.state, 0, "HexCoreUpgrade")
	_assert_rejected(rules, 0, MatchIntents.play_card(unit.instance_id, 0), "noxkraya")
	_assert_accepted(rules, 0, MatchIntents.play_card(spell.instance_id, MatchState.SPELL_COL))
	_assert_accepted(rules, 0, MatchIntents.play_card(unit.instance_id, 1))
	assert_eq(rules.state.zone_cards(1, 0), [unit.instance_id], "the unit is in the active lane")


func test_noxkraya_restricts_the_opponent_too() -> void:
	var rules := _rich_rules()
	rules.state.noxkraya_col = 0
	var unit := _give(rules.state, 1, "Chip")
	_assert_rejected(rules, 1, MatchIntents.play_card(unit.instance_id, 1), "noxkraya")
	_assert_accepted(rules, 1, MatchIntents.play_card(unit.instance_id, 0))


func test_no_lane_is_restricted_while_noxkraya_is_unset() -> void:
	var rules := _rich_rules()
	rules.state.noxkraya_col = -1
	var unit := _give(rules.state, 0, "Chip")
	_assert_accepted(rules, 0, MatchIntents.play_card(unit.instance_id, 0))


# ----------------------------
# end_turn and phases
# ----------------------------

func test_end_turn_rejected_when_the_player_already_ended() -> void:
	var rules := _rich_rules()
	rules.submit(1, MatchIntents.end_turn())
	_assert_rejected(rules, 1, MatchIntents.end_turn(), "turn_ended")


func test_end_turn_is_accepted_and_closes_the_round() -> void:
	var rules := _rich_rules()
	var first := rules.submit(0, MatchIntents.end_turn())
	assert_eq(first.size(), 1, "the first end turn only announces itself")
	assert_eq(first[0]["type"], MatchEvents.TURN_ENDED)
	assert_eq(first[0]["player"], 0)
	var second := rules.submit(1, MatchIntents.end_turn())
	assert_eq(second[0]["type"], MatchEvents.TURN_ENDED, "the second one announces itself too, first")
	assert_eq(second[0]["player"], 1)
	assert_true(second.size() > 1, "and then resolves the round")
	assert_eq(rules.state.turn, 2, "and opens the next turn")
	assert_eq(rules.state.round_phase, MatchState.RoundPhase.PLAY, "which is in PLAY again")


func test_intents_are_rejected_outside_the_play_phase() -> void:
	var rules := _rich_rules()
	var card := _give(rules.state, 0, "Chip")
	rules.state.round_phase = MatchState.RoundPhase.RESOLVE
	_assert_rejected(rules, 0, MatchIntents.play_card(card.instance_id, 0), "wrong_phase")
	_assert_rejected(rules, 0, MatchIntents.undo(), "wrong_phase")
	_assert_rejected(rules, 0, MatchIntents.end_turn(), "wrong_phase")
	_assert_rejected(rules, 0, MatchIntents.swap_card(card.instance_id, 1), "wrong_phase")


# ----------------------------
# Undo restores the hand for EVERY play order
# ----------------------------

## A match where player 0's hand holds exactly four fresh 1-cost cards, newest first.
## The cards drawn by start_match go back to the deck so the hand is predictable.
func _four_card_hand() -> MatchRules:
	var rules := _rich_rules()
	var state: MatchState = rules.state
	for id in state.players[0].hand.duplicate():
		state.remove_from_hand(0, id)
		state.players[0].deck.push_front(id)
	_give(state, 0, "Chip")  # 1
	_give(state, 0, "Blade")  # 1
	_give(state, 0, "Valor")  # 1
	_give(state, 0, "Janna1")  # 1
	return rules


## Plays the cards picked by `picks` (positions in the starting hand) into their own
## columns, undoes the round and returns the restored hand.
## Every recorded hand_index refers to the hand as it was at that play, so the undo has
## to walk the plays backwards (LIFO) to put every card back where it came from.
func _undo_restores(picks: Array) -> Array:
	var rules := _four_card_hand()
	var state: MatchState = rules.state
	var before: Array = state.players[0].hand.duplicate()
	for i in picks.size():
		var card_id: int = before[int(picks[i])]
		_assert_accepted(rules, 0, MatchIntents.play_card(card_id, i))
	assert_eq(state.players[0].hand.size(), before.size() - picks.size(), "%d cards left the hand" % picks.size())
	_assert_accepted(rules, 0, MatchIntents.undo())
	return state.players[0].hand


func test_undo_restores_the_hand_after_every_order_of_two_plays() -> void:
	var before: Array = _four_card_hand().state.players[0].hand.duplicate()
	for i in 4:
		for j in 4:
			if i == j:
				continue
			assert_eq(_undo_restores([i, j]), before, "playing hand[%d] then hand[%d] restores the hand" % [i, j])


func test_undo_restores_the_hand_after_every_order_of_three_plays() -> void:
	var before: Array = _four_card_hand().state.players[0].hand.duplicate()
	for i in 4:
		for j in 4:
			for k in 4:
				if i == j or j == k or i == k:
					continue
				assert_eq(
					_undo_restores([i, j, k]), before,
					"playing hand[%d], hand[%d], hand[%d] restores the hand" % [i, j, k]
				)


func test_undo_restores_the_hand_when_the_same_card_is_played_twice_around_an_undo() -> void:
	var rules := _four_card_hand()
	var state: MatchState = rules.state
	var before: Array = state.players[0].hand.duplicate()
	_assert_accepted(rules, 0, MatchIntents.play_card(before[1], 0))
	_assert_accepted(rules, 0, MatchIntents.undo())
	_assert_accepted(rules, 0, MatchIntents.play_card(before[1], 1))
	_assert_accepted(rules, 0, MatchIntents.undo())
	assert_eq(state.players[0].hand, before, "two separate undo rounds leave the hand untouched")
