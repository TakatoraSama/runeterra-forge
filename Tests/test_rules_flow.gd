## Tests for the match flow in MatchRules: start_match, the turn loop, mana,
## resolve order, swaps, stuns, priority and the game end.
extends "res://Tests/test_case.gd"

## Lanes whose effects never change lane power and never summon anything, so the power
## assertions below stay clean: Sunken Temple only shuffles a hand card back and draws
## (round end of turn 3), Noxkraya Arena only restricts placement (turn 5).
const LANES := ["SunkenTemple", "SunkenTemple", "NoxkrayaArena"]

## Records every ability hook call as ["hook", ...args].
class SpyAbilities extends MatchAbilities:
	var calls: Array = []

	func on_game_start(card_id: String, owner: int) -> void:
		calls.append(["on_game_start", card_id, owner])

	func on_card_drawn(id: int) -> void:
		calls.append(["on_card_drawn", id])

	func on_play(id: int) -> void:
		calls.append(["on_play", id])

	func on_round_start(id: int) -> bool:
		calls.append(["on_round_start", id])
		return false

	func on_round_end(id: int) -> bool:
		calls.append(["on_round_end", id])
		return false

	func on_swap_arrive(id: int, from_col: int, to_col: int) -> void:
		calls.append(["on_swap_arrive", id, from_col, to_col])

	func on_game_end_phase() -> void:
		calls.append(["on_game_end_phase"])

	func after_change() -> void:
		calls.append(["after_change"])

	## The arguments of every call to `hook`, in call order.
	func args_of(hook: String) -> Array:
		var out: Array = []
		for call in calls:
			if call[0] == hook:
				out.append(call.slice(1))
		return out

	func count_of(hook: String) -> int:
		return args_of(hook).size()

	func reset_calls() -> void:
		calls.clear()


var _spy: SpyAbilities


func before_each() -> void:
	_spy = SpyAbilities.new()


# ----------------------------
# Helpers
# ----------------------------

## A rules engine with the spy installed and the match already started.
func _started(deck0: Array, deck1: Array, seed_value: int = 7) -> MatchRules:
	var rules := MatchRules.new(MatchSetup.new_match(deck0, deck1, seed_value))
	rules.set_abilities(_spy)
	rules.start_match(Array(LANES))
	return rules


## A rules engine that has NOT started; the caller decides when.
func _unstarted(deck0: Array, deck1: Array, seed_value: int = 7) -> MatchRules:
	var rules := MatchRules.new(MatchSetup.new_match(deck0, deck1, seed_value))
	rules.set_abilities(_spy)
	return rules


## `count` known card ids, cycled, so a deck is never empty and never has dupes.
func _deck(count: int) -> Array:
	var pool: Array = ["Chip", "Nasus1", "Ahri1", "Tryndamere1", "Blade", "Valor", "Janna1", "Kennen1", "Irelia1", "Renekton1"]
	var out: Array = []
	for i in count:
		out.append(pool[i % pool.size()])
	return out


## Puts a fresh card of `card_id` into player `p`'s hand and returns it.
func _give(state: MatchState, p: int, card_id: String) -> CardState:
	var card := state.new_card(card_id, p, CardState.Location.HAND)
	state.add_to_hand(p, card.instance_id)
	return card


## Puts a resolved card on the board (as if summoned) and returns it.
func _on_board(state: MatchState, p: int, col: int, card_id: String, power_bonus: int = 0) -> CardState:
	var card := state.new_card(card_id, p, CardState.Location.BOARD)
	state.place_card(card.instance_id, col, p)
	card.is_resolved = true
	card.power_modifier = power_bonus
	state.play_order.append(card.instance_id)
	return card


## Ends the round for both players and returns everything the second end_turn emitted.
func _end_round(rules: MatchRules) -> Array:
	rules.submit(0, MatchIntents.end_turn())
	return rules.submit(1, MatchIntents.end_turn())


## Plays until the match is over, or the guard trips.
func _play_to_end(rules: MatchRules, guard: int = 40) -> void:
	var rounds: int = 0
	while rules.state.game_phase != MatchState.GamePhase.GAME_END and rounds < guard:
		_end_round(rules)
		rounds += 1


func _types_of(events: Array) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		out.append(event["type"])
	return out


func _index_of_type(events: Array, type_name: String) -> int:
	return _types_of(events).find(type_name)


func _count_type(events: Array, type_name: String) -> int:
	var count: int = 0
	for event: Dictionary in events:
		if event["type"] == type_name:
			count += 1
	return count


func _events_of_type(events: Array, type_name: String) -> Array:
	var out: Array = []
	for event: Dictionary in events:
		if event["type"] == type_name:
			out.append(event)
	return out


