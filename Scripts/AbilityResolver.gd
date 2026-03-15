extends Node

## AbilityResolver – single authoritative entry point for ALL card ability execution.
## AutoLoad singleton: accessible from any script via AbilityResolver.<method>.
##
## Previously, ability logic was scattered across:
##   Card.gd         (_ability_* and _game_end_* methods)
##   CardManager.gd  (no direct ability logic, but called into Card implicitly)
##   Deck.gd         (Azir {Game Start} summon_sun_disc)
##
## Now any script that needs to fire an ability calls one of the four public
## execute_* functions.  Card.gd becomes a thin wrapper of pure state.
## Deck.gd knows nothing about individual cards.


# ─── Scene-tree helpers ────────────────────────────────────────────────────────

func _get_board() -> Node:
	return get_node_or_null("/root/Main/Board")


func _get_card_manager() -> Node:
	return get_node_or_null("/root/Main/CardManager")


func _get_game_manager() -> Node:
	return get_node_or_null("/root/Main/GameManager")


func _get_network_manager() -> Node:
	return get_node_or_null("/root/Main/NetworkManager")


func _is_online() -> bool:
	var nm := _get_network_manager()
	if nm and nm.has_method("is_online"):
		return nm.is_online()
	return false


func pick_random_target(valid_targets: Array) -> Node:
	"""Return a random resolved entry from valid_targets, or null if none.
	Both clients produce the same result because the resolve-phase RNG
	is seeded with shared state (turn_number + flip_first_player_id)
	before any abilities fire. All ability random picks must use this
	function instead of inline randi().
	Only cards with is_resolved == true are eligible targets."""
	var resolved := valid_targets.filter(func(t): return t.is_resolved)
	if resolved.is_empty():
		return null
	return resolved[randi() % resolved.size()]


# ─── Public phase dispatchers (called by Card.gd thin wrappers) ───────────────

func execute_play_ability(card: Node) -> void:
	"""Fire the {Play} ability of the given card (called when it flips during resolve)."""
	if card.card_id == "":
		return
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"summon_copy":
			_ability_summon_copy(card)
		"buff_allies":
			_ability_buff_allies(card)
		"damage_enemies":
			_ability_damage_enemies(card)
		"create_card":
			_ability_create_card(card)
		"mana_ramp":
			_ability_mana_ramp(card)
		"drain_power":
			_ability_drain_power(card)
		"stun_enemy":
			_ability_stun_enemy(card)
		"recall_allies_same_lane":
			await _ability_recall_allies_same_lane(card)
		"recall_cost_allies":
			await _ability_recall_cost_allies(card)
		"discard_by_cost_bracket":
			await _ability_discard_by_cost_bracket(card)
		_:
			pass  # no Play ability or unhandled type


func execute_level_up_ability(card: Node) -> void:
	"""Fire the {When I level up} ability of the given card.
	Called from _perform_level_up() after animation and lock release."""
	if card.card_id == "":
		return
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return
	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"level_up_create_from_discards":
			_ability_level_up_create_from_discards(card)
		_:
			pass  # no level-up ability or unhandled type


func execute_round_start_ability(card: Node) -> bool:
	"""Fire the {Round Start} ability of the given card.
	Returns true if an ability actually triggered."""
	if card.card_id == "":
		return false
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return false
	var skill: String = card_data.get("Skill", "")
	if not skill.begins_with("{Round Start}"):
		return false

	print("Round Start ability triggered for: ", card_data.get("Name", ""))
	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"conditional_buff":
			_ability_conditional_buff(card)
		_:
			pass
	return true


func execute_round_end_ability(card: Node) -> bool:
	"""Fire the {Round End} ability of the given card.
	Returns true if an ability actually triggered.  May yield (contains await)."""
	if card.card_id == "":
		return false
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return false
	var skill: String = card_data.get("Skill", "")
	if not skill.begins_with("{Round End}"):
		return false

	print("Round End ability triggered for: ", card_data.get("Name", ""))
	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"kill_ally_buff":
			await _ability_kill_ally_buff(card)
		_:
			pass
	return true


func execute_game_end_ability(card: Node) -> bool:
	"""Fire the {Game End} ability of the given card.
	Returns true if an ability actually triggered.  May yield (contains await)."""
	if card.card_id == "":
		return false
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return false
	var skill: String = card_data.get("Skill", "")
	if not (skill.begins_with("{Game End}") or "{Game End}" in skill):
		return false

	print("Game End ability triggered for: ", card_data.get("Name", ""))
	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"conditional_buff":
			_ability_game_end_buff(card)
		"aura_debuff":
			_game_end_xerath_buff(card)
		"kill_ally_buff":
			await _ability_nasus_game_end_kill(card)
		_:
			pass
	return true


func execute_game_start_ability_for_deck(card_id: String, card_data: Dictionary, owner_player_id: int) -> void:
	"""Fire a {Game Start} ability triggered from the player's deck.
	Called by Deck.trigger_game_start_abilities() instead of card-specific logic."""
	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"summon_sun_disc":
			_game_start_summon_sun_disc(owner_player_id)
		_:
			print("AbilityResolver: unknown Game Start ability type '%s' for card %s" % [ability_type, card_id])


# ─── Play abilities ────────────────────────────────────────────────────────────

