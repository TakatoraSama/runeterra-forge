extends Node2D

signal hovered
signal hovered_off

var starting_position 
var card_slot_is_in
var card_id: String = ""
var owner_player_id: int = -1  # Which player owns this card (0 = top, 1 = bottom)
var power_modifier: int = 0  # Runtime power buff/debuff applied to base power
var aura_power_modifier: int = 0  # Aura-based power buff/debuff (recalculated when board changes, not permanent)
var aura_cost_modifier: int = 0   # Aura-based cost reduction for hand cards (reset + reapplied with every aura recalc)
var cost_modifier: int = 0  # Runtime cost adjustment (negative = cheaper, positive = more expensive)
var is_resolved: bool = false  # True once this card has been flipped/revealed during resolve
var is_in_hand: bool = false   # True while this card is in the local player's hand
var runtime_keywords: Array = []  # Runtime-applied keywords (e.g. Stun). Not from CardDatabase.
var _dissolve_mat: ShaderMaterial = null

# Board cards return to the board z layer after the level-up animation.
const BOARD_Z_INDEX := 0

@onready var card_back: Node2D = $"CardBack"
@onready var animation_player: AnimationPlayer = $"AnimationPlayer"

const _DISSOLVE_SHADER = preload("res://Materials/card_discard_dissolve.gdshader")
const _STUN_SWIRL_SHADER = preload("res://Materials/stun_swirl.gdshader")

# Stun visual: symbol sits over the art area, clear of the Cost/Power corners.
# Values are in card-local pixels (630×880 card, origin at centre).
const STUN_FADE_TIME := 0.3
const STUN_VFX_SIZE := Vector2(420, 420)
const STUN_VFX_CENTER := Vector2(0, -170)

var _stun_vfx: ColorRect = null
var _stun_tween: Tween = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Guard: preview instances are not parented to CardManager
	if get_parent().has_method("connect_card_signals"):
		get_parent().connect_card_signals(self)
	_set_card_back_hidden()
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	# Apply dissolve shader to each main Sprite2D in CardFront.
	# Sprite2D nodes always supply TEXTURE correctly — unlike CanvasGroup which
	# has a broken framebuffer pipeline in Godot 4.6 when the .tscn assigns a
	# Particles-mode VisualShader. A shared ShaderMaterial means one parameter
	# update dissolves all sprites at once.
	var mat := ShaderMaterial.new()
	mat.shader = _DISSOLVE_SHADER
	mat.set_shader_parameter("dissolve_amount", 0.0)
	mat.set_shader_parameter("edge_width", 0.06)
	mat.set_shader_parameter("edge_color", Color(1.0, 0.5, 0.0, 1.0))
	mat.set_shader_parameter("gradient_weight", 0.5)
	mat.set_shader_parameter("noise_seed", 0.0)
	mat.set_shader_parameter("gray_amount", 0.0)
	mat.set_shader_parameter("stun_amount", 0.0)
	_dissolve_mat = mat
	for path in ["CardFront/CardBase", "CardFront/CardSpriteParent/CardSprite",
			"CardFront/CardMana", "CardFront/CardPower",
			"CardFront/CardSubType", "CardFront/SkillShadow"]:
		var sprite = get_node_or_null(path)
		if sprite:
			sprite.material = mat
	_build_stun_vfx()
	if animation_player:
		animation_player.animation_started.connect(_on_animation_started)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _set_card_back_hidden() -> void:
	hide_card_back()


func update_glow(current_mana: int) -> void:
	if not is_in_hand:
		return
	if get_current_cost() <= current_mana:
		modulate = Color(1, 1, 1, 1)
		if _dissolve_mat:
			_dissolve_mat.set_shader_parameter("gray_amount", 0.0)
	else:
		modulate = Color(0.5, 0.5, 0.5, 1)
		if _dissolve_mat:
			_dissolve_mat.set_shader_parameter("gray_amount", 1.0)


func hide_glow() -> void:
	modulate = Color(1, 1, 1, 1)
	if _dissolve_mat:
		_dissolve_mat.set_shader_parameter("gray_amount", 0.0)


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


func _on_animation_started(anim_name: StringName) -> void:
	# The kill animation only fades CardFront; fade the stun symbol with it.
	if anim_name == &"card_killed":
		_hide_stun_symbol(0.5)


func get_current_power() -> int:
	"""Returns the card's current power (base + permanent modifier + aura modifier)."""
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data or not card_data.has("Power"):
		return 0
	return int(card_data.get("Power", 0)) + power_modifier + aura_power_modifier


func get_current_cost() -> int:
	"""Returns the card's current cost (base + modifier + aura cost modifier), clamped to minimum 0."""
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data:
		return 0
	return max(0, int(card_data.get("Cost", 0)) + cost_modifier + aura_cost_modifier)



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


# Ability triggers used to live on this view and were removed: the Match engine
# owns abilities now, and the presenter plays the death-prevented flash itself.


