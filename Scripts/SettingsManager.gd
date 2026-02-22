extends CanvasLayer

@onready var settings_button: Button = $SettingsButton
@onready var settings_panel: Panel = $SettingsPanel
@onready var res_1920_button: Button = $SettingsPanel/VBoxContainer/Res1920Button
@onready var res_1600_button: Button = $SettingsPanel/VBoxContainer/Res1600Button
@onready var fullscreen_button: Button = $SettingsPanel/VBoxContainer/FullscreenButton
@onready var windowed_button: Button = $SettingsPanel/VBoxContainer/WindowedButton
@onready var close_button: Button = $SettingsPanel/VBoxContainer/CloseButton


func _ready() -> void:
	settings_button.pressed.connect(_on_settings_button_pressed)
	res_1920_button.pressed.connect(_on_res_1920_pressed)
	res_1600_button.pressed.connect(_on_res_1600_pressed)
	fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	windowed_button.pressed.connect(_on_windowed_pressed)
	close_button.pressed.connect(_on_close_pressed)


func _on_settings_button_pressed() -> void:
	settings_panel.visible = not settings_panel.visible


func _on_res_1920_pressed() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	settings_panel.visible = false


func _on_res_1600_pressed() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	settings_panel.visible = false


func _on_fullscreen_pressed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	settings_panel.visible = false


func _on_windowed_pressed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	settings_panel.visible = false


func _on_close_pressed() -> void:
	settings_panel.visible = false
