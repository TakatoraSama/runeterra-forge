## One JSON-safe picture of a match, filtered through one viewer's eyes.
##
## The engine's state is absolute (player 0 = host, 1 = guest, ids and col/slot straight
## out of MatchState); a snapshot is what ONE viewer is allowed to know. A presenter
## rebuilds its whole view model from a snapshot and can diff the two, so everything the
## presenter is not supposed to see must be missing here, not merely unused:
##   - the opponent's hand is a count, never card ids;
##   - an opponent card still face-down has a null card_id, power, cost AND keywords;
##   - an unrevealed lane has an empty lane_id;
##   - only the viewer's own pending swaps are listed;
##   - the opponent's pool is frozen at its turn-start value while PLAY lasts, because
##     a spend is a private event that only catches up at RESOLVE;
##   - undo_count is real for the viewer and 0 for the opponent, whose plays are hidden.
##
## Ordering is fixed (lanes by column, players by id, the board by owner, col, slot,
## hands in hand order, swaps in queue order) so two snapshots of one state are equal
## and the presenter can compare them verbatim.
##
## No Node, no scene tree, no autoloads, no mutation of `state`: this class is static
## only, exactly like MatchEvents.
class_name MatchSnapshot


## Returns everything `viewer` may see of `state`, as a plain Dictionary of ints,
## Strings, bools, Arrays and Dictionaries — JSON.stringify() can write all of it.
static func for_viewer(state: MatchState, viewer: int) -> Dictionary:
	return {
		"turn": state.turn,
		"game_phase": state.game_phase,
		"round_phase": state.round_phase,
		"flip_first": state.flip_first,
		"local": viewer,
		"noxkraya_col": state.noxkraya_col,
		"lanes": _lanes(state),
		"players": [_player(state, 0, viewer), _player(state, 1, viewer)],
		"board": _board(state, viewer),
		"pending_swaps_own": _pending_swaps_own(state, viewer),
	}


# ----------------------------
# Sections
# ----------------------------

## The three columns with their lane ids, an unrevealed one named "".
static func _lanes(state: MatchState) -> Array:
	var lanes: Array = []
	for col in MatchState.COLUMNS:
		var revealed: bool = col < state.lane_revealed.size() and bool(state.lane_revealed[col])
		var lane_id: String = ""
		if revealed and col < state.lane_ids.size():
			lane_id = str(state.lane_ids[col])
		lanes.append({"col": col, "lane_id": lane_id, "revealed": revealed})
	return lanes


## One player's public numbers. Only the viewer's own hand is spelled out; the
## opponent's collapses to how many cards are in it.
static func _player(state: MatchState, player: int, viewer: int) -> Dictionary:
	var ps: PlayerState = state.players[player]
	var hand: Variant = ps.hand.size()
	var undo_count: int = 0
	if player == viewer:
		hand = _hand(state, player)
		undo_count = ps.undo_stack.size()
	# During PLAY the opponent's real pool is hidden (the spends are private events),
	# so it reads as it stood when the turn opened. Every other phase publishes the
	# real number, because the resolve re-published it.
	var current_mana: int = ps.current_mana
	if player != viewer and state.round_phase == MatchState.RoundPhase.PLAY:
		current_mana = ps.turn_start_mana
	return {
		"player": player,
		"current_mana": current_mana,
		"max_mana": ps.get_max_mana(),
		"deck_count": ps.deck.size(),
		"is_deep": ps.is_deep,
		"ended_turn": ps.ended_turn,
		"undo_count": undo_count,
		"hand": hand,
	}


## The viewer's own hand, in hand order (index 0 is the newest card).
static func _hand(state: MatchState, player: int) -> Array:
	var hand: Array = []
	for raw in state.players[player].hand:
		var card := state.card(int(raw))
		if card == null:
			continue
		hand.append({
			"instance_id": card.instance_id,
			"card_id": card.card_id,
			"cost": card.get_current_cost(),
		})
	return hand


## Every card that is in a lane column or in a spell zone, sorted by owner, then
## column, then slot. An opponent card that has not resolved yet keeps its slot but
## loses its identity AND everything derived from it: a face-down card has no cost and
## no keywords to read off, either.
static func _board(state: MatchState, viewer: int) -> Array:
	var rows: Array = []
	for player in 2:
		for col in range(-1, MatchState.COLUMNS):
			for raw in state.zone_cards(col, player):
				var card := state.card(int(raw))
				if card != null:
					rows.append(card)
	rows.sort_custom(_board_before)

	var board: Array = []
	for card: CardState in rows:
		# An opponent card is only public once it has resolved.
		var visible: bool = card.owner == viewer or card.is_resolved
		var power: Variant = null
		var cost: Variant = null
		var keywords: Variant = null
		if visible:
			power = card.get_current_power()
			cost = card.get_current_cost()
			keywords = card.keywords()
		board.append({
			"instance_id": card.instance_id,
			"owner": card.owner,
			"col": card.col,
			"slot": card.slot,
			"resolved": card.is_resolved,
			"card_id": card.card_id if visible else null,
			"power": power,
			"cost": cost,
			"keywords": keywords,
		})
	return board


## Sorts board rows by (owner, col, slot); slot is unique inside a zone, so the order
## is total and the result never depends on the sort being stable.
static func _board_before(a: CardState, b: CardState) -> bool:
	if a.owner != b.owner:
		return a.owner < b.owner
	if a.col != b.col:
		return a.col < b.col
	return a.slot < b.slot


## The viewer's own queued lane swaps, in the order the rules queued them.
static func _pending_swaps_own(state: MatchState, viewer: int) -> Array:
	var swaps: Array = []
	for entry: Dictionary in state.pending_swaps:
		if int(entry.get("player", -1)) != viewer:
			continue
		swaps.append({
			"instance_id": int(entry.get("instance_id", -1)),
			"to_col": int(entry.get("to_col", -1)),
		})
	return swaps