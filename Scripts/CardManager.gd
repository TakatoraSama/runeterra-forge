extends Node2D

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const DEFAULT_CARD_MOVE_SPEED = 0.1
const DEFAULT_CARD_SCALE = 0.2
const CARD_BIGGER_SCALE = 0.21
const CARD_SMALLER_SCALE = 0.15
const CARD_PAUSE_TIMER = 0.7
const CARD_BOARD_Z_INDEX = 0

var screen_size
var card_being_dragged
var is_hovering_on_card
var player_hand_reference
var board_reference
var game_manager_reference
var network_manager_reference
var current_player_id: int = 1  # 0 = top player, 1 = bottom player (default)
var flip_first_player_id: int = -1  # Synced from GameManager
var played_cards_order: Array = []  # Cards played this turn only (cleared after resolve)
var all_cards_in_play_order: Array = []  # Historical: all cards that ever entered the board (append-only, never removed)
var opponent_played_cards: Array = []  # Cards opponent played (face-down until resolve)
var _pending_opponent_cards: Array = []  # Deferred opponent card data [{card_id, zone_col, zone_row}]
var killed_cards: Array = []  # Tracks all cards killed during the game [{card_id, owner_player_id, killer_player_id, killer_card_id}]
var summoned_cards: Array = []  # Tracks all cards that entered the board [{card_id, owner_player_id, was_played_from_hand}]
var created_cards: Array = []  # Tracks all cards created (not from starting deck) [{card_id, owner_player_id, creator_player_id, creator_card_id, created_at_turn}]
var opponent_hand_card_ids: Array = []  # Synced from opponent via RPC for behold calculations
var _level_up_in_progress: bool = false  # Global lock: only one level-up animation plays at a time
var _is_swap_drag: bool = false           # True when dragging an Elusive board card for a lane swap
var _swap_drag_origin_slot = null         # The slot the Elusive card came from
var _swap_drag_origin_zone: Vector2i = Vector2i(-1, -1)  # The zone the Elusive card came from
var _pending_opponent_swaps: Array = []  # Deferred opponent swap data [{card_id, from_col, to_col}] — applied at SWAP_LANE phase


# Lightweight proxy for opponent hand cards that don't exist as scene nodes on this client.
# Exposes .card_id and .owner_player_id so behold consumers can treat it like a Card.
class BeheldCardProxy extends RefCounted:
	var card_id: String = ""
	var owner_player_id: int = -1
	var _is_proxy: bool = true  # distinguishes from real Card nodes


func _notify_zone_power_changed() -> void:
	"""Recalculate auras via AuraSystem, then ask GameManager to refresh zone power labels."""
	AuraSystem.recalculate_auras()
	if game_manager_reference and game_manager_reference.has_method("_update_zone_power_display"):
		game_manager_reference._update_zone_power_display()


func _wait_for_level_up() -> void:
	"""Suspend the current coroutine until any in-progress level-up animation finishes.
	Call this after any ability or level-up check that may have started _perform_level_up
	so the next card's ability doesn't fire while the animation is still playing."""
	while _level_up_in_progress:
		await get_tree().create_timer(0.05).timeout


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../PlayerHand"
	board_reference = $"../Board"
	game_manager_reference = $"../GameManager"
	network_manager_reference = $"../NetworkManager"
	$"../InputManager".connect("left_mouse_button_released", on_left_click_released)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		card_being_dragged.position = Vector2(clamp(mouse_pos.x, 0, screen_size.x), clamp(mouse_pos.y, 0, screen_size.y))
			
func start_drag(card):
	# Only allow dragging during PLAY phase
	if game_manager_reference and game_manager_reference.has_method("is_play_phase"):
		if not game_manager_reference.is_play_phase():
			return

	if card.card_slot_is_in:
		# Board card: only resolved Elusive cards owned by the local player can be swap-dragged
		if not card.is_resolved:
			return
		if not _has_elusive_keyword(card):
			return
		if card.owner_player_id != current_player_id:
			return
		if SwapLaneManager.has_pending_swap(card):
			return
		# Initiate swap drag: temporarily free the origin slot
		_is_swap_drag = true
		_swap_drag_origin_slot = card.card_slot_is_in
		_swap_drag_origin_zone = board_reference.get_zone_for_slot(_swap_drag_origin_slot)
		_swap_drag_origin_slot.card_in_slot = false
		card.card_slot_is_in = null
		board_reference.remove_card_from_zone(_swap_drag_origin_zone, card)
	else:
		_is_swap_drag = false

	card_being_dragged = card
	card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card.z_index = 10
	
