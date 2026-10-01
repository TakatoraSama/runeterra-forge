## Every M5a hidden-information fix, plus a whole-match sweep with MatchLeakCheck.
##
## The rules are small and easy to state: an opponent's pool must not move while they
## are choosing, a card that has not flipped is nothing but a slot, a refusal is the
## sender's own business, the three lanes stay unnamed until they are revealed, and the
## n-th instance id must not be the n-th card of a deck list. Each test below pins one
## of them against the engine; the sweep at the end then runs MatchLeakCheck over every
## delivered batch of a real bot-vs-bot match, for BOTH viewers, and demands silence.
extends "res://Tests/test_case.gd"

## MatchDecks.DEFAULT_DECK_IDS, spelled out so this file pins the cards it plays.
const DECK_0: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Ahri1",
	"Kennen1", "NavoriConspirator", "Janna1", "Draven1", "Rumble1", "Sion1",
]

## MatchDecks.BOT_DECK_IDS.
const DECK_1: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Trundle1",
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk",
]

const SEEDS: Array[int] = [1, 2, 3, 7, 99]


## A match in turn 1 PLAY with the real abilities, starting from the decks above.
func _started(seed_value: int, deck0: Array = DECK_0, deck1: Array = DECK_1) -> MatchRules:
	var rules := MatchRules.new(MatchSetup.new_match(deck0, deck1, seed_value))
	MatchCardAbilities.install(rules)
	rules.start_match()
	return rules


## A bare state plus a MatchOps whose events land in `log`, for the primitives whose
## output a submit() would otherwise swallow.
func _logged_ops(state: MatchState, log: Array) -> MatchOps:
	return MatchOps.new(state, func(event: Dictionary) -> void: log.append(event), null)


## The first hand card `player` can afford right now, or -1.
func _affordable(state: MatchState, player: int) -> int:
	for raw in state.players[player].hand:
		var card := state.card(int(raw))
		if card.get_current_cost() <= state.players[player].current_mana:
			return int(raw)
	return -1


## The single event of that type in a batch.
func _one_of(events: Array, type_name: StringName) -> Dictionary:
	for event: Variant in events:
		if event is Dictionary and (event as Dictionary).get("type", &"") == type_name:
			return event
	return {}


## Every event of that type in a batch.
func _all_of(events: Array, type_name: StringName) -> Array:
	var found: Array = []
	for event: Variant in events:
		if event is Dictionary and (event as Dictionary).get("type", &"") == type_name:
			found.append(event)
	return found


func _board_row(snapshot: Dictionary, instance_id: int) -> Dictionary:
	for row: Variant in snapshot["board"]:
		if int((row as Dictionary)["instance_id"]) == instance_id:
			return row
	return {}


# ----------------------------
# Opponent mana does not move during PLAY
# ----------------------------

func test_a_play_spends_from_a_pool_the_opponent_cannot_see() -> void:
	var rules := _started(3)
	var state := rules.state
	var id: int = _affordable(state, 0)
	assert_true(id > 0, "player 0 has something to play on turn 1")

	var spent := _one_of(rules.submit(0, MatchIntents.play_card(id, 0)), MatchEvents.MANA_CHANGED)
	assert_false(spent.is_empty(), "the spend is still published — to its owner")
	assert_eq(int(spent["private_to"]), 0, "and privately")
	assert_eq(int(spent["current"]), state.players[0].current_mana, "carrying the new value")
	assert_eq(MatchEvents.redact_for(spent, 0), spent, "the owner sees it")
	assert_eq(MatchEvents.redact_for(spent, 1), null, "the opponent sees nothing at all")


func test_an_undo_refunds_into_the_same_hidden_pool() -> void:
	var rules := _started(4)
	var state := rules.state
	state.players[1].current_mana = 10
	var id: int = _affordable(state, 1)
	rules.submit(1, MatchIntents.play_card(id, 0))

	var refunded := _one_of(rules.submit(1, MatchIntents.undo()), MatchEvents.MANA_CHANGED)
	assert_false(refunded.is_empty(), "the refund is published too")
	assert_eq(int(refunded["private_to"]), 1, "and privately as well")
	assert_eq(MatchEvents.redact_for(refunded, 0), null, "the opponent learns nothing")


