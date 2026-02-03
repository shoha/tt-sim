extends CanvasLayer

## Title screen controller.
## Provides options to start a local game or host/join a networked game.

signal host_game_requested()
signal join_game_requested()

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")

@onready var host_button: Button = %HostGameButton
@onready var join_button: Button = %JoinGameButton
@onready var settings_button: Button = %SettingsButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)


func _on_host_pressed() -> void:
	host_game_requested.emit()


func _on_join_pressed() -> void:
	join_game_requested.emit()


func _on_settings_pressed() -> void:
	var settings_menu = SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)
