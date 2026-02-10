extends GutTest

## Unit tests for TokenPlacement serialization round-trips.


func test_to_dict_from_dict_round_trip() -> void:
	var original = TokenPlacement.new()
	original.placement_id = "test_id_123"
	original.pack_id = "pokemon"
	original.asset_id = "25"
	original.variant_id = "shiny"
	original.position = Vector3(1.0, 2.0, 3.0)
	original.rotation_y = 1.57
	original.scale = Vector3(2.0, 2.0, 2.0)
	original.token_name = "Pikachu"
	original.is_player_controlled = true
	original.max_health = 200
	original.current_health = 150
	original.is_visible_to_players = false
	original.status_effects = ["poisoned", "confused"]
	original.is_alive = true

	var dict = original.to_dict()
	var restored = TokenPlacement.from_dict(dict)

	assert_eq(restored.placement_id, "test_id_123")
	assert_eq(restored.pack_id, "pokemon")
	assert_eq(restored.asset_id, "25")
	assert_eq(restored.variant_id, "shiny")
	assert_almost_eq(restored.position.x, 1.0, 0.001)
	assert_almost_eq(restored.position.y, 2.0, 0.001)
	assert_almost_eq(restored.position.z, 3.0, 0.001)
	assert_almost_eq(restored.rotation_y, 1.57, 0.001)
	assert_almost_eq(restored.scale.x, 2.0, 0.001)
	assert_eq(restored.token_name, "Pikachu")
	assert_true(restored.is_player_controlled)
	assert_eq(restored.max_health, 200)
	assert_eq(restored.current_health, 150)
	assert_false(restored.is_visible_to_players)
	assert_eq(restored.status_effects.size(), 2)
	assert_eq(restored.status_effects[0], "poisoned")
	assert_eq(restored.status_effects[1], "confused")
	assert_true(restored.is_alive)


func test_from_dict_with_defaults() -> void:
	# Minimal dictionary — everything should get defaults
	var restored = TokenPlacement.from_dict({})

	assert_eq(restored.pack_id, "")
	assert_eq(restored.asset_id, "")
	assert_eq(restored.variant_id, "default")
	assert_eq(restored.position, Vector3.ZERO)
	assert_almost_eq(restored.rotation_y, 0.0, 0.001)
	assert_eq(restored.scale, Vector3.ONE)
	assert_eq(restored.token_name, "")
	assert_false(restored.is_player_controlled)
	assert_eq(restored.max_health, 100)
	assert_eq(restored.current_health, 100)
	assert_true(restored.is_visible_to_players)
	assert_true(restored.is_alive)


func test_get_display_name_with_token_name() -> void:
	var placement = TokenPlacement.new()
	placement.token_name = "My Token"
	placement.asset_id = "25"
	assert_eq(placement.get_display_name(), "My Token")


func test_get_display_name_fallback_to_asset_id() -> void:
	var placement = TokenPlacement.new()
	placement.token_name = ""
	placement.asset_id = "25"
	assert_eq(placement.get_display_name(), "25")


func test_get_display_name_unknown() -> void:
	var placement = TokenPlacement.new()
	placement.token_name = ""
	placement.asset_id = ""
	assert_eq(placement.get_display_name(), "Unknown Token")
