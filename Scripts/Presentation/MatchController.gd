## The match driver: the host-authoritative session layer plus the presenter that shows it.
##
## This is the ONLY place a match runs. It owns no rules of its own — every decision is
## an intent handed to MatchHost and every answer is an event batch handed to the
## presenter — and it is the only class that knows which of the four modes it is in:
##
##   OFFLINE  local 1 (human), MatchHost with acks_required = [] and MatchBot as the
##            opponent. play_opened rides in the batch that opened the turn, so no ack
##            is ever sent. The bot is viewer 0 and has no view; it reads host.state.
##   HOST     local 0, owns MatchHost with acks_required = [0, 1]. Its own batches go
##            to its presenter, the guest's go to MatchNet, and every guest batch is
##            run past MatchLeakCheck before it leaves the machine.
##   GUEST    local 1, NO MatchState and NO MatchRules. It sends intents and acks and
##            animates what arrives; every question about what it may do is answered
##            from the PRESENTER's view model.
##
## Player ids are ABSOLUTE in the engine (0 = host, 1 = guest) and local_player follows
## from the mode. They are never screen rows: the presenter owns that mapping, so a host
## renders its own cards on the bottom row exactly as an offline human does.
##
## The presenter is typed as a plain Node and called dynamically: it lives in
## /root/Main/MatchPresenter, and this class must keep loading even before that file
## exists. MatchController.active() is the one test every old script asks before it
## takes an engine-mode branch.
class_name MatchController extends Node

## Which session this controller drives. Player ids are ABSOLUTE: 0 = host, 1 = guest,
## and local_player below follows from the mode (offline keeps the human at 1 and the
## bot at 0, as it always has).
enum Mode {NONE, OFFLINE, HOST, GUEST}

## The presenter finished its queue: the view is up to date with the engine.
signal view_idle
## The match is over. `winner` is -1 for a tie.
signal match_ended(winner: int)

## Bounds the bot loop: a match is 6 turns and the bot plays at most one card per turn,
## so a healthy run needs a handful of iterations. This only catches a broken engine.
const BOT_MAX_STEPS := 512

## The seed of the match in progress (-1 until start_offline, then the real seed).
var match_seed: int = -1

## How long a peer may take to acknowledge a turn before the session opens it anyway.
## Long enough for the longest animation in a resolve (a level-up spin is ~5 s) with
## room to spare, short enough that a peer which died mid-batch does not freeze the
## match. Driven from a SceneTreeTimer that ignores time scale (see _arm_ack_timeout).
const ACK_TIMEOUT := 10.0

## The session this controller drives: NONE until start_offline / start_host /
## start_guest sets it. Everything mode-dependent keys off this — which viewer events
## are redacted for, whether the local player may submit, and whether this controller
## owns a MatchState at all (the guest does not).
var mode: Mode = Mode.NONE

var rules: MatchRules
var state: MatchState
## Absolute player id of this peer: 1 offline (the human, unchanged), 0 as host, 1 as
## guest. The engine is absolute; the board is not, and the presenter maps one to the
## other, so this is never used as a screen row.
var local_player: int = 1
var presenter: Node  # /root/Main/MatchPresenter

## The session layer. Null on a GUEST (it owns no engine) and set in OFFLINE and HOST.
## Everything that touches state or rules goes through it, so there is exactly one
## path into MatchRules in every mode — offline included.
var host: MatchHost = null
## The MatchNet transport on HOST and GUEST, null offline. Typed as a plain Node and
## called dynamically: this file must keep loading before MatchNet does.
var net: Node = null
## The most recent snapshot this peer received from the host, kept so --verify-view on
## a GUEST has something authoritative to compare its view against (it has no state).
var _latest_snapshot: Dictionary = {}
## How many event batches this peer has taken. MatchHost tags every snapshot it sends
## with the batch count that viewer had received, so this is what a guest compares a
## snapshot's "seq" against before trusting it as a --verify-view reference.
var _latest_seq: int = 0
## True once end_session() ran. Latches the session shut so a late batch cannot reopen
## input and the overlay is not torn down by a second call.
var _session_ended: bool = false
## The turn this peer has already acked, so a presenter that goes idle several times
## for one turn sends presentation_done once. -1 means "nothing acked yet".
var _acked_turn: int = -1
## True once the guest's view has been built from its first snapshot. setup() rebuilds a
## whole view from scratch, so it must run exactly once; later snapshots are kept as the
## --verify-view reference and nothing more.
var _view_built: bool = false
## The hidden-information auditor, watching the GUEST's stream against the live engine
## state. It is stream-based — it learns which opponent instances have legitimately
## been revealed — so it is built once per session and outlives every batch.
var _leak_check: MatchLeakCheck = null
## Guest deliveries that arrived before the leak checker existed, in delivery order,
## replayed once _start_leak_check() runs. Only the CHECK waits; the guest still
## received every one of these the moment they were produced.
var _leak_pending: Array = []