func _ability_summon_copy(card: Node) -> void:
	"""Generic 'summon a copy of this card at the next available slot'."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm:
		return

	var next_slot = board.get_next_available_slot_for_position(card.position)
	if not next_slot:
		return

	var card_scene = load("res://Scenes/Card.tscn")
	var new_card   = card_scene.instantiate()

	new_card.card_id = card.card_id
	new_card.owner_player_id = card.owner_player_id  # copy belongs to same player as original
	var card_data    = CardDatabase.CARDS[card.card_id]
	CardDatabase.populate_card_visuals(new_card, card_data)

	new_card.position     = next_slot.position
	new_card.scale        = Vector2(0.15, 0.15)
	new_card.z_index      = 0
	new_card.card_slot_is_in = next_slot
	new_card.get_node("Area2D/CollisionShape2D").disabled = true

	cm.add_child(new_card)
	next_slot.card_in_slot = true

	var zone_key: Vector2i = board.get_zone_for_slot(next_slot)
	if zone_key != Vector2i(-1, -1):
		board.add_card_to_zone(zone_key, new_card)

	cm.add_card_to_play_order(new_card)
	cm.track_summoned_card(new_card, false)  # summoned directly (not from hand)
	cm.track_created_card(new_card, card.owner_player_id, card.card_id)  # created by the card ability
	new_card.is_resolved = true
	if new_card.has_method("hide_card_back"):
		new_card.hide_card_back()
	# Summoned copies do not trigger on_summon to prevent infinite loops.


func _ability_buff_allies(card: Node) -> void:
	"""Placeholder: buff resolved allies in the same zone."""
	var board := _get_board()
	if not board or not card.card_slot_is_in:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	for c in board.get_cards_in_zone(zone_key):
		if c == card or not c.is_resolved:
			continue
		print("Buffing ally: ", c.card_id)  # extend with real buff logic when needed


func _ability_damage_enemies(card: Node) -> void:
	"""Placeholder: deal damage to enemies."""
	print("Damage enemies ability triggered for card: ", card.card_id)


func _ability_stun_enemy(card: Node) -> void:
	"""Kennen {Play}: Stun a random enemy Champion/Follower in this lane.
	Kennen Lv2 also applies -power_decrease Power to the target (data-driven)."""
	var board := _get_board()
	if not board or not card.card_slot_is_in:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	# Collect valid targets: enemy Champions/Followers in the opposing zone
	var valid_targets: Array = []
	for enemy in board.get_cards_in_zone(board.get_opposing_zone(zone_key)):
		if not is_instance_valid(enemy) or not enemy.card_slot_is_in:
			continue
		var target_data = CardDatabase.CARDS.get(enemy.card_id)
		if not target_data:
			continue
		var target_type: String = target_data.get("Type", "")
		if target_type != "Champion" and target_type != "Follower":
			continue
		valid_targets.append(enemy)

	var my_name: String = card_data.get("Name", card.card_id)
	if valid_targets.is_empty():
		print("%s {Play}: no valid targets to Stun" % my_name)
		return

	var target = pick_random_target(valid_targets)
	if target == null:
		print("No targetable unit")
		return
	var chosen_data = CardDatabase.CARDS.get(target.card_id)
	var target_name: String = chosen_data.get("Name", target.card_id) if chosen_data else target.card_id

	var gm := _get_game_manager()
	var current_turn: int = gm.turn_number if gm else 0
	StunManager.apply_stun(target, current_turn)
	print("%s {Play}: Stunned %s" % [my_name, target_name])

	# Optional power debuff (Kennen Lv2: power_decrease = 1; Lv1 has no power_decrease key)
	var power_decrease: int = int(card_data.get("BalanceValues", {}).get("power_decrease", 0))
	if power_decrease > 0:
		target.power_modifier -= power_decrease
		var power_label = target.get_node_or_null("CardFront/Power")
		if power_label:
			power_label.text = target.get_power_display_text()
		print("%s {Play}: granted %s -%d Power (now %d)" % [
			my_name, target_name, power_decrease, target.get_current_power()])


func _ability_drain_power(card: Node) -> void:
	"""Xerath lv1 {Play}: drain drain_power from every other Champion/Follower in this
	lane (both sides).  Xerath gains the total amount actually drained."""
	var board := _get_board()
	if not board or not card.card_slot_is_in:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var drain_amount: int   = int(card_data.get("BalanceValues", {}).get("drain_power", 2))
	var total_power_gained := 0

	var all_lane_cards: Array = []
	all_lane_cards.append_array(board.get_cards_in_zone(zone_key))
	all_lane_cards.append_array(board.get_cards_in_zone(board.get_opposing_zone(zone_key)))

	for c in all_lane_cards:
		if c == card or not is_instance_valid(c) or not c.is_resolved:
			continue
		var target_data = CardDatabase.CARDS.get(c.card_id)
		if not target_data:
			continue
		var target_type: String = target_data.get("Type", "")
		if target_type != "Follower" and target_type != "Champion":
			continue

		var power_before: int = c.get_current_power()
		c.power_modifier -= drain_amount
		var actual_drained: int = power_before - c.get_current_power()
		total_power_gained += actual_drained

		var lbl = c.get_node_or_null("CardFront/Power")
		if lbl:
			lbl.text = c.get_power_display_text()
		print("Xerath drained %d Power from %s (was %d, now %d)" % [
			actual_drained, c.card_id, power_before, c.get_current_power()])

	if total_power_gained > 0:
		card.power_modifier += total_power_gained
		var power_label = card.get_node_or_null("CardFront/Power")
		if power_label:
			power_label.text = card.get_power_display_text()

	print("%s drained a total of +%d Power (now %d)" % [
		card_data.get("Name", card.card_id), total_power_gained, card.get_current_power()])


func _ability_create_card(card: Node) -> void:
	"""Parse [CardName] from the Skill text and create that card in the owner's hand.
	Only runs for the local player.  Used by Trundle lv1 → creates Ice Pillar."""
	if card.owner_player_id != 1:
		return  # only local player gets cards created

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var skill_text: String = card_data.get("Skill", "")
	var bracket_start := skill_text.find("[")
	var bracket_end   := skill_text.find("]")
	if bracket_start == -1 or bracket_end == -1 or bracket_end <= bracket_start:
		print("AbilityResolver create_card: no [CardName] in skill '%s'" % skill_text)
		return

	var target_name := skill_text.substr(bracket_start + 1, bracket_end - bracket_start - 1)
	var target_id   := CardDatabase.get_card_id_by_name(target_name)
	if target_id == "":
		print("AbilityResolver create_card: card not found by name '%s'" % target_name)
		return

	var cm := _get_card_manager()
	if cm and cm.has_method("create_card_in_hand"):
		cm.create_card_in_hand(target_id)
		print("Created [%s] in hand from %s" % [target_name, card_data.get("Name", "")])


func _ability_mana_ramp(card: Node) -> void:
	"""Grant the owner bonus mana next turn. Only runs for the local player."""
	if card.owner_player_id != 1:
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var bonus_amount := 5  # default; can be made data-driven via BalanceValues
	var gm := _get_game_manager()
	if gm and gm.has_method("add_temp_bonus_mana"):
		gm.add_temp_bonus_mana(card.owner_player_id, bonus_amount)
		print("%s grants +%d mana next turn" % [card_data.get("Name", ""), bonus_amount])


func _ability_recall_allies_same_lane(card: Node) -> void:
	"""NavoriConspirator {Play}: recall all other allied Champions/Followers in this lane.
	Only runs on the card owner's client — the opponent is notified via RPC inside recall_card."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm or not card.card_slot_is_in:
		return
	# Multiplayer guard: only the owner's client executes the recall.
	# The opponent receives _receive_opponent_recall RPCs from recall_card() instead.
	if card.owner_player_id != cm.current_player_id:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	var my_name: String = card_data.get("Name", card.card_id) if card_data else card.card_id

	# Collect targets first to avoid iterating a list that changes during recall
	var targets: Array = []
	for c in board.get_cards_in_zone(zone_key):
		if not is_instance_valid(c) or c == card:
			continue
		if c.owner_player_id != card.owner_player_id:
			continue
		if not c.is_resolved:
			continue
		var target_data = CardDatabase.CARDS.get(c.card_id)
		if not target_data:
			continue
		var target_type: String = target_data.get("Type", "")
		if target_type != "Champion" and target_type != "Follower":
			continue
		targets.append(c)

	if targets.is_empty():
		print("%s {Play}: no allied units to recall" % my_name)
		return

	print("%s {Play}: recalling %d allied unit(s)" % [my_name, targets.size()])
	for target in targets:
		if is_instance_valid(target):
			await cm.recall_card(target, card.owner_player_id, card.card_id)


func _ability_recall_cost_allies(card: Node) -> void:
	"""SolitaryMonk {Play}: recall all allied Champions/Followers with recall_cost base mana across all lanes.
	Only runs on the card owner's client — the opponent is notified via RPC inside recall_card."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm:
		return
	# Multiplayer guard: only the owner's client executes the recall.
	if card.owner_player_id != cm.current_player_id:
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var recall_cost: int = int(card_data.get("BalanceValues", {}).get("recall_cost", 1))
	var my_name: String = card_data.get("Name", card.card_id)

	# Collect targets across all allied zones first
	var targets: Array = []
	var ally_zones = board.get_ally_zones(card.owner_player_id)
	for zone_key in ally_zones:
		for c in board.get_cards_in_zone(zone_key):
			if not is_instance_valid(c) or c == card:
				continue
			if c.owner_player_id != card.owner_player_id:
				continue
			if not c.is_resolved:
				continue
			var target_data = CardDatabase.CARDS.get(c.card_id)
			if not target_data:
				continue
			var target_type: String = target_data.get("Type", "")
			if target_type != "Champion" and target_type != "Follower":
				continue
			if int(target_data.get("Cost", 0)) == recall_cost:
				targets.append(c)

	if targets.is_empty():
		print("%s {Play}: no %d-cost allied units to recall" % [my_name, recall_cost])
		return

	print("%s {Play}: recalling %d allied unit(s) with cost %d" % [my_name, targets.size(), recall_cost])
	for target in targets:
		if is_instance_valid(target):
			await cm.recall_card(target, card.owner_player_id, card.card_id)


func _ability_discard_by_cost_bracket(card: Node) -> void:
	"""Rumble {Play}: discard up to 3 cards from hand — one per cost bracket (≤2, 3–4, 5+).
	Grants +2 Power for each card discarded. Uses seeded RNG for multiplayer sync."""
	var cm := _get_card_manager()
	if not cm:
		return
	# Only the card owner's client performs the discard (opponent gets RPC).
	if card.owner_player_id != cm.current_player_id:
		return

	var hand_cards: Array = []
	if cm.player_hand_reference:
		for c in cm.player_hand_reference.player_hand:
			if is_instance_valid(c):
				hand_cards.append(c)

	# Group hand cards by cost bracket
	var bracket_low: Array = []   # cost ≤ 2
	var bracket_mid: Array = []   # cost 3–4
	var bracket_high: Array = []  # cost ≥ 5
	for c in hand_cards:
		var cost = c.get_current_cost()
		if cost <= 2:
			bracket_low.append(c)
		elif cost <= 4:
			bracket_mid.append(c)
		else:
			bracket_high.append(c)

	var discard_count := 0
	var card_data = CardDatabase.CARDS.get(card.card_id)
	var card_name: String = card_data.get("Name", card.card_id) if card_data else card.card_id

	for bracket in [bracket_low, bracket_mid, bracket_high]:
		if bracket.is_empty():
			continue
		# Seeded randi() — both clients produce the same index
		var pick = bracket[randi() % bracket.size()]
		var pick_id = pick.card_id
		print("%s {Play}: discarding %s (cost %d)" % [card_name, pick_id, pick.get_current_cost()])
		await cm.discard_card_from_hand(pick, card.card_id)
		if _is_online():
			cm.rpc("_receive_opponent_discard", pick_id, card.card_id)
		discard_count += 1

	if discard_count > 0:
		var buff = 2 * discard_count
		card.power_modifier += buff
		print("%s {Play}: gained +%d Power (%d cards discarded)" % [card_name, buff, discard_count])
		if _is_online():
			cm.rpc("_receive_opponent_power_buff", card.card_id, buff)
		cm._notify_zone_power_changed()

	# Pause everything: if Rumble met his level-up condition, block until animation completes.
	if discard_count > 0 and card.card_id == "Rumble1":
		var rumble_data = CardDatabase.CARDS.get("Rumble1")
		if rumble_data:
			var threshold: int = int(rumble_data.get("BalanceValues", {}).get("discard_threshold", 4))
			var total: int = cm.discarded_cards.filter(
				func(e): return int(e.get("owner_player_id", -1)) == card.owner_player_id).size()
			if total >= threshold:
				var level_up_to = rumble_data.get("LevelUpTo", "")
				if level_up_to:
					await card._perform_level_up(str(level_up_to))


func _ability_level_up_create_from_discards(card: Node) -> void:
	"""Rumble2 {When I level up}: for each discarded card owned by this player,
	create a random collectible card of the same base cost, then reduce its cost by 1."""
	var cm := _get_card_manager()
	if not cm:
		return
	if card.owner_player_id != cm.current_player_id:
		return

	var owner_id: int = card.owner_player_id
	var owner_discards: Array = cm.discarded_cards.filter(
		func(e): return int(e.get("owner_player_id", -1)) == owner_id)

	if owner_discards.is_empty():
		print("Rumble2 level-up: no discards to create from")
		return

	var card_name: String = CardDatabase.CARDS.get(card.card_id, {}).get("Name", card.card_id)

	# Cache cost → collectible card pool to avoid re-scanning per discard
	var pool_cache: Dictionary = {}

	var created_count := 0
	for entry in owner_discards:
		var src_data = CardDatabase.CARDS.get(str(entry.get("card_id", "")), {})
		var base_cost: int = int(src_data.get("Cost", 0))

		if not pool_cache.has(base_cost):
			var pool: Array = []
			for cid in CardDatabase.CARDS:
				var cd = CardDatabase.CARDS[cid]
				if cd.get("Collectible", false) and int(cd.get("Cost", -1)) == base_cost:
					pool.append(cid)
			pool_cache[base_cost] = pool

		var candidates: Array = pool_cache[base_cost]
		if candidates.is_empty():
			print("%s level-up: no collectible card at cost %d, skipping" % [card_name, base_cost])
			continue

		var picked_id: String = candidates[randi() % candidates.size()]
		cm.create_card_in_hand(picked_id, card.card_id)
		# create_card_in_hand inserts at index 0 — grab it immediately
		var new_card = cm.player_hand_reference.player_hand[0]
		cm.adjust_cost([new_card], -1)
		created_count += 1
		print("%s level-up: created %s (cost %d → %d)" % [
			card_name, picked_id, base_cost, new_card.get_current_cost()])

	print("%s level-up: created %d card(s) from %d discard(s)" % [
		card_name, created_count, owner_discards.size()])


# ─── Round Start abilities ─────────────────────────────────────────────────────

func _ability_conditional_buff(card: Node) -> void:
	"""Renekton {Round Start}: grant +win_power Power if winning this lane.
	After buffing, check whether the power threshold for level-up is reached."""
	var board := _get_board()
	if not board or not card.card_slot_is_in:
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var my_zone_power: int    = _calc_zone_power(board, zone_key)
	var enemy_zone_power: int = _calc_zone_power(board, board.get_opposing_zone(zone_key))

	if my_zone_power <= enemy_zone_power:
		print("%s: not winning here (%d vs %d), no buff" % [
			card_data.get("Name", ""), my_zone_power, enemy_zone_power])
		return

	var buff_amount: int = int(card_data.get("BalanceValues", {}).get("win_power", 2))
	card.power_modifier += buff_amount
	var power_label = card.get_node_or_null("CardFront/Power")
	if power_label:
		power_label.text = card.get_power_display_text()

	print("%s is winning here (%d vs %d), granted +%d Power (now %d)" % [
		card_data.get("Name", ""), my_zone_power, enemy_zone_power,
		buff_amount, card.get_current_power()])

	# check Renekton lv1 → lv2 power threshold
	LevelUpManager.check_level_up_by_power(card)


# ─── Round End abilities ───────────────────────────────────────────────────────

func _ability_kill_ally_buff(card: Node) -> void:
	"""Nasus {Round End}: kill the weakest ally in this zone AND grant self +kill_power Power.
	Both effects always happen (keyword 'and').  Kill tracking only fires on a real kill."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm or not card.card_slot_is_in:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	# Find the weakest ally in the zone (excludes Nasus itself, Landmarks)
	var weakest_card = null
	var weakest_power: float = INF

	for c in board.get_cards_in_zone(zone_key):
		if c == card or not is_instance_valid(c):
			continue
		var target_data = CardDatabase.CARDS.get(c.card_id)
		if not target_data:
			continue
		var target_type: String = target_data.get("Type", "")
		if target_type != "Follower" and target_type != "Champion":
			continue
		var card_power: float = c.get_current_power() if c.has_method("get_current_power") else 0.0
		if card_power < weakest_power:
			weakest_power = card_power
			weakest_card  = c

	if not weakest_card:
		return

	var card_data   = CardDatabase.CARDS.get(card.card_id)
	var buff_amount: int = int(card_data.get("BalanceValues", {}).get("kill_power", 2)) if card_data else 2
	var killed_card_id   = weakest_card.card_id
	var kill_succeeded   := false

	if weakest_card.has_method("can_prevent_death") and weakest_card.can_prevent_death():
		await card.get_tree().create_timer(0.5).timeout
		weakest_card.on_death_prevented()
		print("%s tried to kill %s, but death was prevented!" % [
			card_data.get("Name", card.card_id) if card_data else card.card_id, killed_card_id])
	else:
		kill_succeeded = true
		var killed_anim = weakest_card.get_node_or_null("AnimationPlayer")
		if killed_anim and killed_anim.has_animation("card_killed"):
			killed_anim.play("card_killed")
			await killed_anim.animation_finished
		else:
			await card.get_tree().create_timer(0.5).timeout

		cm.track_killed_card(weakest_card, card.owner_player_id, card.card_id)

		if weakest_card.card_slot_is_in:
			weakest_card.card_slot_is_in.card_in_slot = false
		board.remove_card_from_zone(zone_key, weakest_card)
		board.reposition_cards_in_zone(zone_key)
		weakest_card.card_slot_is_in = null  # Mark as removed from board (historical tracker guard)
		weakest_card.queue_free()

	# 'and' — buff ALWAYS applies regardless of whether the kill succeeded
	card.power_modifier += buff_amount
	var power_label = card.get_node_or_null("CardFront/Power")
	if power_label:
		power_label.text = card.get_power_display_text()

	var my_name: String = card_data.get("Name", card.card_id) if card_data else card.card_id
	if kill_succeeded:
		print("%s killed %s (Power %d) and gained +%d Power (now %d)" % [
			my_name, killed_card_id, int(weakest_power), buff_amount, card.get_current_power()])
	else:
		print("%s failed to kill %s (death prevented) but still gained +%d Power (now %d)" % [
			my_name, killed_card_id, buff_amount, card.get_current_power()])


