extends GutTest

## NetworkStateSync's throttled (queued) transform path must keep GameState in sync
## exactly like the immediate path does. It is unreachable at today's emission rate,
## so this pins it before anyone lowers NETWORK_TRANSFORM_UPDATE_INTERVAL.

const TOKEN_ID := "queue_sync_token"


func before_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	GameState.remove_token_state(TOKEN_ID)
	NetworkStateSync._pending_transforms.clear()


func after_each() -> void:
	GameState.remove_token_state(TOKEN_ID)
	NetworkStateSync._pending_transforms.clear()


func _make_token() -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	add_child_autofree(token)
	token.network_id = TOKEN_ID
	return token


func test_queued_transform_updates_game_state() -> void:
	var token := _make_token()
	GameState.register_token_from_board_token(token)
	token.rigid_body.global_position = Vector3(3, 0, -4)

	NetworkStateSync._queue_transform_update(token)

	assert_eq(GameState.get_token_state(TOKEN_ID).position, Vector3(3, 0, -4))
	assert_true(NetworkStateSync._pending_transforms.has(TOKEN_ID), "still queued for the batch")
