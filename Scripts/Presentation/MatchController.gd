## The M4 match driver: the pure-data engine plus the presenter that shows it.
##
## This is the ONLY place where offline play runs on the new engine (Scripts/Match).
## It owns no rules of its own — every decision is an intent handed to MatchRules and
## every answer is an event handed to the presenter:
##   start_offline -> MatchSetup.new_match + MatchRules + MatchCardAbilities,
##                    the presenter is given the opening snapshot, the start events are
##                    routed and the bot is driven until it ends its turn.
##   submit_local  -> rules.submit(local_player, intent), routed, then the bot answers.
##
## Perspective: offline the human is absolute player 1 and the bot is player 0, so
## local_player is always 1 and every event is filtered through
## MatchEvents.redact_for(event, local_player) before the presenter ever sees it.
##
## It deliberately holds no game logic of the old game: no AbilityResolver, no
## LaneManager, no BotManager decisions, no Deck.draw_card. The three old constants it
## reads (the saved deck, the default deck, the bot deck) are static data.
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

## The session this controller drives: NONE until start_offline / start_host /
## start_guest sets it. Everything mode-dependent keys off this — which viewer events
## are redacted for, whether the local player may submit, and whether this controller
## owns a MatchState at all (the guest does not).
var mode: Mode = Mode.NONE

var rules: MatchRules
var state: MatchState
var local_player: int = 1
var presenter: Node  # /root/Main/MatchPresenter

## The bot's own randomness, kept apart from the match RNG so the engine's replay is
## untouched. Both are seeded from the match seed, so a --seed run replays exactly.
var bot_rng := RandomNumberGenerator.new()
var human_rng := RandomNumberGenerator.new()

var _started: bool = false
var _bot_running: bool = false
var _dev_seed: int = -1
var _dev_autoplay: bool = false
var _dev_verify_view: bool = false


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
func start_offline(human_deck: Array, bot_deck: Array, seed: int = -1) -> void:
	mode = Mode.OFFLINE
	var chosen: int = seed
	if chosen < 0:
		chosen = _dev_seed
	if chosen < 0:
		chosen = randi()
	match_seed = chosen

	state = MatchSetup.new_match(bot_deck, human_deck, chosen)
	rules = MatchRules.new(state)
	MatchCardAbilities.install(rules)
	bot_rng.seed = chosen + 101
	human_rng.seed = chosen + 202
	_started = true

	if presenter == null:
		presenter = _find_presenter()
	if presenter != null:
		_connect_presenter()
		presenter.call("setup", MatchSnapshot.for_viewer(state, local_player), local_player, self)

	_route(rules.start_match())
	_run_bot()


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

## Submits one intent from the local player and routes the answer, then lets the bot
## move. Returns false when the engine refused the intent, so the caller can tell a
## rejected drag from an accepted one.
func submit_local(intent: Dictionary) -> bool:
	if rules == null or state == null:
		return false
	var events: Array = rules.submit(local_player, intent)
	var rejected: bool = _has_local_rejection(events)
	_route(events)
	_run_bot()
	return not rejected


## True while the local player may act: the turn loop is in PLAY, the local player has
## not ended the turn, and the presenter is not still animating (otherwise the board the
## player is looking at is one event behind the engine).
func is_play_phase() -> bool:
	if state == null or rules == null:
		return false
	if state.game_phase != MatchState.GamePhase.TURN_LOOP:
		return false
	if state.round_phase != MatchState.RoundPhase.PLAY:
		return false
	if state.players[local_player].ended_turn:
		return false
	return _presenter_idle()


## True when the local player still has this turn's plays to take back.
func can_undo() -> bool:
	if not is_play_phase():
		return false
	return not state.players[local_player].undo_stack.is_empty()


## True when one of `events` is the local player's own intent being refused.
func _has_local_rejection(events: Array) -> bool:
	for event: Variant in events:
		if not (event is Dictionary):
			continue
		if event.get("type", &"") != MatchEvents.INTENT_REJECTED:
			continue
		if int(event.get("player", -1)) == local_player:
			return true
	return false


# ----------------------------
# Events
# ----------------------------

## Filters `events` down to what the local player may see and hands them to the
## presenter in one batch. Nothing is queued when the presenter does not exist.
func _route(events: Array) -> void:
	var visible: Array = []
	for event: Variant in events:
		if not (event is Dictionary):
			continue
		if event["type"] == MatchEvents.GAME_ENDED:
			var winner: int = int(event.get("winner", -1))
			print("[MATCH] game_ended winner=%d" % winner)
			match_ended.emit(winner)
		var shown: Variant = MatchEvents.redact_for(event, local_player)
		if shown == null:
			continue
		visible.append(shown)
	if presenter == null or visible.is_empty():
		return
	presenter.call("enqueue", visible)


