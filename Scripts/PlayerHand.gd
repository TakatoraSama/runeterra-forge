extends Node2D

const CARD_WIDTH = 160
const HAND_Y_POSITION = 950
const DEFAULT_CARD_MOVE_SPEED = 0.1

var player_hand = []
var center_screen_x: float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_ensure_layout_initialized()


func _ensure_layout_initialized() -> void:
	# Cards can be added before this node's _ready() runs (e.g. GameManager draws on startup),
	# so make sure layout values are always initialized before use.
	if center_screen_x == 0.0:
		center_screen_x = get_viewport().size.x / 2.0
		
func add_card_to_hand(card, speed):
	_ensure_layout_initialized()
	if card not in player_hand:
		player_hand.insert(0, card)
		update_hand_position(speed)
	else:
		animate_card_to_position(card, card.starting_position, speed)
	
func update_hand_position(speed):
	_ensure_layout_initialized()
	for i in range(player_hand.size()):
		var new_postion = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		var card = player_hand[i]
		card.starting_position = new_postion
		animate_card_to_position(card, new_postion, speed)
		
func calculate_card_position(index):
	var total_width = (player_hand.size() - 1) * CARD_WIDTH
	var x_offset = center_screen_x + index * CARD_WIDTH - total_width / 2
	return x_offset
	
func animate_card_to_position(card, new_position, speed):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, speed)
	
func remove_card_from_hand(card):
	if card in player_hand:
		player_hand.erase(card)
		update_hand_position(DEFAULT_CARD_MOVE_SPEED)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
