extends CanvasLayer

## Lobby screen for clients.
## Allows entering a room code and shows connection status.

signal leave_requested

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var connect_button: Button = %ConnectButton
@onready var leave_button: Button = %LeaveButton
@onready var status_label: Label = %StatusLabel
@onready var player_list: ItemList = %PlayerList
@onready var waiting_container: Control = %WaitingContainer
@onready var input_container: Control = %InputContainer

var _is_connected: bool = false


func _ready() -> void:
	# Connect UI signals
	connect_button.pressed.connect(_on_connect_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	room_code_input.text_submitted.connect(_on_room_code_submitted)

	# Connect network signals
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Load saved player name
	player_name_input.text = NetworkManager.get_player_name()

	# Initialize UI
	_show_input_state()


func _exit_tree() -> void:
	# Disconnect network signals
	if NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.disconnect(_on_player_joined)
	if NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.disconnect(_on_player_left)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)


func _show_input_state() -> void:
	input_container.visible = true
	waiting_container.visible = false
	status_label.text = "Enter your name and the room code from the host"
	connect_button.disabled = false
	room_code_input.editable = true
	player_name_input.editable = true
	player_name_input.grab_focus()


func _show_connecting_state() -> void:
	status_label.text = "Connecting..."
	connect_button.disabled = true
	room_code_input.editable = false
	player_name_input.editable = false


func _show_connected_state() -> void:
	input_container.visible = false
	waiting_container.visible = true
	status_label.text = "Connected! Waiting for host to start..."
	_is_connected = true
	_update_player_list()


func _on_connect_pressed() -> void:
	var player_name = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"

	var code = room_code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Please enter a room code"
		return

	# Save and set player name before connecting
	NetworkManager.save_player_name(player_name)

	_show_connecting_state()
	NetworkManager.join_game(code)


func _on_room_code_submitted(_text: String) -> void:
	_on_connect_pressed()


func _on_leave_pressed() -> void:
	leave_requested.emit()


func _on_player_joined(_peer_id: int, _player_info: Dictionary) -> void:
	if _is_connected:
		_update_player_list()
		_flash_player_list()


func _on_player_left(_peer_id: int) -> void:
	if _is_connected:
		_update_player_list()
		_flash_player_list()


func _on_connection_failed(reason: String) -> void:
	status_label.text = "Connection failed: " + reason
	_show_input_state()


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	match new_state:
		NetworkManager.ConnectionState.JOINED:
			_show_connected_state()
		NetworkManager.ConnectionState.OFFLINE:
			if _is_connected:
				status_label.text = "Disconnected from server"
				_is_connected = false
			_show_input_state()


func _update_player_list() -> void:
	player_list.clear()
	var players = NetworkManager.get_players()
	for peer_id in players:
		var info = players[peer_id]
		var player_name = info.get("name", "Player %d" % peer_id)
		if peer_id == 1:
			player_name += " (Host)"
		elif peer_id == multiplayer.get_unique_id():
			player_name += " (You)"
		player_list.add_item(player_name)


## Brief highlight flash on the player list when someone joins or leaves
func _flash_player_list() -> void:
	var tw = player_list.create_tween()
	tw.tween_property(player_list, "self_modulate", Color(1.3, 1.2, 1.0, 1.0), 0.1)
	tw.tween_property(player_list, "self_modulate", Color.WHITE, 0.3)