func test_the_real_pool_is_republished_at_resolve_for_everyone() -> void:
	var rules := _started(5)
	var state := rules.state
	for p in 2:
		state.players[p].current_mana = 10
		rules.submit(p, MatchIntents.play_card(_affordable(state, p), 0))
	# What each pool stands at when the round resolves. The batch has to be judged
	# against that, because the next turn refills both pools right afterwards.
	var owed: Array[int] = [state.players[0].current_mana, state.players[1].current_mana]

	var batch: Array = rules.submit(0, MatchIntents.end_turn())
	batch += rules.submit(1, MatchIntents.end_turn())

	# The window between RESOLVE opening and ROUND_START closing is the catch-up; the
	# refresh the next turn emits is a different (and public) event.
	var republished: Array = []
	var inside: bool = false
	for event: Variant in batch:
		var entry: Dictionary = event
		if entry.get("type", &"") == MatchEvents.PHASE_CHANGED:
			inside = int(entry["round_phase"]) == MatchState.RoundPhase.RESOLVE
			continue
		if inside and entry.get("type", &"") == MatchEvents.MANA_CHANGED:
			republished.append(entry)
	assert_eq(republished.size(), 2, "both players who played get a public catch-up")
	assert_eq(int((republished[0] as Dictionary)["player"]), 0)
	assert_eq(int((republished[0] as Dictionary)["current"]), owed[0], "with the pool they had")
	assert_false((republished[0] as Dictionary).has("private_to"), "and publicly")
	assert_eq(int((republished[1] as Dictionary)["player"]), 1)
	assert_eq(int((republished[1] as Dictionary)["current"]), owed[1])
	assert_eq(MatchEvents.redact_for(republished[0], 1), republished[0], "the opponent gets it too")


func test_the_republish_lands_after_the_phase_changed_to_resolve() -> void:
	var rules := _started(6)
	var state := rules.state
	rules.submit(0, MatchIntents.play_card(_affordable(state, 0), 0))
	var batch: Array = rules.submit(0, MatchIntents.end_turn())
	batch += rules.submit(1, MatchIntents.end_turn())
	var entered_resolve: int = -1
	var republished: int = -1
	for i in batch.size():
		var event: Dictionary = batch[i]
		if event.get("type", &"") == MatchEvents.PHASE_CHANGED \
				and int(event["round_phase"]) == MatchState.RoundPhase.RESOLVE:
			entered_resolve = i
		if event.get("type", &"") == MatchEvents.MANA_CHANGED and not event.has("private_to"):
			if republished < 0:
				republished = i
	assert_true(entered_resolve >= 0, "the round entered RESOLVE")
	assert_true(republished > entered_resolve,
		"the catch-up mana comes after, so a viewer is never asked to show a stale pool")


func test_a_round_with_no_plays_republishes_nothing() -> void:
	var rules := _started(7)
	var batch: Array = rules.submit(0, MatchIntents.end_turn())
	batch += rules.submit(1, MatchIntents.end_turn())
	for event: Variant in _all_of(batch, MatchEvents.MANA_CHANGED):
		assert_false((event as Dictionary).has("private_to"),
			"nothing was spent, so there is nothing to catch up on")


# ----------------------------
# A face-down card is nothing but a slot
# ----------------------------

func test_a_power_change_on_a_face_down_card_is_private() -> void:
	var state := MatchState.new()
	var card := state.new_card("Azir1", 0, CardState.Location.BOARD)
	state.place_card(card.instance_id, 0, 0)
	assert_false(card.is_resolved, "the card is on the board but still face-down")
	var log: Array = []
	_logged_ops(state, log).change_power(card.instance_id, 2)
	var changed := _one_of(log, MatchEvents.POWER_CHANGED)
	assert_eq(int(changed["private_to"]), 0, "its owner may watch it move")
	assert_eq(MatchEvents.redact_for(changed, 1), null, "the opponent may not")


func test_the_same_change_is_public_once_the_card_has_flipped() -> void:
	var state := MatchState.new()
	var card := state.new_card("Azir1", 0, CardState.Location.BOARD)
	state.place_card(card.instance_id, 0, 0)
	card.is_resolved = true
	var log: Array = []
	_logged_ops(state, log).change_power(card.instance_id, 2)
	var changed := _one_of(log, MatchEvents.POWER_CHANGED)
	assert_false(changed.has("private_to"), "a revealed card is public")
	assert_eq(MatchEvents.redact_for(changed, 1), changed, "so both sides see it")


