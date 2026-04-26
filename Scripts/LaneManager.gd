extends Node

# AutoLoad singleton that handles lane reveal timing and lane effect execution.
# Called by:
#   BoardGeneration.create_lanes_from_ids() → setup_lanes()
#   GameManager.begin_round_start()         → on_round_start()
#   GameManager._proceed_to_resolve()       → on_round_end()
#   CardManager.finish_drag()               → is_placement_restricted()

var _lane_ids: Array = []                    # Ordered [left_id, mid_id, right_id]
var _revealed: Array = [false, false, false]
var _noxkraya_active: bool = false
var _noxkraya_col: int = -1


# ── Scene-tree helpers ─────────────────────────────────────────────────────────

func _get_board() -> Node:
	return get_node_or_null("/root/Main/Board")


func _get_card_manager() -> Node:
	return get_node_or_null("/root/Main/CardManager")


func _get_deck() -> Node:
	return get_node_or_null("/root/Main/Deck")


func _get_player_hand() -> Node:
	return get_node_or_null("/root/Main/PlayerHand")


# ── Public API ─────────────────────────────────────────────────────────────────

func setup_lanes(ordered_lane_ids: Array) -> void:
	"""Called by BoardGeneration after lane scenes are instantiated.
	Stores the ID list and fires immediate effects for the left lane (already revealed)."""
	_lane_ids = ordered_lane_ids.duplicate()
	_revealed = [false, false, false]
	_noxkraya_active = false
	_noxkraya_col = -1

	# Left lane is always revealed at game start; BoardGeneration already applied full visuals.
	_revealed[0] = true
	_fire_immediate_effects(0)


func on_round_start(turn_number: int) -> void:
	"""Called by GameManager.begin_round_start() BEFORE card round-start abilities.
	Handles lane reveals (turn 2/3) and round-start lane mechanics (Noxkraya turn 5)."""
	# Reveal mid lane on turn 2
	if turn_number == 2 and not _revealed[1]:
		await _reveal_lane(1)

	# Reveal right lane on turn 3
	if turn_number == 3 and not _revealed[2]:
		await _reveal_lane(2)

	# Noxkraya Arena: restrict card placement to this lane for turn 5 PLAY phase
	for col in range(3):
		if _revealed[col] and _get_lane_name(col) == "Noxkraya Arena" and turn_number == 5:
			_noxkraya_active = true
			_noxkraya_col = col
			print("Noxkraya Arena (lane %d): all cards must be played here this turn!" % col)


func on_round_end(turn_number: int) -> void:
	"""Called by GameManager._proceed_to_resolve() AFTER card round-end abilities.
	Handles timed lane effects that fire at the end of a specific turn."""
	for col in range(3):
		if not _revealed[col]:
			continue
		var lane_name := _get_lane_name(col)
		match lane_name:
			"Ornn's Forge":
				if turn_number == 4:
					await _activate_ornns_forge(col)
			"Sunken Temple":
				if turn_number == 3:
					await _activate_sunken_temple(col)

	# Clear Noxkraya restriction at the end of the round
	_noxkraya_active = false


func is_placement_restricted(zone_key: Vector2i) -> bool:
	"""Returns true if placing a card in zone_key is forbidden this turn.
	Currently only Noxkraya Arena (turn 5) restricts placement to one lane column."""
	if not _noxkraya_active:
		return false
	return zone_key.x != _noxkraya_col


# ── Private: reveal ────────────────────────────────────────────────────────────

func _reveal_lane(col: int) -> void:
	_revealed[col] = true
	var board := _get_board()
	if board and board.has_method("reveal_lane_visuals"):
		board.reveal_lane_visuals(col)
	await _fire_immediate_effects(col)


func _fire_immediate_effects(col: int) -> void:
	"""Trigger on-reveal effects for lanes that activate immediately when shown."""
	var lane_name := _get_lane_name(col)
	match lane_name:
		"Hexcore Foundry":
			await _activate_hexcore_foundry()
		"Rockfall Path":
			await _activate_rockfall_path(col)


# ── Private: helpers ───────────────────────────────────────────────────────────

func _get_lane_name(col: int) -> String:
	if col < 0 or col >= _lane_ids.size():
		return ""
	var lane_data: Dictionary = LaneDatabase.LANES.get(_lane_ids[col], {})
	return lane_data.get("Name", "")


