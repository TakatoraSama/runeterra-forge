## Builds the starting MatchState for a match.
##
## The only randomness of the match itself is the deck shuffle, and it comes from the
## MatchState's own RandomNumberGenerator, seeded from `rng_seed`. Fisher-Yates is run
## on player 0's deck first, then player 1's, always from the same generator, so the
## resulting order depends on nothing but the two deck lists and the seed: the same
## decks and the same seed always produce the same checksum, in any process or on any
## peer.
##
## M5a: instance ids are handed out in deck-list order, which is enough to map a deck —
## the n-th id drawn is the n-th card of the list. `scramble_ids` permutes the order the
## cards are CREATED in, so the ids no longer line up with the list. The permutation is
## drawn from a generator of its own (see _id_rng), never from state.rng: the match RNG
## must keep consuming exactly the same numbers, or a --seed run stops replaying. With
## the flag false (offline, and every seeded expectation) nothing changes at all.
class_name MatchSetup

## The scramble generator is seeded from the match seed XOR this constant, so its
## permutation is reproducible from the seed alone while drawing nothing from state.rng.
const ID_SCRAMBLE_SALT := 0x1D5B_7A5C


static func new_match(deck0: Array, deck1: Array, rng_seed: int, scramble_ids: bool = false) -> MatchState:
	"""Create a fresh GAME_START state where player `p` owns every card in `deck<p>`.
	`deck<p>` is a list of CardDatabase card ids; unknown ids are reported and skipped.
	`scramble_ids` permutes the instance ids (see the header); it never touches state.rng."""
	var state := MatchState.new()
	state.rng.seed = rng_seed
	var decks: Array = [deck0, deck1]
	# Every card of both decks in one list first: that is what gets permuted, so ids
	# come out in an order unrelated to the deck lists while the decks still end up
	# holding exactly their own cards.
	var entries: Array = []
	for p in range(2):
		for card_id: Variant in decks[p]:
			entries.append([p, str(card_id)])
	if scramble_ids:
		_shuffle_ids(entries, _id_rng(rng_seed))
	for entry: Array in entries:
		var p: int = entry[0]
		var id: String = entry[1]
		if not CardDatabase.CARDS.has(id):
			push_error("MatchSetup.new_match: unknown card id '%s' in deck %d" % [id, p])
			continue
		var card := state.new_card(id, p, CardState.Location.DECK)
		state.players[p].deck.append(card.instance_id)
	# Both shuffles after both decks are built, which draws the very same numbers from
	# state.rng as the one-deck-at-a-time loop this replaced.
	for p in range(2):
		_shuffle(state, state.players[p].deck)
	state.game_phase = MatchState.GamePhase.GAME_START
	state.turn = 0
	return state


## The generator the instance-id permutation is drawn from. Deliberately NOT
## state.rng: the match's own stream has to stay exactly as seeded.
static func _id_rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rng_seed) ^ ID_SCRAMBLE_SALT
	return rng


## In-place Fisher-Yates over the [player, card_id] entries, drawn from `rng`.
static func _shuffle_ids(entries: Array, rng: RandomNumberGenerator) -> void:
	for i in range(entries.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Array = entries[i]
		entries[i] = entries[j]
		entries[j] = tmp


static func _shuffle(state: MatchState, cards: Array[int]) -> void:
	"""In-place Fisher-Yates over `cards`, drawn from the match RNG (never the globals)."""
	var n: int = cards.size()
	for i in range(n - 1, 0, -1):
		var j: int = state.rng.randi_range(0, i)
		var tmp: int = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp
