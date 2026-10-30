class_name StructureDecor
extends RefCounted

## Library plants on a structure's ornaments (card plant_decor, 2026-10-30). procgen's ornaments
## emit anchor records for ivy blankets and flower boxes (ProcgenOrnaments.anchors); a library that
## carries decor assets (catalog entries with `placement.scatter` false and a `mount`: plantgen's
## `Bush_IvyWall_S/M/L` wall climbers and `Flower_WindowPlanter_W08/W12/W16` planters) gets a plant
## on each anchor, and procgen is asked to leave its flat blobs out (`soft: "anchors"`). A library
## without them keeps the blobs: the fallback, and what every structure draws in a test that does
## not ask for decor.
##
## Pure functions: rows in, placements out. The rows are the decor assets AssetStore holds
## (rows_of builds them from a catalog when a library is served); AuthoredStructures turns the
## placements into MultiMeshes. Map and model: docs/systems/structures.md "Decor plants".

const KIND_IVY := "ivy"
const KIND_PLANTER := "planter"
## placement.mount -> the kind of decor, and the anchor kind it goes on.
const MOUNT_KINDS := {"wall": KIND_IVY, "sill": KIND_PLANTER}
const ANCHOR_KINDS := {"ivy": KIND_IVY, "box": KIND_PLANTER}
## A patch smaller than the smallest ivy class scales a plant down, but never below this (uniform).
const MIN_SCALE := 0.75
## A planter is scaled to its box by at most this much either way (uniform).
const PLANTER_SCALE_MIN := 0.8
const PLANTER_SCALE_MAX := 1.25
## Tolerance when a patch is compared with a class: a patch 1 cm over still fits.
const FIT_EPS := 0.01
## A tile an opening covers by at least this share of its area is dropped.
const DROP_COVERED := 0.4
const ID_PREFIX := "decor:"


## The AssetStore id of a library's decor asset `local`.
static func decor_id(library_id: String, local: String) -> String:
	return "%s%s:%s" % [ID_PREFIX, library_id, local]


