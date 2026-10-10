class_name LobbyClient
extends AnimatedCanvasLayerPanel

## The join form over the title (the title's Join), until the library title's Join in place
## replaces it: a name and a room code, then Connect. Once connected the form stays locked
## with "Connected. Joining the room..." until Root moves on (ROOM on room_opened, or PLAYING
## when a table is out), which frees it; the room itself is the RoomPanel. A failure or a lost
## connection unlocks the form with the reason.
## Root frees this node directly, so _on_after_animate_out() is a no-op here: a stray
## animate_out() must never free the form a second time.

signal leave_requested

## Tests set this false before adding the screen to the tree so headless runs
## never reach NetworkManager's signals or join_game().
@export var connect_network: bool = true

var header: MenuHeader

var _is_connected: bool = false

@onready var player_name_input: LineEdit = %PlayerNameInput
@onready var room_code_input: LineEdit = %RoomCodeInput
@onready var connect_button: Button = %ConnectButton
@onready var paste_button: Button = %PasteButton
@onready var leave_button: Button = %LeaveButton
@onready var status_label: Label = %StatusLabel
@onready var input_container: Control = %InputContainer


func _on_panel_ready() -> void:
	var box: VBoxContainer = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	box.move_child(header, 0)
	header.setup("Join a game", "Enter the room code from the host")
	var backdrop := $ColorRect as ColorRect
	backdrop.color = ThemeColors.of(backdrop, ThemeColors.BACKDROP)

	# Connect UI signals
	connect_button.pressed.connect(_on_connect_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	paste_button.pressed.connect(_on_paste_pressed)
	room_code_input.text_submitted.connect(_on_room_code_submitted)

	if connect_network:
		NetworkManager.connection_failed.connect(_on_connection_failed)
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)

	# Load saved player name
	player_name_input.text = NetworkManager.get_player_name()
	_show_input_state()


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children($CenterContainer/PanelContainer/MarginContainer/VBoxContainer)


## Root owns this node's lifetime — see the class comment.
func _on_after_animate_out() -> void:
	pass


func _exit_tree() -> void:
	super()
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed):
		NetworkManager.connection_state_changed.disconnect(_on_connection_state_changed)


func _show_input_state() -> void:
	status_label.text = ""
	_lock_form(false)
	_set_footer_action("Back", "arrow-left")
	player_name_input.grab_focus()
	rebuild_focus_trap()


func _show_connecting_state() -> void:
	status_label.text = "Connecting..."
	_lock_form(true)
	_set_footer_action("Leave", "logout")
	rebuild_focus_trap()


## Connected: the form stays locked until Root moves this client into the room or to the
## table.
func _show_connected_state() -> void:
	status_label.text = "Connected. Joining the room..."
	_lock_form(true)
	_set_footer_action("Leave", "logout")
	_is_connected = true
	AudioManager.play(&"success")
	rebuild_focus_trap()


func _lock_form(locked: bool) -> void:
	connect_button.disabled = locked
	room_code_input.editable = not locked
	player_name_input.editable = not locked


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


## NetworkManager emits connection_failed before it goes OFFLINE, so the reason is
## written after _show_input_state() (which clears the label) and _is_connected is
## dropped here, keeping the OFFLINE branch below from overwriting the reason with a
## generic "Disconnected from server".
func _on_connection_failed(reason: String) -> void:
	_is_connected = false
	_show_input_state()
	status_label.text = "Connection failed: " + reason
	AudioManager.play(&"error")


func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	match new_state:
		NetworkManager.ConnectionState.JOINED:
			_show_connected_state()
		NetworkManager.ConnectionState.OFFLINE:
			if _is_connected:
				_is_connected = false
				_show_input_state()
				status_label.text = "Disconnected from server"
			elif connect_button.disabled:
				# Went offline mid-connect without a failure reason: unlock the form.
				# When a failure reason was shown, the form is already unlocked and the
				# reason stays on screen.
				_show_input_state()


## The footer action is Back while the form is still up and Leave once a
## connection is under way — the same button, renamed with the situation.
func _set_footer_action(label: String, icon: String) -> void:
	leave_button.text = label
	leave_button.icon = IconButton.load_icon(icon)
