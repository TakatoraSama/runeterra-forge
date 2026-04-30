extends Node2D

const CARD_DRAW_SPEED = 0.2

# var player_deck = [
# 	{"id": "Azir1", "cost_mod": 0},
# 	{"id": "Renekton1", "cost_mod": 0},
# 	{"id": "Nasus1", "cost_mod": 0},
# 	{"id": "Xerath1", "cost_mod": 0},
# 	{"id": "Tryndamere1", "cost_mod": 0},
# 	{"id": "Ahri1", "cost_mod": 0},
# 	{"id": "Kennen1", "cost_mod": 0},
# 	{"id": "NavoriConspirator", "cost_mod": 0},
# 	{"id": "Janna1", "cost_mod": 0},
# 	{"id": "Draven1", "cost_mod": 0},
# 	{"id": "Rumble1", "cost_mod": 0},
# 	{"id": "Sion1", "cost_mod": 0},
# ]
# var player_deck = [
# 	{"id": "SeaScarab", "cost_mod": 0},
# 	{"id": "Megatusk", "cost_mod": 0},
# 	{"id": "TheBeastBelow", "cost_mod": 0},
# 	{"id": "AbyssalEye", "cost_mod": 0},
# 	{"id": "DevourerOfTheDepths", "cost_mod": 0},
# 	{"id": "TerrorOfTheTides", "cost_mod": 0},
# 	{"id": "Janna1", "cost_mod": 0},
# 	{"id": "Janna1", "cost_mod": 0},
# 	{"id": "Janna1", "cost_mod": 0},
# 	{"id": "Janna1", "cost_mod": 0},
# 	{"id": "Janna1", "cost_mod": 0},
# 	{"id": "Nautilus1", "cost_mod": 0},
# ]
var player_deck = [
	{"id": "Nasus1", "cost_mod": -5},
	{"id": "Nasus1", "cost_mod": -5},
	{"id": "Nasus1", "cost_mod": -5},
	{"id": "Sion1", "cost_mod": -5},
	{"id": "Sion1", "cost_mod": -5},
	{"id": "Sion1", "cost_mod": -5},
	{"id": "Mordekaiser1", "cost_mod": -5},
	{"id": "Janna1", "cost_mod": -5},
	{"id": "Janna1", "cost_mod": -5},
	{"id": "Janna1", "cost_mod": -5},
	{"id": "Mordekaiser1", "cost_mod": -5},
	{"id": "Mordekaiser1", "cost_mod": -5},
]
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
	for entry in player_deck:
		var card_data = CardDatabase.CARDS.get(entry["id"])
		if not card_data:
			continue
		var skill = card_data.get("Skill", "")
		if skill.begins_with("{Game Start}"):
			print("Game Start ability found for: ", card_data.get("Name", ""))
			await AbilityResolver.execute_game_start_ability_for_deck(entry["id"], card_data, owner_player_id)


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

	var entry = player_deck[0]
	player_deck.erase(entry)
	var card_id_str: String = entry["id"]
	var cost_offset: int = entry.get("cost_mod", 0)

	# Safety fallback: if this champion globally leveled up but the deck entry wasn't
	# updated in time (e.g. drawn in the same frame as the level-up), draw the upgraded version.
	var cm_early = $"../CardManager"
	if cm_early and cm_early.has_method("get_upgraded_card_id"):
		card_id_str = cm_early.get_upgraded_card_id(card_id_str)

	if player_deck.size() == 0:
		$Area2D/CollisionShape2D.disabled = true
		$Sprite2D.visible = false
		$RichTextLabel.visible = false

	$RichTextLabel.text = str(player_deck.size())
	var drawn_data = CardDatabase.CARDS[card_id_str]
	var card_scene = CardDatabase.get_card_scene(drawn_data)
	if card_scene == null:
		print("Deck.draw_card: failed to load scene for ", card_id_str)
		return
	var new_card = card_scene.instantiate()
	if new_card.get_script() == null:
		new_card.set_script(CardDatabase.get_card_script(drawn_data))

	# Store card ID and ownership for ability system
	new_card.card_id = card_id_str
	new_card.owner_player_id = owner_player_id

	# Set card spawn
	new_card.position = Vector2(150, 940)

	# Set card text
	CardDatabase.populate_card_visuals(new_card, drawn_data)

	var cm = $"../CardManager"
	cm.add_child(new_card)
	new_card.name = "Card"
	$"../PlayerHand".add_card_to_hand(new_card, CARD_DRAW_SPEED)
	new_card.get_node("AnimationPlayer").play("card_flip")
	new_card.is_in_hand = true
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm:
		new_card.update_glow(gm.get_player_current_mana(new_card.owner_player_id))

	# Apply persistent cost modifier (from Updraft or other effects)
	if cost_offset != 0:
		cm.adjust_cost([new_card], cost_offset)

	# Track for Janna level-up condition
	cm.track_drawn_card(card_id_str, owner_player_id)

	# Check Deep: if the deck is now empty, mark this player as Deep (once-only)
	if player_deck.size() == 0 and cm.has_method("set_player_deep"):
		cm.set_player_deep(owner_player_id)


# --- Draw specific cards by ID from the deck (e.g. Restored Sun Disc pulling Ascended) ---
func draw_specific_cards(card_ids: Array) -> void:
	"""Remove each card_id from the deck and draw it into hand.
	If a card_id is not in the deck, it is skipped."""
	var cm = $"../CardManager"
	for cid in card_ids:
		var entry = null
		for e in player_deck:
			if e["id"] == cid:
				entry = e
				break
		if entry == null:
			print("draw_specific_cards: card %s not in deck, skipping" % cid)
			continue

		player_deck.erase(entry)
		var cost_offset: int = entry.get("cost_mod", 0)

		if player_deck.size() == 0:
			$Area2D/CollisionShape2D.disabled = true
			$Sprite2D.visible = false
			$RichTextLabel.visible = false

		$RichTextLabel.text = str(player_deck.size())
		var drawn_data = CardDatabase.CARDS[cid]
		var card_scene = CardDatabase.get_card_scene(drawn_data)
		var new_card = card_scene.instantiate()

		new_card.card_id = cid
		new_card.owner_player_id = owner_player_id
		new_card.position = Vector2(150, 940)

		CardDatabase.populate_card_visuals(new_card, drawn_data)

		cm.add_child(new_card)
		new_card.name = "Card"
		$"../PlayerHand".add_card_to_hand(new_card, CARD_DRAW_SPEED)
		new_card.get_node("AnimationPlayer").play("card_flip")
		new_card.is_in_hand = true
		var gm = get_node_or_null("/root/Main/GameManager")
		if gm:
			new_card.update_glow(gm.get_player_current_mana(new_card.owner_player_id))

		if cost_offset != 0:
			cm.adjust_cost([new_card], cost_offset)

		cm.track_drawn_card(cid, owner_player_id)
		print("Drew specific card from deck: %s (ID: %s)" % [drawn_data.Name, cid])

	# Check Deep after all specific draws complete
	if player_deck.size() == 0 and cm.has_method("set_player_deep"):
		cm.set_player_deep(owner_player_id)
