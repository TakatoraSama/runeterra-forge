extends Node

const MINI_CARD = preload("res://Scenes/MiniCard.tscn")
const REGIONS := ["Bandle City", "Bilgewater", "Demacia", "Freljord",
	"Ionia", "Ixtal", "Noxus", "Piltover Zaun", "Runeterra", "Shadow Isles", "Shurima", "Targon", "Void"]
const REGION_ICON_MAP := {
	"Bandle City": "res://Assets/RegionSprites/BandleCity.webp",
	"Bilgewater": "res://Assets/RegionSprites/Bilgewater.webp",
	"Demacia": "res://Assets/RegionSprites/Demacia.webp",
	"Freljord": "res://Assets/RegionSprites/Freljord.webp",
	"Ionia": "res://Assets/RegionSprites/Ionia.webp",
	"Ixtal": "res://Assets/RegionSprites/Ixtal.webp",
	"Noxus": "res://Assets/RegionSprites/Noxus.webp",
	"Piltover Zaun": "res://Assets/RegionSprites/PiltoverZaun.webp",
	"Runeterra": "res://Assets/RegionSprites/Runeterra.webp",
	"Shadow Isles": "res://Assets/RegionSprites/ShadowIsles.webp",
	"Shurima": "res://Assets/RegionSprites/Shurima.webp",
	"Targon": "res://Assets/RegionSprites/Targon.webp",
	"Void": "res://Assets/RegionSprites/Void.webp",
}

var _all_cards: Array = []
var _active_regions: Array = []
var _active_costs: Array = []
var _search: String = ""

@onready var _grid: GridContainer = $UI/VBox/ScrollContainer/Grid
@onready var _search_field: LineEdit = $UI/VBox/FilterBar/SearchField
@onready var _region_bar: HBoxContainer = $UI/VBox/FilterBar/RegionBar
@onready var _cost_bar: HBoxContainer = $UI/VBox/FilterBar/CostBar
@onready var _card_preview: Node = $CardPreview


func _ready() -> void:
	_all_cards = CardDatabase.get_collectible_cards()
	_build_region_buttons()
	_build_cost_buttons()
	_rebuild_grid()


func _build_region_buttons() -> void:
	for region in REGIONS:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.tooltip_text = region
		var icon_path: String = REGION_ICON_MAP.get(region, "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			btn.icon = load(icon_path)
		btn.custom_minimum_size = Vector2(40, 40)
		btn.add_theme_constant_override("icon_max_width", 32)
		btn.toggled.connect(_on_region_toggled.bind(region))
		_region_bar.add_child(btn)


func _build_cost_buttons() -> void:
	var costs := ["1", "2", "3", "4", "5", "6+"]
	for cost_label in costs:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = cost_label
		btn.custom_minimum_size = Vector2(40, 40)
		btn.toggled.connect(_on_cost_toggled.bind(cost_label))
		_cost_bar.add_child(btn)


func _get_column_size() -> Vector2i:
	const COLS := 7
	const H_SEP := 8
	const H_MARGIN := 32  # 16px left + 16px right from VBox offsets
	var vp_w: int = int(get_viewport().get_visible_rect().size.x)
	var col_w: int = (vp_w - H_MARGIN - H_SEP * (COLS - 1)) / COLS
	var col_h: int = int(col_w * 176.0 / 126.0)
	return Vector2i(col_w, col_h)


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

	var col_size := _get_column_size()
	var filtered := _filter(_all_cards)
	for card_data in filtered:
		var mc: Control = MINI_CARD.instantiate()
		_grid.add_child(mc)
		mc.setup(card_data["id"])
		mc.set_display_size(col_size.x, col_size.y)
		mc.card_clicked.connect(_on_card_clicked)
		mc.card_right_clicked.connect(_on_card_clicked)


func _filter(cards: Array) -> Array:
	return cards.filter(func(card):
		if not _active_regions.is_empty():
			var regions: Array = card.get("Region", [])
			var match_region := false
			for r in _active_regions:
				if r in regions:
					match_region = true
					break
			if not match_region:
				return false

		if not _active_costs.is_empty():
			var cost: int = card.get("Cost", 0)
			var match_cost := false
			for c in _active_costs:
				if c == "6+" and cost >= 6:
					match_cost = true
				elif c != "6+" and cost == int(c):
					match_cost = true
			if not match_cost:
				return false

		if _search != "":
			var name: String = card.get("Name", "").to_lower()
			if not name.contains(_search.to_lower()):
				return false

		return true)


func _on_region_toggled(pressed: bool, region: String) -> void:
	if pressed:
		_active_regions.append(region)
	else:
		_active_regions.erase(region)
	_rebuild_grid()


func _on_cost_toggled(pressed: bool, cost_label: String) -> void:
	if pressed:
		_active_costs.append(cost_label)
	else:
		_active_costs.erase(cost_label)
	_rebuild_grid()


func _on_search_changed(new_text: String) -> void:
	_search = new_text
	_rebuild_grid()


func _on_card_clicked(card_id: String) -> void:
	if _card_preview and _card_preview.has_method("show_preview_by_id"):
		_card_preview.show_preview_by_id(card_id)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/HomeScreen.tscn")
