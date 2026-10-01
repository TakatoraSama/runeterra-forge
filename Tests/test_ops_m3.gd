## Tests for the M3 MatchOps primitives: the kill / discard / recall / stun / level-up
## flows ported from CardManager, Card.gd, StunManager and Deck, plus the queries
## the ability modules read.
extends "res://Tests/test_case.gd"

const DECK := ["Azir1", "Nasus1", "Chip", "Ahri1", "Kennen1"]

var state: MatchState
var ops: MatchOps
var spy: _SpyAbilities
var log: Array


func before_each() -> void:
	state = MatchSetup.new_match(DECK, DECK, 4242)
	log = []
	spy = _SpyAbilities.new()
	ops = MatchOps.new(state, _collect, spy)
	spy.bind(state, ops)


func _collect(event: Dictionary) -> void:
	log.append(event)


## The events of one type, in emission order.
func _of_type(type: Variant) -> Array:
	var out: Array = []
	for e: Dictionary in log:
		if e["type"] == type:
			out.append(e)
	return out


## Puts a card of player `p` onto the board at `col`, face-up, and returns its id.
func _on_board(card_id: String, p: int, col: int = 0) -> int:
	return ops.summon(card_id, p, col)


# --- queries ---

func test_is_on_board_covers_lanes_and_the_spell_zone() -> void:
	var in_lane: int = _on_board("Chip", 0, 1)
	var in_spell: int = ops.summon("SpinningAxe", 0, MatchState.SPELL_COL)
	var in_hand: int = ops.create_in_hand("Chip", 0)
	assert_true(ops.is_on_board(in_lane), "a lane card is on the board")
	assert_true(ops.is_on_board(in_spell), "a resolving spell is on the board too")
	assert_false(ops.is_on_board(in_hand), "a card in hand is not")
	assert_false(ops.is_on_board(9999), "an unknown id is not on the board")


func test_is_unit_is_followers_and_champions_only() -> void:
	var champ: int = _on_board("Azir1", 0)
	var follower: int = _on_board("Chip", 0)
	var landmark: int = _on_board("BuriedSunDisc", 0)
	var spell: int = ops.summon("SpinningAxe", 0, MatchState.SPELL_COL)
	assert_true(ops.is_unit(champ))
	assert_true(ops.is_unit(follower))
	assert_false(ops.is_unit(landmark), "a landmark is not a unit")
	assert_false(ops.is_unit(spell), "a spell is not a unit")
	assert_false(ops.is_unit(9999))


func test_card_data_queries_read_carddatabase() -> void:
	var azir: int = _on_board("Azir1", 0)
	var disc: int = _on_board("BuriedSunDisc", 0)
	assert_eq(ops.card_type(azir), "Champion")
	assert_eq(ops.card_type(disc), "Landmark")
	assert_eq(ops.card_name(azir), "Azir", "all Azir levels share one Name")
	assert_eq(ops.card_name(disc), "Buried Sun Disc")
	assert_eq(ops.card_level(azir), 1)
	assert_eq(ops.card_level(disc), 1, "a card with no Level field reads as 1")

	assert_eq(ops.card_type(9999), "")
	assert_eq(ops.card_name(9999), "")
	assert_eq(ops.card_level(9999), 1)


func test_bv_reads_balance_values_with_the_given_fallback() -> void:
	var azir: int = _on_board("Azir1", 0)
	var chip: int = _on_board("Chip", 0)
	assert_eq(ops.bv(azir, "ally_threshold", 99), 6, "the real value wins")
	assert_eq(ops.bv(chip, "ally_threshold", 99), 99, "a card with an empty BalanceValues falls back")
	assert_eq(ops.bv(9999, "ally_threshold", 99), 99, "an unknown id falls back too")


