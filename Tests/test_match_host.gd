## MatchHost: the session layer that owns the engine, redacts per viewer and gates the
## opening of a turn.
##
## The engine itself is covered elsewhere; what matters here is everything the engine
## cannot see. Two peers have to be able to walk a match to its end over a redacted
## event stream and land on the same winner, a viewer must never be able to act into a
## turn that has not been announced to it, and a batch that is about to go over a socket
## has to survive the trip intact.
extends "res://Tests/test_case.gd"

const SEED := 4242

## What the host handed to the outside world, in order. `deliveries` keeps the two
## streams interleaved, which is the only way to see that a snapshot really did
## alternate with the batches it belongs to.
class Sink extends RefCounted:
	var batches: Array = []      # {viewer, events, seq}
	var snapshots: Array = []    # {viewer, snapshot} — the snapshot carries its own seq
	var deliveries: Array = []   # {kind: "events"|"snapshot", viewer, seq}, in order

	func on_events(viewer: int, events: Array, seq: int) -> void:
		batches.append({"viewer": viewer, "events": events, "seq": seq})
		deliveries.append({"kind": "events", "viewer": viewer, "seq": seq})

	func on_snapshot(viewer: int, snapshot: Dictionary) -> void:
		snapshots.append({"viewer": viewer, "snapshot": snapshot})
		deliveries.append({"kind": "snapshot", "viewer": viewer, "seq": int(snapshot.get("seq", -1))})

	## One viewer's deliveries as [["snapshot"|"events", seq], ...], in order.
	func timeline(viewer: int) -> Array:
		var out: Array = []
		for entry in deliveries:
			if int(entry["viewer"]) == viewer:
				out.append([str(entry["kind"]), int(entry["seq"])])
		return out

	## The newest snapshot one viewer was sent, or {}.
	func latest_snapshot(viewer: int) -> Dictionary:
		var found: Dictionary = {}
		for entry in snapshots:
			if int(entry["viewer"]) == viewer:
				found = entry["snapshot"]
		return found

	## The snapshots one viewer was sent, in order.
	func snapshots_for(viewer: int) -> Array:
		var out: Array = []
		for entry in snapshots:
			if int(entry["viewer"]) == viewer:
				out.append(entry["snapshot"])
		return out

	## The batches one viewer received, in order.
	func for_viewer(viewer: int) -> Array:
		var out: Array = []
		for entry in batches:
			if int(entry["viewer"]) == viewer:
				out.append(entry)
		return out

	## The seq numbers one viewer saw, in order.
	func seqs(viewer: int) -> Array:
		var out: Array = []
		for entry in for_viewer(viewer):
			out.append(int(entry["seq"]))
		return out

	## Every event one viewer received, flattened in delivery order.
	func events_for(viewer: int) -> Array:
		var out: Array = []
		for entry in for_viewer(viewer):
			out.append_array(entry["events"])
		return out

	## The turns of the batches that carry exactly one play_opened and nothing else.
	func play_opened_batches(viewer: int) -> Array:
		var out: Array = []
		for entry in for_viewer(viewer):
			var events: Array = entry["events"]
			if events.size() == 1 and events[0].get("type", &"") == MatchEvents.PLAY_OPENED:
				out.append(int(events[0]["turn"]))
		return out


## A host wired to `sink`, with the given ack requirement and snapshot viewers.
func _host(sink: Sink, acks: Array = [0, 1], viewers: Array = [1]) -> MatchHost:
	var host := MatchHost.new(sink.on_events, sink.on_snapshot)
	host.acks_required.assign(acks)
	host.snapshot_viewers.assign(viewers)
	return host


## A started LAN host with the real decks.
func _lan_host(sink: Sink) -> MatchHost:
	var host := _host(sink)
	host.start(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED)
	return host


