extends CanvasLayer

# Scale applied to the preview card node.
# Internal sprites are at 0.2 scale, so PREVIEW_SCALE=5 makes them render at
# exactly 1.0 (native texture resolution) → perfectly sharp, zero blur.
const PREVIEW_SCALE := 1.0

@onready var background: ColorRect = $Background
@onready var close_button: Button = $CloseButton
@onready var card_container: Node2D = $CardContainer
@onready var prev_button: Button = $PrevButton
@onready var next_button: Button = $NextButton
@onready var page_label: Label = $PageLabel

var _preview_card: Node = null

# Navigation state
var _tooltip_ids: Array = []   # Array[String] — card IDs built from PreviewTooltip
var _tooltip_index: int = 0
var _source_card: Node = null  # The originally right-clicked card (for live power display)


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close)
	background.gui_input.connect(_on_background_gui_input)
	prev_button.pressed.connect(_on_prev)
	next_button.pressed.connect(_on_next)

	# Wire up the right-click signal from InputManager
	var input_mgr = get_parent().get_node_or_null("InputManager")
	if input_mgr == null:
		input_mgr = get_node_or_null("/root/Main/InputManager")
	if input_mgr and not input_mgr.card_right_clicked.is_connected(show_card_preview):
		input_mgr.card_right_clicked.connect(show_card_preview)


# ── Public API ───────────────────────────────────────────────────────────────

func show_card_preview(source_card: Node) -> void:
	_source_card = source_card
	var card_id := str(source_card.card_id)
	var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})

	# Build the tooltip list from PreviewTooltip (int array → string array)
	var raw_tooltip: Array = card_data.get("PreviewTooltip", [])
	if raw_tooltip.is_empty():
		_tooltip_ids = [card_id]
	else:
		_tooltip_ids = []
		for id in raw_tooltip:
			_tooltip_ids.append(str(id))

	# Find which index in the list corresponds to the clicked card
	var start_idx := 0
	for i in range(_tooltip_ids.size()):
		if _tooltip_ids[i] == card_id:
			start_idx = i
			break

	_show_at_index(start_idx)
	visible = true


# ── Internals ────────────────────────────────────────────────────────────────

func _show_at_index(index: int) -> void:
	_tooltip_index = index
	_clear_preview()

	var card_id = _tooltip_ids[index]
	var card_scene: PackedScene = load("res://Scenes/Card.tscn")
	var preview := card_scene.instantiate()

	# Scale so internal 0.2-scale sprites hit exactly 1.0 → no blur
	preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview.position = Vector2.ZERO  # CardContainer is already screen-centred

	# Disable physics so it doesn't interfere with the game world
	var col := preview.get_node_or_null("Area2D/CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)
	var area := preview.get_node_or_null("Area2D")
	if area:
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)

	card_container.add_child(preview)
	_preview_card = preview

	# Pass the live source_card only when it matches the displayed card ID
	# (so live power values appear on the original card; static data used for others)
	var source: Node = null
	if _source_card != null and str(_source_card.card_id) == card_id:
		source = _source_card

	_populate(preview, card_id, source)

	# Update navigation button states
	prev_button.disabled = (index == 0)
	next_button.disabled = (index == _tooltip_ids.size() - 1)
	page_label.text = str(index + 1) + " / " + str(_tooltip_ids.size())


func _clear_preview() -> void:
	if _preview_card and is_instance_valid(_preview_card):
		_preview_card.queue_free()
	_preview_card = null


func _populate(preview: Node, card_id: String, source: Node = null) -> void:
	var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if card_data.is_empty():
		return

	CardDatabase.populate_card_visuals(preview, card_data, source)

	# ── Show front, hide back ───────────────────────────────────────────────
	var card_back := preview.get_node_or_null("CardBack")
	if card_back:
		card_back.visible = false


func _on_prev() -> void:
	if _tooltip_index > 0:
		_show_at_index(_tooltip_index - 1)


func _on_next() -> void:
	if _tooltip_index < _tooltip_ids.size() - 1:
		_show_at_index(_tooltip_index + 1)


func _on_close() -> void:
	visible = false
	_clear_preview()
	_tooltip_ids = []
	_source_card = null


func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_close()


# ESC key closes the preview from anywhere
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