## Plays the bot's turn out: MatchBot decides, the engine answers, repeat until player
## 0 ended its turn or the round is no longer PLAY. Guarded, because this drives itself
## — a bot that never ends its turn would otherwise spin here forever.
func _run_bot() -> void:
	if _bot_running or state == null or rules == null:
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
			_route(rules.submit(0, intent as Dictionary))
	_bot_running = false


# ----------------------------
# Session (M5a HOST / GUEST) — STUB, implemented by M5a Group B
# ----------------------------

## Starts hosting: this peer is absolute player 0 and owns the engine. `net` is the
## MatchNet node, used only as the delivery transport for the guest's viewer.
## `host_deck` / `guest_deck` are 12 card ids each (guest_deck already validated by
## MatchHost.check_hello). `want_snapshots` adds the guest to the snapshot viewers.
## `seed` below 0 means "pick one": --seed=N when passed, otherwise random. The seed
## and host_deck never leave the host.
func start_host(net: Node, host_deck: Array, guest_deck: Array, want_snapshots: bool, seed: int = -1) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## Starts as the guest: absolute player 1, NO MatchState and no MatchRules — this peer
## only sends intents and animates what `net` receives. Every view question
## (is_play_phase, can_undo) must therefore be answered from the PRESENTER's view model
## in this mode, never from `state`.
func start_guest(net: Node) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## A guest's intent arrived (via MatchNet). HOST mode: hands it to MatchHost.submit(1,
## intent), which redacts and routes the answer. GUEST mode: a host must never send an
## intent, so this is dropped.
func on_remote_intent(intent: Dictionary) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## The guest finished animating turn `turn` (via MatchNet). HOST mode: hands it to
## MatchHost.presentation_done(1, turn), which counts the ack and releases the pending
## play_opened once every id in acks_required has acked. GUEST mode: dropped (the host
## drives the acks).
func on_remote_presentation_done(turn: int) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## A host's event batch arrived (via MatchNet). GUEST mode: hands the batch to the
## presenter as-is — it was already redacted for us on the host. HOST mode: dropped.
func on_remote_events(events: Array) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## A host's full snapshot arrived (via MatchNet). GUEST mode: the first one (seq 0)
## builds the view with presenter.setup(snapshot, 1, self); later ones are kept as the
## reference --verify-view compares against. HOST mode: dropped.
func on_remote_snapshot(snapshot: Dictionary) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## Ends the session for a reason the rules do not own. `reason` is a REASON_TEXT key of
## MatchPresenter ("disconnected", "opponent_left", "not_ready", ...). Shows the
## session-ended overlay with match_over = is_match_over(), so a finished result stays
## visible under the message. Idempotent.
func end_session(reason: String) -> void:
	push_error("MatchController: not implemented (M5a Group B)")


## True once the match is finished. Implemented here for offline and HOST (both own a
## MatchState). GUEST has no state, so it is answered from the presenter's view model
## — which is why the --quit-on-end check asks the controller on both peers.
func is_match_over() -> bool:
	return state != null and state.game_phase == MatchState.GamePhase.GAME_END


## Leaves the match and returns to the lobby: closes the peer first (so no late packet
## can reach the old session), then reloads the current scene. Called from the
## session-ended overlay's Back to lobby button, and after GAME_END in HOST / GUEST.
func leave_to_lobby() -> void:
	push_error("MatchController: not implemented (M5a Group B)")


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


## The view has caught up with the engine: check it, then let the human bot play.
## --verify-view runs first so the diff describes the state the autoplay bot saw.
func _on_presenter_idle() -> void:
	view_idle.emit()
	if state == null:
		return
	if _dev_verify_view:
		var issues: Array = presenter.call("verify", MatchSnapshot.for_viewer(state, local_player))
		if issues.is_empty():
			print("[VIEW] ok turn=%d" % state.turn)
		else:
			for issue: Variant in issues:
				print("[VIEW-MISMATCH] %s" % issue)
	if not _dev_autoplay or not is_play_phase():
		return
	var intents: Array = MatchBot.decide(state, local_player, human_rng)
	if intents.is_empty():
		return
	# Through submit_local, the same path a human click takes, so the autoplay run
	# exercises the same rejections, routing and bot hand-off as a real match. Every
	# intent is submitted even after a refusal: end_turn is what moves the round on, and
	# stopping early would leave the human stuck in PLAY with an idle presenter.
	for intent: Variant in intents:
		submit_local(intent as Dictionary)


# ----------------------------
# Deck helpers
# ----------------------------

## True when the presenter is not busy, or when there is no presenter at all (a
## headless run without the view). is_play_phase() must not hang on a missing view.
func _presenter_idle() -> bool:
	if presenter == null:
		return true
	return not bool(presenter.call("is_busy"))


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

