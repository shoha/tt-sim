extends Node3D

## Root scene controller - manages application state and scene transitions.
##
## Uses a state stack to support overlay states (like PAUSED on top of PLAYING).
## - change_state(): Replaces entire stack with a new base state
## - push_state(): Adds overlay state on top of current state
## - pop_state(): Removes top overlay state, returning to previous
##
## A hosted session is a room first (NetworkManager.session, SessionChannel): a room of
## people that can exist with no map, where the GM sets maps out and everyone returns
## between them, on one connection throughout. Entering ROOM never connects; the action that
## leads there does:
## ROOM shows the RoomPanel full screen (RoomScreen); at a table the same panel is the room
## drawer (RoomDrawer, Tab). Both name shelf maps by key (SessionChannel.ref_key()).
## - TITLE > ROOM: Host (host_session(): ROOM once hosting), or Join (the join screen over
##   the title: ROOM on room_opened, or PLAYING on game_starting when a table is out).
## - ROOM > PLAYING: the room's Set out this map (set_out(), then _on_lobby_start_game():
##   refused with no map).
## - PLAYING > PLAYING: the drawer's Move the table here (move_table()).
## - PLAYING > ROOM: Return everyone to the room (return_to_room(), host).
## Both moves are TableMover's: it counts the move down on every peer, keeps what the session
## did to each map and lays it over the map when it is set out again; Root then carries the
## move out (_on_table_level_chosen(), _open_room()). Saving a changed map into its folder or
## discarding its changes is the shelf rows' (the room's and the drawer's), through TableMover.
## Leaving a table, the host takes the party (the players' avatars, SessionParty) along, and
## sets it out on the next map once that map has loaded (_on_level_play_loaded()).
## - ROOM or PLAYING > TITLE: leave, or the host ends the session.

signal state_changed(old_state: State, new_state: State)

## The values are fixed: UIManager.ROOT_STATE_*, the validation bridge's state names and the
## net scenarios use the numbers.
enum State {
	TITLE_SCREEN = 0,
	ROOM = 1,  ## A hosted session between maps: everyone connected, no table out
	# 2 was LOBBY_CLIENT; ROOM replaced both lobby states on 2026-10-09.
	PLAYING = 3,
	PAUSED = 4,
	AUTHORING = 5,  ## Building or dressing a map in the game view (offline only)
	WARMING_UP = 6,  ## First-launch graphics warm-up before the title screen (GraphicsWarmup)
}

const TITLE_SCREEN_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const APP_MENU_SCENE := preload("res://scenes/ui/app_menu.tscn")
const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const PAUSE_OVERLAY_SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")
const LOBBY_CLIENT_SCENE := preload("res://scenes/states/lobby/lobby_client.tscn")
const UPDATE_DIALOG_SCENE := preload("res://scenes/ui/update_dialog.tscn")
const LOADING_OVERLAY_SCENE := preload("res://scenes/ui/loading_overlay.tscn")
const DISCONNECT_INDICATOR_SCENE := preload("res://scenes/ui/disconnect_indicator.tscn")
const NEW_MAP_DIALOG_SCENE := preload("res://scenes/states/authoring/new_map_dialog.tscn")
const GRAPHICS_WARMUP_SCENE := preload("res://scenes/states/warmup/graphics_warmup_screen.tscn")
## Where leaving authoring returns to.
const RETURN_TO_TITLE := &"title"
const RETURN_TO_EDITOR := &"editor"

var _state_stack: Array[State] = []
var _title_screen: CanvasLayer = null
var _app_menu: CanvasLayer = null
var _game_map: GameMap = null
var _pause_overlay: CanvasLayer = null
## The room's view in ROOM (the RoomPanel full screen)
var _room_screen: RoomScreen = null
## The join screen over the title, until the host places this client in the room or a table
var _join_screen: LobbyClient = null
## True from host_session() until hosting starts (ROOM) or fails (back to the title)
var _hosting_requested := false
## True after the player cancelled the "Opening a room..." wait, until a late HOSTING is closed
var _host_cancelled := false
var _level_play_controller: LevelPlayController = null
## Moves the table between the session's maps and keeps each map's session state
var _table_mover: TableMover = null
var _pending_level_data: LevelData = null
var _loading_overlay: LoadingOverlay = null
var _disconnect_indicator: Node = null
var _startup_update_check_pending: bool = false
var _authoring_controller: AuthoringController = null
## What the next AUTHORING state opens: {"level": LevelData or null, "new_map": spec,
## "return_to": RETURN_TO_*}. See request_authoring().
var _authoring_request: Dictionary = {}
var _new_map_dialog: NewMapDialog = null
var _warmup_screen: GraphicsWarmupScreen = null
var _warmup_entered: bool = false
## Whether the first entry into TITLE_SCREEN starts the startup update check (not for Steam,
## which updates the game itself). Consumed by _take_startup_update_check().
var _update_check_on_title: bool = false


