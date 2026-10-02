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

## How likely the autoplay bot is to queue a lane swap when it has a legal one
## (rng.randf() < this). Only consulted when allow_swaps is true. High on purpose: the
## flag exists so the offline / LAN self-tests actually walk the swap path (including
## the full-lane overflow), and an Elusive with a legal destination is rare enough that
## a coin flip would leave most matches without a single swap.
const SWAP_CHANCE := 0.9

## How likely the bot is to play into the lane its Elusive card just LEFT, so the
## freed room is actually exercised (including the full-lane overflow case) instead
## of being wasted on another lane. Only consulted when a swap was queued.
const REUSE_FREED_LANE_CHANCE := 0.7


## Returns the intents the bot submits for its turn as `player`: at most one
## swap_card, then at most one play_card, then end_turn. Returns an empty Array when
## it is not that player's move (wrong phase, invalid player id, or the turn already
## ended).
##
## `allow_swaps` turns on the lane-swap planner, which ONLY --autoplay uses. With
## false (the real opponent bot and every existing caller) this function touches no
## extra rng number and returns exactly what it always did, byte for byte.
static func decide(state: MatchState, player: int, rng: RandomNumberGenerator,
		allow_swaps: bool = false) -> Array:
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
		state.noxkraya_col, rng, allow_swaps,
		_own_board_from_state(state, player), _own_pending_from_state(state, player))


## The same decision, answered from the viewer's OWN snapshot (MatchSnapshot
## .for_viewer(state, viewer)) instead of the engine: the guest autoplay path.
## Everything it needs is in there — its hand with the cards' current costs, its pool,
## its ended_turn flag, the round phase, noxkraya_col, the board (whose rows carry col,
## resolved and keywords) and its own pending swaps.
static func decide_from_snapshot(snapshot: Dictionary, rng: RandomNumberGenerator,
		allow_swaps: bool = false) -> Array:
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
		_zone_sizes_from_snapshot(snapshot, viewer), int(snapshot.get("noxkraya_col", -1)),
		rng, allow_swaps,
		_own_board_from_snapshot(snapshot, viewer), _own_pending_from_snapshot(snapshot))


## The decision itself, in plain numbers, shared by both entry points so they cannot
## drift apart: `hand` rows are {instance_id, card_id, cost} in hand order, `sizes` is
## _zone_sizes(), `board`/`pending` describe the caller's own cards for the optional
## swap planner. A refusal to play (nothing affordable, or nowhere legal to go) still
## ends the turn, exactly like the old bot.
##
## With `allow_swaps` false NOTHING below the guard touches the rng beyond the draws the
## old bot made, which is what keeps the real opponent bot (and every existing test)
## bit-for-bit unchanged.
static func _decide(hand: Array, mana: int, ended_turn: bool, sizes: Array,
		noxkraya_col: int, rng: RandomNumberGenerator, allow_swaps: bool = false,
		board: Array = [], pending: Array = []) -> Array:
	var intents: Array = []
	if ended_turn:
		return intents
	var freed_col: int = -1
	# Without the flag (or without any queued swap) this IS `sizes`, the very array the
	# old bot read, so the plain decision path is untouched.
	var effective: Array = sizes
	if allow_swaps:
		# `pending` may already hold swaps queued earlier (a second decide() in the
		# same PLAY phase), so the play's sizes are always re-derived from the engine's
		# room rule rather than read off the raw occupancy.
		effective = _effective_sizes(sizes, pending, board)
		var plan: Dictionary = _plan_swap(board, pending, effective, rng)
		if not plan.is_empty():
			intents.append(MatchIntents.swap_card(
				int(plan["instance_id"]), int(plan["to_col"])))
			freed_col = int(plan["from_col"])
			var planned: Array = pending.duplicate()
			planned.append({"instance_id": int(plan["instance_id"]),
				"from_col": freed_col, "to_col": int(plan["to_col"])})
			effective = _effective_sizes(sizes, planned, board)
	var affordable: Array = []
	for row: Variant in hand:
		var entry: Dictionary = row
		if int(entry.get("cost", 0)) <= mana:
			affordable.append(entry)
	if not affordable.is_empty():
		var chosen: Dictionary = affordable[rng.randi_range(0, affordable.size() - 1)]
		var col := _choose_col(str(chosen.get("card_id", "")), effective, noxkraya_col, rng, freed_col)
		if col != INVALID_COL:
			intents.append(MatchIntents.play_card(int(chosen.get("instance_id", -1)), col))
	intents.append(MatchIntents.end_turn())
	return intents