## Advances `count` whole rounds.
func _skip(rules: MatchRules, count: int) -> void:
	for _i in count:
		_end_round(rules)


# ----------------------------
# start_match
# ----------------------------

func test_start_match_opens_game_start_then_priority() -> void:
	var rules := _unstarted(_deck(10), _deck(10))
	var events := rules.start_match(Array(LANES))
	var types := _types_of(events)
	assert_eq(types[0], MatchEvents.PHASE_CHANGED, "GAME_START is announced first")
	assert_eq(events[0]["game_phase"], MatchState.GamePhase.GAME_START)
	assert_eq(events[0]["round_phase"], MatchState.RoundPhase.NONE)
	assert_eq(types[1], MatchEvents.PRIORITY_CHANGED, "priority is the second event")
	assert_eq(events[1]["player"], rules.state.flip_first, "priority names the new holder")
	assert_true(rules.state.flip_first == 0 or rules.state.flip_first == 1, "priority is a real player")


func test_start_match_fires_game_start_once_per_distinct_card() -> void:
	var deck: Array = ["Azir1", "Nasus1", "Azir1", "Chip", "Ahri1"]
	var rules := _unstarted(deck, deck)
	rules.start_match(Array(LANES))
	assert_eq(_spy.args_of("on_game_start"), [["Azir1", 0], ["Azir1", 1]], "two copies fire once, per player, in deck order")


func test_start_match_calls_game_start_for_both_players_in_order() -> void:
	var deck: Array = ["Azir1", "Chip"]
	var rules := _unstarted(deck, deck)
	rules.start_match(Array(LANES))
	var calls := _spy.args_of("on_game_start")
	assert_eq(calls.size(), 2, "one per player")
	assert_eq(calls[0][1], 0, "player 0 first")
	assert_eq(calls[1][1], 1, "then player 1")


func test_start_match_assigns_then_reveals_lane_zero() -> void:
	var rules := _unstarted(_deck(10), _deck(10))
	var events := rules.start_match(Array(LANES))
	var assigned := _index_of_type(events, MatchEvents.LANE_ASSIGNED)
	var revealed := _index_of_type(events, MatchEvents.LANE_REVEALED)
	assert_true(assigned >= 0, "lanes are assigned")
	assert_true(revealed > assigned, "column 0 is revealed after the assignment")
	var reveal: Dictionary = _events_of_type(events, MatchEvents.LANE_REVEALED)[0]
	assert_eq(reveal["col"], 0, "only column 0 opens the match")
	assert_eq(reveal["lane_id"], LANES[0])
	assert_eq(_count_type(events, MatchEvents.LANE_REVEALED), 1, "only one lane opens")
	assert_eq(rules.state.lane_ids, LANES, "the given lane order is kept")


func test_start_match_draws_three_each_in_flip_first_order() -> void:
	var rules := _unstarted(_deck(10), _deck(10))
	var events := rules.start_match(Array(LANES))
	var first: MatchState = rules.state
	var draws := _events_of_type(events, MatchEvents.CARD_DRAWN)
	assert_eq(draws.size(), 6 + 2 * MatchRules.DRAW_PER_TURN, "three opening cards each, then the turn-1 draw")
	var expected: Array[int] = [first.flip_first, 1 - first.flip_first]
	for i in MatchRules.INITIAL_DRAW * 2:
		assert_eq(draws[i]["player"], expected[i / MatchRules.INITIAL_DRAW], "draw %d goes to the flip-first player first" % i)
		assert_true(draws[i]["instance_id"] >= 0, "a real card was drawn")


func test_start_match_ends_in_play_phase_of_turn_one() -> void:
	var rules := _unstarted(_deck(10), _deck(10))
	var events := rules.start_match(Array(LANES))
	var types := _types_of(events)
	assert_eq(types[types.size() - 1], MatchEvents.PHASE_CHANGED, "the last event opens PLAY")
	var last: Dictionary = events[events.size() - 1]
	assert_eq(last["round_phase"], MatchState.RoundPhase.PLAY)
	assert_eq(last["game_phase"], MatchState.GamePhase.TURN_LOOP)
	assert_eq(last["turn"], 1, "turn 1")
	assert_eq(rules.state.round_phase, MatchState.RoundPhase.PLAY)
	assert_eq(rules.state.turn, 1)
	assert_true(_index_of_type(events, MatchEvents.TURN_STARTED) < types.size() - 1, "the turn starts before PLAY opens")


func test_start_match_twice_returns_nothing() -> void:
	var rules := _unstarted(_deck(10), _deck(10))
	rules.start_match(Array(LANES))
	var turn_before: int = rules.state.turn
	assert_eq(rules.start_match(Array(LANES)), [], "a second start is refused")
	assert_eq(rules.state.turn, turn_before, "the match is not restarted")


