class_name Wall
extends RefCounted

## One authored wall or fence in a MapDocument (`MapDocument.walls`): a dry-stone wall or a
## post and rail fence along a polyline of map points. The geometry is built from these fields
## and the ground under them alone (WallGeometry, the shared procgen module's wall and fence
## recipes), so a wall ships as data in the document and every peer builds the same one.
## Summary: docs/systems/walls.md.
##
## `points` are the line's vertices in map XZ (Vector2(x, z), metres, the frame of
## MapDocument.world_to_sample()); the wall follows the ground between them, so no height is
## stored. `closed` joins the last point back to the first. `height_m` is the wall's height
## above the ground. `style` is the palette biome id whose rock a stone wall takes (the same
## rule as a stepping stone, AuthoredCrossings.stone_surface), or "" for the default; a fence
## uses the planks. `id` is stable for the wall's lifetime (1..MAX_ID, unique in the document)
## and seeds its variation with the map seed.

enum Kind { STONE, FENCE, BUILDING, ROW }

## The names Kind takes in walls.json.
const KIND_NAMES: Array[String] = ["stone", "fence", "building", "row"]
const MAX_ID := 255
const MIN_POINTS := 2
const MAX_POINTS := 64
## Height above the ground, metres, per Kind (a building's is its walls', under the roof).
const MIN_HEIGHT_M: Array[float] = [0.4, 0.5, 1.6, 1.5]
const MAX_HEIGHT_M: Array[float] = [2.0, 2.0, 5.0, 10.0]
const DEFAULT_HEIGHT_M: Array[float] = [0.9, 1.0, 2.4, 3.0]
## A row (a street of buildings along an open line) keeps its street's setback, in metres, in
## `height_m` (the range above is then the setback's), the `side` of the street the buildings stand
## on (ROW_SIDES: left, right, both) and the `seed` that varies them. Its buildings are made from
## these (procgen's street_row recipe), never stored one by one.
const ROW_SIDES := 3
const MAX_SEED := 1000000000
## A building is a closed rectangle of four points (its first side carries the door), each side
## within these bounds, metres.
const BUILDING_POINTS := 4
const BUILDING_MIN_SIDE_M := 2.0
const BUILDING_MAX_SIDE_M := 24.0
## A segment shorter than this is not a wall; the whole line may not exceed MAX_LENGTH_M.
const MIN_SEGMENT_M := 0.3
const MAX_LENGTH_M := 120.0

var id: int = 0
var kind: Kind = Kind.STONE
var points: PackedVector2Array = PackedVector2Array()
var closed: bool = false
var height_m: float = 0.9
## A row's variation seed and the side of its street the buildings stand on (0 left, 1 right, 2
## both); unused by the other kinds.
var seed_value: int = 0
var side: int = 2
## Palette biome id for the rock, or "".
var style: String = ""


static func make(
	wall_id: int,
	wall_kind: Kind,
	line: PackedVector2Array,
	is_closed: bool,
	height: float,
	biome_style: String = ""
) -> Wall:
	var wall := Wall.new()
	wall.id = wall_id
	wall.kind = wall_kind
	wall.points = line
	wall.closed = is_closed
	wall.height_m = height
	wall.style = biome_style
	return wall


## The line's length, metres, counting the closing side of a closed wall.
func length_m() -> float:
	var total := 0.0
	for k in range(1, points.size()):
		total += points[k - 1].distance_to(points[k])
	if closed and points.size() > 2:
		total += points[points.size() - 1].distance_to(points[0])
	return total


func is_fence() -> bool:
	return kind == Kind.FENCE


func is_building() -> bool:
	return kind == Kind.BUILDING


func is_row() -> bool:
	return kind == Kind.ROW


## The line's bounding rectangle in map XZ (empty for no points).
func bounds() -> Rect2:
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box


## A copy (the point array is copied, so editing one never moves the other).
func copy() -> Wall:
	var copied := make(id, kind, points.duplicate(), closed, height_m, style)
	copied.seed_value = seed_value
	copied.side = side
	return copied


## True when `other` holds the same fields.
func same_as(other: Wall) -> bool:
	return (
		other != null
		and other.id == id
		and other.kind == kind
		and other.points == points
		and other.closed == closed
		and other.height_m == height_m
		and other.style == style
		and other.seed_value == seed_value
		and other.side == side
	)