func _ready() -> void:
	# Check the saved renderer preference first -- it may relaunch the process
	# entirely (see its own doc comment), so there is no reason to do any other
	# startup work first.
	SettingsMenu.apply_startup_rendering_method()

	# Apply saved graphics settings (fullscreen, vsync) before any UI is shown
	SettingsMenu.apply_startup_graphics_settings()

	# Setup core systems
	_setup_level_play_controller()
	_setup_app_menu()
	_setup_download_notifications()
	_setup_disconnect_indicator()

	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

	# Connect network signals (for handling disconnects and player events while in-game)
	NetworkManager.connection_state_changed.connect(_on_network_state_changed)
	NetworkManager.connection_failed.connect(_on_network_connection_failed)
	NetworkManager.player_left.connect(_on_network_player_left)
	NetworkManager.game_starting.connect(_on_network_game_starting)
	NetworkManager.session.room_opened.connect(_on_session_room_opened)

	# Connect EventBus signals — allows UIManager and other systems to request
	# state changes without importing this script.
	EventBus.pause_requested.connect(func(): push_state(State.PAUSED))
	EventBus.resume_requested.connect(func(): pop_state())
	EventBus.open_editor_requested.connect(_on_open_editor_requested)

	# Skip in-app updates for Steam users — Steam handles updates. The check starts on the
	# first title screen, so its dialog cannot open over the graphics warm-up.
	_update_check_on_title = OS.get_environment("SteamAppId").is_empty()

	# Enter initial state
	push_state(boot_state(GraphicsWarmup.should_run()))


func _setup_download_notifications() -> void:
	# Connect to AssetManager.downloader signals for user feedback
	AssetManager.downloader.download_completed.connect(_on_asset_download_completed)
	AssetManager.downloader.download_failed.connect(_on_asset_download_failed)


func _on_asset_download_completed(
	_pack_id: String, _asset_id: String, _variant_id: String, _local_path: String
) -> void:
	# Download success is shown quietly via the download queue UI
	pass


func _on_asset_download_failed(
	pack_id: String, asset_id: String, _variant_id: String, error: String
) -> void:
	var display_name = AssetManager.get_asset_display_name(pack_id, asset_id)
	UIManager.show_error("Failed to download " + display_name + ": " + error)


func _setup_level_play_controller() -> void:
	_level_play_controller = LevelPlayController.new()
	add_child(_level_play_controller)
	# The party (players' avatars) lands on this table after each map change (SessionParty).
	NetworkManager.session.party.attach(_level_play_controller)
	_level_play_controller.level_loaded.connect(_on_level_play_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)
	_table_mover = TableMover.new()
	_table_mover.name = "TableMover"
	add_child(_table_mover)
	_table_mover.setup(_level_play_controller)
	_table_mover.level_chosen.connect(_on_table_level_chosen)
	_table_mover.room_chosen.connect(_open_room)

	# Connect loading signals for the loading overlay
	_level_play_controller.level_loading_started.connect(_on_level_loading_started)
	_level_play_controller.level_loading_progress.connect(_on_level_loading_progress)
	_level_play_controller.level_loading_completed.connect(_on_level_loading_completed)

	# Create loading overlay (always available)
	_loading_overlay = LOADING_OVERLAY_SCENE.instantiate()
	add_child(_loading_overlay)
	_loading_overlay.cancel_requested.connect(_on_room_wait_cancelled)


func _setup_disconnect_indicator() -> void:
	_disconnect_indicator = DISCONNECT_INDICATOR_SCENE.instantiate()
	add_child(_disconnect_indicator)


func _show_disconnect_indicator(text: String) -> void:
	_disconnect_indicator.show_message(text)


func _hide_disconnect_indicator() -> void:
	_disconnect_indicator.hide_indicator()


func _setup_app_menu() -> void:
	_app_menu = APP_MENU_SCENE.instantiate()
	add_child(_app_menu)

	# Get the controller and set it up
	var app_menu_controller = _app_menu.get_node("AppMenu")
	if app_menu_controller:
		app_menu_controller.setup(_level_play_controller)
		app_menu_controller.play_level_requested.connect(_on_play_level_requested)
		app_menu_controller.build_map_requested.connect(
			func(level: LevelData) -> void: request_authoring(level, RETURN_TO_EDITOR)
		)


func _on_open_editor_requested(level_path: String = "") -> void:
	var app_ctrl = _app_menu.get_node_or_null("AppMenu") if _app_menu else null
	if app_ctrl:
		app_ctrl.open_level_editor(level_path)


