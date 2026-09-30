extends CanvasLayer

@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/JoinButton
@onready var offline_button: Button = $Panel/VBoxContainer/OfflineButton
@onready var ip_input: LineEdit = $Panel/VBoxContainer/IPInput
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var panel: Panel = $Panel

var network_manager: Node


func _ready() -> void:
	network_manager = get_node("/root/Main/NetworkManager")

	_parse_dev_args()
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	offline_button.pressed.connect(_on_offline_pressed)
	
	if network_manager:
		network_manager.game_can_start.connect(_on_game_can_start)
		network_manager.player_connected.connect(_on_player_connected)
		network_manager.player_disconnected.connect(_on_player_disconnected)
	
	# Show lobby, game starts hidden until connection established
	panel.visible = true
	status_label.text = "Choose an option to start"


func _on_host_pressed() -> void:
	if not network_manager:
		return
	BotManager.bot_enabled = false
	var error = network_manager.host_game()
	if error == OK:
		status_label.text = "Hosting... Waiting for opponent to join."
		host_button.disabled = true
		join_button.disabled = true
		offline_button.disabled = true
	else:
		status_label.text = "Failed to host. Error: %d" % error


func _on_join_pressed() -> void:
	if not network_manager:
		return
	BotManager.bot_enabled = false
	var address = ip_input.text.strip_edges()
	if address == "":
		address = "127.0.0.1"
	var error = network_manager.join_game(address)
	if error == OK:
		status_label.text = "Connecting to %s..." % address
		host_button.disabled = true
		join_button.disabled = true
		offline_button.disabled = true
	else:
		status_label.text = "Failed to connect. Error: %d" % error


func _on_offline_pressed() -> void:
	if not network_manager:
		return
	network_manager.start_offline()
	BotManager.bot_enabled = true
	status_label.text = "Starting offline..."
	_start_game()


func _on_player_connected(_peer_id: int) -> void:
	status_label.text = "Opponent connected! Starting game..."


func _on_player_disconnected(_peer_id: int) -> void:
	status_label.text = "Opponent disconnected!"


func _on_game_can_start() -> void:
	_start_game()


func _start_game() -> void:
	panel.visible = false
	
	# Tell GameManager to begin
	var game_manager = get_node("/root/Main/GameManager")
	if game_manager and game_manager.has_method("start_game"):
		game_manager.start_game()


# ─── Dev automation (debug builds only) ───
# Command-line flags (everything after `--`) that drive the lobby headlessly so
# tools/lan_selftest.sh can run a full two-peer match and diff the [SYNC] logs.

const DEV_JOIN_RETRY_INTERVAL := 1.0
const DEV_JOIN_MAX_ATTEMPTS := 15

var _dev_autojoin_ip: String = ""
var _dev_autoendturn: bool = false
var _dev_quit_on_end: bool = false
var _dev_join_attempts: int = 0


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
		elif arg == "--autoendturn":
			_dev_autoendturn = true
		elif arg == "--quit-on-end":
			_dev_quit_on_end = true

	if autojoin:
		multiplayer.connection_failed.connect(_on_dev_join_failed)
	if _dev_autoendturn or _dev_quit_on_end:
		var game_manager = get_node("/root/Main/GameManager")
		if game_manager:
			game_manager.phase_changed.connect(_on_dev_phase_changed)


func _on_dev_join_failed() -> void:
	"""multiplayer.connection_failed: retry the autojoin every second, up to 15 times.
	join_game() returns OK as soon as the ENet client peer is created, not when it
	connects, so each failure emits this signal again — the attempt count has to
	live in a member, otherwise every call would restart at 1 and never give up."""
	if _dev_autojoin_ip == "":
		return
	_dev_join_attempts += 1
	if _dev_join_attempts > DEV_JOIN_MAX_ATTEMPTS:
		print("[DEV] giving up after %d join attempts" % DEV_JOIN_MAX_ATTEMPTS)
		if _dev_quit_on_end:
			get_tree().quit(1)  # fail the self-test fast instead of hanging until `timeout`
		return
	# The previous attempt was rejected; let the peer come up, then retry.
	await get_tree().create_timer(DEV_JOIN_RETRY_INTERVAL).timeout
	host_button.disabled = false
	join_button.disabled = false
	offline_button.disabled = false
	print("[DEV] join attempt %d" % _dev_join_attempts)
	network_manager.join_game(_dev_autojoin_ip)


func _on_dev_phase_changed(game_phase: int, round_phase: int, _turn: int, _active: int) -> void:
	var game_manager = get_node("/root/Main/GameManager")
	if not game_manager:
		return
	if _dev_autoendturn \
			and game_phase == GameManager.GamePhase.TURN_LOOP \
			and round_phase == GameManager.RoundPhase.PLAY:
		await get_tree().create_timer(0.5).timeout
		game_manager.end_play_phase()
	if _dev_quit_on_end and game_phase == GameManager.GamePhase.GAME_END:
		# 3 s so both peers finish printing their [SYNC] lines before we exit.
		await get_tree().create_timer(3.0).timeout
		get_tree().quit()
