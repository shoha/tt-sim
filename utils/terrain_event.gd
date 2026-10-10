class_name TerrainEvent
extends RefCounted

## One terrain event of the GM's Events pane (a bridge collapsing, a forest falling) as the
## few parameters every peer needs to play the same motion on its own board: what happens
## (`kind`), where (`centre`, map XZ, and `radius_m` or `crossing_id`), how long it lasts, how
## long the host waits before it plays it, and a seed for the variation. An effect is not
## document state: the host broadcasts the event (NetworkGameSync.broadcast_terrain_event),
## every peer simulates it (TerrainEvents), and the host then makes the map change it ends in
## as an ordinary live edit (a crossing removal, a Clear over the area), which reaches every
## peer, late joiners included, as an op. A late joiner never sees the motion, only the op.
##
## Wire form: EVENT_BYTES little-endian bytes (encode, decode). decode() is the only way an
## event enters from the network and refuses anything out of bounds (problem_of says why): a
## wrong length or version, an unknown kind, a value that is not finite, a radius, duration or
## lead outside their ranges, a centre past MAX_COORD_M, or a crossing id past Crossing.MAX_ID.
## Whether the crossing or the trees are there is the receiving map's question (TerrainEvents).

enum Kind { BRIDGE_COLLAPSE = 1, FOREST_FALL = 2 }

const VERSION := 1
## version u8, kind u8, crossing id u16, table key u32, centre x f32, centre z f32, radius
## f32, duration f32, lead f32, seed u32.
const EVENT_BYTES := 32
const MIN_RADIUS_M := 1.0
const MAX_RADIUS_M := 16.0
const MIN_DURATION_S := 0.5
const MAX_DURATION_S := 4.0
## The host plays an event this long after it sends it, so a client that hears it a network
## hop later starts nearly together (there is no shared clock; LEAD_S is a typical hop).
const LEAD_S := 0.1
const MAX_LEAD_S := 0.5
## Map frame coordinates beyond this are no map's.
const MAX_COORD_M := 4096.0
## How long each kind plays: a bridge's fall reads in about two seconds, a stand of trees
## toppling in a ripple in under three (the card: 1.5-2.5 s and 2-3 s).
const DURATIONS := {Kind.BRIDGE_COLLAPSE: 2.2, Kind.FOREST_FALL: 2.8}

var kind: int = Kind.BRIDGE_COLLAPSE
## The table the event belongs to (LiveEdits.table_key): a client plays only its own table's.
var table_key: int = 0
## Map frame XZ: a bridge's middle, or the point the trees fall away from.
var centre: Vector2 = Vector2.ZERO
var radius_m: float = MIN_RADIUS_M
## The crossing a collapse takes down (Crossing.id), 0 for a forest fall.
var crossing_id: int = 0
var duration_s: float = MIN_DURATION_S
var lead_s: float = LEAD_S
## Seeds the variation (which piece goes first, how each tree falls), the same on every peer.
var seed_value: int = 0


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


## The event as its EVENT_BYTES wire bytes.
func encode() -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(EVENT_BYTES)
	bytes.encode_u8(0, VERSION)
	bytes.encode_u8(1, kind)
	bytes.encode_u16(2, crossing_id)
	bytes.encode_u32(4, table_key & 0xFFFFFFFF)
	bytes.encode_float(8, centre.x)
	bytes.encode_float(12, centre.y)
	bytes.encode_float(16, radius_m)
	bytes.encode_float(20, duration_s)
	bytes.encode_float(24, lead_s)
	bytes.encode_u32(28, seed_value & 0xFFFFFFFF)
	return bytes


## The event `bytes` carry, or null when they are out of bounds (problem_of says why).
static func decode(bytes: PackedByteArray) -> TerrainEvent:
	if problem_of(bytes) != "":
		return null
	var event := TerrainEvent.new()
	event.kind = bytes.decode_u8(1)
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
	if bytes.size() != EVENT_BYTES:
		return "an event is %d bytes, not %d" % [EVENT_BYTES, bytes.size()]
	if bytes.decode_u8(0) != VERSION:
		return "event version %d" % bytes.decode_u8(0)
	var event_kind := bytes.decode_u8(1)
	if not event_kind in [Kind.BRIDGE_COLLAPSE, Kind.FOREST_FALL]:
		return "unknown event kind %d" % event_kind
	var values := []
	for offset in [8, 12, 16, 20, 24]:
		var value := bytes.decode_float(offset)
		if is_nan(value) or is_inf(value):
			return "a value that is not a number"
		values.append(value)
	if absf(values[0]) > MAX_COORD_M or absf(values[1]) > MAX_COORD_M:
		return "a centre off any map"
	if values[2] < MIN_RADIUS_M or values[2] > MAX_RADIUS_M:
		return "a radius of %.1f m" % values[2]
	if values[3] < MIN_DURATION_S or values[3] > MAX_DURATION_S:
		return "a duration of %.1f s" % values[3]
	if values[4] < 0.0 or values[4] > MAX_LEAD_S:
		return "a lead of %.2f s" % values[4]
	var id := bytes.decode_u16(2)
	if event_kind == Kind.BRIDGE_COLLAPSE and (id < 1 or id > Crossing.MAX_ID):
		return "crossing id %d" % id
	return ""