## The lane swap to queue this turn, or {} when none is legal or the dice said no.
## Returns {instance_id, from_col, to_col}. Candidates are the caller's own board cards
## in a LANE column that the engine would accept: resolved (a card played this round
## has not resolved), Elusive, not stunned, and not already queued for a swap. A
## candidate pairs with every OTHER lane column that still has room.
##
## `sizes` is the EFFECTIVE occupancy (_effective_sizes), i.e. the engine's own room
## rule already folded in, so "< SLOTS_PER_ZONE" here is exactly the engine's test and
## the destination is legal by construction rather than by a second guess.
static func _plan_swap(board: Array, pending: Array, sizes: Array,
		rng: RandomNumberGenerator) -> Dictionary:
	var queued: Array[int] = []
	for entry: Dictionary in pending:
		queued.append(int(entry.get("instance_id", -1)))
	var candidates: Array = []
	for row: Variant in board:
		var card: Dictionary = row
		if int(card.get("col", -1)) < 0:
			continue
		if not bool(card.get("resolved", false)):
			continue
		var keywords: Array = card.get("keywords", [])
		if not keywords.has("Elusive") or keywords.has("Stun"):
			continue
		if queued.has(int(card.get("instance_id", -1))):
			continue
		var from_col: int = int(card["col"])
		for dest in MatchState.COLUMNS:
			if dest == from_col:
				continue
			if _size_at(sizes, dest) >= MatchState.SLOTS_PER_ZONE:
				continue
			candidates.append({
				"instance_id": int(card.get("instance_id", -1)),
				"from_col": from_col,
				"to_col": dest,
			})
	if candidates.is_empty():
		return {}
	if rng.randf() >= SWAP_CHANCE:
		return {}
	var chosen: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
	return chosen


## Picks the column the bot plays into: the spell zone for a Spell, otherwise a
## random lane column that still has a free slot and is not restricted by Noxkraya.
## Returns INVALID_COL when there is no legal column, so the play is skipped.
##
## `freed_col` is the lane the planned swap emptied this turn (INVALID_COL-ish -1 when
## no swap was planned). It is only a PREFERENCE: with REUSE_FREED_LANE_CHANCE the bot
## reuses the freed slot — which is how the self-tests get to exercise the full-lane
## overflow, where the freed lane is the only one with room left — and otherwise it
## picks as it always did. Nothing is drawn from the rng unless a swap really freed
## that lane, so the no-swap path keeps its old draw sequence.
static func _choose_col(card_id: String, sizes: Array, noxkraya_col: int,
		rng: RandomNumberGenerator, freed_col: int = -1) -> int:
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
	if freed_col >= 0 and open.has(freed_col) \
			and rng.randf() < REUSE_FREED_LANE_CHANCE:
		return freed_col
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



## The occupancy _choose_col should compare against SLOTS_PER_ZONE: a lane that is
## losing cards counts fewer, a lane that already has swaps coming IN counts more.
## Without this the bot would refuse to play into a lane the engine has just freed —
## exactly the overflow case the rule exists for — or queue a play on top of a slot
## that is already reserved.
static func _effective_sizes(sizes: Array, pending: Array, board: Array) -> Array:
	var effective: Array = sizes.duplicate()
	for col in MatchState.COLUMNS:
		effective[col + 1] = MatchState.SLOTS_PER_ZONE - _lane_room(sizes, pending, board, col)
	return effective


