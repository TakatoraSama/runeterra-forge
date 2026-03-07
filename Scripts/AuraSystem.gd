extends Node

## AuraSystem – manages all aura power effects on the board.
## AutoLoad singleton: accessible from any script via AuraSystem.<method>.
##
## All card-specific aura logic (Azir lv2/lv3, Xerath lv2/lv3) lives here,
## so CardManager no longer needs to know individual card rules.
## CardManager._notify_zone_power_changed() delegates here.


# ─── Scene-tree helpers ────────────────────────────────────────────────────────

func _get_card_manager() -> Node:
	return get_node_or_null("/root/Main/CardManager")


func _get_board() -> Node:
	return get_node_or_null("/root/Main/Board")


# ─── Public API ───────────────────────────────────────────────────────────────

func recalculate_auras() -> void:
	"""Reset all aura power modifiers, then reapply every active aura source.
	Called by CardManager._notify_zone_power_changed() whenever board state changes."""
	var cm := _get_card_manager()
	var board := _get_board()
	if not cm or not board:
		return

	# Step 1 – reset aura modifier on every card currently on the board
	for zone_key in board.cards_by_zone:
		for card in board.get_cards_in_zone(zone_key):
			if is_instance_valid(card):
				card.aura_power_modifier = 0

	# Step 2 – reapply auras from each active aura source
	for card in cm.all_cards_in_play_order:
		if not is_instance_valid(card) or not card.is_resolved:
			continue
		var card_data = CardDatabase.CARDS.get(card.card_id)
		if not card_data or not card.card_slot_is_in:
			continue

		var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
		if zone_key == Vector2i(-1, -1):
			continue

		var card_name: String = card_data.get("Name", "")
		var level: int      = card_data.get("Level", 1)
		var ability_type: String = card_data.get("AbilityType", "")

		if card_name == "Xerath" and level == 2:
			_apply_aura_xerath_lv2(card, zone_key)
		elif card_name == "Xerath" and level == 3:
			_apply_aura_xerath_lv3(card, zone_key)
		elif card_name == "Azir" and level >= 2:
			_apply_aura_azir(card, zone_key)
		elif ability_type == "aura_ascended_buff":
			# Fallback for any future non-Azir ascended-aura card
			_apply_aura_azir(card, zone_key)
		elif card_name == "Irelia" and level == 2:
			_apply_aura_irelia_lv2(card, zone_key)
		elif ability_type == "aura_blade_buff":
			_apply_aura_blade(card, zone_key)

	# Step 3 – refresh the power label on every card currently on the board
	for zone_key in board.cards_by_zone:
		for card in board.get_cards_in_zone(zone_key):
			if is_instance_valid(card):
				var power_label = card.get_node_or_null("CardFront/Power")
				if power_label:
					power_label.text = card.get_power_display_text()


# ─── Individual aura implementations ─────────────────────────────────────────

func _apply_aura_azir(azir_card: Node, zone_key: Vector2i) -> void:
	"""Azir lv2/lv3 aura: other allied Ascended Champions/Followers in play gain
	+aura_power Power (applies across all allied lanes, not just Azir's lane)."""
	var board := _get_board()
	if not board:
		return

	var azir_data = CardDatabase.CARDS.get(azir_card.card_id)
	if not azir_data:
		return

	var aura_amount: int = int(azir_data.get("BalanceValues", {}).get("aura_power", 2))
	var owner_id: int    = azir_card.owner_player_id
	# zone_key kept as parameter for API consistency; Azir's aura is board-wide.
	var _unused := zone_key

	for ally_zone in board.get_ally_zones(owner_id):
		for ally in board.get_cards_in_zone(ally_zone):
			if not is_instance_valid(ally) or ally == azir_card:
				continue
			if ally.owner_player_id != owner_id or not ally.is_resolved:
				continue
			var ally_data = CardDatabase.CARDS.get(ally.card_id)
			if not ally_data:
				continue
			if ally_data.get("SubType", "").to_lower() != "ascended":
				continue
			var ally_type: String = ally_data.get("Type", "")
			if ally_type != "Champion" and ally_type != "Follower":
				continue
			ally.aura_power_modifier += aura_amount


