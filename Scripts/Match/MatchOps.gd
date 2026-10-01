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
	# A champion that already levelled up draws as its new level (Deck.draw_card).
	card.card_id = upgraded_id(card.card_id, player)
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


## Pulls the FIRST deck entry with `card_id` out of `player`'s deck and into their
## hand (Deck.draw_specific_cards, used by the Restored Sun Disc). The card does
## NOT have to sit on top of the deck. Everything else — the draw tracker, the
## event, the on_card_drawn hook, the permanent level-up mapping and the Deep
## check — is exactly what draw() does. Returns -1 (and emits nothing) when the
## deck holds no such card.
func draw_specific(player: int, card_id: String) -> int:
	if not _is_player(player):
		return -1
	var deck: Array[int] = state.players[player].deck
	var found: int = -1
	for i in deck.size():
		var card := state.card(deck[i])
		if card != null and card.card_id == card_id:
			found = i
			break
	if found < 0:
		return -1
	var id: int = deck[found]
	deck.remove_at(found)
	state.add_to_hand(player, id)
	var drawn := state.card(id)
	drawn.card_id = upgraded_id(drawn.card_id, player)
	state.drawn.append({
		"card_id": drawn.card_id,
		"owner_player_id": player,
		"turn": state.turn,
		"instance_id": id,
	})
	emit_event(MatchEvents.card_drawn(player, id, drawn.card_id))
	if abilities != null:
		abilities.on_card_drawn(id)
	if deck.is_empty():
		set_deep(player)
	return id


## Creates a new card straight into `player`'s hand, records the created tracker and
## emits it. `creator_id` names the card responsible (-1 = lane, environment or
## unknown), which decides the tracker's creator_player_id / creator_card_id.
## An unknown card id returns -1 and changes nothing.
func create_in_hand(card_id: String, player: int, creator_id: int = -1) -> int:
	if not _is_player(player):
		return -1
	# A champion that already levelled up is created at its new level
	# (CardManager.create_card_in_hand).
	card_id = upgraded_id(card_id, player)
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
	emit_event(MatchEvents.card_summoned(owner, id, card_id, col, card.slot,
		card.get_current_power(), card.get_current_cost(), card.keywords()))
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
	_emit_private(MatchEvents.power_changed(id, delta, card.get_current_power()), id)


## Adds `delta` to the card's permanent cost and emits the new value (clamped at 0 by
## CardState.get_current_cost()). 0 is a no-op.
func change_cost(id: int, delta: int) -> void:
	var card := state.card(id)
	if card == null or delta == 0:
		return
	card.cost_modifier += delta
	_emit_private(MatchEvents.cost_changed(id, delta, card.get_current_cost()), id)


## Grants a runtime keyword; a keyword the card already has is not added twice.
func add_keyword(id: int, keyword: String) -> void:
	var card := state.card(id)
	if card == null or card.runtime_keywords.has(keyword):
		return
	card.runtime_keywords.append(keyword)
	_emit_private(MatchEvents.keyword_added(id, keyword), id)


## Takes a runtime keyword away again; a card that never had it emits nothing.
func remove_keyword(id: int, keyword: String) -> void:
	var card := state.card(id)
	if card == null:
		return
	var idx := card.runtime_keywords.find(keyword)
	if idx < 0:
		return
	card.runtime_keywords.remove_at(idx)
	_emit_private(MatchEvents.keyword_removed(id, keyword), id)


## Returns the player a still-hidden card must be hidden from, or -1 when the change is
## public. A card in a hand or a deck was never shown; a card on the board (lane or
## spell zone) that has NOT resolved is still face-down and just as secret. Once it
## resolves, or once it is GONE, it is public: its identity is out in the open.
func _private_to(id: int) -> int:
	var card := state.card(id)
	if card == null:
		return -1
	if card.location == CardState.Location.HAND or card.location == CardState.Location.DECK:
		return card.owner
	if not card.is_resolved:
		if card.location == CardState.Location.BOARD or card.location == CardState.Location.SPELL_ZONE:
			return card.owner
	return -1


## Publishes `event`, tagged with "private_to" when it concerns a still-hidden card.
func _emit_private(event: Dictionary, id: int) -> void:
	var viewer: int = _private_to(id)
	if viewer >= 0:
		event["private_to"] = viewer
	emit_event(event)


