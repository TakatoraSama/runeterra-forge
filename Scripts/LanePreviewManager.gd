extends CanvasLayer

const LANE_PREVIEW_SCALE := 3.0  # Lane.tscn is at game-world scale=1.0; needs upscaling for preview
const CARD_PREVIEW_SCALE := 1.0  # Matches CardPreviewManager (card internal scale 0.2 → 1.0 = 5×)

@onready var background: ColorRect = $Background
@onready var close_button: Button = $CloseButton
@onready var lane_container: Node2D = $LaneContainer
@onready var prev_button: Button = $PrevButton
@onready var next_button: Button = $NextButton
@onready var page_label: Label = $PageLabel

# _pages stores entries like "lane:RockfallPath" or "card:Chip"
var _pages: Array = []
var _page_index: int = 0
var _preview_node: Node = null
var _reveal_turn: int = -1  # -1 = revealed; >0 = turn number when lane reveals


func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close)
	background.gui_input.connect(_on_background_gui_input)
	prev_button.pressed.connect(_on_prev)
	next_button.pressed.connect(_on_next)

	var input_mgr = get_parent().get_node_or_null("InputManager")
	if input_mgr == null:
		input_mgr = get_node_or_null("/root/Main/InputManager")
	if input_mgr and not input_mgr.lane_right_clicked.is_connected(show_lane_preview):
		input_mgr.lane_right_clicked.connect(show_lane_preview)


# ── Public API ────────────────────────────────────────────────────────────────

func show_lane_preview(lane_id: String, reveal_turn: int) -> void:
	var lane_data: Dictionary = LaneDatabase.LANES.get(lane_id, {})
	if lane_data.is_empty():
		return

	_reveal_turn = reveal_turn
	_pages = ["lane:" + lane_id]
	if reveal_turn == -1:  # only show related cards if lane is revealed
		for card_id in lane_data.get("RelatedCard", []):
			_pages.append("card:" + str(card_id))

	_show_at_index(0)
	visible = true


# ── Internals ─────────────────────────────────────────────────────────────────

func _show_at_index(index: int) -> void:
	_page_index = index
	_clear_preview()

	var page: String = _pages[index]
	var id := page.substr(page.find(":") + 1)

	if page.begins_with("lane:"):
		_show_lane_page(id)
	else:
		_show_card_page(id)

	var multi := _pages.size() > 1
	prev_button.visible = multi
	next_button.visible = multi
	page_label.visible = multi
	if multi:
		prev_button.disabled = (index == 0)
		next_button.disabled = (index == _pages.size() - 1)
		page_label.text = str(index + 1) + " / " + str(_pages.size())


func _show_lane_page(lane_id: String) -> void:
	var lane_scene: PackedScene = load("res://Scenes/Lane.tscn")
	var preview := lane_scene.instantiate()

	preview.scale = Vector2(LANE_PREVIEW_SCALE, LANE_PREVIEW_SCALE)
	preview.position = Vector2.ZERO

	var area := preview.get_node_or_null("Area2D")
	if area:
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
	var col := preview.get_node_or_null("Area2D/CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)

	lane_container.add_child(preview)
	_preview_node = preview

	var name_node := preview.get_node_or_null("LaneName")
	var desc_node := preview.get_node_or_null("LaneDesc")
	var sprite_node := preview.get_node_or_null("LaneBase/LaneSprite")

	if _reveal_turn == -1:
		# Revealed — populate full visuals from LaneDatabase
		var lane_data: Dictionary = LaneDatabase.LANES.get(lane_id, {})
		if name_node:
			name_node.text = str(lane_data.get("Name", ""))
		if desc_node:
			desc_node.text = str(lane_data.get("Desc", ""))
		if sprite_node:
			var path := str(lane_data.get("Sprite", ""))
			if path != "":
				sprite_node.texture = load(path)
	else:
		# Hidden — mirror the placeholder the board shows
		if name_node:
			name_node.text = ""
		if desc_node:
			desc_node.text = "Will be revealed on turn %d" % _reveal_turn
		if sprite_node:
			sprite_node.texture = null


func _show_card_page(card_id: String) -> void:
	var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	var card_scene: PackedScene = CardDatabase.get_card_scene(card_data)
	var preview := card_scene.instantiate()

	preview.scale = Vector2(CARD_PREVIEW_SCALE, CARD_PREVIEW_SCALE)
	preview.position = Vector2.ZERO

	var col := preview.get_node_or_null("Area2D/CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)
	var area := preview.get_node_or_null("Area2D")
	if area:
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)

	lane_container.add_child(preview)
	_preview_node = preview

	var card_back := preview.get_node_or_null("CardBack")
	if card_back:
		card_back.visible = false

	if not card_data.is_empty():
		CardDatabase.populate_card_visuals(preview, card_data)


func _clear_preview() -> void:
	if _preview_node and is_instance_valid(_preview_node):
		_preview_node.queue_free()
	_preview_node = null


func _on_prev() -> void:
	if _page_index > 0:
		_show_at_index(_page_index - 1)


func _on_next() -> void:
	if _page_index < _pages.size() - 1:
		_show_at_index(_page_index + 1)


func _on_close() -> void:
	visible = false
	_clear_preview()
	_pages = []


func _on_background_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_close()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
