extends Node

const SAVE_PATH := "user://decks.json"
const MAX_DECK_SIZE := 12

var saved_decks: Dictionary = {}  # { deck_name: [card_id, ...] }
var active_deck_name: String = ""


func _ready() -> void:
	_load_from_disk()


func save_deck(deck_name: String, cards: Array) -> void:
	saved_decks[deck_name] = cards.duplicate()
	active_deck_name = deck_name
	_save_to_disk()


func delete_deck(deck_name: String) -> void:
	saved_decks.erase(deck_name)
	if active_deck_name == deck_name:
		active_deck_name = ""
	_save_to_disk()


func get_deck(deck_name: String) -> Array:
	return saved_decks.get(deck_name, []).duplicate()


func get_deck_names() -> Array:
	return saved_decks.keys()


func get_active_deck() -> Array:
	return get_deck(active_deck_name)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		saved_decks = parsed


func _save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error("DeckManager: could not open %s for writing" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(saved_decks, "\t"))
	file.close()
