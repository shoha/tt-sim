class_name TerrainEvent
extends RefCounted

## One terrain event of the GM's Events pane (a bridge collapsing, a forest falling, a fire) as
## the few parameters every peer needs to play the same motion on its own board: what happens
## (`kind`), where (`centre`, map XZ, and `radius_m` or `crossing_id`), how long it lasts, how
## long the host waits before it plays it, and a seed for the variation. An effect is not
## document state: the host broadcasts the event (NetworkGameSync.broadcast_terrain_event),
## every peer simulates it (TerrainEvents), and the host then makes the map change it ends in
## as an ordinary live edit (a crossing removal, a Clear over the area, ash and the burnt
## biome), which reaches every peer, late joiners included, as ops. A late joiner never sees
## the motion, only the ops.
##
## A fire runs out from its centre over a circle, or along a path (Start a fire's Path shape,
## design 3d): `path` holds the line (map XZ, StrokePath's resample, at most MAX_PATH_POINTS
## points at least a metre apart), `centre` is its first point (where it catches), `radius_m`
## its half-width and the duration follows from its length (path_spread: the front runs at
## PATH_SPEED_MPS, held to PATH_SPREAD_S, then PATH_TAIL_S for the last trees to burn down).
##
## Wire form: EVENT_BYTES little-endian bytes of header (encode, decode), and for a fire along
## a path its points after it: the header's crossing-id u16 (always 0 for a fire) is then the
## point count n, and n x/z f32 pairs follow, so a path is EVENT_BYTES + POINT_BYTES * n bytes,
## at most MAX_EVENT_BYTES (n = 0 is a circle's 32 bytes). decode() is the only way an event
## enters from the network and refuses anything out of bounds (problem_of says why): a wrong
## length or version, an unknown kind, a value that is not finite, a radius, duration or lead
## outside their ranges, a centre past MAX_COORD_M, a crossing id past Crossing.MAX_ID; and for
## a path, points on any kind but a fire, one point or more than MAX_PATH_POINTS, a point that
## is not finite or off any map, a step under MIN_STEP_M or over MAX_STEP_M, a line over
## MAX_PATH_LENGTH_M, a half-width outside the path's range or a duration past
## MAX_PATH_DURATION_S. Whether the crossing or the trees are there is the receiving map's
## question (TerrainEvents).

enum Kind { BRIDGE_COLLAPSE = 1, FOREST_FALL = 2, FIRE = 3 }

const VERSION := 2
## The header: version u8, kind u8, crossing id (a fire's: its path's point count) u16, table
## key u32, centre x f32, centre z f32, radius f32, duration f32, lead f32, seed u32.
const EVENT_BYTES := 32
## A path point: x f32, z f32.
const POINT_BYTES := 8
const MAX_PATH_POINTS := StrokePath.MAX_POINTS
const MAX_EVENT_BYTES := EVENT_BYTES + POINT_BYTES * MAX_PATH_POINTS
const MIN_RADIUS_M := 1.0
const MAX_RADIUS_M := 16.0
const MIN_DURATION_S := 0.5
const MAX_DURATION_S := 4.0
## A path's half-width (a 12 m wide front is already a wall of fire), its steps between points
## (StrokePath spaces them about a metre apart) and its length (about a 200 ft map's width).
const MIN_PATH_RADIUS_M := 1.0
const MAX_PATH_RADIUS_M := 6.0
const MIN_STEP_M := 0.05
const MAX_STEP_M := 4.0
const MAX_PATH_LENGTH_M := StrokePath.MAX_LENGTH_M
const MAX_PATH_DURATION_S := 6.0
## A path's front: it runs at PATH_SPEED_MPS from the first point to the last, taking between
## PATH_SPREAD_S.x and .y however long the path, and the event lasts PATH_TAIL_S past it (the
## last trees' burn and their snags going, as a circle's 4 s are its 2 s front and 2 s after).
const PATH_SPEED_MPS := 12.0
const PATH_SPREAD_S := Vector2(1.0, 3.5)
const PATH_TAIL_S := 2.0
## The host plays an event this long after it sends it, so a client that hears it a network
## hop later starts nearly together (there is no shared clock; LEAD_S is a typical hop).
const LEAD_S := 0.1
const MAX_LEAD_S := 0.5
## Map frame coordinates beyond this are no map's.
const MAX_COORD_M := 4096.0
## How long each kind plays: a bridge's fall reads in about two seconds, a stand of trees
## toppling in a ripple in under three (the card: 1.5-2.5 s and 2-3 s), a fire spreading out
## from the click and burning down in four (the card: 3-5 s; its smoke hangs on after).
const DURATIONS := {Kind.BRIDGE_COLLAPSE: 2.2, Kind.FOREST_FALL: 2.8, Kind.FIRE: 4.0}
const KINDS: Array[int] = [Kind.BRIDGE_COLLAPSE, Kind.FOREST_FALL, Kind.FIRE]

