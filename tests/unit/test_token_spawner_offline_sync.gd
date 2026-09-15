extends GutTest

## Regression test: in single-player (not networked) NetworkManager.is_host() is false, so
## TokenSpawner._on_token_transform_changed used to return without telling GameState about
## the move. GameState.has_authority() is the right gate (host OR offline).

const TOKEN_ID := "offline_sync_token"


func before_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	GameState.remove_token_state(TOKEN_ID)


func after_each() -> void:
	GameState.remove_token_state(TOKEN_ID)


func _make_token() -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	add_child_autofree(token)
	token.network_id = TOKEN_ID
	return token


func test_offline_transform_change_updates_game_state_position() -> void:
	assert_false(NetworkManager.is_host(), "Setup: not host offline")
	assert_true(GameState.has_authority(), "Setup: offline play holds authority")
	var token := _make_token()
	GameState.register_token_from_board_token(token)
	assert_eq(GameState.get_token_state(TOKEN_ID).position, Vector3.ZERO, "Setup")

	token.rigid_body.global_position = Vector3(4, 0, -6)
	var spawner := TokenSpawner.new()
	spawner._on_token_transform_changed(token)

	assert_eq(
		GameState.get_token_state(TOKEN_ID).position,
		Vector3(4, 0, -6),
		"Offline moves must be reflected in GameState"
	)


func test_offline_transform_change_registers_unknown_token() -> void:
	var token := _make_token()
	token.rigid_body.global_position = Vector3(1, 0, 1)
	var spawner := TokenSpawner.new()

	spawner._on_token_transform_changed(token)

	assert_not_null(GameState.get_token_state(TOKEN_ID))
	assert_eq(GameState.get_token_state(TOKEN_ID).position, Vector3(1, 0, 1))