func _on_play_level_requested(level_data: LevelData) -> void:
	# In the room a map only goes out through Set out, so the clients follow it.
	if get_current_state() == State.ROOM and NetworkManager.is_host():
		_pending_level_data = level_data
		_on_lobby_start_game()
		return

	# If already in PLAYING state, reload the level directly
	if get_current_state() == State.PLAYING and _level_play_controller:
		# Set pending data to prevent level_cleared from triggering title screen
		# Note: Don't clear this until loading completes (play_level is async)
		_pending_level_data = level_data
		# The party leaves with the session before the load clears the table.
		NetworkManager.session.party.take()
		_level_play_controller.play_level(level_data)
		# _pending_level_data is cleared in _on_level_play_loaded() when loading completes

		# Broadcast level data to clients if we're the host
		if NetworkManager.is_host():
			NetworkManager.broadcast_level_data(level_data.to_dict())
		return

	# Otherwise, store level data and transition to PLAYING state
	_pending_level_data = level_data
	change_state(State.PLAYING)


## Get the current (topmost) state
func get_current_state() -> State:
	if _state_stack.size() > 0:
		return _state_stack[-1]
	return State.TITLE_SCREEN


## Push a new state onto the stack (for overlay states like PAUSED)
func push_state(state: State) -> void:
	var old_state := get_current_state()
	_state_stack.push_back(state)
	_enter_state(state)
	state_changed.emit(old_state, state)
	EventBus.state_changed.emit(old_state, state)


## Pop the top state from the stack (returns to previous state)
func pop_state() -> void:
	if _state_stack.size() <= 1:
		return  # Don't pop the last state
	var old_state: State = _state_stack.pop_back()
	_exit_state(old_state)
	var new_state := get_current_state()
	state_changed.emit(old_state, new_state)
	EventBus.state_changed.emit(old_state, new_state)


## Replace the entire state stack with a new base state
func change_state(new_state: State) -> void:
	var old_state := get_current_state()
	if new_state == old_state and _state_stack.size() == 1:
		return

	# Exit all current states (top to bottom)
	while _state_stack.size() > 0:
		var state_to_exit: State = _state_stack.pop_back()
		_exit_state(state_to_exit)

	# Push the new base state
	_state_stack.push_back(new_state)
	_enter_state(new_state)

	state_changed.emit(old_state, new_state)
	EventBus.state_changed.emit(old_state, new_state)


## The first state: the graphics warm-up when `warm` (GraphicsWarmup.should_run()), else the
## title screen.
static func boot_state(warm: bool) -> State:
	return State.WARMING_UP if warm else State.TITLE_SCREEN


## True once, on the first call, when the startup update check is wanted.
func _take_startup_update_check() -> bool:
	var take := _update_check_on_title
	_update_check_on_title = false
	return take


func _enter_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			_title_screen = TITLE_SCREEN_SCENE.instantiate()
			add_child(_title_screen)
			# Connect title screen signals
			if _title_screen.has_signal("host_game_requested"):
				_title_screen.host_game_requested.connect(_on_host_game_requested)
			if _title_screen.has_signal("join_game_requested"):
				_title_screen.join_game_requested.connect(_on_join_game_requested)
			if _title_screen.has_signal("play_solo_requested"):
				_title_screen.play_solo_requested.connect(_on_play_solo_requested)
			if _title_screen.has_signal("build_map_requested"):
				_title_screen.build_map_requested.connect(
					func() -> void: request_authoring(null, RETURN_TO_TITLE)
				)
			if _title_screen.has_signal("edit_map_requested"):
				_title_screen.edit_map_requested.connect(_on_edit_map_requested)
			var title_app_ctrl = _app_menu.get_node_or_null("AppMenu") if _app_menu else null
			if title_app_ctrl:
				title_app_ctrl.hide_editor_button()
			if _take_startup_update_check():
				_check_for_updates_on_startup()
		State.ROOM:
			_enter_room_state()
		State.PLAYING:
			_enter_playing_state()
		State.PAUSED:
			_enter_paused_state()
		State.AUTHORING:
			_enter_authoring_state()
		State.WARMING_UP:
			_enter_warming_up_state()