func _return_card_to_hand():
	"""Reset card scale/z_index and return it to the player's hand."""
	card_being_dragged.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
	card_being_dragged.z_index = 2
	player_hand_reference.add_card_to_hand(card_being_dragged, DEFAULT_CARD_MOVE_SPEED)
	card_being_dragged = null

func cancel_active_drag() -> void:
	"""Cancel any card currently being dragged and return it to hand (or origin slot for swap drags)."""
	if card_being_dragged:
		if _is_swap_drag:
			_return_swap_card_to_origin()
		else:
			_return_card_to_hand()

func _has_elusive_keyword(card) -> bool:
	"""Return true if this card has the Elusive keyword."""
	var card_data = CardDatabase.CARDS.get(str(card.card_id), null)
	if not card_data:
		return false
	return "Elusive" in card_data.get("Keyword", [])


func _finish_swap_drag() -> void:
	"""Handle releasing a swap drag. Validates the destination and either registers
	the swap (card moves to dest slot temporarily) or cancels (card snaps to origin)."""
	_is_swap_drag = false
	var dest_slot = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	if dest_slot:
		var dest_zone = board_reference.get_zone_for_slot(dest_slot)
		# Valid destination: same player row, different column, owned by local player
		if dest_zone != Vector2i(-1, -1) \
				and dest_zone.y == _swap_drag_origin_zone.y \
				and dest_zone.x != _swap_drag_origin_zone.x \
				and board_reference.is_zone_owned_by_player(dest_zone, current_player_id):
			# Move card to destination temporarily (animate at SWAP_LANE phase)
			card_being_dragged.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
			card_being_dragged.card_slot_is_in = dest_slot
			dest_slot.card_in_slot = true
			board_reference.add_card_to_zone(dest_zone, card_being_dragged)
			card_being_dragged.position = dest_slot.position
			card_being_dragged.z_index = CARD_BOARD_Z_INDEX
			var card_id_str: String = card_being_dragged.card_id
			var from_col: int = _swap_drag_origin_zone.x
			var to_col: int = dest_zone.x
			SwapLaneManager.register_swap(
				card_being_dragged,
				_swap_drag_origin_zone, _swap_drag_origin_slot,
				dest_zone, dest_slot,
				current_player_id
			)
			board_reference.reposition_cards_in_zone(_swap_drag_origin_zone)
			board_reference.reposition_cards_in_zone(dest_zone)
			if _is_online():
				rpc("_receive_opponent_swap", card_id_str, from_col, to_col)
			card_being_dragged = null
			_swap_drag_origin_slot = null
			_swap_drag_origin_zone = Vector2i(-1, -1)
			return
	# Invalid destination — return card to its origin slot
	_return_swap_card_to_origin()


func _return_swap_card_to_origin() -> void:
	"""Snap the swap-dragged card back to its origin slot without any tween."""
	card_being_dragged.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
	_swap_drag_origin_slot.card_in_slot = true
	card_being_dragged.card_slot_is_in = _swap_drag_origin_slot
	board_reference.add_card_to_zone(_swap_drag_origin_zone, card_being_dragged)
	card_being_dragged.position = _swap_drag_origin_slot.position
	card_being_dragged.z_index = CARD_BOARD_Z_INDEX
	card_being_dragged = null
	_is_swap_drag = false
	_swap_drag_origin_slot = null
	_swap_drag_origin_zone = Vector2i(-1, -1)