func test_a_keyword_on_a_face_down_card_is_private_too() -> void:
	var state := MatchState.new()
	var card := state.new_card("Azir1", 1, CardState.Location.SPELL_ZONE)
	state.place_card(card.instance_id, MatchState.SPELL_COL, 1)
	var log: Array = []
	_logged_ops(state, log).add_keyword(card.instance_id, "Stun")
	var added := _one_of(log, MatchEvents.KEYWORD_ADDED)
	assert_eq(int(added["private_to"]), 1,
		"a card in the spell zone is face-down until it resolves")
	assert_eq(MatchEvents.redact_for(added, 0), null, "so the opponent learns nothing")


func test_emit_card_event_applies_the_hidden_card_rule_to_a_custom_event() -> void:
	# This is the door MatchAuras and any future module builds its own events through.
	var state := MatchState.new()
	var face_down := state.new_card("Azir1", 1, CardState.Location.BOARD)
	state.place_card(face_down.instance_id, 2, 1)
	var revealed := state.new_card("Azir1", 1, CardState.Location.BOARD)
	state.place_card(revealed.instance_id, 0, 1)
	revealed.is_resolved = true
	var log: Array = []
	var ops := _logged_ops(state, log)
	ops.emit_card_event(MatchEvents.power_changed(face_down.instance_id, 1, 3), face_down.instance_id)
	ops.emit_card_event(MatchEvents.power_changed(revealed.instance_id, 1, 3), revealed.instance_id)
	var changes := _all_of(log, MatchEvents.POWER_CHANGED)
	assert_eq(int((changes[0] as Dictionary)["private_to"]), 1,
		"the face-down card's change is its owner's alone")
	assert_false((changes[1] as Dictionary).has("private_to"), "the revealed one is public")


func test_the_snapshot_hides_a_face_down_card_completely() -> void:
	var rules := _started(3)
	var state := rules.state
	var id: int = _affordable(state, 0)
	rules.submit(0, MatchIntents.play_card(id, 0))

	var row := _board_row(MatchSnapshot.for_viewer(state, 1), id)
	assert_false(row.is_empty(), "the opponent's card is on the board, so it is listed")
	assert_eq(row["card_id"], null, "no identity")
	assert_eq(row["power"], null, "no power")
	assert_eq(row["cost"], null, "no cost")
	assert_eq(row["keywords"], null, "and no keywords either")


func test_the_snapshot_still_shows_your_own_face_down_card() -> void:
	var rules := _started(3)
	var state := rules.state
	var id: int = _affordable(state, 1)
	rules.submit(1, MatchIntents.play_card(id, 0))
	var card := state.card(id)
	var row := _board_row(MatchSnapshot.for_viewer(state, 1), id)
	assert_eq(row["card_id"], card.card_id, "your own card is yours")
	assert_eq(row["cost"], card.get_current_cost())
	assert_eq(row["keywords"], card.keywords())


# ----------------------------
# Rejections are the sender's business
# ----------------------------

func test_a_rules_refusal_is_private_to_its_sender() -> void:
	var rules := _started(13)
	var rejected := _one_of(rules.submit(1, MatchIntents.undo()), MatchEvents.INTENT_REJECTED)
	assert_false(rejected.is_empty(), "the undo was refused")
	assert_eq(str(rejected["reason"]), "nothing_to_undo")
	assert_eq(int(rejected["private_to"]), 1, "the refusal is private")
	assert_eq(MatchEvents.redact_for(rejected, 1), rejected, "the sender sees it")
	assert_eq(MatchEvents.redact_for(rejected, 0), null, "the opponent does not")


func test_every_kind_of_refusal_is_private() -> void:
	var rules := _started(14)
	var state := rules.state
	var foreign: int = int(state.players[0].hand[0])
	var cases: Array = [
		MatchIntents.play_card(foreign, 0),
		MatchIntents.undo(),
		MatchIntents.swap_card(foreign, 1),
		MatchIntents.swap_card(-5, 1),
		{"type": "teleport"},
	]
	for intent: Variant in cases:
		var rejected := _one_of(rules.submit(1, intent), MatchEvents.INTENT_REJECTED)
		assert_false(rejected.is_empty(), "%s is refused" % str(intent))
		assert_eq(int(rejected.get("private_to", -1)), 1, "%s carries private_to" % str(intent))
		assert_eq(MatchEvents.redact_for(rejected, 0), null,
			"%s never reaches the opponent" % str(intent))


