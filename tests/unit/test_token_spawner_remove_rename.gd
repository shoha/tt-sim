extends GutTest

## TokenSpawner is the single owner of token storage: remove_token() and rename_token()
## must update storage, the level placement list, and GameState together.

const TOKEN_ID := "remove_rename_token"


func before_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	GameState.remove_token_state(TOKEN_ID)


func after_each() -> void:
	GameState.remove_token_state(TOKEN_ID)


func _make_level_with_token() -> Array:
	var level := LevelData.new()
	var placement := TokenPlacement.new()
	placement.placement_id = TOKEN_ID
	placement.pack_id = "p"
	placement.asset_id = "a"
	placement.token_name = "Goblin"
	level.add_token_placement(placement)

	var token := BoardToken.new()
	token._factory_created = true
	token.network_id = TOKEN_ID
	token.set_meta("placement_id", TOKEN_ID)
	token.token_name = "Goblin"
	token.pack_id = "p"
	token.asset_id = "a"
	add_child_autofree(token)

	var spawner := TokenSpawner.new()
	spawner.setup(null, func() -> LevelData: return level)
	# NOTE: adapted from the plan's _track_token(token, placement) call, which
	# crashes with a null GameMap (_track_token unconditionally reads
	# _game_map.multiplayer via _get_multiplayer_api()). This instead populates
	# storage the way track_network_token() does, plus the two side effects
	# _track_token() would otherwise have performed.
	spawner.track_network_token(token)
	GameState.register_token_from_board_token(token)
	spawner._connect_token_state_signals(token)
	return [spawner, token, level]


func test_remove_token_untracks_and_removes_placement_and_state() -> void:
	var parts := _make_level_with_token()
	var spawner: TokenSpawner = parts[0]
	var token: BoardToken = parts[1]
	var level: LevelData = parts[2]
	assert_not_null(GameState.get_token_state(TOKEN_ID), "Setup: registered")

	assert_true(spawner.remove_token(token))

	assert_null(spawner.find_token_by_network_id(TOKEN_ID))
	assert_eq(spawner.get_token_count(), 0)
	assert_eq(level.token_placements.size(), 0)
	assert_null(GameState.get_token_state(TOKEN_ID))


func test_rename_token_updates_token_placement_and_state() -> void:
	var parts := _make_level_with_token()
	var spawner: TokenSpawner = parts[0]
	var token: BoardToken = parts[1]
	var level: LevelData = parts[2]

	spawner.rename_token(token, "  Hobgoblin ")

	assert_eq(token.token_name, "Hobgoblin")
	assert_eq(String(token.name), "Hobgoblin", "The scene-tree node name follows the display name")
	assert_eq(level.token_placements[0].token_name, "Hobgoblin")
	assert_eq(GameState.get_token_state(TOKEN_ID).token_name, "Hobgoblin")


func test_rename_token_ignores_empty_names() -> void:
	var parts := _make_level_with_token()
	var spawner: TokenSpawner = parts[0]
	var token: BoardToken = parts[1]
	spawner.rename_token(token, "   ")
	assert_eq(token.token_name, "Goblin")


func test_undo_tracking_restores_the_level_placement() -> void:
	var level := LevelData.new()
	var spawner := TokenSpawner.new()
	spawner.setup(null, func() -> LevelData: return level)
	var token := BoardToken.new()
	token._factory_created = true
	token.network_id = TOKEN_ID
	token.token_name = "Goblin"
	add_child_autofree(token)
	var state := TokenState.from_board_token(token)

	spawner._track_token_from_undo(token, state, "p", "a", "default")

	assert_eq(level.token_placements.size(), 1)
	assert_eq(level.token_placements[0].placement_id, TOKEN_ID)
	assert_eq(level.token_placements[0].pack_id, "p")
