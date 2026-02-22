extends Node2D

@export var card_slot_scene: PackedScene
@export var lane_scene: PackedScene = preload("res://Scenes/Lane.tscn")

# GRID_ORIGIN is the *center* of the top-left slot in zone (0,0).
# Zone centers: A1=(700,170), B1=(960,170), C1=(1220,170)
#               A2=(700,710), B2=(960,710), C2=(1220,710)
const GRID_ORIGIN := Vector2(652.75, 104.0)
const SLOT_SIZE := Vector2(630 * 0.15, 880 * 0.15)
const SLOT_STEP := SLOT_SIZE

const SLOTS_PER_ROW := 2
const ZONE_SIZE := Vector2(
	SLOT_SIZE.x * SLOTS_PER_ROW,
	SLOT_SIZE.y * SLOTS_PER_ROW
)

# For zone hit-testing / debug borders we want the *top-left corner*.
const GRID_ORIGIN_TOP_LEFT := GRID_ORIGIN - (SLOT_SIZE * 0.5)

const CARD_STEP_X := 260
const CARD_STEP_Y := 540

const COLUMNS := 3
const ROWS := 2
const SLOTS_PER_CARD := 4

const LANE_POSITIONS := {
	0: Vector2(700, 440),
	1: Vector2(960, 440),
	2: Vector2(1220, 440),
}

const POWER_TEXT_POSITIONS := {
	Vector2i(0, 0): Vector2(700, 340), # A1
	Vector2i(0, 1): Vector2(700, 540), # A2
	Vector2i(1, 0): Vector2(960, 340), # B1
	Vector2i(1, 1): Vector2(960, 540), # B2
	Vector2i(2, 0): Vector2(1220, 340), # C1
	Vector2i(2, 1): Vector2(1220, 540), # C2
}

const DEBUG_DRAW_ZONES := false
const DEBUG_ZONE_COLOR := Color(0.2, 0.9, 0.3, 0.6)
const DEBUG_ZONE_THICKNESS := 2.0

var slots_by_zone := {}
var cards_by_zone := {}
var zone_owners := {}  # Maps Vector2i(col, row) to player_id (0 or 1)
var power_labels_by_zone := {}  # Maps Vector2i(col, row) to Label node
var lane_nodes_by_col := {}
var lane_data_by_col := {}


func _ready() -> void:
	setup_zone_ownership()
	create_all_slots()
	if DEBUG_DRAW_ZONES:
		queue_redraw()


func pick_random_lane_ids() -> Array:
	"""Returns a shuffled array of 3 appearable lane IDs for server to broadcast."""
	var lane_ids := _get_appearable_lane_ids()
	lane_ids.shuffle()
	# Ensure exactly COLUMNS entries (wrap if fewer available)
	var result: Array = []
	for col in range(COLUMNS):
		result.append(str(lane_ids[col % lane_ids.size()]))
	return result


func create_lanes_from_ids(ordered_lane_ids: Array) -> void:
	"""Create and populate 3 lane scenes using the given lane ID list (index = column).
	Left lane (col 0) is fully revealed immediately.
	Mid (col 1) and right (col 2) are hidden until turns 2 and 3 respectively."""
	if not lane_scene:
		return

	for lane in lane_nodes_by_col.values():
		if is_instance_valid(lane):
			lane.queue_free()
	lane_nodes_by_col.clear()
	lane_data_by_col.clear()

	for col in range(COLUMNS):
		var lane_instance := lane_scene.instantiate()
		add_child(lane_instance)
		lane_instance.position = LANE_POSITIONS.get(col, Vector2.ZERO)
		lane_nodes_by_col[col] = lane_instance

		var lane_id: String = str(ordered_lane_ids[col]) if col < ordered_lane_ids.size() else "1"
		var lane_data: Dictionary = LaneDatabase.LANES.get(lane_id, {})
		lane_data_by_col[col] = lane_data

		if col == 0:
			_apply_lane_visuals(lane_instance, lane_data)
		else:
			var reveal_turn := col + 1  # col 1 → turn 2, col 2 → turn 3
			_apply_lane_visuals_hidden(lane_instance, reveal_turn)

	# Inform LaneManager of the lane assignment so it can track reveals and effects
	LaneManager.setup_lanes(ordered_lane_ids)