# ─── Game End abilities ────────────────────────────────────────────────────────

func _ability_game_end_buff(card: Node) -> void:
	"""Dispatcher: routes to the correct Game End buff implementation based on card name."""
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return
	var card_name: String = card_data.get("Name", "")
	if card_name == "Trundle":
		_game_end_trundle_buff(card, card_data)
	elif card_name == "Renekton":
		_game_end_renekton_debuff(card, card_data)
	else:
		print("AbilityResolver: no specific Game End handler for '%s'" % card.card_id)


func _game_end_xerath_buff(card: Node) -> void:
	"""Xerath lv3 {Game End}: gain the Power of all front-row enemies in this lane.
	Front row = slot index 0 or 1 in the enemy zone.  Enemies keep their power."""
	var board := _get_board()
	if not board or not card.card_slot_is_in:
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var zone_key: Vector2i  = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var enemy_zone: Vector2i  = board.get_opposing_zone(zone_key)
	var total_power_gained := 0

	for enemy in board.get_cards_in_zone(enemy_zone):
		if not is_instance_valid(enemy):
			continue
		var slot_idx: int = board.get_card_slot_index_in_zone(enemy_zone, enemy)
		if slot_idx < 0 or slot_idx > 1:
			continue  # back-row; skip
		var enemy_data = CardDatabase.CARDS.get(enemy.card_id)
		if not enemy_data:
			continue
		var enemy_type: String = enemy_data.get("Type", "")
		if enemy_type != "Champion" and enemy_type != "Follower":
			continue
		var enemy_power: int = enemy.get_current_power()
		total_power_gained += enemy_power
		print("Xerath lv3 copies +%d Power from %s (front-row slot %d)" % [
			enemy_power, enemy_data.get("Name", enemy.card_id), slot_idx])

	if total_power_gained > 0:
		card.power_modifier += total_power_gained
		var power_label = card.get_node_or_null("CardFront/Power")
		if power_label:
			power_label.text = card.get_power_display_text()

	print("%s Game End: gained +%d Power from front-row enemies (now %d)" % [
		card_data.get("Name", card.card_id), total_power_gained, card.get_current_power()])


