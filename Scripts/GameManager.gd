extends Node2D

class_name GameManager

signal phase_changed(game_phase: int, round_phase: int, turn_number: int, active_player_id: int)
signal turn_changed(turn_number: int, active_player_id: int)
signal mana_changed(player_id: int, current_mana: int, max_mana: int)
signal flip_first_changed(player_id: int)

enum GamePhase {
	GAME_START,
	TURN_LOOP,
	GAME_END,
}

enum RoundPhase {
	NONE,
	ROUND_START,
	PLAY,
	RESOLVE,
	ROUND_END,
}

class PlayerManaState:
	var base_max_mana: int = 1
	var bonus_max_mana: int = 0
	var current_mana: int = 1

	func get_max_mana() -> int:
		return max(0, base_max_mana + bonus_max_mana)

	func clamp_current_to_max() -> void:
		current_mana = clamp(current_mana, 0, get_max_mana())


@export var max_turns: int = 6
@export var player_count: int = 2
@export var starting_player_id: int = 1
@export var initial_draw_count: int = 3
@export var draw_per_turn: int = 1
@export var mana_indicator_player_id: int = 1

# Node references (resolved in _ready)
@onready var card_manager: Node = $"../CardManager"
@onready var deck_reference: Node = $"../Deck"
@onready var network_manager: Node = $"../NetworkManager"
@onready var board_reference: Node = $"../Board"
@onready var turn_text: Node = $"../CardManager/TurnText"
@onready var mana_text: Node = $"../CardManager/ManaText"
@onready var flip_first_text: Node = $"../CardManager/FlipFirstText"
@onready var end_turn_button: Button = $"../CardManager/Button"
@onready var victory_text: Node = $"../VictoryText"

var game_phase: int = GamePhase.GAME_START
var round_phase: int = RoundPhase.NONE
var turn_number: int = 0
var active_player_id: int = 1
var flip_first_player_id: int = -1  # Player who acts first during resolve and ability phases

var _mana_by_player: Dictionary = {}
var _players_ended_turn: Dictionary = {}  # peer_id -> bool, tracks who hit End Turn
var _pending_bonus_mana: Dictionary = {}  # player_id -> int, bonus mana to apply next turn
var _active_temp_mana: Dictionary = {}    # player_id -> int, temp bonus currently active (removed next turn)


func _ready() -> void:
	_initialize_player_states()
	# Connect end-turn button
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	# Don't auto-start; LobbyUI will call start_game() after connection


func _initialize_player_states() -> void:
	_mana_by_player.clear()
	var count = max(1, player_count)
	for player_id in range(count):
		_mana_by_player[player_id] = PlayerManaState.new()


func start_game() -> void:
	game_phase = GamePhase.GAME_START
	round_phase = RoundPhase.NONE
	turn_number = 0
	active_player_id = clamp(starting_player_id, 0, max(0, player_count - 1))
	if victory_text:
		if "visible" in victory_text:
			victory_text.visible = false
	_emit_phase()

	# --- Assign flip first: server decides, then syncs to client ---
	if _is_online():
		if multiplayer.is_server():
			var chosen = randi_range(0, 1)
			# Map server's player_id to each client's local perspective:
			# Server (host) is network player 0, client is network player 1.
			# Locally each player sees themselves as player 1.
			# So if chosen == 0 (host wins), host sees 0 (opponent), client sees 1 (you) — wrong.
			# We need to send the raw network player id and let each side interpret it.
			rpc("_sync_flip_first", chosen)
		# else: client waits for server's RPC
	else:
		# Offline: just pick locally
		flip_first_player_id = randi_range(0, 1)
		_sync_flip_first_to_card_manager()
		emit_signal("flip_first_changed", flip_first_player_id)
		print("Flip first assigned to player: ", flip_first_player_id)

	# --- Lane assignment: server picks, syncs to all clients ---
	if _is_online():
		if multiplayer.is_server():
			var lane_ids = board_reference.pick_random_lane_ids()
			rpc("_sync_lane_assignment", lane_ids)
		# else: client waits for server RPC
	else:
		var lane_ids = board_reference.pick_random_lane_ids()
		_sync_lane_assignment(lane_ids)

	# --- Game Start: shuffle deck, trigger game start abilities, then draw initial hand ---
	if deck_reference and deck_reference.has_method("shuffle_deck"):
		deck_reference.shuffle_deck()
	
	# Trigger Game Start abilities (flip first player processes first)
	if deck_reference and deck_reference.has_method("trigger_game_start_abilities"):
		await deck_reference.trigger_game_start_abilities()
	
	if deck_reference and deck_reference.has_method("draw_cards"):
		deck_reference.draw_cards(initial_draw_count)

	_update_ui_indicators()
	start_next_turn()


