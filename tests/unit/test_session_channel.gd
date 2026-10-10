extends GutTest

## The session channel (NetworkManager.session, SessionChannel): where a joiner lands, the
## shelf and table pointer a level broadcast moves, the room that clears the late-joiner
## snapshot, players by session id, and the summary clients keep.
##
## NetworkManager is the live autoload (see test_network_manager_security.gd), so the tests
## set its state directly and restore it. GUT runs on an offline multiplayer peer: broadcasts
## reach nobody, and admit_peer() sends a joiner nothing because no such peer is connected,
## which leaves its bookkeeping and the phase it returns to check. The ENet scenario
## tests/net/enet_session_room.gd covers the RPCs between real peers.

const MAP_A := "res://assets/models/maps/oakslabpainted.glb"
const HASH := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var _session: SessionChannel


func before_each() -> void:
	_session = NetworkManager.session
	_session.reset()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager._players.clear()
	NetworkManager.clear_level_data()
	_session.reset()


func _level_dict(folder: String, map_hash := "") -> Dictionary:
	var level := {"level_name": folder, "level_folder": folder, "map_path": MAP_A}
	if map_hash != "":
		level[MapFileHash.HASHES_KEY] = {"map": map_hash}
	return level


func test_a_joiner_lands_in_the_room_while_it_is_open() -> void:
	assert_eq(SessionChannel.join_phase(true, ""), &"room")
	assert_eq(SessionChannel.join_phase(false, "camp"), &"table")
	assert_eq(SessionChannel.join_phase(false, ""), &"", "between close() and the broadcast")


func test_session_ids_are_steam_ids_or_a_test_id() -> void:
	assert_eq(SessionChannel.session_id(76561198000000001, 3), "76561198000000001")
	assert_eq(SessionChannel.session_id(0, 3), SessionChannel.TEST_ID_PREFIX + "3")
	assert_eq(
		_session.session_id_for_peer(4),
		SessionChannel.TEST_ID_PREFIX + "4",
		"a transport without Steam ids gets the test id"
	)


func test_without_steam_a_reported_key_is_the_session_id() -> void:
	assert_eq(SessionChannel.session_id(0, 3, "ana"), SessionChannel.TEST_ID_PREFIX + "ana")
	assert_eq(SessionChannel.session_id(76561198000000001, 3, "ana"), "76561198000000001")
	assert_eq(SessionChannel.clean_key("Ana-2_b"), "Ana-2_b")
	assert_eq(SessionChannel.clean_key(""), "")
	assert_eq(SessionChannel.clean_key("a b"), "", "only letters, digits, - and _")
	assert_eq(SessionChannel.clean_key("x".repeat(SessionChannel.MAX_SESSION_KEY + 1)), "")
	assert_eq(SessionChannel.clean_key(5), "")


func test_a_map_ref_is_keyed_by_its_folder_else_its_map_path() -> void:
	var ref := SessionChannel.map_ref(_level_dict("camp", HASH))
	assert_eq(ref, {"folder": "camp", "map_path": "", "hashes": {"map": HASH}, "name": "camp"})
	assert_eq(SessionChannel.ref_key(ref), "camp")
	var shipped := SessionChannel.map_ref({"map_path": MAP_A, "map_hashes": {"map": "bogus"}})
	assert_eq(SessionChannel.ref_key(shipped), MAP_A, "a level without a folder")
	assert_eq(shipped.hashes, {}, "hashes are sanitized")


func test_hosting_begins_a_session_in_the_room() -> void:
	var saved_name := NetworkManager.get_player_name()
	NetworkManager.set_player_name("Gm")
	_session._on_connection_state_changed(
		NetworkManager.ConnectionState.CONNECTING, NetworkManager.ConnectionState.HOSTING
	)
	NetworkManager.set_player_name(saved_name)
	assert_true(_session.is_open())
	assert_eq(_session.get_table(), "")
	var host_id := SessionChannel.TEST_ID_PREFIX + "1"
	assert_eq(_session.get_players(), {host_id: {"name": "Gm", "peer_id": 1}})