## The bot's own randomness, kept apart from the match RNG so the engine's replay is
## untouched. Both are seeded from the match seed, so a --seed run replays exactly.
var bot_rng := RandomNumberGenerator.new()
var human_rng := RandomNumberGenerator.new()

var _started: bool = false
var _bot_running: bool = false
var _dev_seed: int = -1
var _dev_autoplay: bool = false
var _dev_verify_view: bool = false
## A pending ack timeout, so a second one cannot be armed for the same turn.
var _ack_timeout_turn: int = -1


func _ready() -> void:
	_parse_dev_args()


# ----------------------------
# Lifetime
# ----------------------------

## True when an offline match is running on the new engine: a MatchController under
## /root/Main exists and has started. Every old script asks this before taking an
## engine-mode branch, so the old paths stay byte-for-byte unchanged when it is false.
static func active() -> bool:
	var controller := _find_singleton()
	return controller != null and controller._started


## The MatchController under /root/Main, or null when there is none.
static func _find_singleton() -> MatchController:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var main := (loop as SceneTree).root.get_node_or_null(^"Main")
	if main == null:
		return null
	return main.get_node_or_null(^"MatchController") as MatchController


## True once start_offline() has built the engine and the presenter is showing it.
func is_started() -> bool:
	return _started


## Builds the match and shows it. `bot_deck` is player 0's card ids, `human_deck`
## player 1's. A seed below 0 means "pick one": --seed=N when it was passed on the
## command line, otherwise a random one, so a run without --seed is not repeatable.
##
## Offline runs through MatchHost exactly like a LAN host does, with acks_required
## empty: there is nobody to wait for, so play_opened rides in the same batch that
## opened the turn and no ack is ever sent. That is deliberate — it means the offline
## path exercises the same session layer, the same per-viewer redaction and the same
## play_opened gate as LAN, instead of a second, simpler code path that could drift.
## The bot is the one viewer with no presenter: it reads host.state directly.
func start_offline(human_deck: Array, bot_deck: Array, seed: int = -1) -> void:
	mode = Mode.OFFLINE
	local_player = 1
	var chosen: int = seed
	if chosen < 0:
		chosen = _dev_seed
	if chosen < 0:
		chosen = randi()
	match_seed = chosen
	bot_rng.seed = chosen + 101
	human_rng.seed = chosen + 202
	_started = true
	_session_ended = false

	if presenter == null:
		presenter = _find_presenter()
	if presenter != null:
		_connect_presenter()

	host = MatchHost.new(_deliver_events, _deliver_snapshot)
	host.acks_required = []
	# Only the human has a view; the bot's batch is delivered and dropped.
	host.snapshot_viewers = [local_player]
	host.start(bot_deck, human_deck, chosen)
	_sync_engine_refs()
	_run_bot()


## Mirrors MatchHost's state and rules into this controller's own fields. MatchHost owns
## them, but state/rules are part of this class's existing public surface (LobbyUI's
## --quit-on-end reads controller.state), and the offline bot loop reads them directly.
func _sync_engine_refs() -> void:
	if host == null:
		state = null
		rules = null
		return
	state = host.state
	rules = host.rules


## The presenter node under /root/Main, or null when it has not been created yet.
static func _find_presenter() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var main := (loop as SceneTree).root.get_node_or_null(^"Main")
	if main == null:
		return null
	return main.get_node_or_null(^"MatchPresenter")


# ----------------------------
# Intents
# ----------------------------