func finish_drag():
	if _is_swap_drag:
		_finish_swap_drag()
		return
	var card_slot_found = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	if card_slot_found:
		# Check zone ownership before placing
		var zone_key = board_reference.get_zone_for_slot(card_slot_found)
		if zone_key != Vector2i(-1, -1):
			# Validate that the zone belongs to the current player
			if not board_reference.is_zone_owned_by_player(zone_key, current_player_id):
				print("Cannot place card in opponent's zone!")
				_return_card_to_hand()
				return

		# Check lane placement restriction (e.g. Noxkraya Arena turn 5)
		if LaneManager.is_placement_restricted(zone_key):
			print("Cards must be played in the active lane this turn (Noxkraya Arena)!")
			_return_card_to_hand()
			return

		# Validate it's currently PLAY phase (turn system)
		if game_manager_reference and game_manager_reference.has_method("is_play_phase"):
			if not game_manager_reference.is_play_phase():
				print("Cannot play cards right now (not in PLAY phase).")
				_return_card_to_hand()
				return

		# Mana check + spend
		var card_cost := 0
		if card_being_dragged and ("card_id" in card_being_dragged):
			var card_data = CardDatabase.CARDS.get(str(card_being_dragged.card_id), null)
			if card_data:
				card_cost = int(card_data.get("Cost", 0))
		if card_cost > 0 and game_manager_reference and game_manager_reference.has_method("spend_player_mana"):
			var ok = game_manager_reference.spend_player_mana(current_player_id, card_cost)
			if not ok:
				print("Not enough mana to play card. Need: ", card_cost)
				_return_card_to_hand()
				return
		
		card_being_dragged.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
		card_being_dragged.z_index = CARD_BOARD_Z_INDEX
		card_being_dragged.card_slot_is_in = card_slot_found
		player_hand_reference.remove_card_from_hand(card_being_dragged)
		card_being_dragged.position = card_slot_found.position
		if not _has_elusive_keyword(card_being_dragged):
			card_being_dragged.get_node("Area2D/CollisionShape2D").disabled = true
		card_slot_found.card_in_slot = true
		
		# Set card ownership
		card_being_dragged.owner_player_id = current_player_id
		
		# Register card in zone tracking
		if zone_key != Vector2i(-1, -1):
			board_reference.add_card_to_zone(zone_key, card_being_dragged)

		# Queue for resolve phase (abilities fire when card flips during resolve)
		played_cards_order.append(card_being_dragged)
		# Also add to persistent play order
		all_cards_in_play_order.append(card_being_dragged)
		# Track as summoned (was_played_from_hand = true)
		track_summoned_card(card_being_dragged, true)

		# Multiplayer: notify opponent about this card play (face-down)
		if _is_online() and zone_key != Vector2i(-1, -1):
			var card_id_str = str(card_being_dragged.card_id)
			# Send the zone mirrored: my row 1 -> their row 0 (opponent's top)
			var mirrored_zone = Vector2i(zone_key.x, 1 - zone_key.y)
			rpc("_receive_opponent_card_play", card_id_str, mirrored_zone.x, mirrored_zone.y)
		card_being_dragged = null
	else:
		_return_card_to_hand()


func resolve_played_cards() -> void:
	# Spawn any pending opponent cards (hidden during PLAY, shown now as face-down)
	_spawn_pending_opponent_cards()
	
	# Sort cards so flip_first player's cards resolve first
	var sorted_cards := _sort_cards_by_flip_first(played_cards_order)
	
	# First pass: show ALL cards as face-down (card back covering front)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		if card.has_method("set_card_back_z_index"):
			card.set_card_back_z_index(5)
	
	# Brief pause so players can see all cards face-down before flipping
	await get_tree().create_timer(0.5).timeout

	# Second pass: flip and trigger abilities one by one in flip_first order
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		var anim_player = card.get_node_or_null("AnimationPlayer")
		if anim_player:
			anim_player.play("card_flip_play")
			await anim_player.animation_finished
		if card.has_method("hide_card_back"):
			card.hide_card_back()
		else:
			var card_back = card.get_node_or_null("CardBack")
			if card_back:
				card_back.visible = false
		# Mark card as resolved before triggering abilities so other cards
		# can see it, but cards later in the queue remain unresolved.
		card.is_resolved = true
		# Trigger ability after reveal/flip animation
		card.on_summon()
		# Check if this resolve triggers any level-ups (e.g. Ice Pillar → Trundle)
		check_level_ups_after_resolve(card)
		# Wait for any level-up animation triggered by this resolve to finish
		await _wait_for_level_up()
		# Update zone power display after each card resolves
		_notify_zone_power_changed()
		# Pause between each card so play effects (e.g. card created in hand) can finish animating
		await get_tree().create_timer(CARD_PAUSE_TIMER).timeout
	played_cards_order.clear()
			
func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)
	
func on_left_click_released():
	if card_being_dragged:
		finish_drag()
	
func on_hovered_over_card(card):
	if !is_hovering_on_card: 
		is_hovering_on_card = true
		highlight_card(card, true)
	