func start_next_turn() -> void:
	if game_phase == GamePhase.GAME_END:
		return
	if turn_number >= max_turns:
		end_game()
		return

	game_phase = GamePhase.TURN_LOOP

	# Increment global turn number (1..max_turns)
	turn_number += 1

	# This game uses global turns (Marvel Snap style): both players play during the
	# same PLAY phase. We do NOT swap active_player_id each turn.

	_sync_active_player_to_card_manager()
	emit_signal("turn_changed", turn_number, active_player_id)

	begin_round_start()
	_update_ui_indicators()


func is_play_phase() -> bool:
	return game_phase == GamePhase.TURN_LOOP and round_phase == RoundPhase.PLAY


func begin_round_start() -> void:
	_set_round_phase(RoundPhase.ROUND_START)

	# --- Handle temporary bonus mana lifecycle ---
	# 1. Remove any active temp bonus from last turn
	_expire_temp_bonus_mana()
	# 2. Apply any pending bonus queued last turn
	_apply_pending_bonus_mana()

	# Turn-based mana growth: base max mana equals turn number.
	_apply_turn_based_mana_growth(turn_number)

	# Default behavior: refill all players each new turn.
	_refill_all_players_mana()

	# Lane reveal and round-start lane mechanics (fires BEFORE card abilities)
	await LaneManager.on_round_start(turn_number)

	# Trigger Round Start abilities in play order
	if card_manager and card_manager.has_method("trigger_round_start_abilities"):
		await card_manager.trigger_round_start_abilities()

	# --- Round Start: draw cards for the active player ---
	if deck_reference and deck_reference.has_method("draw_cards"):
		deck_reference.draw_cards(draw_per_turn)

	# Leave ROUND_START as a real phase for triggers,
	# then move into PLAY immediately.
	_set_round_phase(RoundPhase.PLAY)


func end_play_phase() -> void:
	# End Turn button now enters RESOLVE, then auto-ends the round.
	if game_phase != GamePhase.TURN_LOOP:
		return
	if round_phase != RoundPhase.PLAY:
		return

	# Immediately lock the button to prevent double-clicks
	if end_turn_button:
		end_turn_button.disabled = true
	
	# Cancel any card currently being dragged so it can't linger into resolve phase
	if card_manager and card_manager.has_method("cancel_active_drag"):
		card_manager.cancel_active_drag()
	
	# Multiplayer: notify server we ended our turn
	if _is_online():
		# Sync hand data to opponent for behold calculations
		if card_manager and card_manager.has_method("sync_hand_data"):
			card_manager.sync_hand_data()
		var my_peer_id = multiplayer.get_unique_id()
		if multiplayer.is_server():
			_on_player_end_turn(my_peer_id)
		else:
			rpc_id(1, "_on_player_end_turn", my_peer_id)
		end_turn_button.disabled = true
		return  # Wait for server to call _proceed_to_resolve
	
	# Offline: proceed immediately
	_proceed_to_resolve()


@rpc("any_peer", "reliable")
func _on_player_end_turn(peer_id: int) -> void:
	"""Server-side: track which players have ended their turn"""
	if not multiplayer.is_server():
		return
	_players_ended_turn[peer_id] = true
	print("Player (peer %d) ended turn. %d/%d ready" % [peer_id, _players_ended_turn.size(), player_count])
	
	# Check if all players have ended turn
	if _players_ended_turn.size() >= player_count:
		_players_ended_turn.clear()
		# call_local ensures this also runs on the host
		rpc("_proceed_to_resolve")


@rpc("authority", "call_local", "reliable")
func _proceed_to_resolve() -> void:
	"""All players ended turn, proceed to resolve phase"""
	_set_round_phase(RoundPhase.RESOLVE)
	await _resolve_phase()
	
	# Update zone power texts after cards are revealed
	_update_zone_power_display()
	
	_set_round_phase(RoundPhase.ROUND_END)
	
	# Trigger Round End abilities in play order (respects flip first)
	if card_manager and card_manager.has_method("trigger_round_end_abilities"):
		await card_manager.trigger_round_end_abilities()

	# Lane round-end effects (Ornn's Forge, Sunken Temple) — fire AFTER card abilities
	await LaneManager.on_round_end(turn_number)

	# Update zone power again after round end abilities
	_update_zone_power_display()
	
	# Check lane winners and reassign flip first
	check_lane_winners_and_update_flip_first()
	
	start_next_turn()