## Submits one intent from the local player. Returns false when the session refused it,
## so the caller can tell a rejected drag from an accepted one.
##
## A GUEST has no engine: it hands the intent to MatchNet and returns true optimistically
## — the answer comes back later as an event batch, and a refusal arrives as an
## intent_rejected the presenter turns into a toast. OFFLINE and HOST both go through
## MatchHost, which returns true only when the engine accepted the intent.
func submit_local(intent: Dictionary) -> bool:
	if mode == Mode.GUEST:
		if net == null:
			return false
		net.call("send_intent", intent)
		return true
	if host == null:
		return false
	# The turn is read BEFORE the submit: a refusal leaves the engine where it was, but
	# reading it after would tie the log to whenever the batch finished being routed.
	var turn := state.turn if state != null else -1
	var accepted: bool = host.submit(local_player, intent)
	_sync_engine_refs()
	if accepted:
		_log_play(local_player, turn, intent)
	_arm_ack_timeout()
	if mode == Mode.OFFLINE:
		_run_bot()
	return accepted


## True while the local player may act.
##
## Answered from the PRESENTER in every mode, never from `state`: a guest holds no
## MatchState, so a controller that read its own engine would have to answer "no" for
## the entire match. The view model tracks the same things the engine does (phase,
## ended_turn, the play_opened gate) and sees them from the same event stream, so the
## answer is identical on both sides of the wire — which is the point: what the player
## is allowed to do must not depend on which peer they happen to be.
func is_play_phase() -> bool:
	return _presenter_can_act()


## True when the local player still has this turn's plays to take back.
func can_undo() -> bool:
	return _presenter_can_act() and _presenter_undo_count() > 0


## The presenter's view of "may act", or false when there is no presenter (a headless
## run with no view at all — there is nothing to click either way).
func _presenter_can_act() -> bool:
	if presenter == null or not presenter.has_method("local_can_act"):
		return false
	return bool(presenter.call("local_can_act"))


func _presenter_undo_count() -> int:
	if presenter == null or not presenter.has_method("local_undo_count"):
		return 0
	return int(presenter.call("local_undo_count"))


# ----------------------------
# Events
# ----------------------------

## MatchHost's first delivery Callable: one batch, ALREADY redacted for `viewer`.
##
## This is the only way events reach a view in any mode. The local viewer's batch goes
## to the presenter; on a host the guest's goes to MatchNet, after the leak check has
## had a look at it. Offline the bot is viewer 0 and has no presenter, so its batch is
## dropped here — the bot reads host.state directly and never needs its own animation.
func _deliver_events(viewer: int, events: Array, seq: int) -> void:
	if viewer == local_player:
		# Only the LOCAL viewer's batch announces the result: on a host MatchHost
		# delivers the same game_ended twice, once per viewer, and lan_selftest wants
		# exactly one [MATCH] game_ended line per peer.
		_note_batch_end(events)
		if presenter != null and not events.is_empty():
			presenter.call("enqueue", events)
		return
	if mode != Mode.HOST or net == null:
		return
	_check_batch_for_leaks(events)
	net.call("send_events", events, seq)


## MatchHost's second delivery Callable: the full state for `viewer`. Always precedes
## that viewer's first event batch, so this is where the view is BUILT (setup) and every
## later one is just the reference --verify-view compares against.
func _deliver_snapshot(viewer: int, snapshot: Dictionary) -> void:
	if viewer == local_player:
		# setup() builds a whole view from scratch, so it runs exactly ONCE — on the
		# opening snapshot, before any event. MatchHost sends a fresh snapshot after
		# every batch, and calling setup() on each of those would clear the model and
		# rebuild it from a mid-match state, wiping the board the player is looking at.
		# Every later snapshot is only a reference to verify against.
		if presenter != null and not _view_built:
			_view_built = true
			presenter.call("setup", snapshot, local_player, self)
		return
	if mode != Mode.HOST or net == null:
		return
	_check_snapshot_for_leaks(snapshot)
	net.call("send_snapshot", snapshot)


