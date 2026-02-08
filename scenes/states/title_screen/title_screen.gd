extends CanvasLayer

## Title screen controller.
## Provides options to start a local game or host/join a networked game.

signal host_game_requested
signal join_game_requested

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")

## Stagger delay between each UI element fading in (seconds)
const ENTRANCE_STAGGER := 0.08
const ENTRANCE_DURATION := 0.3

@onready var host_button: Button = %HostGameButton
@onready var join_button: Button = %JoinGameButton
@onready var settings_button: Button = %SettingsButton


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	_play_entrance_animation()


## Staggered fade-in for title screen UI elements
func _play_entrance_animation() -> void:
	var container = $PlaceholderContainer/CenterContainer/VBoxContainer
	var children: Array[Node] = container.get_children()

	# Hide everything, then stagger each element's fade-in
	for i in range(children.size()):
		var child = children[i]
		if not child is Control:
			continue
		child.modulate.a = 0.0
		var delay: float = i * ENTRANCE_STAGGER
		var tw = create_tween()
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(child, "modulate:a", 1.0, ENTRANCE_DURATION).set_delay(delay)


func _on_host_pressed() -> void:
	host_game_requested.emit()


func _on_join_pressed() -> void:
	join_game_requested.emit()


func _on_settings_pressed() -> void:
	var settings_menu = SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)