## Room left in lane column `col` under the ENGINE's rule, which is the only rule that
## decides whether the bot's swap will be accepted:
##   SLOTS_PER_ZONE - cards now in the lane + swaps queued OUT of it - slots already
##   reserved by swaps queued INTO it
## (MatchRules._room_in.) `pending` entries whose card is no longer in the lane they
## left do not free anything, which is why the count of outgoing swaps is read off the
## board rows instead of the queue.
static func _lane_room(sizes: Array, pending: Array, board: Array, col: int) -> int:
	var outgoing: int = 0
	var incoming: int = 0
	for entry: Dictionary in pending:
		var id: int = int(entry.get("instance_id", -1))
		if _board_col_of(board, id) == int(entry.get("from_col", -1)):
			outgoing += 1
		if int(entry.get("to_col", -1)) == col:
			incoming += 1
	return MatchState.SLOTS_PER_ZONE - _size_at(sizes, col) + outgoing - incoming


## The lane column the card with this instance id currently sits in, or -1 when it is
## not on the board any more (killed, recalled, gone).
static func _board_col_of(board: Array, id: int) -> int:
	for row: Variant in board:
		var entry: Dictionary = row
		if int(entry.get("instance_id", -99)) == id:
			return int(entry.get("col", -1))
	return -1


## The caller's own board cards in {_instance_id, col, resolved, keywords} form, the
## shape _plan_swap works on. Both entry points build exactly this, which is what keeps
## the engine path and the snapshot path making the same choice from the same numbers.
static func _own_board_from_state(state: MatchState, player: int) -> Array:
	var board: Array = []
	for col in MatchState.COLUMNS:
		for raw in state.zone_cards(col, player):
			var card := state.card(int(raw))
			if card == null:
				continue
			board.append({
				"instance_id": card.instance_id,
				"col": card.col,
				"resolved": card.is_resolved,
				"keywords": card.keywords(),
			})
	return board


## The same rows off the snapshot's board section. Stun shows up as a keyword, exactly
## like it does in the engine (MatchOps.stun adds it, clear_stun removes it), so the
## planner needs nothing the viewer is not allowed to see.
static func _own_board_from_snapshot(snapshot: Dictionary, viewer: int) -> Array:
	var board: Array = []
	for row: Variant in snapshot.get("board", []):
		var entry: Dictionary = row
		if int(entry.get("owner", -1)) != viewer:
			continue
		var keywords: Variant = entry.get("keywords", null)
		board.append({
			"instance_id": int(entry.get("instance_id", -1)),
			"col": int(entry.get("col", -1)),
			"resolved": bool(entry.get("resolved", false)),
			"keywords": (keywords as Array) if keywords is Array else [],
		})
	return board


## The caller's own pending swaps as {_instance_id, from_col, to_col}.
##
## The engine keeps a swapping card in its ORIGIN zone until SWAP_LANE (public truth,
## hidden information), so the card's own board row is where from_col comes from: the
## snapshot deliberately does not repeat it. A swap whose card is no longer on the
## board gets from_col -1, which makes it free nothing and reserve nothing — the same
## verdict MatchState.outgoing_swaps reaches from the card itself.
static func _own_pending_from_state(state: MatchState, player: int) -> Array:
	var pending: Array = []
	for entry: Dictionary in state.pending_swaps:
		if int(entry.get("player", -1)) != player:
			continue
		var card := state.card(int(entry.get("instance_id", -1)))
		pending.append({
			"instance_id": int(entry.get("instance_id", -1)),
			"from_col": card.col if card != null else -1,
			"to_col": int(entry.get("to_col", -1)),
		})
	return pending


## The same rows off pending_swaps_own, with from_col taken from the board rows.
static func _own_pending_from_snapshot(snapshot: Dictionary) -> Array:
	var board: Array = []
	for row: Variant in snapshot.get("board", []):
		var entry: Dictionary = row
		if int(entry.get("owner", -1)) != int(snapshot.get("local", -1)):
			continue
		board.append({"instance_id": int(entry.get("instance_id", -1)),
			"col": int(entry.get("col", -1))})
	var pending: Array = []
	for entry: Variant in snapshot.get("pending_swaps_own", []):
		var swap: Dictionary = entry
		var id: int = int(swap.get("instance_id", -1))
		pending.append({
			"instance_id": id,
			"from_col": _board_col_of(board, id),
			"to_col": int(swap.get("to_col", -1)),
		})
	return pending