## The end of a match is announced once, by the peer whose own view carries game_ended.
## Done here rather than in the presenter because offline_selftest and lan_selftest both
## grep for exactly one [MATCH] game_ended line per peer with a matching winner.
func _note_batch_end(events: Array) -> void:
	for event: Variant in events:
		if not (event is Dictionary):
			continue
		if event.get("type", &"") != MatchEvents.GAME_ENDED:
			continue
		var winner: int = int(event.get("winner", -1))
		print("[MATCH] game_ended winner=%d" % winner)
		match_ended.emit(winner)


## Plays the offline bot's turn out: MatchBot decides, MatchHost answers, repeat until
## player 0 ended its turn or the round is no longer PLAY. Guarded, because this drives
## itself — a bot that never ends its turn would otherwise spin here forever.
## OFFLINE only: on a host the bot is a peer with its own peer id, not a local loop.
func _run_bot() -> void:
	if _bot_running or host == null or state == null:
		return
	_bot_running = true
	var steps: int = 0
	while state.game_phase == MatchState.GamePhase.TURN_LOOP \
			and state.round_phase == MatchState.RoundPhase.PLAY \
			and not state.players[0].ended_turn:
		steps += 1
		if steps > BOT_MAX_STEPS:
			push_error("MatchController._run_bot: the bot did not end its turn in %d steps" % BOT_MAX_STEPS)
			break
		for intent: Variant in MatchBot.decide(state, 0, bot_rng):
			host.submit(0, intent as Dictionary)
	_bot_running = false
	_sync_engine_refs()
	_arm_ack_timeout()


# ----------------------------
# Session (M5a HOST / GUEST)
# ----------------------------

## Starts hosting: this peer is absolute player 0 and owns the engine. `net` is the
## MatchNet node, used only as the delivery transport for the guest's viewer.
## `host_deck` / `guest_deck` are 12 card ids each (guest_deck already validated by
## MatchHost.check_hello). `want_snapshots` adds the guest to the snapshot viewers.
## `seed` below 0 means "pick one": --seed=N when passed, otherwise random. The seed
## and host_deck never leave the host.
##
## acks_required is [0, 1]: the host's own presenter acks exactly like the guest's, so
## a turn opens only once BOTH peers have finished animating the batch before it. A host
## that skipped its own ack would open turns at its own pace and the whole gate would be
## pointless on the one peer that can be fast.
func start_host(p_net: Node, host_deck: Array, guest_deck: Array, want_snapshots: bool, seed: int = -1) -> void:
	mode = Mode.HOST
	local_player = 0
	net = p_net
	var chosen: int = seed
	if chosen < 0:
		chosen = _dev_seed
	if chosen < 0:
		chosen = randi()
	match_seed = chosen
	bot_rng.seed = chosen + 101
	human_rng.seed = chosen + 202
	_started = true
	_session_ended = false
	_acked_turn = -1
	_leak_check = null
	_leak_pending.clear()

	if presenter == null:
		presenter = _find_presenter()
	if presenter != null:
		_connect_presenter()

	host = MatchHost.new(_deliver_events, _deliver_snapshot)
	host.acks_required = [0, 1]
	# The host's own view is always built from a snapshot; the guest only gets one when
	# it asked for snapshots (--verify-view / --autoplay), because on a normal LAN match
	# it never needs a reference, only the event stream.
	host.snapshot_viewers = [local_player]
	if want_snapshots:
		host.snapshot_viewers.append(1)
	# scramble_ids: the host's deck must not be mappable from the guest's draw ids, since
	# instance ids are handed out in deck order before the shuffle. Offline keeps this
	# false so a --seed run stays byte-identical to the pre-M5a offline setup.
	host.start(host_deck, guest_deck, chosen, true)
	_sync_engine_refs()
	# After start(), so the checker is built against a state that exists and can already
	# be asked what the opening batches should and should not have revealed.
	_start_leak_check()
	_arm_ack_timeout()


## Starts as the guest: absolute player 1, NO MatchState and no MatchRules — this peer
## only sends intents and animates what `net` receives. Every view question
## (is_play_phase, can_undo) is answered from the PRESENTER's view model in this mode,
## which is why those two never read `state` (see is_play_phase).
func start_guest(p_net: Node) -> void:
	mode = Mode.GUEST
	local_player = 1
	net = p_net
	# No engine here, and no state either: the fields stay null on purpose so that any
	# code reaching for them on a guest fails loudly instead of reading player 0's data.
	host = null
	state = null
	rules = null
	_started = true
	_session_ended = false
	_acked_turn = -1
	if presenter == null:
		presenter = _find_presenter()
	if presenter != null:
		_connect_presenter()