func test_zone_ids_and_board_ids_walk_the_zones_in_order() -> void:
	var a: int = ops.summon("Chip", 0, 1)
	var b: int = ops.summon("Chip", 0, 1)
	var c: int = ops.summon("Chip", 0, 0)
	assert_eq(ops.zone_ids(1, 0), [a, b])
	assert_eq(ops.zone_ids(2, 0), [], "an empty zone is just empty")
	assert_eq(ops.board_ids(0), [c, a, b], "column 0 first, then 1, slot by slot")
	assert_eq(ops.board_ids(1), [], "the opponent's side is empty")
	state.card(b).is_resolved = false
	assert_eq(ops.board_ids(0), [c, a, b], "a face-down card is still on the board")
	assert_eq(ops.board_ids(0, true), [c, a], "but not resolved yet")


func test_board_ids_skips_the_spell_zone() -> void:
	var lane: int = ops.summon("Chip", 0, 2)
	var spell: int = ops.summon("SpinningAxe", 0, MatchState.SPELL_COL)
	assert_eq(ops.board_ids(0), [lane], "a resolving spell is not a board card")
	assert_true(ops.is_on_board(spell), "but it is still on the board")


func test_pick_random_is_deterministic_per_seed() -> void:
	var picks: Array = []
	for seed_value in [11, 11, 12]:
		var s := MatchSetup.new_match(DECK, DECK, seed_value)
		var o := MatchOps.new(s, func(_e): pass, MatchAbilities.new())
		picks.append([o.pick_random([1, 2, 3, 4, 5]), o.pick_random([1, 2, 3, 4, 5])])
	assert_eq(picks[0], picks[1], "same seed, same picks")
	assert_true(picks[0][0] in [1, 2, 3, 4, 5], "and the pick really is one of the ids")


func test_pick_random_of_nothing_is_minus_one() -> void:
	assert_eq(ops.pick_random([]), -1)


func test_upgraded_id_follows_the_owners_permanent_levels() -> void:
	assert_eq(ops.upgraded_id("Azir1", 0), "Azir1", "before the level-up nothing changes")
	state.players[0].permanently_leveled_up["Azir"] = "Azir3"
	assert_eq(ops.upgraded_id("Azir1", 0), "Azir3")
	assert_eq(ops.upgraded_id("Azir1", 1), "Azir1", "the opponent levels up on their own")
	assert_eq(ops.upgraded_id("NotACard", 0), "NotACard", "an unknown id comes back unchanged")
	assert_eq(ops.upgraded_id("Azir1", 7), "Azir1", "an invalid player comes back unchanged")


# --- kill ---

func test_kill_records_the_tracker_and_the_zone_it_died_in() -> void:
	var victim: int = _on_board("Chip", 0, 2)
	var killer: int = _on_board("Nasus1", 1, 2)
	log.clear()

	assert_true(ops.kill(victim, 1, killer))
	assert_eq(state.killed, [{
		"card_id": "Chip",
		"owner_player_id": 0,
		"killer_player_id": 1,
		"killer_card_id": "Nasus1",
		"zone_key": [2, 0],
		"is_revived": false,
		"instance_id": victim,
	}])
	assert_eq(_of_type(MatchEvents.CARD_KILLED), [MatchEvents.card_killed(victim, 1, killer)])
	assert_eq(spy.last_breath_ids, [victim], "Last Breath runs after the card is gone")


func test_kill_without_a_killer_records_an_empty_card_id() -> void:
	var victim: int = _on_board("Chip", 0)
	ops.kill(victim, -1)
	assert_eq(state.killed[0]["killer_card_id"], "", "no killer card is the empty string")
	assert_eq(state.killed[0]["killer_player_id"], -1)


func test_kill_releases_the_slot_and_compacts_the_zone() -> void:
	var first: int = ops.summon("Chip", 0, 1)
	var second: int = ops.summon("Chip", 0, 1)
	var third: int = ops.summon("Chip", 0, 1)

	ops.kill(second, 0)

	assert_eq(state.zone_cards(1, 0), [first, third], "the zone closes up")
	assert_eq(state.card(third).slot, 1, "and the cards behind shift down")
	assert_eq(state.card(second).location, CardState.Location.GONE)
	assert_eq(state.card(second).col, -1)
	assert_eq(state.card(second).slot, -1)
	assert_false(ops.is_on_board(second))