func _game_end_trundle_buff(card: Node, card_data: Dictionary) -> void:
	"""Trundle lv2 {Game End}: grant +behold_power Power for every Champions/Follower with
	mana_threshold+ Cost that you behold (hand + board)."""
	var cm := _get_card_manager()
	if not cm:
		return

	var bv                = card_data.get("BalanceValues", {})
	var buff_per_unit: int = int(bv.get("behold_power", 2))
	var mana_threshold: int = int(bv.get("mana_threshold", 5))
	var my_name: String   = card_data.get("Name", card.card_id)

	print("========== BEHOLD DEBUG: %s (owner=%d) =========" % [my_name, card.owner_player_id])
	var beheld_cards: Array = cm.get_beheld_cards(card.owner_player_id)
	print("  Total beheld: %d" % beheld_cards.size())

	var count := 0
	for c in beheld_cards:
		var c_id   = c.card_id
		var c_data = CardDatabase.CARDS.get(c_id)
		var c_name = c_data.get("Name", c_id) if c_data else c_id
		var c_type = c_data.get("Type", "?") if c_data else "?"
		var c_cost = int(c_data.get("Cost", 0)) if c_data else 0
		var is_proxy     = "_is_proxy" in c
		var on_board     = ("card_slot_is_in" in c) and c.card_slot_is_in
		var source: String = "(synced hand)" if is_proxy else ("(board)" if on_board else "(hand)")
		var qualifies: bool = (c != card) and c_data != null \
			and (c_type == "Champion" or c_type == "Follower") \
			and c_cost >= mana_threshold

		if qualifies:
			count += 1
			print("  ✓ %s (cost:%d type:%s) %s" % [c_name, c_cost, c_type, source])
		else:
			var reason: String
			if c == card:                 reason = "self"
			elif c_cost < mana_threshold: reason = "cost<%d" % mana_threshold
			else:                         reason = "type:%s" % c_type
			print("  ✗ %s (cost:%d type:%s) %s [skip: %s]" % [c_name, c_cost, c_type, source, reason])

	print("  Result: %d qualifying units" % count)
	print("==================================================")

	if count <= 0:
		print("%s Game End: no %d+ mana units beheld, no buff" % [my_name, mana_threshold])
		return

	var total_buff: int = buff_per_unit * count
	card.power_modifier += total_buff
	var power_label = card.get_node_or_null("CardFront/Power")
	if power_label:
		power_label.text = card.get_power_display_text()
	print("%s Game End: %d units with %d+ mana beheld → +%d Power (now %d)" % [
		my_name, count, mana_threshold, total_buff, card.get_current_power()])


