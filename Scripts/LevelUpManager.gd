extends Node

## LevelUpManager – owns ALL champion level-up condition checks and Sun Disc logic.
## AutoLoad singleton: accessible from any script via LevelUpManager.<method>.
##
## These checks were previously scattered across CardManager (the _check_* funcs)
## and Card.gd (_check_level_up_by_power). Centralising them here means adding a
## new champion only requires changes to CardDatabase + this file.


# ─── Scene-tree helpers ────────────────────────────────────────────────────────

func _get_card_manager() -> Node:
	return get_node_or_null("/root/Main/CardManager")


func _get_board() -> Node:
	return get_node_or_null("/root/Main/Board")


func _get_deck() -> Node:
	return get_node_or_null("/root/Main/Deck")


func _notify_zone_power_changed() -> void:
	"""Proxy call to CardManager so level-up side-effects refresh the UI."""
	var cm := _get_card_manager()
	if cm and cm.has_method("_notify_zone_power_changed"):
		cm._notify_zone_power_changed()


# ─── Public entry points (called by CardManager) ──────────────────────────────

func check_level_ups_after_resolve(resolved_card: Node) -> void:
	"""Called by CardManager after each card resolves during the resolve phase.
	Checks whether the newly revealed card triggers a level-up for any champion."""
	if not is_instance_valid(resolved_card):
		return
	_check_trundle_levelup(resolved_card)
	_check_azir_levelup()
	_check_xerath_levelup()
	_check_nasus_levelup()
	_check_sun_disc_transform()


func check_level_ups_after_abilities() -> void:
	"""Called by CardManager after round-start / round-end ability loops complete.
	Re-checks state-based conditions that may have been satisfied by ability effects."""
	_check_azir_levelup()
	_check_xerath_levelup()
	_check_nasus_levelup()
	_check_sun_disc_transform()


func check_level_up_by_power(card: Node) -> void:
	"""Called by AbilityResolver after any ability that can increase power_modifier.
	Renekton lv1 → lv2: levels up when power_modifier >= BalanceValues.power_threshold."""
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return
	var level_up_to = card_data.get("LevelUpTo", null)
	if level_up_to == null or str(level_up_to) == "":
		return
	# Only applies to cards whose on-board buff tracks towards a level-up.
	if card_data.get("AbilityType", "") == "conditional_buff" and card_data.get("Level", 1) == 1:
		var power_threshold: int = int(card_data.get("BalanceValues", {}).get("power_threshold", 4))
		if card.power_modifier >= power_threshold:
			print("%s met level-up condition! (power_modifier=%d >= %d)" % [
				card_data.get("Name", card.card_id), card.power_modifier, power_threshold])
			card._perform_level_up(str(level_up_to))
			# If Sun Disc is already restored, immediately push to lv3.
			_check_ascended_sun_disc_upgrade(card)


# ─── Sun Disc helpers ──────────────────────────────────────────────────────────

func _is_sun_disc_restored(owner_id: int) -> bool:
	"""Returns true if the given player has a Restored Sun Disc on the board."""
	var cm := _get_card_manager()
	if not cm:
		return false
	for card in cm.all_cards_in_play_order:
		if not is_instance_valid(card) or card.owner_player_id != owner_id:
			continue
		if not card.card_slot_is_in:  # card removed from board
			continue
		var card_data = CardDatabase.CARDS.get(card.card_id)
		if card_data and card_data.get("Name", "") == "Restored Sun Disc":
			return true
	return false


func _check_ascended_sun_disc_upgrade(card: Node) -> void:
	"""If Sun Disc is already restored and this card just became lv2 Ascended,
	immediately push it to lv3.  Called right after any 1→2 level-up."""
	if not is_instance_valid(card):
		return
	var card_data = CardDatabase.CARDS.get(card.card_id)
	if not card_data:
		return
	if card_data.get("Type", "") != "Champion":
		return
	if card_data.get("SubType", "") != "Ascended":
		return
	if card_data.get("Level", 1) != 2:
		return
	if not _is_sun_disc_restored(card.owner_player_id):
		return
	var level_up_to = card_data.get("LevelUpTo", "")
	if level_up_to and str(level_up_to) != "":
		print("%s is lv2 Ascended and Sun Disc already restored — leveling up to lv3!" % card_data.get("Name", ""))
		card._perform_level_up(str(level_up_to))
		_notify_zone_power_changed()


# ─── Individual level-up checks ───────────────────────────────────────────────

