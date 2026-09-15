extends GutTest

## Regression tests for client-side network token tracking. RootNetworkHandler used to write
## controller.spawned_tokens[network_id] directly, which bypassed TokenSpawner's reverse
## index, so find_token_by_network_id() could not see tokens the host spawned mid-game.


func _make_token(network_id: String) -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	token.network_id = network_id
	token.set_meta("placement_id", network_id)
	add_child_autofree(token)
	return token


func test_track_network_token_is_found_by_network_id() -> void:
	var spawner := TokenSpawner.new()
	var token := _make_token("net_a")

	spawner.track_network_token(token)

	assert_eq(spawner.find_token_by_network_id("net_a"), token)
	assert_eq(spawner.get_spawned_tokens().get("net_a"), token)


func test_track_network_token_emits_token_added() -> void:
	var spawner := TokenSpawner.new()
	var token := _make_token("net_b")
	watch_signals(spawner)

	spawner.track_network_token(token)

	assert_signal_emitted_with_parameters(spawner, "token_added", [token])


func test_untrack_network_token_clears_both_maps() -> void:
	var spawner := TokenSpawner.new()
	var token := _make_token("net_c")
	spawner.track_network_token(token)

	spawner.untrack_network_token("net_c")

	assert_null(spawner.find_token_by_network_id("net_c"))
	assert_false(spawner.get_spawned_tokens().has("net_c"))


func test_untrack_unknown_network_id_is_a_noop() -> void:
	var spawner := TokenSpawner.new()
	spawner.untrack_network_token("never_tracked")
	assert_eq(spawner.get_token_count(), 0)


func test_level_play_controller_delegates_tracking() -> void:
	var controller := LevelPlayController.new()
	var token := _make_token("net_d")

	controller.track_network_token(token)
	assert_eq(controller.spawned_tokens.get("net_d"), token)
	assert_eq(controller._token_spawner.find_token_by_network_id("net_d"), token)

	controller.untrack_network_token("net_d")
	assert_false(controller.spawned_tokens.has("net_d"))
	controller.free()


func test_level_play_controller_forwards_find_token_by_network_id() -> void:
	var controller := LevelPlayController.new()
	var token := _make_token("net_e")

	controller.track_network_token(token)

	assert_eq(controller.find_token_by_network_id("net_e"), token)
	assert_null(controller.find_token_by_network_id("missing"))
	controller.free()
