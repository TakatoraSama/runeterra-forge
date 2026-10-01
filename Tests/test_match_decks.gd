extends "res://Tests/test_case.gd"

## MatchDecks — the deck constants and the sanitize() rule.
##
## The constants are copies of two tables that live in autoload scripts (Deck.DEFAULT_DECK
## and BotManager.BOT_DECK). They are read back here through get_script_constant_map(),
## the same way MatchController used to, so the copies cannot drift silently.

const UNKNOWN := "ThisCardDoesNotExist1"
## 65 entries: one more than MatchDecks.MAX_RAW_ENTRIES, so sanitize refuses it outright.
const OVERSIZED_ENTRIES := 65


# ----------------------------
# The constants match the old tables
# ----------------------------

func test_default_deck_ids_are_deck_default_deck_in_order() -> void:
	var expected: Array[String] = []
	for entry: Variant in _script_constant(load("res://Scripts/Deck.gd"), "DEFAULT_DECK", []):
		expected.append(str((entry as Dictionary)["id"]))
	assert_eq(MatchDecks.DEFAULT_DECK_IDS, expected, "Deck.DEFAULT_DECK ids, in order")


func test_bot_deck_ids_are_bot_manager_bot_deck() -> void:
	var expected: Array[String] = []
	for card_id: Variant in _script_constant(load("res://Scripts/BotManager.gd"), "BOT_DECK", []):
		expected.append(str(card_id))
	assert_eq(MatchDecks.BOT_DECK_IDS, expected, "BotManager.BOT_DECK")


func test_default_deck_has_exactly_deck_size_known_cards() -> void:
	assert_eq(MatchDecks.DEFAULT_DECK_IDS.size(), MatchDecks.DECK_SIZE, "default deck size")
	for card_id: String in MatchDecks.DEFAULT_DECK_IDS:
		assert_true(CardDatabase.CARDS.has(card_id), "%s is a known card" % card_id)


# ----------------------------
# sanitize() accepts exactly one shape of deck
# ----------------------------

func test_a_complete_deck_of_known_ids_is_kept_as_is() -> void:
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "kept unchanged")


func test_sanitize_preserves_order_and_duplicates() -> void:
	# Duplicates are legal: a deck may hold two copies of the same card.
	var deck: Array = [
		"Sion1", "Azir1", "Azir1", "Rumble1", "Draven1", "Janna1",
		"NavoriConspirator", "Kennen1", "Ahri1", "Tryndamere1", "Xerath1", "Nasus1",
	]
	assert_eq(MatchDecks.sanitize(deck), deck, "order and duplicate copies kept")


func test_a_short_deck_falls_back_to_the_default() -> void:
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	deck.pop_back()
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "11 cards is not a deck")


func test_a_long_deck_falls_back_to_the_default() -> void:
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	deck.append("Azir1")
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "13 cards is not a deck")


func test_an_empty_array_falls_back_to_the_default() -> void:
	assert_eq(MatchDecks.sanitize([]), MatchDecks.DEFAULT_DECK_IDS, "no deck sent")


func test_unknown_ids_are_dropped_and_the_result_must_still_be_full() -> void:
	# One unknown id leaves 11 known ones, which is not a deck.
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	deck[2] = UNKNOWN
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "the unknown id is dropped")
	# Two unknown ids leave 10, still not a deck.
	deck[2] = UNKNOWN
	deck[5] = UNKNOWN
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "two unknown ids dropped")


func test_an_unknown_id_is_ignored_when_twelve_known_ones_remain() -> void:
	# 12 known + 1 unknown: the unknown is dropped and the 12 that remain ARE the deck.
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	deck.append(UNKNOWN)
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "the 12 known ids survive")


func test_a_non_string_entry_is_dropped_and_twelve_known_ids_still_make_a_deck() -> void:
	# 12 real ids plus one int: an int is not a card id, and the 12 that remain are a deck.
	var deck: Array = [
		7, "Sion1", "Azir1", "Rumble1", "Draven1", "Janna1",
		"NavoriConspirator", "Kennen1", "Ahri1", "Tryndamere1", "Xerath1", "Nasus1",
	]
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "the int entry is dropped")


func test_a_non_string_entry_that_leaves_too_few_falls_back_to_the_default() -> void:
	# The same deck without the spare id: the int leaves 11 survivors, which is no deck.
	var deck: Array = [
		"Sion1", "Azir1", 7, "Rumble1", "Draven1", "Janna1",
		"NavoriConspirator", "Kennen1", "Ahri1", "Tryndamere1", "Xerath1", "Nasus1",
	]
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "11 known ids is not a deck")


func test_string_names_are_accepted_as_strings() -> void:
	# A JSON round trip turns everything into String, so a payload of Strings is normal.
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "Strings are kept")


# ----------------------------
# sanitize() refuses anything that is not a sane Array
# ----------------------------