func on_hovered_off_card(card):
	if !card.card_slot_is_in && !card_being_dragged:
		highlight_card(card, false)
		var new_card_hovered = raycast_check_for_card()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else:
			is_hovering_on_card = false
	
func highlight_card(card, hovered):
	if hovered:
		card.scale = Vector2(CARD_BIGGER_SCALE, CARD_BIGGER_SCALE)
		card.z_index = 3
	else:
		card.scale = Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE)
		card.z_index = 2

func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:		
		return result[0].collider.get_parent()
	return null

func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:		
		#return result[0].collider.get_parent()
		return get_card_with_highest_z_index(result)
	return null
	
func get_card_with_highest_z_index(cards):
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card


# Persistent play order management
func add_card_to_play_order(card) -> void:
	"""Add a card to the persistent play order (for summoned cards, etc.)"""
	if card and not all_cards_in_play_order.has(card):
		all_cards_in_play_order.append(card)


func recall_card(card) -> void:
	"""Return a board card to its owner's hand (Recall mechanic).
	Removes the card from its slot and zone, then animates it flying back to
	the local player's hand. Only adds to hand when the card belongs to the
	local player — opponent cards are simply removed from the board (the
	opponent's client manages their own hand).
	Reusable for any card ability that recalls an ally (Ahri, future cards…)."""
	if not is_instance_valid(card):
		return

	# Release slot and remove from zone tracking
	var zone_key := Vector2i(-1, -1)
	if card.card_slot_is_in:
		zone_key = board_reference.get_zone_for_slot(card.card_slot_is_in)
		card.card_slot_is_in.card_in_slot = false
	card.card_slot_is_in = null

	if zone_key != Vector2i(-1, -1):
		board_reference.remove_card_from_zone(zone_key, card)
		board_reference.reposition_cards_in_zone(zone_key)
		# Notify the opponent so their client removes the card from the same zone
		if _is_online():
			var mirrored_zone := Vector2i(zone_key.x, 1 - zone_key.y)
			rpc("_receive_opponent_recall", card.card_id, mirrored_zone.x, mirrored_zone.y)

	# Opponent cards are only removed from the board — do not add to local hand
	if card.owner_player_id != current_player_id:
		print("Recalled opponent card %s — removed from board" % card.card_id)
		return

	# Reset board state before the flight animation
	card.is_resolved = false
	card.z_index = 10  # elevated so it renders above other cards during flight

	# Re-enable collision so the card can be dragged from hand
	var col_shape = card.get_node_or_null("Area2D/CollisionShape2D")
	if col_shape:
		col_shape.disabled = false

	# Scale tween: board size (0.15) → hand size (0.2) over the flight duration
	var scale_tween = card.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	scale_tween.tween_property(card, "scale", Vector2(DEFAULT_CARD_SCALE, DEFAULT_CARD_SCALE), 0.8)

	# Position tween: fly from board position directly to the correct hand slot
	# (same mechanic as create_card_in_hand / Trundle Ice Pillar)
	player_hand_reference.add_card_to_hand(card, 0.8)

	await scale_tween.finished
	card.z_index = 2
	print("Recalled: %s to player %d's hand" % [card.card_id, card.owner_player_id])


func create_card_in_hand(card_id_to_create: String, creator_card_id: String = "", creator_player_id: int = -1) -> void:
	"""Create a card by ID and add it to the local player's hand. Reusable for any
	'create card in hand' ability (Trundle -> Ice Pillar, etc.).
	creator_card_id: which card created this (empty = unknown/no tracking).
	creator_player_id: which player created this (-1 = same as owner, -999 = unknown)."""
	var card_data = CardDatabase.CARDS.get(card_id_to_create)
	if not card_data:
		print("create_card_in_hand: unknown card id ", card_id_to_create)
		return

	var card_scene = load("res://Scenes/Card.tscn")
	var new_card = card_scene.instantiate()

	new_card.card_id = card_id_to_create
	new_card.owner_player_id = current_player_id  # belongs to the local player

	# Spawn at screen center so the player sees where it came from
	var viewport_size = get_viewport_rect().size
	new_card.position = Vector2(viewport_size.x / 2.0, viewport_size.y / 2.0)

	# Populate card visuals
	CardDatabase.populate_card_visuals(new_card, card_data)

	add_child(new_card)
	new_card.name = "Card"
	new_card.get_node("AnimationPlayer").play("card_flip")

	# Add to hand — this tweens the card from screen center to the hand position
	player_hand_reference.add_card_to_hand(new_card, 0.3)

	# Track as created card if creator info provided
	if creator_card_id != "":
		var creator_player = creator_player_id if creator_player_id != -1 else current_player_id
		track_created_card(new_card, creator_player, creator_card_id)

	print("Created card in hand: ", card_data.get("Name", ""), " (ID: ", card_id_to_create, ")")