func test_kill_clears_a_stun() -> void:
	var victim: int = _on_board("Chip", 0)
	ops.stun(victim)
	ops.kill(victim, 0)
	assert_false(ops.is_stunned(victim), "a dead card cannot stay stunned")
	assert_eq(state.card(victim).runtime_keywords, [], "and the Stun badge goes with it")


func test_kill_off_the_board_is_refused_and_changes_nothing() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	log.clear()
	assert_false(ops.kill(in_hand, 0))
	assert_false(ops.kill(9999, 0))
	assert_eq(state.killed, [])
	assert_eq(log, [], "a refused kill is completely silent")
	assert_eq(spy.last_breath_ids, [])


func test_kill_that_is_prevented_leaves_the_card_alive() -> void:
	var victim: int = _on_board("Chip", 0, 1)
	var bystander: int = ops.summon("Chip", 0, 1)
	spy.save_from = victim
	log.clear()

	assert_false(ops.kill(victim, 1), "the kill did not happen")
	assert_true(ops.is_on_board(victim), "the card is still in play")
	assert_eq(state.zone_cards(1, 0), [victim, bystander], "the zone is untouched")
	assert_eq(state.killed, [], "and nothing was tracked as killed")
	assert_eq(_of_type(MatchEvents.CARD_KILLED), [], "no kill event")
	assert_eq(_of_type(MatchEvents.DEATH_PREVENTED), [MatchEvents.death_prevented(victim)])
	assert_eq(spy.death_prevented_ids, [victim], "the card runs its survival effect")
	assert_eq(spy.last_breath_ids, [], "a saved card has no Last Breath")


# --- discard ---

func test_discard_takes_the_card_out_of_the_hand() -> void:
	var id: int = ops.create_in_hand("Chip", 0)
	var hand_before: int = state.players[0].hand.size()
	var by: int = _on_board("Sion1", 0)
	log.clear()

	ops.discard(id, by)

	assert_false(state.players[0].hand.has(id))
	assert_eq(state.players[0].hand.size(), hand_before - 1)
	assert_eq(state.card(id).location, CardState.Location.GONE)
	assert_eq(state.discarded, [{
		"card_id": "Chip",
		"owner_player_id": 0,
		"discarded_by_card_id": "Sion1",
		"discarded_at_turn": state.turn,
		"instance_id": id,
	}])
	assert_eq(_of_type(MatchEvents.CARD_DISCARDED), [MatchEvents.card_discarded(0, id, "Chip")])
	assert_eq(spy.discard_ids, [id], "the on-discard hook fires after the card left the hand")


func test_discard_without_a_cause_records_an_empty_card_id() -> void:
	var id: int = ops.create_in_hand("Chip", 0)
	ops.discard(id)
	assert_eq(state.discarded[0]["discarded_by_card_id"], "", "no cause is the empty string")


func test_discard_needs_a_card_in_a_hand() -> void:
	var on_board: int = _on_board("Chip", 0)
	log.clear()
	ops.discard(on_board)
	ops.discard(9999)
	assert_eq(state.discarded, [], "a board card and an unknown id are both left alone")
	assert_eq(state.card(on_board).location, CardState.Location.BOARD)
	assert_eq(log, [])


# --- recall ---

