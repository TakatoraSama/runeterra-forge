## Tests for MatchOps: the state-mutating primitives that emit their own events.
extends "res://Tests/test_case.gd"

const DECK := ["Azir1", "Nasus1", "Chip", "Ahri1", "Kennen1"]

var state: MatchState
var ops: MatchOps
var log: Array


func before_each() -> void:
	state = MatchSetup.new_match(DECK, DECK, 4242)
	log = []
	ops = MatchOps.new(state, _collect, MatchAbilities.new())


func _collect(event: Dictionary) -> void:
	log.append(event)


## The events of one type, in emission order.
func _of_type(type: Variant) -> Array:
	var out: Array = []
	for e: Dictionary in log:
		if e["type"] == type:
			out.append(e)
	return out


## Drops the deck down to `count` cards so draws and Deep are easy to control.
func _shrink_deck(player: int, count: int) -> Array[int]:
	var deck: Array[int] = state.players[player].deck
	while deck.size() > count:
		deck.pop_back()
	return deck


## Puts a card of player `p` into their hand, drawn out of their deck.
func _card_in_hand(player: int) -> CardState:
	var id: int = ops.draw(player)
	return state.card(id)


# --- draw ---

func test_draw_moves_top_card_and_records_tracker() -> void:
	var top: int = state.players[0].deck[0]
	var card := state.card(top)
	var drawn := ops.draw(0)
	assert_eq(drawn, top, "the top of the deck comes over")
	assert_false(state.players[0].deck.has(top), "it left the deck")
	assert_eq(state.players[0].hand[0], top, "draws land at the front of the hand")
	assert_eq(card.location, CardState.Location.HAND)

	assert_eq(state.drawn.size(), 1)
	assert_eq(state.drawn[0], {
		"card_id": card.card_id,
		"owner_player_id": 0,
		"turn": state.turn,
		"instance_id": top,
	}, "Janna's draw tracker has exactly the contract keys")

	var events := _of_type(MatchEvents.CARD_DRAWN)
	assert_eq(events.size(), 1)
	assert_eq(events[0], MatchEvents.card_drawn(0, top, card.card_id))


func test_draw_on_empty_deck_is_a_silent_minus_one() -> void:
	_shrink_deck(0, 0)
	assert_eq(ops.draw(0), -1)
	assert_eq(log, [], "an empty deck emits nothing at all")
	assert_eq(state.drawn, [], "and records no tracker")


func test_draw_going_deep_is_announced_once() -> void:
	_shrink_deck(0, 1)
	assert_eq(ops.draw(0) > 0, true, "the last card still draws")
	assert_true(state.players[0].is_deep, "an empty deck means Deep")
	assert_eq(_of_type(MatchEvents.DEEP_CHANGED), [MatchEvents.deep_changed(0, true)])

	# Once Deep, never re-announced: Sunken Temple can put cards back in the deck.
	state.players[0].deck.append(state.players[0].hand[0])
	state.players[0].hand.remove_at(0)
	ops.draw(0)
	log.clear()
	ops.set_deep(0)
	assert_eq(log, [], "set_deep on an already Deep player does nothing")
	assert_true(state.players[0].is_deep)


func test_draw_calls_the_card_drawn_ability_hook() -> void:
	var spy := _SpyAbilities.new()
	spy.bind(state, ops)
	ops.abilities = spy
	var id: int = ops.draw(1)
	assert_eq(spy.drawn_ids, [id], "on_card_drawn fires after every draw")
	_shrink_deck(1, 0)
	ops.draw(1)
	assert_eq(spy.drawn_ids, [id], "an empty deck never reaches the hook")


# --- create_in_hand ---

func test_create_in_hand_puts_the_card_at_index_zero() -> void:
	_shrink_deck(1, 0)
	var before: int = state.players[0].hand.size()
	var id: int = ops.create_in_hand("Chip", 0)
	assert_true(id > 0, "a new instance id is returned")
	assert_eq(state.players[0].hand[0], id, "created cards land at the front of the hand")
	assert_eq(state.players[0].hand.size(), before + 1)
	var card := state.card(id)
	assert_eq(card.card_id, "Chip")
	assert_eq(card.owner, 0)
	assert_eq(card.location, CardState.Location.HAND)
	assert_eq(state.zones.get(Vector2i(0, 0), []).has(id), false, "it is not on the board")