## Publishes an event that concerns card `id` through the same hidden-card rule the stat
## primitives use. This is the door for a module that builds its own event — MatchAuras
## publishes one power_changed per board card whose total moved, and an aura must not
## announce an opponent's face-down card's new power. Events about a card of the
## viewer's own, or about a public one, go out unchanged.
func emit_card_event(event: Dictionary, id: int) -> void:
	_emit_private(event, id)


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
## `hidden` tags the event with "private_to" = player: a spend that happens during PLAY
## is a move the opponent must not watch happen (MatchRules passes it for play and
## undo; the round's true pool is re-published at RESOLVE instead).
func spend_mana(player: int, amount: int, hidden: bool = false) -> bool:
	if amount <= 0:
		return true
	if not _is_player(player):
		return false
	var p := state.players[player]
	if p.current_mana < amount:
		return false
	p.current_mana -= amount
	_emit_mana(player, hidden)
	return true


## Gives `amount` back, never past the player's maximum, and emits the new value.
## `hidden` means exactly what it does in spend_mana.
func refund_mana(player: int, amount: int, hidden: bool = false) -> void:
	if not _is_player(player):
		return
	var p := state.players[player]
	p.current_mana = mini(p.current_mana + amount, p.get_max_mana())
	_emit_mana(player, hidden)


## The one mana_changed for `player`, private to them when `hidden` is set.
func _emit_mana(player: int, hidden: bool) -> void:
	var p := state.players[player]
	var event := MatchEvents.mana_changed(player, p.current_mana, p.get_max_mana())
	if hidden:
		event["private_to"] = player
	emit_event(event)


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
	if abilities != null:
		abilities.on_deep(player)


# --- Queries (no events) ---

## Returns true when the card is anywhere on the board: a lane zone or the spell
## zone. This is the old `card.card_slot_is_in` truthiness test.
func is_on_board(id: int) -> bool:
	var card := state.card(id)
	if card == null:
		return false
	return card.location == CardState.Location.BOARD or card.location == CardState.Location.SPELL_ZONE


## Returns true when the card is a Champion or a Follower (spells and landmarks
## are not units, so they never satisfy an "ally"/"enemy unit" condition).
func is_unit(id: int) -> bool:
	var t: String = card_type(id)
	return t == "Champion" or t == "Follower"


## The CardDatabase "Type" of the card ("" for an unknown id).
func card_type(id: int) -> String:
	var card := state.card(id)
	if card == null:
		return ""
	return str(card.data().get("Type", ""))


## The CardDatabase "Name" of the card ("" for an unknown id). Champions share one
## Name across all their levels, which is what permanently_leveled_up is keyed on.
func card_name(id: int) -> String:
	var card := state.card(id)
	if card == null:
		return ""
	return str(card.data().get("Name", ""))


## The CardDatabase "Level" of the card, 1 when it has none.
func card_level(id: int) -> int:
	var card := state.card(id)
	if card == null:
		return 1
	return int(card.data().get("Level", 1))


## One entry of the card's BalanceValues, or `fallback` when the card is unknown,
## has no BalanceValues, or does not carry that key.
func bv(id: int, key: String, fallback: int) -> int:
	var card := state.card(id)
	if card == null:
		return fallback
	var values: Variant = card.data().get("BalanceValues", {})
	if not (values is Dictionary):
		return fallback
	return int((values as Dictionary).get(key, fallback))


## The instance ids in one zone — a copy of state.zone_cards, so a caller cannot
## mutate the board through the result.
func zone_ids(col: int, owner: int) -> Array[int]:
	return state.zone_cards(col, owner)


## Every card on `owner`'s side of the board, column 0 to 2 and slot by slot.
## The spell zone is NOT part of the board. With `resolved_only` the face-down
## cards of the current round are left out.
func board_ids(owner: int, resolved_only: bool = false) -> Array[int]:
	var result: Array[int] = []
	for col in MatchState.COLUMNS:
		for id in state.zone_cards(col, owner):
			var card := state.card(id)
			if card == null:
				continue
			if resolved_only and not card.is_resolved:
				continue
			result.append(id)
	return result


## Picks one of `ids` with the match rng, or -1 when the list is empty. This is
## the old AbilityResolver.pick_random_target without its resolved filter: the
## caller narrows the list first, exactly like the old abilities did.
func pick_random(ids: Array) -> int:
	if ids.is_empty():
		return -1
	return int(ids[state.rng.randi() % ids.size()])


