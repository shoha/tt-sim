class_name Crossing
extends RefCounted

## One authored way over water in a MapDocument (`MapDocument.crossings`, phase 4b): a plank
## footbridge, a line of stepping stones or a stone arch bridge (phase 4d) laid between two
## bank anchors. The geometry is built from these fields alone (CrossingGeometry), so a
## crossing ships as data in the document and every peer builds the same one. Summary:
## docs/systems/crossings.md.
##
## `start` and `end` are the bank anchors in map XZ (Vector2(x, z), metres, the frame of
## MapDocument.world_to_sample()): where the crossing meets dry ground on each side
## (CrossingPlacement snaps a drawn line to them). `levels` is the walking surface's height
## at the start, the middle and the end (x, y, z of a Vector3, metres, the frame of
## MapDocument.heights): a deck (plank or arch) rises from the start level through the middle
## one to the end level on a quadratic arch (CrossingGeometry.deck_y); stepping stones put
## their tops at the middle level (just above the water) and rise to the bank levels only
## where the ground itself rises under them.
##
## `width_m` is a deck's width, or a stepping stone's typical diameter. `style` is the
## palette biome id whose materials the crossing takes (its cliff rock for stones and the
## arch's masonry, its first paved path for the arch's deck, a tint of the planks for its
## climate), or "" for the defaults; an id the palette lacks falls back the same way. `id` is
## stable for the crossing's lifetime (1..MAX_ID, unique in the document) and seeds its
## variation (plank jitter, stone shapes, facet shade) with the map seed.

enum Kind { PLANK, STONES, ARCH }

## The names Kind takes in crossings.json.
const KIND_NAMES: Array[String] = ["plank", "stones", "arch"]
const MAX_ID := 255
## Deck width (plank, arch) or stone size (stones) range, metres, per Kind.
const MIN_WIDTH_M: Array[float] = [0.8, 0.4, 1.2]
const MAX_WIDTH_M: Array[float] = [3.0, 1.2, 3.0]
## Stones default near their largest: at 1.05 m they read small at the home zoom (P4b-2).
const DEFAULT_WIDTH_M: Array[float] = [1.5, 1.15, 2.0]
## Anchor to anchor, metres. Shorter is not a crossing; longer needs piers nobody drew.
const MIN_SPAN_M := 0.5
const MAX_SPAN_M := 24.0
## The middle level may sit at most this far from the ends' mean (an arch's rise, or stones
## below banks).
const MAX_RISE_M := 4.0

var id: int = 0
var kind: Kind = Kind.PLANK
var start: Vector2 = Vector2.ZERO
var end: Vector2 = Vector2.ZERO
## Walking surface height at the start, the middle and the end.
var levels: Vector3 = Vector3.ZERO
var width_m: float = 1.5
## Palette biome id for the materials, or "".
var style: String = ""


static func make(
	crossing_id: int,
	crossing_kind: Kind,
	from: Vector2,
	to: Vector2,
	heights: Vector3,
	width: float,
	biome_style: String = ""
) -> Crossing:
	var crossing := Crossing.new()
	crossing.id = crossing_id
	crossing.kind = crossing_kind
	crossing.start = from
	crossing.end = to
	crossing.levels = heights
	crossing.width_m = width
	crossing.style = biome_style
	return crossing


## Anchor to anchor, metres.
func span_m() -> float:
	return start.distance_to(end)


## Unit direction from the start anchor to the end one (Vector2.ZERO for a zero span).
func direction() -> Vector2:
	var d := end - start
	return d / d.length() if d.length() > 0.0 else Vector2.ZERO


## True for a plank footbridge (wood, pile bents; the question "is it planks").
func is_plank() -> bool:
	return kind == Kind.PLANK


## True for a stone arch bridge.
func is_arch() -> bool:
	return kind == Kind.ARCH


## True when the crossing has a walking deck on deck_y (plank or arch): the deck collision
## strip, the grid's deck field, the deck level rule and the plank clearances apply.
func is_deck() -> bool:
	return kind == Kind.PLANK or kind == Kind.ARCH


## A copy (Vector types are values; kept for symmetry with WaterBody.copy()).
func copy() -> Crossing:
	return make(id, kind, start, end, levels, width_m, style)


## True when `other` holds the same fields.
func same_as(other: Crossing) -> bool:
	return (
		other != null
		and other.id == id
		and other.kind == kind
		and other.start == start
		and other.end == end
		and other.levels == levels
		and other.width_m == width_m
		and other.style == style
	)