func test_create_in_hand_tracker_and_event() -> void:
	var id: int = ops.create_in_hand("Chip", 0, -1)
	assert_eq(state.created.size(), 1)
	assert_eq(state.created[0], {
		"card_id": "Chip",
		"owner_player_id": 0,
		"creator_player_id": 0,
		"creator_card_id": "",
		"created_at_turn": state.turn,
		"instance_id": id,
	}, "without a creator the card is its own creator")

	var events := _of_type(MatchEvents.CARD_CREATED_IN_HAND)
	assert_eq(events.size(), 1)
	assert_eq(events[0], MatchEvents.card_created_in_hand(0, id, "Chip", -1))


func test_create_in_hand_records_the_real_creator() -> void:
	var creator := _card_in_hand(0)
	var id: int = ops.create_in_hand("Chip", 0, creator.instance_id)
	assert_eq(state.created[0]["creator_player_id"], 0, "the creator's owner, not the target player")
	assert_eq(state.created[0]["creator_card_id"], creator.card_id)
	var events := _of_type(MatchEvents.CARD_CREATED_IN_HAND)
	assert_eq(events[0]["creator_instance_id"], creator.instance_id)


func test_create_in_hand_rejects_unknown_card_id() -> void:
	_shrink_deck(0, 0)
	var hand_before := state.players[0].hand.duplicate()
	var id: int = ops.create_in_hand("NotACard", 0)
	assert_eq(id, -1)
	assert_eq(state.players[0].hand, hand_before, "nothing entered the hand")
	assert_eq(state.created, [], "and nothing was tracked")
	assert_eq(log, [], "and nothing was emitted")


# --- summon ---

func test_summon_places_a_resolved_card_at_the_end() -> void:
	var id: int = ops.summon("Chip", 0, 1)
	assert_true(id > 0)
	var card := state.card(id)
	assert_eq(card.location, CardState.Location.BOARD)
	assert_eq(card.col, 1)
	assert_eq(card.slot, 0, "the first card in the zone sits at slot 0")
	assert_true(card.is_resolved, "a summoned card lands face-up")
	assert_eq(state.zone_cards(1, 0), [id])
	assert_eq(state.play_order, [id], "and joins the play order")

	var events := _of_type(MatchEvents.CARD_SUMMONED)
	assert_eq(events.size(), 1)
	assert_eq(events[0], MatchEvents.card_summoned(0, id, "Chip", 1, 0,
		state.card(id).get_current_power(), state.card(id).get_current_cost(), state.card(id).keywords()),
		"and the event carries the card's final numbers, so a viewer never has to guess them")


func test_summon_appends_to_a_used_zone() -> void:
	var first: int = ops.summon("Chip", 0, 1)
	var second: int = ops.summon("Chip", 0, 1)
	assert_eq(state.zone_cards(1, 0), [first, second])
	assert_eq(state.card(second).slot, 1)
	assert_eq(state.play_order, [first, second], "play order keeps the append order")


func test_summon_records_both_trackers() -> void:
	var id: int = ops.summon("Chip", 0, 1)
	assert_eq(state.summoned, [{
		"card_id": "Chip",
		"owner_player_id": 0,
		"was_played_from_hand": false,
		"is_resolved": true,
		"instance_id": id,
	}])
	assert_eq(state.created, [{
		"card_id": "Chip",
		"owner_player_id": 0,
		"creator_player_id": -1,
		"creator_card_id": "",
		"created_at_turn": state.turn,
		"instance_id": id,
	}], "creator_player_id -1 means a lane / environment created it")


func test_summon_records_the_real_creator() -> void:
	var creator := ops.summon("Chip", 0, 1)
	log.clear()
	var id: int = ops.summon("Chip", 1, 2, creator)
	assert_eq(state.created[1]["creator_player_id"], 0, "the creator's owner is recorded")
	assert_eq(state.created[1]["creator_card_id"], "Chip")


func test_summon_on_a_full_zone_returns_minus_one() -> void:
	for i in MatchState.SLOTS_PER_ZONE:
		assert_true(ops.summon("Chip", 0, 1) > 0, "slot %d fills" % i)
	var hand_before := state.players[0].hand.duplicate()
	var order_before := state.play_order.duplicate()
	log.clear()
	assert_eq(ops.summon("Chip", 0, 1), -1, "the fifth card does not fit")
	assert_eq(state.zone_cards(1, 0).size(), MatchState.SLOTS_PER_ZONE, "the zone is untouched")
	assert_eq(state.summoned.size(), 4, "only the four that landed are tracked")
	assert_eq(state.play_order, order_before)
	assert_eq(state.players[0].hand, hand_before)
	assert_eq(log, [], "a refused summon is completely silent")


