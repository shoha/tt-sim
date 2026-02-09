extends Node3D

## Root scene controller - manages application state and scene transitions.
##
## Uses a state stack to support overlay states (like PAUSED on top of PLAYING).
## - change_state(): Replaces entire stack with a new base state
## - push_state(): Adds overlay state on top of current state
## - pop_state(): Removes top overlay state, returning to previous

const TITLE_SCREEN_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const APP_MENU_SCENE := preload("res://scenes/ui/app_menu.tscn")
const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const PAUSE_OVERLAY_SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")
const LOBBY_HOST_SCENE := preload("res://scenes/states/lobby/lobby_host.tscn")
const LOBBY_CLIENT_SCENE := preload("res://scenes/states/lobby/lobby_client.tscn")
const UPDATE_DIALOG_SCENE := preload("res://scenes/ui/update_dialog.tscn")
const LOADING_OVERLAY_SCENE := preload("res://scenes/ui/loading_overlay.tscn")

enum State {
	TITLE_SCREEN,
	LOBBY_HOST,  ## Hosting a game, waiting for players
	LOBBY_CLIENT,  ## Joined a game, waiting for host to start
	PLAYING,
	PAUSED,
}

signal state_changed(old_state: State, new_state: State)

var _state_stack: Array[State] = []
var _title_screen: CanvasLayer = null
var _app_menu: CanvasLayer = null
var _game_map: GameMap = null
var _pause_overlay: CanvasLayer = null
var _lobby_host: CanvasLayer = null
var _lobby_client: CanvasLayer = null
var _level_play_controller: LevelPlayController = null
var _pending_level_data: LevelData = null
var _loading_overlay: LoadingOverlay = null
var _disconnect_indicator: CanvasLayer = null
var _disconnect_label: Label = null


func _ready() -> void:
	# Setup core systems
	_setup_level_play_controller()
	_setup_app_menu()
	_setup_download_notifications()
	_setup_update_checker()
	_setup_disconnect_indicator()

	# Connect to level manager signals
	LevelManager.level_loaded.connect(_on_level_loaded)

	# Connect network signals (for handling disconnects and player events while in-game)
	NetworkManager.connection_state_changed.connect(_on_network_state_changed)
	NetworkManager.reconnecting.connect(_on_network_reconnecting)
	NetworkManager.player_left.connect(_on_network_player_left)

	# Enter initial state
	push_state(State.TITLE_SCREEN)

	# Check for updates after a short delay to let the UI settle
	_check_for_updates_on_startup()


func _setup_download_notifications() -> void:
	# Connect to AssetDownloader signals for user feedback
	if has_node("/root/AssetDownloader"):
		var downloader = get_node("/root/AssetDownloader")
		downloader.download_completed.connect(_on_asset_download_completed)
		downloader.download_failed.connect(_on_asset_download_failed)


func _on_asset_download_completed(
	_pack_id: String, _asset_id: String, _variant_id: String, _local_path: String
) -> void:
	# Download success is shown quietly via the download queue UI
	pass


func _on_asset_download_failed(
	pack_id: String, asset_id: String, _variant_id: String, error: String
) -> void:
	var display_name = AssetPackManager.get_asset_display_name(pack_id, asset_id)
	UIManager.show_error("Failed to download " + display_name + ": " + error)


func _setup_level_play_controller() -> void:
	_level_play_controller = LevelPlayController.new()
	add_child(_level_play_controller)
	_level_play_controller.level_loaded.connect(_on_level_play_loaded)
	_level_play_controller.level_cleared.connect(_on_level_cleared)

	# Connect loading signals for the loading overlay
	_level_play_controller.level_loading_started.connect(_on_level_loading_started)
	_level_play_controller.level_loading_progress.connect(_on_level_loading_progress)
	_level_play_controller.level_loading_completed.connect(_on_level_loading_completed)

	# Create loading overlay (always available)
	_loading_overlay = LOADING_OVERLAY_SCENE.instantiate()
	add_child(_loading_overlay)


func _setup_disconnect_indicator() -> void:
	_disconnect_indicator = CanvasLayer.new()
	_disconnect_indicator.layer = Constants.LAYER_TOAST
	add_child(_disconnect_indicator)

	# Top-center margin container
	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_TOP_WIDE
	margin.anchor_right = 1.0
	margin.offset_bottom = 40
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top", 12)
	_disconnect_indicator.add_child(margin)

	# Panel with warning styling
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Constants.COLOR_TOAST_BG
	style.border_color = Constants.COLOR_WARNING
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)

	# Label
	_disconnect_label = Label.new()
	_disconnect_label.text = "Reconnecting..."
	_disconnect_label.theme_type_variation = "Body"
	_disconnect_label.add_theme_color_override("font_color", Constants.COLOR_WARNING)
	panel.add_child(_disconnect_label)

	# Start hidden
	_disconnect_indicator.hide()