func test_recall_returns_the_card_to_the_front_of_its_hand() -> void:
	var target: int = _on_board("Chip", 0, 1)
	var ahri: int = _on_board("Ahri1", 0, 1)
	ops.stun(target)
	state.played_this_turn.append(target)
	log.clear()

	ops.recall(target, 0, ahri)

	assert_eq(state.players[0].hand[0], target, "the recalled card is the newest one")
	assert_eq(state.card(target).location, CardState.Location.HAND)
	assert_false(state.card(target).is_resolved, "it comes back face-down until it resolves again")
	assert_false(ops.is_stunned(target), "recall clears Stun")
	assert_eq(state.card(target).runtime_keywords, [], "and the Stun badge goes with it")
	assert_false(state.played_this_turn.has(target), "it cannot resolve again this round")
	assert_eq(state.recalled, [{
		"card_id": "Chip",
		"owner_player_id": 0,
		"recaller_player_id": 0,
		"recaller_card_id": "Ahri1",
		"recaller_instance_id": ahri,
		"instance_id": target,
	}], "Ahri can match the recall on the instance")
	assert_eq(_of_type(MatchEvents.CARD_RECALLED), [MatchEvents.card_recalled(0, target)])


func test_recall_without_a_recaller_is_not_tracked() -> void:
	var target: int = _on_board("Chip", 0)
	ops.recall(target)
	assert_eq(state.recalled, [], "only a card-caused recall feeds the trackers")
	assert_eq(state.players[0].hand[0], target, "but the card still comes back")
	assert_eq(_of_type(MatchEvents.CARD_RECALLED), [MatchEvents.card_recalled(0, target)])


func test_recall_works_for_both_players() -> void:
	var mine: int = _on_board("Chip", 0)
	var theirs: int = _on_board("Chip", 1)
	var ahri: int = _on_board("Ahri1", 0)

	ops.recall(mine, 0, ahri)
	ops.recall(theirs, 0, ahri)

	assert_eq(state.players[0].hand[0], mine)
	assert_eq(state.players[1].hand[0], theirs, "an opponent card goes to the opponent's hand")
	assert_eq(state.recalled[1]["owner_player_id"], 1)


func test_recall_needs_a_card_on_the_board() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	log.clear()
	ops.recall(in_hand, 0, -1)
	assert_eq(state.recalled, [])
	assert_eq(log, [], "a card that is not on the board cannot be recalled")


func test_recall_compacts_the_zone_it_came_from() -> void:
	var a: int = ops.summon("Chip", 0, 2)
	var b: int = ops.summon("Chip", 0, 2)
	ops.recall(a)
	assert_eq(state.zone_cards(2, 0), [b])
	assert_eq(state.card(b).slot, 0)


# --- stun ---

func test_stun_adds_the_keyword_and_the_entry() -> void:
	var id: int = _on_board("Chip", 0)
	log.clear()
	ops.stun(id)
	assert_true(ops.is_stunned(id))
	assert_eq(state.card(id).runtime_keywords, ["Stun"])
	assert_eq(state.stuns, [{"instance_id": id, "stunned_on_turn": state.turn}])
	assert_eq(_of_type(MatchEvents.KEYWORD_ADDED), [MatchEvents.keyword_added(id, "Stun")])


func test_stun_does_not_stack() -> void:
	var id: int = _on_board("Chip", 0)
	ops.stun(id)
	log.clear()
	ops.stun(id)
	assert_eq(state.stuns.size(), 1, "still one entry")
	assert_eq(state.card(id).runtime_keywords, ["Stun"], "and one badge")
	assert_eq(log, [], "the duplicate application is completely silent")


func test_stun_needs_a_card_on_the_board() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	ops.stun(in_hand)
	ops.stun(9999)
	assert_eq(state.stuns, [], "hand cards and unknown ids cannot be stunned")


func test_clear_stun_drops_the_entry_and_the_keyword() -> void:
	var id: int = _on_board("Chip", 0)
	ops.stun(id)
	log.clear()
	ops.clear_stun(id)
	assert_false(ops.is_stunned(id))
	assert_eq(state.card(id).runtime_keywords, [])
	assert_eq(state.stuns, [])
	assert_eq(_of_type(MatchEvents.KEYWORD_REMOVED), [MatchEvents.keyword_removed(id, "Stun")])

	log.clear()
	ops.clear_stun(id)
	ops.clear_stun(9999)
	assert_eq(log, [], "clearing a card that is not stunned emits nothing")