func test_a_level_broadcast_shelves_the_map_and_points_the_table_at_it() -> void:
	_session.open()
	_session.close()
	NetworkManager.broadcast_level_data(_level_dict("camp"))
	assert_false(_session.is_open())
	assert_eq(_session.get_table(), "camp")
	assert_eq(_session.get_shelf().size(), 1)

	# A map change in play moves the pointer and adds to the shelf, oldest first.
	NetworkManager.broadcast_level_data(_level_dict("ruins"))
	assert_eq(_session.get_table(), "ruins")
	var keys := _session.get_shelf().map(func(r: Dictionary) -> String: return r.folder)
	assert_eq(keys, ["camp", "ruins"])


func test_setting_a_shelved_map_out_again_refreshes_its_hashes() -> void:
	_session.note_table_out(_level_dict("camp"))
	_session.note_table_out(_level_dict("camp", HASH))
	assert_eq(_session.get_shelf().size(), 1)
	assert_eq(_session.get_shelf()[0].hashes, {"map": HASH})


func test_opening_the_room_takes_the_table_away() -> void:
	NetworkManager.broadcast_level_data(_level_dict("camp"))
	assert_true(NetworkManager.is_game_in_progress())
	_session.open()
	assert_true(_session.is_open())
	assert_eq(_session.get_table(), "")
	assert_eq(_session.get_shelf().size(), 1, "the shelf outlives the table")
	assert_eq(NetworkManager.get_current_level_folder(), "", "nothing is served in the room")
	assert_false(NetworkManager.is_game_in_progress(), "nobody is synced into a table")


func test_a_joiner_is_recorded_and_sent_to_the_sessions_phase() -> void:
	NetworkManager._players[7] = {"name": "Ana", "role": NetworkManager.PlayerRole.PLAYER}
	_session.open()
	assert_eq(_session.admit_peer(7), &"room")
	var id := SessionChannel.TEST_ID_PREFIX + "7"
	assert_eq(_session.get_players()[id], {"name": "Ana", "peer_id": 7})
	assert_eq(_session.session_id_of(7), id)
	assert_eq(_session.peer_for(id), 7)

	_session.close()
	_session.note_table_out(_level_dict("camp"))
	NetworkManager._players[8] = {"name": "Bo", "role": NetworkManager.PlayerRole.PLAYER}
	assert_eq(_session.admit_peer(8), &"table")


func test_a_player_who_leaves_keeps_an_entry_with_no_peer() -> void:
	NetworkManager._players[7] = {"name": "Ana", "role": NetworkManager.PlayerRole.PLAYER}
	_session.admit_peer(7)
	_session._on_player_left(7, {})
	var id := SessionChannel.TEST_ID_PREFIX + "7"
	assert_eq(_session.peer_for(id), 0)
	assert_eq(_session.session_id_of(7), "")
	assert_eq(_session.get_players()[id].name, "Ana")


func test_a_new_peers_player_info_admits_it() -> void:
	_session.open()
	var info := {"name": "Cy", VersionGate.PLAYER_INFO_KEY: UpdateVersion.get_current()}
	NetworkManager._rpc_send_player_info(info)
	# Outside a real RPC the sender reads as peer 0.
	assert_has(_session.get_players(), SessionChannel.TEST_ID_PREFIX + "0")


func test_only_the_host_changes_the_session() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	_session.open()
	_session.note_table_out(_level_dict("camp"))
	assert_eq(_session.admit_peer(7), &"")
	assert_false(_session.is_open())
	assert_eq(_session.get_table(), "")
	assert_true(_session.get_shelf().is_empty())
	assert_true(_session.get_players().is_empty())


func test_a_client_keeps_the_hosts_summary() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	watch_signals(_session)
	_session._rpc_session_summary(
		{
			"open": false,
			"table": "camp",
			"shelf": [{"folder": "camp", "map_path": "", "hashes": {"map": HASH}}],
			"players": {"enet-1": {"name": "Gm", "peer_id": 1}},
		}
	)
	assert_signal_emitted(_session, "session_changed")
	assert_eq(_session.get_table(), "camp")
	assert_eq(_session.get_shelf().size(), 1)
	assert_eq(
		_session.get_shelf()[0],
		{"folder": "camp", "map_path": "", "hashes": {"map": HASH}, "name": ""},
		"a summary without a name keeps an empty one"
	)
	assert_eq(_session.peer_for("enet-1"), 1)