func _get_appearable_lane_ids() -> Array:
	var lane_ids: Array = []
	for lane_id in LaneDatabase.LANES.keys():
		var lane_data: Dictionary = LaneDatabase.LANES.get(str(lane_id), {})
		if bool(lane_data.get("Appearable", false)):
			lane_ids.append(str(lane_id))
	return lane_ids


func _apply_lane_visuals_hidden(lane_instance: Node, reveal_turn: int) -> void:
	"""Apply placeholder visuals to a lane that hasn't been revealed yet."""
	if not lane_instance:
		return

	var lane_name_node := lane_instance.get_node_or_null("LaneName")
	if lane_name_node and "text" in lane_name_node:
		lane_name_node.text = ""

	var lane_desc_node := lane_instance.get_node_or_null("LaneDesc")
	if lane_desc_node and "text" in lane_desc_node:
		lane_desc_node.text = "Will be revealed on turn %d" % reveal_turn

	var lane_sprite_node := lane_instance.get_node_or_null("LaneBase/LaneSprite")
	if lane_sprite_node and "texture" in lane_sprite_node:
		lane_sprite_node.texture = null


func reveal_lane_visuals(col: int) -> void:
	"""Called by LaneManager when a hidden lane becomes revealed.
	Applies full name, sprite, and description to the lane scene."""
	var lane_instance = lane_nodes_by_col.get(col)
	var lane_data: Dictionary = lane_data_by_col.get(col, {})
	if lane_instance and is_instance_valid(lane_instance):
		_apply_lane_visuals(lane_instance, lane_data)


func _apply_lane_visuals(lane_instance: Node, lane_data: Dictionary) -> void:
	if not lane_instance:
		return

	var lane_name_node := lane_instance.get_node_or_null("LaneName")
	if lane_name_node and "text" in lane_name_node:
		lane_name_node.text = str(lane_data.get("Name", ""))

	var lane_desc_node := lane_instance.get_node_or_null("LaneDesc")
	if lane_desc_node and "text" in lane_desc_node:
		lane_desc_node.text = str(lane_data.get("Desc", ""))

	var lane_sprite_node := lane_instance.get_node_or_null("LaneBase/LaneSprite")
	if lane_sprite_node and "texture" in lane_sprite_node:
		var sprite_path := str(lane_data.get("Sprite", ""))
		if sprite_path != "":
			var lane_texture: Texture2D = load(sprite_path)
			if lane_texture:
				lane_sprite_node.texture = lane_texture


func get_slot_position(card_col: int, card_row: int, slot_index: int) -> Vector2:
	var slot_x := slot_index % 2
	var slot_y := slot_index >> 1

	var card_offset := Vector2(
		card_col * CARD_STEP_X,
		card_row * CARD_STEP_Y
	)

	var slot_offset := Vector2(
		slot_x * SLOT_STEP.x,
		slot_y * SLOT_STEP.y
	)

	return GRID_ORIGIN + card_offset + slot_offset


func create_all_slots() -> Dictionary:
	var slots := {}
	slots_by_zone.clear()
	power_labels_by_zone.clear()

	for row in range(ROWS):
		for col in range(COLUMNS):
			var zone_key := Vector2i(col, row)
			slots_by_zone[zone_key] = []

			# Row 0 (opponent, top): fill from bottom-left toward board center: BL, BR, TL, TR
			# Row 1 (player, bottom): fill from top-left toward board center: TL, TR, BL, BR
			var slot_order: Array = [2, 3, 0, 1] if row == 0 else [0, 1, 2, 3]

			for slot in slot_order:
				var slot_instance := card_slot_scene.instantiate()
				slot_instance.z_index = -12
				add_child(slot_instance)

				slot_instance.position = get_slot_position(col, row, slot)

				var key := "%s%d-%d" % [
					char(65 + col), # A/B/C
					row + 1,
					slot + 1
				]

				slots[key] = slot_instance
				slots_by_zone[zone_key].append(slot_instance)

			# Create power label for this zone
			_create_zone_power_label(zone_key)

	return slots