## A guest's intent arrived (via MatchNet). HOST mode: hands it to MatchHost.submit(1,
## intent), which redacts and routes the answer. GUEST mode: a host must never send an
## intent, so this is dropped.
func on_remote_intent(intent: Dictionary) -> void:
	if mode != Mode.HOST or host == null:
		return
	# The guest is ALWAYS absolute 1 here — it is the only peer that can send an intent
	# to a host, and its id comes from the transport, not from the payload.
	var turn := state.turn if state != null else -1
	var accepted: bool = host.submit(1, intent)
	_sync_engine_refs()
	if accepted:
		_log_play(1, turn, intent)
	_arm_ack_timeout()


## The guest finished animating turn `turn` (via MatchNet). HOST mode: hands it to
## MatchHost.presentation_done(1, turn), which counts the ack and releases the pending
## play_opened once every id in acks_required has acked. GUEST mode: dropped (the host
## drives the acks).
func on_remote_presentation_done(turn: int) -> void:
	if mode != Mode.HOST or host == null:
		return
	host.presentation_done(1, turn)
	_arm_ack_timeout()


## A host's event batch arrived (via MatchNet). GUEST mode: hands the batch to the
## presenter as-is — it was already redacted for us on the host. HOST mode: dropped.
func on_remote_events(events: Array) -> void:
	if mode != Mode.GUEST or presenter == null:
		return
	_note_batch_end(events)
	_latest_seq += 1
	if not events.is_empty():
		presenter.call("enqueue", events)


## A host's full snapshot arrived (via MatchNet). GUEST mode: the first one (seq 0)
## builds the view with presenter.setup(snapshot, 1, self); later ones are kept as the
## reference --verify-view compares against. HOST mode: dropped.
func on_remote_snapshot(snapshot: Dictionary) -> void:
	if mode != Mode.GUEST:
		return
	_latest_snapshot = snapshot
	if presenter == null:
		return
	# setup() builds a whole view from scratch, so it runs exactly once — on the opening
	# snapshot, which is the pre-start state. Every later snapshot is only the
	# --verify-view reference and the guest autoplay's picture; running setup() again
	# would tear down a live board and rebuild it from a mid-match state.
	if not _view_built:
		_view_built = true
		presenter.call("setup", snapshot, local_player, self)


## Ends the session for a reason the rules do not own. `reason` is a REASON_TEXT key of
## MatchPresenter ("disconnected", "opponent_left", "not_ready", ...). Shows the
## session-ended overlay with match_over = is_match_over(), so a finished result stays
## visible under the message. Idempotent.
func end_session(reason: String) -> void:
	if _session_ended:
		return
	_session_ended = true
	if presenter == null or not presenter.has_method("show_session_ended"):
		return
	presenter.call("show_session_ended",
		MatchPresenter.session_reason_text(reason), is_match_over())


## True once the match is finished. Answered from `state` where there is one (OFFLINE
## and HOST both own the engine) and from the presenter's view model on a GUEST, which
## has neither — which is why the --quit-on-end check asks the controller on both peers
## and gets the same answer from each.
func is_match_over() -> bool:
	if state != null:
		return state.game_phase == MatchState.GamePhase.GAME_END
	if presenter != null and presenter.has_method("is_match_over"):
		return bool(presenter.call("is_match_over"))
	return false


## Leaves the match and returns to the lobby: closes the peer first (so no late packet
## can reach the old session), then reloads the current scene. Called from the
## session-ended overlay's Back to lobby button, and after GAME_END in HOST / GUEST.
##
## NetworkManager.close() is Group C's and is called dynamically: this file must keep
## loading whether or not that method exists, and a headless run with no networking has
## no NetworkManager at all.
func leave_to_lobby() -> void:
	var network_manager := get_node_or_null(^"/root/Main/NetworkManager")
	if network_manager != null and network_manager.has_method("close"):
		network_manager.call("close")
	get_tree().reload_current_scene()


