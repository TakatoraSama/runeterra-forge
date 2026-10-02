extends CanvasLayer

## The lobby and the M5a join handshake.
##
## Both peers build MatchNet BEFORE they connect, so the RPC node path
## (/root/Main/MatchNet) is identical on both sides — an @rpc call is addressed by node
## path, and a path that only exists on one peer silently never arrives.
##
## The handshake itself is five lines of data and no rules:
##   guest: on connected_to_server -> hello({protocol, deck, want_snapshots})
##   host:  MatchNet.hello -> MatchHost.check_hello -> guest_ready | session_refused
##   host:  guest_ready -> controller.start_host(net, host_deck, guest_deck, ...)
##   guest: start_guest(net) as soon as it connects; its view comes from the snapshot
## The host's deck and the match seed never leave this machine: the guest only ever
## learns its own validated deck, and the host picks the seed.

@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/JoinButton
@onready var offline_button: Button = $Panel/VBoxContainer/OfflineButton
@onready var ip_input: LineEdit = $Panel/VBoxContainer/IPInput
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var panel: Panel = $Panel

var network_manager: Node

## The session's MatchNet node, or null while still in the lobby. Both peers create
## one before connecting; it is the only node that carries an @rpc annotation.
var match_net: MatchNet = null

## The MatchController of a LAN session (HOST or GUEST), or null in the lobby and in
## offline mode. Kept as a field because the session outlives these button handlers.
var session_controller: Node = null


func _ready() -> void:
	network_manager = get_node("/root/Main/NetworkManager")

	_parse_dev_args()

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	offline_button.pressed.connect(_on_offline_pressed)

	if network_manager:
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)

	# Show lobby, game starts hidden until connection established
	panel.visible = true
	status_label.text = "Choose an option to start"


# ---------------------------------------------------------------------------
# Lobby buttons
# ---------------------------------------------------------------------------

func _on_host_pressed() -> void:
	if not network_manager:
		return
	# MatchNet first: the RPC path has to exist before a single packet is exchanged.
	_ensure_match_net(true)
	var error = network_manager.host_game()
	if error == OK:
		status_label.text = "Hosting... Waiting for opponent to join."
		_set_buttons_enabled(false)
	else:
		status_label.text = "Failed to host. Error: %d" % error


func _on_join_pressed() -> void:
	if not network_manager:
		return
	var address = ip_input.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	# The guest builds its whole session here — MatchNet, controller and presenter —
	# because start_guest() has to be running before the host's first snapshot lands.
	_ensure_match_net(false)
	_build_session_nodes()
	match_net.controller = session_controller
	session_controller.call("start_guest", match_net)
	var error = network_manager.join_game(address)
	if error == OK:
		status_label.text = "Connecting to %s..." % address
		_set_buttons_enabled(false)
		# multiplayer.connected_to_server fires once the socket is really up; the
		# hello goes out from there, not from here, because create_client() returns
		# long before the connection is established.
		multiplayer.connected_to_server.connect(_on_guest_connected)
	else:
		status_label.text = "Failed to connect. Error: %d" % error


func _on_offline_pressed() -> void:
	"""Start an offline match on the Match engine. Nothing else here touches the
	board: the presenter builds the view."""
	_start_engine_offline()


func _start_engine_offline() -> void:
	"""Create the MatchController + MatchPresenter under /root/Main and hand the match
	to the engine. Nothing else here touches the board: the presenter builds the view."""
	_build_session_nodes()
	_connect_quit_on_end(session_controller)

	panel.visible = false
	# Decks: the human's saved deck when complete (else the default deck) and the
	# offline bot's deck, via MatchController.
	session_controller.call("start_offline",
		MatchController.human_deck_ids(), MatchController.bot_deck_ids(), _dev_seed)


# ---------------------------------------------------------------------------
# Session construction
# ---------------------------------------------------------------------------

## Creates MatchNet under /root/Main, or returns the one already there. `as_host` is
## fixed on creation and is what makes the node send in one direction and accept in the
## other, so a second call must not flip it.
func _ensure_match_net(as_host: bool) -> MatchNet:
	if match_net != null and is_instance_valid(match_net):
		return match_net
	var main := get_node_or_null("/root/Main")
	if not main:
		status_label.text = "Cannot start a session: /root/Main is missing"
		return null
	var net := MatchNet.new()
	net.name = "MatchNet"
	net.is_host = as_host
	net.debug_logs = OS.is_debug_build()
	main.add_child(net)
	net.guest_ready.connect(_on_guest_ready)
	net.session_refused.connect(_on_session_refused)
	net.session_ended.connect(_on_session_ended)
	net.open_batch_log()
	match_net = net
	return match_net