func _show_disconnect_indicator(text: String) -> void:
	_disconnect_label.text = text
	if not _disconnect_indicator.visible:
		_disconnect_indicator.show()


func _hide_disconnect_indicator() -> void:
	_disconnect_indicator.hide()


func _setup_app_menu() -> void:
	_app_menu = APP_MENU_SCENE.instantiate()
	add_child(_app_menu)

	# Get the controller and set it up
	var app_menu_controller = _app_menu.get_node("AppMenu")
	if app_menu_controller:
		app_menu_controller.setup(_level_play_controller)
		app_menu_controller.play_level_requested.connect(_on_play_level_requested)


func _on_play_level_requested(level_data: LevelData) -> void:
	# If already in PLAYING state, reload the level directly
	if get_current_state() == State.PLAYING and _level_play_controller:
		# Set pending data to prevent level_cleared from triggering title screen
		# Note: Don't clear this until loading completes (play_level is async)
		_pending_level_data = level_data
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


## Pop the top state from the stack (returns to previous state)
func pop_state() -> void:
	if _state_stack.size() <= 1:
		return  # Don't pop the last state
	var old_state: State = _state_stack.pop_back()
	_exit_state(old_state)
	state_changed.emit(old_state, get_current_state())


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
		State.LOBBY_HOST:
			_enter_lobby_host_state()
		State.LOBBY_CLIENT:
			_enter_lobby_client_state()
		State.PLAYING:
			_enter_playing_state()
		State.PAUSED:
			_enter_paused_state()


func _enter_playing_state() -> void:
	# Instantiate GameMap
	_game_map = GAME_MAP_SCENE.instantiate()
	add_child(_game_map)

	# Setup bidirectional references between LevelPlayController and GameMap
	_level_play_controller.setup(_game_map)
	_game_map.setup(_level_play_controller)

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


## Connect client-side signals for receiving state updates
func _connect_client_state_signals() -> void:
	# Full state updates (initial sync, reconciliation)
	if not NetworkStateSync.full_state_received.is_connected(_on_full_state_received):
		NetworkStateSync.full_state_received.connect(_on_full_state_received)

	# Individual token updates
	if not NetworkManager.token_transform_received.is_connected(_on_token_transform_received):
		NetworkManager.token_transform_received.connect(_on_token_transform_received)
	if not NetworkManager.transform_batch_received.is_connected(_on_transform_batch_received):
		NetworkManager.transform_batch_received.connect(_on_transform_batch_received)
	if not NetworkManager.token_state_received.is_connected(_on_token_state_received):
		NetworkManager.token_state_received.connect(_on_token_state_received)
	if not NetworkManager.token_removed_received.is_connected(_on_token_removed_received):
		NetworkManager.token_removed_received.connect(_on_token_removed_received)


## Disconnect client-side state signals
func _disconnect_client_state_signals() -> void:
	if NetworkStateSync.full_state_received.is_connected(_on_full_state_received):
		NetworkStateSync.full_state_received.disconnect(_on_full_state_received)
	if NetworkManager.token_transform_received.is_connected(_on_token_transform_received):
		NetworkManager.token_transform_received.disconnect(_on_token_transform_received)
	if NetworkManager.transform_batch_received.is_connected(_on_transform_batch_received):
		NetworkManager.transform_batch_received.disconnect(_on_transform_batch_received)
	if NetworkManager.token_state_received.is_connected(_on_token_state_received):
		NetworkManager.token_state_received.disconnect(_on_token_state_received)
	if NetworkManager.token_removed_received.is_connected(_on_token_removed_received):
		NetworkManager.token_removed_received.disconnect(_on_token_removed_received)


func _exit_state(state: State) -> void:
	match state:
		State.TITLE_SCREEN:
			if _title_screen:
				_title_screen.queue_free()
				_title_screen = null
		State.LOBBY_HOST:
			_exit_lobby_host_state()
		State.LOBBY_CLIENT:
			_exit_lobby_client_state()
		State.PLAYING:
			_exit_playing_state()
		State.PAUSED:
			_exit_paused_state()


func _exit_playing_state() -> void:
	# Disconnect network signals
	if NetworkManager.level_data_received.is_connected(_on_level_data_received):
		NetworkManager.level_data_received.disconnect(_on_level_data_received)
	_disconnect_client_state_signals()

	# Clear the level and reset loading state
	if _level_play_controller:
		_level_play_controller.reset_loading_state()
		_level_play_controller.clear_level_tokens()
		_level_play_controller.clear_level_map()

	# Remove GameMap
	if _game_map:
		_game_map.queue_free()
		_game_map = null