func play_level_up_animation(new_card_id: String) -> void:
	"""View-only level-up sequence: fly to centre → spin (repopulated mid-spin)
	→ fly back to the current slot → settle.
	Used directly by the presenter in engine mode (the Match engine owns the
	upgrade itself). Callers set card_id to new_card_id before playing; the
	power/cost modifiers and the card's slot are preserved."""
	var new_data = CardDatabase.CARDS.get(new_card_id)
	if not new_data:
		print("play_level_up_animation: unknown card id ", new_card_id)
		return

	# Hide the stun symbol so it doesn't float over the card back mid-spin
	if _stun_vfx:
		_stun_vfx.visible = false

	# ── 1. Fly to screen centre and scale up to 0.5 simultaneously (1 sec) ─
	var original_global_pos := global_position
	var original_z := z_index
	var restore_z := BOARD_Z_INDEX if card_slot_is_in else original_z
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
	CardDatabase.populate_card_visuals(self, new_data, self)
	_refresh_keyword_display()  # Re-apply runtime keywords (e.g. Stun badge) after visual rebuild

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
	if _stun_vfx:
		_stun_vfx.visible = "Stun" in runtime_keywords

	# ── 6. Brief settle pause (0.5 sec) ──────────────────────────────────
	await get_tree().create_timer(0.5).timeout



# ── Runtime keyword management ─────────────────────────────────────────────

func add_runtime_keyword(keyword_name: String) -> void:
	"""Add a runtime keyword badge to this card. Ignores duplicates."""
	if keyword_name in runtime_keywords:
		return
	runtime_keywords.append(keyword_name)
	_refresh_keyword_display()
	if keyword_name == "Stun":
		_set_stun_visual(true)


func remove_runtime_keyword(keyword_name: String) -> void:
	"""Remove a runtime keyword badge from this card. Safe to call if not present."""
	if keyword_name in runtime_keywords:
		runtime_keywords.erase(keyword_name)
		_refresh_keyword_display()
		if keyword_name == "Stun":
			_set_stun_visual(false)


# ── Stun visual ────────────────────────────────────────────────────────────

func _build_stun_vfx() -> void:
	"""Create the spinning 'confused' symbol (procedural shader on a ColorRect). Hidden until stunned."""
	var swirl_mat := ShaderMaterial.new()
	swirl_mat.shader = _STUN_SWIRL_SHADER
	swirl_mat.set_shader_parameter("alpha", 0.0)
	_stun_vfx = ColorRect.new()
	_stun_vfx.name = "StunVfx"
	_stun_vfx.material = swirl_mat
	_stun_vfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stun_vfx.size = STUN_VFX_SIZE
	_stun_vfx.position = STUN_VFX_CENTER - STUN_VFX_SIZE / 2.0
	_stun_vfx.z_index = -4  # above CardFront sprites/labels (-5..-11), below a shown CardBack (5)
	_stun_vfx.visible = false
	add_child(_stun_vfx)


func _set_stun_visual(stunned: bool) -> void:
	"""Fade the purple tint and the swirl symbol in or out."""
	if not _stun_vfx:
		return
	if _stun_tween and _stun_tween.is_valid():
		_stun_tween.kill()
	var target := 1.0 if stunned else 0.0
	var swirl_mat := _stun_vfx.material as ShaderMaterial
	if stunned:
		_stun_vfx.visible = true
	_stun_tween = create_tween().set_parallel(true)
	if _dissolve_mat:
		_stun_tween.tween_method(func(v: float): _dissolve_mat.set_shader_parameter("stun_amount", v),
			float(_dissolve_mat.get_shader_parameter("stun_amount")), target, STUN_FADE_TIME)
	_stun_tween.tween_method(func(v: float): swirl_mat.set_shader_parameter("alpha", v),
		float(swirl_mat.get_shader_parameter("alpha")), target, STUN_FADE_TIME)
	if not stunned:
		_stun_tween.chain().tween_callback(func(): _stun_vfx.visible = false)


func _hide_stun_symbol(duration: float) -> void:
	"""Fade only the swirl symbol (used when the card is killed or dissolved)."""
	if not _stun_vfx or not _stun_vfx.visible:
		return
	if _stun_tween and _stun_tween.is_valid():
		_stun_tween.kill()
	var swirl_mat := _stun_vfx.material as ShaderMaterial
	_stun_tween = create_tween()
	_stun_tween.tween_method(func(v: float): swirl_mat.set_shader_parameter("alpha", v),
		float(swirl_mat.get_shader_parameter("alpha")), 0.0, duration)


func _refresh_keyword_display() -> void:
	"""Rebuild keyword sprites from static card data + runtime_keywords.
	Delegates to CardDatabase.fill_keyword_container() so display stays consistent
	with populate_card_visuals() on every card type."""
	var keyword_container = get_node_or_null("CardFront/TextContainer/KeywordContainer")
	var all_keywords: Array = CardDatabase.CARDS.get(card_id, {}).get("Keyword", []) + runtime_keywords
	CardDatabase.fill_keyword_container(keyword_container, all_keywords)

func play_discard_dissolve(duration: float = 0.8) -> void:
	hide_card_back()
	_hide_stun_symbol(duration)
	if _dissolve_mat:
		_dissolve_mat.set_shader_parameter("noise_seed", CardDatabase.cosmetic_randf() * 100.0)
		var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_method(func(val: float): _dissolve_mat.set_shader_parameter("dissolve_amount", val), 0.0, 1.0, duration)
		tween.parallel().tween_property(self, "modulate:a", 0.0, duration)
		await tween.finished
	else:
		var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "modulate:a", 0.0, duration)
		await tween.finished