func track_killed_card(card, killer_player_id: int = -1, killer_card_id: String = "") -> void:
	"""Record a killed card for ability tracking (e.g. Nasus level-up condition).
	killer_player_id: which player caused the kill (-1 = unknown/environment).
	killer_card_id: which card performed the kill (empty = unknown)."""
	if not is_instance_valid(card):
		return
	killed_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"killer_player_id": killer_player_id,
		"killer_card_id": killer_card_id
	})
	print("Card killed and tracked: %s (killed by player %d, card %s) (total killed: %d)" % [
		card.card_id, killer_player_id, killer_card_id, killed_cards.size()])
	# Re-check Nasus level-up immediately when a real kill is recorded.
	# This prevents delayed level-up until end-of-phase and keeps trigger order intuitive.
	LevelUpManager._check_nasus_levelup()


func track_summoned_card(card, was_played_from_hand: bool = false) -> void:
	"""Record a summoned card for ability tracking (e.g. Kennen level-up condition).
	was_played_from_hand: true if the card was dragged from hand to board,
	false if it was created/summoned directly onto the board."""
	if not is_instance_valid(card):
		return
	summoned_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"was_played_from_hand": was_played_from_hand
	})
	print("Card summoned tracked: %s (from_hand: %s, total: %d)" % [
		card.card_id, was_played_from_hand, summoned_cards.size()])


func track_created_card(card, creator_player_id: int, creator_card_id: String) -> void:
	"""Record a card that was created (not from starting deck).
	creator_player_id: which player created it (-1 = environment/lane effect).
	creator_card_id: which card created it (or lane ID for lane effects)."""
	if not is_instance_valid(card):
		return
	var game_manager = get_node_or_null("/root/Main/GameManager")
	var current_turn = 0
	if game_manager and "turn_number" in game_manager:
		current_turn = game_manager.turn_number

	created_cards.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner_player_id,
		"creator_player_id": creator_player_id,
		"creator_card_id": creator_card_id,
		"created_at_turn": current_turn
	})
	print("Card created tracked: %s (created by %s, creator: %s, turn: %d, total: %d)" % [
		card.card_id, creator_card_id, creator_player_id, current_turn, created_cards.size()])


func _sort_cards_by_flip_first(cards: Array) -> Array:
	"""Sort cards so that flip_first player's cards come first, preserving play order within each group."""
	if flip_first_player_id < 0:
		return cards  # No flip first set, use original order
	
	var first_player_cards: Array = []
	var second_player_cards: Array = []
	
	for card in cards:
		if not is_instance_valid(card):
			continue
		if card.owner_player_id == flip_first_player_id:
			first_player_cards.append(card)
		else:
			second_player_cards.append(card)
	
	var sorted: Array = []
	sorted.append_array(first_player_cards)
	sorted.append_array(second_player_cards)
	return sorted


# Trigger abilities in play order
func trigger_round_start_abilities() -> void:
	"""Trigger Round Start abilities for all cards in play order (flip first player first)"""
	var sorted_cards := _sort_cards_by_flip_first(all_cards_in_play_order)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		# Re-check: card may have been killed by a prior ability this phase (slot is cleared on kill)
		if not card.card_slot_is_in:
			continue
		if card.has_method("on_round_start"):
			var did_fire = await card.on_round_start()
			# Wait for any level-up triggered by this ability before continuing
			await _wait_for_level_up()
			if did_fire:
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout
	# After all round-start abilities, re-check state-based level-up conditions
	check_level_ups_after_abilities()
	await _wait_for_level_up()


