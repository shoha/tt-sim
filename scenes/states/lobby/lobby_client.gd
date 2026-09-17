class_name LobbyClient
extends AnimatedCanvasLayerPanel

## Lobby screen for clients: enter a room code, then wait for the host.
## Root frees this node directly on state exit, so _on_after_animate_out() is a
## no-op here: a stray animate_out() must never free the lobby a second time.

signal leave_requested

## Tests set this false before adding the screen to the tree so headless runs
## never reach NetworkManager's signals or join_game().
@export var connect_network: bool = true

var header: MenuHeader

var _is_connected: bool = false
## Suppresses join sounds/flash during the initial player list sync so only
## the "you connected" sound plays, not an extra sound for every existing player.
var _suppressing_join_sounds: bool = false

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var connect_button: Button = %ConnectButton
@onready var paste_button: Button = %PasteButton
@onready var leave_button: Button = %LeaveButton
@onready var status_label: Label = %StatusLabel
@onready var player_list: ItemList = %PlayerList
@onready var waiting_container: Control = %WaitingContainer
@onready var input_container: Control = %InputContainer


func _on_panel_ready() -> void:
	var box: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	box.move_child(header, 0)
	header.setup("Join a game", "Enter the room code from the host")
	($ColorRect as ColorRect).color = ThemeColors.BACKGROUND

	# Connect UI signals
	connect_button.pressed.connect(_on_connect_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	paste_button.pressed.connect(_on_paste_pressed)
	room_code_input.text_submitted.connect(_on_room_code_submitted)

	if connect_network:
		NetworkManager.player_joined.connect(_on_player_joined)
		NetworkManager.player_left.connect(_on_player_left)
		NetworkManager.connection_failed.connect(_on_connection_failed)
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Load saved player name
	player_name_input.text = NetworkManager.get_player_name()

	# Initialize UI
	_show_input_state()


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
	_set_footer_action("Back", "arrow-left")
	player_name_input.grab_focus()
	_cross_fade(input_container)


func _show_connecting_state() -> void:
	status_label.text = "Connecting..."
	connect_button.disabled = true
	room_code_input.editable = false
	player_name_input.editable = false
	_set_footer_action("Leave", "logout")


func _show_connected_state() -> void:
	input_container.visible = false
	waiting_container.visible = true
	status_label.text = "Connected! Waiting for host to start..."
	_set_footer_action("Leave", "logout")
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


func _on_paste_pressed() -> void:
	var clipboard_text = DisplayServer.clipboard_get().strip_edges()
	if not clipboard_text.is_empty():
		room_code_input.text = clipboard_text
		room_code_input.caret_column = clipboard_text.length()


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
		NetworkManager.ConnectionState.OFFLINE:
			if _is_connected:
				status_label.text = "Disconnected from server"
				_is_connected = false
			_show_input_state()


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


## The footer action is Back while the form is still up and Leave once a
## connection is under way — the same button, renamed with the situation.
func _set_footer_action(label: String, icon: String) -> void:
	leave_button.text = label
	leave_button.icon = IconButton.load_icon(icon)