func _resolve_phase() -> void:
	if not card_manager:
		return
	if card_manager.has_method("resolve_played_cards"):
		await card_manager.resolve_played_cards()


func end_game() -> void:
	game_phase = GamePhase.GAME_END
	round_phase = RoundPhase.NONE
	_emit_phase()
	
	# Trigger Game End abilities in play order
	if card_manager and card_manager.has_method("trigger_game_end_abilities"):
		await card_manager.trigger_game_end_abilities()

	_update_zone_power_display()
	_show_match_result_text(_determine_match_winner_local())
	
	_update_ui_indicators()


func _determine_match_winner_local() -> int:
	"""Returns local winner id: 0 (top), 1 (bottom), or -1 for tie."""
	if not board_reference:
		return -1

	var player_0_lanes_won := 0
	var player_1_lanes_won := 0
	var total_power_0 := 0
	var total_power_1 := 0

	for col in range(3):
		var power_0 := _get_zone_total_power(Vector2i(col, 0))
		var power_1 := _get_zone_total_power(Vector2i(col, 1))
		total_power_0 += power_0
		total_power_1 += power_1

		if power_0 > power_1:
			player_0_lanes_won += 1
		elif power_1 > power_0:
			player_1_lanes_won += 1

	# Rule 1: whoever wins 2 of 3 lanes wins immediately.
	if player_0_lanes_won >= 2:
		return 0
	if player_1_lanes_won >= 2:
		return 1

	# Rule 2: if no one has 2 lane wins (e.g. tied lanes), compare total power.
	if total_power_0 > total_power_1:
		return 0
	if total_power_1 > total_power_0:
		return 1

	# Same total power => tie.
	return -1


func _show_match_result_text(winner_local_id: int) -> void:
	if not victory_text:
		return

	if "text" in victory_text:
		if winner_local_id == -1:
			victory_text.text = "TIE"
		elif winner_local_id == 1:
			victory_text.text = "VICTORY"
		else:
			victory_text.text = "DEFEAT"

	if "visible" in victory_text:
		victory_text.visible = true


func _set_round_phase(next_round_phase: int) -> void:
	round_phase = next_round_phase
	_emit_phase()
	_update_ui_indicators()


func _emit_phase() -> void:
	emit_signal("phase_changed", game_phase, round_phase, turn_number, active_player_id)


func _sync_active_player_to_card_manager() -> void:
	# CardManager currently uses `current_player_id` to restrict placement.
	# Keep that in sync so the active player can play into their zones.
	if card_manager and "current_player_id" in card_manager:
		card_manager.current_player_id = active_player_id


func _sync_flip_first_to_card_manager() -> void:
	if card_manager and "flip_first_player_id" in card_manager:
		card_manager.flip_first_player_id = flip_first_player_id


func get_flip_first_player_id() -> int:
	return flip_first_player_id


func set_flip_first_player_id(player_id: int) -> void:
	flip_first_player_id = player_id
	_sync_flip_first_to_card_manager()
	emit_signal("flip_first_changed", flip_first_player_id)
	_update_ui_indicators()
	print("Flip first changed to player: ", flip_first_player_id)


@rpc("authority", "call_local", "reliable")
func _sync_lane_assignment(lane_ids: Array) -> void:
	"""Server broadcasts the authoritative lane ID order [left, mid, right].
	Both server and client apply the same lane data."""
	if board_reference and board_reference.has_method("create_lanes_from_ids"):
		board_reference.create_lanes_from_ids(lane_ids)
	print("Lane assignment synced: ", lane_ids)


@rpc("authority", "call_local", "reliable")
func _sync_flip_first(network_player_id: int) -> void:
	"""Server broadcasts the authoritative flip_first as a network player id.
	Network player 0 = host, network player 1 = client.
	Locally, each player sees themselves as player 1 (bottom).
	So host maps: network 0 -> local 1 (me), network 1 -> local 0 (opponent).
	Client maps: network 0 -> local 0 (opponent), network 1 -> local 1 (me)."""
	var local_id: int
	if _is_online():
		var my_network_id = network_manager.get_network_player_id()
		if network_player_id == my_network_id:
			local_id = 1  # I have priority
		else:
			local_id = 0  # Opponent has priority
	else:
		local_id = network_player_id
	
	set_flip_first_player_id(local_id)
	print("Flip first synced: network_id=%d -> local_id=%d" % [network_player_id, local_id])


