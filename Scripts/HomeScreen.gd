extends Node


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")


func _on_deck_builder_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/DeckBuilder.tscn")


func _on_card_catalog_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/CardCatalog.tscn")