func test_a_bad_player_id_is_refused_to_nobody_in_particular() -> void:
	var rules := _started(15)
	var rejected := _one_of(rules.submit(7, MatchIntents.undo()), MatchEvents.INTENT_REJECTED)
	assert_eq(str(rejected["reason"]), "bad_player")
	assert_eq(int(rejected["player"]), 7, "player 7 is not a player")
	assert_eq(MatchEvents.redact_for(rejected, 0), null, "so viewer 0 gets nothing")
	assert_eq(MatchEvents.redact_for(rejected, 1), null, "nor does viewer 1")


# ----------------------------
# Lanes stay unnamed until they are revealed
# ----------------------------

func test_lane_assigned_carries_no_lane_ids_to_anyone() -> void:
	var state := MatchState.new()
	var log: Array = []
	MatchLanes.new(state, _logged_ops(state, log)).assign([])
	var assigned := _one_of(log, MatchEvents.LANE_ASSIGNED)
	assert_false(assigned.is_empty(), "lanes are assigned")
	assert_eq(assigned.has("lane_ids"), true,
		"the engine knows which lane sits where — that is exactly what has to stop at redaction")
	assert_eq(MatchEvents.redact_for(assigned, 0), {"type": MatchEvents.LANE_ASSIGNED},
		"viewer 0 gets the bare event")
	assert_eq(MatchEvents.redact_for(assigned, 1), {"type": MatchEvents.LANE_ASSIGNED},
		"viewer 1 too")


func test_a_revealed_lane_is_still_named_publicly() -> void:
	var rules := MatchRules.new(MatchSetup.new_match(DECK_0, DECK_1, 16))
	rules.set_abilities(MatchAbilities.new())
	var revealed := _one_of(rules.start_match(["SunkenTemple", "SunkenTemple", "NoxkrayaArena"]),
		MatchEvents.LANE_REVEALED)
	assert_false(revealed.is_empty(), "column 0 opens the match")
	assert_eq(str(revealed["lane_id"]), "SunkenTemple")
	assert_eq(MatchEvents.redact_for(revealed, 1), revealed, "a revealed lane is public")


# ----------------------------
# The reveal carries the real numbers
# ----------------------------

func test_a_reveal_carries_the_final_power_cost_and_keywords() -> void:
	var rules := _started(17)
	var state := rules.state
	var id: int = _affordable(state, 0)
	rules.submit(0, MatchIntents.play_card(id, 0))
	rules.ops.change_power(id, 2)

	var batch: Array = rules.submit(0, MatchIntents.end_turn())
	batch += rules.submit(1, MatchIntents.end_turn())
	var revealed := _one_of(batch, MatchEvents.CARD_REVEALED)
	assert_eq(int(revealed["instance_id"]), id)
	assert_eq(int(revealed["power"]), state.card(id).get_current_power(), "the real power")
	assert_eq(int(revealed["cost"]), state.card(id).get_current_cost(), "the real cost")
	assert_eq(revealed["keywords"], state.card(id).keywords(), "the real keywords")


func test_a_summon_carries_the_final_numbers_too() -> void:
	var state := MatchState.new()
	var log: Array = []
	var id: int = _logged_ops(state, log).summon("Azir3", 0, 1)
	var card := state.card(id)
	var summoned := _one_of(log, MatchEvents.CARD_SUMMONED)
	assert_false(summoned.is_empty(), "the summon was published")
	assert_eq(int(summoned["instance_id"]), id)
	assert_eq(int(summoned["power"]), card.get_current_power(), "with the real power")
	assert_eq(int(summoned["cost"]), card.get_current_cost(), "and the real cost")
	assert_eq(summoned["keywords"], card.keywords(), "and the real keywords")
	assert_false(summoned.has("private_to"), "a summon lands face-up, so it is public")


# ----------------------------
# The snapshot's other masks
# ----------------------------