func test_the_host_ignores_a_summary() -> void:
	_session.note_table_out(_level_dict("camp"))
	_session._rpc_session_summary({"table": "elsewhere"})
	assert_eq(_session.get_table(), "camp")


func test_a_summary_keeps_only_known_well_typed_fields() -> void:
	var clean := SessionChannel.sanitize_summary(
		{
			"open": "yes",
			"table": 5,
			"shelf": ["junk", {"folder": 3, "map_path": MAP_A, "hashes": {"map": "x", "evil": HASH}}],
			"players": {7: {"name": "NoStringKey"}, "enet-2": {"name": "Di", "peer_id": "2"}},
			"extra": true,
		}
	)
	assert_eq(
		clean.keys(), ["open", "table", "shelf", "players", "holdings", "selected", "progress"]
	)
	assert_eq(clean.open, false)
	assert_eq(clean.table, "")
	assert_eq(clean.shelf, [{"folder": "", "map_path": MAP_A, "hashes": {}, "name": ""}])
	assert_eq(clean.players, {"enet-2": {"name": "Di", "peer_id": 0}})
	assert_eq(SessionChannel.sanitize_summary("not a dictionary").table, "")


func test_a_summary_is_bounded() -> void:
	var shelf := []
	for i in SessionChannel.MAX_SHELF + 10:
		shelf.append({"folder": "m%d" % i})
	var clean := SessionChannel.sanitize_summary({"shelf": shelf, "table": "x".repeat(10000)})
	assert_eq(clean.shelf.size(), SessionChannel.MAX_SHELF)
	assert_eq(clean.table.length(), SessionChannel.MAX_TEXT)


func test_room_opened_reaches_a_client() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	_session._rpc_session_summary({"open": false, "table": "camp"})
	watch_signals(_session)
	_session._rpc_room_opened()
	assert_signal_emitted(_session, "room_opened")
	assert_true(_session.is_open())
	assert_eq(_session.get_table(), "")


func test_going_offline_forgets_the_session() -> void:
	_session.note_table_out(_level_dict("camp"))
	_session._on_connection_state_changed(
		NetworkManager.ConnectionState.HOSTING, NetworkManager.ConnectionState.OFFLINE
	)
	assert_eq(_session.get_table(), "")
	assert_true(_session.get_shelf().is_empty())


func test_the_gm_shelves_a_map_without_setting_it_out() -> void:
	_session.open()
	watch_signals(_session)
	assert_eq(_session.shelve(_level_dict("camp")), "camp")
	assert_signal_emitted(_session, "session_changed")
	assert_true(_session.is_open(), "the room stays open")
	assert_eq(_session.get_table(), "")
	assert_eq(_session.get_shelf()[0].name, "camp")
	assert_eq(_session.shelve(_level_dict("camp")), "camp", "shelving again keeps one entry")
	assert_eq(_session.get_shelf().size(), 1)
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	assert_eq(_session.shelve(_level_dict("ruins")), "", "only the host shelves")


func test_holdings_keep_shelf_keys_and_the_host_holds_every_map() -> void:
	_session._add_player("enet-1", "Gm", 1)
	_session._add_player("enet-ana", "Ana", 7)
	_session.shelve(_level_dict("camp"))
	_session.shelve(_level_dict("ruins"))
	_session.note_holdings("enet-ana", ["ruins", "not-on-the-shelf", 5])
	var holdings := _session.get_holdings()
	assert_eq(holdings["enet-ana"], ["ruins"])
	assert_eq(holdings["enet-1"], ["camp", "ruins"])
	assert_eq(_session.summary().holdings, holdings, "the summary carries them")


func test_a_summary_keeps_clean_holdings() -> void:
	var clean := SessionChannel.sanitize_summary(
		{"holdings": {"enet-2": ["camp", 3, {}], 9: ["camp"], "enet-3": "camp"}}
	)
	assert_eq(clean.holdings, {"enet-2": ["camp"], "enet-3": []})