func _enter_lobby_host_state() -> void:
	_lobby_host = LOBBY_HOST_SCENE.instantiate()
	add_child(_lobby_host)

	# Connect lobby signals
	if _lobby_host.has_signal("start_game_requested"):
		_lobby_host.start_game_requested.connect(_on_lobby_start_game)
	if _lobby_host.has_signal("cancel_requested"):
		_lobby_host.cancel_requested.connect(_on_lobby_cancel)


func _exit_lobby_host_state() -> void:
	if _lobby_host:
		_lobby_host.queue_free()
		_lobby_host = null


func _enter_lobby_client_state() -> void:
	_lobby_client = LOBBY_CLIENT_SCENE.instantiate()
	add_child(_lobby_client)

	# Connect lobby signals
	if _lobby_client.has_signal("leave_requested"):
		_lobby_client.leave_requested.connect(_on_lobby_cancel)

	# Listen for game starting from host
	if not NetworkManager.game_starting.is_connected(_on_network_game_starting):
		NetworkManager.game_starting.connect(_on_network_game_starting)
		print("Root: Connected game_starting signal handler")


func _exit_lobby_client_state() -> void:
	if _lobby_client:
		_lobby_client.queue_free()
		_lobby_client = null

	# Disconnect network signals
	if NetworkManager.game_starting.is_connected(_on_network_game_starting):
		NetworkManager.game_starting.disconnect(_on_network_game_starting)


func _on_host_game_requested() -> void:
	# Transition to host lobby
	change_state(State.LOBBY_HOST)


func _on_join_game_requested() -> void:
	# Transition to client lobby
	change_state(State.LOBBY_CLIENT)


func _on_lobby_start_game() -> void:
	# Host is starting the game - notify clients and transition
	NetworkManager.notify_game_starting()
	change_state(State.PLAYING)


func _on_lobby_cancel() -> void:
	# Cancel/leave lobby - disconnect and return to title
	NetworkManager.disconnect_game()
	change_state(State.TITLE_SCREEN)


func _on_network_game_starting() -> void:
	# Client received game starting signal from host
	print("Root: Received game_starting signal, transitioning to PLAYING state")
	change_state(State.PLAYING)