# ----------------------------
# Turn loop and mana
# ----------------------------

func test_turn_one_gives_four_cards_and_one_mana() -> void:
	var rules := _started(_deck(10), _deck(10))
	for p in 2:
		assert_eq(rules.state.players[p].hand.size(), 4, "3 opening cards + the turn draw")
		assert_eq(rules.state.players[p].get_max_mana(), 1, "turn 1 max mana is 1")
		assert_eq(rules.state.players[p].current_mana, 1)


func test_max_mana_follows_the_turn_number() -> void:
	var rules := _started(_deck(20), _deck(20))
	var expected: Array[int] = [2, 3, 4]
	for turn in 3:
		_skip(rules, 1)
		assert_eq(rules.state.turn, turn + 2, "the turn advanced")
		for p in 2:
			assert_eq(rules.state.players[p].get_max_mana(), expected[turn], "max mana on turn %d" % rules.state.turn)
			assert_eq(rules.state.players[p].current_mana, expected[turn], "mana refilled each turn")


func test_temp_mana_applies_for_exactly_one_turn() -> void:
	var rules := _started(_deck(20), _deck(20))
	rules.ops.queue_temp_mana(0, 5)
	_skip(rules, 1)
	assert_eq(rules.state.turn, 2, "queued during turn 1, so it lands on turn 2")
	assert_eq(rules.state.players[0].get_max_mana(), 2 + 5, "turn 2 max mana is turn + 5")
	assert_eq(rules.state.players[0].current_mana, 2 + 5, "and the pool is full")
	assert_eq(rules.state.players[1].get_max_mana(), 2, "the other player is unaffected")
	_skip(rules, 1)
	assert_eq(rules.state.turn, 3)
	assert_eq(rules.state.players[0].get_max_mana(), 3, "the bonus is gone on turn 3")
	assert_eq(rules.state.players[0].current_mana, 3)


func test_end_turn_of_one_player_announces_only_that_turn_end() -> void:
	var rules := _started(_deck(20), _deck(20))
	var events := rules.submit(0, MatchIntents.end_turn())
	assert_eq(_types_of(events), [MatchEvents.TURN_ENDED], "ending early is accepted, and says so")
	assert_eq(events[0]["player"], 0, "turn_ended is public and names who ended")
	assert_eq(rules.state.round_phase, MatchState.RoundPhase.PLAY, "the round keeps going")
	assert_true(rules.state.players[0].ended_turn)
	assert_false(rules.state.players[1].ended_turn)


func test_both_end_turns_run_swaps_resolve_and_round_end() -> void:
	var rules := _started(_deck(20), _deck(20))
	var events := _end_round(rules)
	var types := _types_of(events)
	var swap := types.find(MatchEvents.PHASE_CHANGED)
	var phases: Array = []
	for event: Dictionary in events:
		if event["type"] == MatchEvents.PHASE_CHANGED:
			phases.append(event["round_phase"])
	assert_eq(phases, [
		MatchState.RoundPhase.SWAP_LANE,
		MatchState.RoundPhase.RESOLVE,
		MatchState.RoundPhase.ROUND_END,
		MatchState.RoundPhase.ROUND_START,
		MatchState.RoundPhase.PLAY,
	], "the phase changes of a round, and the next turn opening right after it")
	assert_eq(events[swap]["turn"], 1, "the round ran on turn 1")
	assert_true(types.has(MatchEvents.PRIORITY_CHANGED), "priority is reassigned every round")
	assert_eq(rules.state.turn, 2, "the next turn opened")
	assert_false(rules.state.players[0].ended_turn, "the flag resets for the new turn")
	assert_false(rules.state.players[1].ended_turn)


func test_new_turn_draws_one_card_each() -> void:
	var rules := _started(_deck(20), _deck(20))
	var before: Array = [rules.state.players[0].deck.size(), rules.state.players[1].deck.size()]
	_skip(rules, 1)
	for p in 2:
		assert_eq(rules.state.players[p].deck.size(), before[p] - 1, "player %d drew one card" % p)


# ----------------------------
# Resolve order
# ----------------------------

## Gives both players two cards, plays them, and returns
## [flip_first, [ids the flip-first player played], [ids the other player played]].
func _play_both(rules: MatchRules) -> Array:
	var state: MatchState = rules.state
	for p in 2:
		state.players[p].current_mana = 10
	var mine: Array = [_give(state, state.flip_first, "Chip"), _give(state, state.flip_first, "Valor")]
	var theirs: Array = [_give(state, 1 - state.flip_first, "Chip"), _give(state, 1 - state.flip_first, "Valor")]
	for card in mine:
		rules.submit(state.flip_first, MatchIntents.play_card(card.instance_id, 0))
	for card in theirs:
		rules.submit(1 - state.flip_first, MatchIntents.play_card(card.instance_id, 1))
	return [
		state.flip_first,
		[mine[0].instance_id, mine[1].instance_id],
		[theirs[0].instance_id, theirs[1].instance_id],
	]