# --- level up ---

## Empties both decks: a level-up upgrades every copy the owner controls, so a
## test that counts the resulting events must control the deck first.
func _clear_decks() -> void:
	state.players[0].deck.clear()
	state.players[1].deck.clear()




func test_level_up_changes_the_card_and_announces_it() -> void:
	_clear_decks()
	var azir: int = _on_board("Azir1", 0)
	log.clear()
	ops.level_up(azir, "Azir2")

	assert_eq(state.card(azir).card_id, "Azir2")
	assert_eq(state.players[0].permanently_leveled_up, {"Azir": "Azir2"})
	assert_eq(_of_type(MatchEvents.CARD_LEVELED_UP), [
		MatchEvents.card_leveled_up(azir, "Azir1", "Azir2"),
	], "the primary card levels up loudly")
	assert_eq(spy.level_up_ids, [azir], "on_level_up fires once, for the primary card")


func test_level_up_upgrades_every_copy_of_that_owner() -> void:
	_clear_decks()
	var primary: int = _on_board("Azir1", 0, 0)
	var also_on_board: int = _on_board("Azir1", 0, 1)
	var in_hand: int = ops.create_in_hand("Azir1", 0)
	var in_deck: int = ops.create_in_hand("Azir1", 0)
	state.remove_from_hand(0, in_deck)
	state.card(in_deck).location = CardState.Location.DECK
	state.players[0].deck.append(in_deck)

	ops.level_up(primary, "Azir2")

	assert_eq(state.card(also_on_board).card_id, "Azir2", "the other board copy follows")
	assert_eq(state.card(in_hand).card_id, "Azir2", "the hand copy follows")
	assert_eq(state.card(in_deck).card_id, "Azir2", "the deck copy follows")
	assert_eq(state.card(primary).card_id, "Azir2")


func test_level_up_leaves_the_opponents_copies_alone() -> void:
	var primary: int = _on_board("Azir1", 0)
	var their_board: int = _on_board("Azir1", 1)
	var their_hand: int = ops.create_in_hand("Azir1", 1)
	var their_deck: int = ops.create_in_hand("Azir1", 1)
	state.remove_from_hand(1, their_deck)
	state.card(their_deck).location = CardState.Location.DECK
	state.players[1].deck.append(their_deck)

	ops.level_up(primary, "Azir2")

	assert_eq(state.card(their_board).card_id, "Azir1", "their board copy is untouched")
	assert_eq(state.card(their_hand).card_id, "Azir1")
	assert_eq(state.card(their_deck).card_id, "Azir1")
	assert_false(state.players[1].permanently_leveled_up.has("Azir"), "and they never levelled up")


func test_level_up_marks_the_copies_silent_and_private() -> void:
	_clear_decks()
	var primary: int = _on_board("Azir1", 0)
	var in_hand: int = ops.create_in_hand("Azir1", 0)
	var also_on_board: int = _on_board("Azir1", 0, 1)
	log.clear()

	ops.level_up(primary, "Azir2")

	var events := _of_type(MatchEvents.CARD_LEVELED_UP)
	assert_eq(events.size(), 3, "primary plus both copies")
	assert_false(events[0]["silent"], "the primary is the loud one")
	assert_true(events[1]["silent"], "a board copy is silent")
	assert_eq(events[1]["instance_id"], also_on_board, "board copies are processed before hand cards")
	assert_false(events[1].has("private_to"), "a card on the board needs no privacy tag")
	assert_true(events[2]["silent"], "a hand copy is silent too")
	assert_eq(events[2]["instance_id"], in_hand)
	assert_eq(events[2]["private_to"], 0, "but its identity is the owner's business")