func test_the_opponent_pool_reads_as_its_turn_start_value_during_play() -> void:
	var rules := _started(18)
	var state := rules.state
	rules.submit(0, MatchIntents.play_card(_affordable(state, 0), 0))
	assert_true(state.players[0].current_mana < state.players[0].turn_start_mana,
		"the play really did spend something")

	var snapshot := MatchSnapshot.for_viewer(state, 1)
	assert_eq(int(snapshot["players"][0]["current_mana"]), state.players[0].turn_start_mana,
		"the opponent's pool is frozen at the turn-start value")
	assert_eq(int(snapshot["players"][1]["current_mana"]), state.players[1].current_mana,
		"yours is always the real one")


func test_the_mask_only_applies_during_play() -> void:
	var rules := _started(19)
	var state := rules.state
	state.players[0].current_mana = 1
	state.players[0].turn_start_mana = 3
	for round_phase: int in [MatchState.RoundPhase.ROUND_START, MatchState.RoundPhase.PLAY,
			MatchState.RoundPhase.SWAP_LANE, MatchState.RoundPhase.RESOLVE,
			MatchState.RoundPhase.ROUND_END]:
		state.round_phase = round_phase
		var shown := int(MatchSnapshot.for_viewer(state, 1)["players"][0]["current_mana"])
		if round_phase == MatchState.RoundPhase.PLAY:
			assert_eq(shown, 3, "during PLAY the opponent sees the turn-start value")
		else:
			assert_eq(shown, 1, "outside PLAY (phase %d) the number is the real one" % round_phase)


func test_the_turn_start_value_is_the_pool_at_the_opening_of_play() -> void:
	# The mask is only honest while the pool still equals what it was when PLAY opened,
	# which is what MatchRules records and what the public mana_changed announced.
	var rules := _started(20)
	for p in 2:
		var ps: PlayerState = rules.state.players[p]
		assert_eq(ps.turn_start_mana, ps.current_mana, "player %d opens PLAY full" % p)
		assert_eq(ps.turn_start_mana, ps.get_max_mana(), "and the maximum is public anyway")


func test_the_opponent_undo_count_is_never_shown() -> void:
	var rules := _started(21)
	var state := rules.state
	state.players[1].current_mana = 10
	rules.submit(1, MatchIntents.play_card(_affordable(state, 1), 0))
	assert_true(state.players[1].undo_stack.size() > 0, "they played something")

	var snapshot := MatchSnapshot.for_viewer(state, 0)
	assert_eq(int(snapshot["players"][1]["undo_count"]), 0,
		"their undo count would say how many cards they played")
	assert_eq(int(snapshot["players"][0]["undo_count"]), state.players[0].undo_stack.size(),
		"yours is the real one")


func test_the_snapshot_carries_the_noxkraya_column() -> void:
	var rules := _started(22)
	rules.state.noxkraya_col = 2
	assert_eq(int(MatchSnapshot.for_viewer(rules.state, 1)["noxkraya_col"]), 2,
		"the guest needs it to pick a legal column")
	rules.state.noxkraya_col = -1
	assert_eq(int(MatchSnapshot.for_viewer(rules.state, 1)["noxkraya_col"]), -1,
		"and -1 when no lane is restricted")


# ----------------------------
# Instance ids no longer map the deck
# ----------------------------

func test_the_default_flag_keeps_the_old_setup_exactly() -> void:
	var implicit := MatchSetup.new_match(DECK_0, DECK_1, 77)
	var explicit := MatchSetup.new_match(DECK_0, DECK_1, 77, false)
	assert_eq(explicit.checksum(), implicit.checksum(), "the default is the old behaviour")
	assert_eq(str(implicit.card(1).card_id), str(DECK_0[0]),
		"which is exactly the mapping the flag exists to break")


func test_scrambling_ids_permutes_them_without_touching_the_match_rng() -> void:
	var plain := MatchSetup.new_match(DECK_0, DECK_1, 4242)
	var scrambled := MatchSetup.new_match(DECK_0, DECK_1, 4242, true)
	assert_eq(scrambled.rng.state, plain.rng.state,
		"the match RNG has consumed exactly the same numbers either way")
	assert_eq(_sorted(scrambled, 0), _sorted(plain, 0), "player 0 still holds exactly their deck")
	assert_eq(_sorted(scrambled, 1), _sorted(plain, 1), "player 1 too")
	assert_eq(scrambled.cards.size(), plain.cards.size(), "the same number of cards exists")
	assert_ne(str(scrambled.card(1).card_id), str(DECK_0[0]),
		"but the first id is no longer the first card of the list")