var kind: int = Kind.BRIDGE_COLLAPSE
## The table the event belongs to (LiveEdits.table_key): a client plays only its own table's.
var table_key: int = 0
## Map frame XZ: a bridge's middle, or the point the trees fall away from.
var centre: Vector2 = Vector2.ZERO
var radius_m: float = MIN_RADIUS_M
## The crossing a collapse takes down (Crossing.id), 0 for a forest fall or a fire.
var crossing_id: int = 0
var duration_s: float = MIN_DURATION_S
var lead_s: float = LEAD_S
## Seeds the variation (which piece goes first, how each tree falls), the same on every peer.
var seed_value: int = 0
## A fire along a path: its points (map XZ), the first its centre; empty for a circle.
var path := PackedVector2Array()


## A bridge collapse of crossing `id` whose middle is map point `middle`.
static func bridge_collapse(id: int, middle: Vector2, event_seed: int) -> TerrainEvent:
	var event := TerrainEvent.new()
	event.kind = Kind.BRIDGE_COLLAPSE
	event.crossing_id = id
	event.centre = middle
	event.radius_m = MIN_RADIUS_M
	event.duration_s = DURATIONS[Kind.BRIDGE_COLLAPSE]
	event.seed_value = event_seed
	return event


## A forest fall over the circle of `radius` metres around map point `at`.
static func forest_fall(at: Vector2, radius: float, event_seed: int) -> TerrainEvent:
	var event := TerrainEvent.new()
	event.kind = Kind.FOREST_FALL
	event.centre = at
	event.radius_m = clampf(radius, MIN_RADIUS_M, MAX_RADIUS_M)
	event.duration_s = DURATIONS[Kind.FOREST_FALL]
	event.seed_value = event_seed
	return event


## A fire over the circle of `radius` metres around map point `at`, spreading out from it.
static func fire(at: Vector2, radius: float, event_seed: int) -> TerrainEvent:
	var event := forest_fall(at, radius, event_seed)
	event.kind = Kind.FIRE
	event.duration_s = DURATIONS[Kind.FIRE]
	return event


## A fire along `line` (map XZ, StrokePath's resample: at least two points), `half_width`
## metres either side of it, catching at its first point and running to its last.
static func fire_path(line: PackedVector2Array, half_width: float, event_seed: int) -> TerrainEvent:
	var event := TerrainEvent.new()
	event.kind = Kind.FIRE
	event.path = line
	event.centre = line[0] if not line.is_empty() else Vector2.ZERO
	event.radius_m = clampf(half_width, MIN_PATH_RADIUS_M, MAX_PATH_RADIUS_M)
	event.duration_s = path_spread(StrokePath.line_length(line)) + PATH_TAIL_S
	event.seed_value = event_seed
	return event


## How long a path's front takes from its first point to its last on a path `length` metres
## long: at PATH_SPEED_MPS, within PATH_SPREAD_S. Pure.
static func path_spread(length: float) -> float:
	return clampf(length / PATH_SPEED_MPS, PATH_SPREAD_S.x, PATH_SPREAD_S.y)


## True for a wire length `size` an event can have: the header, and whole points after it up
## to MAX_EVENT_BYTES (the RPC drops anything else unread). Pure.
static func is_event_size(size: int) -> bool:
	var extra := size - EVENT_BYTES
	return extra >= 0 and size <= MAX_EVENT_BYTES and extra % POINT_BYTES == 0


## True for a fire along a path.
func is_path() -> bool:
	return not path.is_empty()


## The map rectangle the event reaches: its circle, or its path grown by the half-width.
func bounds() -> Rect2:
	var rect := Rect2(centre, Vector2.ZERO)
	for p in path:
		rect = rect.expand(p)
	return rect.grow(radius_m)


## The least distance between this event's line and `other`'s (a circle's line is its centre),
## metres. Pure.
func distance_to(other: TerrainEvent) -> float:
	var mine := path if is_path() else PackedVector2Array([centre])
	var theirs := other.path if other.is_path() else PackedVector2Array([other.centre])
	var least := INF
	for p in mine:
		least = minf(least, distance_to_line(p, theirs))
	for p in theirs:
		least = minf(least, distance_to_line(p, mine))
	return least


## The distance from `p` to the polyline `line` (one point: to it). Pure.
static func distance_to_line(p: Vector2, line: PackedVector2Array) -> float:
	if line.size() == 1:
		return p.distance_to(line[0])
	var least := INF
	for i in line.size() - 1:
		var on := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		least = minf(least, p.distance_to(on))
	return least


