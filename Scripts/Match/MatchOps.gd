## Primitives that mutate a MatchState and publish what they changed.
##
## Every function here changes the state AND emits the matching event through the
## Callable the engine handed in, so a caller never describes the same change twice.
## An unknown instance id is a silent no-op (or -1 / false). There are deliberately
## no phase checks here: the caller decides when a primitive may run.
## No Node, no scene tree, no signals, no autoloads — and all randomness goes
## through the MatchState's own rng.
class_name MatchOps extends RefCounted

var state: MatchState
var abilities: MatchAbilities

var _emit: Callable


func _init(p_state: MatchState, p_emit: Callable, p_abilities: MatchAbilities) -> void:
	"""Bind to a state, the event sink and the ability hooks."""
	state = p_state
	_emit = p_emit
	abilities = p_abilities


# --- Drawing ---

## Moves the top card of `player`'s deck into their hand, records the draw tracker
## (Janna's level-up counts these) and emits it. Returns the new instance id, or -1
## when the deck is empty — then nothing at all is emitted. A player whose deck runs
## out goes Deep.
func draw(player: int) -> int:
	if not _is_player(player):
		return -1
	var id: int = state.draw_top(player)
	if id < 0:
		return -1
	var card := state.card(id)
	state.drawn.append({
		"card_id": card.card_id,
		"owner_player_id": player,
		"turn": state.turn,
		"instance_id": id,
	})
	emit_event(MatchEvents.card_drawn(player, id, card.card_id))
	if abilities != null:
		abilities.on_card_drawn(id)
	if state.players[player].deck.is_empty():
		set_deep(player)
	return id


## Creates a new card straight into `player`'s hand, records the created tracker and
## emits it. `creator_id` names the card responsible (-1 = lane, environment or
## unknown), which decides the tracker's creator_player_id / creator_card_id.
## An unknown card id returns -1 and changes nothing.
func create_in_hand(card_id: String, player: int, creator_id: int = -1) -> int:
	if not _is_player(player):
		return -1
	if not _is_known_card(card_id):
		return -1
	var card := state.new_card(card_id, player, CardState.Location.HAND)
	state.add_to_hand(player, card.instance_id)
	var creator := _creator_of(creator_id)
	state.created.append({
		"card_id": card_id,
		"owner_player_id": player,
		"creator_player_id": creator.owner if creator != null else player,
		"creator_card_id": creator.card_id if creator != null else "",
		"created_at_turn": state.turn,
		"instance_id": card.instance_id,
	})
	emit_event(MatchEvents.card_created_in_hand(player, card.instance_id, card_id, creator_id))
	return card.instance_id


## Puts a brand new card face-up on the board, appended to the end of (col, owner),
## and records it as summoned (is_resolved) and as created. `creator_id` -1 means a
## lane / the environment, which the created tracker records as creator_player_id -1.
## A full target zone or an unknown card id returns -1 and changes nothing.
func summon(card_id: String, owner: int, col: int, creator_id: int = -1) -> int:
	if not _is_player(owner):
		return -1
	if not _is_known_card(card_id):
		return -1
	if not state.zone_has_space(col, owner):
		return -1
	var card := state.new_card(card_id, owner, CardState.Location.BOARD)
	var id: int = card.instance_id
	if not state.place_card(id, col, owner):
		return -1
	card.is_resolved = true
	if not state.play_order.has(id):
		state.play_order.append(id)
	state.summoned.append({
		"card_id": card_id,
		"owner_player_id": owner,
		"was_played_from_hand": false,
		"is_resolved": true,
		"instance_id": id,
	})
	var creator := _creator_of(creator_id)
	state.created.append({
		"card_id": card_id,
		"owner_player_id": owner,
		"creator_player_id": creator.owner if creator != null else -1,
		"creator_card_id": creator.card_id if creator != null else "",
		"created_at_turn": state.turn,
		"instance_id": id,
	})
	emit_event(MatchEvents.card_summoned(owner, id, card_id, col, card.slot))
	return id


## Shuffles a card the player is holding back into their deck at a random position,
## keeping its permanent cost modifier (Sunken Temple). Not in hand = no-op.
func shuffle_into_deck(player: int, id: int) -> void:
	if not _is_player(player):
		return
	var card := state.card(id)
	if card == null or not state.players[player].hand.has(id):
		return
	state.remove_from_hand(player, id)
	card.location = CardState.Location.DECK
	card.col = -1
	card.slot = -1
	var deck: Array[int] = state.players[player].deck
	deck.insert(state.rng.randi_range(0, deck.size()), id)
	emit_event(MatchEvents.card_shuffled_into_deck(player, id, card.card_id))


