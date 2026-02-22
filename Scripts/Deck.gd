extends Node2D

const CARD_SCENE_PATH = "res://Scenes/Card.tscn"
const CARD_DRAW_SPEED = 0.2

# var player_deck = ["1", "2", "3", "4", "9", "31", "2", "2", "3", "4", "9", "31"]
var player_deck = ["1", "2", "3", "4", "9", "31"]
# var player_deck = ["25", "26", "27", "28", "9", "31"]
var owner_player_id: int = 1  # Which player owns this deck (1 = bottom/local)


func _ready() -> void:
	$RichTextLabel.text = str(player_deck.size())


# --- Shuffle ---
func shuffle_deck() -> void:
	player_deck.shuffle()
	print("Deck shuffled. Cards left: ", player_deck.size())


# --- Trigger Game Start abilities (in deck order) ---
func trigger_game_start_abilities() -> void:
	"""Check each card in deck for Game Start abilities and execute them in deck order.
	Logic has moved to AbilityResolver.execute_game_start_ability_for_deck."""
	print("Checking for Game Start abilities...")
	for card_id in player_deck:
		var card_data = CardDatabase.CARDS.get(card_id)
		if not card_data:
			continue
		var skill = card_data.get("Skill", "")
		if skill.begins_with("{Game Start}"):
			print("Game Start ability found for: ", card_data.get("Name", ""))
			await AbilityResolver.execute_game_start_ability_for_deck(card_id, card_data, owner_player_id)


# _execute_game_start_ability, _game_start_summon_sun_disc, _receive_opponent_game_start_summon,
# and _is_online have moved to AbilityResolver.gd.



# --- Draw multiple cards (callable by GameManager or card abilities) ---
func draw_cards(amount: int) -> void:
	for i in range(amount):
		if player_deck.size() == 0:
			print("Deck is empty, cannot draw more cards.")
			return
		draw_card()


# --- Draw a single card (reusable: called by draw_cards, or by card abilities) ---
func draw_card() -> void:
	if player_deck.size() == 0:
		print("Deck is empty, cannot draw.")
		return

	var card_drawn = player_deck[0]
	player_deck.erase(card_drawn)

	if player_deck.size() == 0:
		$Area2D/CollisionShape2D.disabled = true
		$Sprite2D.visible = false
		$RichTextLabel.visible = false

	$RichTextLabel.text = str(player_deck.size())
	var card_scene = preload(CARD_SCENE_PATH)
	var new_card = card_scene.instantiate()

	# Store card ID and ownership for ability system
	new_card.card_id = card_drawn
	new_card.owner_player_id = owner_player_id

	# Set card spawn
	new_card.position = Vector2(150, 940)

	# Set card text
	var drawn_data = CardDatabase.CARDS[card_drawn]
	CardDatabase.populate_card_visuals(new_card, drawn_data)

	$"../CardManager".add_child(new_card)
	new_card.name = "Card"
	$"../PlayerHand".add_card_to_hand(new_card, CARD_DRAW_SPEED)
	new_card.get_node("AnimationPlayer").play("card_flip")


# --- Draw specific cards by ID from the deck (e.g. Restored Sun Disc pulling Ascended) ---
func draw_specific_cards(card_ids: Array) -> void:
	"""Remove each card_id from the deck and draw it into hand.
	If a card_id is not in the deck, it is skipped."""
	for cid in card_ids:
		if cid not in player_deck:
			print("draw_specific_cards: card %s not in deck, skipping" % cid)
			continue

		player_deck.erase(cid)

		if player_deck.size() == 0:
			$Area2D/CollisionShape2D.disabled = true
			$Sprite2D.visible = false
			$RichTextLabel.visible = false

		$RichTextLabel.text = str(player_deck.size())
		var card_scene = preload(CARD_SCENE_PATH)
		var new_card = card_scene.instantiate()

		new_card.card_id = cid
		new_card.owner_player_id = owner_player_id
		new_card.position = Vector2(150, 940)

		var drawn_data = CardDatabase.CARDS[cid]
		CardDatabase.populate_card_visuals(new_card, drawn_data)

		$"../CardManager".add_child(new_card)
		new_card.name = "Card"
		$"../PlayerHand".add_card_to_hand(new_card, CARD_DRAW_SPEED)
		new_card.get_node("AnimationPlayer").play("card_flip")
		print("Drew specific card from deck: %s (ID: %s)" % [drawn_data.Name, cid])
