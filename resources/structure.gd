class_name Structure
extends RefCounted

## One authored structure (a building) in a MapDocument (`MapDocument.structures`): a library
## recipe plus the author's inputs, never a baked mesh and never a transform. Every peer builds
## the same building from these fields and the document's ground (the figurine and wall
## precedent), so the record is all that is saved and synced. Summary: docs/systems/structures.md.
##
## `recipe` is `<library id>:<structure id>`, the cross-library reference grammar. `footprint` is
## the closed plan polygon in map XZ metres (the frame of Wall.points); its edge 0, from point 0
## to point 1, is the front and carries the door, so rotation is the point order and position.
## Points are float32 (PackedVector2Array), which survive a JSON round trip bit for bit; the
## editor snaps them to FOOTPRINT_STEP_M. `seed_value` is stored, not derived, so a copy keeps
## its look and no peer depends on an engine hash. `params` holds only the values that differ
## from the recipe's interface defaults, each a number rounded to PARAM_STEP or a bool (JSON
## float64 does not round-trip bit for bit, so a value is rounded on every write and read).
## `style` is the palette biome id whose rock tints the walls, or "" (as Wall.style). `id` is
## stable for the structure's lifetime (1..MAX_ID, unique in the document).

const MAX_ID := 255
const MIN_POINTS := 3
const MAX_POINTS := 24
const MAX_SEED := 1000000000
## Parameters one structure may override, the longest parameter name, and the largest magnitude
## of a numeric value.
const MAX_PARAMS := 16
const MAX_PARAM_NAME := 32
const MAX_PARAM_ABS := 1000000.0
## Params are rounded to this (the editor's 0.01 step).
const PARAM_STEP := 0.01
## Footprint points snap to this in the editor (1 cm).
const FOOTPRINT_STEP_M := 0.01
## The longest `recipe` reference.
const MAX_RECIPE_LENGTH := 100

var id: int = 0
var recipe: String = ""
var footprint: PackedVector2Array = PackedVector2Array()
var seed_value: int = 0
## Parameter name -> float (rounded to PARAM_STEP) or bool.
var params: Dictionary = {}
var style: String = ""


static func make(
	structure_id: int,
	recipe_ref: String,
	plan: PackedVector2Array,
	seed_number: int = 0,
	overrides: Dictionary = {},
	biome_style: String = ""
) -> Structure:
	var structure := Structure.new()
	structure.id = structure_id
	structure.recipe = recipe_ref
	structure.footprint = plan
	structure.seed_value = seed_number
	structure.params = overrides
	structure.style = biome_style
	return structure


## `value` rounded to PARAM_STEP, the one form a numeric param is stored and written in.
static func round_param(value: float) -> float:
	return snappedf(value, PARAM_STEP)


## The footprint's bounding rectangle in map XZ (empty for no points).
func bounds() -> Rect2:
	if footprint.is_empty():
		return Rect2()
	var box := Rect2(footprint[0], Vector2.ZERO)
	for p in footprint:
		box = box.expand(p)
	return box


## A copy (the point array and the params are copied, so editing one never changes the other).
func copy() -> Structure:
	return make(id, recipe, footprint.duplicate(), seed_value, params.duplicate(), style)


## True when `other` holds the same fields.
func same_as(other: Structure) -> bool:
	return (
		other != null
		and other.id == id
		and other.recipe == recipe
		and other.footprint == footprint
		and other.seed_value == seed_value
		and other.params == params
		and other.style == style
	)
