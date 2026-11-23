class_name TerraKinds
extends RefCounted
## The kind registry, GDScript side (docs/systems/terraform.md "Kinds"): every primitive kind a
## terrain document may hold, one script each in utils/terraform/kinds/<name>/<name>_kind.gd. The
## native twin is native/src/terra_kinds.h, where each kernel registers itself; test_terra_kinds
## fails when the two disagree on an id, name, stage, shape, header or stride.
##
## A kind script declares NAME (stable, written in the map's kind table), ID (stable, never
## reused: 0 to 8 built in, 9 the sculpt raster, 10 to 15 reserved, 16 up new), STAGE (the
## native stage's name), SHAPE ("stamp", "line" or "water"), HEADER, STRIDE and MIN_ITEMS (its
## float layout: the header, then at least MIN_ITEMS whole items of STRIDE floats), LABEL and
## DEFAULTS for the tool, and static validate(data) -> bool, bounds(data) -> Rect2 (the world box
## it can change; empty for the whole map) and describe() -> String. Phase 2 adds each kind's tool
## to its folder.
##
## A new kind is its folder, its native kernel file and one line in KINDS. Every lookup goes by
## id, so the order of KINDS means nothing.

const Layout := preload("res://utils/terraform/kinds/kind_layout.gd")

## The registry: one line per kind.
const KINDS := [
	preload("res://utils/terraform/kinds/plane/plane_kind.gd"),
	preload("res://utils/terraform/kinds/hill/hill_kind.gd"),
	preload("res://utils/terraform/kinds/ridge/ridge_kind.gd"),
	preload("res://utils/terraform/kinds/stroke/stroke_kind.gd"),
	preload("res://utils/terraform/kinds/river/river_kind.gd"),
	preload("res://utils/terraform/kinds/pond/pond_kind.gd"),
	preload("res://utils/terraform/kinds/path/path_kind.gd"),
	preload("res://utils/terraform/kinds/wall/wall_kind.gd"),
	preload("res://utils/terraform/kinds/paint/paint_kind.gd"),
	preload("res://utils/terraform/kinds/terrace/terrace_kind.gd"),
	preload("res://utils/terraform/kinds/level/level_kind.gd"),
	preload("res://utils/terraform/kinds/sculpt/sculpt_kind.gd"),
]


## The kind script with `id`, or null.
static func script_for(id: int) -> GDScript:
	for k: GDScript in KINDS:
		if k.ID == id:
			return k
	return null


## True when `id` is a registered kind.
static func has(id: int) -> bool:
	return script_for(id) != null


## The stable name of kind `id`, or "" when it is not registered.
static func name_of(id: int) -> String:
	var k := script_for(id)
	return k.NAME if k != null else ""


## Every registered id, ascending.
static func ids() -> Array[int]:
	var out: Array[int] = []
	for k: GDScript in KINDS:
		out.append(k.ID)
	out.sort()
	return out


## The registry as TerraDerive.kinds() gives it: per kind, ascending id, {"id", "name", "stage",
## "shape", "header", "stride"}.
static func table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		var k := script_for(id)
		out.append(
			{
				"id": k.ID,
				"name": k.NAME,
				"stage": k.STAGE,
				"shape": k.SHAPE,
				"header": k.HEADER,
				"stride": k.STRIDE,
			}
		)
	return out


## Why `data` is not a valid primitive of kind `id`, or "": the kind is registered and its
## validate() holds (layout, finite values, its field ranges). Pure; any thread.
static func problem(id: int, data: PackedFloat32Array) -> String:
	var k := script_for(id)
	if k == null:
		return "unknown kind %d" % id
	if k.validate(data):
		return ""
	for v in data:
		if is_nan(v) or is_inf(v) or absf(v) > Layout.MAX_ABS_VALUE:
			return "%s holds a NaN, Inf or out-of-range value" % k.NAME
	if not Layout.fits(data, k.HEADER, k.STRIDE, k.MIN_ITEMS):
		return (
			"%s takes %d header floats and at least %d items of %d, not %d floats"
			% [k.NAME, k.HEADER, k.MIN_ITEMS, k.STRIDE, data.size()]
		)
	return "%s has a field out of its range" % k.NAME
