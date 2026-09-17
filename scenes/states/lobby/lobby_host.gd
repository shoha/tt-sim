class_name LobbyHost
extends AnimatedCanvasLayerPanel

## Lobby screen for the host.
## Shows the room code, the level about to be played, and who has joined.
## Root frees this node directly on state exit, so _on_after_animate_out() is a
## no-op here: a stray animate_out() must never free the lobby a second time.

signal start_game_requested
signal cancel_requested
signal level_change_requested(level_info: Dictionary)

const LEVEL_PICKER_SCENE := preload("res://scenes/ui/level_picker_dialog.tscn")

## Tests set this false before adding the lobby to the tree so headless runs
## never reach NetworkManager.host_game() or its signal connections.
@export var start_hosting: bool = true

var header: MenuHeader
var _level: LevelData = null

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var room_code_value: Label = %RoomCodeValue
@onready var player_list: ItemList = %PlayerList
@onready var start_button: Button = %StartButton
@onready var cancel_button: Button = %CancelButton
@onready var status_label: Label = %StatusLabel
@onready var copy_button: Button = %CopyCodeButton
@onready var invite_button: Button = %InviteButton
@onready var level_thumb: TextureRect = %LevelThumb
@onready var level_name: Label = %LevelName
@onready var level_caption: Label = %LevelCaption
@onready var change_level_button: Button = %ChangeLevelButton


func _on_panel_ready() -> void:
	var box: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	box.move_child(header, 0)
	header.setup("Host a game", "Share the code, pick a level, start when everyone is in")
	($ColorRect as ColorRect).color = ThemeColors.BACKGROUND

	# Connect UI signals
	start_button.pressed.connect(_on_start_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	copy_button.pressed.connect(_on_copy_code_pressed)
	invite_button.pressed.connect(_on_invite_pressed)
	player_name_input.text_changed.connect(_on_player_name_changed)
	change_level_button.pressed.connect(_on_change_pressed)

	if start_hosting:
		# Connect network signals
		NetworkManager.room_code_received.connect(_on_room_code_received)
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		NetworkManager.connection_failed.connect(_on_connection_failed)
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Load and display saved player name
	player_name_input.text = NetworkManager.get_player_name()

	# Initialize UI
	room_code_value.text = "Connecting..."
	status_label.text = "Setting up lobby..."
	start_button.disabled = true
	_update_player_list()

	# Start hosting
	if start_hosting:
		NetworkManager.host_game()


func _on_after_animate_in() -> void:
	UiMotion.stagger_in(
		UiMotion.visible_children($CenterContainer/PanelContainer/MarginContainer/VBoxContainer),
		self
	)


## Root owns this node's lifetime — see the class comment.
func _on_after_animate_out() -> void:
	pass


func _exit_tree() -> void:
	# Disconnect network signals
	if NetworkManager.room_code_received.is_connected(_on_room_code_received):
		NetworkManager.room_code_received.disconnect(_on_room_code_received)
	if NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.disconnect(_on_player_joined)
	if NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.disconnect(_on_player_left)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)


func _on_room_code_received(code: String) -> void:
	room_code_value.text = code
	status_label.text = "Waiting for players..."
	start_button.disabled = false


func _on_player_joined(_peer_id: int, _player_info: Dictionary) -> void:
	_update_player_list()
	status_label.text = "%d player(s) connected" % NetworkManager.get_player_count()
	_flash_player_list()
	AudioManager.play_success()


func _on_player_left(_peer_id: int, _player_info: Dictionary) -> void:
	_update_player_list()
	status_label.text = "%d player(s) connected" % NetworkManager.get_player_count()
	_flash_player_list()
	AudioManager.play_tick()


func _on_connection_failed(reason: String) -> void:
	UIManager.show_error(reason)
	cancel_requested.emit()


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	match new_state:
		NetworkManager.ConnectionState.HOSTING:
			status_label.text = "Lobby ready!"
		NetworkManager.ConnectionState.OFFLINE:
			status_label.text = "Disconnected"


func _update_player_list() -> void:
	player_list.clear()
	var players = NetworkManager.get_players()
	if players.is_empty():
		player_list.add_item("Waiting for players...")
		player_list.set_item_disabled(0, true)
		player_list.set_item_selectable(0, false)
		return
	for peer_id in players:
		var info = players[peer_id]
		var player_name = info.get("name", "Player %d" % peer_id)
		if peer_id == 1:
			player_name += " (Host)"
		player_list.add_item(player_name)


func _on_start_pressed() -> void:
	start_game_requested.emit()


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


func _on_invite_pressed() -> void:
	NetworkManager.open_invite_overlay()


func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(room_code_value.text)
	UIManager.show_success("Code copied")


func _on_player_name_changed(new_name: String) -> void:
	var name_to_save = new_name.strip_edges()
	if name_to_save.is_empty():
		name_to_save = "Player"
	NetworkManager.save_player_name(name_to_save)
	_update_player_list()


## Brief highlight flash on the player list when someone joins or leaves
func _flash_player_list() -> void:
	var tw = player_list.create_tween()
	tw.tween_property(player_list, "self_modulate", Color(1.3, 1.2, 1.0, 1.0), 0.1)
	tw.tween_property(player_list, "self_modulate", Color.WHITE, 0.3)


## Show the pending level the root handed over (or the replacement after Change).
func set_level(level: LevelData) -> void:
	_level = level
	level_name.text = level.level_name
	var count := level.token_placements.size()
	level_caption.text = (
		"No tokens" if count == 0 else ("1 token" if count == 1 else "%d tokens" % count)
	)
	level_thumb.texture = null
	if not level.level_folder.is_empty():
		var path := LevelManager.thumbnail_path(level.level_folder)
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image:
				level_thumb.texture = ImageTexture.create_from_image(image)
	if level_thumb.texture == null:
		var config := EnvironmentPresets.get_environment_config(level.environment_preset, {}, {})
		level_thumb.texture = SwatchTextures.sky_preview(String(config.get("sky_preset", "")))


## The level already picked: its card cannot be deleted from this picker.
func locked_level_path() -> String:
	if _level == null or _level.level_folder.is_empty():
		return ""
	return LevelManager.folder_path(_level.level_folder)


func _on_change_pressed() -> void:
	var picker: LevelPickerDialog = LEVEL_PICKER_SCENE.instantiate()
	picker.setup("Change level", locked_level_path())
	picker.level_chosen.connect(_on_level_picked)
	get_tree().root.add_child(picker)
	# Cancelling the lobby (or otherwise leaving the tree) while the picker is
	# still open must not strand it floating over whatever comes next.
	tree_exiting.connect(picker.queue_free)


func _on_level_picked(info: Dictionary) -> void:
	level_change_requested.emit(info)