func test_summon_rejects_unknown_card_id() -> void:
	assert_eq(ops.summon("NotACard", 0, 1), -1)
	assert_eq(state.zone_cards(1, 0), [])
	assert_eq(state.summoned, [])
	assert_eq(log, [])


# --- shuffle_into_deck ---

func test_shuffle_into_deck_keeps_the_card_and_its_cost_modifier() -> void:
	var card := _card_in_hand(1)
	ops.change_cost(card.instance_id, -2)
	var hand_before: Array = state.players[1].hand.duplicate()
	var deck_before: Array = state.players[1].deck.duplicate()
	# Predict the insertion index from a copy of the rng, so the prediction itself
	# does not consume the number shuffle_into_deck is about to draw.
	var peek := RandomNumberGenerator.new()
	peek.state = state.rng.state
	var pos: int = peek.randi_range(0, state.players[1].deck.size())

	log.clear()
	ops.shuffle_into_deck(1, card.instance_id)
	assert_eq(card.location, CardState.Location.DECK, "it is back in the deck")
	assert_false(state.players[1].hand.has(card.instance_id), "and out of the hand")
	assert_eq(card.cost_modifier, -2, "a permanent discount survives the round trip")

	var expected: Array = deck_before.duplicate()
	expected.insert(pos, card.instance_id)
	assert_eq(state.players[1].deck, expected, "inserted at the rng-chosen position")

	var events := _of_type(MatchEvents.CARD_SHUFFLED_INTO_DECK)
	assert_eq(events.size(), 1)
	assert_eq(events[0], MatchEvents.card_shuffled_into_deck(1, card.instance_id, card.card_id))


func test_shuffle_into_deck_is_deterministic_per_seed() -> void:
	# The insertion point comes from state.rng, so the same seed must always give
	# the same shuffle, and a different seed must be free to differ.
	var positions: Array = []
	for seed_value in [777, 777, 778]:
		var s := MatchSetup.new_match(DECK, DECK, seed_value)
		var o := MatchOps.new(s, func(_e): pass, MatchAbilities.new())
		var hand_card: CardState = s.card(o.draw(1))
		var deck_copy := s.players[1].deck.duplicate()
		o.shuffle_into_deck(1, hand_card.instance_id)
		positions.append({
			"deck": s.players[1].deck.duplicate(),
			"index": s.players[1].deck.find(hand_card.instance_id),
			"original": deck_copy,
		})
	assert_eq(positions[0], positions[1], "same seed, same shuffle")
	assert_true(positions[0]["index"] >= 0, "the card really is in the deck")
	assert_ne(positions[0]["deck"], positions[0]["original"], "the deck order actually changed")


func test_shuffle_into_deck_needs_the_card_in_hand() -> void:
	var deck_card: int = state.players[0].deck[0]
	log.clear()
	ops.shuffle_into_deck(0, deck_card)
	assert_eq(state.players[0].deck[0], deck_card, "a card still in the deck is left there")
	ops.shuffle_into_deck(0, 9999)
	assert_eq(log, [], "an unknown instance id does nothing")


func test_lane_power_ignores_cards_with_no_power_stat() -> void:
	# Spells and landmarks have no Power field, so they contribute nothing.
	var spell_id: int = ops.create_in_hand("SpinningAxe", 0)
	state.place_card(spell_id, MatchState.SPELL_COL, 0)
	state.card(spell_id).is_resolved = true
	assert_eq(state.card(spell_id).get_current_power(), 0, "SpinningAxe has no Power")
	assert_eq(ops.lane_power(0, 0), 0, "so no lane power comes from it")


# --- power and cost ---

func test_change_power_emits_the_new_total() -> void:
	var id: int = ops.summon("Chip", 0, 0)
	var card := state.card(id)
	var base: int = card.get_current_power()
	log.clear()
	ops.change_power(id, 2)
	assert_eq(card.power_modifier, 2)
	assert_eq(card.get_current_power(), base + 2)
	assert_eq(_of_type(MatchEvents.POWER_CHANGED), [MatchEvents.power_changed(id, 2, base + 2)])