func _game_end_renekton_debuff(card: Node, card_data: Dictionary) -> void:
	"""Renekton lv3 {Game End}: grant a random enemy Champion/Follower in this lane
	-enemy_debuff Power (permanent)."""
	var board := _get_board()
	if not board or not card.card_slot_is_in:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var valid_targets: Array = []
	for enemy in board.get_cards_in_zone(board.get_opposing_zone(zone_key)):
		if not is_instance_valid(enemy) or not enemy.is_resolved:
			continue
		var target_data = CardDatabase.CARDS.get(enemy.card_id)
		if not target_data:
			continue
		var target_type: String = target_data.get("Type", "")
		if target_type != "Champion" and target_type != "Follower":
			continue
		valid_targets.append(enemy)

	var my_name: String = card_data.get("Name", card.card_id)
	if valid_targets.is_empty():
		print("%s Game End: no valid targets to debuff" % my_name)
		return

	var target            = pick_random_target(valid_targets)
	if target == null:
		print("No targetable unit")
		return
	var target_data       = CardDatabase.CARDS.get(target.card_id)
	var target_name: String = target_data.get("Name", target.card_id) if target_data else target.card_id
	var power_before: int = target.get_current_power()
	var debuff_amount: int = int(card_data.get("BalanceValues", {}).get("enemy_debuff", 3))

	target.power_modifier -= debuff_amount
	var power_label = target.get_node_or_null("CardFront/Power")
	if power_label:
		power_label.text = target.get_power_display_text()
	print("%s Game End: granted %s -%d Power (was %d, now %d)" % [
		my_name, target_name, debuff_amount, power_before, target.get_current_power()])


func _ability_nasus_game_end_kill(card: Node) -> void:
	"""Nasus lv3 {Game End}: kill a random enemy Champion/Follower in this lane that
	has strictly less Power than Nasus."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm or not card.card_slot_is_in:
		return

	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return

	var zone_key: Vector2i = board.get_zone_for_slot(card.card_slot_is_in)
	if zone_key == Vector2i(-1, -1):
		return

	var my_power: int        = card.get_current_power()
	var enemy_zone: Vector2i = board.get_opposing_zone(zone_key)
	var valid_targets: Array = []

	for enemy in board.get_cards_in_zone(enemy_zone):
		if not is_instance_valid(enemy) or not enemy.is_resolved:
			continue
		var target_data = CardDatabase.CARDS.get(enemy.card_id)
		if not target_data:
			continue
		var target_type: String = target_data.get("Type", "")
		if target_type != "Champion" and target_type != "Follower":
			continue
		if enemy.get_current_power() < my_power:
			valid_targets.append(enemy)

	var my_name: String = card_data.get("Name", card.card_id)
	if valid_targets.is_empty():
		print("%s Game End: no valid targets (no enemy has less Power than %d)" % [my_name, my_power])
		return

	var target            = pick_random_target(valid_targets)
	if target == null:
		print("No targetable unit")
		return
	var target_data       = CardDatabase.CARDS.get(target.card_id)
	var target_name: String = target_data.get("Name", target.card_id) if target_data else target.card_id
	var target_power: int = target.get_current_power()

	# Death prevention check
	if target.has_method("can_prevent_death") and target.can_prevent_death():
		await card.get_tree().create_timer(0.5).timeout
		target.on_death_prevented()
		print("%s Game End: tried to kill %s, but death was prevented!" % [my_name, target_name])
		return

	# Kill animation
	var killed_anim = target.get_node_or_null("AnimationPlayer")
	if killed_anim and killed_anim.has_animation("card_killed"):
		killed_anim.play("card_killed")
		await killed_anim.animation_finished
	else:
		await card.get_tree().create_timer(0.5).timeout

	cm.track_killed_card(target, card.owner_player_id, card.card_id)

	if target.card_slot_is_in:
		target.card_slot_is_in.card_in_slot = false
	board.remove_card_from_zone(enemy_zone, target)
	board.reposition_cards_in_zone(enemy_zone)
	target.card_slot_is_in = null  # Mark as removed from board (historical tracker guard)
	target.queue_free()

	print("%s Game End: killed %s (Power %d)" % [my_name, target_name, target_power])


# ─── Game Start abilities ──────────────────────────────────────────────────────

func _game_start_summon_sun_disc(owner_player_id: int) -> void:
	"""Azir {Game Start}: summon a Buried Sun Disc in the mid-lane on the owner's side.
	In multiplayer, the opponent is notified via RPC so they can place it on their board."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm:
		print("AbilityResolver: cannot summon Sun Disc — Board or CardManager not found")
		return

	var my_row: int       = board.get_ally_row(owner_player_id)
	var mid_zone: Vector2i = Vector2i(1, my_row)  # column B = index 1
	var zone_slots: Array = board.slots_by_zone.get(mid_zone, [])
	if zone_slots.is_empty():
		print("AbilityResolver: cannot find mid lane zone for Sun Disc")
		return

	var available_slot = null
	for slot in zone_slots:
		if not slot.card_in_slot:
			available_slot = slot
			break
	if not available_slot:
		print("AbilityResolver: no available slot in mid lane for Sun Disc")
		return

	var card_scene = preload("res://Scenes/Card.tscn")
	var sun_disc   = card_scene.instantiate()

	sun_disc.card_id          = "BuriedSunDisc"
	sun_disc.owner_player_id  = owner_player_id
	CardDatabase.populate_card_visuals(sun_disc, CardDatabase.CARDS["BuriedSunDisc"])

	sun_disc.position                                        = available_slot.position
	sun_disc.scale                                           = Vector2(0.15, 0.15)
	sun_disc.z_index                                         = 0
	sun_disc.card_slot_is_in                                 = available_slot
	sun_disc.get_node("Area2D/CollisionShape2D").disabled    = true
	sun_disc.is_resolved                                     = true
	if sun_disc.has_method("hide_card_back"):
		sun_disc.hide_card_back()

	cm.add_child(sun_disc)
	available_slot.card_in_slot = true
	board.add_card_to_zone(mid_zone, sun_disc)
	cm.add_card_to_play_order(sun_disc)
	cm.track_summoned_card(sun_disc, false)  # summoned directly (not from hand)
	cm.track_created_card(sun_disc, owner_player_id, "Azir1")  # created by Azir

	print("Buried Sun Disc summoned at mid lane!")

	# Multiplayer: notify opponent (mirror the zone row from our side to theirs)
	if _is_online():
		var mirrored: Vector2i = Vector2i(mid_zone.x, 1 - mid_zone.y)
		rpc("_receive_opponent_game_start_summon", "BuriedSunDisc", mirrored.x, mirrored.y)


