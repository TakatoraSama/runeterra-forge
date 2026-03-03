extends Node

## BotManager – simple AI opponent for offline (single-player) mode.
## AutoLoad singleton: set bot_enabled = true before start_game() is called.
##
## Architecture (synchronous):
##   GameManager.begin_round_start() calls BotManager.on_round_start() directly
##   after mana is refilled. The bot draws a card and queues its play in
##   CardManager._pending_opponent_cards synchronously — no timers, no signals.
##   At RESOLVE the opponent-card-spawning path handles the rest normally.

var bot_enabled: bool = false

## Bot deck — full set including Azir1 (Game Start handled in setup_bot) and
## Trundle1 (create_card ability skips safely when owner_player_id != 1).
## Extra copies of 1-cost cards (Ahri1, Kennen1) to ensure turn-1 playability.
const BOT_DECK: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", 
	"Xerath1", "Tryndamere1", "Trundle1", 
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk"
]

var _bot_deck_remaining: Array = []
var _bot_hand: Array = []       # Array of card_id Strings
var _card_manager: Node = null
var _game_manager: Node = null


# ---------------------------------------------------------------------------
# Public API (called by GameManager)
# ---------------------------------------------------------------------------

func setup_bot(initial_draw_count: int) -> void:
	"""Initialize the bot for a new game.
	Called from GameManager.start_game() right after the human's initial draw."""
	_card_manager = get_node_or_null("/root/Main/CardManager")
	_game_manager = get_node_or_null("/root/Main/GameManager")

	_bot_hand.clear()
	_bot_deck_remaining = BOT_DECK.duplicate()
	_bot_deck_remaining.shuffle()

	_draw_bot_cards(initial_draw_count)

	# Trigger {Game Start} abilities for the bot's deck (same logic as Deck.gd).
	# execute_game_start_ability_for_deck uses owner_player_id to place cards on
	# the correct row, so passing 0 puts the Sun Disc on the bot's side (row 0).
	var triggered: Dictionary = {}
	for card_id in BOT_DECK:
		if triggered.get(card_id, false):
			continue
		var data = CardDatabase.CARDS.get(card_id)
		if data and data.get("Skill", "").begins_with("{Game Start}"):
			AbilityResolver.execute_game_start_ability_for_deck(card_id, data, 0)
			triggered[card_id] = true

	print("BotManager: Initialized. Hand: ", str(_bot_hand))


func on_round_start() -> void:
	"""Called by GameManager.begin_round_start() after mana is refilled.
	Draws one card for the bot then synchronously decides and queues its play."""
	_draw_bot_cards(1)
	_decide_bot_play()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _draw_bot_cards(count: int) -> void:
	for i in range(count):
		if _bot_deck_remaining.is_empty():
			print("BotManager: Deck empty, cannot draw.")
			break
		_bot_hand.append(_bot_deck_remaining.pop_front())
	print("BotManager: Drew %d card(s). Hand size: %d" % [count, _bot_hand.size()])


func _decide_bot_play() -> void:
	"""Pick a random affordable card from hand and queue it to a random open column.
	Runs synchronously — no await, no delay — so the play is always queued before
	the player gets control of the PLAY phase."""
	if not _card_manager or not _game_manager:
		return
	if _bot_hand.is_empty():
		print("BotManager: No cards in hand, passing.")
		return

	var current_mana: int = _game_manager.get_player_current_mana(0)

	# Collect cards the bot can afford
	var playable: Array = []
	for card_id in _bot_hand:
		var data = CardDatabase.CARDS.get(str(card_id))
		if data:
			var cost: int = data.get("Cost", 0)
			if cost <= current_mana:
				playable.append(card_id)

	if playable.is_empty():
		print("BotManager: No affordable cards. Mana: %d, Hand: %s" % [current_mana, str(_bot_hand)])
		return

	# Find lane columns that still have room (max 4 cards per zone)
	var available_cols: Array = []
	if _card_manager.board_reference:
		for c in range(3):
			var zone_key := Vector2i(c, 0)   # row 0 = bot/opponent side
			var zone_cards: Array = _card_manager.board_reference.get_cards_in_zone(zone_key)
			if zone_cards.size() < 4:
				available_cols.append(c)
	else:
		available_cols = [0, 1, 2]

	if available_cols.is_empty():
		print("BotManager: All bot zones are full, passing.")
		return

	# Pick randomly
	var chosen: String = playable[randi() % playable.size()]
	var col: int = available_cols[randi() % available_cols.size()]

	var chosen_data = CardDatabase.CARDS.get(str(chosen))
	var chosen_cost: int = chosen_data.get("Cost", 0) if chosen_data else 0

	# Spend mana and queue the play. _receive_opponent_card_play() appends to
	# _pending_opponent_cards; the card is spawned face-down at RESOLVE start
	# and flips + fires on_summon() exactly like a real opponent's card.
	_game_manager.spend_player_mana(0, chosen_cost)
	_bot_hand.erase(chosen)
	_card_manager._receive_opponent_card_play(chosen, col, 0)

	print("BotManager: Queued '%s' (cost %d) to column %d" % [chosen, chosen_cost, col])