# ----------------------------
# Dev flags (debug builds only)
# ----------------------------

## Reads the command-line flags of tools/offline_selftest.sh. --fast is applied here so
## it takes effect before the match starts.
func _parse_dev_args() -> void:
	if not OS.is_debug_build():
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_dev_seed = int(arg.substr("--seed=".length()))
		elif arg == "--autoplay":
			_dev_autoplay = true
		elif arg == "--verify-view":
			_dev_verify_view = true
		elif arg == "--fast":
			Engine.time_scale = 8.0


## Wires the presenter's idle signal. Safe to call twice: the connection is made once.
func _connect_presenter() -> void:
	if presenter == null or not presenter.has_signal("idle"):
		return
	if not presenter.is_connected("idle", _on_presenter_idle):
		presenter.connect("idle", _on_presenter_idle)


## The view has caught up with the engine. This is the one place that decides what a
## finished batch MEANS, and it differs per mode:
##
##   verify    OFFLINE / HOST: the presenter's model against host.snapshot_for(local),
##             which is the authoritative view the host just sent itself. GUEST: against
##             the last snapshot the host sent, and only while the view is still at the
##             point in the event stream that snapshot describes — a snapshot only ever
##             explains the batches up to its own, so comparing a view that has since
##             animated more would report differences that are not differences.
##   ack       HOST: MatchHost.presentation_done(0, turn). GUEST: MatchNet, which
##             forwards it to the host. Once per turn, when the view is in PLAY of it.
##   autoplay  OFFLINE / HOST: MatchBot.decide against the local engine. GUEST:
##             decide_from_snapshot, because there is no state to decide from.
##
## Order matters: verify runs first so a reported diff describes the state the autoplay
## bot then acted on.
func _on_presenter_idle() -> void:
	view_idle.emit()
	if mode == Mode.NONE:
		return
	if _dev_verify_view:
		_verify_view_now()
	_send_presentation_done()
	_check_match_finished()
	if not _dev_autoplay or not is_play_phase():
		return
	for intent: Variant in _decide_autoplay():
		submit_local(intent as Dictionary)


## Diffs the presenter's model against the authoritative snapshot for this mode.
##
## A GUEST compares against the snapshot the host last sent, and only while that
## snapshot is CURRENT: MatchHost tags every delivered snapshot with the batch count
## the viewer had received, so `seq == _latest_seq` means the snapshot describes
## exactly the state the guest's view has animated. Once the guest has taken another
## batch the reference is behind, and comparing against it would report the difference
## between "the view moved on" and "the view is wrong" — which is why this waits for
## the matching snapshot instead of comparing a stale one.
func _verify_view_now() -> void:
	var reference: Dictionary = {}
	if mode == Mode.GUEST:
		if _latest_snapshot.is_empty():
			return
		if int(_latest_snapshot.get("seq", -1)) != _latest_seq:
			return
		reference = _latest_snapshot
	elif host != null:
		# No leak check here: the checker guards the GUEST (viewer 1) and this is the
		# host's own picture of viewer 0. Feeding it a snapshot the guest never receives
		# would judge the host's own view by the guest's rules, and it is already covered
		# — every snapshot that actually goes to the guest is checked in
		# _deliver_snapshot.
		reference = host.snapshot_for(local_player)
	else:
		return
	var issues: Array = presenter.call("verify", reference)
	if issues.is_empty():
		print("[VIEW] ok turn=%d" % presenter.call("view_turn"))
		return
	for issue: Variant in issues:
		print("[VIEW-MISMATCH] %s" % issue)


## Tells the session this view has animated the turn it is showing, which is what lets
## MatchHost release the play_opened for it. Once per turn: the presenter goes idle
## several times for one turn (every extra batch re-announces idle) and a repeat ack is
## ignored by the host, but sending it anyway would put noise on the wire.
func _send_presentation_done() -> void:
	if mode != Mode.HOST and mode != Mode.GUEST:
		return
	if presenter == null or not bool(presenter.call("view_in_play")):
		return
	var turn := int(presenter.call("view_turn"))
	if turn <= 0 or turn == _acked_turn:
		return
	_acked_turn = turn
	if mode == Mode.GUEST:
		if net != null:
			net.call("send_presentation_done", turn)
		return
	if host == null:
		return
	host.presentation_done(local_player, turn)
	_arm_ack_timeout()