func test_resolve_reveals_flip_first_player_first_in_play_order() -> void:
	var rules := _started(_deck(20), _deck(20))
	var setup := _play_both(rules)
	var first_ids: Array = setup[1]
	var second_ids: Array = setup[2]
	_spy.reset_calls()
	var events := _end_round(rules)
	var revealed: Array = []
	for event: Dictionary in _events_of_type(events, MatchEvents.CARD_REVEALED):
		revealed.append(event["instance_id"])
	assert_eq(revealed, first_ids + second_ids, "flip-first player's plays come first, in play order")
	assert_eq(_spy.args_of("on_play"), [[first_ids[0]], [first_ids[1]], [second_ids[0]], [second_ids[1]]], "on_play follows the reveal order")


func test_resolve_started_lists_plays_without_card_id() -> void:
	var rules := _started(_deck(20), _deck(20))
	var setup := _play_both(rules)
	var played: Array = setup[1] + setup[2]
	var events := _end_round(rules)
	var started := _events_of_type(events, MatchEvents.RESOLVE_STARTED)
	assert_eq(started.size(), 1, "resolve announces the round once")
	var plays: Array = started[0]["plays"]
	assert_eq(plays.size(), 4, "all four plays are listed")
	for play: Dictionary in plays:
		assert_false(play.has("card_id"), "a face-down play must not name its card")
		assert_true(play.has("player") and play.has("instance_id") and play.has("col") and play.has("slot"), "the play is locatable")
	var listed: Array = []
	for play: Dictionary in plays:
		listed.append(play["instance_id"])
	assert_eq(listed, played, "in the order they will be revealed")


func test_resolve_started_leaves_out_cards_that_left_the_board() -> void:
	var rules := _started(_deck(20), _deck(20))
	var setup := _play_both(rules)
	rules.submit(setup[0], MatchIntents.undo())
	var events := _end_round(rules)
	var plays: Array = _events_of_type(events, MatchEvents.RESOLVE_STARTED)[0]["plays"]
	var listed: Array = []
	for play: Dictionary in plays:
		listed.append(play["instance_id"])
	assert_eq(listed, setup[2], "the undone plays are not on the board any more")


func test_spell_resolves_and_leaves_the_board() -> void:
	var rules := _started(_deck(20), _deck(20))
	var spell := _give(rules.state, 0, "HexCoreUpgrade")
	rules.state.players[0].current_mana = 10
	rules.submit(0, MatchIntents.play_card(spell.instance_id, MatchState.SPELL_COL))
	var events := _end_round(rules)
	var resolved := _events_of_type(events, MatchEvents.SPELL_RESOLVED)
	assert_eq(resolved.size(), 1, "the spell announced its resolution")
	assert_eq(resolved[0]["instance_id"], spell.instance_id)
	assert_eq(rules.state.card(spell.instance_id).location, CardState.Location.GONE, "a resolved spell leaves the board")
	assert_false(rules.state.zone_cards(MatchState.SPELL_COL, 0).has(spell.instance_id), "the spell zone is free again")
	assert_eq(_spy.args_of("on_play"), [[spell.instance_id]], "the spell's {Play} ability fired")


func test_unit_stays_on_the_board_after_resolving() -> void:
	var rules := _started(_deck(20), _deck(20))
	var unit := _give(rules.state, 0, "Chip")
	rules.state.players[0].current_mana = 10
	rules.submit(0, MatchIntents.play_card(unit.instance_id, 2))
	_end_round(rules)
	var card: CardState = rules.state.card(unit.instance_id)
	assert_eq(card.location, CardState.Location.BOARD, "the unit is still on the board")
	assert_eq(card.col, 2, "in the column it was played into")
	assert_true(card.is_resolved, "and it counts towards lane power")


func test_resolve_marks_the_summoned_tracker_resolved() -> void:
	var rules := _started(_deck(20), _deck(20))
	var unit := _give(rules.state, 0, "Chip")
	rules.state.players[0].current_mana = 10
	rules.submit(0, MatchIntents.play_card(unit.instance_id, 0))
	assert_eq(rules.state.summoned.size(), 1, "the play was tracked")
	assert_false(rules.state.summoned[0]["is_resolved"], "a card played this turn starts unresolved")
	_end_round(rules)
	assert_true(rules.state.summoned[0]["is_resolved"], "and is marked resolved when it flips")


# ----------------------------
# Stuns
# ----------------------------