func _enter_playing_state() -> void:
	# Instantiate GameMap
	_game_map = GAME_MAP_SCENE.instantiate()
	add_child(_game_map)

	# Setup bidirectional references between LevelPlayController and GameMap
	_level_play_controller.setup(_game_map)
	_game_map.setup(_level_play_controller)
	_connect_room_drawer()

	# Hide the AppMenu "Level Editor" button during gameplay — the pause
	# menu provides "Edit Level" instead.
	var app_ctrl = _app_menu.get_node_or_null("AppMenu") if _app_menu else null
	if app_ctrl:
		app_ctrl.hide_editor_button()

	# Handle networked vs local play
	# Note: Don't clear _pending_level_data until loading completes (play_level is async)
	# It will be cleared in _on_level_play_loaded or _on_level_loading_completed
	if NetworkManager.is_host() and _pending_level_data:
		# Host: Load level and broadcast to clients
		if not _level_play_controller.play_level(_pending_level_data):
			push_error("Root: Failed to play level")
		else:
			# Broadcast level data to all clients
			NetworkManager.broadcast_level_data(_pending_level_data.to_dict())
	elif NetworkManager.is_client():
		# Client: Listen for level data and state updates from host
		NetworkManager.level_data_received.connect(_on_level_data_received)
		_connect_client_state_signals()
	elif _pending_level_data:
		# Local play: Just load the level
		if not _level_play_controller.play_level(_pending_level_data):
			push_error("Root: Failed to play level")


## The room drawer over the table: Move the table here, the shelf rows' Save into map and
## Discard changes (TableMover), and Leave or End session.
func _connect_room_drawer() -> void:
	var menu = _game_map.gameplay_menu.get_node_or_null("GameplayMenu")
	var drawer: RoomDrawer = menu.get("room_drawer") if menu else null
	if drawer:
		drawer.move_table_requested.connect(move_table)
		drawer.leave_requested.connect(_on_pause_main_menu_requested)
		_table_mover.attach_panel(drawer.panel)


## Connect client-side signals for receiving state updates
func _connect_client_state_signals() -> void:
	RootNetworkHandler.connect_client_signals(self)


## Disconnect client-side state signals
func _disconnect_client_state_signals() -> void:
	RootNetworkHandler.disconnect_client_signals(self)


func _exit_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			if _title_screen:
				_title_screen.queue_free()
				_title_screen = null
			_close_join_screen()
		State.ROOM:
			_exit_room_state()
		State.PLAYING:
			_exit_playing_state()
		State.PAUSED:
			_exit_paused_state()
		State.AUTHORING:
			_exit_authoring_state()
		State.WARMING_UP:
			_exit_warming_up_state()


func _enter_warming_up_state() -> void:
	assert(not _warmup_entered, "Root: the graphics warm-up runs at most once per process")
	_warmup_entered = true
	if _app_menu:
		_app_menu.hide()
	_warmup_screen = GRAPHICS_WARMUP_SCENE.instantiate()
	_warmup_screen.finished.connect(change_state.bind(State.TITLE_SCREEN), CONNECT_ONE_SHOT)
	add_child(_warmup_screen)


func _exit_warming_up_state() -> void:
	if _warmup_screen:
		_warmup_screen.queue_free()
		_warmup_screen = null
	if _app_menu:
		_app_menu.show()


func _exit_playing_state() -> void:
	# Disconnect network signals
	if NetworkManager.level_data_received.is_connected(_on_level_data_received):
		NetworkManager.level_data_received.disconnect(_on_level_data_received)
	_disconnect_client_state_signals()

	# A move still being asked about or counted down goes with the table.
	if _table_mover:
		_table_mover.cancel()

	# Clear the level and reset loading state
	if _level_play_controller:
		_level_play_controller.reset_loading_state()
		_level_play_controller.clear_level_tokens()
		_level_play_controller.clear_level_map()

	# Remove GameMap
	if _game_map:
		_game_map.queue_free()
		_game_map = null


## The room, full screen (RoomScreen), the same for the GM and the players. A map the GM
## hosted with (Host with this map) goes on the shelf, selected, ready to set out. Entering
## never connects; hosting or joining has already happened.
func _enter_room_state() -> void:
	_end_room_wait()
	var first := ""
	if NetworkManager.is_host() and _pending_level_data:
		first = NetworkManager.session.shelve(_pending_level_data.to_dict())
	_room_screen = RoomScreen.new()
	add_child(_room_screen)
	_room_screen.panel.set_out_requested.connect(set_out)
	_room_screen.panel.leave_requested.connect(_on_lobby_cancel)
	_table_mover.attach_panel(_room_screen.panel)
	if first != "":
		_room_screen.panel.select(first)


func _exit_room_state() -> void:
	if _room_screen:
		_room_screen.queue_free()
		_room_screen = null


## ROOM > PLAYING (host): set the shelf map `key` out, the room's Set out this map, with what
## this session did to it before (TableMover).
func set_out(key: String) -> void:
	_table_mover.set_out(key)


## PLAYING > PLAYING (host): the room drawer's Move the table here (TableMover: the notice,
## then the move; the table is kept as it is and the party goes along).
func move_table(key: String) -> void:
	_table_mover.request_move(key)