## Every card `player` beholds: their hand plus everything of theirs on the board,
## face-down cards and the spell zone included (CardManager.get_beheld_cards).
## The hand comes first, then the board in zone order.
func beheld(player: int) -> Array[int]:
	var result: Array[int] = []
	if not _is_player(player):
		return result
	result.append_array(state.players[player].hand)
	result.append_array(_all_zone_ids(player))
	return result


## The card id `player` should actually see for `card_id`: the level this player's
## champion permanently levelled up to, or `card_id` itself
## (CardManager.get_upgraded_card_id).
func upgraded_id(card_id: String, owner: int) -> String:
	if not _is_player(owner):
		return card_id
	var data: Dictionary = CardDatabase.CARDS.get(card_id, {})
	if data.is_empty():
		return card_id
	var champ_name: String = str(data.get("Name", ""))
	return str(state.players[owner].permanently_leveled_up.get(champ_name, card_id))


## Every instance id of `owner` that sits in any zone — the three lanes and the
## spell zone — column by column and slot by slot.
func _all_zone_ids(owner: int) -> Array[int]:
	var result: Array[int] = []
	for col in [0, 1, 2, MatchState.SPELL_COL]:
		result.append_array(state.zone_cards(col, owner))
	return result


# --- Zone moves, kills, discards, recalls ---

## Moves a card straight from its owner's hand onto the board at `col`, appended
## at the end of the zone (Sion's {Game End} summon). Unlike summon() this card
## already existed, so only the summoned tracker is written — and it is recorded
## like any other summon, because Sion's level-up counts summoned allies.
## Returns false when the card is not in a hand or the zone is full.
func put_into_play(id: int, col: int) -> bool:
	var card := state.card(id)
	if card == null or not _is_player(card.owner):
		return false
	var owner: int = card.owner
	if card.location != CardState.Location.HAND or not state.players[owner].hand.has(id):
		return false
	if not state.zone_has_space(col, owner):
		return false
	state.remove_from_hand(owner, id)
	if not state.place_card(id, col, owner):
		return false
	card.is_resolved = true
	if not state.play_order.has(id):
		state.play_order.append(id)
	state.summoned.append({
		"card_id": card.card_id,
		"owner_player_id": owner,
		"was_played_from_hand": false,
		"is_resolved": true,
		"instance_id": id,
	})
	emit_event(MatchEvents.card_summoned(owner, id, card.card_id, col, card.slot,
		card.get_current_power(), card.get_current_cost(), card.keywords()))
	return true


## Kills an on-board card — the whole old kill flow in one primitive: the death
## prevention check, the kill tracker, clearing the Stun, releasing the slot,
## marking the card GONE, the kill event and finally Last Breath.
## Returns false — changing nothing but the prevention events — when the card is
## not on the board, or when an ability saves it (abilities.prevents_death /
## on_death_prevented).
func kill(id: int, killer_player: int, killer_id: int = -1) -> bool:
	var card := state.card(id)
	if card == null or not is_on_board(id):
		return false
	if abilities != null and abilities.prevents_death(id):
		emit_event(MatchEvents.death_prevented(id))
		abilities.on_death_prevented(id)
		return false
	var killer := _creator_of(killer_id)
	state.killed.append({
		"card_id": card.card_id,
		"owner_player_id": card.owner,
		"killer_player_id": killer_player,
		"killer_card_id": killer.card_id if killer != null else "",
		"zone_key": [card.col, card.owner],
		"is_revived": false,
		"instance_id": id,
	})
	clear_stun(id)
	state.remove_from_zone(id)
	card.location = CardState.Location.GONE
	emit_event(MatchEvents.card_killed(id, killer_player, killer_id))
	if abilities != null:
		abilities.on_last_breath(id)
	return true


## Discards a card from its owner's hand (CardManager.discard_card_from_hand).
## A card that is not in a hand is left alone. `by_id` is the card responsible; it
## lands in the tracker as its card_id, or "" when unknown.
func discard(id: int, by_id: int = -1) -> void:
	var card := state.card(id)
	if card == null or not _is_player(card.owner):
		return
	var owner: int = card.owner
	if not state.players[owner].hand.has(id):
		return
	state.remove_from_hand(owner, id)
	card.location = CardState.Location.GONE
	var by := _creator_of(by_id)
	state.discarded.append({
		"card_id": card.card_id,
		"owner_player_id": owner,
		"discarded_by_card_id": by.card_id if by != null else "",
		"discarded_at_turn": state.turn,
		"instance_id": id,
	})
	emit_event(MatchEvents.card_discarded(owner, id, card.card_id))
	if abilities != null:
		abilities.on_discard(id)


