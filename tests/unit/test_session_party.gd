extends GutTest

## The session party (NetworkManager.session.party, SessionParty): CONTROL grants kept by
## session id through a leave and a rejoin, the members a table hands on, where they land,
## and a player's avatar leaving the map's placements.
##
## GameState and NetworkManager are the live autoloads, so the tests set host state directly
## and restore it (as test_session_channel.gd does). GUT runs on an offline peer, so nothing
## is sent; the ENet scenario tests/net/enet_session_room.gd covers the party travelling
## between real peers.

const CONTROL := TokenPermissions.Permission.CONTROL
const HERO := "hero"
const EXTRA := "extra"
const ROCK := "rock"

var _session: SessionChannel
var _party: SessionParty
var _saved_controller: LevelPlayController


func before_each() -> void:
	_session = NetworkManager.session
	_party = _session.party
	_saved_controller = _party._controller
	_session.reset()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	GameState.clear_all_tokens()


func after_each() -> void:
	GameState.clear_all_tokens()
	_party._controller = _saved_controller
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._players.clear()
	_session.reset()


func _register(network_id: String, avatar := true) -> TokenState:
	var state := TokenState.new()
	state.network_id = network_id
	state.token_name = network_id
	if avatar:
		state.avatar_recipe = {"format": 1}
	else:
		state.pack_id = "pack"
		state.asset_id = network_id
	GameState.register_token(state)
	return state


## A player joining on `peer_id` that reports `key` (the ENet stand-in for a Steam id);
## returns its session id.
func _join(peer_id: int, key: String) -> String:
	NetworkManager._players[peer_id] = {"name": key, "role": NetworkManager.PlayerRole.PLAYER}
	_session.admit_peer(peer_id, {SessionChannel.SESSION_KEY: key})
	return _session.session_id_of(peer_id)


func _leave(peer_id: int) -> void:
	NetworkManager._players.erase(peer_id)
	_session._on_player_left(peer_id, {})
	# What TokenPermissionHandler does at the table.
	GameState.clear_permissions_for_peer(peer_id)


func test_a_grant_is_kept_by_session_id_through_a_leave() -> void:
	var ana := _join(7, "ana")
	assert_eq(ana, SessionChannel.TEST_ID_PREFIX + "ana")
	_register(HERO)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	assert_eq(_party.get_grants(), {ana: [HERO]})
	_leave(7)
	assert_false(GameState.has_token_permission(HERO, 7, CONTROL), "the table forgets the peer")
	assert_eq(_party.get_grants(), {ana: [HERO]}, "the session keeps the player's grant")


func test_a_player_who_rejoins_controls_its_avatar_again() -> void:
	var ana := _join(7, "ana")
	_register(HERO)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	_leave(7)
	assert_eq(_join(9, "ana"), ana, "a new peer id, the same session id")
	assert_eq(_session.peer_for(ana), 9)
	assert_true(GameState.has_token_permission(HERO, 9, CONTROL))
	assert_eq(_session.get_players().size(), 1, "the rejoin reuses the entry")


func test_a_key_a_connected_player_holds_is_not_taken() -> void:
	_join(7, "ana")
	assert_eq(_join(8, "ana"), SessionChannel.TEST_ID_PREFIX + "8")
	assert_eq(_session.peer_for(SessionChannel.TEST_ID_PREFIX + "ana"), 7)


func test_a_revoke_or_a_removed_token_drops_the_grant() -> void:
	var ana := _join(7, "ana")
	_register(HERO)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	GameState.revoke_token_permission(HERO, 7, CONTROL)
	assert_eq(_party.get_grants(), {})
	GameState.grant_token_permission(HERO, 7, CONTROL)
	GameState.remove_token(HERO)
	assert_eq(_party.get_grants(), {})
	assert_eq(_party.owners_of(HERO), [] as Array[String])
	assert_ne(ana, "")


func test_revoke_all_takes_control_from_players_who_are_away() -> void:
	var ana := _join(7, "ana")
	_register(HERO)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	_leave(7)
	_party.revoke_all(HERO)
	assert_eq(_party.get_grants(), {})
	assert_eq(_join(9, "ana"), ana)
	assert_false(GameState.has_token_permission(HERO, 9, CONTROL))


func test_the_party_is_every_avatar_a_player_controls() -> void:
	var states := {
		HERO: _register(HERO),
		EXTRA: _register(EXTRA),
		ROCK: _register(ROCK, false),
	}
	var grants := {"enet-bo": [HERO], "enet-ana": [HERO, ROCK]}
	var members := SessionParty.members_of(states, grants)
	assert_eq(members.size(), 1, "an avatar nobody controls and a prop stay with the map")
	assert_eq(members[0].state.network_id, HERO)
	assert_eq(members[0].owners, ["enet-ana", "enet-bo"])


