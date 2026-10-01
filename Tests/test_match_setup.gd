extends "res://Tests/test_case.gd"

## MatchSetup.new_match() — deck creation, owners, shuffling and determinism.
##
## The decks are the real ones used by the game: Deck.DEFAULT_DECK (12 ids) and
## BotManager.BOT_DECK (10 ids, padded to 12). Both live in autoloads without a
## class_name, so the ids are duplicated here on purpose — the engine and these
## tests must not touch autoloads.

const DECK_0: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Ahri1",
	"Kennen1", "NavoriConspirator", "Janna1", "Draven1", "Rumble1", "Sion1",
]

const DECK_1: Array[String] = [
	"Azir1", "Renekton1", "Nasus1", "Xerath1", "Tryndamere1", "Trundle1",
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk", "Azir1", "Kennen1",
]

const UNKNOWN := "ThisCardDoesNotExist1"
const SEED_A := 1234567
const SEED_B := 7654321
const SEED_C := 42
const SEED_D := 20260901


func test_new_match_creates_two_decks_of_twelve() -> void:
	var state := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	assert_eq(state.players.size(), 2, "two players")
	assert_eq(state.players[0].deck.size(), 12, "deck 0 size")
	assert_eq(state.players[1].deck.size(), 12, "deck 1 size")
	assert_eq(state.cards.size(), 24, "one CardState per card")
	assert_eq(state.players[0].hand.is_empty(), true, "no starting hand")
	assert_true(_board_is_empty(state), "empty board")
	assert_eq(state.turn, 0, "turn 0")
	assert_eq(state.game_phase, MatchState.GamePhase.GAME_START, "GAME_START")


func test_every_deck_card_is_a_deck_card_of_its_owner() -> void:
	var state := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	for owner in 2:
		for instance_id in state.players[owner].deck:
			var card: CardState = state.card(instance_id)
			assert_true(card != null, "card %d exists" % instance_id)
			assert_eq(card.owner, owner, "owner of %d" % instance_id)
			assert_eq(card.location, CardState.Location.DECK, "location of %d" % instance_id)
	assert_eq(state.players[0].deck.size(), 12, "deck 0 still holds 12")
	assert_true(_board_is_empty(state), "no card on the board")


## No card sits in any lane or spell zone of either player. (Whether the zones
## dictionary pre-creates its entries is not fixed by the contract.)
func _board_is_empty(state: MatchState) -> bool:
	for owner in 2:
		for col in 3:
			if not state.zone_cards(col, owner).is_empty():
				return false
		if not state.zone_cards(MatchState.SPELL_COL, owner).is_empty():
			return false
	return true


func test_instance_ids_are_unique() -> void:
	var state := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	var seen := {}
	for instance_id in state.players[0].deck + state.players[1].deck:
		assert_false(seen.has(instance_id), "id %d appears once" % instance_id)
		seen[instance_id] = true
	assert_eq(seen.size(), 24, "24 distinct ids")
	assert_eq(state.next_instance_id, 25, "next id after 24 cards")


func test_same_seed_gives_the_same_match() -> void:
	var first := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	var second := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	assert_eq(first.players[0].deck, second.players[0].deck, "deck 0 order")
	assert_eq(first.players[1].deck, second.players[1].deck, "deck 1 order")
	assert_eq(first.checksum(), second.checksum(), "checksum")


func test_same_seed_survives_a_json_round_trip() -> void:
	var state := MatchSetup.new_match(DECK_0, DECK_1, SEED_C)
	var expected := state.players[0].deck.duplicate()
	var restored := MatchState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.players[0].deck, expected, "deck order after the round trip")
	assert_eq(restored.checksum(), state.checksum(), "checksum after the round trip")


func test_different_seeds_give_different_deck_orders() -> void:
	var a := MatchSetup.new_match(DECK_0, DECK_1, SEED_C)
	var b := MatchSetup.new_match(DECK_0, DECK_1, SEED_D)
	assert_ne(a.players[0].deck, b.players[0].deck, "seed %d vs %d, player 0" % [SEED_C, SEED_D])
	assert_ne(a.checksum(), b.checksum(), "seed %d vs %d, checksum" % [SEED_C, SEED_D])

	var c := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	var d := MatchSetup.new_match(DECK_0, DECK_1, SEED_B)
	assert_ne(c.players[1].deck, d.players[1].deck, "seed %d vs %d, player 1" % [SEED_A, SEED_B])
	assert_ne(c.checksum(), d.checksum(), "seed %d vs %d, checksum" % [SEED_A, SEED_B])


func test_unknown_card_ids_are_skipped() -> void:
	var deck: Array[String] = DECK_0.duplicate()
	deck[3] = UNKNOWN
	var state := MatchSetup.new_match(deck, DECK_1, SEED_A)
	assert_eq(state.players[0].deck.size(), 11, "the unknown card is not added")
	assert_eq(state.cards.size(), 23, "no CardState for the unknown id")
	for instance_id in state.players[0].deck:
		assert_ne(state.card(instance_id).card_id, UNKNOWN, "no unknown id in the deck")


func test_decks_keep_their_cards() -> void:
	var state := MatchSetup.new_match(DECK_0, DECK_1, SEED_A)
	var counts := {}
	for instance_id in state.players[0].deck:
		var card_id: String = state.card(instance_id).card_id
		counts[card_id] = int(counts.get(card_id, 0)) + 1
	for card_id in DECK_0:
		assert_eq(int(counts.get(card_id, 0)), 1, "%s survived the shuffle" % card_id)