## The first hand card `player` could actually play into a lane right now, or -1.
## hand[0] is no use for that: it may be a spell, or too expensive on turn 1.
func _playable(state: MatchState, player: int) -> int:
	for raw in state.players[player].hand:
		var card := state.card(int(raw))
		if card.get_current_cost() > state.players[player].current_mana:
			continue
		if str(card.data().get("Type", "")) == "Spell":
			continue
		if state.noxkraya_col >= 0 and state.noxkraya_col != 0:
			continue
		return int(raw)
	return -1


## Opens the turn the way a well-behaved peer pair does: every required ack, in order.
func _ack_all(host: MatchHost) -> void:
	while host.pending_turn() != -1:
		for player in host.acks_required:
			host.presentation_done(player, host.pending_turn())


## Drives a host to the end of the match with both peers acking, and returns the winner.
func _play_out(host: MatchHost) -> int:
	var guard: int = 0
	while not host.is_over() and guard < 200:
		guard += 1
		if host.pending_turn() != -1:
			_ack_all(host)
			continue
		for player in [0, 1]:
			var intent := MatchIntents.end_turn()
			host.submit(player, intent)
	return host.winner()


func _first_hand_card(state: MatchState, player: int) -> int:
	return int(state.players[player].hand[0])


func _rejections(events: Array) -> Array:
	var out: Array = []
	for event: Variant in events:
		if event.get("type", &"") == MatchEvents.INTENT_REJECTED:
			out.append(event)
	return out


# ----------------------------
# Delivery
# ----------------------------

func test_the_opening_snapshot_precedes_the_first_batch_and_is_seq_zero() -> void:
	var sink := Sink.new()
	var host := _host(sink, [0, 1], [0, 1])
	host.start(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED)
	assert_eq(sink.deliveries.size() > 2, true, "the match produced deliveries")
	for viewer in [0, 1]:
		var first: Dictionary = sink.snapshots_for(viewer)[0]
		assert_eq(int(first["seq"]), 0, "nothing has been delivered yet, so the opening is seq 0")
		assert_eq(int(first["local"]), viewer, "and it is that viewer's")
	# The very first thing the host did was push a snapshot, to each viewer in turn.
	assert_eq(str(sink.deliveries[0]["kind"]), "snapshot", "viewer 0 opened on a snapshot")
	assert_eq(int(sink.deliveries[0]["viewer"]), 0)
	assert_eq(str(sink.deliveries[1]["kind"]), "snapshot", "and so did viewer 1")
	assert_eq(int(sink.deliveries[1]["viewer"]), 1)
	assert_eq(str(sink.deliveries[2]["kind"]), "events", "only then came the first batch")
	assert_eq(int(sink.deliveries[2]["seq"]), 0, "numbered 0, like the snapshot it followed")


func test_a_viewer_outside_snapshot_viewers_never_gets_a_snapshot() -> void:
	var sink := Sink.new()
	var host := _host(sink, [0, 1], [])
	host.start(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED)
	assert_eq(sink.snapshots, [], "no snapshot viewer, no snapshot")
	assert_true(sink.batches.size() > 0, "but the events still flow")
	for step in sink.timeline(0):
		assert_eq(str(step[0]), "events", "viewer 0 only ever gets batches")


func test_a_snapshot_viewer_alternates_snapshot_and_batch_all_match() -> void:
	# The guest has no MatchState, so the only picture it can check itself against is
	# the one the host pushes. Strict alternation is what makes it trustworthy: a
	# snapshot always describes exactly the batches that came before it.
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	for _round in 4:
		host.submit(0, MatchIntents.end_turn())
		host.submit(1, MatchIntents.end_turn())
		_ack_all(host)

	var timeline: Array = sink.timeline(1)
	assert_true(timeline.size() > 10, "the match produced plenty of deliveries")
	assert_eq(str(timeline[0][0]), "snapshot", "it opens on a snapshot")
	for i in timeline.size():
		var step: Array = timeline[i]
		if i % 2 == 0:
			assert_eq(str(step[0]), "snapshot", "delivery %d is a snapshot" % i)
			assert_eq(int(step[1]), i / 2, "and it is numbered by the batches so far")
		else:
			assert_eq(str(step[0]), "events", "delivery %d is a batch" % i)
			assert_eq(int(step[1]), (i - 1) / 2, "and it carries the same number")
	# The timeline is the opening snapshot followed by one (batch, snapshot) pair per
	# batch, so it is always one entry longer than the batch count.
	assert_eq(sink.snapshots_for(1).size(), sink.for_viewer(1).size() + 1,
		"a snapshot after every batch, plus the opening one")
	assert_eq(sink.for_viewer(1).size(), (timeline.size() - 1) / 2, "and no batch without one")


func test_every_delivered_snapshot_is_the_state_of_that_moment() -> void:
	# The host is synchronous and does nothing else after a call returns, so the newest
	# snapshot a viewer holds must equal snapshot_for() right now, plus its seq.
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	var bots: Array = [_bot_rng(0), _bot_rng(1)]
	for _round in 3:
		for player in [0, 1]:
			for intent: Variant in MatchBot.decide(host.state, player, bots[player]):
				host.submit(player, intent)
		_check_latest_snapshot(sink, host, 1, "a bot round")
		_ack_all(host)
		_check_latest_snapshot(sink, host, 1, "a play_opened release")


func test_snapshot_for_carries_no_seq() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	for viewer in [0, 1]:
		assert_false(host.snapshot_for(viewer).has("seq"),
			"the local picture has no seq — only a delivered copy is tagged")


func _check_latest_snapshot(sink: Sink, host: MatchHost, viewer: int, where: String) -> void:
	var delivered: Dictionary = sink.latest_snapshot(viewer)
	assert_false(delivered.is_empty(), "%s: a snapshot was delivered" % where)
	assert_eq(int(delivered.get("seq", -1)), sink.for_viewer(viewer).size(),
		"%s: its seq counts the batches that viewer has received" % where)
	var expected := host.snapshot_for(viewer)
	var stripped := delivered.duplicate(true)
	stripped.erase("seq")
	assert_eq(stripped, expected, "%s: and it is the state of that moment" % where)


func test_every_viewer_receives_the_raw_batch_redacted_for_them() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	sink.batches.clear()

	var played: int = _playable(host.state, 0)
	assert_true(played > 0, "player 0 has a card it can play on turn 1")
	assert_true(host.submit(0, MatchIntents.play_card(played, 0)), "the play was accepted")

	for viewer in [0, 1]:
		for entry in sink.for_viewer(viewer):
			for event: Variant in entry["events"]:
				assert_false(event.has("lane_ids"), "viewer %d never sees lane ids" % viewer)
	var saw_own_play: bool = false
	for event: Variant in sink.events_for(0):
		if event.get("type", &"") == MatchEvents.CARD_PLAYED:
			saw_own_play = true
	assert_true(saw_own_play, "the owner still sees their own play")
	var saw_theirs: bool = false
	for event: Variant in sink.events_for(1):
		if event.get("type", &"") == MatchEvents.CARD_PLAYED:
			saw_theirs = true
	assert_false(saw_theirs, "the opponent never sees a card_played")


func test_seq_starts_at_zero_and_never_skips_a_number() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	for _round in 4:
		host.submit(0, MatchIntents.end_turn())
		host.submit(1, MatchIntents.end_turn())
		_ack_all(host)
	for viewer in [0, 1]:
		var seqs: Array = sink.seqs(viewer)
		assert_true(seqs.size() > 1, "viewer %d got several batches" % viewer)
		assert_eq(int(seqs[0]), 0, "viewer %d starts at 0" % viewer)
		for i in seqs.size():
			assert_eq(int(seqs[i]), i, "viewer %d batch %d is numbered in order" % [viewer, i])


func test_a_batch_that_redacts_to_nothing_is_not_delivered() -> void:
	# An opponent's play is redacted away for the other side entirely. That must not
	# spend a seq number, or the guest would read a gap where nothing was lost.
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	var before: Array = sink.seqs(1)
	host.submit(0, MatchIntents.undo())
	assert_eq(sink.seqs(1), before,
		"a refusal the guest may not see leaves its seq stream untouched")


func test_snapshot_for_is_the_same_picture_the_snapshot_carries() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	for viewer in [0, 1]:
		assert_eq(host.snapshot_for(viewer), MatchSnapshot.for_viewer(host.state, viewer),
			"viewer %d" % viewer)
		assert_eq(int(host.snapshot_for(viewer)["local"]), viewer, "and it is addressed to them")


func test_every_delivered_batch_survives_a_var_to_bytes_round_trip() -> void:
	# What goes over the wire is var_to_bytes()/bytes_to_var(), NOT JSON: an int stays an
	# int and a StringName stays a StringName, which redaction depends on.
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	var bots: Array = [_bot_rng(0), _bot_rng(1)]
	for _round in 3:
		for player in [0, 1]:
			for intent: Variant in MatchBot.decide(host.state, player, bots[player]):
				host.submit(player, intent)
		_ack_all(host)
	var checked: int = 0
	for entry in sink.batches:
		var events: Array = entry["events"]
		var restored: Variant = bytes_to_var(var_to_bytes(events))
		assert_true(restored is Array, "a batch comes back as an Array")
		assert_eq(restored, events, "byte for byte")
		for event: Variant in events:
			assert_true(event["type"] is StringName, "the event type survives as a StringName")
			if event.has("private_to"):
				assert_true(int(event["private_to"]) == 0 or int(event["private_to"]) == 1,
					"and a private tag stays a whole player id")
		checked += 1
	assert_true(checked > 4, "the run really produced batches to check")


# ----------------------------
# The play_opened gate
# ----------------------------

func test_offline_opens_the_first_turn_in_the_opening_batch() -> void:
	var sink := Sink.new()
	var host := _host(sink, [])
	host.start(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED)
	assert_eq(host.pending_turn(), -1, "nobody to wait for, so nothing is pending")
	for viewer in [0, 1]:
		assert_eq(sink.play_opened_batches(viewer), [], "no batch of its own")
		assert_eq(sink.events_for(viewer).size() > 5, true, "the opening arrives as one batch")
	var opened: int = 0
	for entry in sink.batches:
		if entry["events"].size() > 1 and entry["events"][-1].get("type", &"") == MatchEvents.PLAY_OPENED:
			opened += 1
	assert_eq(opened, 2, "each viewer's batch ends with play_opened(1)")


func test_the_first_turn_is_gated_like_every_other_one() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	assert_eq(host.pending_turn(), 1, "turn 1 waits for both peers, exactly like turn 2")
	assert_eq(sink.play_opened_batches(0), [], "and nobody has been told yet")


func test_the_turn_opens_only_once_every_required_player_acked() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	host.presentation_done(0, 1)
	assert_eq(host.pending_turn(), 1, "one ack is not enough")
	assert_eq(sink.play_opened_batches(0), [], "still nothing")
	host.presentation_done(1, 1)
	assert_eq(host.pending_turn(), -1, "the second ack releases it")
	for viewer in [0, 1]:
		assert_eq(sink.play_opened_batches(viewer), [1], "viewer %d was told, once" % viewer)


func test_a_repeated_or_stale_ack_cannot_open_a_turn_twice() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	host.presentation_done(0, 1)
	host.presentation_done(0, 1)          # the same peer, twice
	host.presentation_done(1, 99)         # a turn nobody is waiting for
	host.presentation_done(1, -1)         # nonsense
	assert_eq(host.pending_turn(), 1, "none of those counted")
	assert_eq(sink.play_opened_batches(0), [], "and the turn is still closed")
	host.presentation_done(1, 1)
	assert_eq(sink.play_opened_batches(0), [1], "the real ack opens it")
	host.presentation_done(0, 1)          # late arrivals for a turn that is already open
	host.presentation_done(1, 1)
	assert_eq(sink.play_opened_batches(0), [1], "still exactly one play_opened")
	assert_eq(host.pending_turn(), -1, "and nothing new is pending")