func test_take_keeps_the_owners_when_the_table_is_cleared() -> void:
	var ana := _join(7, "ana")
	_register(HERO)
	_register(EXTRA)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	assert_eq(_party.take(), 1)
	GameState.clear_all_tokens()
	assert_eq(_party.get_grants(), {}, "the table's tokens are gone")
	var members := _party.get_members()
	assert_eq(members.size(), 1)
	assert_eq(members[0].state.network_id, HERO)
	assert_false(members[0].state.get("avatar_recipe", {}).is_empty(), "its recipe travels")
	assert_eq(members[0].owners, [ana])


func test_a_second_take_keeps_members_not_yet_set_out() -> void:
	_join(7, "ana")
	_register(HERO)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	_party.take()
	GameState.clear_all_tokens()
	assert_eq(_party.take(), 1, "a map change while the last one was loading")


func test_only_the_host_takes_a_party() -> void:
	_join(7, "ana")
	_register(HERO)
	GameState.grant_token_permission(HERO, 7, CONTROL)
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	assert_eq(_party.take(), 0)
	assert_true(_party.is_empty())


func test_members_land_on_a_block_around_the_centre() -> void:
	var centre := Vector3(10, 2, -4)
	assert_eq(SessionParty.landing_spots(centre, 0), [] as Array[Vector3])
	assert_eq(SessionParty.landing_spots(centre, 1), [centre] as Array[Vector3])
	var spots := SessionParty.landing_spots(centre, 4, 1.0)
	assert_eq(spots.size(), 4)
	var sum := Vector3.ZERO
	for spot in spots:
		sum += spot
		assert_eq(spot.y, centre.y)
	assert_almost_eq(sum / 4.0, centre, Vector3.ONE * 0.001, "centred")
	assert_almost_eq(spots[0].distance_to(spots[1]), 1.0, 0.001, "one spacing apart")
	assert_eq(SessionParty.landing_spots(centre, 5).size(), 5)


func test_a_spawn_point_comes_before_the_camera() -> void:
	var level := LevelData.new()
	assert_eq(SessionParty.landing_point(level, null), Vector3.ZERO, "no spawn point, no camera")
	level.has_spawn_point = true
	level.spawn_point = Vector3(3, 1, 5)
	assert_eq(SessionParty.landing_point(level, null), Vector3(3, 1, 5))


func test_a_spawn_point_round_trips_and_junk_is_ignored() -> void:
	var level := LevelData.new()
	assert_false(level.to_dict().has("spawn_point"), "written only when set")
	level.has_spawn_point = true
	level.spawn_point = Vector3(3, 1.5, -5)
	var copy := LevelData.from_dict(level.to_dict())
	assert_true(copy.has_spawn_point)
	assert_eq(copy.spawn_point, Vector3(3, 1.5, -5))
	assert_false(LevelData.from_dict({}).has_spawn_point)
	assert_null(LevelData.spawn_point_from({"x": "1", "y": 0, "z": 0}))
	assert_null(LevelData.spawn_point_from({"x": NAN, "y": 0, "z": 0}))
	assert_null(LevelData.spawn_point_from([1, 2, 3]))
	assert_eq(LevelData.spawn_point_from({"x": 1, "y": 2, "z": 3}), Vector3(1, 2, 3))


func test_a_players_avatar_leaves_the_maps_placements_and_returns_when_freed() -> void:
	var level := LevelData.new()
	var placement := TokenPlacement.new()
	placement.token_name = HERO
	placement.avatar_recipe = {"format": 1}
	level.add_token_placement(placement)
	var controller: LevelPlayController = autofree(LevelPlayController.new())
	controller._token_spawner.setup(null, func() -> LevelData: return level)
	var token := BoardToken.new()
	token._factory_created = true
	token.network_id = HERO
	token.token_name = HERO
	token.avatar_recipe = {"format": 1}
	token.set_meta("placement_id", placement.placement_id)
	add_child_autofree(token)
	controller.track_network_token(token)
	_party._controller = controller
	_join(7, "ana")
	_register(HERO)

	GameState.grant_token_permission(HERO, 7, CONTROL)
	assert_true(level.token_placements.is_empty(), "a player's avatar is not saved with the map")
	GameState.revoke_token_permission(HERO, 7, CONTROL)
	assert_eq(level.token_placements.size(), 1, "nobody's avatar is the map's again")
	assert_eq(level.token_placements[0].placement_id, placement.placement_id)
	assert_eq(level.token_placements[0].token_name, HERO)