## Creates the MatchController + MatchPresenter of a session under /root/Main, or
## returns the ones already there. Offline calls this with no MatchNet; both LAN peers
## call it before connecting.
func _build_session_nodes() -> void:
	var main := get_node_or_null("/root/Main")
	if not main:
		status_label.text = "Cannot start a session: /root/Main is missing"
		return
	if session_controller == null or not is_instance_valid(session_controller):
		var controller := MatchController.new()
		controller.name = "MatchController"
		main.add_child(controller)
		session_controller = controller
	if main.get_node_or_null(^"MatchPresenter") == null:
		var presenter := MatchPresenter.new()
		presenter.name = "MatchPresenter"
		main.add_child(presenter)
	_connect_quit_on_end(session_controller)


## `--quit-on-end` has to work on all three peers, and they do not agree on how to
## learn that the match is over: offline and HOST own a MatchState, the GUEST has
## none. controller.is_match_over() is the one question all three can answer, so every
## mode asks it rather than reading the state directly.
func _connect_quit_on_end(controller: Node) -> void:
	if not _dev_quit_on_end or _dev_quit_done or controller == null:
		return
	# controller.presenter is only assigned once start_offline/start_host ran, so this
	# looks the node up directly instead: on a LAN peer the flag is set before the
	# match starts (the guest has to be watching before the host's snapshot lands).
	var presenter: Node = controller.get("presenter")
	if presenter == null:
		presenter = controller.get_node_or_null(^"/root/Main/MatchPresenter")
	if presenter == null or not presenter.has_signal("idle"):
		return
	# This is called from more than one place (building the session nodes and answering
	# the handshake), so the Callable is kept and compared before connecting again.
	# Comparing a fresh `bind()` result would not do: every bind() is a new object.
	var bound := _on_dev_presenter_idle.bind(controller)
	if _quit_on_end_callable.is_valid() and _quit_on_end_callable == bound:
		return
	_quit_on_end_callable = bound
	presenter.idle.connect(bound)


func _on_dev_presenter_idle(controller: Node) -> void:
	"""`--quit-on-end` watches the presenter and quits once the controller says the
	match is over (a 3 s grace so both peers have printed their final lines
	before the process exits)."""
	if _dev_quit_done or not _dev_quit_on_end:
		return
	if controller == null or not bool(controller.call("is_match_over")):
		return
	_dev_quit_done = true
	await get_tree().create_timer(3.0).timeout
	get_tree().quit()


# ---------------------------------------------------------------------------
# The handshake
# ---------------------------------------------------------------------------

## GUEST: the connection is up. Send hello and stop listening for it. The deck is this
## peer's own saved deck, already sanitized by MatchDecks; want_snapshots is only ever
## true for a debug run that asked to check its view, because a snapshot is the largest
## thing on the wire and a release match never needs one.
func _on_guest_connected() -> void:
	if match_net != null and multiplayer.connected_to_server.is_connected(_on_guest_connected):
		multiplayer.connected_to_server.disconnect(_on_guest_connected)
	status_label.text = "Connected. Starting game..."
	match_net.send_hello({
		"protocol": MatchHost.PROTOCOL_VERSION,
		"deck": MatchController.human_deck_ids(),
		"want_snapshots": _want_snapshots(),
	})


## HOST: the guest's hello passed MatchHost.check_hello (the deck is validated, the
## protocol matches and there is no second guest), so the match can start. The host's
## own deck and the seed are read here and stay here.
##
## The session nodes are built HERE, not at Host time: the host needs the guest's deck
## before it can start, and start_host delivers the opening snapshot to its own
## presenter inside that call — so the controller and the presenter both have to exist
## before it runs.
func _on_guest_ready(guest_deck: Array, want_snapshots: bool) -> void:
	status_label.text = "Opponent connected! Starting game..."
	_build_session_nodes()
	_connect_quit_on_end(session_controller)
	match_net.controller = session_controller
	panel.visible = false
	session_controller.call("start_host",
		match_net,
		MatchController.human_deck_ids(),
		guest_deck,
		want_snapshots,
		_dev_seed)


## HOST: the handshake was refused. Nothing was started, so this is still a lobby and
## the buttons have to work again.
func _on_session_refused(reason: String) -> void:
	status_label.text = "Join refused: %s" % _reason_text(reason)
	_set_buttons_enabled(true)


## BOTH peers: the session ended (a peer dropped, or the host ended it after GAME_END).
## The controller shows the overlay and owns the Back to lobby button.
func _on_session_ended(reason: String) -> void:
	if session_controller != null and is_instance_valid(session_controller):
		session_controller.call("end_session", reason)
		return
	# Still in the lobby: nothing to end, so just say it and re-enable the buttons.
	_on_lobby_disconnect(reason)