func test_a_non_array_falls_back_to_the_default() -> void:
	for raw: Variant in [null, 42, "Azir1", {}, {"deck": "Azir1"}, true]:
		assert_eq(MatchDecks.sanitize(raw), MatchDecks.DEFAULT_DECK_IDS, "raw %s" % [str(raw)])


func test_an_oversized_array_falls_back_without_walking_it() -> void:
	var deck: Array = []
	deck.resize(OVERSIZED_ENTRIES)
	deck.fill("Azir1")
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "over MAX_RAW_ENTRIES")


func test_a_nested_array_falls_back_to_the_default() -> void:
	# A sub-Array is not a String, so every entry drops and the deck is empty.
	var deck: Array = MatchDecks.DEFAULT_DECK_IDS.duplicate()
	deck[0] = ["Azir1"]
	assert_eq(MatchDecks.sanitize(deck), MatchDecks.DEFAULT_DECK_IDS, "a nested Array is not an id")


# ----------------------------
# The returned deck is the caller's own
# ----------------------------

func test_sanitize_never_hands_out_a_constant() -> void:
	var first: Array[String] = MatchDecks.sanitize(MatchDecks.DEFAULT_DECK_IDS.duplicate())
	first[0] = "Tampered"
	assert_ne(MatchDecks.DEFAULT_DECK_IDS[0], "Tampered", "DEFAULT_DECK_IDS is untouched")

	var fallback: Array[String] = MatchDecks.sanitize(null)
	fallback[0] = "Tampered"
	assert_ne(MatchDecks.DEFAULT_DECK_IDS[0], "Tampered", "the fallback is a fresh array too")


func test_sanitize_output_starts_a_real_match() -> void:
	# The point of the rule: whatever comes out is a deck the engine can build. The bot
	# deck is passed through as the engine gets it — MatchSetup.new_match does not pad
	# it, so player 0 holds exactly the 10 ids BotManager has always supplied.
	var deck := MatchDecks.sanitize(MatchDecks.DEFAULT_DECK_IDS.duplicate())
	var state := MatchSetup.new_match(MatchDecks.BOT_DECK_IDS, deck, 4242)
	assert_eq(state.players[1].deck.size(), MatchDecks.DECK_SIZE, "player 1 got a full deck")
	assert_eq(state.players[0].deck.size(), MatchDecks.BOT_DECK_IDS.size(), "player 0 got the bot deck")


# ----------------------------
# The M5a contract files parse and expose their signatures
# ----------------------------
# MatchHost and MatchNet are stubs in Step 0, but a typo in a signature here would only
# surface in Group A/B/C at run time. Loading them and asking for their method and
# signal lists is enough to keep the contract honest.

func test_match_host_declares_the_contract_signatures() -> void:
	var script := load("res://Scripts/Match/MatchHost.gd") as GDScript
	assert_true(script != null and script.can_instantiate(), "MatchHost parses")
	assert_eq(MatchHost.PROTOCOL_VERSION, 1, "PROTOCOL_VERSION")
	var methods: Array = _method_names(script)
	for method_name in ["start", "submit", "presentation_done", "ack_timeout",
			"pending_turn", "is_over", "winner", "snapshot_for", "check_hello"]:
		assert_true(methods.has(method_name), "MatchHost.%s exists" % method_name)


func test_match_net_declares_the_five_rpcs_the_senders_and_the_signals() -> void:
	var script := load("res://Scripts/Presentation/MatchNet.gd") as GDScript
	assert_true(script != null and script.can_instantiate(), "MatchNet parses")
	var methods: Array = _method_names(script)
	for method_name in ["hello", "submit_intent", "presentation_done",
			"receive_events", "receive_snapshot"]:
		assert_true(methods.has(method_name), "MatchNet.%s exists" % method_name)
	for sender in ["send_events", "send_snapshot", "send_intent", "send_presentation_done"]:
		assert_true(methods.has(sender), "MatchNet.%s exists" % sender)
	var signals: Array = script.get_script_signal_list().map(
			func(info: Dictionary) -> Variant: return str(info.get("name", "")))
	for signal_name in ["guest_ready", "session_refused", "session_ended"]:
		assert_true(signals.has(signal_name), "MatchNet.%s exists" % signal_name)


# ----------------------------
# Helpers
# ----------------------------

## The names of every method `script` declares, including the inherited ones.
static func _method_names(script: GDScript) -> Array:
	return script.get_script_method_list().map(
			func(info: Dictionary) -> Variant: return str(info.get("name", "")))


## One constant of `source`, read the way the old MatchController read the deck tables.
static func _script_constant(source: Variant, constant_name: StringName, fallback: Variant) -> Variant:
	var script: Script = source as Script
	if script == null:
		return fallback
	return script.get_script_constant_map().get(constant_name, fallback)