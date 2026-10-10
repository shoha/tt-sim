extends GutTest

## TerrainEvent, a terrain event's wire form (the GM's presets: a bridge collapse, a forest
## fall), and the NetworkGameSync RPC that carries it host -> clients: an event round-trips
## through its 32 bytes; decode() refuses anything out of bounds, which is the only way an
## event enters from the network; a client re-emits an event of the right length and the host
## ignores one sent to it; only the host broadcasts.
##
## NetworkManager is a live autoload: these tests set _connection_state directly and restore it
## in after_each(), as test_network_game_sync does.


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager.game_sync.reset()


func _sample() -> TerrainEvent:
	var event := TerrainEvent.forest_fall(Vector2(-9.5, 7.25), 6.0, 123456)
	event.table_key = 0x7FFF0001
	return event


func test_an_event_round_trips_through_its_bytes() -> void:
	var event := _sample()
	var bytes := event.encode()
	assert_eq(bytes.size(), TerrainEvent.EVENT_BYTES, "tens of bytes, not a document")
	var back := TerrainEvent.decode(bytes)
	assert_not_null(back)
	assert_eq(back.kind, TerrainEvent.Kind.FOREST_FALL)
	assert_eq(back.table_key, event.table_key)
	assert_eq(back.centre, event.centre)
	assert_eq(back.radius_m, event.radius_m)
	assert_almost_eq(back.duration_s, event.duration_s, 0.0001)
	assert_almost_eq(back.lead_s, event.lead_s, 0.0001)
	assert_eq(back.seed_value, event.seed_value)
	var collapse := TerrainEvent.bridge_collapse(7, Vector2(9, 0), 3)
	var collapse_back := TerrainEvent.decode(collapse.encode())
	assert_eq(collapse_back.kind, TerrainEvent.Kind.BRIDGE_COLLAPSE)
	assert_eq(collapse_back.crossing_id, 7)


## The bytes of _sample() with `value` written at `offset`, as a float, or as a byte with
## `as_byte`.
func _with(offset: int, value: float, as_byte: bool = false) -> PackedByteArray:
	var bytes := _sample().encode()
	if as_byte:
		bytes.encode_u8(offset, int(value))
	else:
		bytes.encode_float(offset, value)
	return bytes


func test_decode_refuses_what_is_out_of_bounds() -> void:
	var cases := {
		"short": _sample().encode().slice(0, 31),
		"long": _sample().encode() + PackedByteArray([0]),
		"version": _with(0, 9, true),
		"kind": _with(1, 7, true),
		"nan centre": _with(8, NAN),
		"inf radius": _with(16, INF),
		"far centre": _with(12, TerrainEvent.MAX_COORD_M * 2.0),
		"small radius": _with(16, 0.2),
		"big radius": _with(16, TerrainEvent.MAX_RADIUS_M + 1.0),
		"long duration": _with(20, TerrainEvent.MAX_DURATION_S + 1.0),
		"short duration": _with(20, 0.0),
		"negative lead": _with(24, -0.1),
		"long lead": _with(24, TerrainEvent.MAX_LEAD_S + 0.1),
	}
	for label: String in cases:
		var bytes: PackedByteArray = cases[label]
		assert_ne(TerrainEvent.problem_of(bytes), "", "%s is refused" % label)
		assert_null(TerrainEvent.decode(bytes), "%s decodes to nothing" % label)
	var no_bridge := TerrainEvent.bridge_collapse(0, Vector2.ZERO, 1).encode()
	assert_null(TerrainEvent.decode(no_bridge), "a collapse names a crossing")
	assert_eq(TerrainEvent.problem_of(_sample().encode()), "")


func test_a_client_hears_an_event_and_the_host_ignores_one() -> void:
	var game_sync := NetworkManager.game_sync
	watch_signals(game_sync)
	var bytes := _sample().encode()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	game_sync._rpc_terrain_event(bytes)
	assert_signal_not_emitted(game_sync, "terrain_event_received", "the host sends events")
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	game_sync._rpc_terrain_event(bytes.slice(0, 8))
	assert_signal_not_emitted(game_sync, "terrain_event_received", "a wrong length is dropped")
	game_sync._rpc_terrain_event(bytes)
	assert_signal_emitted_with_parameters(game_sync, "terrain_event_received", [bytes])


func test_only_the_host_broadcasts_an_event() -> void:
	var game_sync := NetworkManager.game_sync
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	game_sync.broadcast_terrain_event(_sample().encode())
	assert_eq(game_sync.live_edits_waiting(), 0, "a client queues nothing")
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	game_sync.broadcast_terrain_event(PackedByteArray([1, 2, 3]))
	assert_eq(game_sync.live_edits_waiting(), 0, "nor does the host for bytes that are no event")