func test_stun_from_an_earlier_turn_expires_at_resolve() -> void:
	var rules := _started(_deck(20), _deck(20))
	var unit := _on_board(rules.state, 0, 0, "Chip")
	rules.ops.add_keyword(unit.instance_id, "Stun")
	rules.state.stuns.append({"instance_id": unit.instance_id, "stunned_on_turn": 0})
	var events := _end_round(rules)
	var removed := _events_of_type(events, MatchEvents.KEYWORD_REMOVED)
	assert_eq(removed.size(), 1, "the Stun keyword was taken away")
	assert_eq(removed[0]["instance_id"], unit.instance_id)
	assert_eq(removed[0]["keyword"], "Stun")
	assert_eq(rules.state.stuns.size(), 0, "the stun entry is gone")
	assert_false(rules.state.card(unit.instance_id).has_keyword("Stun"), "and so is the runtime keyword")


func test_stun_from_this_turn_survives_the_resolve() -> void:
	var rules := _started(_deck(20), _deck(20))
	var unit := _on_board(rules.state, 0, 0, "Chip")
	rules.ops.add_keyword(unit.instance_id, "Stun")
	rules.state.stuns.append({"instance_id": unit.instance_id, "stunned_on_turn": rules.state.turn})
	var events := _end_round(rules)
	assert_eq(_count_type(events, MatchEvents.KEYWORD_REMOVED), 0, "a stun from this turn does not expire")
	assert_eq(rules.state.stuns.size(), 1, "the entry stays")


func test_stun_of_a_card_that_left_the_board_is_cleared() -> void:
	var rules := _started(_deck(20), _deck(20))
	var unit := _on_board(rules.state, 0, 0, "Chip")
	rules.ops.add_keyword(unit.instance_id, "Stun")
	rules.state.stuns.append({"instance_id": unit.instance_id, "stunned_on_turn": rules.state.turn})
	rules.state.remove_from_zone(unit.instance_id)
	rules.state.card(unit.instance_id).location = CardState.Location.GONE
	var events := _end_round(rules)
	assert_eq(_count_type(events, MatchEvents.KEYWORD_REMOVED), 1, "a stun on a card that is gone is dropped")
	assert_eq(rules.state.stuns.size(), 0)


func test_stunned_card_skips_the_round_start_and_round_end_hooks() -> void:
	var rules := _started(_deck(20), _deck(20))
	var unit := _on_board(rules.state, 0, 0, "Chip")
	rules.ops.add_keyword(unit.instance_id, "Stun")
	rules.state.stuns.append({"instance_id": unit.instance_id, "stunned_on_turn": rules.state.turn})
	_spy.reset_calls()
	_end_round(rules)
	assert_eq(_spy.args_of("on_round_end"), [], "a stunned card does not fire {Round End}")
	assert_eq(_spy.args_of("on_round_start"), [], "nor {Round Start} on the next turn")
	var free := _on_board(rules.state, 0, 1, "Chip")
	_skip(rules, 1)
	var on_start: Array = _spy.args_of("on_round_start")
	on_start.sort()
	var expected: Array = [[unit.instance_id], [free.instance_id]]
	expected.sort()
	assert_eq(on_start, expected, "once the stun expired at the resolve of turn 2 both cards fire again")


# ----------------------------
# Swaps
# ----------------------------

## Puts a resolved Elusive card in column `col` for `p` and returns it.
func _elusive(state: MatchState, p: int, col: int) -> CardState:
	return _on_board(state, p, col, "Ahri1")


func test_swap_moves_the_card_at_swap_lane() -> void:
	var rules := _started(_deck(20), _deck(20))
	var card := _elusive(rules.state, 0, 0)
	_spy.reset_calls()
	var started := rules.submit(0, MatchIntents.swap_card(card.instance_id, 2))
	assert_eq(_types_of(started), [MatchEvents.SWAP_STARTED], "the swap is announced while still in PLAY")
	assert_eq(rules.state.pending_swaps.size(), 1)
	var events := _end_round(rules)
	var swapped := _events_of_type(events, MatchEvents.CARD_SWAPPED)
	assert_eq(swapped.size(), 1, "the move happened at SWAP_LANE")
	assert_eq(swapped[0]["from_col"], 0)
	assert_eq(swapped[0]["to_col"], 2)
	assert_eq(rules.state.card(card.instance_id).col, 2, "the card ended in the destination")
	assert_eq(rules.state.pending_swaps.size(), 0, "the queue is cleared")
	assert_eq(rules.state.swap_history.size(), 1, "the swap is in the history")
	var entry: Dictionary = rules.state.swap_history[0]
	assert_eq(entry["card_id"], "Ahri1")
	assert_eq(entry["owner_player_id"], 0)
	assert_eq(entry["swapped_by_player_id"], 0)
	assert_eq(entry["from_col"], 0)
	assert_eq(entry["to_col"], 2)
	assert_eq(entry["turn_number"], 1)
	assert_eq(_spy.args_of("on_swap_arrive"), [[card.instance_id, 0, 2]], "the swap-arrive ability fired")


