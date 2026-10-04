class_name WaterBody
extends RefCounted

## One authored body of water in a MapDocument (`MapDocument.water_bodies`): a river drawn
## as a line or a pond painted as an area. Every body is flat: its surface is one level in
## metres, and the water covers the samples of its area whose ground is below that level
## (WaterGeometry.levels()). Summary and the level rules: docs/systems/water.md (Water model
## and flow bake).
##
## River: `points` is the control polyline in map XZ (Vector2(x, z), metres, the frame of
## MapDocument.world_to_sample()), first point upstream, so the water flows from the first
## point to the last; `half_widths` holds the channel half-width at each point. Everything
## derived (wet area, carve, flow) follows its Chaikin-smoothed course
## (WaterGeometry.river_course()), not the raw corners. `speed` is the flow bake's speed
## factor (terrain-paint's tp_flow_speed: 1 is full speed, above 1 saturates the channel).
##
## Pond: its area is the samples of MapDocument.pond_mask holding its id; `points`,
## `half_widths` and `speed` are unused and empty / 0. Ponds are still water.
##
## `id` is stable for the body's lifetime (1..MAX_ID, unique across all bodies of a
## document): a pond's id is the byte its area carries in the mask, and undo and erase
## address bodies by it. `depth` is the per-stroke depth class the author picked; the
## carve reads the channel or basin depth below the level from depth_m().

enum Kind { RIVER, POND }
## Wading depth classes: a token stands on the bed in ANKLE and WAIST water and floats at
## the surface in DEEP water.
enum Depth { ANKLE, WAIST, DEEP }

## Water depth below the level for each Depth, in metres (a 5 ft token is ~1.5 m tall).
const DEPTH_M: Array[float] = [0.3, 0.9, 2.0]
## The names Depth and Kind take in splines.json.
const DEPTH_NAMES: Array[String] = ["ankle", "waist", "deep"]
const KIND_NAMES: Array[String] = ["river", "pond"]
## Ids are one byte in the pond mask, 0 meaning no pond.
const MAX_ID := 255
const MIN_HALF_WIDTH_M := 0.2
const MAX_HALF_WIDTH_M := 10.0
const MAX_SPEED := 2.0
const DEFAULT_SPEED := 1.0

var id: int = 0
var kind: Kind = Kind.RIVER
var depth: Depth = Depth.WAIST
## Flat water surface height in metres, the frame of MapDocument.heights.
var level_m: float = 0.0
## Rivers only: flow speed factor 0..MAX_SPEED.
var speed: float = 0.0
## Rivers only: control polyline in map XZ, upstream first.
var points: PackedVector2Array = PackedVector2Array()
## Rivers only: half-width in metres at each point of `points`.
var half_widths: PackedFloat32Array = PackedFloat32Array()


static func river(
	body_id: int,
	line: PackedVector2Array,
	widths: PackedFloat32Array,
	depth_class: Depth,
	level: float,
	flow_speed: float = DEFAULT_SPEED
) -> WaterBody:
	var body := WaterBody.new()
	body.id = body_id
	body.kind = Kind.RIVER
	body.depth = depth_class
	body.level_m = level
	body.speed = flow_speed
	body.points = line
	body.half_widths = widths
	return body


static func pond(body_id: int, depth_class: Depth, level: float) -> WaterBody:
	var body := WaterBody.new()
	body.id = body_id
	body.kind = Kind.POND
	body.depth = depth_class
	body.level_m = level
	return body


## Metres of water below the level for `depth_class`.
static func depth_for(depth_class: Depth) -> float:
	return DEPTH_M[depth_class]


## True when a token stands on the bed in this depth class rather than floating.
static func is_wadeable(depth_class: Depth) -> bool:
	return depth_class != Depth.DEEP


func depth_m() -> float:
	return depth_for(depth)


func is_river() -> bool:
	return kind == Kind.RIVER


## A deep copy (packed arrays are shared by reference in GDScript).
func copy() -> WaterBody:
	var body := WaterBody.new()
	body.id = id
	body.kind = kind
	body.depth = depth
	body.level_m = level_m
	body.speed = speed
	body.points = points.duplicate()
	body.half_widths = half_widths.duplicate()
	return body