func _on_network_state_changed(
	old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	# Handle disconnect while in PLAYING state
	if new_state == NetworkManager.ConnectionState.OFFLINE and get_current_state() == State.PLAYING:
		_hide_disconnect_indicator()
		# Show disconnect dialog if we were in any networked state.
		# Exclude OFFLINE→OFFLINE (redundant) and HOSTING (host disconnects via
		# pause menu, which handles its own transition to title screen).
		if (
			old_state != NetworkManager.ConnectionState.OFFLINE
			and old_state != NetworkManager.ConnectionState.HOSTING
		):
			_show_disconnect_dialog()
	elif new_state == NetworkManager.ConnectionState.JOINED:
		# Successfully reconnected
		_hide_disconnect_indicator()


func _on_network_player_left(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	var players = NetworkManager.get_players()
	var player_name: String = "A player"
	if players.has(peer_id):
		player_name = players[peer_id].get("name", player_name)
	UIManager.show_warning("%s disconnected" % player_name)


func _on_network_reconnecting(attempt: int, max_attempts: int) -> void:
	# Show persistent indicator while reconnecting
	if get_current_state() == State.PLAYING:
		_show_disconnect_indicator(
			"Disconnected — Reconnecting (%d/%d)..." % [attempt, max_attempts]
		)


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
	# Don't apply state during loading - it will be applied when loading completes
	if _level_play_controller and _level_play_controller.is_loading():
		return
	_apply_game_state_to_tokens()


## Handle individual token transform update (unreliable channel, high frequency)
func _on_token_transform_received(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	var token = _level_play_controller.spawned_tokens.get(network_id) as BoardToken
	if token and is_instance_valid(token):
		token.set_interpolation_target(pos, rot, scl)


## Handle batch transform update (unreliable channel)
func _on_transform_batch_received(batch: Dictionary) -> void:
	for network_id in batch:
		var data = batch[network_id]
		var pos_arr = data["position"]
		var rot_arr = data["rotation"]
		var scl_arr = data["scale"]

		var pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
		var rot = Vector3(rot_arr[0], rot_arr[1], rot_arr[2])
		var scl = Vector3(scl_arr[0], scl_arr[1], scl_arr[2])

		var token = _level_play_controller.spawned_tokens.get(network_id) as BoardToken
		if token and is_instance_valid(token):
			token.set_interpolation_target(pos, rot, scl)


## Handle individual token property update (reliable channel, low frequency)
func _on_token_state_received(network_id: String, token_dict: Dictionary) -> void:
	var token_state = TokenState.from_dict(token_dict)

	# Update GameState using proper API (always do this, even during loading)
	GameState.set_token_state(network_id, token_state)

	# Don't create visual tokens during async loading - the loading process will
	# create them from placements, and we'll sync GameState afterward.
	# This prevents duplicate tokens from being created.
	if _level_play_controller and _level_play_controller.is_loading():
		return

	# Apply to visual token
	var token = _level_play_controller.spawned_tokens.get(network_id) as BoardToken
	if token and is_instance_valid(token):
		token_state.apply_to_token(token)
	else:
		# Token doesn't exist, might be a new one added by host - create it
		var new_token = _create_token_from_state(token_state)
		if new_token and _game_map:
			_game_map.drag_and_drop_node.add_child(new_token)
			_level_play_controller.spawned_tokens[network_id] = new_token


## Handle token removal (reliable channel)
func _on_token_removed_received(network_id: String) -> void:
	# Remove from GameState using proper API
	GameState.remove_token_state(network_id)

	# Remove visual token with shrink-out animation
	var token = _level_play_controller.spawned_tokens.get(network_id)
	if token and is_instance_valid(token):
		token.play_removal_animation()
	_level_play_controller.spawned_tokens.erase(network_id)


func _apply_game_state_to_tokens() -> void:
	# Update visual tokens from GameState
	if not _level_play_controller or not _game_map:
		return

	# Don't apply during loading - wait for loading to complete
	if _level_play_controller.is_loading():
		return

	var drag_and_drop = _game_map.drag_and_drop_node
	if not drag_and_drop:
		return

	for network_id in GameState.get_all_token_states():
		var token_state: TokenState = GameState.get_token_state(network_id)
		var token = _level_play_controller.spawned_tokens.get(network_id)

		if token and is_instance_valid(token):
			# Update existing token
			token_state.apply_to_token(token)
		else:
			# Create new token that was added on host
			var new_token = _create_token_from_state(token_state)
			if new_token:
				drag_and_drop.add_child(new_token)
				_level_play_controller.spawned_tokens[network_id] = new_token


func _create_token_from_state(token_state: TokenState) -> BoardToken:
	# Create a token from network state (with async download support)
	if token_state.pack_id == "" or token_state.asset_id == "":
		push_warning("Root: Cannot create token - missing pack_id or asset_id")
		return null

	# Use async factory method that handles remote asset downloading
	# Priority based on visibility - visible tokens download first
	var priority = (
		Constants.ASSET_PRIORITY_HIGH
		if token_state.is_visible_to_players
		else Constants.ASSET_PRIORITY_DEFAULT
	)

	var result = BoardTokenFactory.create_from_asset_async(
		token_state.pack_id, token_state.asset_id, token_state.variant_id, priority
	)

	var token = result.token
	var _is_placeholder = result.is_placeholder

	if not token:
		push_error("Root: Failed to create token from state")
		return null

	# Set network_id and metadata
	token.network_id = token_state.network_id
	token.set_meta("placement_id", token_state.network_id)
	token.set_meta("pack_id", token_state.pack_id)
	token.set_meta("asset_id", token_state.asset_id)
	token.set_meta("variant_id", token_state.variant_id)

	# Apply the full state (position, health, etc.) without interpolation for initial placement
	token_state.apply_to_token(token, false)

	# Download progress is shown via the compact download queue UI
	# No toast needed for placeholder assets

	return token


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


func _on_pause_resume_requested() -> void:
	pop_state()


func _on_pause_main_menu_requested() -> void:
	# First unpause (if paused), then return to title
	if not NetworkManager.is_networked():
		get_tree().paused = false
	else:
		NetworkManager.disconnect_game()
	change_state(State.TITLE_SCREEN)


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


func _on_level_cleared() -> void:
	# Don't transition if we're in the middle of loading a new level
	# (play_level() calls clear_level() internally before loading)
	if _pending_level_data:
		return
	change_state(State.TITLE_SCREEN)


# ============================================================================
# Loading Overlay
# ============================================================================


func _on_level_loading_started() -> void:
	if _loading_overlay:
		_loading_overlay.show_loading("Loading Level...")


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
		_apply_game_state_to_tokens()

	# Clear pending data in case loading was aborted
	# (successful loads clear this in _on_level_play_loaded via level_loaded signal)
	_pending_level_data = null


# ============================================================================
# Update Checking
# ============================================================================

var _startup_update_check_pending: bool = false


func _setup_update_checker() -> void:
	# We'll connect signals only for the startup check
	pass


func _check_for_updates_on_startup() -> void:
	# Wait a moment for the title screen to fully load before checking
	await get_tree().create_timer(1.0).timeout

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