func test_ack_timeout_opens_the_turn_and_a_late_timer_does_not() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	assert_false(host.ack_timeout(99), "a timer for a turn nobody waits for does nothing")
	assert_true(host.ack_timeout(1), "the real one opens the turn")
	assert_eq(host.pending_turn(), -1, "which is now open")
	assert_eq(sink.play_opened_batches(0), [1], "and was announced")
	assert_false(host.ack_timeout(1), "a late timer for the same turn is ignored")
	assert_eq(sink.play_opened_batches(0), [1], "so the turn is not opened twice")


func test_a_second_turn_waits_for_the_acks_again() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	host.submit(0, MatchIntents.end_turn())
	host.submit(1, MatchIntents.end_turn())
	assert_eq(host.pending_turn(), 2, "turn 2 goes through the same gate")
	assert_eq(sink.play_opened_batches(0), [1], "only turn 1 has been announced so far")
	_ack_all(host)
	assert_eq(sink.play_opened_batches(0), [1, 2], "and now turn 2 as well")


func test_the_offline_flow_never_pends() -> void:
	var sink := Sink.new()
	var host := _host(sink, [])
	host.start(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED)
	for _round in 3:
		assert_eq(host.pending_turn(), -1, "offline waits for nobody")
		host.submit(0, MatchIntents.end_turn())
		host.submit(1, MatchIntents.end_turn())
	assert_eq(host.pending_turn(), -1, "still nobody")


# ----------------------------
# submit()
# ----------------------------

func test_submit_is_refused_until_the_turn_has_been_announced() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	assert_false(host.submit(1, MatchIntents.end_turn()),
		"a peer may not act into a turn it has not been told about")
	assert_eq(host.state.round_phase, MatchState.RoundPhase.PLAY, "and nothing changed")
	assert_false(host.state.players[1].ended_turn, "the intent did not take effect")
	_ack_all(host)
	assert_true(host.submit(1, MatchIntents.end_turn()), "once it is open, the same intent works")


func test_a_not_ready_refusal_reaches_the_sender_alone() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	host.submit(1, MatchIntents.end_turn())

	var mine: Array = _rejections(sink.events_for(1))
	assert_eq(mine.size(), 1, "the sender is told once")
	assert_eq(str(mine[0]["reason"]), "not_ready")
	assert_eq(int(mine[0]["player"]), 1)
	assert_eq(int(mine[0]["private_to"]), 1, "and it is private to them")
	assert_eq(int(mine[0]["instance_id"]), -1, "end_turn names no card")
	assert_eq(_rejections(sink.events_for(0)), [], "the opponent is told nothing at all")


func test_a_not_ready_refusal_names_the_card_the_intent_was_about() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	var card: int = _first_hand_card(host.state, 1)
	host.submit(1, MatchIntents.play_card(card, 0))
	var mine: Array = _rejections(sink.events_for(1))
	assert_eq(mine.size(), 1)
	assert_eq(str(mine[0]["intent_type"]), str(MatchIntents.PLAY_CARD))
	assert_eq(int(mine[0]["instance_id"]), card, "so the card can go back where it came from")


func test_a_rules_refusal_is_also_false_and_still_private() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	assert_false(host.submit(0, MatchIntents.undo()), "there is nothing to undo on turn 1")
	var mine: Array = _rejections(sink.events_for(0))
	assert_eq(mine.size(), 1, "the sender is told why")
	assert_eq(str(mine[0]["reason"]), "nothing_to_undo")
	assert_eq(int(mine[0]["private_to"]), 0, "and it stays private")
	assert_eq(_rejections(sink.events_for(1)), [], "the opponent learns nothing about it")


func test_an_accepted_intent_returns_true() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	_ack_all(host)
	assert_true(host.submit(0, MatchIntents.end_turn()), "the first end turn is accepted")
	assert_true(host.state.players[0].ended_turn, "and it took effect")


