extends Node

const MINI_CARD = preload("res://Scenes/MiniCard.tscn")
const MAX_DECK := 12

const REGIONS := ["Bandle City", "Bilgewater", "Demacia", "Freljord",
	"Ionia", "Noxus", "Piltover Zaun", "Runeterra", "Shadow Isles", "Shurima", "Targon"]
const REGION_ICON_MAP := {
	"Bandle City": "res://Assets/RegionSprites/BandleCity.webp",
	"Bilgewater": "res://Assets/RegionSprites/Bilgewater.webp",
	"Demacia": "res://Assets/RegionSprites/Demacia.webp",
	"Freljord": "res://Assets/RegionSprites/Freljord.webp",
	"Ionia": "res://Assets/RegionSprites/Ionia.webp",
	"Noxus": "res://Assets/RegionSprites/Noxus.webp",
	"Piltover Zaun": "res://Assets/RegionSprites/PiltoverZaun.webp",
	"Runeterra": "res://Assets/RegionSprites/Runeterra.webp",
	"Shadow Isles": "res://Assets/RegionSprites/ShadowIsles.webp",
	"Shurima": "res://Assets/RegionSprites/Shurima.webp",
	"Targon": "res://Assets/RegionSprites/Targon.webp",
}

var _all_cards: Array = []
var _deck_cards: Array = []       # current (unsaved) deck [card_id, ...]
var _saved_deck_cards: Array = [] # last saved state
var _active_regions: Array = []
var _active_costs: Array = []
var _search: String = ""

@onready var _deck_grid: GridContainer     = $UI/HBox/DeckPanel/VBox/DeckScroll/DeckGrid
@onready var _deck_label: Label            = $UI/HBox/DeckPanel/VBox/DeckCountLabel
@onready var _name_field: LineEdit         = $UI/HBox/DeckPanel/VBox/Header/DeckNameField
@onready var _load_option: OptionButton    = $UI/HBox/DeckPanel/VBox/Header/LoadOption
@onready var _collection_grid: GridContainer = $UI/HBox/CollectionPanel/CollectionScroll/CollectionGrid
@onready var _search_field: LineEdit       = $UI/HBox/CollectionPanel/FilterBar/SearchField
@onready var _region_bar: HBoxContainer   = $UI/HBox/CollectionPanel/FilterBar/RegionBar
@onready var _cost_bar: HBoxContainer     = $UI/HBox/CollectionPanel/FilterBar/CostBar
@onready var _card_preview: Node          = $CardPreview


func _ready() -> void:
	_all_cards = CardDatabase.get_collectible_cards()
	_build_region_buttons()
	_build_cost_buttons()
	_refresh_load_dropdown()
	_rebuild_collection()
	_rebuild_deck()


# ─── Filter bar ───────────────────────────────────────────────────────────────

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
	for cost_label in ["0", "1", "2", "3", "4", "5", "6+"]:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = cost_label
		btn.custom_minimum_size = Vector2(40, 40)
		btn.toggled.connect(_on_cost_toggled.bind(cost_label))
		_cost_bar.add_child(btn)


# ─── Collection grid ──────────────────────────────────────────────────────────

func _get_collection_col_size() -> Vector2i:
	const COLS := 5
	const H_SEP := 8
	const DECK_PANEL_W := 488
	var vp_w: int = int(get_viewport().get_visible_rect().size.x)
	var available: int = vp_w - DECK_PANEL_W
	var col_w: int = (available - H_SEP * (COLS - 1)) / COLS
	var col_h: int = int(col_w * 176.0 / 126.0)
	return Vector2i(col_w, col_h)


func _get_deck_col_size() -> Vector2i:
	const COLS := 3
	const H_SEP := 4
	const DECK_PANEL_INNER_W := 472  # 488px panel - 8px padding each side
	var col_w: int = (DECK_PANEL_INNER_W - H_SEP * (COLS - 1)) / COLS
	var col_h: int = int(col_w * 176.0 / 126.0)
	return Vector2i(col_w, col_h)