func test_the_permutation_is_a_permutation_and_repeats_for_one_seed() -> void:
	var first := MatchSetup.new_match(DECK_0, DECK_1, 31, true)
	var again := MatchSetup.new_match(DECK_0, DECK_1, 31, true)
	var other := MatchSetup.new_match(DECK_0, DECK_1, 32, true)
	assert_eq(_all_ids(first), _all_ids(again), "the same seed gives the same permutation")
	assert_ne(_all_ids(first), _all_ids(other), "another seed gives another one")
	var unique: Dictionary = {}
	for id in _all_ids(first):
		assert_false(unique.has(id), "instance %d is handed out once" % id)
		unique[id] = true
	assert_eq(unique.size(), DECK_0.size() + DECK_1.size(), "and every card still exists")


func test_a_scrambled_match_still_plays_to_game_end() -> void:
	var rules := MatchRules.new(MatchSetup.new_match(DECK_0, DECK_1, 8, true))
	MatchCardAbilities.install(rules)
	rules.start_match()
	var bot := RandomNumberGenerator.new()
	bot.seed = 9
	var guard: int = 0
	while rules.state.game_phase == MatchState.GamePhase.TURN_LOOP and guard < 40:
		for p in [0, 1]:
			for intent: Variant in MatchBot.decide(rules.state, p, bot):
				rules.submit(p, intent)
		guard += 1
	assert_eq(rules.state.game_phase, MatchState.GamePhase.GAME_END, "and finishes")


# ----------------------------
# The sweep
# ----------------------------

func test_match_leak_check_finds_nothing_over_five_seeds_and_both_decks() -> void:
	for seed_value in SEEDS:
		for decks: Array in [[DECK_0, DECK_1], [DECK_1, DECK_0]]:
			_sweep(seed_value, decks[0], decks[1])


## Plays one whole match, feeding every batch — redacted per viewer, exactly as the host
## would send it — and every snapshot to a MatchLeakCheck for BOTH players. Any leak in
## any of them fails the test, naming the batch it came from.
func _sweep(seed_value: int, deck0: Array, deck1: Array) -> void:
	var where: String = "seed %d, deck %s" % [seed_value, str(deck0[0])]
	var state := MatchSetup.new_match(deck0, deck1, seed_value, true)
	var rules := MatchRules.new(state)
	MatchCardAbilities.install(rules)
	var checks: Array = [MatchLeakCheck.new(state, 0), MatchLeakCheck.new(state, 1)]

	rules.start_match()
	var bot := RandomNumberGenerator.new()
	bot.seed = seed_value + 1
	var guard: int = 0
	while state.game_phase == MatchState.GamePhase.TURN_LOOP and guard < 40:
		for player in [0, 1]:
			for intent: Variant in MatchBot.decide(state, player, bot):
				var batch := rules.submit(player, intent)
				for viewer in [0, 1]:
					var seen: Array = []
					for event: Variant in batch:
						var shown: Variant = MatchEvents.redact_for(event, viewer)
						if shown != null:
							seen.append(shown)
					_collect(checks[viewer].check_batch(seen), where, viewer, "batch")
					_collect(checks[viewer].check_snapshot(
						MatchSnapshot.for_viewer(state, viewer)), where, viewer, "snapshot")
		guard += 1
	assert_eq(state.game_phase, MatchState.GamePhase.GAME_END, "%s: the match finished" % where)
	for viewer in [0, 1]:
		assert_true(checks[viewer].is_clean(), "%s: viewer %d stayed clean" % [where, viewer])


## Fails once per issue, naming where it came from.
func _collect(found: Array, where: String, viewer: int, kind: String) -> void:
	for issue: String in found:
		fail("%s: viewer %d %s leak — %s" % [where, viewer, kind, issue])


# ----------------------------
# The checker itself has to be able to fail
# ----------------------------

