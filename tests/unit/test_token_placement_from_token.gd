extends GutTest

## Tests that TokenPlacement copies the full live-token state in both the static factory
## (from_board_token) and the instance sync used by the in-play Save Level path
## (TokenSpawner._sync_placement_from_token). The two used to be separate copies and the
## spawner's dropped is_alive and status_effects.


func _make_dead_token() -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	add_child_autofree(token)
	token.network_id = "placement_test_token"
	token.token_name = "Goblin"
	token.max_health = 12
	token.current_health = 12
	token.status_effects = ["poisoned"]
	body.position = Vector3(3, 0, -2)
	body.rotation.y = 1.5
	body.scale = Vector3(2, 2, 2)
	token.take_damage(-12)
	assert_false(token.is_alive, "Setup: token should be dead")
	return token


func test_sync_from_board_token_copies_is_alive_and_status_effects() -> void:
	var token := _make_dead_token()
	var placement := TokenPlacement.new()

	placement.sync_from_board_token(token)

	assert_false(placement.is_alive, "is_alive must be copied")
	assert_eq(placement.status_effects, ["poisoned"])
	assert_eq(placement.token_name, "Goblin")
	assert_eq(placement.current_health, 0)
	assert_eq(placement.max_health, 12)
	assert_eq(placement.position, Vector3(3, 0, -2))
	assert_almost_eq(placement.rotation_y, 1.5, 0.0001)
	assert_eq(placement.scale, Vector3(2, 2, 2))


func test_sync_from_board_token_does_not_touch_asset_ids() -> void:
	var token := _make_dead_token()
	var placement := TokenPlacement.new()
	placement.pack_id = "pokemon"
	placement.asset_id = "bulbasaur"
	placement.variant_id = "shiny"
	var original_id := placement.placement_id

	placement.sync_from_board_token(token)

	assert_eq(placement.pack_id, "pokemon")
	assert_eq(placement.asset_id, "bulbasaur")
	assert_eq(placement.variant_id, "shiny")
	assert_eq(placement.placement_id, original_id)


func test_spawner_sync_placement_matches_static_factory() -> void:
	var token := _make_dead_token()
	var spawner := TokenSpawner.new()
	var via_spawner := TokenPlacement.new()
	spawner._sync_placement_from_token(via_spawner, token)

	var via_factory := TokenPlacement.from_board_token(token, "p", "a", "v")

	assert_eq(via_spawner.is_alive, via_factory.is_alive)
	assert_eq(via_spawner.status_effects, via_factory.status_effects)
	assert_eq(via_spawner.current_health, via_factory.current_health)
	assert_eq(via_spawner.position, via_factory.position)