func test_level_up_does_not_touch_a_non_champion() -> void:
	_clear_decks()
	var disc: int = _on_board("BuriedSunDisc", 0)
	var other: int = _on_board("BuriedSunDisc", 0, 1)
	log.clear()

	ops.level_up(disc, "RestoredSunDisc")

	assert_eq(state.card(disc).card_id, "RestoredSunDisc")
	assert_eq(state.card(other).card_id, "BuriedSunDisc", "a landmark is not upgraded globally")
	assert_eq(state.players[0].permanently_leveled_up, {}, "and nothing is recorded")
	assert_eq(_of_type(MatchEvents.CARD_LEVELED_UP).size(), 1, "only the landmark itself changed")


func test_level_up_ignores_an_unknown_or_unchanged_id() -> void:
	_clear_decks()
	var azir: int = _on_board("Azir1", 0)
	log.clear()
	ops.level_up(azir, "")
	ops.level_up(azir, "Azir1")
	ops.level_up(azir, "NotACard")
	ops.level_up(9999, "Azir2")
	assert_eq(state.card(azir).card_id, "Azir1")
	assert_eq(state.players[0].permanently_leveled_up, {})
	assert_eq(log, [], "all three are no-ops")
	assert_eq(spy.level_up_ids, [])


func test_draw_and_create_hand_out_the_upgraded_id() -> void:
	_clear_decks()
	var primary: int = _on_board("Azir1", 0)
	var in_deck: int = ops.create_in_hand("Azir1", 0)
	state.remove_from_hand(0, in_deck)
	state.card(in_deck).location = CardState.Location.DECK
	state.players[0].deck.push_front(in_deck)
	ops.level_up(primary, "Azir2")

	assert_eq(ops.upgraded_id("Azir1", 0), "Azir2")
	assert_eq(state.card(ops.draw(0)).card_id, "Azir2", "the deck entry now draws as the new level")
	assert_eq(state.card(ops.create_in_hand("Azir1", 0)).card_id, "Azir2", "so does a fresh creation")
	assert_eq(state.card(ops.create_in_hand("Azir1", 1)).card_id, "Azir1", "the opponent is unaffected")


func test_draw_specific_pulls_a_named_card_from_anywhere_in_the_deck() -> void:
	var buried: int = ops.create_in_hand("BuriedSunDisc", 0)
	var restored: int = ops.create_in_hand("RestoredSunDisc", 0)
	state.remove_from_hand(0, buried)
	state.remove_from_hand(0, restored)
	state.card(buried).location = CardState.Location.DECK
	state.card(restored).location = CardState.Location.DECK
	# The card is NOT on top: an unrelated card sits above it.
	state.players[0].deck.clear()
	state.players[0].deck.append(buried)
	state.players[0].deck.append(restored)

	log.clear()
	assert_eq(ops.draw_specific(0, "RestoredSunDisc"), restored)
	assert_eq(state.players[0].hand[0], restored)
	assert_false(state.players[0].deck.has(restored), "it left the deck")
	assert_true(state.players[0].deck.has(buried), "and the rest of the deck is untouched")

	assert_eq(state.drawn, [{
		"card_id": "RestoredSunDisc",
		"owner_player_id": 0,
		"turn": state.turn,
		"instance_id": restored,
	}], "a specific draw feeds the draw trackers just like a normal draw")
	assert_eq(_of_type(MatchEvents.CARD_DRAWN), [MatchEvents.card_drawn(0, restored, "RestoredSunDisc")])
	assert_eq(spy.drawn_ids, [restored], "the on_card_drawn hook fires too")


func test_draw_specific_takes_the_first_match_and_goes_deep_at_the_end() -> void:
	var first: int = ops.create_in_hand("BuriedSunDisc", 0)
	var second: int = ops.create_in_hand("BuriedSunDisc", 0)
	state.remove_from_hand(0, first)
	state.remove_from_hand(0, second)
	state.card(first).location = CardState.Location.DECK
	state.card(second).location = CardState.Location.DECK
	state.players[0].deck.clear()
	state.players[0].deck.append(first)
	state.players[0].deck.append(second)

	log.clear()
	assert_eq(ops.draw_specific(0, "BuriedSunDisc"), first, "the topmost copy comes over")
	assert_eq(state.players[0].deck, [second], "the copy underneath stays")
	assert_false(state.players[0].is_deep, "the deck is not empty yet")

	assert_eq(ops.draw_specific(0, "BuriedSunDisc"), second)
	assert_true(state.players[0].is_deep, "emptying the deck on a specific draw still goes Deep")
	assert_eq(_of_type(MatchEvents.DEEP_CHANGED), [MatchEvents.deep_changed(0, true)])


