extends Node2D

signal hovered
signal hovered_off

var starting_position 
var card_slot_is_in
var card_id: String = ""
var owner_player_id: int = -1  # Which player owns this card (0 = top, 1 = bottom)
var power_modifier: int = 0  # Runtime power buff/debuff applied to base power
var aura_power_modifier: int = 0  # Aura-based power buff/debuff (recalculated when board changes, not permanent)
var is_resolved: bool = false  # True once this card has been flipped/revealed during resolve

# Cached scene-tree references (set in _ready). Null for preview-only instances.
var _board: Node = null
var _card_manager: Node = null
var _game_manager: Node = null

@onready var card_back: Node2D = $"CardBack"
@onready var animation_player: AnimationPlayer = $"AnimationPlayer"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Guard: preview instances are not parented to CardManager
	if get_parent().has_method("connect_card_signals"):
		get_parent().connect_card_signals(self)
	_set_card_back_hidden()
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	# Cache references so ability methods don't call get_node every time they fire.
	# guard_: preview cards live outside /root/Main so these legitimately return null.
	_board = get_node_or_null("/root/Main/Board")
	_card_manager = get_node_or_null("/root/Main/CardManager")
	_game_manager = get_node_or_null("/root/Main/GameManager")


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _set_card_back_hidden() -> void:
	hide_card_back()


func hide_card_back() -> void:
	if card_back:
		card_back.visible = false
		card_back.z_index = -12


func show_card_back(z_index_value: int = 5) -> void:
	if card_back:
		card_back.visible = true
		card_back.z_index = z_index_value


func set_card_back_z_index(z_index_value: int) -> void:
	if z_index_value >= 0:
		show_card_back(z_index_value)
	else:
		hide_card_back()


func _on_animation_finished(anim_name: StringName) -> void:
	# After any flip animation, keep the back behind the front.
	if anim_name == &"card_flip" or anim_name == &"card_flip_play":
		hide_card_back()


func get_current_power() -> int:
	"""Returns the card's current power (base + permanent modifier + aura modifier)."""
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data or not card_data.has("Power"):
		return 0
	return int(card_data.get("Power", 0)) + power_modifier + aura_power_modifier


func get_power_display_text() -> String:
	"""Returns the power number formatted for the RichTextLabel.
	Wraps in green BBCode when the combined modifier (power_modifier + aura_power_modifier) > 0,
	and red when < 0, so players can see buffed or debuffed power."""
	var value = get_current_power()
	var total_modifier = power_modifier + aura_power_modifier
	if total_modifier > 0:
		return "[color=green]%d[/color]" % value
	elif total_modifier < 0:
		return "[color=red]%d[/color]" % value
	return str(value)


func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)


func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)


func on_summon() -> void:
	"""Called during RESOLVE phase when the card is flipped/revealed.
	Delegates entirely to AbilityResolver so ability logic stays in one place."""
	await AbilityResolver.execute_play_ability(self)



# Phase-based ability triggers (called in play order)
func on_round_start() -> bool:
	"""Triggered at the start of each round. Delegates to AbilityResolver."""
	return await AbilityResolver.execute_round_start_ability(self)


func on_round_end() -> bool:
	"""Triggered at the end of each round. Delegates to AbilityResolver."""
	return await AbilityResolver.execute_round_end_ability(self)


func on_game_end() -> bool:
	"""Triggered at game end. Delegates to AbilityResolver."""
	return await AbilityResolver.execute_game_end_ability(self)


# ---- Level-up / Death prevention ----

func can_prevent_death() -> bool:
	"""Returns true if this card has a death-prevention ability
	(levelup_on_death or survive_death)."""
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data:
		return false
	var ability = card_data.get("AbilityType", "none")
	return ability == "levelup_on_death" or ability == "survive_death"


func on_death_prevented() -> void:
	"""Called instead of dying when can_prevent_death() is true.
	Handles level-up transformation or survive-death buff."""
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data:
		return

	var ability = card_data.get("AbilityType", "none")

	match ability:
		"levelup_on_death":
			# Transform into the LevelUpTo card (e.g. Tryndamere Lv1 -> Lv2)
			var new_id = card_data.get("LevelUpTo", "")
			if new_id and new_id != "":
				_perform_level_up(str(new_id))
			else:
				print("levelup_on_death: no LevelUpTo defined for ", card_id)

		"survive_death":
			# Don't die; grant self +survive_power Power instead
			var buff_amount := int(card_data.get("BalanceValues", {}).get("survive_power", 2))
			power_modifier += buff_amount
			var power_label = get_node_or_null("CardFront/Power")
			if power_label:
				power_label.text = get_power_display_text()
			var name_str = card_data.get("Name", card_id)
			print("%s survived death and gained +%d Power (now %d)" % [
				name_str, buff_amount, get_current_power()])


