extends Node2D

## Input only: turns drags/drops and button presses into MatchIntents.
##
## The Match engine owns every rule; this script only turns input into intents and
## asks the PRESENTER whether a drag may start. It deliberately does NOT read
## controller.state: a guest holds no MatchState, so every gate here has to be
## answerable from the view. There is exactly one game path — engine mode.
## `current_player_id` is kept because MatchPresenter.setup() assigns it.

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2
const DEFAULT_CARD_MOVE_SPEED = 0.1
const DEFAULT_CARD_SCALE = 0.2
const CARD_BIGGER_SCALE = 0.21
const CARD_SMALLER_SCALE = 0.15
const CARD_BOARD_Z_INDEX = 0

var screen_size
var card_being_dragged
var is_hovering_on_card
var player_hand_reference
var board_reference
var current_player_id: int = 1  # Local player id, assigned by MatchPresenter.setup()
var undo_button: Button
var end_turn_button: Button
var _is_swap_drag: bool = false           # True when dragging an Elusive board card for a lane swap
var _swap_drag_origin_slot = null         # The slot the Elusive card came from
var _swap_drag_origin_zone: Vector2i = Vector2i(-1, -1)  # The zone the Elusive card came from


const TOAST_FADE_TIME := 1.5
const TOAST_FONT_SIZE := 26
const TOAST_COLOR := Color(1.0, 0.85, 0.3, 1.0)


## The MatchController node, or null while there is no match (e.g. the lobby).
func _match_controller() -> Node:
	if MatchController.active():
		return get_node_or_null("/root/Main/MatchController")
	return null


## The MatchPresenter node (view only), or null while there is no match.
func _match_presenter() -> Node:
	if _match_controller():
		return get_node_or_null("/root/Main/MatchPresenter")
	return null


## The engine instance id a card node stands for, or -1 when the presenter has none for
## it (a preview card, a card the view only knows face-down, or no presenter at all).
func _engine_instance_id(card) -> int:
	var presenter := _match_presenter()
	if presenter == null:
		return -1
	return int(presenter.call("instance_of", card))


## The screen row the LOCAL player's cards sit on. The board has no absolute ids:
## the row is a constant here rather than something derived per drop, so a host
## (absolute player 0) still plays on the bottom row exactly as an offline human does.
const ENGINE_OWN_ROW := 1


## Engine gate for swap-dragging a board card: the card must be ours, resolved and
## Elusive, not stunned, with no swap queued yet — the presenter's view model answers
## all of that, which is what lets a guest with no MatchState drag its own Elusive.
## Stun is deliberately NOT excluded: the engine rejects a stunned swap with reason
## "stunned", which the presenter turns into a toast and a snap back. The presenter
## does check it (so a stunned card does not start a drag), and the engine stays the
## authority on the final word.
func _engine_can_start_swap_drag(card) -> bool:
	var presenter := _match_presenter()
	if presenter == null:
		return false
	var instance_id := _engine_instance_id(card)
	if instance_id < 0:
		return false
	return bool(presenter.call("can_start_swap", instance_id))


