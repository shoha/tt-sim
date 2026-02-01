extends CanvasLayer

## Title screen controller.
## Provides options to start a local game or host/join a networked game.

signal host_game_requested()
signal join_game_requested()

@onready var host_button: Button = %HostGameButton
@onready var join_button: Button = %JoinGameButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)


func _on_host_pressed() -> void:
	host_game_requested.emit()


func _on_join_pressed() -> void:
	join_game_requested.emit()
