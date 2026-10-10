extends Node3D

## Root scene controller - manages application state and scene transitions.
##
## Uses a state stack to support overlay states (like PAUSED on top of PLAYING).
## - change_state(): Replaces entire stack with a new base state
## - push_state(): Adds overlay state on top of current state
## - pop_state(): Removes top overlay state, returning to previous
##
## Root is the state machine and the wiring between the states' views and its helpers, each a
## child it sets up once:
## - SessionFlow (scenes/session_flow.gd): the way into a hosted session and out of it. Host,
##   Join (the join screen over the title), the room full screen in ROOM (RoomScreen), Set out,
##   leaving, and the network events that move Root between TITLE_SCREEN, ROOM and PLAYING.
## - TableMover (scenes/table_mover.gd): moving the table between the session's maps (the
##   drawer's Move the table here, return_to_room()) and what each map keeps of the session;
##   Root carries a move out (_on_table_level_chosen()), or SessionFlow opens the room.
## - LevelFlow (scenes/level_flow.gd): a table's load and the loading overlay, the level and
##   the state stream a client receives, and the party set out on each new table.
## Every path into play (host, client, solo, a table move) hands its level over in
## pending_level, which LevelFlow clears once the load completes or fails.
## A hosted session goes TITLE > ROOM (Host or Join), ROOM > PLAYING (Set out), PLAYING >
## PLAYING (Move the table here), PLAYING > ROOM (Return everyone to the room), and ROOM or
## PLAYING > TITLE (leave, or the host ends the session); the table of transitions is in
## docs/NETWORKING.md ("Sessions, the room and the table").

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
const UPDATE_DIALOG_SCENE := preload("res://scenes/ui/update_dialog.tscn")
const NEW_MAP_DIALOG_SCENE := preload("res://scenes/states/authoring/new_map_dialog.tscn")
const GRAPHICS_WARMUP_SCENE := preload("res://scenes/states/warmup/graphics_warmup_screen.tscn")
## Where leaving authoring returns to.
const RETURN_TO_TITLE := &"title"
const RETURN_TO_EDITOR := &"editor"

## The level the next table sets out, on every path into play (host, client and solo), from the
## request until its load completes or fails (LevelFlow); null otherwise. Entering ROOM, the
## host's is the map it opened the room with, shelved and selected (SessionFlow).
var pending_level: LevelData = null

var _state_stack: Array[State] = []
var _title_screen: CanvasLayer = null
var _app_menu: CanvasLayer = null
var _game_map: GameMap = null
var _pause_overlay: CanvasLayer = null
var _level_play_controller: LevelPlayController = null
## A table's load and the loading overlay, and a client's level and state stream
var _level_flow: LevelFlow = null
## Moves the table between the session's maps and keeps each map's session state
var _table_mover: TableMover = null
## Host, Join, the room and leaving a session
var _session_flow: SessionFlow = null
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
	# Network signals (hosting, the room, disconnects and player events while in-game)
	_setup_session_flow()

	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

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
	# The loads and the loading overlay (always available). Set up before TableMover, so the
	# party is set out on a loaded table before TableMover's own level_loaded handler runs.
	_level_flow = LevelFlow.new()
	_level_flow.name = "LevelFlow"
	add_child(_level_flow)
	_level_flow.setup(self, _level_play_controller)
	_table_mover = TableMover.new()
	_table_mover.name = "TableMover"
	add_child(_table_mover)
	_table_mover.setup(_level_play_controller)
	_table_mover.level_chosen.connect(_on_table_level_chosen)


## After TableMover's setup: the flow's network handlers run after the mover's and the
## keeper's (SessionFlow._ready()).
func _setup_session_flow() -> void:
	_session_flow = SessionFlow.new()
	_session_flow.name = "SessionFlow"
	_session_flow.setup(self, _table_mover, _level_flow.loading_overlay)
	add_child(_session_flow)
	_session_flow.join_screen_shown.connect(
		func(shown: bool) -> void:
			if _title_screen:
				_title_screen.visible = not shown
	)


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
		pending_level = level_data
		_session_flow.set_out_pending()
		return

	# If already in PLAYING state, reload the level directly
	if get_current_state() == State.PLAYING and _level_play_controller:
		# Set pending data to prevent level_cleared from triggering title screen
		# Note: Don't clear this until loading completes (play_level is async)
		pending_level = level_data
		# The party leaves with the session before the load clears the table.
		NetworkManager.session.party.take()
		_level_play_controller.play_level(level_data)
		# pending_level is cleared by LevelFlow when loading completes

		# Broadcast level data to clients if we're the host
		if NetworkManager.is_host():
			NetworkManager.broadcast_level_data(level_data.to_dict())
		return

	# Otherwise, store level data and transition to PLAYING state
	pending_level = level_data
	change_state(State.PLAYING)