## The event as its wire bytes: the header, and a path's points after it.
func encode() -> PackedByteArray:
	var bytes := PackedByteArray()
	var points := path.size() if kind == Kind.FIRE else 0
	bytes.resize(EVENT_BYTES + POINT_BYTES * points)
	bytes.encode_u8(0, VERSION)
	bytes.encode_u8(1, kind)
	bytes.encode_u16(2, points if kind == Kind.FIRE else crossing_id)
	bytes.encode_u32(4, table_key & 0xFFFFFFFF)
	bytes.encode_float(8, centre.x)
	bytes.encode_float(12, centre.y)
	bytes.encode_float(16, radius_m)
	bytes.encode_float(20, duration_s)
	bytes.encode_float(24, lead_s)
	bytes.encode_u32(28, seed_value & 0xFFFFFFFF)
	for i in points:
		bytes.encode_float(EVENT_BYTES + POINT_BYTES * i, path[i].x)
		bytes.encode_float(EVENT_BYTES + POINT_BYTES * i + 4, path[i].y)
	return bytes


## The event `bytes` carry, or null when they are out of bounds (problem_of says why).
static func decode(bytes: PackedByteArray) -> TerrainEvent:
	if problem_of(bytes) != "":
		return null
	var event := TerrainEvent.new()
	event.kind = bytes.decode_u8(1)
	if event.kind == Kind.FIRE:
		for i in bytes.decode_u16(2):
			var at := EVENT_BYTES + POINT_BYTES * i
			event.path.append(Vector2(bytes.decode_float(at), bytes.decode_float(at + 4)))
	else:
		event.crossing_id = bytes.decode_u16(2)
	event.table_key = bytes.decode_u32(4)
	event.centre = Vector2(bytes.decode_float(8), bytes.decode_float(12))
	event.radius_m = bytes.decode_float(16)
	event.duration_s = bytes.decode_float(20)
	event.lead_s = bytes.decode_float(24)
	event.seed_value = bytes.decode_u32(28)
	return event


## Why `bytes` are no event ("" when they are one). Pure.
static func problem_of(bytes: PackedByteArray) -> String:
	if bytes.size() < EVENT_BYTES or bytes.size() > MAX_EVENT_BYTES:
		return "an event is %d to %d bytes, not %d" % [EVENT_BYTES, MAX_EVENT_BYTES, bytes.size()]
	if bytes.decode_u8(0) != VERSION:
		return "event version %d" % bytes.decode_u8(0)
	var event_kind := bytes.decode_u8(1)
	if not event_kind in KINDS:
		return "unknown event kind %d" % event_kind
	var id := bytes.decode_u16(2)
	if event_kind == Kind.FOREST_FALL and id != 0:
		return "a forest fall carries no path"
	var points := id if event_kind == Kind.FIRE else 0
	if bytes.size() != EVENT_BYTES + POINT_BYTES * points:
		return "an event of %d points is not %d bytes" % [points, bytes.size()]
	if points == 1 or points > MAX_PATH_POINTS:
		return "a path of %d points" % points
	var values := []
	for offset in [8, 12, 16, 20, 24]:
		var value := bytes.decode_float(offset)
		if is_nan(value) or is_inf(value):
			return "a value that is not a number"
		values.append(value)
	if absf(values[0]) > MAX_COORD_M or absf(values[1]) > MAX_COORD_M:
		return "a centre off any map"
	var radius := Vector2(MIN_RADIUS_M, MAX_RADIUS_M)
	var duration := Vector2(MIN_DURATION_S, MAX_DURATION_S)
	if points > 0:
		radius = Vector2(MIN_PATH_RADIUS_M, MAX_PATH_RADIUS_M)
		duration = Vector2(MIN_DURATION_S, MAX_PATH_DURATION_S)
	if values[2] < radius.x or values[2] > radius.y:
		return "a radius of %.1f m" % values[2]
	if values[3] < duration.x or values[3] > duration.y:
		return "a duration of %.1f s" % values[3]
	if values[4] < 0.0 or values[4] > MAX_LEAD_S:
		return "a lead of %.2f s" % values[4]
	if event_kind == Kind.BRIDGE_COLLAPSE and (id < 1 or id > Crossing.MAX_ID):
		return "crossing id %d" % id
	return _path_problem(bytes, points)


## Why the `points` path points after the header of `bytes` are no path ("" when they are
## one, or there are none). Pure.
static func _path_problem(bytes: PackedByteArray, points: int) -> String:
	var total := 0.0
	var last := Vector2.INF
	for i in points:
		var x := bytes.decode_float(EVENT_BYTES + POINT_BYTES * i)
		var z := bytes.decode_float(EVENT_BYTES + POINT_BYTES * i + 4)
		if is_nan(x) or is_inf(x) or is_nan(z) or is_inf(z):
			return "a path point that is not a number"
		if absf(x) > MAX_COORD_M or absf(z) > MAX_COORD_M:
			return "a path point off any map"
		var p := Vector2(x, z)
		if last != Vector2.INF:
			var step := last.distance_to(p)
			if step < MIN_STEP_M or step > MAX_STEP_M:
				return "a path step of %.2f m" % step
			total += step
		last = p
	# StrokePath.capped's cut lands on the length to float precision.
	if total > MAX_PATH_LENGTH_M + 0.01:
		return "a path of %.1f m" % total
	return ""
