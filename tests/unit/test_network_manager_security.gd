extends GutTest

## Regression tests for NetworkManager trust-boundary and rate-limiting fixes.
##
## NetworkManager is a live autoload (not a doubled instance -- GUT's stub()/double()
## only works on instances you construct yourself, see test_asset_manager_needs_download.gd
## for the established precedent on this constraint), so these tests drive it directly
## and restore its state in after_each(). is_host()-gated code paths are exercised by
## setting _connection_state directly rather than through a real Steam/multiplayer
## connection -- is_host() is a pure state-enum check (see network_manager.gd:132-133),
## not dependent on an actual peer.


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._players.clear()
	NetworkManager._current_level_dict.clear()
	NetworkManager._client_transform_throttle.clear()


func test_client_supplied_role_is_ignored_when_hosting() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	# Simulate a malicious/buggy client claiming GM in its player-info payload.
	NetworkManager._rpc_send_player_info({"name": "Evil", "role": NetworkManager.PlayerRole.GM})
	var stored: Dictionary = NetworkManager._players.values()[0]
	assert_eq(
		stored.get("role"),
		NetworkManager.PlayerRole.PLAYER,
		"Client-asserted role must never be trusted -- only the host assigns GM"
	)


func test_client_supplied_name_is_still_accepted_when_hosting() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._rpc_send_player_info(
		{"name": "Legit Name", "role": NetworkManager.PlayerRole.GM}
	)
	var stored: Dictionary = NetworkManager._players.values()[0]
	assert_eq(stored.get("name"), "Legit Name", "Display name is legitimately client-controlled")


func test_player_info_always_has_a_role_key() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	# A payload with no role field at all (or a garbage one) must still resolve to a
	# real role, never store whatever the client happened to send (or omit).
	NetworkManager._rpc_send_player_info({"name": "NoRoleField"})
	var stored: Dictionary = NetworkManager._players.values()[0]
	assert_has(stored, "role", "Stored player info must always include a resolved role key")
	assert_eq(stored.get("role"), NetworkManager.PlayerRole.PLAYER, "Default role must be PLAYER")


## NOTE: emit_count is wrapped in an Array, not a plain int -- GDScript lambdas capture
## local variables by value, so a lambda mutating a captured `int` directly would silently
## mutate its own copy. Arrays/Dictionaries are reference types, so `counts[0] += 1` inside
## the lambda is visible to the test function afterward.
func test_rate_limit_drops_rapid_repeat_transform_updates() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	var counts := [0]
	var counter := func(_sender_id, _network_id, _pos, _rot, _scl): counts[0] += 1
	NetworkManager.client_token_transform_received.connect(counter)

	NetworkManager._rpc_client_token_transform("rate_test_token", [1, 0, 0], [0, 0, 0], [1, 1, 1])
	NetworkManager._rpc_client_token_transform("rate_test_token", [2, 0, 0], [0, 0, 0], [1, 1, 1])

	NetworkManager.client_token_transform_received.disconnect(counter)
	assert_eq(
		counts[0],
		1,
		"Second update within CLIENT_TRANSFORM_RATE_LIMIT must be dropped, not relayed"
	)


func test_rate_limit_allows_update_after_interval_elapses() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	var counts := [0]
	var counter := func(_sender_id, _network_id, _pos, _rot, _scl): counts[0] += 1
	NetworkManager.client_token_transform_received.connect(counter)

	NetworkManager._rpc_client_token_transform("rate_test_token_2", [1, 0, 0], [0, 0, 0], [1, 1, 1])
	# Simulate time passing past CLIENT_TRANSFORM_RATE_LIMIT by directly backdating the
	# throttle entry, rather than an actual sleep (keeps the test fast and deterministic).
	NetworkManager._client_transform_throttle["rate_test_token_2"] = 0.0
	NetworkManager._rpc_client_token_transform("rate_test_token_2", [2, 0, 0], [0, 0, 0], [1, 1, 1])

	NetworkManager.client_token_transform_received.disconnect(counter)
	assert_eq(counts[0], 2, "Update after the rate-limit interval elapses must be relayed")


func test_rate_limit_tracks_tokens_independently() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	var counts := [0]
	var counter := func(_sender_id, _network_id, _pos, _rot, _scl): counts[0] += 1
	NetworkManager.client_token_transform_received.connect(counter)

	NetworkManager._rpc_client_token_transform("token_a", [1, 0, 0], [0, 0, 0], [1, 1, 1])
	NetworkManager._rpc_client_token_transform("token_b", [1, 0, 0], [0, 0, 0], [1, 1, 1])

	NetworkManager.client_token_transform_received.disconnect(counter)
	assert_eq(counts[0], 2, "Rate limit must be per-token, not global")


func test_transform_rpc_is_ignored_when_not_hosting() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	var counts := [0]
	var counter := func(_sender_id, _network_id, _pos, _rot, _scl): counts[0] += 1
	NetworkManager.client_token_transform_received.connect(counter)

	NetworkManager._rpc_client_token_transform("token_c", [1, 0, 0], [0, 0, 0], [1, 1, 1])

	NetworkManager.client_token_transform_received.disconnect(counter)
	assert_eq(counts[0], 0, "Only the host should ever process a client transform RPC")


func test_late_joiner_snapshot_reflects_live_visual_settings_edit() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	NetworkManager._current_level_dict = {
		"level_folder": "sectest_level", "light_intensity_scale": 1.0, "environment_preset": ""
	}

	NetworkManager._patch_current_level_dict(
		{"light_intensity_scale": 0.4, "environment_preset": "night"}
	)

	assert_eq(
		NetworkManager._current_level_dict["environment_preset"],
		"night",
		"A live visual-settings edit must update the snapshot late joiners receive"
	)


func test_patch_current_level_dict_is_noop_with_no_active_level() -> void:
	NetworkManager._current_level_dict.clear()
	NetworkManager._patch_current_level_dict({"environment_preset": "night"})
	assert_true(
		NetworkManager._current_level_dict.is_empty(),
		"Patching with no active level must not fabricate a level snapshot"
	)


func test_get_current_level_folder_reflects_active_level() -> void:
	NetworkManager._current_level_dict = {"level_folder": "sectest_dungeon"}
	assert_eq(NetworkManager.get_current_level_folder(), "sectest_dungeon")


func test_get_current_level_folder_empty_when_no_level_active() -> void:
	NetworkManager._current_level_dict.clear()
	assert_eq(NetworkManager.get_current_level_folder(), "")
