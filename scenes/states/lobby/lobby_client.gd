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
## Suppresses join sounds/flash during the initial player list sync so only
## the "you connected" sound plays, not an extra sound for every existing player.
var _suppressing_join_sounds: bool = false


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
	NetworkManager.reconnecting.connect(_on_reconnecting)

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
	if NetworkManager.reconnecting.is_connected(_on_reconnecting):
		NetworkManager.reconnecting.disconnect(_on_reconnecting)


func _show_input_state() -> void:
	input_container.visible = true
	waiting_container.visible = false
	status_label.text = "Enter your name and the room code from the host"
	connect_button.disabled = false
	room_code_input.editable = true
	player_name_input.editable = true
	player_name_input.grab_focus()
	_cross_fade(input_container)


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
	_suppressing_join_sounds = true
	_update_player_list()
	_cross_fade(waiting_container)
	AudioManager.play_success()
	# Allow the initial player list sync from the host to complete before
	# treating subsequent player_joined signals as new-player events.
	get_tree().create_timer(1.0).timeout.connect(
		func(): _suppressing_join_sounds = false, CONNECT_ONE_SHOT
	)


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
		if not _suppressing_join_sounds:
			_flash_player_list()
			AudioManager.play_success()


func _on_player_left(_peer_id: int, _player_info: Dictionary) -> void:
	if _is_connected:
		_update_player_list()
		_flash_player_list()
		AudioManager.play_tick()


func _on_connection_failed(reason: String) -> void:
	status_label.text = "Connection failed: " + reason
	AudioManager.play_error()
	_show_input_state()


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	match new_state:
		NetworkManager.ConnectionState.JOINED:
			_show_connected_state()
		NetworkManager.ConnectionState.RECONNECTING:
			# Status will be updated by _on_reconnecting signal
			pass
		NetworkManager.ConnectionState.OFFLINE:
			if _is_connected:
				status_label.text = "Disconnected from server"
				_is_connected = false
			_show_input_state()


func _on_reconnecting(attempt: int, max_attempts: int) -> void:
	status_label.text = "Reconnecting (attempt %d/%d)..." % [attempt, max_attempts]


func _update_player_list() -> void:
	player_list.clear()
	var players = NetworkManager.get_players()
	if players.is_empty():
		player_list.add_item("No players yet")
		player_list.set_item_disabled(0, true)
		player_list.set_item_selectable(0, false)
		return
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


## Quick cross-fade when switching between lobby states
func _cross_fade(container: Control) -> void:
	container.modulate.a = 0.0
	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(container, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
