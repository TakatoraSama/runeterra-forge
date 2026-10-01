extends Node

class_name NetworkManager

## The LAN transport of M5a. ENet stays, but this class is now ONLY the peer: it opens
## the connection, closes it, and reports who joined or left. It no longer knows about
## players, assignments or readiness — M5a moved all of that into MatchNet's handshake
## (Scripts/Presentation/MatchNet.gd), which is the only file with an @rpc annotation.
##
## Player ids are absolute (0 = host, 1 = guest) and travel with the session, never with
## the connection: nothing here maps a peer id onto a player id, because the host is
## always player 0 and the guest always player 1.

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)

const DEFAULT_PORT := 9999

## M5a is a two-player game: one host and exactly one guest. create_server(port, 2) used
## to admit a second client to the same match, which has no meaning now that the host
## runs one MatchHost and would have to decide which of two guests is player 1.
const MAX_PLAYERS := 1

var is_host: bool = false


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

	print("Server started on port ", port, ". Peer ID: ", multiplayer.get_unique_id())
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

	print("Connecting to ", address, ":", port)
	return OK


# --- Close the session ---
## Drops the peer and clears every session flag. The peer is closed BEFORE it is
## nulled, so the OS socket is released immediately: leave_to_lobby() reloads the scene
## right after this, and a socket that outlived the scene would keep the port bound.
## Emitting nothing here on purpose — MatchNet already turned a real disconnect into
## session_ended, and this is the deliberate local one.
func close() -> void:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	is_host = false
	print("Network session closed.")


# --- Callbacks ---
## Only the host ever sees this (the guest's peer arrives through this same signal, but
## a client gets server_disconnected instead). The peer id is handed on untouched:
## MatchNet decides whether this peer is allowed to speak to the host.
func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected: ", peer_id)
	emit_signal("player_connected", peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: ", peer_id)
	emit_signal("player_disconnected", peer_id)


func _on_connected_to_server() -> void:
	print("Connected to server! My peer ID: ", multiplayer.get_unique_id())


## The address was unreachable. The peer is dropped so the next join attempt starts
## from a clean slate; the caller retries (LobbyUI's --autojoin does, up to 15 times).
func _on_connection_failed() -> void:
	print("Connection failed!")
	multiplayer.multiplayer_peer = null


## The host is gone. MatchNet's own server_disconnected handler turns this into
## session_ended, so this callback only reports it.
func _on_server_disconnected() -> void:
	print("Server disconnected!")
	multiplayer.multiplayer_peer = null