## True when this run wants the host to keep sending snapshots: a debug build that
## asked for --verify-view or --autoplay. Anything else (a release play) never asks.
func _want_snapshots() -> bool:
	return OS.is_debug_build() and (_dev_verify_view or _dev_autoplay)


func _reason_text(reason: String) -> String:
	return str(MatchPresenter.REASON_TEXT.get(reason, reason))


# ---------------------------------------------------------------------------
# Lobby-time connection callbacks
# ---------------------------------------------------------------------------

## The peer that just joined. This is the ONLY place the host learns who the guest is:
## MatchNet drops every guest -> host message that did not come from `guest_peer_id`,
## so the id has to be recorded here, before the guest's hello can arrive.
## The match still does not start until that hello has been checked, so the text must
## not promise a game.
func _on_player_connected(peer_id: int) -> void:
	if match_net != null and match_net.is_host:
		match_net.guest_peer_id = peer_id
	if not panel.visible:
		return  # already in a match, nothing to announce
	status_label.text = "Opponent connected! Handshaking..."


## A peer went away. In the lobby this is the only feedback there is, so it re-enables
## the buttons; in a match MatchNet has already turned it into session_ended.
func _on_player_disconnected(_peer_id: int) -> void:
	if match_net != null and not panel.visible:
		return  # the match handles it (MatchNet -> session_ended)
	_on_lobby_disconnect("disconnected")


func _on_lobby_disconnect(reason: String) -> void:
	status_label.text = "Opponent disconnected!" if reason == "disconnected" \
		else "Session ended: %s" % _reason_text(reason)
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	offline_button.disabled = not enabled


# ─── Dev automation (debug builds only) ───
# Command-line flags (everything after `--`) that drive the lobby headlessly so
# tools/lan_selftest.sh can run a full two-peer match and diff the [NET-OUT] / [NET-IN]
# logs of both sides.

const DEV_JOIN_RETRY_INTERVAL := 1.0
const DEV_JOIN_MAX_ATTEMPTS := 15

var _dev_autojoin_ip: String = ""
var _dev_autoplay: bool = false
var _dev_offline: bool = false
var _dev_quit_done: bool = false
var _dev_quit_on_end: bool = false
var _dev_seed: int = -1
var _dev_verify_view: bool = false
var _dev_join_attempts: int = 0

## The Callable currently connected to the presenter's `idle` for --quit-on-end, so a
## second _connect_quit_on_end() call is a no-op instead of a duplicate connection.
var _quit_on_end_callable: Callable = Callable()


func _parse_dev_args() -> void:
	if not OS.is_debug_build():
		return
	var autojoin := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--autohost":
			call_deferred("_on_host_pressed")
		elif arg.begins_with("--autojoin="):
			autojoin = true
			_dev_autojoin_ip = arg.substr("--autojoin=".length())
			ip_input.text = _dev_autojoin_ip
			call_deferred("_on_join_pressed")
		elif arg == "--quit-on-end":
			_dev_quit_on_end = true
		elif arg == "--offline":
			_dev_offline = true
		elif arg == "--autoplay":
			_dev_autoplay = true
		elif arg == "--verify-view":
			_dev_verify_view = true
		elif arg.begins_with("--seed="):
			_dev_seed = int(arg.substr("--seed=".length()))

	if autojoin:
		multiplayer.connection_failed.connect(_on_dev_join_failed)
	if _dev_offline:
		call_deferred("_on_offline_pressed")


## multiplayer.connection_failed: retry the autojoin every second, up to 15 times.
## join_game() returns OK as soon as the ENet client peer is created, not when it
## connects, so each failure emits this signal again — the attempt count has to
## live in a member, otherwise every call would restart at 1 and never give up.
func _on_dev_join_failed() -> void:
	if _dev_autojoin_ip == "":
		return
	_dev_join_attempts += 1
	if _dev_join_attempts > DEV_JOIN_MAX_ATTEMPTS:
		print("[DEV] giving up after %d join attempts" % _dev_join_attempts)
		if _dev_quit_on_end:
			get_tree().quit(1)  # fail the self-test fast instead of hanging until `timeout`
		return
	# The previous attempt was rejected; let the peer come up, then retry.
	await get_tree().create_timer(DEV_JOIN_RETRY_INTERVAL).timeout
	_set_buttons_enabled(true)
	print("[DEV] join attempt %d" % _dev_join_attempts)
	network_manager.join_game(_dev_autojoin_ip)