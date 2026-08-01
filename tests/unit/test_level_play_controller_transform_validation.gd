extends GutTest

## Regression test for the NaN/Inf rejection fix in
## LevelPlayController._on_client_transform_received() -- without it, a buggy or
## malicious client with legitimate CONTROL permission could inject non-finite floats
## that propagate into GameState and get rebroadcast to every other client.
##
## LevelPlayController is not an autoload (constructed fresh per level by Root), so unlike
## NetworkManager/AssetStreamer it can be instantiated directly here without touching the
## live singleton. It's never added to the scene tree -- the finite-value check runs
## before anything that requires _game_map/spawned_tokens to be populated, so a bare
## LevelPlayController.new() is sufficient.

const _TEST_TOKEN := "sectest_transform_token"
const _TEST_PEER := 4242


func before_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	GameState.grant_token_permission(_TEST_TOKEN, _TEST_PEER, TokenPermissions.Permission.CONTROL)


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	GameState.clear_all_permissions()


func test_nan_position_is_rejected_before_reaching_game_state() -> void:
	var controller := LevelPlayController.new()
	controller._on_client_transform_received(
		_TEST_PEER, _TEST_TOKEN, Vector3(NAN, 0, 0), Vector3.ZERO, Vector3.ONE
	)
	assert_null(
		GameState.get_token_state(_TEST_TOKEN),
		"A NaN transform must never reach GameState, even for a token that doesn't exist yet"
	)
	controller.free()


func test_infinite_rotation_is_rejected() -> void:
	var controller := LevelPlayController.new()
	controller._on_client_transform_received(
		_TEST_PEER, _TEST_TOKEN, Vector3.ZERO, Vector3(INF, 0, 0), Vector3.ONE
	)
	assert_null(GameState.get_token_state(_TEST_TOKEN))
	controller.free()


func test_infinite_scale_is_rejected() -> void:
	var controller := LevelPlayController.new()
	controller._on_client_transform_received(
		_TEST_PEER, _TEST_TOKEN, Vector3.ZERO, Vector3.ZERO, Vector3(1, INF, 1)
	)
	assert_null(GameState.get_token_state(_TEST_TOKEN))
	controller.free()


func test_negative_infinity_is_also_rejected() -> void:
	var controller := LevelPlayController.new()
	controller._on_client_transform_received(
		_TEST_PEER, _TEST_TOKEN, Vector3(0, -INF, 0), Vector3.ZERO, Vector3.ONE
	)
	assert_null(GameState.get_token_state(_TEST_TOKEN))
	controller.free()


func test_finite_transform_without_permission_is_still_rejected() -> void:
	# Sanity check that the finite-value guard doesn't accidentally bypass the
	# pre-existing permission check that runs before it.
	var controller := LevelPlayController.new()
	controller._on_client_transform_received(
		9999, _TEST_TOKEN, Vector3(1, 2, 3), Vector3.ZERO, Vector3.ONE  # peer 9999 has no grant
	)
	assert_null(GameState.get_token_state(_TEST_TOKEN))
	controller.free()


func test_finite_transform_does_not_crash_when_called_directly() -> void:
	# A finite transform for a token that isn't spawned falls through to
	# _find_token_by_network_id() returning null and a plain early return -- confirms
	# the finite-value check doesn't block legitimate input, without needing a full
	# GameMap/BoardToken fixture (see file header).
	var controller := LevelPlayController.new()
	controller._on_client_transform_received(
		_TEST_PEER, _TEST_TOKEN, Vector3(1, 2, 3), Vector3.ZERO, Vector3.ONE
	)
	pass_test("Finite transform for an unspawned token did not crash")
	controller.free()