func test_intents_after_game_end_are_refused() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	var winner: int = _play_out(host)
	assert_true(host.is_over(), "the match finished")
	assert_true(winner == 0 or winner == 1 or winner == -1, "and reports a winner")
	assert_eq(host.winner(), winner, "winner() is stable")
	var before: int = sink.batches.size()
	assert_false(host.submit(0, MatchIntents.end_turn()), "a finished match takes no more intents")
	assert_eq(sink.batches.size(), before + 1, "the sender is still told, once")
	assert_eq(_rejections(sink.events_for(1)).size(), 0, "and the opponent still is not")


func test_winner_is_minus_one_while_the_match_runs() -> void:
	var sink := Sink.new()
	var host := _lan_host(sink)
	assert_eq(host.winner(), -1, "nothing has been decided yet")
	assert_false(host.is_over())


# ----------------------------
# check_hello
# ----------------------------

func test_check_hello_accepts_a_matching_protocol_and_a_real_deck() -> void:
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	var answer := MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION,
		"deck": deck, "want_snapshots": true})
	assert_true(answer["ok"], "a well formed hello is accepted")
	assert_eq(str(answer["reason"]), "", "with no reason")
	assert_eq(answer["deck"], deck, "and the deck it sent")
	assert_true(answer["want_snapshots"], "snapshots are echoed back")


func test_check_hello_refuses_another_build() -> void:
	for bad: Variant in [0, 2, -1, "1", 1.5, null]:
		var answer := MatchHost.check_hello({"protocol": bad, "deck": MatchDecks.DEFAULT_DECK_IDS})
		assert_false(answer["ok"], "protocol %s is refused" % str(bad))
		assert_eq(str(answer["reason"]), "bad_protocol")
	assert_false(MatchHost.check_hello({})["ok"], "a hello with no protocol at all is refused")


func test_check_hello_refuses_a_deck_that_is_not_a_list() -> void:
	for bad: Variant in [{"a": 1}, "Azir1", 7, true]:
		var answer := MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION, "deck": bad})
		assert_false(answer["ok"], "deck %s is refused" % str(bad))
		assert_eq(str(answer["reason"]), "bad_deck")
		assert_eq(int((answer["deck"] as Array).size()), MatchDecks.DECK_SIZE,
			"and the answer still carries a usable deck")


func test_check_hello_substitutes_the_default_for_a_missing_or_bad_deck() -> void:
	var missing := MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION})
	assert_true(missing["ok"], "no deck is not a refusal, it is the default deck")
	assert_eq(missing["deck"], MatchDecks.DEFAULT_DECK_IDS)
	var short := MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION, "deck": ["Azir1"]})
	assert_true(short["ok"], "a deck that is not a legal one falls back, like a saved deck")
	assert_eq(short["deck"], MatchDecks.DEFAULT_DECK_IDS)


func test_check_hello_only_echoes_a_real_bool_for_want_snapshots() -> void:
	for value: Variant in [true, false]:
		assert_eq(bool(MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION,
			"want_snapshots": value})["want_snapshots"]), value)
	for hostile: Variant in [1, 0, "yes", null, []]:
		assert_false(MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION,
			"want_snapshots": hostile})["want_snapshots"],
			"a hostile %s cannot force snapshots" % str(hostile))


func test_check_hello_never_hands_the_seed_or_the_host_deck_back() -> void:
	var answer := MatchHost.check_hello({"protocol": MatchHost.PROTOCOL_VERSION,
		"deck": MatchDecks.DEFAULT_DECK_IDS, "seed": SEED, "host_deck": ["Chip"]})
	assert_true(answer["ok"], "extra keys are ignored, not honoured")
	assert_false(answer.has("seed"), "and no seed comes back")
	assert_false(answer.has("host_deck"), "nor the host's own deck")


# ----------------------------
# Two peers, one match
# ----------------------------

