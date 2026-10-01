## Builds the starting MatchState for a match.
##
## The only randomness is the deck shuffle, and it comes from the MatchState's own
## RandomNumberGenerator, seeded from `rng_seed`. Fisher-Yates is run on player 0's
## deck first, then player 1's, always from the same generator, so the resulting
## order depends on nothing but the two deck lists and the seed: the same decks and
## the same seed always produce the same checksum, in any process or on any peer.
class_name MatchSetup


static func new_match(deck0: Array, deck1: Array, rng_seed: int) -> MatchState:
	"""Create a fresh GAME_START state where player `p` owns every card in `deck<p>`.
	`deck<p>` is a list of CardDatabase card ids; unknown ids are reported and skipped."""
	var state := MatchState.new()
	state.rng.seed = rng_seed
	var decks: Array = [deck0, deck1]
	for p in range(2):
		for card_id: Variant in decks[p]:
			var id: String = str(card_id)
			if not CardDatabase.CARDS.has(id):
				push_error("MatchSetup.new_match: unknown card id '%s' in deck %d" % [id, p])
				continue
			var card := state.new_card(id, p, CardState.Location.DECK)
			state.players[p].deck.append(card.instance_id)
		_shuffle(state, state.players[p].deck)
	state.game_phase = MatchState.GamePhase.GAME_START
	state.turn = 0
	return state


static func _shuffle(state: MatchState, cards: Array[int]) -> void:
	"""In-place Fisher-Yates over `cards`, drawn from the match RNG (never the globals)."""
	var n: int = cards.size()
	for i in range(n - 1, 0, -1):
		var j: int = state.rng.randi_range(0, i)
		var tmp: int = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
