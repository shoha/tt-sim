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
## Ivy keeps this far from every opening (card plant_decor2, 2026-10-30): the baked leaves overhang
## their patch by about 0.1 m a side, so a plant stays 0.2 m off a window or door and its leaves
## never reach the glass.
const OPENING_MARGIN := 0.2
## Beside an opening a plant may shrink this far (uniform) to fit the free rectangle; below it the
## plant is left out.
const FIT_MIN_SCALE := 0.4
## Plants stacked in one free rectangle beside an opening, at most, and the cover a taller stack
## must have over a shorter one to be taken.
const MAX_STACK := 3
const FIT_GAIN := 1.15
## The most triangles of plants one structure draws (ivy and planters together). Past it the lowest
## value anchors go first (cap_triangles).
const MAX_TRIANGLES := 3000
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
## climber), extent (Vector2: what the plant covers on the wall, its class size times its scale)}].
## Ivy: a patch bigger than the largest class is tiled; one with an opening in it is cut into the
## free rectangles around the openings grown by OPENING_MARGIN (free_rects), each tiled with the
## biggest class that fits inside it (shrunk to FIT_MIN_SCALE), so no plant's extent meets an
## opening and a rectangle nothing fits in stays bare. Planters: the class nearest the box's width.
## Nothing when `rows` lack the kind.
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
	# A patch with no opening is tiled whole; with openings, each free rectangle around them is
	# tiled on its own and a plant is fitted inside it (the baked leaves cannot be cut around glass).
	var runs: Array = [[-width * 0.5, 0.0, width * 0.5, height]]
	if not open.is_empty():
		runs = free_rects(width, height, open, OPENING_MARGIN)
	var salt := 0
	for run: Array in runs:
		var run_w := float(run[2]) - float(run[0])
		var run_h := float(run[3]) - float(run[1])
		var fit := _fit(classes, run_w, run_h, not open.is_empty())
		if fit.is_empty():
			continue
		var chosen: Dictionary = fit.chosen
		var scale: float = fit.scale
		var cols: int = fit.cols
		var rows: int = fit.rows
		var tile_w := run_w / cols
		var tile_h := run_h / rows
		var size: Vector2 = chosen.size
		for row in rows:
			for col in cols:
				var centre_x := float(run[0]) + (col + 0.5) * tile_w
				var foot_y := float(run[1]) + row * tile_h
				var origin: Vector3 = (
					anchor.origin
					+ (anchor.along as Vector3) * centre_x
					+ (anchor.up as Vector3) * foot_y
				)
				(
					out
					. append(
						{
							"id": variant_of(chosen.ids, int(anchor.get("seed", 0)), salt),
							"kind": KIND_IVY,
							"transform": _frame(anchor, origin, scale),
							"anchor": index,
							"size": Vector2(tile_w, tile_h),
							"extent": size * scale,
							"exclusions": _shifted(open, centre_x, foot_y),
						}
					)
				)
				salt += 1
	return out


## The layout of a `run_w` by `run_h` rectangle: {chosen (class), scale, cols, rows}. Free
## (`bounded` false): tiles of the largest class's size, the smallest class that covers a tile,
## scaled down to it (MIN_SCALE floor), as a plain wall always was. `bounded` (beside an opening):
## the extent of every plant lies inside the rectangle. Columns as the largest class needs, then
## the class and a stack of up to MAX_STACK plants (each shrunk uniformly to fit, at least
## FIT_MIN_SCALE) that cover the most wall; a taller stack must beat a shorter one by FIT_GAIN,
## since a plant costs the same triangles at any scale. {} when nothing fits.
static func _fit(
	classes: Array[Dictionary], run_w: float, run_h: float, bounded: bool
) -> Dictionary:
	var largest: Vector2 = classes[classes.size() - 1].size
	var cols := maxi(1, ceili(run_w / largest.x - FIT_EPS))
	if not bounded:
		var rows := maxi(1, ceili(run_h / largest.y - FIT_EPS))
		var chosen := ivy_class(classes, run_w / cols, run_h / rows)
		var size: Vector2 = chosen.size
		# The larger ratio: a narrow column of a tall patch keeps its height (it may overlap its
		# neighbours), a squat one keeps its width.
		var scale := clampf(maxf(run_w / cols / size.x, run_h / rows / size.y), MIN_SCALE, 1.0)
		return {"chosen": chosen, "scale": scale, "cols": cols, "rows": rows}
	var best: Dictionary = {}
	var best_cover := 0.0
	for rows in range(1, MAX_STACK + 1):
		for item in classes:
			var size: Vector2 = item.size
			var scale := minf(1.0, minf(run_w / cols / size.x, run_h / rows / size.y))
			if scale < FIT_MIN_SCALE:
				continue
			var cover := size.x * size.y * scale * scale * cols * rows
			if best.is_empty() or cover > best_cover * FIT_GAIN:
				best_cover = cover
				best = {"chosen": item, "scale": scale, "cols": cols, "rows": rows}
	return best