func test_two_simulated_peers_play_to_the_same_winner_as_the_engine() -> void:
	# The host decides player 0 from the state; the guest decides player 1 from the
	# snapshots that were DELIVERED to it — it never touches host.state, never calls
	# snapshot_for(), and holds no MatchState at all. Both go through submit() and wait
	# for the acks. The result must match a plain engine run in which both sides are the
	# same bot: that is the whole no-leak, no-desync claim.
	var via_host := _two_peers()
	var direct := _direct_run()
	assert_eq(via_host["winner"], direct["winner"], "same winner")
	assert_true(via_host["winner"] == 0 or via_host["winner"] == 1, "and there was a winner")
	assert_eq(via_host["turn"], direct["turn"], "the same number of turns")
	assert_eq(via_host["checksum"], direct["checksum"], "and byte-identical final state")
	assert_true(int(via_host["guest_snapshots"]) > 5, "the guest really autoplayed from snapshots")
	assert_eq(via_host["guest_seq"], via_host["guest_batches_at_use"],
		"the snapshot it decided from was current: its seq matched the batches it had")


## Plays the match through the host: player 0 with decide(), player 1 with
## decide_from_snapshot() on the guest's newest DELIVERED snapshot.
## Returns {winner, turn, checksum, guest_snapshots, guest_batches, guest_seq,
## guest_batches_at_use}.
func _two_peers() -> Dictionary:
	var sink := Sink.new()
	var host := MatchHost.new(sink.on_events, sink.on_snapshot)
	host.acks_required = [0, 1]
	host.snapshot_viewers = [1]
	host.start(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED, true)
	var rngs: Array = [_bot_rng(0), _bot_rng(1)]
	var guard: int = 0
	var seen_at_use: Array = [-1, -1]
	while not host.is_over() and guard < 200:
		guard += 1
		if host.pending_turn() != -1:
			_ack_all(host)
			continue
		if host.state.round_phase != MatchState.RoundPhase.PLAY:
			break
		for intent: Variant in MatchBot.decide(host.state, 0, rngs[0]):
			host.submit(0, intent)
		# What the guest has: the newest snapshot the host pushed to it. Nothing else.
		var guest_view: Dictionary = sink.latest_snapshot(1)
		seen_at_use[0] = int(guest_view.get("seq", -1))
		seen_at_use[1] = sink.for_viewer(1).size()
		for intent: Variant in MatchBot.decide_from_snapshot(guest_view, rngs[1]):
			host.submit(1, intent)
	_ack_all(host)
	return {
		"winner": host.winner(),
		"turn": host.state.turn,
		"checksum": host.state.checksum(),
		"guest_snapshots": sink.snapshots_for(1).size(),
		"guest_batches": sink.for_viewer(1).size(),
		"guest_seq": seen_at_use[0],
		"guest_batches_at_use": seen_at_use[1],
	}


## The same match with no session layer at all: both players are MatchBot.decide().
func _direct_run() -> Dictionary:
	var state := MatchSetup.new_match(MatchDecks.DEFAULT_DECK_IDS, MatchDecks.BOT_DECK_IDS, SEED, true)
	var rules := MatchRules.new(state)
	MatchCardAbilities.install(rules)
	var log: Array = rules.start_match()
	# One generator per peer, held for the whole match, exactly as the session run does.
	var rngs: Array = [_bot_rng(0), _bot_rng(1)]
	var guard: int = 0
	while state.game_phase == MatchState.GamePhase.TURN_LOOP and guard < 200:
		guard += 1
		for player in [0, 1]:
			for intent: Variant in MatchBot.decide(state, player, rngs[player]):
				log += rules.submit(player, intent)
	var winner: int = -1
	for event: Variant in log:
		if event.get("type", &"") == MatchEvents.GAME_ENDED:
			winner = int(event["winner"])
	return {"winner": winner, "turn": state.turn, "checksum": state.checksum()}


## A generator per peer, seeded apart so a divergence names the side that drifted.
func _bot_rng(player: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1 if player == 0 else SEED + 2
	return rng