## Get the current (topmost) state
func get_current_state() -> State:
	if _state_stack.size() > 0:
		return _state_stack[-1]
	return State.TITLE_SCREEN


## True when `state` is anywhere on the stack: PLAYING stays under a PAUSED pushed over it.
func is_in_state(state: State) -> bool:
	return state in _state_stack


## The table's GameMap in PLAYING and AUTHORING, else null.
func get_game_map() -> GameMap:
	return _game_map


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
				_title_screen.host_game_requested.connect(_session_flow.host_from_title)
			if _title_screen.has_signal("join_game_requested"):
				_title_screen.join_game_requested.connect(_session_flow.open_join_screen)
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
			_session_flow.enter_room()
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
	# Note: Don't clear pending_level until loading completes (play_level is async)
	# LevelFlow clears it once the table has loaded or the load ends
	if NetworkManager.is_host() and pending_level:
		# Host: Load level and broadcast to clients
		if not _level_play_controller.play_level(pending_level):
			push_error("Root: Failed to play level")
		else:
			# Broadcast level data to all clients
			NetworkManager.broadcast_level_data(pending_level.to_dict())
	elif NetworkManager.is_client():
		# Client: Listen for level data and state updates from host
		_level_flow.start_client_table()
	elif pending_level:
		# Local play: Just load the level
		if not _level_play_controller.play_level(pending_level):
			push_error("Root: Failed to play level")


## The room drawer over the table: Move the table here, the shelf rows' Save into map and
## Discard changes (TableMover), and Leave or End session.
func _connect_room_drawer() -> void:
	var menu = _game_map.gameplay_menu.get_node_or_null("GameplayMenu")
	var drawer: RoomDrawer = menu.get("room_drawer") if menu else null
	if drawer:
		drawer.move_table_requested.connect(_table_mover.request_move)
		drawer.leave_requested.connect(_on_pause_main_menu_requested)
		_table_mover.attach_panel(drawer.panel)


func _exit_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			if _title_screen:
				_title_screen.queue_free()
				_title_screen = null
			_session_flow.close_join_screen()
		State.ROOM:
			_session_flow.exit_room()
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
	_level_flow.stop_client_table()

	# The session file keeps the table as it stands; a move counting down goes with it.
	if _table_mover:
		_table_mover.table_closing()

	# Clear the level and reset loading state
	if _level_play_controller:
		_level_play_controller.reset_loading_state()
		_level_play_controller.clear_level_tokens()
		_level_play_controller.clear_level_map()

	# Remove GameMap
	if _game_map:
		_game_map.queue_free()
		_game_map = null


## The level TableMover chose for the table: set out from the room, or the table moved to it
## in play (over the pause menu too).
func _on_table_level_chosen(level: LevelData) -> void:
	if get_current_state() == State.PAUSED:
		pop_state()
	_on_play_level_requested(level)


## PLAYING > ROOM (host): Return everyone to the room, the table move with the room as its
## destination (TableMover: the notice, then the move; the table is kept as it is).
func return_to_room() -> void:
	if not NetworkManager.is_host() or State.PLAYING not in _state_stack:
		return
	_table_mover.request_move(TableMover.ROOM)


func _on_play_solo_requested(level_info: Dictionary) -> void:
	var level := LevelManager.load_level(String(level_info.get("path", "")), false)
	if level == null:
		UIManager.show_error(MapLoadError.for_info(level_info))
		return
	_on_play_level_requested(level)


func _on_level_loaded(_level_data: LevelData) -> void:
	pending_level = _level_data
	change_state(State.PLAYING)


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
	_level_flow.track_authoring(_authoring_controller)
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
	_level_flow.end_loading()
	if _game_map:
		_game_map.queue_free()
		_game_map = null


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


# ============================================================================
# Paused
# ============================================================================


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