## The level TableMover chose for the table: set out from the room, or the table moved to it
## in play (over the pause menu too).
func _on_table_level_chosen(level: LevelData) -> void:
	if get_current_state() == State.PAUSED:
		pop_state()
	_on_play_level_requested(level)


## The title hands over the level the host picked; it goes on the shelf when the room opens,
## selected for Set out.
func _on_host_game_requested(level_info: Dictionary) -> void:
	var level := LevelManager.load_level(String(level_info.get("path", "")), false)
	if level == null:
		UIManager.show_error(MapLoadError.for_info(level_info))
		return
	host_session(level)


## TITLE > ROOM for the host: start hosting with `level` (null: none chosen yet) as the map
## to set out first. Root enters ROOM once NetworkManager is HOSTING, or stays on the title
## with the reason when hosting fails (_on_network_connection_failed).
func host_session(level: LevelData) -> void:
	if NetworkManager.connection_state != NetworkManager.ConnectionState.OFFLINE:
		return
	_pending_level_data = level
	_hosting_requested = true
	_host_cancelled = false
	if _loading_overlay:
		_loading_overlay.show_indeterminate(RoomScreen.OPENING, true, RoomScreen.OPENING_STEP)
	NetworkManager.host_game()


## The "Opening a room..." wait's Cancel: stop hosting and stay on the title. Hosting may
## still finish after this (Steam answers late); _on_network_state_changed drops it then.
func _on_room_wait_cancelled() -> void:
	if not _hosting_requested:
		return
	_hosting_requested = false
	_host_cancelled = true
	_pending_level_data = null
	_end_room_wait()
	NetworkManager.disconnect_game()


## Hide the "Opening a room..." wait (and any level loading a client had under way when the
## room opened). The next map load lays its own sky and bar (LoadingOverlay.show_loading).
func _end_room_wait() -> void:
	if _loading_overlay and _loading_overlay.visible:
		_loading_overlay.hide_loading()


## PLAYING > ROOM (host): Return everyone to the room, the table move with the room as its
## destination (TableMover: the notice, then the move; the table is kept as it is).
func return_to_room() -> void:
	if not NetworkManager.is_host() or State.PLAYING not in _state_stack:
		return
	_table_mover.request_move(TableMover.ROOM)


## Put the table away for everyone, once TableMover has settled it. The connection, the
## players and the Steam lobby stay; GameMap is torn down as on any move, and every client is
## sent to the room (SessionChannel.open). The party (the players' avatars) is taken first and
## set out on the next map (SessionParty). The next map is chosen in the room.
func _open_room() -> void:
	if not NetworkManager.is_host() or State.PLAYING not in _state_stack:
		return
	_pending_level_data = null
	NetworkManager.session.party.take()
	NetworkManager.session.open()
	change_state(State.ROOM)


## Client: the host opened the room, from the table or as this client joined it.
func _on_session_room_opened() -> void:
	if NetworkManager.is_client() and get_current_state() != State.ROOM:
		change_state(State.ROOM)


func _on_play_solo_requested(level_info: Dictionary) -> void:
	var level := LevelManager.load_level(String(level_info.get("path", "")), false)
	if level == null:
		UIManager.show_error(MapLoadError.for_info(level_info))
		return
	_on_play_level_requested(level)


# ============================================================================
# Authoring
# ============================================================================


## Opens map building for `level` (null: a level made there). A level with a map opens at
## once (a GLB-only level as a dressing layer over its Blender map); otherwise the new-map
## dialog asks for a size and starting biome first, and cancelling it changes nothing.
## `return_to` (RETURN_TO_TITLE or RETURN_TO_EDITOR) is where leaving goes back to.
func request_authoring(level: LevelData, return_to: StringName) -> void:
	var refusal := authoring_refusal(level, NetworkManager.is_networked())
	if refusal != "":
		UIManager.show_warning(refusal)
		return
	if level != null and level.has_map():
		_begin_authoring({"level": level, "return_to": return_to})
		return
	if is_instance_valid(_new_map_dialog):
		return
	_new_map_dialog = NEW_MAP_DIALOG_SCENE.instantiate()
	_new_map_dialog.map_chosen.connect(
		func(spec: Dictionary) -> void:
			_begin_authoring({"level": level, "new_map": spec, "return_to": return_to})
	)
	add_child(_new_map_dialog)


## Why map building cannot open for `level` right now, or "" when it can. Authoring is
## offline only (a session only ever receives a finished, saved map), and a built-in res://
## map has no level folder to write a document into. Pure.
static func authoring_refusal(level: LevelData, networked: bool) -> String:
	if networked:
		return "Maps are built offline. Leave the session to build or edit a map."
	if level != null and level.map_path.begins_with("res://"):
		return "Built-in maps cannot be edited in the game."
	return ""


