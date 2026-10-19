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
	var fire := TerrainEvent.fire(Vector2(3.5, -2.0), 40.0, 99)
	assert_eq(fire.radius_m, TerrainEvent.MAX_RADIUS_M, "a fire's radius is clamped as a fall's")
	var fire_back := TerrainEvent.decode(fire.encode())
	assert_not_null(fire_back, "a fire is an event")
	assert_eq(fire_back.kind, TerrainEvent.Kind.FIRE)
	assert_eq(fire_back.crossing_id, 0)
	assert_eq(fire_back.centre, Vector2(3.5, -2.0))
	assert_almost_eq(fire_back.duration_s, TerrainEvent.DURATIONS[TerrainEvent.Kind.FIRE], 0.0001)
	assert_lte(fire.duration_s, TerrainEvent.MAX_DURATION_S, "within the duration bound")


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
	# The kind after the last one is unknown; a fire is held to a fall's bounds.
	assert_ne(TerrainEvent.problem_of(_with(1, TerrainEvent.Kind.FIRE + 1, true)), "")
	var fire := TerrainEvent.fire(Vector2.ZERO, 5.0, 1).encode()
	assert_eq(TerrainEvent.problem_of(fire), "")
	fire.encode_float(16, TerrainEvent.MAX_RADIUS_M * 2.0)
	assert_null(TerrainEvent.decode(fire), "a fire past the radius bound")


## A fire path of `n` points `step` metres apart along x from (-10, 2), resampled as
## IgniteMode makes one when `step` is 0 (a 30 m curve).
func _path(n: int = 0, step: float = 1.0) -> PackedVector2Array:
	if n > 0:
		var line := PackedVector2Array()
		for i in n:
			line.append(Vector2(-10.0 + step * i, 2.0))
		return line
	var drawn := PackedVector2Array([Vector2(-10, 2), Vector2(0, 6), Vector2(10, 0), Vector2(18, 3)])
	var smooth := StrokePath.smooth_line(drawn)
	return StrokePath.resample(smooth, StrokePath.MAX_POINTS, StrokePath.MIN_SPACING_M)


## A fire path's bytes: the header with the point count in place of the crossing id, then the
## points; it round-trips, a circle stays 32 bytes, and the longest path is 544.
func test_a_fire_path_round_trips_through_its_bytes() -> void:
	var line := _path()
	var event := TerrainEvent.fire_path(line, 2.5, 4242)
	event.table_key = 0x7FFF0002
	var bytes := event.encode()
	assert_eq(bytes.size(), TerrainEvent.EVENT_BYTES + TerrainEvent.POINT_BYTES * line.size())
	assert_eq(bytes.decode_u16(2), line.size(), "the point count in the crossing id's place")
	var back := TerrainEvent.decode(bytes)
	assert_not_null(back, "a path is an event: %s" % TerrainEvent.problem_of(bytes))
	if back == null:
		return
	assert_true(back.is_path())
	assert_eq(back.path, line, "every point, in order")
	assert_eq(back.centre, line[0], "it catches at its first point")
	assert_eq(back.radius_m, 2.5)
	assert_eq(back.crossing_id, 0)
	assert_eq(back.table_key, event.table_key)
	var length := StrokePath.line_length(line)
	var spread := clampf(length / TerrainEvent.PATH_SPEED_MPS, 1.0, 3.5)
	assert_almost_eq(back.duration_s, spread + TerrainEvent.PATH_TAIL_S, 0.0001)
	assert_lt(back.duration_s, TerrainEvent.MAX_PATH_DURATION_S, "under 6 s")
	assert_almost_eq(TerrainEvent.path_spread(64.0), 3.5, 0.0001, "the longest front is held")
	assert_almost_eq(TerrainEvent.path_spread(3.0), 1.0, 0.0001, "and the shortest")
	assert_eq(TerrainEvent.fire_path(line, 9.0, 1).radius_m, TerrainEvent.MAX_PATH_RADIUS_M)
	assert_eq(TerrainEvent.fire_path(line, 0.2, 1).radius_m, TerrainEvent.MIN_PATH_RADIUS_M)
	assert_eq(TerrainEvent.fire(Vector2.ZERO, 5.0, 1).encode().size(), 32, "a circle: 32 bytes")
	var longest := TerrainEvent.fire_path(_path(TerrainEvent.MAX_PATH_POINTS, 1.0), 6.0, 3)
	var most := longest.encode()
	assert_eq(most.size(), 544, "the longest path")
	assert_eq(TerrainEvent.MAX_EVENT_BYTES, 544)
	assert_not_null(TerrainEvent.decode(most), TerrainEvent.problem_of(most))
	assert_true(TerrainEvent.is_event_size(32))
	assert_true(TerrainEvent.is_event_size(544))
	assert_false(TerrainEvent.is_event_size(33), "whole points only")
	assert_false(TerrainEvent.is_event_size(552), "no more than 64 points")
	var rect := event.bounds()
	assert_true(rect.has_point(line[-1]) and rect.has_point(line[0]), "the whole path in bounds")