func test_swaps_run_in_flip_first_order() -> void:
	var rules := _started(_deck(20), _deck(20))
	var state: MatchState = rules.state
	var mine := _elusive(state, state.flip_first, 0)
	var theirs := _elusive(state, 1 - state.flip_first, 0)
	rules.submit(1 - state.flip_first, MatchIntents.swap_card(theirs.instance_id, 1))
	rules.submit(state.flip_first, MatchIntents.swap_card(mine.instance_id, 1))
	var events := _end_round(rules)
	var swapped := _events_of_type(events, MatchEvents.CARD_SWAPPED)
	assert_eq(swapped.size(), 2)
	assert_eq(swapped[0]["instance_id"], mine.instance_id, "the flip-first player's swap moves first")
	assert_eq(swapped[1]["instance_id"], theirs.instance_id)


func test_swap_is_cancelled_when_the_destination_filled_up() -> void:
	var rules := _started(_deck(20), _deck(20))
	var state: MatchState = rules.state
	var card := _elusive(state, 0, 0)
	rules.submit(0, MatchIntents.swap_card(card.instance_id, 1))
	for _i in 4:
		_on_board(state, 0, 1, "Chip")
	var events := _end_round(rules)
	assert_eq(_count_type(events, MatchEvents.CARD_SWAPPED), 0, "the swap is dropped")
	assert_eq(state.card(card.instance_id).col, 0, "the card stays where it was")
	assert_eq(state.swap_history.size(), 0, "a cancelled swap is not in the history")
	assert_eq(_spy.count_of("on_swap_arrive"), 0, "and no swap-arrive ability fires")


func test_swap_is_cancelled_when_the_card_left_its_column() -> void:
	var rules := _started(_deck(20), _deck(20))
	var state: MatchState = rules.state
	var card := _elusive(state, 0, 0)
	rules.submit(0, MatchIntents.swap_card(card.instance_id, 1))
	state.remove_from_zone(card.instance_id)
	card.location = CardState.Location.GONE
	var events := _end_round(rules)
	assert_eq(_count_type(events, MatchEvents.CARD_SWAPPED), 0, "a card that is no longer there cannot swap")


# ----------------------------
# Priority
# ----------------------------

## Puts a resolved unit worth `power` in every lane of player `p`.
func _lane_row(state: MatchState, p: int, powers: Array) -> void:
	for col in MatchState.COLUMNS:
		_on_board(state, p, col, "Chip", int(powers[col]) - 1)


func test_priority_goes_to_whoever_won_more_lanes() -> void:
	var rules := _started(_deck(20), _deck(20))
	_lane_row(rules.state, 0, [5, 4, 0])
	_lane_row(rules.state, 1, [1, 1, 2])
	_end_round(rules)
	assert_eq(rules.state.flip_first, 0, "two lanes won is enough")
	assert_true(rules.state.flip_first != 1, "and it beats the higher total power of the opponent")


func test_priority_falls_back_to_total_power() -> void:
	var rules := _started(_deck(20), _deck(20))
	# Lane wins are level (one each plus a tie), so the totals decide: 11 vs 12.
	_lane_row(rules.state, 0, [9, 2, 0])
	_lane_row(rules.state, 1, [4, 8, 0])
	_end_round(rules)
	assert_eq(rules.state.flip_first, 1, "the higher total takes priority")


func test_priority_counts_only_resolved_cards() -> void:
	var rules := _started(_deck(20), _deck(20))
	var face_down := _on_board(rules.state, 0, 0, "Chip", 40)
	face_down.is_resolved = false
	_on_board(rules.state, 1, 0, "Chip")
	_on_board(rules.state, 0, 1, "Chip")
	_on_board(rules.state, 1, 1, "Chip")
	_on_board(rules.state, 0, 2, "Chip")
	_on_board(rules.state, 1, 2, "Chip")
	_end_round(rules)
	assert_eq(rules.state.flip_first, 1, "a face-down card does not win its lane")


func test_priority_on_a_full_tie_comes_from_the_match_rng() -> void:
	var rules := _started(_deck(20), _deck(20))
	var state: MatchState = rules.state
	_lane_row(state, 0, [0, 0, 0])
	_lane_row(state, 1, [0, 0, 0])
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = state.rng.state
	var expected: int = expected_rng.randi_range(0, 1)
	var events := _end_round(rules)
	var priority := _events_of_type(events, MatchEvents.PRIORITY_CHANGED)
	assert_eq(priority.size(), 1, "priority is always announced once a round")
	assert_eq(state.flip_first, expected, "an even match is decided by the match RNG, not by chance")
	assert_eq(priority[0]["player"], expected)


