extends CanvasLayer

## Title screen controller.
## Provides options to play a saved level locally, or host/join a networked game.

signal host_game_requested
signal join_game_requested

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const LevelBrowserDialogScene := preload("res://scenes/ui/level_browser_dialog.tscn")

## Stagger delay between each UI element fading in (seconds)
const ENTRANCE_STAGGER := 0.08
const ENTRANCE_DURATION := 0.3

@onready var play_level_button: Button = %PlayLevelButton
@onready var host_button: Button = %HostGameButton
@onready var join_button: Button = %JoinGameButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	play_level_button.pressed.connect(_on_play_level_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	_play_entrance_animation()


## Staggered fade-in + slide-up for title screen UI elements
func _play_entrance_animation() -> void:
	var container = $PlaceholderContainer/CenterContainer/VBoxContainer
	var children: Array[Node] = container.get_children()

	# Hide everything immediately (before layout is computed)
	for child in children:
		if child is Control:
			child.modulate.a = 0.0

	# Wait one frame so the VBoxContainer computes its layout positions
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	# Now capture the real layout positions and animate each element
	for i in range(children.size()):
		var child = children[i]
		if not child is Control:
			continue
		var target_y: float = child.position.y
		child.position.y = target_y + 12.0  # Start 12px below final position
		var delay: float = i * ENTRANCE_STAGGER
		var tw = create_tween()
		tw.set_parallel(true)
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(child, "modulate:a", 1.0, ENTRANCE_DURATION).set_delay(delay)
		tw.tween_property(child, "position:y", target_y, ENTRANCE_DURATION).set_delay(delay)


func _on_play_level_pressed() -> void:
	var dialog = LevelBrowserDialogScene.instantiate()
	get_tree().root.add_child(dialog)


func _on_host_pressed() -> void:
	host_game_requested.emit()


func _on_join_pressed() -> void:
	join_game_requested.emit()


func _on_settings_pressed() -> void:
	var settings_menu = SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)


func _on_quit_pressed() -> void:
	get_tree().quit()