func _begin_authoring(request: Dictionary) -> void:
	_authoring_request = request
	var app_ctrl = _app_menu.get_node_or_null("AppMenu") if _app_menu else null
	if app_ctrl:
		app_ctrl.close_level_editor()
	change_state(State.AUTHORING)


func _on_edit_map_requested(level_info: Dictionary) -> void:
	var level := LevelManager.load_level(String(level_info.get("path", "")), false)
	if level == null:
		UIManager.show_error(MapLoadError.for_info(level_info))
		return
	request_authoring(level, RETURN_TO_TITLE)


func _enter_authoring_state() -> void:
	_game_map = GAME_MAP_SCENE.instantiate()
	add_child(_game_map)
	_authoring_controller = AuthoringController.new()
	_authoring_controller.name = "AuthoringController"
	add_child(_authoring_controller)
	_authoring_controller.loading_started.connect(_on_authoring_loading_started)
	_authoring_controller.loading_progress.connect(_on_level_loading_progress)
	_authoring_controller.loading_completed.connect(_on_authoring_loading_completed)
	_authoring_controller.exit_requested.connect(_on_authoring_exit_requested)
	_authoring_controller.setup(_game_map)
	var app_ctrl = _app_menu.get_node_or_null("AppMenu") if _app_menu else null
	if app_ctrl:
		app_ctrl.hide_editor_button()
	_authoring_controller.start(_authoring_request)


func _exit_authoring_state() -> void:
	if _authoring_controller:
		_authoring_controller.teardown()
		_authoring_controller.queue_free()
		_authoring_controller = null
	if _loading_overlay and _loading_overlay.visible:
		_loading_overlay.hide_loading()
	if _game_map:
		_game_map.queue_free()
		_game_map = null


func _on_authoring_loading_started() -> void:
	if _loading_overlay:
		_loading_overlay.show_loading("Building the map...")


func _on_authoring_loading_completed() -> void:
	if _loading_overlay:
		_loading_overlay.hide_loading()


## Back to where authoring was opened from: the title (its level list is rebuilt on entry,
## so a saved map shows with its new thumbnail), or the Level Editor on the same level.
func _on_authoring_exit_requested(level: LevelData) -> void:
	var return_to: StringName = _authoring_request.get("return_to", RETURN_TO_TITLE)
	_authoring_request = {}
	change_state(State.TITLE_SCREEN)
	if return_to != RETURN_TO_EDITOR:
		return
	var app_ctrl = _app_menu.get_node_or_null("AppMenu") if _app_menu else null
	if app_ctrl:
		app_ctrl.open_level_editor_with_level(level)


## Title > Join: the join screen opens over the hidden title, and its Connect joins. Root
## moves on when the host places this client: ROOM on room_opened, or PLAYING on
## game_starting when a table is out. A client the host rejects stays here with the reason.
func _on_join_game_requested() -> void:
	if is_instance_valid(_join_screen):
		return
	_join_screen = LOBBY_CLIENT_SCENE.instantiate() as LobbyClient
	_join_screen.leave_requested.connect(_on_join_screen_left)
	add_child(_join_screen)
	if _title_screen:
		_title_screen.hide()


## The join screen's Back or Leave: drop any connection under way and show the title again.
func _on_join_screen_left() -> void:
	_close_join_screen()
	if _title_screen:
		_title_screen.show()
	NetworkManager.disconnect_game()


func _close_join_screen() -> void:
	if is_instance_valid(_join_screen):
		_join_screen.queue_free()
	_join_screen = null


## ROOM > PLAYING (host): set the pending map out. Refused with no map, which used to enter
## an empty PLAYING where clients waited for a level that never came.
func _on_lobby_start_game() -> void:
	if _pending_level_data == null:
		UIManager.show_warning("Choose a map to set out first")
		return
	NetworkManager.session.close()
	NetworkManager.notify_game_starting()
	change_state(State.PLAYING)


## ROOM > TITLE: a client leaves the session, the host ends it for everyone. The title
## comes first, so the disconnect that follows is not read as a lost connection.
func _on_lobby_cancel() -> void:
	_pending_level_data = null
	change_state(State.TITLE_SCREEN)
	NetworkManager.disconnect_game()


## Client: the host set a map out from the room, or this client joined while one is out.
func _on_network_game_starting() -> void:
	if NetworkManager.is_client() and State.PLAYING not in _state_stack:
		change_state(State.PLAYING)