func check_lane_winners_and_update_flip_first() -> void:
	"""After Round End, check lane winners. Player winning 2+ of 3 lanes gets flip first.
	If tied on lanes, compare total power across all lanes. If still tied, random.
	In multiplayer, only the server decides and syncs via RPC."""
	if not board_reference:
		return
	
	# In online mode, only the server should decide
	if _is_online() and not multiplayer.is_server():
		return
	
	var player_0_lanes_won := 0
	var player_1_lanes_won := 0
	var total_power_0 := 0
	var total_power_1 := 0
	
	for col in range(3):  # 3 lanes
		var power_0 := _get_zone_total_power(Vector2i(col, 0))
		var power_1 := _get_zone_total_power(Vector2i(col, 1))
		total_power_0 += power_0
		total_power_1 += power_1
		
		if power_0 > power_1:
			player_0_lanes_won += 1
		elif power_1 > power_0:
			player_1_lanes_won += 1
		# If equal, neither wins this lane
	
	print("Lane wins - Player 0: %d, Player 1: %d | Total power - P0: %d, P1: %d" % [player_0_lanes_won, player_1_lanes_won, total_power_0, total_power_1])
	
	# Determine winner as network player id (0 = host side, 1 = client side)
	# On the server, row 0 = opponent (client, network 1), row 1 = me (host, network 0)
	# So server's local player_0 (row 0) is actually network player 1
	# and server's local player_1 (row 1) is network player 0
	var winner_network_id: int = -1
	
	if player_0_lanes_won > player_1_lanes_won:
		winner_network_id = _local_to_network_player(0)
	elif player_1_lanes_won > player_0_lanes_won:
		winner_network_id = _local_to_network_player(1)
	elif total_power_0 > total_power_1:
		winner_network_id = _local_to_network_player(0)
		print("Lanes tied, player in row 0 wins on total power.")
	elif total_power_1 > total_power_0:
		winner_network_id = _local_to_network_player(1)
		print("Lanes tied, player in row 1 wins on total power.")
	else:
		winner_network_id = randi_range(0, 1)
		print("Lanes and total power tied, flip first randomly reassigned.")
	
	if _is_online():
		rpc("_sync_flip_first", winner_network_id)
	else:
		set_flip_first_player_id(winner_network_id)


func _get_zone_total_power(zone_key: Vector2i) -> int:
	"""Calculate total power of all RESOLVED cards in a zone (includes power_modifier).
	Unresolved (face-down) cards are excluded from the lane power display."""
	if not board_reference:
		return 0
	var cards = board_reference.get_cards_in_zone(zone_key)
	var total := 0
	for card in cards:
		if not is_instance_valid(card):
			continue
		# Skip face-down cards — they haven't been revealed yet
		if "is_resolved" in card and not card.is_resolved:
			continue
		if card.has_method("get_current_power"):
			total += card.get_current_power()
		else:
			var card_data = CardDatabase.CARDS.get(str(card.card_id), null)
			if card_data and "Power" in card_data:
				total += int(card_data.get("Power", 0))
	return total


# ----------------------------
# Mana API (reusable by others)
# ----------------------------

func get_player_max_mana(player_id: int) -> int:
	var state: PlayerManaState = _mana_by_player.get(player_id)
	return state.get_max_mana() if state else 0


func get_player_current_mana(player_id: int) -> int:
	var state: PlayerManaState = _mana_by_player.get(player_id)
	return state.current_mana if state else 0


func set_player_bonus_max_mana(player_id: int, bonus: int, refill: bool = true) -> void:
	var state: PlayerManaState = _mana_by_player.get(player_id)
	if not state:
		return
	state.bonus_max_mana = bonus
	if refill:
		state.current_mana = state.get_max_mana()
	else:
		state.clamp_current_to_max()
	_emit_mana(player_id)
	_update_ui_indicators()


func add_player_bonus_max_mana(player_id: int, delta: int, refill: bool = true) -> void:
	set_player_bonus_max_mana(player_id, get_player_bonus_max_mana(player_id) + delta, refill)


func get_player_bonus_max_mana(player_id: int) -> int:
	var state: PlayerManaState = _mana_by_player.get(player_id)
	return state.bonus_max_mana if state else 0


func refill_player_mana(player_id: int) -> void:
	var state: PlayerManaState = _mana_by_player.get(player_id)
	if not state:
		return
	state.current_mana = state.get_max_mana()
	_emit_mana(player_id)
	_update_ui_indicators()


func spend_player_mana(player_id: int, amount: int) -> bool:
	# Optional helper for later card costs.
	if amount <= 0:
		return true
	var state: PlayerManaState = _mana_by_player.get(player_id)
	if not state:
		return false
	if state.current_mana < amount:
		return false
	state.current_mana -= amount
	_emit_mana(player_id)
	_update_ui_indicators()
	return true