## The bytes of a 3-point path fire with `at` (byte offset) set to `value`.
func _path_with(at: int, value: float) -> PackedByteArray:
	var bytes := TerrainEvent.fire_path(_path(3, 1.0), 2.0, 1).encode()
	bytes.encode_float(at, value)
	return bytes


func test_decode_refuses_a_path_out_of_bounds() -> void:
	var first := TerrainEvent.EVENT_BYTES
	var fall := _sample().encode()
	fall.encode_u16(2, 2)
	fall.append_array(TerrainEvent.fire_path(_path(2, 1.0), 2.0, 1).encode().slice(first))
	var one := TerrainEvent.fire_path(_path(2, 1.0), 2.0, 1).encode().slice(0, first + 8)
	one.encode_u16(2, 1)
	var many := TerrainEvent.fire_path(_path(65, 0.9), 2.0, 1).encode()
	var short := TerrainEvent.fire_path(_path(3, 1.0), 2.0, 1).encode().slice(0, first + 16)
	var cases := {
		"points on a forest fall": fall,
		"one point": one,
		"65 points": many,
		"a length other than 32 + 8n": short,
		"a nan point": _path_with(first + 8, NAN),
		"an infinite point": _path_with(first + 12, INF),
		"a point off any map": _path_with(first + 16, TerrainEvent.MAX_COORD_M * 2.0),
		"a step under 5 cm": _path_with(first + 8, -10.01),
		"a step over 4 m": _path_with(first + 16, -3.0),
		"a narrow path": _path_with(16, 0.5),
		"a wide path": _path_with(16, TerrainEvent.MAX_PATH_RADIUS_M + 0.5),
		"a long path duration": _path_with(20, TerrainEvent.MAX_PATH_DURATION_S + 0.5),
		"a short path duration": _path_with(20, 0.2),
		"a path over 64 m": TerrainEvent.fire_path(_path(20, 3.9), 2.0, 1).encode(),
	}
	for label: String in cases:
		var bytes: PackedByteArray = cases[label]
		assert_ne(TerrainEvent.problem_of(bytes), "", "%s is refused" % label)
		assert_null(TerrainEvent.decode(bytes), "%s decodes to nothing" % label)
	assert_eq(TerrainEvent.problem_of(_path_with(16, 6.0)), "", "6 m is the widest path")
	assert_eq(TerrainEvent.problem_of(_path_with(20, 5.9)), "", "a path may last nearly 6 s")
	# A circle keeps its own bounds: wider than a path, never past 4 s.
	var circle := TerrainEvent.fire(Vector2.ZERO, 12.0, 1).encode()
	assert_eq(TerrainEvent.problem_of(circle), "", "a 12 m circle")
	circle.encode_float(20, 5.0)
	assert_ne(TerrainEvent.problem_of(circle), "", "a circle over 4 s")


## Two events' lines: a circle's is its centre; the busy check measures between them.
func test_events_measure_between_their_lines() -> void:
	var line := _path(11, 1.0)
	var path := TerrainEvent.fire_path(line, 2.0, 1)
	var near := TerrainEvent.fire(Vector2(-5.0, 5.0), 3.0, 1)
	var far := TerrainEvent.fire(Vector2(-30.0, 2.0), 3.0, 1)
	assert_almost_eq(path.distance_to(near), 3.0, 0.001, "to the line, not its start")
	assert_almost_eq(near.distance_to(path), 3.0, 0.001)
	assert_almost_eq(path.distance_to(far), 20.0, 0.001)
	assert_almost_eq(near.distance_to(far), Vector2(-5, 5).distance_to(Vector2(-30, 2)), 0.001)


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
	var path := TerrainEvent.fire_path(_path(), 2.0, 5).encode()
	game_sync._rpc_terrain_event(path)
	assert_signal_emitted_with_parameters(game_sync, "terrain_event_received", [path])
	assert_signal_emit_count(game_sync, "terrain_event_received", 2)
	game_sync._rpc_terrain_event(path.slice(0, path.size() - 3))
	assert_signal_emit_count(game_sync, "terrain_event_received", 2, "a broken point is dropped")


func test_only_the_host_broadcasts_an_event() -> void:
	var game_sync := NetworkManager.game_sync
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	game_sync.broadcast_terrain_event(_sample().encode())
	assert_eq(game_sync.live_edits_waiting(), 0, "a client queues nothing")
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	game_sync.broadcast_terrain_event(PackedByteArray([1, 2, 3]))
	assert_eq(game_sync.live_edits_waiting(), 0, "nor does the host for bytes that are no event")