func test_change_cost_emits_the_new_total() -> void:
	var id: int = ops.summon("Chip", 0, 0)
	var card := state.card(id)
	var base: int = card.get_current_cost()
	log.clear()
	ops.change_cost(id, -1)
	assert_eq(card.cost_modifier, -1)
	assert_eq(card.get_current_cost(), base - 1)
	assert_eq(_of_type(MatchEvents.COST_CHANGED), [MatchEvents.cost_changed(id, -1, base - 1)])


func test_change_power_and_cost_ignore_zero_and_unknown_ids() -> void:
	var id: int = ops.summon("Chip", 0, 0)
	var card := state.card(id)
	log.clear()
	ops.change_power(id, 0)
	ops.change_cost(id, 0)
	ops.change_power(9999, 3)
	ops.change_cost(9999, 3)
	assert_eq(log, [], "a delta of 0 and an unknown id are both no-ops")
	assert_eq(card.power_modifier, 0)
	assert_eq(card.cost_modifier, 0)


func test_change_cost_never_drops_below_zero() -> void:
	var id: int = ops.create_in_hand("Chip", 0)
	var card := state.card(id)
	ops.change_cost(id, -50)
	assert_eq(card.get_current_cost(), 0, "CardState clamps the total, the modifier is untouched")
	assert_eq(card.cost_modifier, -50)


# --- keywords ---

func test_add_keyword_does_not_duplicate() -> void:
	var id: int = ops.summon("Chip", 0, 0)
	var card := state.card(id)
	log.clear()
	ops.add_keyword(id, "Elusive")
	ops.add_keyword(id, "Elusive")
	assert_eq(card.runtime_keywords, ["Elusive"])
	assert_eq(_of_type(MatchEvents.KEYWORD_ADDED), [MatchEvents.keyword_added(id, "Elusive")])


func test_add_keyword_keeps_the_other_keywords() -> void:
	var id: int = ops.summon("Chip", 0, 0)
	ops.add_keyword(id, "Stun")
	ops.add_keyword(id, "Elusive")
	assert_eq(state.card(id).runtime_keywords, ["Stun", "Elusive"])


func test_remove_keyword_only_when_present() -> void:
	var id: int = ops.summon("Chip", 0, 0)
	var card := state.card(id)
	ops.add_keyword(id, "Stun")
	log.clear()

	ops.remove_keyword(id, "Shield")
	assert_eq(log, [], "a keyword the card never had emits nothing")
	assert_eq(card.runtime_keywords, ["Stun"])

	ops.remove_keyword(id, "Stun")
	assert_eq(card.runtime_keywords, [])
	assert_eq(_of_type(MatchEvents.KEYWORD_REMOVED), [MatchEvents.keyword_removed(id, "Stun")])

	ops.remove_keyword(9999, "Stun")
	assert_eq(_of_type(MatchEvents.KEYWORD_REMOVED).size(), 1, "an unknown id emits nothing")


# --- lane_power ---

func test_lane_power_ignores_unresolved_cards() -> void:
	var first: int = ops.summon("Chip", 0, 1)
	var second: int = ops.summon("Chip", 0, 1)
	var power: int = state.card(first).get_current_power()
	assert_eq(ops.lane_power(1, 0), power * 2, "both are resolved")

	state.card(second).is_resolved = false
	assert_eq(ops.lane_power(1, 0), power, "a face-down card does not count yet")


func test_lane_power_is_per_column_and_per_owner() -> void:
	var mine: int = ops.summon("Chip", 0, 0)
	ops.summon("Chip", 1, 0)
	ops.summon("Chip", 0, 1)
	var power: int = state.card(mine).get_current_power()
	assert_eq(ops.lane_power(0, 0), power)
	assert_eq(ops.lane_power(0, 1), power)
	assert_eq(ops.lane_power(1, 0), power)
	assert_eq(ops.lane_power(2, 0), 0, "an empty column scores 0")


func test_lane_power_counts_power_modifiers() -> void:
	var id: int = ops.summon("Chip", 0, 2)
	ops.change_power(id, 3)
	assert_eq(ops.lane_power(2, 0), state.card(id).get_current_power(), "buffs count")
	assert_eq(ops.lane_power(2, 1), 0, "the opponent's side is unaffected")


# --- mana ---

func test_spend_mana_subtracts_and_emits() -> void:
	state.players[0].base_max_mana = 5
	state.players[0].current_mana = 5
	log.clear()
	assert_true(ops.spend_mana(0, 3))
	assert_eq(state.players[0].current_mana, 2)
	assert_eq(_of_type(MatchEvents.MANA_CHANGED), [MatchEvents.mana_changed(0, 2, 5)])