## The intents --autoplay submits for this peer. The guest has no MatchState, so it
## decides from the snapshot the host sent — exactly the information a human has on
## that peer, which is what keeps autoplay from becoming a hidden-information channel.
##
## Both branches pass allow_swaps = true, so an autoplay peer also uses the Elusive lane
## swaps and the offline / LAN self-tests actually exercise that path (including the
## full-lane overflow the new room rule allows). The flag is what keeps the real
## opponent bot (the OTHER decide() call above) and every other caller unchanged.
func _decide_autoplay() -> Array:
	if mode == Mode.GUEST:
		if _latest_snapshot.is_empty():
			return []
		return MatchBot.decide_from_snapshot(_latest_snapshot, human_rng, true)
	if state == null:
		return []
	return MatchBot.decide(state, local_player, human_rng, true)


## Once the match is over on a LAN peer there is nothing left to play and nobody to
## play against: the session gets the same "Opponent left" overlay a disconnect shows,
## with the result left visible underneath. OFFLINE is untouched — it has no opponent
## to leave and must not grow an overlay over the victory text.
func _check_match_finished() -> void:
	if mode != Mode.HOST and mode != Mode.GUEST:
		return
	if _session_ended or not is_match_over():
		return
	end_session("opponent_left")


## Arms the ~10 s ack timeout for the turn MatchHost is currently holding. The timer
## ignores time scale: --fast runs at 8x, and a timeout that shrank to 1.25 s would
## fire before a slow peer had finished a single long resolve, turning the gate into a
## no-op exactly when it is needed. MatchHost cannot await (it is a RefCounted with no
## scene tree), so the timer is driven from here.
func _arm_ack_timeout() -> void:
	if mode != Mode.HOST or host == null:
		return
	var turn := host.pending_turn()
	if turn < 0 or turn == _ack_timeout_turn:
		return
	_ack_timeout_turn = turn
	_run_ack_timeout(turn)


## Waits out the ack for `turn` and lets the session open it anyway if nobody acked. A
## timer that finds nothing pending (the peers got there first) says nothing: only a
## timeout that actually released a turn is a [NET] ack timeout, which is what
## lan_selftest counts.
func _run_ack_timeout(turn: int) -> void:
	await get_tree().create_timer(ACK_TIMEOUT, true, false, true).timeout
	if host == null or mode != Mode.HOST or not is_inside_tree():
		return
	if host.ack_timeout(turn):
		print("[NET] ack timeout turn=%d" % turn)
	_sync_engine_refs()



# ----------------------------
# Session logging and leak checking
# ----------------------------

## One [PLAY] line per ACCEPTED play, on the peer that owns the engine. This is the
## host's record that a real play actually happened for each player — lan_selftest
## requires at least one per player, and a session where a peer only ever ends its turn
## would otherwise look like a healthy match.
##
## `player` is passed in rather than read from `local_player`, which is the HOST's own
## id (always 0 here) and so could only ever print player=0. `turn` is the turn the
## intent was submitted IN, captured by the caller before host.submit() ran.
##
## Only ever called for an intent MatchHost ACCEPTED, which is the second half of the
## point: the guest submits into a turn the host has not opened yet and is refused with
## not_ready several times a match, and a [PLAY] line for a refused intent would claim
## a card reached the board when it never left a hand.
func _log_play(player: int, turn: int, intent: Dictionary) -> void:
	if mode != Mode.HOST:
		return
	if str(intent.get("type", "")) != str(MatchIntents.PLAY_CARD):
		return
	print("[PLAY] player=%d turn=%d" % [player, turn])


## The guest's snapshot refresh is MatchHost's job, not this file's: a viewer in
## snapshot_viewers is sent a fresh snapshot after every batch, so a host that wants
## the guest to --verify-view simply puts 1 in snapshot_viewers and MatchHost keeps the
## pair in step. Nothing here forces an extra send — doing so would put a snapshot
## between a batch and the one that explains it.