func _apply_turn_based_mana_growth(new_turn_number: int) -> void:
	# Base max mana follows turn number (1->1, 2->2, ...)
	for player_id in _mana_by_player.keys():
		var state: PlayerManaState = _mana_by_player[player_id]
		state.base_max_mana = max(1, new_turn_number)
		state.clamp_current_to_max()
		_emit_mana(player_id)


func _refill_all_players_mana() -> void:
	for player_id in _mana_by_player.keys():
		refill_player_mana(player_id)


# --- Temporary bonus mana (reusable) ---

func add_temp_bonus_mana(player_id: int, amount: int) -> void:
	"""Queue bonus mana that the player receives at the start of NEXT turn.
	The bonus lasts for one turn only, then is automatically removed."""
	if not _pending_bonus_mana.has(player_id):
		_pending_bonus_mana[player_id] = 0
	_pending_bonus_mana[player_id] += amount
	print("Queued +%d temp bonus mana for player %d next turn" % [amount, player_id])


func _apply_pending_bonus_mana() -> void:
	"""Move pending bonus into active and add to player's max mana."""
	for player_id in _pending_bonus_mana.keys():
		var amount: int = _pending_bonus_mana[player_id]
		if amount <= 0:
			continue
		if not _active_temp_mana.has(player_id):
			_active_temp_mana[player_id] = 0
		_active_temp_mana[player_id] += amount
		add_player_bonus_max_mana(player_id, amount, false)  # don't refill yet, refill happens after
		print("Applied +%d temp bonus mana to player %d" % [amount, player_id])
	_pending_bonus_mana.clear()


func _expire_temp_bonus_mana() -> void:
	"""Remove any active temp bonus from the previous turn."""
	for player_id in _active_temp_mana.keys():
		var amount: int = _active_temp_mana[player_id]
		if amount <= 0:
			continue
		add_player_bonus_max_mana(player_id, -amount, false)
		print("Expired -%d temp bonus mana from player %d" % [amount, player_id])
	_active_temp_mana.clear()


func _emit_mana(player_id: int) -> void:
	var state: PlayerManaState = _mana_by_player.get(player_id)
	if not state:
		return
	emit_signal("mana_changed", player_id, state.current_mana, state.get_max_mana())


# ----------------------------
# End Turn Button
# ----------------------------

func _on_end_turn_button_pressed() -> void:
	end_play_phase()


func _is_online() -> bool:
	"""Check if we are in a multiplayer session"""
	if network_manager and network_manager.has_method("is_online"):
		return network_manager.is_online()
	return false


func _local_to_network_player(local_player_id: int) -> int:
	"""Convert a local player id (0=top row, 1=bottom row) to a network player id.
	Each player sees themselves as row 1 (bottom), so:
	  - Host: local 1 = network 0 (host), local 0 = network 1 (client)
	  - Client: local 1 = network 1 (client), local 0 = network 0 (host)
	This is only called on the server (host), so local 1 = network 0, local 0 = network 1."""
	if _is_online():
		return 1 - local_player_id  # Host: my row 1 is network 0, opponent row 0 is network 1
	return local_player_id


# ----------------------------
# Optional UI indicator updates
# ----------------------------

func _update_ui_indicators() -> void:
	if turn_text and "text" in turn_text:
		if game_phase == GamePhase.GAME_END:
			turn_text.text = "Game End"
		else:
			turn_text.text = "Turn: %d" % turn_number

	if mana_text and "text" in mana_text:
		var cur := get_player_current_mana(mana_indicator_player_id)
		var mx := get_player_max_mana(mana_indicator_player_id)
		mana_text.text = "Mana: %d/%d" % [cur, mx]

	if flip_first_text and "text" in flip_first_text:
		if flip_first_player_id == 1:
			flip_first_text.text = "Priority: You"
		elif flip_first_player_id == 0:
			flip_first_text.text = "Priority: Opponent"
		else:
			flip_first_text.text = "Priority: —"

	# Disable button when not in PLAY phase
	if end_turn_button:
		end_turn_button.disabled = not (game_phase == GamePhase.TURN_LOOP and round_phase == RoundPhase.PLAY)


func _update_zone_power_display() -> void:
	"""Update zone power text labels on the board."""
	if not board_reference or not board_reference.has_method("update_zone_power_texts"):
		return
	
	var power_by_zone := {}
	for col in range(3):
		for row in range(2):
			var zone_key := Vector2i(col, row)
			power_by_zone[zone_key] = _get_zone_total_power(zone_key)
	
	board_reference.update_zone_power_texts(power_by_zone)


func _set_text_if_possible(node: Node, text_value: String) -> void:
	if not node:
		return
	if "text" in node:
		node.text = text_value