## The rectangles [x0, y0, x1, y1] (anchor frame: x from the centre, y up from the foot) of a
## `width` by `height` patch that no opening of `open` ([x0, y0, x1, y1] each) touches once grown
## by `margin` on every side. Sliced by the grown openings' x edges, then the free runs of a slice
## are joined with the neighbouring slice's run when they match, so a wall beside a window is one
## tall rectangle and the bands above and below it are two short ones.
static func free_rects(width: float, height: float, open: Array, margin: float) -> Array:
	var grown: Array = []
	for rect: Array in open:
		var x0 := maxf(float(rect[0]) - margin, -width * 0.5)
		var x1 := minf(float(rect[2]) + margin, width * 0.5)
		var y0 := maxf(float(rect[1]) - margin, 0.0)
		var y1 := minf(float(rect[3]) + margin, height)
		if x1 > x0 and y1 > y0:
			grown.append([x0, y0, x1, y1])
	var xs: Array[float] = [-width * 0.5, width * 0.5]
	for rect: Array in grown:
		xs.append(float(rect[0]))
		xs.append(float(rect[2]))
	xs.sort()
	var out: Array = []
	var live := {}
	for i in xs.size() - 1:
		var a := xs[i]
		var b := xs[i + 1]
		if b - a < 1e-4:
			continue
		var blocked: Array = []
		for rect: Array in grown:
			if float(rect[2]) > a + 1e-6 and float(rect[0]) < b - 1e-6:
				blocked.append([float(rect[1]), float(rect[3])])
		blocked.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var runs: Array = []
		var floor_y := 0.0
		for span: Array in blocked:
			if float(span[0]) - floor_y > 1e-4:
				runs.append([floor_y, float(span[0])])
			floor_y = maxf(floor_y, float(span[1]))
		if height - floor_y > 1e-4:
			runs.append([floor_y, height])
		var next_live := {}
		for run: Array in runs:
			var key := "%.4f,%.4f" % [run[0], run[1]]
			if live.has(key):
				var joined: Array = live[key]
				joined[2] = b
				next_live[key] = joined
			else:
				var made := [a, run[0], b, run[1]]
				out.append(made)
				next_live[key] = made
		live = next_live
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
				"extent": size * scale,
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


## `placed` held to `cap` triangles in all: `cost` maps a plant's id to its triangle count. The
## plants that go first are the lowest value: ivy before planters (a flower box is cheap and the
## best read of a lived-in house), then the smallest area of wall covered, then the highest (the
## least seen from tabletop zoom). The survivors keep their order.
static func cap_triangles(
	placed: Array[Dictionary], cost: Dictionary, cap: int = MAX_TRIANGLES
) -> Array[Dictionary]:
	var total := 0
	for plant in placed:
		total += int(cost.get(plant.id, 0))
	if total <= cap:
		return placed
	var order: Array[int] = []
	for i in placed.size():
		order.append(i)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var pa := placed[a]
			var pb := placed[b]
			var ka := 1 if pa.kind == KIND_PLANTER else 0
			var kb := 1 if pb.kind == KIND_PLANTER else 0
			if ka != kb:
				return ka < kb
			var area_a := _area_of(pa)
			var area_b := _area_of(pb)
			if not is_equal_approx(area_a, area_b):
				return area_a < area_b
			var ya := (pa.transform as Transform3D).origin.y
			var yb := (pb.transform as Transform3D).origin.y
			if not is_equal_approx(ya, yb):
				return ya > yb
			return a < b
	)
	var dropped := {}
	for i in order:
		if total <= cap:
			break
		total -= int(cost.get(placed[i].id, 0))
		dropped[i] = true
	var out: Array[Dictionary] = []
	for i in placed.size():
		if not dropped.has(i):
			out.append(placed[i])
	return out


static func _area_of(plant: Dictionary) -> float:
	var extent: Vector2 = plant.get("extent", plant.size)
	return extent.x * extent.y
