extends GutTest

## A client builds the tokens a state brings on the shared TokenSpawnQueue, never all in the
## frame the state lands (RootNetworkHandler.queue_token_build), and a network id waiting there
## is built once however many states or adds name it meanwhile; the job builds from GameState
## as it is when the job runs.

const IDS: Array[String] = ["_netjoin_a", "_netjoin_b", "_netjoin_c"]


class FakeMap:
	extends Node
	var drag_and_drop_node: Node = null


var _controller: LevelPlayController
var _map: FakeMap


func before_each() -> void:
	_controller = LevelPlayController.new()
	add_child_autofree(_controller)
	_map = FakeMap.new()
	_map.drag_and_drop_node = Node3D.new()
	_map.add_child(_map.drag_and_drop_node)
	add_child_autofree(_map)
	for id in IDS:
		GameState.set_token_state(id, _avatar_state(id, Vector3.ZERO))


func after_each() -> void:
	await _drain()
	for id in IDS:
		GameState.remove_token_state(id)


func _avatar_state(id: String, at: Vector3) -> TokenState:
	var state := TokenState.new()
	state.network_id = id
	state.token_name = id
	state.avatar_recipe = {"format": 1}
	state.position = at
	return state


func _drain() -> void:
	for i in 600:
		if TokenSpawnQueue.shared().pending() == 0:
			return
		await get_tree().process_frame


func _board_ids() -> Array[String]:
	var ids: Array[String] = []
	for child in _map.drag_and_drop_node.get_children():
		if child is BoardToken:
			ids.append((child as BoardToken).network_id)
	ids.sort()
	return ids


func test_a_state_queues_its_tokens_instead_of_building_them_at_once() -> void:
	RootNetworkHandler.apply_tokens_to_board(_controller, _map, IDS)
	assert_eq(_board_ids().size(), 0, "nothing built in the frame the state landed")
	for id in IDS:
		assert_true(RootNetworkHandler.is_build_queued(id), id)
	await _drain()
	assert_eq(_board_ids(), IDS, "every token built once the queue ran")
	for id in IDS:
		assert_false(RootNetworkHandler.is_build_queued(id), id)


func test_a_second_state_for_a_queued_token_builds_no_duplicate_and_the_newest_state_wins() -> void:
	var pending_before := TokenSpawnQueue.shared().pending()
	RootNetworkHandler.apply_tokens_to_board(_controller, _map, IDS)
	RootNetworkHandler.apply_tokens_to_board(_controller, _map, IDS)
	RootNetworkHandler.on_token_state_received(
		_controller, _map, IDS[0], _avatar_state(IDS[0], Vector3(3.0, 0.0, 4.0)).to_dict()
	)
	assert_eq(TokenSpawnQueue.shared().pending() - pending_before, IDS.size(), "one job per id")
	await _drain()
	assert_eq(_board_ids(), IDS, "each token once")
	var token := _controller.find_token_by_network_id(IDS[0])
	assert_not_null(token)
	if token:
		var built := TokenState.from_board_token(token)
		assert_almost_eq(built.position.x, 3.0, 0.01, "built from the newest state")


func test_a_token_removed_while_queued_is_not_built() -> void:
	RootNetworkHandler.apply_tokens_to_board(_controller, _map, IDS)
	GameState.remove_token_state(IDS[1])
	await _drain()
	assert_eq(_board_ids(), [IDS[0], IDS[2]] as Array[String])