func test_spend_mana_refuses_when_short_and_changes_nothing() -> void:
	state.players[0].base_max_mana = 5
	state.players[0].current_mana = 2
	log.clear()
	assert_false(ops.spend_mana(0, 3))
	assert_eq(state.players[0].current_mana, 2, "a refused spend costs nothing")
	assert_eq(log, [])


func test_spend_mana_of_zero_or_less_succeeds_silently() -> void:
	state.players[0].base_max_mana = 5
	state.players[0].current_mana = 0
	log.clear()
	assert_true(ops.spend_mana(0, 0))
	assert_true(ops.spend_mana(0, -4))
	assert_eq(state.players[0].current_mana, 0)
	assert_eq(log, [], "a negative refund-ish spend never doubles as a gain")


func test_spend_mana_emptying_the_pool_is_allowed() -> void:
	state.players[0].base_max_mana = 3
	state.players[0].current_mana = 3
	assert_true(ops.spend_mana(0, 3))
	assert_eq(state.players[0].current_mana, 0)


func test_refund_mana_is_capped_at_max() -> void:
	state.players[0].base_max_mana = 4
	state.players[0].current_mana = 1
	log.clear()
	ops.refund_mana(0, 2)
	assert_eq(state.players[0].current_mana, 3)
	ops.refund_mana(0, 10)
	assert_eq(state.players[0].current_mana, 4, "the pool never goes past its maximum")
	assert_eq(_of_type(MatchEvents.MANA_CHANGED), [
		MatchEvents.mana_changed(0, 3, 4),
		MatchEvents.mana_changed(0, 4, 4),
	])


func test_refund_mana_counts_bonus_mana_in_the_cap() -> void:
	state.players[0].base_max_mana = 2
	state.players[0].bonus_max_mana = 3
	state.players[0].current_mana = 0
	ops.refund_mana(0, 9)
	assert_eq(state.players[0].current_mana, 5, "the cap is base + bonus")


func test_queue_temp_mana_only_touches_pending() -> void:
	state.players[0].base_max_mana = 2
	state.players[0].current_mana = 2
	log.clear()
	ops.queue_temp_mana(0, 3)
	assert_eq(state.players[0].pending_bonus_mana, 3)
	assert_eq(state.players[0].bonus_max_mana, 0, "not active yet")
	assert_eq(state.players[0].get_max_mana(), 2, "and not part of the maximum yet")
	assert_eq(state.players[0].current_mana, 2, "and the pool did not move")
	assert_eq(log, [], "queued mana is applied at the next round start, not now")

	ops.queue_temp_mana(0, 1)
	assert_eq(state.players[0].pending_bonus_mana, 4, "queues accumulate")


# --- mana guards ---

func test_mana_primitives_ignore_bad_players() -> void:
	log.clear()
	ops.spend_mana(5, 1)
	ops.refund_mana(-1, 3)
	ops.queue_temp_mana(2, 3)
	ops.set_deep(7)
	ops.draw(3)
	ops.create_in_hand("Chip", 9)
	assert_eq(ops.summon("Chip", 9, 0), -1)
	assert_eq(log, [], "an out-of-range player id changes nothing")
	assert_eq(state.players[0].pending_bonus_mana, 0)
	assert_false(state.players[0].is_deep)


func test_emit_event_passes_custom_events_through() -> void:
	var custom := MatchEvents.lane_effect(1, "RockfallPath", "rockfall_chip")
	ops.emit_event(custom)
	assert_eq(log, [custom])


# --- state round trip ---

func test_undo_stack_survives_a_state_round_trip() -> void:
	state.players[0].undo_stack = [
		{"instance_id": 7, "hand_index": 2, "cost": 3},
		{"instance_id": 9, "hand_index": 0, "cost": 1},
	]
	var restored := MatchState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.players[0].undo_stack, state.players[0].undo_stack)
	assert_eq(restored.players[1].undo_stack, [], "the other player has none")
	assert_eq(restored.checksum(), state.checksum(), "the whole state is reproducible")


## A stand-in for MatchAbilities that just records what it was asked to do.
class _SpyAbilities extends MatchAbilities:
	var drawn_ids: Array[int] = []

	func on_card_drawn(id: int) -> void:
		drawn_ids.append(id)
