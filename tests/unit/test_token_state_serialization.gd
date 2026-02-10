extends GutTest

## Unit tests for TokenState serialization round-trips.


func test_to_dict_from_dict_round_trip() -> void:
	var original = TokenState.new()
	original.network_id = "net_123"
	original.pack_id = "pokemon"
	original.asset_id = "6"
	original.variant_id = "shiny"
	original.position = Vector3(10.0, 0.5, -3.0)
	original.rotation = Vector3(0.0, 1.57, 0.0)
	original.scale = Vector3(1.5, 1.5, 1.5)
	original.token_name = "Charizard"
	original.is_player_controlled = true
	original.character_id = "char_abc"
	original.max_health = 300
	original.current_health = 250
	original.is_alive = true
	original.is_visible_to_players = false
	original.is_hidden_from_gm = true
	original.status_effects = ["burned"]

	var dict = original.to_dict()
	var restored = TokenState.from_dict(dict)

	assert_eq(restored.network_id, "net_123")
	assert_eq(restored.pack_id, "pokemon")
	assert_eq(restored.asset_id, "6")
	assert_eq(restored.variant_id, "shiny")
	assert_almost_eq(restored.position.x, 10.0, 0.001)
	assert_almost_eq(restored.position.y, 0.5, 0.001)
	assert_almost_eq(restored.position.z, -3.0, 0.001)
	assert_almost_eq(restored.rotation.y, 1.57, 0.001)
	assert_almost_eq(restored.scale.x, 1.5, 0.001)
	assert_eq(restored.token_name, "Charizard")
	assert_true(restored.is_player_controlled)
	assert_eq(restored.character_id, "char_abc")
	assert_eq(restored.max_health, 300)
	assert_eq(restored.current_health, 250)
	assert_true(restored.is_alive)
	assert_false(restored.is_visible_to_players)
	assert_true(restored.is_hidden_from_gm)
	assert_eq(restored.status_effects.size(), 1)
	assert_eq(restored.status_effects[0], "burned")


func test_from_dict_with_defaults() -> void:
	var restored = TokenState.from_dict({})

	assert_eq(restored.network_id, "")
	assert_eq(restored.pack_id, "")
	assert_eq(restored.variant_id, "default")
	assert_eq(restored.position, Vector3.ZERO)
	assert_eq(restored.rotation, Vector3.ZERO)
	assert_eq(restored.scale, Vector3.ONE)
	assert_eq(restored.token_name, "Token")
	assert_false(restored.is_player_controlled)
	assert_eq(restored.max_health, 100)
	assert_eq(restored.current_health, 100)
	assert_true(restored.is_alive)
	assert_true(restored.is_visible_to_players)
	assert_false(restored.is_hidden_from_gm)


func test_duplicate_state() -> void:
	var original = TokenState.new()
	original.network_id = "dup_test"
	original.token_name = "Test"
	original.position = Vector3(5.0, 5.0, 5.0)

	var copy = original.duplicate_state()

	assert_eq(copy.network_id, "dup_test")
	assert_eq(copy.token_name, "Test")
	assert_eq(copy.position, Vector3(5.0, 5.0, 5.0))

	# Modifying copy should not affect original
	copy.token_name = "Modified"
	assert_eq(original.token_name, "Test")


func test_should_sync_to_client_gm_sees_all() -> void:
	var state = TokenState.new()
	state.is_visible_to_players = false
	state.is_hidden_from_gm = false
	assert_true(state.should_sync_to_client("", true))


func test_should_sync_to_client_gm_hidden() -> void:
	var state = TokenState.new()
	state.is_hidden_from_gm = true
	assert_false(state.should_sync_to_client("", true))


func test_should_sync_to_client_player_visible() -> void:
	var state = TokenState.new()
	state.is_visible_to_players = true
	assert_true(state.should_sync_to_client("player1", false))


func test_should_sync_to_client_player_hidden() -> void:
	var state = TokenState.new()
	state.is_visible_to_players = false
	assert_false(state.should_sync_to_client("player1", false))