# ----------------------------
# Game end
# ----------------------------

func test_game_ends_after_max_turns() -> void:
	var rules := _started(_deck(40), _deck(40))
	_play_to_end(rules)
	assert_eq(rules.state.game_phase, MatchState.GamePhase.GAME_END)
	assert_eq(rules.state.round_phase, MatchState.RoundPhase.NONE)
	assert_eq(rules.state.turn, MatchRules.MAX_TURNS, "six turns were played")
	assert_eq(_spy.count_of("on_game_end_phase"), 1, "{Game End} abilities ran exactly once")


func test_game_end_winner_by_two_lanes() -> void:
	var rules := _started(_deck(40), _deck(40))
	_skip(rules, 5)
	_lane_row(rules.state, 0, [5, 5, 0])
	_lane_row(rules.state, 1, [1, 1, 1])
	var events := _end_round(rules)
	var ended := _events_of_type(events, MatchEvents.GAME_ENDED)
	assert_eq(ended.size(), 1, "the match ends after the sixth round")
	assert_eq(ended[0]["winner"], 0, "two lanes win the match")
	assert_eq(ended[0]["lane_powers"], [[5, 5, 0], [1, 1, 1]], "the powers are absolute player rows")


func test_game_end_winner_by_total_power() -> void:
	var rules := _started(_deck(40), _deck(40))
	_skip(rules, 5)
	# Lane wins are level (one each plus a tie), but player 1 has the bigger total.
	_lane_row(rules.state, 0, [9, 2, 0])
	_lane_row(rules.state, 1, [4, 8, 0])
	var events := _end_round(rules)
	var ended := _events_of_type(events, MatchEvents.GAME_ENDED)
	assert_eq(ended[0]["winner"], 1, "no lane win, so the total power decides")
	assert_eq(ended[0]["lane_powers"], [[9, 2, 0], [4, 8, 0]])


func test_game_end_is_a_tie_on_equal_power() -> void:
	var rules := _started(_deck(40), _deck(40))
	_skip(rules, 5)
	_lane_row(rules.state, 0, [2, 2, 2])
	_lane_row(rules.state, 1, [2, 2, 2])
	var events := _end_round(rules)
	var ended := _events_of_type(events, MatchEvents.GAME_ENDED)
	assert_eq(ended[0]["winner"], -1, "identical boards tie")
	assert_eq(ended[0]["lane_powers"], [[2, 2, 2], [2, 2, 2]])


func test_game_end_ignores_unresolved_cards() -> void:
	var rules := _started(_deck(40), _deck(40))
	_skip(rules, 5)
	_lane_row(rules.state, 0, [0, 0, 0])
	_lane_row(rules.state, 1, [0, 0, 0])
	var face_down := _on_board(rules.state, 1, 0, "Chip", 99)
	face_down.is_resolved = false
	var events := _end_round(rules)
	var ended := _events_of_type(events, MatchEvents.GAME_ENDED)
	assert_eq(ended[0]["winner"], -1, "a face-down card counts for nothing")
	assert_eq(ended[0]["lane_powers"][1][0], 0, "not even for the lane it sits in")


func test_intents_after_the_game_end_are_wrong_phase() -> void:
	var rules := _started(_deck(40), _deck(40))
	_play_to_end(rules)
	for intent: Dictionary in [
		MatchIntents.end_turn(),
		MatchIntents.undo(),
		MatchIntents.play_card(1, 0),
		MatchIntents.swap_card(1, 1),
	]:
		var events := rules.submit(0, intent)
		assert_eq(events.size(), 1, "one rejection")
		assert_eq(events[0]["type"], MatchEvents.INTENT_REJECTED)
		assert_eq(events[0]["reason"], "wrong_phase", "nothing is playable once the match is over")
		assert_eq(_spy.count_of("on_game_end_phase"), 1, "and the {Game End} pass does not run twice")


# ----------------------------
# Deep
# ----------------------------

func test_emptying_the_deck_marks_the_player_deep() -> void:
	var rules := _unstarted(["Chip", "Blade", "Valor"], _deck(10))
	var events := rules.start_match(Array(LANES))
	var deep := _events_of_type(events, MatchEvents.DEEP_CHANGED)
	assert_eq(deep.size(), 1, "only the player with the three-card deck runs out")
	assert_eq(deep[0]["player"], 0)
	assert_true(deep[0]["is_deep"], "and they are Deep")
	assert_true(rules.state.players[0].is_deep, "the flag sticks on the player")
	assert_false(rules.state.players[1].is_deep, "the other player is fine")