func test_holding_a_map_needs_its_hashed_files_here() -> void:
	var none := func(_folder: String, _variant: String, _hash: String) -> String: return ""
	var cached := func(_folder: String, _variant: String, _hash: String) -> String:
		return "user://cache/map.glb"
	var shipped := {"folder": "", "map_path": MAP_A, "hashes": {}}
	assert_true(SessionChannel.holds_map(shipped, none), "a map that ships with the game")
	var unhashed := {"folder": "_room_panel_absent", "hashes": {}}
	assert_false(SessionChannel.holds_map(unhashed, cached), "no hashes: not counted")
	var hashed := {"folder": "_room_panel_absent", "hashes": {"map": HASH}}
	assert_false(SessionChannel.holds_map(hashed, none))
	assert_true(SessionChannel.holds_map(hashed, cached), "in the download cache")


func test_missing_variants_name_the_files_to_fetch() -> void:
	var only_ttmap := func(_folder: String, variant: String, _hash: String) -> String:
		return "user://cache/map.ttmap" if variant == "ttmap" else ""
	var both := {"folder": "_room_panel_absent", "hashes": {"map": HASH, "ttmap": HASH}}
	assert_eq(SessionChannel.missing_variants(both, only_ttmap), ["map"])
	assert_eq(SessionChannel.missing_variants({"folder": "", "map_path": MAP_A}, only_ttmap), [])
	assert_eq(SessionChannel.missing_variants({"folder": "x", "hashes": {}}, only_ttmap), [])


## The host serves map files only for the map on the table and the shelf maps.
func test_the_whitelist_is_the_table_and_the_shelf() -> void:
	_session.shelve(_level_dict("camp"))
	_session.shelve({"level_name": "Shipped", "map_path": MAP_A})
	assert_eq(_session.servable_folders(), ["camp"], "a shipped map has no folder to serve")
	NetworkManager.broadcast_level_data(_level_dict("ruins"))
	assert_eq(_session.servable_folders(), ["ruins", "camp"])
	var folders := _session.servable_folders()
	var streamer := AssetManager.streamer
	assert_ne(streamer.level_map_file_for_request("camp", "map", folders), "", "a shelf map")
	assert_ne(streamer.level_map_file_for_request("ruins", "ttmap", folders), "", "the table")
	assert_eq(streamer.level_map_file_for_request("vault", "map", folders), "", "not shelved")
	assert_eq(streamer.level_map_file_for_request("../camp", "../x", folders), "", "no variant")
	assert_eq(SessionChannel.servable("", []), [])


func test_the_gms_selection_rides_in_the_summary() -> void:
	_session.shelve(_level_dict("camp"))
	_session.select_map("camp")
	assert_eq(_session.get_selected(), "camp")
	assert_eq(_session.summary().selected, "camp")
	_session.select_map("not-on-the-shelf")
	assert_eq(_session.get_selected(), "", "only a shelf map is selected")
	var clean := SessionChannel.sanitize_summary(
		{"selected": 5, "progress": {"enet-2": {"camp": 40.7, "x": "a", 3: 1}, 9: {}}}
	)
	assert_eq(clean.selected, "")
	assert_eq(clean.progress, {"enet-2": {"camp": 40}})


## Taking a map off the shelf drops its holdings, its progress and its selection; the map on
## the table stays.
func test_unshelving_forgets_the_map_but_never_the_table() -> void:
	_session._add_player("enet-ana", "Ana", 7)
	_session.shelve(_level_dict("camp"))
	_session.shelve(_level_dict("ruins"))
	_session.note_holdings("enet-ana", ["camp", "ruins"])
	_session.prefetch.note_progress("enet-bo", {"camp": 30}, ["camp", "ruins"])
	_session.select_map("camp")
	watch_signals(_session)
	assert_true(_session.unshelve("camp"))
	assert_signal_emitted(_session, "session_changed")
	assert_eq(_session.get_shelf().map(func(r: Dictionary) -> String: return r.folder), ["ruins"])
	assert_eq(_session.get_holdings()["enet-ana"], ["ruins"])
	assert_eq(_session.prefetch.get_progress(), {})
	assert_eq(_session.get_selected(), "")
	assert_eq(_session.servable_folders(), ["ruins"], "no longer served")
	assert_false(_session.unshelve("camp"), "already gone")
	NetworkManager.broadcast_level_data(_level_dict("ruins"))
	assert_false(_session.unshelve("ruins"), "the map on the table stays")
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	assert_false(_session.unshelve("ruins"), "only the host")
