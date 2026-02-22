extends Node

class_name NetworkManager

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal all_players_ready
signal game_can_start

const DEFAULT_PORT := 9999
const MAX_PLAYERS := 2

# Maps peer_id -> player_id (0 or 1)
var peer_to_player: Dictionary = {}
# Maps player_id -> peer_id
var player_to_peer: Dictionary = {}

var local_player_id: int = 1  # Always 1 for local view (bottom side)
var is_host: bool = false
var players_ready: Dictionary = {}  # peer_id -> bool


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Host a game ---
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Failed to create server: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	
	# Host is player 0 (top side from their own view, but they see themselves as bottom)
	# In a mirrored view: host = player 0, client = player 1
	# But each player always sees themselves as the bottom player locally
	var my_peer_id = multiplayer.get_unique_id()
	peer_to_player[my_peer_id] = 0
	player_to_peer[0] = my_peer_id
	local_player_id = 1  # Locally, you always see yourself as bottom (player 1)
	
	print("Server started on port ", port, ". Peer ID: ", my_peer_id)
	return OK


# --- Join a game ---
func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> Error:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		print("Failed to connect to server: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	local_player_id = 1  # Locally, you always see yourself as bottom (player 1)
	
	print("Connecting to ", address, ":", port)
	return OK


# --- Get the "real" player ID for network (0 = host, 1 = client) ---
func get_network_player_id() -> int:
	"""Returns the actual network player ID (0 for host, 1 for client)"""
	var my_peer_id = multiplayer.get_unique_id()
	return peer_to_player.get(my_peer_id, 0)


# --- Check if it's our turn to do something (both play simultaneously) ---
func is_local_action() -> bool:
	"""In Marvel Snap style, both players act simultaneously, so always true during PLAY"""
	return true


# --- Convert local zone to network zone ---
func local_zone_to_network(zone_key: Vector2i) -> Vector2i:
	"""
	Convert a zone from local view to network view.
	Locally, player is always row 1 (bottom), enemy is row 0 (top).
	On network: host is player 0, client is player 1.
	For the host, their 'own' row is 0 on network, so we flip.
	For the client, their 'own' row is 1 on network, so no flip needed.
	"""
	if is_host:
		# Host: local row 1 (my side) -> network row 0
		return Vector2i(zone_key.x, 1 - zone_key.y)
	else:
		# Client: local row 1 (my side) -> network row 1
		return zone_key


func network_zone_to_local(zone_key: Vector2i) -> Vector2i:
	"""Convert a network zone to local view."""
	if is_host:
		return Vector2i(zone_key.x, 1 - zone_key.y)
	else:
		return zone_key


# --- Callbacks ---
func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)
	
	if is_host:
		# Assign the client as player 1
		peer_to_player[peer_id] = 1
		player_to_peer[1] = peer_id
		
		# Tell the client their assignment
		rpc_id(peer_id, "_receive_player_assignment", 1)
		
		print("Player 1 assigned to peer: ", peer_id)
		emit_signal("player_connected", peer_id)
		
		# Both players connected, game can start
		if peer_to_player.size() >= MAX_PLAYERS:
			emit_signal("all_players_ready")
			# call_local ensures this also runs on the host
			rpc("_notify_game_can_start")


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)
	if peer_to_player.has(peer_id):
		var player_id = peer_to_player[peer_id]
		player_to_peer.erase(player_id)
		peer_to_player.erase(peer_id)
	emit_signal("player_disconnected", peer_id)


func _on_connected_to_server() -> void:
	print("Connected to server! My peer ID: ", multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	print("Connection failed!")
	multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
	print("Server disconnected!")
	multiplayer.multiplayer_peer = null


# --- RPCs ---
@rpc("authority", "reliable")
func _receive_player_assignment(player_id: int) -> void:
	var my_peer_id = multiplayer.get_unique_id()
	peer_to_player[my_peer_id] = player_id
	player_to_peer[player_id] = my_peer_id
	print("Assigned as player: ", player_id)


@rpc("authority", "call_local", "reliable")
func _notify_game_can_start() -> void:
	print("All players ready! Game can start.")
	emit_signal("game_can_start")


# --- Offline / Solo mode ---
func start_offline() -> void:
	"""Start in offline mode (no networking, single player testing)"""
	is_host = true
	local_player_id = 1
	peer_to_player[1] = 0  # Fake host
	player_to_peer[0] = 1
	print("Started in offline mode. Player ID: ", local_player_id)


func is_online() -> bool:
	"""Check if we're in a multiplayer session"""
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