func trigger_round_end_abilities() -> void:
	"""Trigger Round End abilities for all cards in play order (flip first player first)"""
	var sorted_cards := _sort_cards_by_flip_first(all_cards_in_play_order)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		# Re-check: card may have been killed by a prior ability this phase (slot is cleared on kill)
		if not card.card_slot_is_in:
			continue
		if card.has_method("on_round_end"):
			var did_fire = await card.on_round_end()
			# Wait for any level-up triggered by this ability before continuing
			await _wait_for_level_up()
			if did_fire:
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout
	# After all round-end abilities, re-check state-based level-up conditions
	check_level_ups_after_abilities()
	await _wait_for_level_up()


func trigger_game_end_abilities() -> void:
	"""Trigger Game End abilities for all cards in play order (flip first player first).
	Azir Lv3 causes other Ascended allies to fire their Game End a second time.
	A guard dictionary prevents any card from double-firing more than once,
	blocking infinite loops even if multiple Azir Lv3s somehow exist."""
	var sorted_cards := _sort_cards_by_flip_first(all_cards_in_play_order)

	# First pass — every card fires once (normal)
	for card in sorted_cards:
		if not is_instance_valid(card):
			continue
		# Re-check: card may have been killed by a prior ability this phase (slot is cleared on kill)
		if not card.card_slot_is_in:
			continue
		if card.has_method("on_game_end"):
			var did_fire = await card.on_game_end()
			# Wait for any level-up triggered by this ability before continuing
			await _wait_for_level_up()
			if did_fire:
				_notify_zone_power_changed()
				await get_tree().create_timer(CARD_PAUSE_TIMER).timeout

	# Second pass — Azir Lv3: other Ascended allies fire their Game End a second time
	# Guard set prevents any card from being double-fired more than once.
	var double_game_end_fired: Dictionary = {}

	for azir_card in all_cards_in_play_order:
		if not is_instance_valid(azir_card):
			continue
		if not azir_card.card_slot_is_in:  # killed earlier this phase
			continue
		if not azir_card.is_resolved:
			continue
		var azir_data = CardDatabase.CARDS.get(azir_card.card_id)
		if not azir_data:
			continue
		if azir_data.get("Name", "") != "Azir" or azir_data.get("Level", 1) != 3:
			continue

		var owner_id = azir_card.owner_player_id
		print("Azir Lv3: triggering second Game End for allied Ascended units (owner %d)" % owner_id)

		for card in sorted_cards:
			if not is_instance_valid(card) or card == azir_card:
				continue
			if not card.card_slot_is_in:  # card was killed earlier this phase
				continue
			if card.owner_player_id != owner_id:
				continue
			if not card.is_resolved:
				continue
			# Only Ascended subtype (case-insensitive)
			var c_data = CardDatabase.CARDS.get(card.card_id)
			if not c_data or c_data.get("SubType", "").to_lower() != "ascended":
				continue
			# Only if the card actually has a {Game End} in its skill text
			if not ("{Game End}" in c_data.get("Skill", "")):
				continue
			# Guard: skip if this card already received its bonus second fire this game
			if double_game_end_fired.has(card):
				continue
			double_game_end_fired[card] = true  # mark BEFORE firing to block re-entry
			if card.has_method("on_game_end"):
				var did_fire = await card.on_game_end()
				# Wait for any level-up triggered by this ability before continuing
				await _wait_for_level_up()
				if did_fire:
					_notify_zone_power_changed()
					await get_tree().create_timer(CARD_PAUSE_TIMER).timeout


# --- Multiplayer RPCs ---

@rpc("any_peer", "reliable")
func _receive_opponent_card_play(card_id: String, zone_col: int, zone_row: int) -> void:
	"""Receive opponent's card play. Store data to spawn at resolve time (hidden during PLAY)."""
	_pending_opponent_cards.append({
		"card_id": card_id,
		"zone_col": zone_col,
		"zone_row": zone_row
	})
	print("Opponent card play queued: ", card_id, " for zone: ", Vector2i(zone_col, zone_row))


@rpc("any_peer", "reliable")
func _receive_opponent_swap(card_id: String, from_col: int, to_col: int) -> void:
	"""Queue opponent's lane swap for deferred application at SWAP_LANE phase start.
	We do NOT move the card during PLAY phase so the local player never sees the
	opponent's card jump to a new lane before the swap animation plays."""
	_pending_opponent_swaps.append({"card_id": card_id, "from_col": from_col, "to_col": to_col})
	print("Opponent swap queued: '%s' col %d → col %d (applied at SWAP_LANE phase)" % [card_id, from_col, to_col])