func test_deep_is_not_announced_twice() -> void:
	var rules := _unstarted(["Chip", "Blade", "Valor"], _deck(10))
	var events := rules.start_match(Array(LANES))
	_skip(rules, 1)
	assert_true(rules.state.players[0].is_deep, "still Deep on turn 2")
	assert_eq(_spy.count_of("on_game_start"), 0, "no abilities exist in M2")


func test_round_start_and_round_end_hooks_run_over_the_whole_board() -> void:
	var rules := _started(_deck(20), _deck(20))
	var state: MatchState = rules.state
	var first := _on_board(state, state.flip_first, 0, "Chip")
	var second := _on_board(state, 1 - state.flip_first, 1, "Chip")
	var gone := _on_board(state, 0, 2, "Chip")
	state.remove_from_zone(gone.instance_id)
	gone.location = CardState.Location.GONE
	_skip(rules, 1)
	var on_start: Array = _spy.args_of("on_round_start")
	on_start.sort()
	var expected: Array = [[first.instance_id], [second.instance_id]]
	expected.sort()
	assert_eq(on_start, expected, "both board cards fired {Round Start}, the gone one did not")
	assert_eq(_spy.count_of("on_round_end"), 2, "and both fired {Round End} as well")


## Forces `flip_first` and gives both players something to act with.
func _with_priority(first_player: int) -> MatchRules:
	var rules := _started(_deck(20), _deck(20))
	rules.state.flip_first = first_player
	for p in 2:
		rules.state.players[p].current_mana = 10
	return rules


## Submits a play and fails the test when the engine refuses it.
func _assert_plays_first(rules: MatchRules, player: int, intent: Dictionary) -> void:
	var rejections: Array = []
	for event: Dictionary in rules.submit(player, intent):
		if event["type"] == MatchEvents.INTENT_REJECTED:
			rejections.append(event)
	assert_eq(rejections, [], "the play of player %d was accepted" % player)


func test_resolve_reveals_the_flip_first_player_first_although_they_played_last() -> void:
	var rules := _with_priority(1)
	var state: MatchState = rules.state
	var early := _give(state, 0, "Chip")  # player 0 plays first
	var late := _give(state, 1, "Chip")  # player 1 plays second
	_assert_plays_first(rules, 0, MatchIntents.play_card(early.instance_id, 0))
	_assert_plays_first(rules, 1, MatchIntents.play_card(late.instance_id, 0))
	assert_eq(state.played_this_turn, [early.instance_id, late.instance_id], "the play order is 0 then 1")
	_spy.reset_calls()
	var events := _end_round(rules)
	var revealed: Array = []
	for event: Dictionary in _events_of_type(events, MatchEvents.CARD_REVEALED):
		revealed.append(event["instance_id"])
	assert_eq(revealed, [late.instance_id, early.instance_id], "the flip-first player reveals first, not the first player")
	assert_eq(_spy.args_of("on_play"), [[late.instance_id], [early.instance_id]], "on_play follows the reveal order")


func test_resolve_started_also_puts_the_flip_first_player_first() -> void:
	var rules := _with_priority(1)
	var state: MatchState = rules.state
	var early := _give(state, 0, "Chip")
	var late := _give(state, 1, "Chip")
	rules.submit(0, MatchIntents.play_card(early.instance_id, 0))
	rules.submit(1, MatchIntents.play_card(late.instance_id, 0))
	var events := _end_round(rules)
	var plays: Array = _events_of_type(events, MatchEvents.RESOLVE_STARTED)[0]["plays"]
	var listed: Array = []
	for play: Dictionary in plays:
		listed.append(play["instance_id"])
	assert_eq(listed, [late.instance_id, early.instance_id], "the face-down board is listed in reveal order")


func test_round_hooks_run_flip_first_player_first_not_in_play_order() -> void:
	var rules := _with_priority(1)
	var state: MatchState = rules.state
	# play_order deliberately lists player 0's card first, and player 1 goes on to win
	# two lanes so that the priority of the next turn stays deterministic at 1.
	var zero_card := _on_board(state, 0, 0, "Chip")
	var one_card := _on_board(state, 1, 0, "Chip", 4)
	var one_other := _on_board(state, 1, 1, "Chip")
	assert_eq(state.play_order, [zero_card.instance_id, one_card.instance_id, one_other.instance_id], "player 0's card is first in play order")
	_spy.reset_calls()
	_skip(rules, 1)
	assert_eq(state.flip_first, 1, "player 1 still has priority after winning two lanes")
	var flip_first_first: Array = [
		[one_card.instance_id], [one_other.instance_id], [zero_card.instance_id],
	]
	assert_eq(_spy.args_of("on_round_end"), flip_first_first, "{Round End} runs for the flip-first player first")
	assert_eq(_spy.args_of("on_round_start"), flip_first_first, "{Round Start} runs for the flip-first player first")
