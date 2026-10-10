extends GutTest

## The client half of the late-joiner sync, through the real LevelPlayLoader and GameMap:
## a full state that lands inside the loader's pre-clear yield is wiped by its
## clear_level(), and a state the host holds for the table-loaded report survives.
##
## Before 2026-10-09 the host sent a late joiner's state on the client's receipt ACK, about
## two frames after the level data, which is the first case: every late joiner lost the
## table's tokens and avatars. The second case runs LateJoinerSync's real hold in the same
## process, with the transport replaced by direct calls: the report is table_loaded emitted
## on level_loading_completed (LevelFlow._on_level_loading_completed calls
## NetworkManager.report_table_loaded there), and the send is
## NetworkStateSync._on_game_state_received, the client's receive path.
##
## NetworkManager is set to HOSTING so the hold runs and the receive path skips its ACK RPC.
## The level is a 4 x 4 cell map document in a level folder under Paths.LEVELS_DIR (the GUT
## run's own test data root); it is removed after each test.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const FOLDER := "_late_joiner_state_gut"
const PEER := 7
const TOKEN_ID := "late_joiner_avatar"
const LOAD_TIMEOUT := 20.0

var _controller: LevelPlayController
var _events: Array = []


func before_each() -> void:
	_events.clear()
	DirAccess.make_dir_recursive_absolute(Paths.get_level_folder(FOLDER))
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 7)
	assert_eq(MapDocumentIO.write(doc, Paths.get_level_map_document_path(FOLDER)), OK)
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._players[PEER] = {"name": "Late", "role": NetworkManager.PlayerRole.PLAYER}
	GameState.clear_all_tokens()

	# Wired the way Root._enter_playing_state wires them.
	_controller = LevelPlayController.new()
	add_child_autofree(_controller)
	var game_map: GameMap = GAME_MAP_SCENE.instantiate()
	# DragAndDrop3D awaits the current scene's ready signal, and GUT's runner has no current
	# scene: a stand-in whose ready has already fired lets that wait sit harmlessly.
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(game_map)
	get_tree().current_scene = null
	stand_in.free()
	_controller.setup(game_map)
	game_map.setup(_controller)
	_controller.level_cleared.connect(func() -> void: _events.append("cleared"))
	_controller.level_loading_completed.connect(func() -> void: _events.append("completed"))


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._players.clear()
	GameState.clear_all_tokens()
	var folder := Paths.get_level_folder(FOLDER)
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder.trim_suffix("/"))


func _level() -> LevelData:
	var level := LevelData.new()
	level.level_folder = FOLDER
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	return level


## A host's full state with one avatar token in it, as GameState.get_full_state_dict()
## shapes it.
func _host_state() -> Dictionary:
	var token := TokenState.new()
	token.network_id = TOKEN_ID
	token.token_name = "Late Joiner"
	token.avatar_recipe = {"body": "human"}
	return {"tokens": {TOKEN_ID: token.to_dict()}, "permissions": {}}


## The client's receive path for the host's _rpc_receive_game_state.
func _deliver_state(_peer_id: int = PEER) -> void:
	_events.append("state")
	NetworkStateSync._on_game_state_received(_host_state())


func test_a_state_landing_inside_the_loader_yield_is_wiped() -> void:
	_controller.play_level(_level())
	# The old order: the receipt ACK's round trip, then the state, inside the yield.
	await wait_process_frames(1)
	_deliver_state()
	assert_eq(GameState.get_token_count(), 1, "the state landed")
	assert_true(await wait_for_signal(_controller.level_loading_completed, LOAD_TIMEOUT))
	assert_eq(_events, ["state", "cleared", "completed"])
	assert_eq(GameState.get_token_count(), 0, "the loader's clear_level() wiped it")


func test_a_state_held_for_the_table_loaded_report_survives() -> void:
	var report := func() -> void: NetworkManager.table_loaded.emit(PEER)
	_controller.level_loading_completed.connect(report)
	_controller.play_level(_level())
	var sent: bool = await LateJoinerSync.send_state_once_table_loaded(PEER, _deliver_state)
	assert_true(sent)
	assert_eq(_events, ["cleared", "completed", "state"], "the state goes after the clear")
	assert_eq(GameState.get_token_count(), 1, "the table's state survives the load")
	assert_not_null(GameState.get_token_state(TOKEN_ID))