func _summon_card_in_lane(card_id: String, col: int, player_id: int) -> void:
	"""Summon a card face-up on the board in a specific lane column and player row.
	Follows the same pattern as AbilityResolver._game_start_summon_sun_disc()."""
	var board := _get_board()
	var cm := _get_card_manager()
	if not board or not cm:
		return

	var card_data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if card_data.is_empty():
		print("LaneManager._summon_card_in_lane: unknown card id '%s'" % card_id)
		return

	var ally_row: int = board.get_ally_row(player_id)
	var zone_key := Vector2i(col, ally_row)
	var zone_slots: Array = board.slots_by_zone.get(zone_key, [])

	var available_slot = null
	for slot in zone_slots:
		if not slot.card_in_slot:
			available_slot = slot
			break
	if not available_slot:
		print("LaneManager._summon_card_in_lane: no available slot in lane %d for player %d" % [col, player_id])
		return

	var card_scene = CardDatabase.get_card_scene(card_data)
	var new_card = card_scene.instantiate()

	new_card.card_id = card_id
	new_card.owner_player_id = player_id
	CardDatabase.populate_card_visuals(new_card, card_data)

	new_card.position = available_slot.position
	new_card.scale = Vector2(0.15, 0.15)
	new_card.z_index = 0
	new_card.card_slot_is_in = available_slot
	new_card.get_node("Area2D/CollisionShape2D").disabled = true
	new_card.is_resolved = true
	if new_card.has_method("hide_card_back"):
		new_card.hide_card_back()

	cm.add_child(new_card)
	available_slot.card_in_slot = true
	board.add_card_to_zone(zone_key, new_card)
	cm.add_card_to_play_order(new_card)
	# Track as created by lane (creator_player_id = -1 for environment/lane)
	var lane_id = _lane_ids[col] if col < _lane_ids.size() else "UnknownLane"
	cm.track_created_card(new_card, -1, lane_id)

	print("LaneManager: summoned %s for player %d in lane %d" % [card_data.get("Name", card_id), player_id, col])


# ── Private: lane effects ──────────────────────────────────────────────────────

func _activate_hexcore_foundry() -> void:
	"""Hexcore Foundry: local player draws 1 card.
	In online play each client draws for themselves, so both players effectively draw 1."""
	var deck := _get_deck()
	if deck and deck.has_method("draw_cards"):
		deck.draw_cards(1)
	print("Hexcore Foundry: draw 1 card")


func _activate_rockfall_path(col: int) -> void:
	"""Rockfall Path: summon Chip (card 'Chip') for both players in this lane column."""
	for player_id in range(2):
		_summon_card_in_lane("Chip", col, player_id)
	# Refresh power labels after placing cards
	var cm := _get_card_manager()
	if cm and cm.has_method("_notify_zone_power_changed"):
		cm._notify_zone_power_changed()
	print("Rockfall Path: Chip summoned in lane %d for both players" % col)


func _activate_ornns_forge(col: int) -> void:
	"""Ornn's Forge: after turn 4, grant +1 Power to all resolved units in this lane (both sides)."""
	var board := _get_board()
	if not board:
		return

	for row in range(2):
		for card in board.get_cards_in_zone(Vector2i(col, row)):
			if not is_instance_valid(card) or not card.is_resolved:
				continue
			var card_data: Dictionary = CardDatabase.CARDS.get(card.card_id, {})
			var card_type: String = card_data.get("Type", "")
			if card_type != "Champion" and card_type != "Follower":
				continue
			card.power_modifier += 1
			var lbl = card.get_node_or_null("CardFront/Power")
			if lbl:
				lbl.text = card.get_power_display_text()

	var cm := _get_card_manager()
	if cm and cm.has_method("_notify_zone_power_changed"):
		cm._notify_zone_power_changed()
	print("Ornn's Forge: +1 Power to all units in lane %d" % col)


func _activate_sunken_temple(col: int) -> void:
	"""Sunken Temple: after turn 3, local player shuffles a random hand card into their deck,
	then draws 1 card. If hand is empty, just draws 1."""
	var player_hand := _get_player_hand()
	var deck := _get_deck()
	if not deck:
		return

	# Shuffle a random hand card back into the deck (if hand is non-empty)
	if player_hand and player_hand.get("player_hand") != null:
		var hand_cards: Array = player_hand.player_hand
		if hand_cards.size() > 0:
			var rand_idx := randi() % hand_cards.size()
			var card_to_shuffle = hand_cards[rand_idx]
			if is_instance_valid(card_to_shuffle):
				var shuffled_id: String = card_to_shuffle.card_id
				# Add card ID back to deck (insert at random position for a shuffle feel)
				var insert_pos = randi() % (deck.player_deck.size() + 1)
				deck.player_deck.insert(insert_pos, shuffled_id)
				# Remove from hand and free the scene node
				if player_hand.has_method("remove_card_from_hand"):
					player_hand.remove_card_from_hand(card_to_shuffle)
				card_to_shuffle.queue_free()
				# Update deck count label
				if deck.has_node("RichTextLabel"):
					deck.get_node("RichTextLabel").text = str(deck.player_deck.size())
				print("Sunken Temple: shuffled %s back into deck" % shuffled_id)

	# Draw 1 card
	deck.draw_cards(1)
	print("Sunken Temple: draw 1 card")
