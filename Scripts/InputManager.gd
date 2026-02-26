extends Node2D

signal left_mouse_button_clicked
signal left_mouse_button_released
signal card_right_clicked(card)

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_DECK = 4

var card_manager_reference
var deck_reference
var card_preview_reference  # Set in _ready; used to block game input while preview is open
var board_reference

func _ready() -> void:
	card_manager_reference = $"../CardManager"
	deck_reference = $"../Deck"
	board_reference = $"../Board"
	card_preview_reference = get_parent().get_node_or_null("CardPreview")

func _input(event):
	# Block game-world input while the card preview overlay is open
	if card_preview_reference and card_preview_reference.visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			emit_signal("left_mouse_button_clicked")
			raycast_at_cursor()
		else:
			emit_signal("left_mouse_button_released")

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_handle_right_click()

func raycast_at_cursor():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	var result = space_state.intersect_point(parameters)
	# Scan all results: an Elusive card and its slot overlap exactly, so result[0]
	# may be the slot (mask=2) instead of the card (mask=1). Check every hit.
	for r in result:
		var mask = r.collider.collision_mask
		if mask == COLLISION_MASK_CARD:
			var card_found = r.collider.get_parent()
			if card_found:
				card_manager_reference.start_drag(card_found)
			return
		elif mask == COLLISION_MASK_DECK:
			# Click-to-draw disabled — auto-draw is handled by GameManager now.
			# deck_reference.draw_card()
			print("Deck clicked. Cards left: ", deck_reference.player_deck.size())
			return

func _handle_right_click() -> void:
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	var card = null
	if result.size() > 0:
		card = _get_card_with_highest_z(result)
	else:
		# In-play cards have Area2D disabled; use geometric hit test fallback.
		card = _get_in_play_card_at_cursor()
	if card:
		emit_signal("card_right_clicked", card)

func _get_card_with_highest_z(results: Array):
	var best = results[0].collider.get_parent()
	for i in range(1, results.size()):
		var c = results[i].collider.get_parent()
		if c.z_index > best.z_index:
			best = c
	return best

func _get_in_play_card_at_cursor() -> Node:
	if board_reference == null or not board_reference.has_method("get_cards_in_zone"):
		return null

	var mouse_pos := get_global_mouse_position()
	var best_card: Node = null
	var best_z := -999999

	for zone_cards in board_reference.cards_by_zone.values():
		for card in zone_cards:
			if card == null or not is_instance_valid(card):
				continue
			if not ("card_slot_is_in" in card) or card.card_slot_is_in == null:
				continue

			# Card scene base size is 630x880 at scale 1.0
			var card_size := Vector2(630.0 * card.scale.x, 880.0 * card.scale.y)
			var card_rect := Rect2(card.global_position - card_size * 0.5, card_size)
			if card_rect.has_point(mouse_pos):
				if card.z_index >= best_z:
					best_z = card.z_index
					best_card = card

	return best_card
