class_name LevelFlow
extends Node

## A table's load, from the level a path into play hands over to the table it builds (Root's
## helper): the loading overlay over every map load (the map named, its progress, kept up when a
## queued level follows at once), the level a client receives from the host, the state stream a
## client applies to its tokens (RootNetworkHandler; a load under way holds it, and it is applied
## once the load completes), the client's report that its table is built (LateJoinerSync), and
## the party set out on each new table (SessionParty). Building a map (AUTHORING) shows its loads
## on the same overlay (track_authoring()); the room's "Opening a room..." wait is SessionFlow's.
##
## Root's pending level (Root.pending_level) is the level being set out, on every path into play
## (host, client and solo), until its load completes or fails. While it is set, the table
## clearing is part of the load (LevelPlayController.play_level() clears before it loads); a
## table cleared without one sends Root to the title.

const RootScript := preload("res://scenes/root.gd")
const LOADING_OVERLAY_SCENE := preload("res://scenes/ui/loading_overlay.tscn")

## The full-screen loading overlay, always present (a child of this flow)
var loading_overlay: LoadingOverlay = null

var _root: RootScript = null
var _controller: LevelPlayController = null


## Root and its table, which live as long as Root does: listens to the table's loads and adds
## the loading overlay.
func setup(root: RootScript, controller: LevelPlayController) -> void:
	_root = root
	_controller = controller
	controller.level_loaded.connect(_on_level_play_loaded)
	controller.level_cleared.connect(_on_level_cleared)
	controller.level_loading_started.connect(_on_level_loading_started)
	controller.level_loading_progress.connect(_on_level_loading_progress)
	controller.level_loading_completed.connect(_on_level_loading_completed)
	loading_overlay = LOADING_OVERLAY_SCENE.instantiate()
	add_child(loading_overlay)


## Client, entering a table: listen for the level and the state stream from the host.
func start_client_table() -> void:
	NetworkManager.level_data_received.connect(_on_level_data_received)
	RootNetworkHandler.connect_client_signals(self)


## Leaving a table: stop listening for the level and the state stream (any peer).
func stop_client_table() -> void:
	if NetworkManager.level_data_received.is_connected(_on_level_data_received):
		NetworkManager.level_data_received.disconnect(_on_level_data_received)
	RootNetworkHandler.disconnect_client_signals(self)


## Building a map (AUTHORING) shows its loads on the same overlay.
func track_authoring(controller: AuthoringController) -> void:
	controller.loading_started.connect(_on_authoring_loading_started)
	controller.loading_progress.connect(_on_level_loading_progress)
	controller.loading_completed.connect(_on_authoring_loading_completed)


## Hide the overlay if a load still shows it (leaving AUTHORING).
func end_loading() -> void:
	if loading_overlay and loading_overlay.visible:
		loading_overlay.hide_loading()


func _on_level_play_loaded(_level_data: LevelData) -> void:
	# Already in PLAYING state, no need to transition
	# Clear pending data now that loading is complete
	_root.pending_level = null
	# The party that left the last table with the session lands on this one (host).
	NetworkManager.session.party.set_out()


func _on_level_cleared() -> void:
	# Don't transition if we're in the middle of loading a new level
	# (play_level() calls clear_level() internally before loading)
	if _root.pending_level:
		return
	_root.change_state(RootScript.State.TITLE_SCREEN)


## A map load names its map (UI_TASTE.md W4): the pending level is the one being set out on
## every path into play (host, client and solo), or null after a queued load's handover.
func _on_level_loading_started() -> void:
	if loading_overlay:
		loading_overlay.show_loading(LoadingOverlay.setting_out_text(_root.pending_level))


func _on_level_loading_progress(progress: float, status: String) -> void:
	if loading_overlay:
		loading_overlay.set_progress(progress, status)


func _on_level_loading_completed() -> void:
	# Don't hide loading overlay if there's another level queued - it will start loading immediately
	# This prevents a visual flash between levels
	if loading_overlay and not (_controller and _controller.has_queued_level()):
		loading_overlay.hide_loading()

	# Apply any GameState updates that arrived during async loading
	# This syncs token properties and creates any tokens added by host during loading
	if NetworkManager.is_client():
		RootNetworkHandler.apply_game_state_to_tokens(_controller, _root.get_game_map())
		# Tell the host the table is built, unless a queued level is about to clear it again:
		# a late joiner's full state is held until now, since the loader's clear_level()
		# wipes any state that lands before it (LateJoinerSync).
		if not (_controller and _controller.has_queued_level()):
			NetworkManager.report_table_loaded()

	# Clear pending data in case loading was aborted
	# (successful loads clear this in _on_level_play_loaded via level_loaded signal)
	_root.pending_level = null


func _on_authoring_loading_started() -> void:
	if loading_overlay:
		loading_overlay.show_loading("Building the map...")


func _on_authoring_loading_completed() -> void:
	if loading_overlay:
		loading_overlay.hide_loading()


func _on_level_data_received(level_dict: Dictionary) -> void:
	# Client received level data from host
	var level_data = LevelData.from_dict(level_dict)
	if _controller and _root.get_game_map():
		# Set pending data to prevent _on_level_cleared from returning to title
		# Don't clear until loading completes (play_level is async)
		_root.pending_level = level_data
		if not _controller.play_level(level_data):
			push_error("Root: Failed to load networked level")


## Handle full state sync (initial sync or reconciliation)
func _on_full_state_received(_state_dict: Dictionary) -> void:
	if _controller and _controller.is_loading():
		return
	RootNetworkHandler.apply_game_state_to_tokens(_controller, _root.get_game_map())


## Handle individual token transform update (unreliable channel, high frequency)
func _on_token_transform_received(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	if not _controller or not _root.get_game_map():
		return
	RootNetworkHandler.on_token_transform_received(_controller, network_id, pos, rot, scl)


## Handle batch transform update (unreliable channel)
func _on_transform_batch_received(batch: Dictionary) -> void:
	if not _controller or not _root.get_game_map():
		return
	RootNetworkHandler.on_transform_batch_received(_controller, batch)


## Handle individual token property update (reliable channel, low frequency)
func _on_token_state_received(network_id: String, token_dict: Dictionary) -> void:
	if not _controller or not _root.get_game_map():
		return
	RootNetworkHandler.on_token_state_received(
		_controller, _root.get_game_map(), network_id, token_dict
	)


## Handle token removal (reliable channel)
func _on_token_removed_received(network_id: String) -> void:
	if not _controller:
		return
	RootNetworkHandler.on_token_removed_received(_controller, network_id)