## Returns an on-board card to its owner's hand at the front
## (CardManager.recall_card). Stun is cleared, the card goes back unresolved and
## leaves played_this_turn, so it cannot resolve again this round. `recaller_id`
## is the instance of the card that caused the recall; with it, the recall is
## tracked (Ahri counts them). A card that is not on the board is left alone.
func recall(id: int, recaller_player: int = -1, recaller_id: int = -1) -> void:
	var card := state.card(id)
	if card == null or not is_on_board(id) or not _is_player(card.owner):
		return
	var owner: int = card.owner
	clear_stun(id)
	state.remove_from_zone(id)
	state.add_to_hand(owner, id)
	card.is_resolved = false
	state.played_this_turn.erase(id)
	if recaller_id >= 0:
		var recaller := state.card(recaller_id)
		state.recalled.append({
			"card_id": card.card_id,
			"owner_player_id": owner,
			"recaller_player_id": recaller_player,
			"recaller_card_id": recaller.card_id if recaller != null else "",
			"recaller_instance_id": recaller_id,
			"instance_id": id,
		})
	emit_event(MatchEvents.card_recalled(owner, id))


# --- Stun and level-up ---

## Stuns an on-board card (StunManager.apply_stun). Stun does not stack: a card
## that is already stunned, is not on the board, or does not exist changes
## nothing. The entry records the turn so MatchRules can expire the stun at the
## next resolve; the Stun keyword goes on for the UI.
func stun(id: int) -> void:
	if not is_on_board(id) or is_stunned(id):
		return
	state.stuns.append({"instance_id": id, "stunned_on_turn": state.turn})
	add_keyword(id, "Stun")


## Removes the Stun entry and the Stun keyword (StunManager.clear_stun). A kill
## and a recall both clear it; calling it on a card that is not stunned is safe
## and emits nothing.
func clear_stun(id: int) -> void:
	for i in range(state.stuns.size() - 1, -1, -1):
		if int(state.stuns[i].get("instance_id", -1)) == id:
			state.stuns.remove_at(i)
			break
	remove_keyword(id, "Stun")


## Levels a card up in place (Card._perform_level_up + CardManager.upgrade_all_copies).
## The card itself changes id and emits a loud card_leveled_up. For a CHAMPION it
## also records the new level for its owner and upgrades every other copy that
## owner controls — board, hand and deck — each with its own silent
## card_leveled_up. The opponent's copies are untouched: they level up in their
## own right. Then on_level_up fires once, for the primary card only.
## An unknown new id, or the id the card already has, is a no-op.
func level_up(id: int, new_card_id: String) -> void:
	var card := state.card(id)
	if card == null or new_card_id.is_empty() or new_card_id == card.card_id:
		return
	if not _is_known_card(new_card_id):
		return
	var old_id: String = card.card_id
	card.card_id = new_card_id
	_emit_private(MatchEvents.card_leveled_up(id, old_id, new_card_id), id)
	if card_type(id) == "Champion" and _is_player(card.owner):
		_upgrade_owner_copies(card.owner, old_id, new_card_id, id)
	if abilities != null:
		abilities.on_level_up(id)


## Records the champion's new level for `owner` and upgrades every other card
## they control — board, hand, deck — that still has `old_id`, skipping the
## primary instance `except_id`. Copies in a hand or a deck become private
## events, copies on the board stay public.
func _upgrade_owner_copies(owner: int, old_id: String, new_id: String, except_id: int) -> void:
	var champ_name: String = str(CardDatabase.CARDS.get(new_id, {}).get("Name", ""))
	state.players[owner].permanently_leveled_up[champ_name] = new_id
	for id in _cards_of(owner):
		if id == except_id:
			continue
		var copy := state.card(id)
		if copy == null or copy.card_id != old_id:
			continue
		copy.card_id = new_id
		_emit_private(MatchEvents.card_leveled_up(id, old_id, new_id, true), id)


## Every instance id `owner` currently controls: board (lanes + spell zone),
## then hand, then deck, each in its own order.
func _cards_of(owner: int) -> Array[int]:
	var result: Array[int] = []
	result.append_array(_all_zone_ids(owner))
	result.append_array(state.players[owner].hand)
	result.append_array(state.players[owner].deck)
	return result



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