func _apply_aura_xerath_lv2(xerath_card: Node, zone_key: Vector2i) -> void:
	"""Xerath lv2 aura: all enemy Champions/Followers in this lane have -aura_debuff Power."""
	var board := _get_board()
	if not board:
		return

	var xerath_data = CardDatabase.CARDS.get(xerath_card.card_id)
	var aura_debuff: int = int(xerath_data.get("BalanceValues", {}).get("aura_debuff", 1)) if xerath_data else 1

	var enemy_zone: Vector2i = board.get_opposing_zone(zone_key)
	for enemy in board.get_cards_in_zone(enemy_zone):
		if not is_instance_valid(enemy) or not enemy.is_resolved:
			continue
		var enemy_data = CardDatabase.CARDS.get(enemy.card_id)
		if not enemy_data:
			continue
		var enemy_type: String = enemy_data.get("Type", "")
		if enemy_type != "Champion" and enemy_type != "Follower":
			continue
		enemy.aura_power_modifier -= aura_debuff


func _apply_aura_xerath_lv3(xerath_card: Node, zone_key: Vector2i) -> void:
	"""Xerath lv3 aura: back-row (slot index 2-3) enemy Champions/Followers in EVERY
	lane have -aura_debuff Power."""
	var board := _get_board()
	if not board:
		return

	var xerath_data = CardDatabase.CARDS.get(xerath_card.card_id)
	var aura_debuff: int = int(xerath_data.get("BalanceValues", {}).get("aura_debuff", 1)) if xerath_data else 1
	var _unused := zone_key  # Lv3 aura is board-wide; parameter kept for consistency.
	var enemy_row: int = board.get_enemy_row(xerath_card.owner_player_id)

	for col in range(board.COLUMNS):
		var enemy_zone := Vector2i(col, enemy_row)
		for enemy in board.get_cards_in_zone(enemy_zone):
			if not is_instance_valid(enemy) or not enemy.is_resolved:
				continue
			var enemy_data = CardDatabase.CARDS.get(enemy.card_id)
			if not enemy_data:
				continue
			var enemy_type: String = enemy_data.get("Type", "")
			if enemy_type != "Champion" and enemy_type != "Follower":
				continue
			# Back-row = slot index 2 or higher
			var slot_idx: int = board.get_card_slot_index_in_zone(enemy_zone, enemy)
			if slot_idx < 2:
				continue
			enemy.aura_power_modifier -= aura_debuff


func _apply_aura_irelia_lv2(irelia_card: Node, zone_key: Vector2i) -> void:
	"""Irelia lv2 aura: allied Champions/Followers with base cost 1 gain +power_increase Power.
	Uses all_cards_in_play_order (not zone-based) so opponent-viewed cards are found correctly
	even when zone mirroring places them at a row that doesn't match owner_id."""
	var cm := _get_card_manager()
	if not cm:
		return
	var irelia_data = CardDatabase.CARDS.get(irelia_card.card_id)
	if not irelia_data:
		return

	var aura_amount: int = int(irelia_data.get("BalanceValues", {}).get("power_increase", 1))
	var owner_id: int = irelia_card.owner_player_id
	var _unused := zone_key

	for ally in cm.all_cards_in_play_order:
		if not is_instance_valid(ally) or not ally.is_resolved:
			continue
		if ally.owner_player_id != owner_id or not ally.card_slot_is_in:
			continue
		var ally_data = CardDatabase.CARDS.get(ally.card_id)
		if not ally_data:
			continue
		var ally_type: String = ally_data.get("Type", "")
		if ally_type != "Champion" and ally_type != "Follower":
			continue
		if int(ally_data.get("Cost", -1)) != 1:
			continue
		ally.aura_power_modifier += aura_amount


func _apply_aura_blade(blade_card: Node, zone_key: Vector2i) -> void:
	"""Blade aura: all OTHER allied Blades gain +aura_power Power.
	Uses zone row (not owner_player_id) to determine same side — opponent Blades are
	always at a different row due to zone mirroring, so this is reliable in multiplayer."""
	var cm := _get_card_manager()
	var board := _get_board()
	if not cm or not board:
		return
	var blade_data = CardDatabase.CARDS.get(blade_card.card_id)
	if not blade_data:
		return

	var aura_amount: int = int(blade_data.get("BalanceValues", {}).get("aura_power", 1))
	var ally_row: int = zone_key.y  # same side = same row (zone_key already validated)

	for ally in cm.all_cards_in_play_order:
		if not is_instance_valid(ally) or ally == blade_card:
			continue  # Skip self
		if not ally.is_resolved or not ally.card_slot_is_in:
			continue
		if ally.card_id != "Blade":
			continue
		var ally_zone: Vector2i = board.get_zone_for_slot(ally.card_slot_is_in)
		if ally_zone == Vector2i(-1, -1) or ally_zone.y != ally_row:
			continue
		ally.aura_power_modifier += aura_amount