## Runs one guest batch past the leak check and prints anything it finds. The guest's
## stream is the one that matters: it is the only traffic a second party ever sees, and
## every hidden-information bug in M5 is a batch that says too much.
##
## With no checker yet (the window before _start_leak_check) the batch is BUFFERED
## rather than dropped — see _buffer_for_leak_check.
func _check_batch_for_leaks(events: Array) -> void:
	if _leak_check == null:
		_buffer_for_leak_check("batch", events)
		return
	_print_leaks(_leak_check.check_batch(events))


## The same for a snapshot, which is the other way hidden information escapes: an
## opponent's face-down card that kept its cost, a hand that arrived as ids, or their
## mana moving mid-PLAY.
func _check_snapshot_for_leaks(snapshot: Dictionary) -> void:
	if _leak_check == null:
		_buffer_for_leak_check("snapshot", snapshot)
		return
	_print_leaks(_leak_check.check_snapshot(snapshot))


## Holds one guest delivery until the checker exists.
##
## The checker cannot be built until MatchHost.start() has run, and start() already
## delivers the opening snapshot and the opening event batch — which is where
## lane_assigned lives, the one event the checker most has to see. Checking on arrival
## would therefore skip exactly the traffic that matters most, so anything delivered in
## that window is kept and replayed in delivery order by _start_leak_check.
## Only the CHECK is deferred: the batch still goes to the guest immediately, because
## holding it would freeze the match waiting on a debug-only auditor.
func _buffer_for_leak_check(kind: String, payload: Variant) -> void:
	if not OS.is_debug_build():
		return
	_leak_pending.append({"kind": kind, "payload": payload})


## The checker guards ONE viewer against the live state, so it is built once per
## session (it learns which opponent instances have legitimately been revealed and has
## to carry that across batches) and it watches the GUEST — the host's own view is this
## machine's screen. Debug builds only: it re-derives the truth for every event.
##
## Replays whatever was delivered to the guest before this point, IN DELIVERY ORDER:
## the checker is stream-based, so the opening snapshot has to be judged before the
## first batch, and the first batch before the first play_opened release. Replaying out
## of order would teach it the wrong thing about what was public when.
func _start_leak_check() -> void:
	_leak_check = null
	if not OS.is_debug_build() or host == null:
		_leak_pending.clear()
		return
	_leak_check = MatchLeakCheck.new(host.state, 1)
	var pending: Array = _leak_pending.duplicate()
	_leak_pending.clear()
	for item: Dictionary in pending:
		if str(item.get("kind", "")) == "batch":
			_print_leaks(_leak_check.check_batch(item.get("payload", [])))
		else:
			_print_leaks(_leak_check.check_snapshot(item.get("payload", {})))


func _print_leaks(problems: Array) -> void:
	for problem: Variant in problems:
		print("[LEAK] %s" % problem)


# ----------------------------
# Deck helpers
# ----------------------------

## Card ids for the human's offline deck: the active saved deck when it is complete and
## every id is known, otherwise MatchDecks.DEFAULT_DECK_IDS — the same rule as
## Deck._build_player_deck. MatchDecks owns the rule (and DECK_SIZE); this only reads
## the saved ids out of the DeckManager autoload, because a guest's deck arrives the
## same way through the join handshake.
static func human_deck_ids() -> Array[String]:
	var saved: Array = []
	var dm := _autoload(&"DeckManager")
	if dm != null and dm.has_method("get_active_deck"):
		for raw: Variant in dm.call("get_active_deck"):
			saved.append(raw)
	return MatchDecks.sanitize(saved)


## MatchDecks.DEFAULT_DECK_IDS, in deck order (a copy: the caller owns the result).
static func default_deck_ids() -> Array[String]:
	return MatchDecks.DEFAULT_DECK_IDS.duplicate()


## MatchDecks.BOT_DECK_IDS: the offline AI's deck (the decisions come from MatchBot,
## the list is data).
static func bot_deck_ids() -> Array[String]:
	return MatchDecks.BOT_DECK_IDS.duplicate()


## The autoload node of that name, or null outside a running tree.
static func _autoload(node_name: StringName) -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null(NodePath(node_name))

