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
