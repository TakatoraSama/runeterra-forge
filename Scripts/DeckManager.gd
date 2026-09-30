extends Node

const SAVE_PATH := "user://decks.json"
const ACTIVE_PATH := "user://active_deck.json"
const MAX_DECK_SIZE := 12

var saved_decks: Dictionary = {}  # { deck_name: [card_id, ...] }
var active_deck_name: String = ""


func _ready() -> void:
	_load_from_disk()
	_load_active_from_disk()


func save_deck(deck_name: String, cards: Array) -> void:
	saved_decks[deck_name] = cards.duplicate()
	active_deck_name = deck_name
	_save_to_disk()
	_save_active_to_disk()


## Make a saved deck the one played in matches. An empty name clears it.
## Returns false if the deck does not exist (nothing is changed in that case).
func set_active_deck(deck_name: String) -> bool:
	if deck_name == "":
		if active_deck_name == "":
			return true
		active_deck_name = ""
		_save_active_to_disk()
		return true
	if not saved_decks.has(deck_name):
		return false
	if active_deck_name == deck_name:
		return true
	active_deck_name = deck_name
	_save_active_to_disk()
	return true


func delete_deck(deck_name: String) -> void:
	saved_decks.erase(deck_name)
	if active_deck_name == deck_name:
		active_deck_name = ""
	_save_to_disk()
	_save_active_to_disk()


func get_deck(deck_name: String) -> Array:
	return saved_decks.get(deck_name, []).duplicate()


func get_deck_names() -> Array:
	return saved_decks.keys()


func get_active_deck() -> Array:
	return get_deck(active_deck_name)



func get_active_deck_name() -> String:
	return active_deck_name


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	# decks.json stays a flat {deck_name: [card_id, ...]} map — every key is a deck.
	# Ignore anything that is not a deck so one bad entry cannot break the rest.
	for deck_name in parsed:
		if parsed[deck_name] is Array:
			saved_decks[str(deck_name)] = parsed[deck_name]


func _save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("DeckManager: could not open %s for writing" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(saved_decks, "\t"))
	file.close()


func _load_active_from_disk() -> void:
	"""The active deck name lives in its own file so decks.json can stay a flat
	{deck_name: [card_id, ...]} map that get_deck_names() can treat uniformly."""
	if not FileAccess.file_exists(ACTIVE_PATH):
		return
	var file := FileAccess.open(ACTIVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	var deck_name := str(parsed.get("active_deck", ""))
	if deck_name != "" and not saved_decks.has(deck_name):
		# Saved deck was deleted outside the Deck Builder (or file edited by hand).
		print("DeckManager: active deck '%s' no longer exists, clearing it" % deck_name)
		return
	active_deck_name = deck_name


func _save_active_to_disk() -> void:
	var file := FileAccess.open(ACTIVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("DeckManager: could not open %s for writing" % ACTIVE_PATH)
		return
	file.store_string(JSON.stringify({"active_deck": active_deck_name}, "\t"))
	file.close()