## The decor rows of a catalog ({id: entry}): {id (decor_id), library, local, kind, group,
## size (Vector2 of placement.size_m), wind_category, file, node}, sorted by id. An entry is decor
## when its placement says `scatter: false`, names a known mount and gives a size and its
## wind_category is not empty.
static func rows_of(library_id: String, catalog: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for local: String in catalog:
		var entry: Variant = catalog[local]
		if not entry is Dictionary or LibraryContracts.scatters(entry):
			continue
		var placement: Variant = (entry as Dictionary).get("placement", {})
		if not placement is Dictionary:
			continue
		var kind: String = MOUNT_KINDS.get(str((placement as Dictionary).get("mount", "")), "")
		var size_m: Variant = (placement as Dictionary).get("size_m")
		if kind == "" or not size_m is Array or (size_m as Array).size() != 2:
			continue
		var size := Vector2(float(size_m[0]), float(size_m[1]))
		if size.x <= 0.0 or size.y <= 0.0:
			continue
		(
			out
			. append(
				{
					"id": decor_id(library_id, local),
					"library": library_id,
					"local": local,
					"kind": kind,
					"group": str((entry as Dictionary).get("group", "")),
					"size": size,
					"wind_category": str((entry as Dictionary).get("wind_category", "")),
					"file": str((entry as Dictionary).get("file", "")),
					"node": str((entry as Dictionary).get("node", "")),
					"sha256": str((entry as Dictionary).get("sha256", "")),
					"bytes": int((entry as Dictionary).get("bytes", 0)),
				}
			)
		)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return out


## True when the palette at `root` serves at least one ivy and one planter asset: only then does a
## structure ask procgen for anchors instead of blobs.
static func available(root: String = PaletteLibrary.DEFAULT_ROOT) -> bool:
	return has_both(AssetStore.decor_rows(root))


## True when `rows` hold an ivy and a planter.
static func has_both(rows: Array[Dictionary]) -> bool:
	var ivy := false
	var planter := false
	for row in rows:
		ivy = ivy or row.kind == KIND_IVY
		planter = planter or row.kind == KIND_PLANTER
	return ivy and planter


## `placed` (ProcgenOrnaments.placed_kinds) plus the kinds that have an anchor: with soft pieces
## left out an ivy blanket or a flower box that found room leaves an anchor and no tag.
static func placed_kinds_with(placed: Array[String], anchors: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = placed.duplicate()
	for anchor in anchors:
		var kind := "ivy" if anchor.get("kind") == "ivy" else "flower_boxes"
		if not out.has(kind):
			out.append(kind)
	return out


## The size classes of `kind` in `rows`: [{size (Vector2), ids (sorted)}], smallest first (ivy by
## area, planters by width). Rows of one `group` are variants of one class.
static func classes_of(rows: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var by_group := {}
	for row in rows:
		if row.kind != kind:
			continue
		var key := str(row.group) if str(row.group) != "" else str(row.size)
		if not by_group.has(key):
			by_group[key] = {"size": row.size, "ids": [] as Array[String]}
		(by_group[key].ids as Array[String]).append(str(row.id))
	var out: Array[Dictionary] = []
	for key: String in by_group:
		var item: Dictionary = by_group[key]
		(item.ids as Array[String]).sort()
		out.append(item)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if kind == KIND_PLANTER:
				return a.size.x < b.size.x
			return a.size.x * a.size.y < b.size.x * b.size.y
	)
	return out


## The smallest ivy class that covers a `width` by `height` patch; the largest when none does.
## {} when there are no ivy classes.
static func ivy_class(classes: Array[Dictionary], width: float, height: float) -> Dictionary:
	for item in classes:
		var size: Vector2 = item.size
		if size.x + FIT_EPS >= width and size.y + FIT_EPS >= height:
			return item
	return classes[classes.size() - 1] if not classes.is_empty() else {}


## The planter class whose width is nearest `width`; {} when there are none.
static func planter_class(classes: Array[Dictionary], width: float) -> Dictionary:
	var best: Dictionary = {}
	var gap := INF
	for item in classes:
		var d := absf(float(item.size.x) - width)
		if d < gap:
			gap = d
			best = item
	return best


## A variant of `ids` for the draw number `salt` of an anchor with `seed_value`: stable across
## peers (integer arithmetic only).
static func variant_of(ids: Array[String], seed_value: int, salt: int) -> String:
	if ids.is_empty():
		return ""
	var h := (seed_value * 73856093) ^ (salt * 19349663)
	return ids[posmod(h, ids.size())]


## The plants for `anchors` (ProcgenOrnaments.anchors dictionaries) from `rows`: [{id (decor_id),
## kind, transform (Transform3D, uniform scale only, in the anchors' frame), anchor (index),
## size (Vector2: the patch the plant stands for), exclusions (rectangles [x0, y0, x1, y1] in the
## PLANT's own frame: x from its centre, y up from its foot, the anchor's openings moved into it;
## the baked asset cannot honour them, they say where glass is for a test and a later runtime
## climber)}]. Ivy: a patch bigger than the largest class is tiled, one with an opening in it is cut
## into columns, and a tile an opening covers by DROP_COVERED is dropped. Planters: the class
## nearest the box's width. Nothing when `rows` lack the kind.
static func placements(anchors: Array[Dictionary], rows: Array[Dictionary]) -> Array[Dictionary]:
	var ivy_classes := classes_of(rows, KIND_IVY)
	var planter_classes := classes_of(rows, KIND_PLANTER)
	var out: Array[Dictionary] = []
	for index in anchors.size():
		var anchor := anchors[index]
		if anchor.get("kind") == "ivy":
			out.append_array(_ivy_placements(anchor, index, ivy_classes))
		elif anchor.get("kind") == "box":
			out.append_array(_planter_placements(anchor, index, planter_classes))
	return out


static func _ivy_placements(
	anchor: Dictionary, index: int, classes: Array[Dictionary]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if classes.is_empty():
		return out
	var width := float(anchor.width)
	var height := float(anchor.height)
	var largest: Vector2 = classes[classes.size() - 1].size
	var open: Array = anchor.get("exclusions", [])
	var cols := maxi(1, ceili(width / largest.x - FIT_EPS))
	var rows := maxi(1, ceili(height / largest.y - FIT_EPS))
	if not open.is_empty():
		# The baked plants cannot leave a window clear, so a patch with an opening in it is cut into
		# columns of the smallest class's width: the columns the opening covers are dropped and the
		# rest hang beside it.
		var smallest: Vector2 = classes[0].size
		cols = maxi(cols, ceili(width / smallest.x - FIT_EPS))
	var tile_w := width / cols
	var tile_h := height / rows
	var chosen := ivy_class(classes, tile_w, tile_h)
	var size: Vector2 = chosen.size
	# The larger ratio: a narrow column of a tall patch keeps its height (it may overlap its
	# neighbours), a squat one keeps its width.
	var scale := clampf(maxf(tile_w / size.x, tile_h / size.y), MIN_SCALE, 1.0)
	for row in rows:
		for col in cols:
			var centre_x := -width * 0.5 + (col + 0.5) * tile_w
			var foot_y := row * tile_h
			var tile_open := _shifted(open, centre_x, foot_y)
			if _covered(tile_open, tile_w, tile_h):
				continue
			var origin: Vector3 = (
				anchor.origin
				+ (anchor.along as Vector3) * centre_x
				+ (anchor.up as Vector3) * foot_y
			)
			(
				out
				. append(
					{
						"id": variant_of(chosen.ids, int(anchor.get("seed", 0)), row * cols + col),
						"kind": KIND_IVY,
						"transform": _frame(anchor, origin, scale),
						"anchor": index,
						"size": Vector2(tile_w, tile_h),
						"exclusions": tile_open,
					}
				)
			)
	return out


static func _planter_placements(
	anchor: Dictionary, index: int, classes: Array[Dictionary]
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var chosen := planter_class(classes, float(anchor.width))
	if chosen.is_empty():
		return out
	var size: Vector2 = chosen.size
	var scale := clampf(float(anchor.width) / size.x, PLANTER_SCALE_MIN, PLANTER_SCALE_MAX)
	(
		out
		. append(
			{
				"id": variant_of(chosen.ids, int(anchor.get("seed", 0)), 0),
				"kind": KIND_PLANTER,
				"transform": _frame(anchor, anchor.origin, scale),
				"anchor": index,
				"size": Vector2(float(anchor.width), float(anchor.height)),
				"exclusions": [] as Array,
			}
		)
	)
	return out


## The frame of an anchor at `origin`: x along the wall, y up, z out of it, uniformly scaled.
static func _frame(anchor: Dictionary, origin: Vector3, scale: float) -> Transform3D:
	var basis := Basis(anchor.along, anchor.up, anchor.normal)
	return Transform3D(basis.scaled(Vector3.ONE * scale), origin)


## The rectangles `open` moved so their origin is a tile's centre-foot (x - dx, y - dy).
static func _shifted(open: Array, dx: float, dy: float) -> Array:
	var out: Array = []
	for rect: Variant in open:
		var r: Array = rect
		out.append([float(r[0]) - dx, float(r[1]) - dy, float(r[2]) - dx, float(r[3]) - dy])
	return out


## True when one rectangle of `open` covers at least DROP_COVERED of the tile (-w/2..w/2 by 0..h).
static func _covered(open: Array, tile_w: float, tile_h: float) -> bool:
	for r: Array in open:
		var x := minf(float(r[2]), tile_w * 0.5) - maxf(float(r[0]), -tile_w * 0.5)
		var y := minf(float(r[3]), tile_h) - maxf(float(r[1]), 0.0)
		if x > 0.0 and y > 0.0 and x * y >= DROP_COVERED * tile_w * tile_h:
			return true
	return false
