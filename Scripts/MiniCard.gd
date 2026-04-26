extends Control

signal card_clicked(card_id: String)
signal card_right_clicked(card_id: String)

const CARD_W := 126
const CARD_H := 176

var _card_id: String = ""
var _card_node: Node = null
var _viewport_container: SubViewportContainer = null


func setup(card_id: String) -> void:
	_card_id = card_id
	var data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if data.is_empty():
		return

	if _viewport_container:
		_viewport_container.queue_free()
		_viewport_container = null
		_card_node = null

	var card_scene: PackedScene = CardDatabase.get_card_scene(data)
	_card_node = card_scene.instantiate()
	_card_node.card_id = card_id
	# Card Node2D is centered on its own origin.
	# Position at (CARD_W/2, CARD_H/2) so the 126×176 visual fills the viewport.
	_card_node.position = Vector2(CARD_W / 2.0, CARD_H / 2.0)
	_card_node.scale = Vector2(0.2, 0.2)

	# SubViewport isolates the card from the UI z-index space.
	# Without it, card sprites at relative z=-11..-5 inside CardFront land at
	# absolute z < 0 in the CanvasLayer and are hidden behind panel backgrounds.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CARD_W, CARD_H)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	viewport.add_child(_card_node)

	CardDatabase.populate_card_visuals(_card_node, data)

	var card_back = _card_node.get_node_or_null("CardBack")
	if card_back:
		card_back.visible = false

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.add_child(viewport)

	add_child(_viewport_container)
	move_child(_viewport_container, 0)  # render behind Highlight


func set_in_deck(value: bool) -> void:
	$Highlight.visible = value


func set_display_size(w: int, h: int) -> void:
	custom_minimum_size = Vector2(w, h)
	if _viewport_container == null:
		return
	var vp := _viewport_container.get_child(0) as SubViewport
	if vp == null:
		return
	vp.size = Vector2i(w, h)
	if _card_node:
		var scale_factor: float = float(w) / float(CARD_W)
		_card_node.scale = Vector2(0.2 * scale_factor, 0.2 * scale_factor)
		_card_node.position = Vector2(w / 2.0, h / 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			card_clicked.emit(_card_id)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			card_right_clicked.emit(_card_id)