@rpc("any_peer", "reliable")
func _receive_opponent_recall(card_id: String, zone_col: int, zone_row: int) -> void:
	"""Opponent recalled a card — remove it from our board view and reposition the zone.
	The card is freed entirely; the opponent's client handles adding it to their own hand."""
	var zone_key := Vector2i(zone_col, zone_row)
	var target_card = null
	for c in board_reference.get_cards_in_zone(zone_key):
		if is_instance_valid(c) and c.card_id == card_id:
			target_card = c
			break

	if not target_card:
		print("_receive_opponent_recall: '%s' not found in zone %s" % [card_id, str(zone_key)])
		return

	if target_card.card_slot_is_in:
		target_card.card_slot_is_in.card_in_slot = false
	target_card.card_slot_is_in = null
	board_reference.remove_card_from_zone(zone_key, target_card)
	board_reference.reposition_cards_in_zone(zone_key)
	target_card.queue_free()
	print("_receive_opponent_recall: removed '%s' from zone %s" % [card_id, str(zone_key)])


func apply_pending_opponent_swaps() -> void:
	"""Move each queued opponent card to its destination slot and register the swap.
	Called at the very start of SWAP_LANE phase, before execute_swaps() runs."""
	for data in _pending_opponent_swaps:
		var card_id: String = data["card_id"]
		var from_zone := Vector2i(data["from_col"], 0)  # opponent is always row 0 from our view
		var to_zone   := Vector2i(data["to_col"],   0)

		# Find the opponent's card in from_zone
		var card_to_swap = null
		for c in board_reference.get_cards_in_zone(from_zone):
			if is_instance_valid(c) and c.card_id == card_id:
				card_to_swap = c
				break

		if not card_to_swap:
			print("apply_pending_opponent_swaps: card '%s' not found in zone %s" % [card_id, str(from_zone)])
			continue

		var from_slot = card_to_swap.card_slot_is_in
		if not from_slot:
			print("apply_pending_opponent_swaps: card '%s' has no slot" % card_id)
			continue

		# Find a free slot in the destination zone
		var dest_slot = null
		for slot in board_reference.slots_by_zone.get(to_zone, []):
			if not slot.card_in_slot:
				dest_slot = slot
				break

		if not dest_slot:
			print("apply_pending_opponent_swaps: no free slot in zone %s for '%s'" % [str(to_zone), card_id])
			continue

		# Move card to destination so execute_swaps() can snap it back then tween forward
		board_reference.remove_card_from_zone(from_zone, card_to_swap)
		from_slot.card_in_slot = false
		card_to_swap.card_slot_is_in = dest_slot
		dest_slot.card_in_slot = true
		board_reference.add_card_to_zone(to_zone, card_to_swap)
		card_to_swap.position = dest_slot.position

		# Register so execute_swaps() includes this card
		SwapLaneManager.register_swap(card_to_swap, from_zone, from_slot, to_zone, dest_slot, 0)
		print("Opponent swap applied: '%s' zone %s → zone %s" % [card_id, str(from_zone), str(to_zone)])

	_pending_opponent_swaps.clear()


func _spawn_pending_opponent_cards() -> void:
	"""Spawn all pending opponent cards face-down on the board (called at resolve start)."""
	for data in _pending_opponent_cards:
		var card_id_str: String = data["card_id"]
		var zone_key = Vector2i(data["zone_col"], data["zone_row"])
		var zone_slots = board_reference.slots_by_zone.get(zone_key, [])

		var available_slot = null
		for slot in zone_slots:
			if not slot.card_in_slot:
				available_slot = slot
				break

		if not available_slot:
			print("No available slot for opponent card in zone: ", zone_key)
			continue

		var card_scene = load("res://Scenes/Card.tscn")
		var opp_card = card_scene.instantiate()

		opp_card.card_id = card_id_str
		opp_card.owner_player_id = 0  # Opponent is always player 0 from our view

		var card_data = CardDatabase.CARDS.get(card_id_str)
		if card_data:
			CardDatabase.populate_card_visuals(opp_card, card_data)

		opp_card.position = available_slot.position
		opp_card.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
		opp_card.z_index = 0
		opp_card.card_slot_is_in = available_slot
		opp_card.get_node("Area2D/CollisionShape2D").disabled = true

		# Spawn face-down
		if opp_card.has_method("set_card_back_z_index"):
			opp_card.set_card_back_z_index(5)

		add_child(opp_card)
		available_slot.card_in_slot = true

		board_reference.add_card_to_zone(zone_key, opp_card)

		played_cards_order.append(opp_card)
		all_cards_in_play_order.append(opp_card)
		opponent_played_cards.append(opp_card)
		# Track opponent's card as summoned (was_played_from_hand = true — they played it from their hand)
		track_summoned_card(opp_card, true)

		print("Opponent card spawned face-down: ", card_id_str, " in zone: ", zone_key)

	_pending_opponent_cards.clear()


