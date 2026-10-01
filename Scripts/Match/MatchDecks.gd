## The two deck lists a match can start with, and the one rule that validates a
## deck that arrives from outside (the saved deck, or the guest's join handshake).
##
## DEFAULT_DECK_IDS and BOT_DECK_IDS are static data copied from the old scripts:
##   DEFAULT_DECK_IDS = the card ids of Deck.DEFAULT_DECK, in deck order.
##   BOT_DECK_IDS     = BotManager.BOT_DECK, the offline AI's list.
## They live here so Scripts/Match never has to reach an autoload or load() the old
## scripts: MatchController used to read both through load() + get_script_constant_map()
## exactly because the engine must not depend on Deck.gd / BotManager.gd, which are
## autoloads. Tests/test_match_decks.gd pins them against those two tables, so the
## copies cannot drift silently.
##
## This class is static only: it holds no state and touches no node. Like every other
## file in Scripts/Match it is a RefCounted and obeys the engine rules — no Node, no
## get_node, no await, no autoload access, no global randi()/randf(). Card data comes
## from CardDatabase.CARDS, which is a plain class (class_name), not an autoload.
class_name MatchDecks extends RefCounted

## Cards per deck. A match is built from exactly two decks of this size, so a saved
## deck of any other length is refused rather than padded (a short deck would start
## the match immediately in Deep).
const DECK_SIZE := 12

## Deck.DEFAULT_DECK's card ids, in deck order.
const DEFAULT_DECK_IDS: Array[String] = [
	"Azir1", "Renekton1", "Nasus1",
	"Xerath1", "Tryndamere1", "Ahri1",
	"Kennen1", "NavoriConspirator", "Janna1",
	"Draven1", "Rumble1", "Sion1",
]

## BotManager.BOT_DECK's card ids: the offline AI's deck. Ten cards, not twelve —
## the extra copies of the 1-costs are what make turn-1 playability work.
const BOT_DECK_IDS: Array[String] = [
	"Azir1", "Renekton1", "Nasus1",
	"Xerath1", "Tryndamere1", "Trundle1",
	"Ahri1", "Kennen1", "NavoriConspirator", "SolitaryMonk",
]

## How many raw entries sanitize() will even look at. A guest's hello payload is
## untrusted input; a huge array is refused outright instead of walked entry by entry.
const MAX_RAW_ENTRIES := 64


## Returns `raw` as a usable deck of exactly DECK_SIZE known card ids, or
## DEFAULT_DECK_IDS when it is not one.
##
## The rule, in order:
##   1. `raw` must be an Array of at most MAX_RAW_ENTRIES entries; anything else
##      (a Dictionary from a malformed payload, null, a 10 000-entry array) is the
##      default deck.
##   2. Every entry must be a String naming a card CardDatabase knows. Anything else
##      — a non-String, an unknown id — is dropped.
##   3. The survivors are the deck only if there are exactly DECK_SIZE of them. A
##      partial deck is skipped, never padded: it would start the match short and
##      immediately Deep.
## Order is preserved, duplicates are kept (a deck may legitimately hold two copies),
## and the returned array is always a fresh Array[String] the caller may keep: the
## constants above are never handed out or mutated.
static func sanitize(raw: Variant) -> Array[String]:
	if not (raw is Array):
		return DEFAULT_DECK_IDS.duplicate()
	var entries: Array = raw
	if entries.size() > MAX_RAW_ENTRIES:
		return DEFAULT_DECK_IDS.duplicate()
	var ids: Array[String] = []
	for entry: Variant in entries:
		if not (entry is String):
			continue
		var card_id: String = entry as String
		if not CardDatabase.CARDS.has(card_id):
			continue
		ids.append(card_id)
	if ids.size() != DECK_SIZE:
		return DEFAULT_DECK_IDS.duplicate()
	return ids