func _create_zone_power_label(zone_key: Vector2i) -> void:
	"""Create a Label node to display total power for a zone."""
	var label := Label.new()
	label.text = "0"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.z_index = 0

	var label_center: Vector2 = POWER_TEXT_POSITIONS.get(zone_key, Vector2.ZERO)
	label.position = label_center - Vector2(25, 15)
	label.size = Vector2(50, 30)
	
	add_child(label)
	power_labels_by_zone[zone_key] = label


func update_zone_power_texts(power_by_zone: Dictionary) -> void:
	"""Update all zone power labels with the given power values."""
	for zone_key in power_by_zone:
		if power_labels_by_zone.has(zone_key):
			var label: Label = power_labels_by_zone[zone_key]
			var power_value: int = power_by_zone[zone_key]
			label.text = str(power_value)


func get_next_available_slot_for_position(world_pos: Vector2):
	var local_pos := world_pos - GRID_ORIGIN_TOP_LEFT
	if local_pos.x < 0 or local_pos.y < 0:
		return null

	var col := int(floor(local_pos.x / CARD_STEP_X))
	var row := int(floor(local_pos.y / CARD_STEP_Y))
	if col < 0 or col >= COLUMNS or row < 0 or row >= ROWS:
		return null

	# CARD_STEP_* defines the spacing between zones; ZONE_SIZE defines the actual 2x2 slot area.
	# If the pointer is in the gap area between zones, ignore it.
	var zone_local := local_pos - Vector2(col * CARD_STEP_X, row * CARD_STEP_Y)
	if zone_local.x < 0 or zone_local.y < 0 or zone_local.x >= ZONE_SIZE.x or zone_local.y >= ZONE_SIZE.y:
		return null

	var zone_key := Vector2i(col, row)
	if not slots_by_zone.has(zone_key):
		return null

	for slot_instance in slots_by_zone[zone_key]:
		if not slot_instance.card_in_slot:
			return slot_instance

	return null


func _draw() -> void:
	if not DEBUG_DRAW_ZONES:
		return

	for row in range(ROWS):
		for col in range(COLUMNS):
			var top_left := GRID_ORIGIN_TOP_LEFT + Vector2(col * CARD_STEP_X, row * CARD_STEP_Y)
			var zone_rect := Rect2(top_left, ZONE_SIZE)
			draw_rect(zone_rect, DEBUG_ZONE_COLOR, false, DEBUG_ZONE_THICKNESS)


# Zone card tracking functions
func add_card_to_zone(zone_key: Vector2i, card: Node2D) -> void:
	if not cards_by_zone.has(zone_key):
		cards_by_zone[zone_key] = []
	if card not in cards_by_zone[zone_key]:
		cards_by_zone[zone_key].append(card)


func remove_card_from_zone(zone_key: Vector2i, card: Node2D) -> void:
	if cards_by_zone.has(zone_key) and card in cards_by_zone[zone_key]:
		cards_by_zone[zone_key].erase(card)


func reposition_cards_in_zone(zone_key: Vector2i) -> void:
	"""Shift remaining cards in a zone to fill empty slots from left to right, top to bottom."""
	if not slots_by_zone.has(zone_key):
		return

	var zone_slots: Array = slots_by_zone[zone_key]
	var remaining_cards: Array = cards_by_zone.get(zone_key, [])

	# Clear all slots in this zone first
	for slot in zone_slots:
		slot.card_in_slot = false

	# Reassign each remaining card to the next available slot in order
	for i in range(remaining_cards.size()):
		if i >= zone_slots.size():
			break  # More cards than slots (shouldn't happen)
		var card = remaining_cards[i]
		if not is_instance_valid(card):
			continue
		var target_slot = zone_slots[i]
		card.card_slot_is_in = target_slot
		card.position = target_slot.position
		target_slot.card_in_slot = true