# ---- Behold helpers ----

func get_beheld_cards(player_id: int) -> Array:
	"""Return all cards a player 'beholds' — cards in their hand + on the board.
	Behold includes unresolved cards (face-down on board).
	For the opponent, also includes synced hand card IDs (as BeheldCardProxy objects)."""
	var result: Array = []
	var seen: Dictionary = {}  # card instance -> true, to avoid duplicates

	# Cards in hand (local player's hand is tracked by PlayerHand)
	if player_id == current_player_id and player_hand_reference:
		for card in player_hand_reference.player_hand:
			if is_instance_valid(card):
				result.append(card)
				seen[card] = true

	# Cards on the board belonging to this player
	if board_reference:
		var ally_zones = board_reference.get_ally_zones(player_id)
		for zone_key in ally_zones:
			for card in board_reference.get_cards_in_zone(zone_key):
				if is_instance_valid(card) and not seen.has(card):
					result.append(card)
					seen[card] = true

	# Fallback: scan all CardManager children for cards belonging to this player
	# that weren't already found (catches cards in limbo)
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if not ("card_id" in child and "owner_player_id" in child):
			continue
		if child.owner_player_id == player_id and not seen.has(child):
			result.append(child)
			seen[child] = true

	# Opponent hand cards (synced via RPC, don't exist as scene nodes on this client)
	if player_id != current_player_id and opponent_hand_card_ids.size() > 0:
		for id in opponent_hand_card_ids:
			var proxy = BeheldCardProxy.new()
			proxy.card_id = id
			proxy.owner_player_id = player_id
			result.append(proxy)

	return result


func get_beheld_cards_filtered(player_id: int, filter_func: Callable) -> Array:
	"""Return beheld cards that pass a filter function.
	filter_func receives a card node and returns bool."""
	var all_beheld = get_beheld_cards(player_id)
	var filtered: Array = []
	for card in all_beheld:
		if filter_func.call(card):
			filtered.append(card)
	return filtered


func count_beheld_matching(player_id: int, filter_func: Callable) -> int:
	"""Count how many beheld cards pass the filter."""
	return get_beheld_cards_filtered(player_id, filter_func).size()


# ---- Level-up checks (delegated to LevelUpManager) ----

func check_level_ups_after_resolve(resolved_card) -> void:
	"""Called after each card resolves. Delegates to LevelUpManager."""
	LevelUpManager.check_level_ups_after_resolve(resolved_card)


func check_level_ups_after_abilities() -> void:
	"""Called after round-start / round-end ability loops. Delegates to LevelUpManager."""
	LevelUpManager.check_level_ups_after_abilities()


# ---- Aura system (see AuraSystem.gd) ----
# recalculate_auras() and individual _apply_aura_* methods have moved to AuraSystem.
# CardManager calls _notify_zone_power_changed() → AuraSystem.recalculate_auras().


func _is_online() -> bool:
	if network_manager_reference and network_manager_reference.has_method("is_online"):
		return network_manager_reference.is_online()
	return false


# ---- Opponent hand sync (for behold) ----

func sync_hand_data() -> void:
	"""Send current hand card IDs to the opponent so their behold calculations
	can include our hand cards. Called when ending a turn."""
	var ids: Array = []
	if player_hand_reference:
		for card in player_hand_reference.player_hand:
			if is_instance_valid(card):
				ids.append(card.card_id)
	if _is_online():
		rpc("_receive_opponent_hand_ids", ids)
		print("Synced hand data to opponent: %d cards %s" % [ids.size(), str(ids)])


@rpc("any_peer", "reliable")
func _receive_opponent_hand_ids(card_ids: Array) -> void:
	"""Receive opponent's hand card IDs for behold calculations."""
	opponent_hand_card_ids = card_ids
	print("Received opponent hand data: %d cards %s" % [card_ids.size(), str(card_ids)])