## Small centred message under the cards, fading out.
func _show_toast(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", TOAST_FONT_SIZE)
	label.add_theme_color_override("font_color", TOAST_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 6)
	label.size = Vector2(700, 40)
	label.position = Vector2(610, 1010)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 50
	add_child(label)
	var tween := create_tween()
	tween.tween_interval(TOAST_FADE_TIME - 0.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	await tween.finished
	label.queue_free()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	screen_size = get_viewport_rect().size
	player_hand_reference = $"../PlayerHand"
	board_reference = $"../Board"
	$"../InputManager".connect("left_mouse_button_released", on_left_click_released)
	undo_button = $Undo
	undo_button.pressed.connect(_on_undo_button_pressed)
	undo_button.disabled = true
	# End Turn lives here next to Undo: one press is one end_turn intent, and the
	# presenter (which already holds this same button) owns the disabled state.
	end_turn_button = $Button
	end_turn_button.pressed.connect(_on_end_turn_button_pressed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		card_being_dragged.position = Vector2(clamp(mouse_pos.x, 0, screen_size.x), clamp(mouse_pos.y, 0, screen_size.y))

func start_drag(card):
	# No match (lobby): nothing to drag into.
	if _match_controller() == null:
		return
	# Only the play phase and the swap gate are checked here — mana,
	# stun and every other rule are the engine's to answer.
	_start_drag_engine(card)


func _start_drag_engine(card) -> void:
	"""Drag start. The board model belongs to the presenter, so the
	origin slot is NOT freed here — only the drag bookkeeping is set up."""
	var controller := _match_controller()
	if controller == null or not controller.is_play_phase():
		return
	if card.card_slot_is_in:
		if not _engine_can_start_swap_drag(card):
			return
		_is_swap_drag = true
		_swap_drag_origin_slot = card.card_slot_is_in
		_swap_drag_origin_zone = board_reference.get_zone_for_slot(_swap_drag_origin_slot)
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


func _finish_swap_drag() -> void:
	"""Handle releasing a swap drag: a valid drop becomes a swap_card intent,
	an invalid one snaps back to the origin slot."""
	_finish_swap_drag_engine()


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


func _finish_swap_drag_engine() -> void:
	"""Swap release. A valid drop becomes a swap_card intent; the engine
	keeps the card in its origin zone until SWAP_LANE and the presenter lays it out in
	the destination. An invalid drop snaps back.

	On a valid drop the card is immediately taken to BOARD size and parked on the
	destination slot, rather than being left where it was dropped. _process would
	otherwise keep following the mouse, and between the drop and swap_started arriving
	the card would sit there at DRAG size (0.2) instead of board size (0.15) — on a LAN
	guest that gap is a whole network round trip. Parking it on the free slot the drop
	landed on is the closest thing to the final display slot that is knowable here; the
	layout appends incoming swaps at the END of the destination zone, so the presenter
	still tweens it from here onto its real slot when swap_started lands."""
	_is_swap_drag = false
	var controller := _match_controller()
	var card = card_being_dragged
	var instance_id := _engine_instance_id(card)
	var dest_slot = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	var dest_zone: Vector2i = board_reference.get_zone_for_slot(dest_slot) if dest_slot else Vector2i(-1, -1)
	# Valid destination: our own row, a different column, a lane (not the spell zone).
	# The row is the SCREEN row, so ENGINE_OWN_ROW and not local_player_id — a host is
	# absolute player 0 and its cards belong on the bottom row all the same.
	if controller != null and instance_id >= 0 \
			and dest_zone != Vector2i(-1, -1) \
			and dest_zone.y == ENGINE_OWN_ROW \
			and dest_zone.x != _swap_drag_origin_zone.x \
			and dest_zone.x >= 0:
		# Detach BEFORE parking: _process moves card_being_dragged to the mouse every
		# frame and would drag the card straight back off the slot it was just parked on.
		card_being_dragged = null
		_swap_drag_origin_slot = null
		_swap_drag_origin_zone = Vector2i(-1, -1)
		card.scale = Vector2(CARD_SMALLER_SCALE, CARD_SMALLER_SCALE)
		if dest_slot:
			card.position = dest_slot.position
		card.z_index = CARD_BOARD_Z_INDEX
		controller.submit_local(MatchIntents.swap_card(instance_id, dest_zone.x))
		return
	# Invalid destination — return card to its origin slot
	_return_swap_card_to_origin()


func finish_drag():
	if _is_swap_drag:
		_finish_swap_drag()
		return
	# The drop becomes a play_card intent, the engine validates it.
	_finish_drag_engine()


func _finish_drag_engine() -> void:
	"""Drop. The drop slot resolves to a board zone (col, row); only our
	own row is playable, everything else goes back to the hand with a toast. The
	engine decides the rest (mana, card type, lane, turn) and the presenter either
	places the card or hands it back on intent_rejected."""
	if card_being_dragged == null:
		return
	var controller := _match_controller()
	if controller == null:
		_return_card_to_hand()
		return
	var card = card_being_dragged
	var instance_id := _engine_instance_id(card)
	var dest_slot = board_reference.get_next_available_slot_for_position(get_global_mouse_position())
	var zone_key: Vector2i = board_reference.get_zone_for_slot(dest_slot) if dest_slot else Vector2i(-1, -1)
	# ENGINE_OWN_ROW, not local_player_id: the drop row is a screen row, and a host is
	# absolute player 0 whose cards belong on the bottom row all the same.
	if instance_id < 0 or zone_key == Vector2i(-1, -1) or zone_key.y != ENGINE_OWN_ROW:
		if zone_key != Vector2i(-1, -1) and zone_key.y != ENGINE_OWN_ROW:
			_show_toast("Play on your side")
		_return_card_to_hand()
		return
	# Lane columns are 0..2, the spell zone is -1 (MatchState.SPELL_COL).
	card_being_dragged = null
	controller.submit_local(MatchIntents.play_card(instance_id, zone_key.x, -1))

func connect_card_signals(card):
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)


# ── Undo / End Turn ──────────────────────────────────────────────────────────

func _on_undo_button_pressed() -> void:
	# The engine owns the undo stack and refunds the mana itself;
	# the presenter sends the cards back to the hand in the right order.
	var controller := _match_controller()
	if controller == null:
		return
	if not controller.can_undo():
		return
	controller.submit_local(MatchIntents.undo())


func _on_end_turn_button_pressed() -> void:
	# One press is one end_turn intent; the engine decides what it means.
	var controller := _match_controller()
	if controller == null:
		return
	controller.submit_local(MatchIntents.end_turn())


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