func test_draw_specific_of_a_card_that_is_not_there_is_minus_one() -> void:
	log.clear()
	assert_eq(ops.draw_specific(0, "RestoredSunDisc"), -1)
	assert_eq(ops.draw_specific(7, "Chip"), -1, "an invalid player is refused too")
	assert_eq(state.drawn, [])
	assert_eq(log, [], "and nothing at all is emitted")


# --- put_into_play ---

func test_put_into_play_moves_a_hand_card_onto_the_board() -> void:
	var id: int = ops.create_in_hand("Chip", 0)
	var hand_before: int = state.players[0].hand.size()
	log.clear()

	assert_true(ops.put_into_play(id, 1))

	assert_false(state.players[0].hand.has(id))
	assert_eq(state.players[0].hand.size(), hand_before - 1)
	assert_eq(state.zone_cards(1, 0), [id])
	assert_true(state.card(id).is_resolved, "it lands face-up, like every other summon")
	assert_eq(state.card(id).slot, 0)
	assert_eq(state.play_order, [id])
	assert_eq(state.summoned, [{
		"card_id": "Chip",
		"owner_player_id": 0,
		"was_played_from_hand": false,
		"is_resolved": true,
		"instance_id": id,
	}], "Sion counts it as a summoned ally")
	assert_eq(_of_type(MatchEvents.CARD_SUMMONED), [MatchEvents.card_summoned(0, id, "Chip", 1, 0,
		state.card(id).get_current_power(), state.card(id).get_current_cost(), state.card(id).keywords())],
		"the summoned event carries the card's final numbers too")


func test_put_into_play_appends_to_a_used_zone() -> void:
	var first: int = _on_board("Chip", 0, 1)
	var from_hand: int = ops.create_in_hand("Chip", 0)
	assert_true(ops.put_into_play(from_hand, 1))
	assert_eq(state.zone_cards(1, 0), [first, from_hand])
	assert_eq(state.card(from_hand).slot, 1)


func test_put_into_play_refuses_a_full_zone() -> void:
	for _i in MatchState.SLOTS_PER_ZONE:
		_on_board("Chip", 0, 1)
	var from_hand: int = ops.create_in_hand("Chip", 0)
	log.clear()
	assert_false(ops.put_into_play(from_hand, 1), "no room left")
	assert_true(state.players[0].hand.has(from_hand), "the card stays in hand")
	assert_eq(state.zone_cards(1, 0).size(), MatchState.SLOTS_PER_ZONE)
	assert_eq(log, [], "and nothing is emitted")


func test_put_into_play_needs_a_card_in_a_hand() -> void:
	var on_board: int = _on_board("Chip", 0, 1)
	assert_false(ops.put_into_play(on_board, 2), "a board card is not put into play again")
	assert_false(ops.put_into_play(9999, 2))
	assert_eq(state.zone_cards(1, 0), [on_board], "the board is untouched")


func test_put_into_play_does_not_duplicate_the_play_order() -> void:
	var id: int = _on_board("Chip", 0, 1)
	ops.recall(id)
	assert_true(ops.put_into_play(id, 1), "a recalled card can go straight back down")
	assert_eq(state.play_order, [id], "the play order keeps one entry per card")
	assert_eq(state.summoned.size(), 2, "but every arrival is tracked")


# --- beheld ---