func _on_network_state_changed(
	old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	# Hosting started from the title: the session opens in the room.
	if new_state == NetworkManager.ConnectionState.HOSTING and _hosting_requested:
		_hosting_requested = false
		change_state(State.ROOM)
		return
	# Hosting the player cancelled finished late: close it again.
	if new_state == NetworkManager.ConnectionState.HOSTING and _host_cancelled:
		_host_cancelled = false
		NetworkManager.disconnect_game.call_deferred()
		return
	# Handle a disconnect at a table or in the room.
	# PAUSED is pushed on top of PLAYING (not swapped), so check the whole
	# stack rather than just the top — otherwise pausing hides this branch.
	if new_state != NetworkManager.ConnectionState.OFFLINE:
		return
	if State.PLAYING in _state_stack or State.ROOM in _state_stack:
		_hide_disconnect_indicator()
		# Show disconnect dialog if we were in any networked state.
		# Exclude OFFLINE→OFFLINE (redundant) and HOSTING (the host only goes offline by
		# leaving, and every leave path changes to the title first).
		if (
			old_state != NetworkManager.ConnectionState.OFFLINE
			and old_state != NetworkManager.ConnectionState.HOSTING
		):
			_show_disconnect_dialog()


## Hosting from the title failed (Steam not running, no lobby): the title stays, with the
## reason.
func _on_network_connection_failed(reason: String) -> void:
	if not _hosting_requested:
		return
	_hosting_requested = false
	_pending_level_data = null
	_end_room_wait()
	UIManager.show_error(reason)


func _on_network_player_left(_peer_id: int, player_info: Dictionary) -> void:
	var player_name: String = player_info.get("name", "A player")
	UIManager.show_warning("%s disconnected" % player_name)


func _show_disconnect_dialog() -> void:
	var go_to_title := func(): change_state(State.TITLE_SCREEN)
	var dialog = (
		UIManager
		. show_confirmation(
			"Disconnected",
			"The connection to the host was lost.",
			"Return to Title",
			"",  # No cancel text
			go_to_title,
			go_to_title,  # ESC also returns to title — can't continue without host
		)
	)
	# Hide the cancel button since there's only one valid action
	if dialog:
		var cancel_btn = dialog.get_node_or_null("%CancelButton")
		if cancel_btn:
			cancel_btn.hide()


func _on_level_data_received(level_dict: Dictionary) -> void:
	# Client received level data from host
	var level_data = LevelData.from_dict(level_dict)
	if _level_play_controller and _game_map:
		# Set pending data to prevent _on_level_cleared from returning to title
		# Don't clear until loading completes (play_level is async)
		_pending_level_data = level_data
		if not _level_play_controller.play_level(level_data):
			push_error("Root: Failed to load networked level")


## Handle full state sync (initial sync or reconciliation)
func _on_full_state_received(_state_dict: Dictionary) -> void:
	if _level_play_controller and _level_play_controller.is_loading():
		return
	RootNetworkHandler.apply_game_state_to_tokens(_level_play_controller, _game_map)


## Handle individual token transform update (unreliable channel, high frequency)
func _on_token_transform_received(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	if not _level_play_controller or not _game_map:
		return
	RootNetworkHandler.on_token_transform_received(
		_level_play_controller, network_id, pos, rot, scl
	)


## Handle batch transform update (unreliable channel)
func _on_transform_batch_received(batch: Dictionary) -> void:
	if not _level_play_controller or not _game_map:
		return
	RootNetworkHandler.on_transform_batch_received(_level_play_controller, batch)


## Handle individual token property update (reliable channel, low frequency)
func _on_token_state_received(network_id: String, token_dict: Dictionary) -> void:
	if not _level_play_controller or not _game_map:
		return
	RootNetworkHandler.on_token_state_received(
		_level_play_controller, _game_map, network_id, token_dict
	)


## Handle token removal (reliable channel)
func _on_token_removed_received(network_id: String) -> void:
	if not _level_play_controller:
		return
	RootNetworkHandler.on_token_removed_received(_level_play_controller, network_id)


func _enter_paused_state() -> void:
	# Only pause the game tree in local (non-networked) games
	# Networked games continue running with the menu as an overlay
	if not NetworkManager.is_networked():
		get_tree().paused = true

	# Show pause overlay
	_pause_overlay = PAUSE_OVERLAY_SCENE.instantiate()
	add_child(_pause_overlay)

	# Connect pause overlay signals
	if _pause_overlay.has_signal("resume_requested"):
		_pause_overlay.resume_requested.connect(_on_pause_resume_requested)
	if _pause_overlay.has_signal("main_menu_requested"):
		_pause_overlay.main_menu_requested.connect(_on_pause_main_menu_requested)
	if _pause_overlay.has_signal("room_requested"):
		_pause_overlay.room_requested.connect(_on_pause_room_requested)
	if _pause_overlay is PauseOverlay and _level_play_controller:
		(_pause_overlay as PauseOverlay).watch_table(_level_play_controller)


func _on_pause_resume_requested() -> void:
	pop_state()


## Pause > Return everyone to the room: resume, then move the table to the room.
func _on_pause_room_requested() -> void:
	pop_state()
	return_to_room()


## PLAYING > TITLE: leave the table (a client leaves the session, the host ends it). The
## title comes first, so a client's own disconnect is not read as a lost connection (it
## used to leave a "connection to the host was lost" dialog over the title).
func _on_pause_main_menu_requested() -> void:
	var networked := NetworkManager.is_networked()
	if not networked:
		get_tree().paused = false
	change_state(State.TITLE_SCREEN)
	if networked:
		NetworkManager.disconnect_game()


func _exit_paused_state() -> void:
	# Hide pause overlay
	if _pause_overlay:
		_pause_overlay.queue_free()
		_pause_overlay = null

	# Resume the game tree (only needed for local games that were actually paused)
	if not NetworkManager.is_networked():
		get_tree().paused = false


func _on_level_loaded(_level_data: LevelData) -> void:
	_pending_level_data = _level_data
	change_state(State.PLAYING)


func _on_level_play_loaded(_level_data: LevelData) -> void:
	# Already in PLAYING state, no need to transition
	# Clear pending data now that loading is complete
	_pending_level_data = null
	# The party that left the last table with the session lands on this one (host).
	NetworkManager.session.party.set_out()


func _on_level_cleared() -> void:
	# Don't transition if we're in the middle of loading a new level
	# (play_level() calls clear_level() internally before loading)
	if _pending_level_data:
		return
	change_state(State.TITLE_SCREEN)


# ============================================================================
# Loading Overlay
# ============================================================================


## A map load names its map (UI_TASTE.md W4): the pending level is the one being set out on
## every path into play (host, client and solo), or null after a queued load's handover.
func _on_level_loading_started() -> void:
	if _loading_overlay:
		_loading_overlay.show_loading(LoadingOverlay.setting_out_text(_pending_level_data))


func _on_level_loading_progress(progress: float, status: String) -> void:
	if _loading_overlay:
		_loading_overlay.set_progress(progress, status)


func _on_level_loading_completed() -> void:
	# Don't hide loading overlay if there's another level queued - it will start loading immediately
	# This prevents a visual flash between levels
	if (
		_loading_overlay
		and not (_level_play_controller and _level_play_controller.has_queued_level())
	):
		_loading_overlay.hide_loading()

	# Apply any GameState updates that arrived during async loading
	# This syncs token properties and creates any tokens added by host during loading
	if NetworkManager.is_client():
		RootNetworkHandler.apply_game_state_to_tokens(_level_play_controller, _game_map)
		# Tell the host the table is built, unless a queued level is about to clear it again:
		# a late joiner's full state is held until now, since the loader's clear_level()
		# wipes any state that lands before it (LateJoinerSync).
		if not (_level_play_controller and _level_play_controller.has_queued_level()):
			NetworkManager.report_table_loaded()

	# Clear pending data in case loading was aborted
	# (successful loads clear this in _on_level_play_loaded via level_loaded signal)
	_pending_level_data = null


# ============================================================================
# Update Checking
# ============================================================================


func _check_for_updates_on_startup() -> void:
	# Wait a moment for the title screen to fully load before checking
	await get_tree().create_timer(1.0).timeout

	if not is_instance_valid(self):
		return

	# Only check if we're still on the title screen
	if get_current_state() == State.TITLE_SCREEN:
		_startup_update_check_pending = true

		# Connect one-shot handler for startup check only
		UpdateManager.update_available.connect(_on_startup_update_available, CONNECT_ONE_SHOT)
		UpdateManager.update_check_complete.connect(_on_startup_check_complete, CONNECT_ONE_SHOT)

		UpdateManager.check_for_updates()


func _on_startup_update_available(release_info: Dictionary) -> void:
	_startup_update_check_pending = false
	# Disconnect the complete signal since we got an update
	if UpdateManager.update_check_complete.is_connected(_on_startup_check_complete):
		UpdateManager.update_check_complete.disconnect(_on_startup_check_complete)

	# Show the update dialog
	var dialog = UPDATE_DIALOG_SCENE.instantiate()
	add_child(dialog)
	dialog.setup(release_info)


func _on_startup_check_complete(_has_update: bool) -> void:
	_startup_update_check_pending = false
	# Disconnect the available signal since check is done
	if UpdateManager.update_available.is_connected(_on_startup_update_available):
		UpdateManager.update_available.disconnect(_on_startup_update_available)