func get_cards_in_zone(zone_key: Vector2i) -> Array:
	return cards_by_zone.get(zone_key, [])


func get_zone_for_slot(slot) -> Vector2i:
	for zone_key in slots_by_zone:
		if slot in slots_by_zone[zone_key]:
			return zone_key
	return Vector2i(-1, -1)


# Zone ownership functions
func setup_zone_ownership() -> void:
	"""Initialize zone ownership. Row 0 = Player 0 (top), Row 1 = Player 1 (bottom)"""
	zone_owners.clear()
	for row in range(ROWS):
		for col in range(COLUMNS):
			var zone_key := Vector2i(col, row)
			# Row 0 (top) belongs to player 0, Row 1 (bottom) belongs to player 1
			zone_owners[zone_key] = row


func get_zone_owner(zone_key: Vector2i) -> int:
	"""Returns the player_id (0 or 1) who owns this zone, or -1 if invalid."""
	return zone_owners.get(zone_key, -1)


func is_zone_owned_by_player(zone_key: Vector2i, player_id: int) -> bool:
	"""Check if a zone belongs to a specific player."""
	return get_zone_owner(zone_key) == player_id


func get_player_zones(player_id: int) -> Array:
	"""Returns all zone keys owned by a specific player."""
	var player_zones := []
	for zone_key in zone_owners:
		if zone_owners[zone_key] == player_id:
			player_zones.append(zone_key)
	return player_zones


# --- Ally / Enemy zone helpers ---

func get_ally_row(player_id: int) -> int:
	"""Returns the row index for a player's own side. Row 0 = Player 0, Row 1 = Player 1."""
	return player_id


func get_enemy_row(player_id: int) -> int:
	"""Returns the row index for the opponent's side."""
	return 1 - player_id


func get_ally_zones(player_id: int) -> Array:
	"""Returns zone keys for a player's own side (3 zones)."""
	var row = get_ally_row(player_id)
	var zones := []
	for col in range(COLUMNS):
		zones.append(Vector2i(col, row))
	return zones


func get_enemy_zones(player_id: int) -> Array:
	"""Returns zone keys for the opponent's side (3 zones)."""
	var row = get_enemy_row(player_id)
	var zones := []
	for col in range(COLUMNS):
		zones.append(Vector2i(col, row))
	return zones


func get_ally_cards_in_lane(player_id: int, col: int) -> Array:
	"""Returns ally cards in a specific lane (column)."""
	var row = get_ally_row(player_id)
	return get_cards_in_zone(Vector2i(col, row))


func get_enemy_cards_in_lane(player_id: int, col: int) -> Array:
	"""Returns enemy cards in a specific lane (column)."""
	var row = get_enemy_row(player_id)
	return get_cards_in_zone(Vector2i(col, row))


func get_all_ally_cards(player_id: int) -> Array:
	"""Returns all cards on a player's side across all lanes."""
	var cards := []
	for zone_key in get_ally_zones(player_id):
		cards.append_array(get_cards_in_zone(zone_key))
	return cards


func get_all_enemy_cards(player_id: int) -> Array:
	"""Returns all cards on the opponent's side across all lanes."""
	var cards := []
	for zone_key in get_enemy_zones(player_id):
		cards.append_array(get_cards_in_zone(zone_key))
	return cards


func get_lane_for_zone(zone_key: Vector2i) -> int:
	"""Returns the lane column (0=Left, 1=Mid, 2=Right) for a zone."""
	return zone_key.x


func get_opposing_zone(zone_key: Vector2i) -> Vector2i:
	"""Returns the zone on the opposite side of the same lane."""
	return Vector2i(zone_key.x, 1 - zone_key.y)


func get_card_slot_index_in_zone(zone_key: Vector2i, card: Node2D) -> int:
	"""Returns the slot index (0-3) of a card within its zone, or -1 if not found.
	Indices 0-1 = front row, 2-3 = back row."""
	if not card or not ("card_slot_is_in" in card) or not card.card_slot_is_in:
		return -1
	var zone_slots = slots_by_zone.get(zone_key, [])
	return zone_slots.find(card.card_slot_is_in)