# --- Stats, keywords ---

## Adds `delta` to the card's permanent power and emits the new value. 0 is a no-op.
func change_power(id: int, delta: int) -> void:
	var card := state.card(id)
	if card == null or delta == 0:
		return
	card.power_modifier += delta
	emit_event(MatchEvents.power_changed(id, delta, card.get_current_power()))


## Adds `delta` to the card's permanent cost and emits the new value (clamped at 0 by
## CardState.get_current_cost()). 0 is a no-op.
func change_cost(id: int, delta: int) -> void:
	var card := state.card(id)
	if card == null or delta == 0:
		return
	card.cost_modifier += delta
	emit_event(MatchEvents.cost_changed(id, delta, card.get_current_cost()))


## Grants a runtime keyword; a keyword the card already has is not added twice.
func add_keyword(id: int, keyword: String) -> void:
	var card := state.card(id)
	if card == null or card.runtime_keywords.has(keyword):
		return
	card.runtime_keywords.append(keyword)
	emit_event(MatchEvents.keyword_added(id, keyword))


## Takes a runtime keyword away again; a card that never had it emits nothing.
func remove_keyword(id: int, keyword: String) -> void:
	var card := state.card(id)
	if card == null:
		return
	var idx := card.runtime_keywords.find(keyword)
	if idx < 0:
		return
	card.runtime_keywords.remove_at(idx)
	emit_event(MatchEvents.keyword_removed(id, keyword))


## Returns true when the card is currently stunned.
func is_stunned(id: int) -> bool:
	for entry in state.stuns:
		if int(entry.get("instance_id", -1)) == id:
			return true
	return false


## Sum of the power of every RESOLVED card in (col, player); face-down cards do not
## count, exactly like GameManager._get_zone_total_power.
func lane_power(col: int, player: int) -> int:
	var total: int = 0
	for id in state.zone_cards(col, player):
		var card := state.card(id)
		if card == null or not card.is_resolved:
			continue
		total += card.get_current_power()
	return total


# --- Mana ---

## Spends `amount` from the player's pool and emits the new value. Returns false and
## changes nothing when they cannot afford it; a non-positive amount always succeeds.
func spend_mana(player: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if not _is_player(player):
		return false
	var p := state.players[player]
	if p.current_mana < amount:
		return false
	p.current_mana -= amount
	emit_event(MatchEvents.mana_changed(player, p.current_mana, p.get_max_mana()))
	return true


## Gives `amount` back, never past the player's maximum, and emits the new value.
func refund_mana(player: int, amount: int) -> void:
	if not _is_player(player):
		return
	var p := state.players[player]
	p.current_mana = mini(p.current_mana + amount, p.get_max_mana())
	emit_event(MatchEvents.mana_changed(player, p.current_mana, p.get_max_mana()))


## Queues bonus mana that only becomes active at the start of the next turn; nothing
## is emitted because nothing has changed yet.
func queue_temp_mana(player: int, amount: int) -> void:
	if not _is_player(player):
		return
	state.players[player].pending_bonus_mana += amount


# --- Player status ---

## Marks the player as Deep (their deck ran out). Once Deep, always Deep: later
## draws from a refilled deck do not undo it.
func set_deep(player: int) -> void:
	if not _is_player(player):
		return
	var p := state.players[player]
	if p.is_deep:
		return
	p.is_deep = true
	emit_event(MatchEvents.deep_changed(player, true))


# --- Escape hatch ---

## Publishes a custom event through the same sink as everything else, for lanes and
## abilities whose effect the engine itself does not build.
func emit_event(event: Dictionary) -> void:
	if _emit.is_valid():
		_emit.call(event)


# --- Internals ---

## Returns true when `player` is one of the two absolute player ids.
func _is_player(player: int) -> bool:
	return player >= 0 and player < state.players.size()


## Returns true when the card id exists in CardDatabase.
func _is_known_card(card_id: String) -> bool:
	return not card_id.is_empty() and CardDatabase.CARDS.has(card_id)


## Returns the card responsible for a creation, or null for -1 / an unknown id.
func _creator_of(creator_id: int) -> CardState:
	if creator_id < 0:
		return null
	return state.card(creator_id)
