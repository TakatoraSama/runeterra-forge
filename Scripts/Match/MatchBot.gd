## The offline AI opponent as a pure function: no Node, no scene tree, no autoloads.
##
## Mirrors `BotManager._decide_bot_play`: one random affordable card from hand,
## a random column that still has room, and then the turn is over. All randomness
## comes from the RNG passed in by the caller (the old bot used the global randi()),
## so the same RNG seed always produces the same decision.
class_name MatchBot

## Returned by _choose_col() when the card has nowhere legal to go this turn.
const INVALID_COL := -99


## Returns the intents the bot submits for its turn as `player`: at most one
## play_card followed by end_turn. Returns an empty Array when it is not that
## player's move (wrong phase, invalid player id, or the turn already ended).
static func decide(state: MatchState, player: int, rng: RandomNumberGenerator) -> Array:
	var intents: Array = []
	if state == null or player < 0 or player >= state.players.size():
		return intents
	if state.game_phase != MatchState.GamePhase.TURN_LOOP:
		return intents
	if state.round_phase != MatchState.RoundPhase.PLAY:
		return intents
	var ps: PlayerState = state.players[player]
	if ps.ended_turn:
		return intents

	var affordable: Array[int] = []
	for id in ps.hand:
		var c := state.card(id)
		if c == null:
			continue
		if c.get_current_cost() <= ps.current_mana:
			affordable.append(id)
	if not affordable.is_empty():
		var chosen: int = affordable[rng.randi_range(0, affordable.size() - 1)]
		var col := _choose_col(state, player, state.card(chosen), rng)
		if col != INVALID_COL:
			intents.append(MatchIntents.play_card(chosen, col))
	intents.append(MatchIntents.end_turn())
	return intents


## Picks the column the bot plays into: the spell zone for a Spell, otherwise a
## random lane column that still has a free slot and is not restricted by Noxkraya.
## Returns INVALID_COL when there is no legal column, so the play is skipped.
static func _choose_col(state: MatchState, player: int, card: CardState, rng: RandomNumberGenerator) -> int:
	if card == null:
		return INVALID_COL
	if str(card.data().get("Type", "")) == "Spell":
		if state.zone_cards(MatchState.SPELL_COL, player).size() < MatchState.SPELL_SLOTS:
			return MatchState.SPELL_COL
		return INVALID_COL
	var open: Array[int] = []
	for col in MatchState.COLUMNS:
		if state.zone_cards(col, player).size() >= MatchState.SLOTS_PER_ZONE:
			continue
		if state.noxkraya_col >= 0 and col != state.noxkraya_col:
			continue
		open.append(col)
	if open.is_empty():
		return INVALID_COL
	return open[rng.randi_range(0, open.size() - 1)]