func _rebuild_collection() -> void:
	for child in _collection_grid.get_children():
		child.queue_free()

	var col_size := _get_collection_col_size()
	for card_data in _filter(_all_cards):
		var mc: Control = MINI_CARD.instantiate()
		_collection_grid.add_child(mc)
		mc.setup(card_data["id"])
		mc.set_display_size(col_size.x, col_size.y)
		mc.set_in_deck(card_data["id"] in _deck_cards)
		mc.card_clicked.connect(_on_collection_card_clicked)
		mc.card_right_clicked.connect(_on_card_right_clicked)


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


# ─── Deck grid ────────────────────────────────────────────────────────────────

func _rebuild_deck() -> void:
	for child in _deck_grid.get_children():
		child.queue_free()

	var sorted_ids := _deck_cards.duplicate()
	sorted_ids.sort_custom(func(a, b):
		var da: Dictionary = CardDatabase.CARDS.get(a, {})
		var db: Dictionary = CardDatabase.CARDS.get(b, {})
		var a_champ := 0 if da.get("Type", "") == "Champion" else 1
		var b_champ := 0 if db.get("Type", "") == "Champion" else 1
		if a_champ != b_champ:
			return a_champ < b_champ
		if da.get("Cost", 0) != db.get("Cost", 0):
			return da.get("Cost", 0) < db.get("Cost", 0)
		return da.get("Name", "") < db.get("Name", ""))

	var col_size := _get_deck_col_size()
	for card_id in sorted_ids:
		var mc: Control = MINI_CARD.instantiate()
		_deck_grid.add_child(mc)
		mc.setup(card_id)
		mc.set_display_size(col_size.x, col_size.y)
		mc.card_clicked.connect(_on_deck_card_clicked)
		mc.card_right_clicked.connect(_on_card_right_clicked)

	_deck_label.text = "Deck (%d / %d)" % [_deck_cards.size(), MAX_DECK]


func _update_collection_highlights() -> void:
	for child in _collection_grid.get_children():
		if child.has_method("set_in_deck"):
			var cid: String = child._card_id
			child.set_in_deck(cid in _deck_cards)


# ─── Interactions ─────────────────────────────────────────────────────────────

func _on_collection_card_clicked(card_id: String) -> void:
	if card_id in _deck_cards:
		_deck_cards.erase(card_id)
	else:
		if _deck_cards.size() >= MAX_DECK:
			return
		_deck_cards.append(card_id)
	_rebuild_deck()
	_update_collection_highlights()


func _on_deck_card_clicked(card_id: String) -> void:
	_deck_cards.erase(card_id)
	_rebuild_deck()
	_update_collection_highlights()


func _on_card_right_clicked(card_id: String) -> void:
	if _card_preview and _card_preview.has_method("show_preview_by_id"):
		_card_preview.show_preview_by_id(card_id)


func _on_region_toggled(pressed: bool, region: String) -> void:
	if pressed:
		_active_regions.append(region)
	else:
		_active_regions.erase(region)
	_rebuild_collection()


func _on_cost_toggled(pressed: bool, cost_label: String) -> void:
	if pressed:
		_active_costs.append(cost_label)
	else:
		_active_costs.erase(cost_label)
	_rebuild_collection()


func _on_search_changed(new_text: String) -> void:
	_search = new_text
	_rebuild_collection()


# ─── Save / Cancel / Back ─────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	var deck_name: String = _name_field.text.strip_edges()
	if deck_name.is_empty():
		deck_name = "My Deck"
	DeckManager.save_deck(deck_name, _deck_cards)
	_saved_deck_cards = _deck_cards.duplicate()
	_refresh_load_dropdown()


func _on_cancel_pressed() -> void:
	_deck_cards = _saved_deck_cards.duplicate()
	_rebuild_deck()
	_update_collection_highlights()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/HomeScreen.tscn")


# ─── Load saved deck ──────────────────────────────────────────────────────────

func _refresh_load_dropdown() -> void:
	_load_option.clear()
	_load_option.add_item("Load deck…")
	for deck_name in DeckManager.get_deck_names():
		_load_option.add_item(deck_name)


func _on_load_option_selected(index: int) -> void:
	if index == 0:
		return
	var deck_name: String = _load_option.get_item_text(index)
	_name_field.text = deck_name
	_deck_cards = DeckManager.get_deck(deck_name)
	_saved_deck_cards = _deck_cards.duplicate()
	_rebuild_deck()
	_update_collection_highlights()