func _check_azir_levelup() -> void:
	"""Azir lv1 → lv2: levels up when ally_threshold+ summoned allies or
	landmarks are tracked in cm.summoned_cards (excludes Azir itself)."""
	var cm := _get_card_manager()
	if not cm:
		return

	for azir_card in cm.all_cards_in_play_order:
		if not is_instance_valid(azir_card) or not azir_card.is_resolved:
			continue
		if not azir_card.card_slot_is_in:  # card removed from board
			continue
		var azir_data = CardDatabase.CARDS.get(azir_card.card_id)
		if not azir_data:
			continue
		if azir_data.get("Name", "") != "Azir" or azir_data.get("Level", 1) != 1:
			continue

		var owner_id: int     = azir_card.owner_player_id
		var ally_threshold: int = int(azir_data.get("BalanceValues", {}).get("ally_threshold", 6))
		var count := 0

		# Count summoned allies and landmarks from summoned_cards tracker
		for summoned_entry in cm.summoned_cards:
			if int(summoned_entry.get("owner_player_id", -1)) != owner_id:
				continue
			var summoned_card_id: String = summoned_entry.get("card_id", "")
			# Skip Azir itself (don't count self)
			if summoned_card_id == azir_card.card_id:
				continue
			var card_data = CardDatabase.CARDS.get(summoned_card_id)
			if not card_data:
				continue
			var card_type: String = card_data.get("Type", "")
			# Count Champions, Followers, and Landmarks
			if card_type == "Landmark" or card_type == "Champion" or card_type == "Follower":
				count += 1

		if count < ally_threshold:
			continue

		var level_up_to = azir_data.get("LevelUpTo", "")
		if not level_up_to or str(level_up_to) == "":
			continue

		print("Azir has summoned %d allies/landmarks — leveling up to lv2!" % count)
		azir_card._perform_level_up(str(level_up_to))
		_notify_zone_power_changed()
		_check_ascended_sun_disc_upgrade(azir_card)


func _check_trundle_levelup(resolved_card: Node) -> void:
	"""Trundle lv1 → lv2: levels up when the player resolves an Ice Pillar."""
	var cm := _get_card_manager()
	if not cm:
		return

	var resolved_data = CardDatabase.CARDS.get(resolved_card.card_id)
	if not resolved_data or resolved_data.get("Name", "") != "Ice Pillar":
		return

	var owner_id: int = resolved_card.owner_player_id

	for card in cm.all_cards_in_play_order:
		if not is_instance_valid(card) or card.owner_player_id != owner_id:
			continue
		if not card.card_slot_is_in:  # card removed from board
			continue
		var card_data = CardDatabase.CARDS.get(card.card_id)
		if not card_data:
			continue
		if card_data.get("Name", "") == "Trundle" and card_data.get("AbilityType", "") == "create_card":
			var level_up_to = card_data.get("LevelUpTo", "")
			if level_up_to and str(level_up_to) != "":
				print("Ice Pillar resolved — Trundle levels up!")
				card._perform_level_up(str(level_up_to))
				_notify_zone_power_changed()


func _check_xerath_levelup() -> void:
	"""Xerath lv1 → lv2: levels up when ally_threshold+ allied resolved
	Champions/Followers (including Xerath) have increased power (power_modifier > 0)."""
	var cm := _get_card_manager()
	if not cm:
		return

	for xerath_card in cm.all_cards_in_play_order:
		if not is_instance_valid(xerath_card) or not xerath_card.is_resolved:
			continue
		if not xerath_card.card_slot_is_in:  # card removed from board
			continue
		var xerath_data = CardDatabase.CARDS.get(xerath_card.card_id)
		if not xerath_data:
			continue
		if xerath_data.get("Name", "") != "Xerath" or xerath_data.get("AbilityType", "") != "drain_power":
			continue

		var owner_id: int      = xerath_card.owner_player_id
		var ally_threshold: int = int(xerath_data.get("BalanceValues", {}).get("ally_threshold", 4))
		var buffed_count := 0

		for card in cm.all_cards_in_play_order:
			if not is_instance_valid(card) or card.owner_player_id != owner_id or not card.is_resolved:
				continue
			if not card.card_slot_is_in:  # card removed from board
				continue
			var c_data = CardDatabase.CARDS.get(card.card_id)
			if not c_data:
				continue
			var c_type: String = c_data.get("Type", "")
			if c_type != "Champion" and c_type != "Follower":
				continue
			if card.power_modifier > 0:
				buffed_count += 1

		if buffed_count >= ally_threshold:
			var level_up_to = xerath_data.get("LevelUpTo", "")
			if level_up_to and str(level_up_to) != "":
				print("Xerath lv1 sees %d allies with increased power — leveling up!" % buffed_count)
				xerath_card._perform_level_up(str(level_up_to))
				_check_ascended_sun_disc_upgrade(xerath_card)
				_notify_zone_power_changed()


func _check_nasus_levelup() -> void:
	"""Nasus lv1 → lv2: levels up when the owning player has killed kill_threshold+
	units (only kills where killer_player_id matches Nasus's owner are counted)."""
	var cm := _get_card_manager()
	if not cm or cm.killed_cards.is_empty():
		return

	for card in cm.all_cards_in_play_order:
		if not is_instance_valid(card) or not card.is_resolved:
			continue
		if not card.card_slot_is_in:  # card removed from board
			continue
		var card_data = CardDatabase.CARDS.get(card.card_id)
		if not card_data:
			continue
		if card_data.get("Name", "") != "Nasus" or card_data.get("Level", 1) != 1:
			continue

		var kill_threshold: int = int(card_data.get("BalanceValues", {}).get("kill_threshold", 2))
		var owner_id: int       = int(card.owner_player_id)
		var owner_kill_count := 0

		for kill_entry in cm.killed_cards:
			if int(kill_entry.get("killer_player_id", -1)) == owner_id:
				owner_kill_count += 1

		if owner_kill_count < kill_threshold:
			continue

		var level_up_to = card_data.get("LevelUpTo", "")
		if level_up_to and str(level_up_to) != "":
			print("Nasus lv1 met level-up condition! (player %d has %d kills)" % [owner_id, owner_kill_count])
			card._perform_level_up(str(level_up_to))
			_check_ascended_sun_disc_upgrade(card)
			_notify_zone_power_changed()