@rpc("any_peer", "reliable")
func _receive_opponent_game_start_summon(card_id_str: String, zone_col: int, zone_row: int) -> void:
	"""Receive the opponent's {Game Start} summon and place their card face-up on our board."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm:
		return

	var zone_key: Vector2i = Vector2i(zone_col, zone_row)
	var zone_slots: Array  = board.slots_by_zone.get(zone_key, [])

	var available_slot = null
	for slot in zone_slots:
		if not slot.card_in_slot:
			available_slot = slot
			break
	if not available_slot:
		print("AbilityResolver: no slot for opponent game-start summon in zone: ", zone_key)
		return

	var card_scene = preload("res://Scenes/Card.tscn")
	var opp_card   = card_scene.instantiate()

	opp_card.card_id         = card_id_str
	opp_card.owner_player_id = 0  # opponent is always player 0 from our view

	var card_data = CardDatabase.CARDS.get(card_id_str)
	if card_data:
		CardDatabase.populate_card_visuals(opp_card, card_data)

	opp_card.position                                       = available_slot.position
	opp_card.scale                                          = Vector2(0.15, 0.15)
	opp_card.z_index                                        = 0
	opp_card.card_slot_is_in                                = available_slot
	opp_card.get_node("Area2D/CollisionShape2D").disabled   = true
	opp_card.is_resolved                                    = true
	if opp_card.has_method("hide_card_back"):
		opp_card.hide_card_back()

	cm.add_child(opp_card)
	available_slot.card_in_slot = true
	board.add_card_to_zone(zone_key, opp_card)
	cm.add_card_to_play_order(opp_card)
	cm.track_summoned_card(opp_card, false)  # summoned directly (not from hand)
	cm.track_created_card(opp_card, opp_card.owner_player_id, "Azir1")  # created by opponent's Azir

	print("Opponent game-start summon received: %s in zone %s" % [card_id_str, str(zone_key)])


# ─── Swap-arrive abilities ─────────────────────────────────────────────────────

func execute_swap_arrive_ability(card: Node, to_zone: Vector2i, from_zone: Vector2i) -> void:
	"""Called by SwapLaneManager after an Elusive card completes its swap tween.
	Dispatches the card's swap-arrive ability, if any."""
	if not is_instance_valid(card) or card.card_id == "":
		return
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return
	var ability_type: String = card_data.get("AbilityType", "none")
	match ability_type:
		"swap_arrive_recall":
			await _ability_swap_arrive_recall(card, to_zone)
		"swap_arrive_summon_blade":
			await _ability_swap_arrive_summon_blade(card, from_zone)
		_:
			pass


