extends CanvasLayer

## Lobby screen for the host.
## Displays the room code, connected players, and provides a start game button.

signal start_game_requested
signal cancel_requested

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var room_code_label: Label = %RoomCodeLabel
@onready var room_code_value: Label = %RoomCodeValue
@onready var player_list: ItemList = %PlayerList
@onready var start_button: Button = %StartButton
@onready var cancel_button: Button = %CancelButton
@onready var status_label: Label = %StatusLabel
@onready var copy_button: Button = %CopyCodeButton


func _ready() -> void:
	# Connect UI signals
	start_button.pressed.connect(_on_start_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	copy_button.pressed.connect(_on_copy_code_pressed)
	player_name_input.text_changed.connect(_on_player_name_changed)

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
	NetworkManager.host_game()


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


func _on_player_left(_peer_id: int) -> void:
	_update_player_list()
	status_label.text = "%d player(s) connected" % NetworkManager.get_player_count()
	_flash_player_list()
	AudioManager.play_tick()


func _on_connection_failed(reason: String) -> void:
	status_label.text = "Connection failed: " + reason
	room_code_value.text = "Error"
	start_button.disabled = true


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


func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(room_code_value.text)
	# Brief visual + color feedback
	copy_button.text = "Copied!"
	var original_variant: StringName = copy_button.theme_type_variation
	copy_button.theme_type_variation = &"Success"
	await get_tree().create_timer(1.0).timeout
	copy_button.text = "Copy"
	copy_button.theme_type_variation = original_variant


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