func _perform_level_up(new_card_id: String) -> void:
	"""Transform this card in-place into a different card (level up).
	Plays a fly-to-center → spin → fly-back animation sequence, then
	updates all visuals to the new card.
	Preserves power_modifier, slot, zone, play order position.
	Acquires a global lock from CardManager so only one level-up animation
	runs at a time — simultaneous level-ups queue up automatically."""
	var new_data = CardDatabase.CARDS.get(new_card_id)
	if not new_data:
		print("_perform_level_up: unknown card id ", new_card_id)
		return

	var old_id = card_id
	var old_name = CardDatabase.CARDS.get(card_id, {}).get("Name", card_id)

	# Update identity immediately so callers reading card_id see the new value
	card_id = new_card_id

	# ── 0. Acquire global level-up lock ──────────────────────────────────
	if _card_manager:
		while _card_manager._level_up_in_progress:
			await get_tree().create_timer(0.05).timeout
		_card_manager._level_up_in_progress = true

	# ── 1. Fly to screen centre and scale up to 0.5 simultaneously (1 sec) ─
	var original_global_pos := global_position
	var original_z := z_index
	var restore_z := original_z
	# Board cards should always return to the board z layer (usually 0).
	if card_slot_is_in:
		if _card_manager and "CARD_BOARD_Z_INDEX" in _card_manager:
			restore_z = int(_card_manager.CARD_BOARD_Z_INDEX)
		else:
			restore_z = 0
	var original_scale := scale  # Store original scale to restore after animation
	z_index = 100  # render on top of everything during the sequence

	var tween_to := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_to.tween_property(self, "global_position", get_viewport_rect().size / 2.0, 1.0)
	tween_to.parallel().tween_property(self, "scale", Vector2(0.5, 0.5), 1.0)
	await tween_to.finished

	# ── 2. Start spin animation; update visuals 1.5 sec in (mid-spin reveal) ─
	animation_player.play("card_levelup_spin")
	await get_tree().create_timer(1.5).timeout

	# ── 3. Update visuals mid-spin ────────────────────────────────────────
	var name_label = get_node_or_null("CardFront/TextContainer/CardName")
	if name_label:
		name_label.text = str(new_data.get("Name", ""))

	var cost_label = get_node_or_null("CardFront/Cost")
	if cost_label:
		cost_label.text = str(new_data.get("Cost", 0))

	CardDatabase.apply_power_visual(self, new_data, self)

	var skill_label = get_node_or_null("CardFront/TextContainer/Skill")
	if skill_label:
		skill_label.text = CardDatabase.format_card_text(str(new_data.get("Skill", "")), new_data.get("BalanceValues", {}))

	var levelup_label = get_node_or_null("CardFront/TextContainer/LevelUp")
	var levelup_separator = get_node_or_null("CardFront/TextContainer/LevelSeperator")
	var new_level_up_text = new_data.get("LevelUp", "")
	if new_level_up_text and str(new_level_up_text) != "":
		if levelup_label:
			levelup_label.text = CardDatabase.format_card_text(str(new_level_up_text), new_data.get("BalanceValues", {}))
			levelup_label.visible = true
		if levelup_separator:
			levelup_separator.visible = true
	else:
		if levelup_label:
			levelup_label.text = ""
			levelup_label.visible = false
		if levelup_separator:
			levelup_separator.visible = false

	var sprite_node = get_node_or_null("CardFront/CardSpriteParent/CardSprite")
	if sprite_node:
		var sprite_path = new_data.get("Sprite", "")
		if sprite_path != "":
			sprite_node.texture = ResourceLoader.load(sprite_path)

	var subtype_label = get_node_or_null("CardFront/SubType")
	var subtype_bg = get_node_or_null("CardFront/CardSubType")
	var new_sub_type = str(new_data.get("SubType", ""))
	if new_sub_type != "":
		if subtype_label:
			subtype_label.text = new_sub_type.to_upper()
			subtype_label.visible = true
		if subtype_bg:
			subtype_bg.visible = true
	else:
		if subtype_label:
			subtype_label.visible = false
		if subtype_bg:
			subtype_bg.visible = false

	# ── 4. Wait for spin animation to finish ────────────────────────────
	await animation_player.animation_finished

	# ── 5. Fly back to current board slot position and scale (1 sec) ─────
	# If the zone was reflowed while this card was leveling up (e.g. another
	# card died and the lane was repositioned), return to the updated slot
	# position instead of the stale pre-animation position.
	var return_global_pos := original_global_pos
	if card_slot_is_in:
		return_global_pos = card_slot_is_in.position
	var tween_back := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween_back.tween_property(self, "global_position", return_global_pos, 1.0)
	tween_back.parallel().tween_property(self, "scale", original_scale, 1.0)
	await tween_back.finished

	z_index = restore_z

	# ── 6. Brief settle pause (0.5 sec) ──────────────────────────────────
	await get_tree().create_timer(0.5).timeout

	# ── 7. Release global level-up lock ──────────────────────────────────
	if _card_manager:
		_card_manager._level_up_in_progress = false

	var new_name = new_data.get("Name", new_card_id)
	print("%s leveled up! %s (ID %s) -> %s (ID %s)" % [
		old_name, old_name, old_id, new_name, new_card_id])