func _check_sun_disc_transform() -> void:
	"""Buried Sun Disc → Restored Sun Disc: transforms when the owner has
	ascended_threshold+ allied Ascended champions at lv2 on the board."""
	var cm := _get_card_manager()
	if not cm:
		return

	for card in cm.all_cards_in_play_order:
		if not is_instance_valid(card):
			continue
		if not card.card_slot_is_in:  # card removed from board
			continue
		var card_data = CardDatabase.CARDS.get(card.card_id)
		if not card_data:
			continue
		if card_data.get("AbilityType", "") != "transform_landmark":
			continue
		if card_data.get("Name", "") != "Buried Sun Disc":
			continue

		var owner_id: int = card.owner_player_id
		var ascended_lv2_count := 0

		for ally in cm.all_cards_in_play_order:
			if not is_instance_valid(ally) or ally.owner_player_id != owner_id or not ally.is_resolved:
				continue
			if not ally.card_slot_is_in:  # card removed from board
				continue
			var ally_data = CardDatabase.CARDS.get(ally.card_id)
			if not ally_data:
				continue
			if ally_data.get("Type", "") != "Champion" or ally_data.get("SubType", "") != "Ascended":
				continue
			if ally_data.get("Level", 1) == 2:
				ascended_lv2_count += 1

		var ascended_threshold: int = int(card_data.get("BalanceValues", {}).get("ascended_threshold", 2))
		if ascended_lv2_count >= ascended_threshold:
			var level_up_to = card_data.get("LevelUpTo", "")
			if level_up_to and str(level_up_to) != "":
				print("Buried Sun Disc transforms! %d Ascended champions at lv2" % ascended_lv2_count)
				card._perform_level_up(str(level_up_to))
				_on_sun_disc_restored(owner_id)


func _on_sun_disc_restored(owner_id: int) -> void:
	"""Side-effects triggered when Buried Sun Disc transforms into Restored Sun Disc:
	  1. Draw each Ascended card from the deck that is not currently beheld.
	  2. Immediately level up all allied lv2 Ascended champions to lv3."""
	print("Sun Disc restored for player %d!" % owner_id)
	var cm := _get_card_manager()
	if not cm:
		return

	# ── Step 1: draw un-beheld Ascended cards from the deck ───────────────────
	var beheld_cards: Array = cm.get_beheld_cards(owner_id)
	var beheld_names: Array = []
	for bc in beheld_cards:
		var bc_data = CardDatabase.CARDS.get(bc.card_id)
		if bc_data and bc_data.get("SubType", "") == "Ascended":
			var bc_name: String = bc_data.get("Name", "")
			if bc_name != "" and bc_name not in beheld_names:
				beheld_names.append(bc_name)

	var deck_ref := _get_deck()
	if deck_ref and owner_id == cm.current_player_id:
		var cards_to_draw: Array = []
		for deck_card_id in deck_ref.player_deck:
			var deck_data = CardDatabase.CARDS.get(deck_card_id)
			if not deck_data or deck_data.get("SubType", "") != "Ascended":
				continue
			var deck_name: String = deck_data.get("Name", "")
			if deck_name not in beheld_names:
				cards_to_draw.append(deck_card_id)
				beheld_names.append(deck_name)  # prevent drawing duplicates of same champ

		if cards_to_draw.size() > 0:
			print("Restored Sun Disc: drawing %d Ascended cards from deck" % cards_to_draw.size())
			deck_ref.draw_specific_cards(cards_to_draw)
		else:
			print("Restored Sun Disc: no un-beheld Ascended cards in deck to draw")

	# ── Step 2: level up all allied lv2 Ascended champions to lv3 ─────────────
	# Use a snapshot because _perform_level_up changes card_id in place.
	var cards_snapshot: Array = cm.all_cards_in_play_order.duplicate()
	for ally in cards_snapshot:
		if not is_instance_valid(ally) or ally.owner_player_id != owner_id:
			continue
		if not ally.card_slot_is_in:  # card removed from board
			continue
		var ally_data = CardDatabase.CARDS.get(ally.card_id)
		if not ally_data:
			continue
		if ally_data.get("Type", "") != "Champion" or ally_data.get("SubType", "") != "Ascended":
			continue
		if ally_data.get("Level", 1) != 2:
			continue
		var level_up_to = ally_data.get("LevelUpTo", "")
		if level_up_to and str(level_up_to) != "":
			print("%s (lv2 Ascended) leveling up to lv3!" % ally_data.get("Name", ""))
			ally._perform_level_up(str(level_up_to))

	_notify_zone_power_changed()