func test_beheld_is_hand_plus_the_whole_board() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	var face_down: int = _on_board("Chip", 0, 1)
	state.card(face_down).is_resolved = false
	var in_spell: int = ops.summon("SpinningAxe", 0, MatchState.SPELL_COL)
	var theirs: int = _on_board("Chip", 1, 1)

	assert_eq(ops.beheld(0), [in_hand, face_down, in_spell],
		"hand first, then the board; a face-down card still counts, the opponent's does not")
	assert_eq(ops.beheld(1), [theirs])
	assert_eq(ops.beheld(7), [], "an invalid player beholds nothing")


func test_beheld_follows_a_recall() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	var on_board: int = _on_board("Chip", 0, 1)
	assert_eq(ops.beheld(0), [in_hand, on_board], "hand first, board after")

	ops.recall(on_board)
	assert_eq(ops.beheld(0), [on_board, in_hand], "a recalled card is now the newest card of the hand")
	assert_eq(ops.beheld(0).size(), 2, "and it is not counted twice")


# --- deep ---

func test_set_deep_calls_the_on_deep_hook() -> void:
	log.clear()
	ops.set_deep(0)
	assert_true(state.players[0].is_deep)
	assert_eq(spy.deep_players, [0])
	assert_eq(_of_type(MatchEvents.DEEP_CHANGED), [MatchEvents.deep_changed(0, true)])

	ops.set_deep(0)
	assert_eq(spy.deep_players, [0], "once Deep, the hook does not fire again")


func test_draw_into_an_empty_deck_calls_the_on_deep_hook() -> void:
	state.players[0].deck.clear()
	ops.draw(0)
	assert_eq(spy.deep_players, [], "an empty draw never reaches set_deep")


# --- privacy of the hidden-card events ---

func test_hand_and_deck_changes_are_private_and_board_changes_are_not() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	var on_board: int = _on_board("Chip", 0)
	log.clear()

	ops.change_power(in_hand, 1)
	ops.change_cost(in_hand, -1)
	ops.add_keyword(in_hand, "Shield")
	ops.change_power(on_board, 1)
	ops.add_keyword(on_board, "Shield")

	assert_eq(_of_type(MatchEvents.POWER_CHANGED)[0]["private_to"], 0, "a buff in hand is the owner's business")
	assert_eq(_of_type(MatchEvents.COST_CHANGED)[0]["private_to"], 0)
	assert_eq(_of_type(MatchEvents.KEYWORD_ADDED)[0]["private_to"], 0)
	assert_false(_of_type(MatchEvents.POWER_CHANGED)[1].has("private_to"), "a board buff is public")
	assert_false(_of_type(MatchEvents.KEYWORD_ADDED)[1].has("private_to"))


func test_a_private_event_is_hidden_from_the_other_player_only() -> void:
	var in_hand: int = ops.create_in_hand("Chip", 0)
	log.clear()
	ops.change_cost(in_hand, -1)
	var event: Dictionary = _of_type(MatchEvents.COST_CHANGED)[0]
	assert_eq(MatchEvents.redact_for(event, 0), event, "the owner sees it unchanged")
	assert_eq(MatchEvents.redact_for(event, 1), null, "the opponent does not get it at all")


## A stand-in for MatchAbilities that records what it was asked to do and can be
## told to save one card from dying.
class _SpyAbilities extends MatchAbilities:
	var drawn_ids: Array[int] = []
	var discard_ids: Array[int] = []
	var last_breath_ids: Array[int] = []
	var level_up_ids: Array[int] = []
	var death_prevented_ids: Array[int] = []
	var deep_players: Array[int] = []
	var save_from: int = -1

	func on_card_drawn(id: int) -> void:
		drawn_ids.append(id)

	func on_discard(id: int) -> void:
		discard_ids.append(id)

	func on_last_breath(id: int) -> void:
		last_breath_ids.append(id)

	func on_level_up(id: int) -> void:
		level_up_ids.append(id)

	func on_death_prevented(id: int) -> void:
		death_prevented_ids.append(id)

	func on_deep(player: int) -> void:
		deep_players.append(player)

	func prevents_death(id: int) -> bool:
		return id == save_from