func _ability_swap_arrive_recall(card: Node, to_zone: Vector2i) -> void:
	"""Ahri {Swap Lane}: recall the weakest resolved ally at the destination zone.
	The recalled ally is returned to its owner's hand. Landmarks are excluded.
	Ahri Lv2 additionally reduces the recalled card's cost by recall_cost_reduction."""
	var board      := _get_board()
	var cm         := _get_card_manager()
	var card_data  := CardDatabase.CARDS.get(card.card_id, {}) as Dictionary
	if not board or not cm:
		return

	# Find the weakest resolved ally at the destination (exclude Ahri herself and Landmarks)
	var weakest_card = null
	var weakest_power: float = INF

	for c in board.get_cards_in_zone(to_zone):
		if not is_instance_valid(c) or c == card:
			continue
		if c.owner_player_id != card.owner_player_id:
			continue
		if not c.is_resolved:
			continue
		var card_type: String = CardDatabase.CARDS.get(c.card_id, {}).get("Type", "")
		if card_type != "Champion" and card_type != "Follower":
			continue
		var power: float = c.get_current_power() if c.has_method("get_current_power") else 0.0
		if power < weakest_power or (power == weakest_power and weakest_card != null and c.card_id < weakest_card.card_id):
			weakest_power = power
			weakest_card  = c

	if not weakest_card:
		print("Ahri swap-arrive: no valid ally to recall in zone %s" % str(to_zone))
		return

	print("Ahri swap-arrive recall: %s (power %d) from zone %s" % [
		weakest_card.card_id, int(weakest_power), str(to_zone)])
	await cm.recall_card(weakest_card, card.owner_player_id, card.card_id)

	# Ahri Lv2: reduce the recalled card's cost (Ahri1 has no recall_cost_reduction key → 0)
	var cost_reduction: int = int(card_data.get("BalanceValues", {}).get("recall_cost_reduction", 0))
	if cost_reduction > 0 and is_instance_valid(weakest_card):
		cm.adjust_cost(weakest_card, -cost_reduction)

	LevelUpManager._check_ahri_levelup()
	await cm._wait_for_level_up()


func _ability_swap_arrive_summon_blade(card: Node, from_zone: Vector2i) -> void:
	"""Irelia {Swap Lane}: summon a Blade at the original (from) lane.
	Runs only on the owning player's client; opponent is notified via RPC."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm:
		return
	var owner_id: int = card.owner_player_id

	# Find first available slot in from_zone (Irelia has already left it)
	var zone_slots: Array = board.slots_by_zone.get(from_zone, [])
	var available_slot = null
	for slot in zone_slots:
		if not slot.card_in_slot:
			available_slot = slot
			break
	if not available_slot:
		print("Irelia swap-arrive: no slot for Blade in zone %s" % str(from_zone))
		return

	# Summon Blade (standard 8-step pattern)
	var card_scene = preload("res://Scenes/Card.tscn")
	var blade = card_scene.instantiate()
	blade.card_id = "Blade"
	blade.owner_player_id = owner_id
	CardDatabase.populate_card_visuals(blade, CardDatabase.CARDS["Blade"])
	blade.position = available_slot.position
	blade.scale = Vector2(0.15, 0.15)
	blade.z_index = 0
	blade.card_slot_is_in = available_slot
	blade.get_node("Area2D/CollisionShape2D").disabled = true
	blade.is_resolved = true
	blade.hide_card_back()

	cm.add_child(blade)
	available_slot.card_in_slot = true
	board.add_card_to_zone(from_zone, blade)
	cm.add_card_to_play_order(blade)
	cm.track_summoned_card(blade, false)
	cm.track_created_card(blade, owner_id, card.card_id)
	cm._notify_zone_power_changed()

	# Immediately check if Irelia can level up after the new Blade was tracked
	LevelUpManager._check_irelia_levelup()
	await cm._wait_for_level_up()

	print("Irelia swap-arrive: Blade summoned at zone %s" % str(from_zone))

	# Multiplayer: notify opponent to mirror-summon the Blade
	if _is_online():
		var mirrored := Vector2i(from_zone.x, 1 - from_zone.y)
		rpc("_receive_opponent_irelia_blade_summon", mirrored.x, mirrored.y, owner_id, card.card_id)


@rpc("any_peer", "reliable")
func _receive_opponent_irelia_blade_summon(zone_col: int, zone_row: int,
		owner_player_id: int, creator_card_id: String) -> void:
	"""Receive Irelia's Blade summon from the opponent's ability resolution."""
	var board := _get_board()
	var cm    := _get_card_manager()
	if not board or not cm:
		return

	var zone_key := Vector2i(zone_col, zone_row)
	var zone_slots: Array = board.slots_by_zone.get(zone_key, [])
	var available_slot = null
	for slot in zone_slots:
		if not slot.card_in_slot:
			available_slot = slot
			break
	if not available_slot:
		print("Irelia blade RPC: no slot in zone %s" % str(zone_key))
		return

	var card_scene = preload("res://Scenes/Card.tscn")
	var blade = card_scene.instantiate()
	blade.card_id = "Blade"
	blade.owner_player_id = owner_player_id
	CardDatabase.populate_card_visuals(blade, CardDatabase.CARDS["Blade"])
	blade.position = available_slot.position
	blade.scale = Vector2(0.15, 0.15)
	blade.z_index = 0
	blade.card_slot_is_in = available_slot
	blade.get_node("Area2D/CollisionShape2D").disabled = true
	blade.is_resolved = true
	blade.hide_card_back()

	cm.add_child(blade)
	available_slot.card_in_slot = true
	board.add_card_to_zone(zone_key, blade)
	cm.add_card_to_play_order(blade)
	cm.track_summoned_card(blade, false)
	cm.track_created_card(blade, owner_player_id, creator_card_id)
	cm._notify_zone_power_changed()

	print("Irelia blade RPC received: Blade at zone %s" % str(zone_key))


# ─── Shared helpers ────────────────────────────────────────────────────────────

func _calc_zone_power(board: Node, zone_key: Vector2i) -> int:
	"""Sum the current Power of every RESOLVED card in a zone.
	Unresolved (face-down) cards are excluded so they don't affect lane comparisons."""
	var total := 0
	for card in board.get_cards_in_zone(zone_key):
		if is_instance_valid(card) and card.is_resolved:
			total += card.get_current_power()
	return total
