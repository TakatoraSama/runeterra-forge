## The offline AI opponent as a pure function: no Node, no scene tree, no autoloads.
##
## Mirrors `BotManager._decide_bot_play`: one random affordable card from hand,
## a random column that still has room, and then the turn is over. All randomness
## comes from the RNG passed in by the caller (the old bot used the global randi()),
## so the same RNG seed always produces the same decision.
##
## decide() reads the engine and decide_from_snapshot() reads what a viewer is allowed
## to see; both end in the SAME _decide(), so the two can never disagree about which
## card the RNG picked or which column it went to. That is what lets a guest autoplay
## from its own snapshot: it has no MatchState, and it must not need one.
class_name MatchBot

## Returned by _choose_col() when the card has nowhere legal to go this turn.
const INVALID_COL := -99


## Returns the intents the bot submits for its turn as `player`: at most one
## play_card followed by end_turn. Returns an empty Array when it is not that
## player's move (wrong phase, invalid player id, or the turn already ended).
static func decide(state: MatchState, player: int, rng: RandomNumberGenerator) -> Array:
	if state == null or player < 0 or player >= state.players.size():
		return []
	if state.game_phase != MatchState.GamePhase.TURN_LOOP:
		return []
	if state.round_phase != MatchState.RoundPhase.PLAY:
		return []
	var ps: PlayerState = state.players[player]
	var hand: Array = []
	for id in ps.hand:
		var c := state.card(id)
		if c == null:
			continue
		hand.append({
			"instance_id": c.instance_id,
			"card_id": c.card_id,
			"cost": c.get_current_cost(),
		})
	return _decide(hand, ps.current_mana, ps.ended_turn, _zone_sizes(state, player),
		state.noxkraya_col, rng)


## The same decision, answered from the viewer's OWN snapshot (MatchSnapshot
## .for_viewer(state, viewer)) instead of the engine: the guest autoplay path.
## Everything it needs is in there — its hand with the cards' current costs, its pool,
## its ended_turn flag, the round phase, noxkraya_col and the board, whose rows say how
## full each of its own four zones is.
static func decide_from_snapshot(snapshot: Dictionary, rng: RandomNumberGenerator) -> Array:
	if snapshot == null or snapshot.is_empty():
		return []
	if int(snapshot.get("game_phase", -1)) != MatchState.GamePhase.TURN_LOOP:
		return []
	if int(snapshot.get("round_phase", -1)) != MatchState.RoundPhase.PLAY:
		return []
	var viewer: int = int(snapshot.get("local", -1))
	var players: Variant = snapshot.get("players", [])
	if not (players is Array):
		return []
	var roster: Array = players
	if viewer < 0 or viewer >= roster.size() or not (roster[viewer] is Dictionary):
		return []
	var mine: Dictionary = roster[viewer]
	var hand: Variant = mine.get("hand", null)
	if not (hand is Array):
		return []
	return _decide(hand, int(mine.get("current_mana", 0)), bool(mine.get("ended_turn", false)),
		_zone_sizes_from_snapshot(snapshot, viewer), int(snapshot.get("noxkraya_col", -1)), rng)


## The decision itself, in plain numbers, shared by both entry points so they cannot
## drift apart: `hand` rows are {instance_id, card_id, cost} in hand order, `sizes` is
## _zone_sizes(). A refusal to play (nothing affordable, or nowhere legal to go) still
## ends the turn, exactly like the old bot.
static func _decide(hand: Array, mana: int, ended_turn: bool, sizes: Array, noxkraya_col: int, rng: RandomNumberGenerator) -> Array:
	var intents: Array = []
	if ended_turn:
		return intents
	var affordable: Array = []
	for row: Variant in hand:
		var entry: Dictionary = row
		if int(entry.get("cost", 0)) <= mana:
			affordable.append(entry)
	if not affordable.is_empty():
		var chosen: Dictionary = affordable[rng.randi_range(0, affordable.size() - 1)]
		var col := _choose_col(str(chosen.get("card_id", "")), sizes, noxkraya_col, rng)
		if col != INVALID_COL:
			intents.append(MatchIntents.play_card(int(chosen.get("instance_id", -1)), col))
	intents.append(MatchIntents.end_turn())
	return intents


## Picks the column the bot plays into: the spell zone for a Spell, otherwise a
## random lane column that still has a free slot and is not restricted by Noxkraya.
## Returns INVALID_COL when there is no legal column, so the play is skipped.
static func _choose_col(card_id: String, sizes: Array, noxkraya_col: int, rng: RandomNumberGenerator) -> int:
	if str(CardDatabase.CARDS.get(card_id, {}).get("Type", "")) == "Spell":
		if _size_at(sizes, MatchState.SPELL_COL) < MatchState.SPELL_SLOTS:
			return MatchState.SPELL_COL
		return INVALID_COL
	var open: Array[int] = []
	for col in MatchState.COLUMNS:
		if _size_at(sizes, col) >= MatchState.SLOTS_PER_ZONE:
			continue
		if noxkraya_col >= 0 and col != noxkraya_col:
			continue
		open.append(col)
	if open.is_empty():
		return INVALID_COL
	return open[rng.randi_range(0, open.size() - 1)]


## How many cards sit in each of `player`'s four zones (spell zone first).
static func _zone_sizes(state: MatchState, player: int) -> Array:
	var sizes: Array = []
	for col in [MatchState.SPELL_COL, 0, 1, 2]:
		sizes.append(state.zone_cards(col, player).size())
	return sizes


## The same four numbers counted off the board rows the viewer may see. Every card in
## a zone is listed there, face-down ones included, which is what a zone occupancy is.
static func _zone_sizes_from_snapshot(snapshot: Dictionary, viewer: int) -> Array:
	var sizes: Array = [0, 0, 0, 0]
	for row: Variant in snapshot.get("board", []):
		var entry: Dictionary = row
		if int(entry.get("owner", -1)) != viewer:
			continue
		var index: int = int(entry.get("col", -99)) + 1
		if index < 0 or index >= sizes.size():
			continue
		sizes[index] = int(sizes[index]) + 1
	return sizes


## The occupancy of one column, or 0 for a column that is not one of the four.
static func _size_at(sizes: Array, col: int) -> int:
	var index: int = col + 1
	if index < 0 or index >= sizes.size():
		return 0
	return int(sizes[index])