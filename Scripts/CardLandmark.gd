extends Node2D

signal hovered
signal hovered_off

var starting_position 
var card_slot_is_in
var card_id: String = ""
var owner_player_id: int = -1
var is_resolved: bool = false
var is_in_hand: bool = false
var runtime_keywords: Array = []
var aura_power_modifier: int = 0
var _dissolve_mat: ShaderMaterial = null

var _card_manager: Node = null
var _game_manager: Node = null

@onready var card_back: Node2D = $"CardBack"
@onready var animation_player: AnimationPlayer = $"AnimationPlayer"

const _DISSOLVE_SHADER = preload("res://Materials/card_discard_dissolve.gdshader")

func _ready() -> void:
	if get_parent().has_method("connect_card_signals"):
		get_parent().connect_card_signals(self)
	_set_card_back_hidden()
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)
	_card_manager = get_node_or_null("/root/Main/CardManager")
	_game_manager = get_node_or_null("/root/Main/GameManager")
	var mat := ShaderMaterial.new()
	mat.shader = _DISSOLVE_SHADER
	mat.set_shader_parameter("dissolve_amount", 0.0)
	mat.set_shader_parameter("edge_width", 0.06)
	mat.set_shader_parameter("edge_color", Color(1.0, 0.5, 0.0, 1.0))
	mat.set_shader_parameter("gradient_weight", 0.5)
	mat.set_shader_parameter("noise_seed", 0.0)
	mat.set_shader_parameter("gray_amount", 0.0)
	_dissolve_mat = mat
	for path in ["CardFront/CardBase", "CardFront/CardSpriteParent/CardSprite",
			"CardFront/CardMana", "CardFront/SkillShadow"]:
		var sprite = get_node_or_null(path)
		if sprite:
			sprite.material = mat


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
	if anim_name == &"card_flip" or anim_name == &"card_flip_play":
		hide_card_back()


func get_current_cost() -> int:
	var card_data = CardDatabase.CARDS.get(card_id)
	if not card_data:
		return 0
	return max(0, int(card_data.get("Cost", 0)))


func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self)


func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)


func on_summon() -> void:
	await AbilityResolver.execute_play_ability(self)


func on_round_start() -> bool:
	return await AbilityResolver.execute_round_start_ability(self)


func on_round_end() -> bool:
	return await AbilityResolver.execute_round_end_ability(self)


func on_game_end() -> bool:
	return await AbilityResolver.execute_game_end_ability(self)


func add_runtime_keyword(keyword_name: String) -> void:
	if keyword_name in runtime_keywords:
		return
	runtime_keywords.append(keyword_name)
	_refresh_keyword_display()


func remove_runtime_keyword(keyword_name: String) -> void:
	if keyword_name in runtime_keywords:
		runtime_keywords.erase(keyword_name)
		_refresh_keyword_display()


func _refresh_keyword_display() -> void:
	var keyword_container = get_node_or_null("CardFront/TextContainer/KeywordContainer")
	if not keyword_container:
		return
	for child in keyword_container.get_children():
		child.queue_free()
	var card_data = CardDatabase.CARDS.get(card_id, {})
	var all_keywords: Array = card_data.get("Keyword", []) + runtime_keywords
	if all_keywords.size() > 0:
		keyword_container.visible = true
		var keyword_item_scene = preload("res://Scenes/KeywordItem.tscn")
		for keyword in all_keywords:
			var item = keyword_item_scene.instantiate()
			item.get_node("KeywordSprite").texture = ResourceLoader.load(
				"res://Assets/KeywordSprites/" + str(keyword) + ".webp")
			keyword_container.add_child(item)
	else:
		keyword_container.visible = false

func _perform_level_up(new_card_id: String) -> void:
	var new_data = CardDatabase.CARDS.get(new_card_id)
	if not new_data:
		print("_perform_level_up (landmark): unknown card id ", new_card_id)
		return
	var old_id = card_id
	card_id = new_card_id
	CardDatabase.populate_card_visuals(self, new_data)
	if _card_manager and _card_manager._is_online() \
			and owner_player_id == _card_manager.current_player_id:
		_card_manager.rpc("_receive_opponent_level_up", old_id, new_card_id)


func play_discard_dissolve(duration: float = 0.8) -> void:
	hide_card_back()
	if _dissolve_mat:
		_dissolve_mat.set_shader_parameter("noise_seed", randf() * 100.0)
		var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_method(func(val: float): _dissolve_mat.set_shader_parameter("dissolve_amount", val), 0.0, 1.0, duration)
		tween.parallel().tween_property(self, "modulate:a", 0.0, duration)
		await tween.finished
	else:
		var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "modulate:a", 0.0, duration)
		await tween.finished