func test_the_leak_check_stays_quiet_on_a_legitimate_reveal() -> void:
	var rules := _started(3)
	var state := rules.state
	var id: int = _affordable(state, 0)
	rules.submit(0, MatchIntents.play_card(id, 0))
	var check := MatchLeakCheck.new(state, 1)
	assert_eq(check.check_batch([
		MatchEvents.card_revealed(0, id, state.card(id).card_id, 0, 0,
			state.card(id).get_current_power(), state.card(id).get_current_cost(),
			state.card(id).keywords()),
	]), [], "the reveal is the moment the card turns face-up, so its payload is legitimate")


func test_the_leak_check_catches_an_opponent_play() -> void:
	var check := MatchLeakCheck.new(MatchState.new(), 1)
	var found := check.check_batch([MatchEvents.card_played(0, 4, "Azir1", 0, 0)])
	assert_true(found.size() > 0, "an opponent play must never reach the viewer")
	assert_true("\n".join(found).contains("card_played"), "and it says which event")


func test_the_leak_check_catches_an_opponent_mana_move_during_play() -> void:
	var rules := _started(23)
	var check := MatchLeakCheck.new(rules.state, 1)
	var quiet := check.check_batch([MatchEvents.mana_changed(1, 0, 1)])
	assert_eq(quiet, [], "your own pool is yours")
	# Reach PLAY in the stream, then spend the opponent's pool publicly.
	check.check_batch([MatchEvents.phase_changed(MatchState.GamePhase.TURN_LOOP,
		MatchState.RoundPhase.PLAY, 1)])
	assert_eq(check.check_batch([MatchEvents.mana_changed(0, 0, 2)]).size(), 1,
		"the opponent's pool must not move while they are choosing")


func test_the_leak_check_catches_a_leaked_hand_cost() -> void:
	var rules := _started(24)
	var state := rules.state
	var check := MatchLeakCheck.new(state, 1)
	var foreign: int = int(state.players[0].hand[0])
	var found := check.check_batch([MatchEvents.cost_changed(foreign, -1, 2)])
	assert_eq(found.size(), 1, "a cost change on an opponent hand card is a leak")
	assert_true(found[0].contains("instance %d" % foreign), "and it names the card")


func test_the_leak_check_catches_a_face_down_row_that_shows_a_cost() -> void:
	var rules := _started(25)
	var state := rules.state
	var id: int = _affordable(state, 0)
	rules.submit(0, MatchIntents.play_card(id, 0))
	var snapshot := MatchSnapshot.for_viewer(state, 1)
	assert_eq(MatchLeakCheck.new(state, 1).check_snapshot(snapshot), [], "the real snapshot is clean")

	var tampered := snapshot.duplicate(true)
	for row: Variant in tampered["board"]:
		if int((row as Dictionary)["instance_id"]) == id:
			(row as Dictionary)["cost"] = 3
	assert_eq(MatchLeakCheck.new(state, 1).check_snapshot(tampered).size(), 1,
		"a face-down row with a cost is a leak")


func test_the_leak_check_catches_an_opponent_hand_list() -> void:
	var rules := _started(26)
	var tampered := MatchSnapshot.for_viewer(rules.state, 1)
	(tampered["players"][0] as Dictionary)["hand"] = ["Azir1"]
	assert_eq(MatchLeakCheck.new(rules.state, 1).check_snapshot(tampered).size(), 1,
		"the opponent's hand must be a count")


func test_the_leak_check_catches_a_private_to_for_the_wrong_player() -> void:
	var rules := _started(27)
	var event := MatchEvents.card_drawn(1, 5, "Azir1")
	event["private_to"] = 0
	var found := MatchLeakCheck.new(rules.state, 1).check_batch([event])
	assert_true(found.size() > 0, "an event tagged for player 0 must not reach viewer 1")
	assert_true("\n".join(found).contains("private_to=0"), "and it says the tag was wrong")


# ----------------------------
# Helpers
# ----------------------------

## One player's deck as card ids, sorted — the deck CONTENT, independent of any order.
func _sorted(state: MatchState, player: int) -> Array:
	var out: Array = _deck_ids(state, player)
	out.sort()
	return out


## The card ids of one player's deck, in deck order.
func _deck_ids(state: MatchState, player: int) -> Array:
	var out: Array = []
	for id in state.players[player].deck:
		out.append(state.card(id).card_id)
	return out


## Every instance id of the match, deck 0 first.
func _all_ids(state: MatchState) -> Array:
	var out: Array = []
	for p in 2:
		out.append_array(state.players[p].deck)
	return out
