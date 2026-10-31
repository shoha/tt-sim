extends GutTest

## Library plants on ornament anchors (card plant_decor, 2026-10-30): StructureDecor's pure rules
## (rows from a catalog, size classes, the transform of an anchor, tiling, openings), the climber
## wind category, the decor opt-out of the scatter, the build (anchors in the parts, the blobs left
## out, the fallback when the library lacks the assets, the pinned digests untouched) and a built
## cottage whose plants sit on its wall.
## Summary: docs/systems/structures.md "Decor plants".

const COTTAGE := "core:cottage"
const MANOR := "core:ivy_manor"
const KEEP := "core:castle_keep"

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _entry(group: String, mount: String, size: Array, scatter: bool = false) -> Dictionary:
	return {
		"group": group,
		"file": "assets/x/%s.glb" % group,
		"node": group,
		"wind_category": "climber",
		"placement": {"mount": mount, "origin": "foot_centre", "scatter": scatter, "size_m": size},
	}


func _catalog() -> Dictionary:
	return {
		"Ivy_S_v0": _entry("ivy_s", "wall", [1.2, 1.2]),
		"Ivy_S_v1": _entry("ivy_s", "wall", [1.2, 1.2]),
		"Ivy_M_v0": _entry("ivy_m", "wall", [1.6, 2.0]),
		"Ivy_L_v0": _entry("ivy_l", "wall", [2.2, 2.6]),
		"Planter_W08_v0": _entry("pl_08", "sill", [0.8, 0.4]),
		"Planter_W12_v0": _entry("pl_12", "sill", [1.2, 0.4]),
		"Planter_W16_v0": _entry("pl_16", "sill", [1.6, 0.4]),
		"Oak_v0": {"group": "oak", "file": "a.glb", "node": "oak", "wind_category": "tree"},
		"Bush_v0": _entry("bush", "wall", [1.0, 1.0], true),
	}


func _rows() -> Array[Dictionary]:
	return StructureDecor.rows_of("core", _catalog())


func _anchor(kind: String, width: float, height: float, exclusions: Array = []) -> Dictionary:
	return {
		"kind": kind,
		"origin": Vector3(2.0, 0.5, 3.0),
		"normal": Vector3(0, 0, 1),
		"along": Vector3(1, 0, 0),
		"up": Vector3.UP,
		"width": width,
		"height": height,
		"depth": 0.0 if kind == "ivy" else 0.3,
		"tags": [],
		"seed": 4,
		"exclusions": exclusions,
	}


# --- rows and classes ------------------------------------------------------------------------


func test_rows_are_the_scatter_false_entries_with_a_known_mount() -> void:
	var rows := _rows()
	assert_eq(rows.size(), 7, "seven decor entries; the tree and the scattering bush are not")
	assert_true(StructureDecor.has_both(rows))
	assert_eq(rows[0].id, "decor:core:Ivy_L_v0", "sorted by id")
	assert_false(StructureDecor.has_both([] as Array[Dictionary]))
	var ivy_only := rows.filter(func(r: Dictionary) -> bool: return r.kind == "ivy")
	var typed: Array[Dictionary] = []
	typed.assign(ivy_only)
	assert_false(StructureDecor.has_both(typed), "a planter is needed too")


func test_classes_are_ordered_smallest_first_and_group_the_variants() -> void:
	var ivy := StructureDecor.classes_of(_rows(), "ivy")
	assert_eq(ivy.size(), 3)
	assert_eq(ivy[0].size, Vector2(1.2, 1.2))
	assert_eq((ivy[0].ids as Array).size(), 2, "two variants of the small class")
	assert_eq(ivy[2].size, Vector2(2.2, 2.6))
	var planters := StructureDecor.classes_of(_rows(), "planter")
	assert_almost_eq(float(planters[0].size.x), 0.8, 0.0001)
	assert_almost_eq(float(planters[2].size.x), 1.6, 0.0001)


func test_the_smallest_class_that_covers_the_patch_is_picked() -> void:
	var ivy := StructureDecor.classes_of(_rows(), "ivy")
	assert_eq(StructureDecor.ivy_class(ivy, 1.1, 1.0).size, Vector2(1.2, 1.2))
	assert_eq(StructureDecor.ivy_class(ivy, 1.3, 1.0).size, Vector2(1.6, 2.0), "wider than S")
	assert_eq(StructureDecor.ivy_class(ivy, 1.2, 1.9).size, Vector2(1.6, 2.0), "taller than S")
	assert_eq(StructureDecor.ivy_class(ivy, 2.0, 2.5).size, Vector2(2.2, 2.6))
	assert_eq(
		StructureDecor.ivy_class(ivy, 9.0, 9.0).size, Vector2(2.2, 2.6), "none covers: largest"
	)
	assert_true(StructureDecor.ivy_class([] as Array[Dictionary], 1.0, 1.0).is_empty())


func test_the_planter_class_is_the_nearest_width() -> void:
	var planters := StructureDecor.classes_of(_rows(), "planter")
	assert_almost_eq(float(StructureDecor.planter_class(planters, 0.7).size.x), 0.8, 0.0001)
	assert_almost_eq(float(StructureDecor.planter_class(planters, 1.1).size.x), 1.2, 0.0001)
	assert_almost_eq(float(StructureDecor.planter_class(planters, 2.4).size.x), 1.6, 0.0001)


# --- placements --------------------------------------------------------------------------------


func test_an_ivy_anchor_gives_one_plant_in_the_anchors_frame() -> void:
	var out := StructureDecor.placements([_anchor("ivy", 1.6, 2.0)], _rows())
	assert_eq(out.size(), 1)
	var plant := out[0]
	assert_eq(plant.id, "decor:core:Ivy_M_v0")
	var t: Transform3D = plant.transform
	# Dressed (plant_decor4): within a jitter of its slot, turned only about the wall normal.
	assert_lt(absf(t.origin.x - 2.0), 0.6, "near the slot's centre")
	assert_true(t.basis.z.normalized().is_equal_approx(Vector3(0, 0, 1)), "z out of the wall")
	assert_almost_eq(t.origin.z, 3.0, 0.0001, "the foot stays on the wall plane")
	var turn := t.basis.x.normalized().angle_to(Vector3(1, 0, 0))
	assert_lte(turn, deg_to_rad(StructureDecor.MAX_TURN_DEGREES) + 0.0001, "x along the wall")
	var scale := t.basis.get_scale().x
	assert_between(scale, 0.85 - 0.0001, 1.15 + 0.0001, "scale variation")


func test_a_plant_is_scaled_uniformly_and_never_below_the_floor() -> void:
	var tiny := StructureDecor.placements([_anchor("ivy", 0.5, 0.4)], _rows())[0]
	var scale: Vector3 = (tiny.transform as Transform3D).basis.get_scale()
	assert_gte(scale.x, StructureDecor.MIN_SCALE - 0.0001)
	assert_almost_eq(scale.y, scale.x, 0.0001)
	assert_almost_eq(scale.z, scale.x, 0.0001)
	var near := StructureDecor.placements([_anchor("ivy", 1.1, 1.1)], _rows())[0]
	var near_scale: Vector3 = (near.transform as Transform3D).basis.get_scale()
	assert_between(near_scale.x, 1.1 / 1.2 * 0.85 - 0.001, 1.1 / 1.2 * 1.15 + 0.001, "near its fit")


func test_a_patch_bigger_than_the_largest_class_is_tiled() -> void:
	var out := StructureDecor.placements([_anchor("ivy", 5.0, 2.0)], _rows())
	assert_eq(out.size(), 3, "three tiles across, one up")
	var xs: Array[float] = []
	for plant in out:
		xs.append((plant.transform as Transform3D).origin.x)
		assert_true(plant.size.x <= 2.2 + 0.001)
	xs.sort()
	# along is +x: the tiles are centred at -2.5 + (i + 0.5) * 5/3 along it, then dressed.
	assert_almost_eq(xs[0], 2.0 + (-2.5 + 0.5 * 5.0 / 3.0), 0.5)
	assert_almost_eq(xs[2], 2.0 + (-2.5 + 2.5 * 5.0 / 3.0), 0.5)
	var tall := StructureDecor.placements([_anchor("ivy", 1.0, 5.0)], _rows())
	assert_eq(tall.size(), 2)
	var ys: Array[float] = []
	for plant in tall:
		ys.append((plant.transform as Transform3D).origin.y)
	ys.sort()
	assert_almost_eq(ys[1] - ys[0], 2.5, 1.0, "the second tile starts about where the first ends")


func _sorted_rects(rects: Array) -> Array:
	var out := rects.duplicate()
	out.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])
	)
	return out


func test_free_rects_are_the_patch_minus_the_grown_openings() -> void:
	var window := [-0.5, 0.8, 0.5, 1.8]
	var rects := _sorted_rects(StructureDecor.free_rects(5.0, 2.5, [window], 0.2))
	# The window grown by 0.2: x -0.7..0.7, y 0.6..2.0.
	var want := [
		[-2.5, 0.0, -0.7, 2.5], [-0.7, 0.0, 0.7, 0.6], [-0.7, 2.0, 0.7, 2.5], [0.7, 0.0, 2.5, 2.5]
	]
	assert_eq(
		rects.size(), 4, "the wall left of it, the band below, the band above, the wall right"
	)
	for i in 4:
		for k in 4:
			assert_almost_eq(
				float(rects[i][k]), float(want[i][k]), 0.0001, "rect %d edge %d" % [i, k]
			)
	assert_eq(StructureDecor.free_rects(2.0, 1.0, [], 0.2).size(), 1, "no opening: the patch")
	assert_eq(
		StructureDecor.free_rects(1.0, 1.0, [[-0.5, 0.0, 0.5, 1.0]], 0.2).size(), 0, "all covered"
	)
	var door := StructureDecor.free_rects(4.0, 2.6, [[-0.4, 0.0, 0.4, 1.9]], 0.2)
	assert_eq(door.size(), 3, "a door from the foot: both sides and the strip over it")


func test_the_margin_lets_a_leaf_cross_a_frame_slightly() -> void:
	# The baked leaves overhang their patch by about 0.1 m: the owner asked for leaves that cross
	# a frame slightly (2026-10-30), so the margin is a few centimetres.
	assert_between(StructureDecor.OPENING_MARGIN, 0.02, 0.05, "about 0.03 m")
	assert_almost_eq(StructureDecor.FIT_MIN_SCALE, 0.6, 0.0001, "no plant is shrunk to a scrap")


func _shaped_catalog() -> Dictionary:
	var out := _catalog()
	out["Strip_N_v0"] = _entry("strip_n", "wall", [0.5, 2.2])
	out["Strip_W_v0"] = _entry("strip_w", "wall", [0.8, 2.2])
	out["Strip_W_v1"] = _entry("strip_w", "wall", [0.8, 2.2])
	out["Band_S_v0"] = _entry("band_s", "wall", [1.2, 0.5])
	out["Band_M_v0"] = _entry("band_m", "wall", [1.8, 0.6])
	return out


func _shaped_rows() -> Array[Dictionary]:
	return StructureDecor.rows_of("core", _shaped_catalog())


# Two windows 1.0 m apart on a 3 m by 2.5 m wall: a pier between them, bands under and over.
func _pier_windows() -> Array:
	return [[-1.5, 0.5, -0.6, 2.0], [0.6, 0.5, 1.5, 2.0]]


func test_shapes_follow_the_aspect_of_the_patch() -> void:
	assert_eq(StructureDecor.shape_of(Vector2(0.5, 2.2)), StructureDecor.SHAPE_STRIP)
	assert_eq(StructureDecor.shape_of(Vector2(0.8, 2.2)), StructureDecor.SHAPE_STRIP)
	assert_eq(StructureDecor.shape_of(Vector2(1.2, 0.5)), StructureDecor.SHAPE_BAND)
	assert_eq(StructureDecor.shape_of(Vector2(1.8, 0.6)), StructureDecor.SHAPE_BAND)
	assert_eq(StructureDecor.shape_of(Vector2(1.2, 1.2)), StructureDecor.SHAPE_SQUARE)
	assert_eq(StructureDecor.shape_of(Vector2(2.2, 2.6)), StructureDecor.SHAPE_SQUARE)
	assert_eq(StructureDecor.shape_for(0.8, 2.5), StructureDecor.SHAPE_STRIP, "tall and narrow")
	assert_eq(StructureDecor.shape_for(3.0, 0.4), StructureDecor.SHAPE_BAND, "wide and short")
	assert_eq(StructureDecor.shape_for(1.6, 2.0), StructureDecor.SHAPE_SQUARE)
	var classes := StructureDecor.classes_of(_shaped_rows(), "ivy")
	assert_eq(StructureDecor.of_shape(classes, StructureDecor.SHAPE_STRIP).size(), 2)
	assert_eq(StructureDecor.of_shape(classes, StructureDecor.SHAPE_BAND).size(), 2)
	assert_eq(StructureDecor.of_shape(classes, StructureDecor.SHAPE_SQUARE).size(), 3)


func test_a_pier_takes_strips_and_a_band_gap_takes_bands() -> void:
	var out := StructureDecor.placements(
		[_anchor("ivy", 3.0, 2.5, _pier_windows())], _shaped_rows()
	)
	var strips := 0
	var bands := 0
	for plant in out:
		var id := str(plant.id)
		var centre_x: float = (plant.transform as Transform3D).origin.x - 2.0
		var foot_y: float = (plant.transform as Transform3D).origin.y - 0.5
		if id.contains("Strip"):
			strips += 1
			assert_true(absf(centre_x) < 0.5, "a strip stands in the pier: %s" % centre_x)
		elif id.contains("Band"):
			bands += 1
			assert_true(foot_y < 0.5 or foot_y >= 2.0 - 0.001, "a band under or over the windows")
	assert_gt(strips, 0, "the pier gets a strip")
	assert_gt(bands, 0, "the bands under and over the windows get a band")


func test_a_plant_beside_an_opening_is_never_shrunk_below_the_floor() -> void:
	for width in [2.5, 3.0, 4.0, 5.0]:
		var out := StructureDecor.placements(
			[_anchor("ivy", width, 2.5, _pier_windows())], _shaped_rows()
		)
		for plant in out:
			var scale: float = (plant.transform as Transform3D).basis.get_scale().x
			assert_gte(
				scale, StructureDecor.FIT_MIN_SCALE - 0.0001, "%s wide: %s" % [width, plant.id]
			)


func test_shaped_plants_never_reach_an_opening_grown_by_the_margin() -> void:
	var windows := [[-0.5, 0.8, 0.5, 1.8], [1.2, 0.8, 2.0, 1.8], [-2.2, 0.0, -1.5, 2.0]]
	for width in [2.5, 3.0, 4.0, 5.0, 7.0]:
		for height in [1.5, 2.5, 3.5]:
			var open := windows.filter(
				func(r: Array) -> bool:
					return r[0] >= -float(width) * 0.5 and r[2] <= float(width) * 0.5
			)
			var out := StructureDecor.placements(
				[_anchor("ivy", width, height, open)], _shaped_rows()
			)
			for plant in out:
				assert_false(
					_overlaps_grown(plant, open, StructureDecor.OPENING_MARGIN),
					"%s x %s: %s at %s" % [width, height, plant.id, plant.transform.origin]
				)


func test_a_pier_is_filled_not_left_to_one_small_plant() -> void:
	var rect := StructureDecor.free_rects(3.0, 2.5, _pier_windows(), StructureDecor.OPENING_MARGIN)
	var pier: Array = []
	for r: Array in rect:
		if float(r[0]) > -0.6 and float(r[2]) < 0.6 and float(r[3]) - float(r[1]) > 2.0:
			pier = r
	assert_false(pier.is_empty(), "the pier is a free rectangle")
	var area := (float(pier[2]) - float(pier[0])) * (float(pier[3]) - float(pier[1]))
	var out := StructureDecor.placements(
		[_anchor("ivy", 3.0, 2.5, _pier_windows())], _shaped_rows()
	)
	var covered := 0.0
	for plant in out:
		var centre_x: float = (plant.transform as Transform3D).origin.x - 2.0
		if absf(centre_x) < 0.6:
			covered += plant.extent.x * plant.extent.y
	assert_gte(covered, area * 0.6, "the pier is at least 60 percent covered")


func test_plants_in_a_rectangle_overlap_by_at_most_the_limit() -> void:
	var out := StructureDecor.placements(
		[_anchor("ivy", 1.0, 6.0, [[-0.5, 5.0, 0.5, 5.5]])], _shaped_rows()
	)
	# One column below the band: dressed plants (each moves up to JITTER of its height either way)
	# are spaced by at least extent less the limit and the two jitters.
	var column: Array = []
	for plant in out:
		if (plant.transform as Transform3D).origin.y - 0.5 < 4.5:
			column.append(plant)
	assert_gt(column.size(), 0)
	# The centres of the turned plants (a plant turns about its centre, so its foot moves).
	var centres: Array[Dictionary] = []
	for plant in column:
		var box := _plant_box(plant)
		centres.append(
			{
				"x": (box[0] + box[2]) * 0.5,
				"y": (box[1] + box[3]) * 0.5,
				"w": plant.extent.x,
				"h": plant.extent.y
			}
		)
	centres.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.y < b.y)
	var stacked := 0
	for i in range(1, centres.size()):
		if absf(centres[i].x - centres[i - 1].x) > 0.5 * float(centres[i - 1].w):
			continue  # side by side, not stacked
		stacked += 1
		var pitch: float = centres[i].y - centres[i - 1].y
		assert_gte(pitch, 0.5 * float(centres[i - 1].h), "stack pitch %s" % pitch)
	assert_gt(stacked, 0, "the probe has stacked plants")


func test_the_shaped_cap_still_holds_the_triangle_cap() -> void:
	var anchors: Array[Dictionary] = [
		_anchor("ivy", 3.0, 2.5, _pier_windows()), _anchor("ivy", 7.0, 3.5, [[-0.5, 0.8, 0.5, 1.8]])
	]
	var placed := StructureDecor.placements(anchors, _shaped_rows())
	var cost := {}
	for plant in placed:
		cost[plant.id] = 400
	var capped := StructureDecor.cap_triangles(placed, cost)
	assert_lte(capped.size() * 400, StructureDecor.MAX_TRIANGLES)
	assert_gt(
		placed.size() * 400, StructureDecor.MAX_TRIANGLES, "the probe is over the cap to start"
	)


func test_exclusions_are_passed_on_in_the_plants_frame() -> void:
	var window := [-0.5, 0.8, 0.5, 1.8]
	var out := StructureDecor.placements([_anchor("ivy", 5.0, 2.5, [window])], _rows())
	assert_gt(out.size(), 0)
	for plant in out:
		var centre_x: float = (plant.transform as Transform3D).origin.x - 2.0
		var foot_y: float = (plant.transform as Transform3D).origin.y - 0.5
		var rect: Array = plant.exclusions[0]
		assert_almost_eq(float(rect[0]), -0.5 - centre_x, 0.001)
		assert_almost_eq(float(rect[3]), 1.8 - foot_y, 0.001)


## The box [x0, y0, x1, y1] (anchor frame of _anchor: x from the centre, y up from the foot) a
## plant covers once turned about its own centre.
func _plant_box(plant: Dictionary) -> Array[float]:
	var t: Transform3D = plant.transform
	var extent: Vector2 = plant.extent
	var angle: float = plant.angle
	var box := StructureDecor.turned_box(extent, 1.0, angle)
	var centre_x := t.origin.x - 2.0 - sin(angle) * extent.y * 0.5
	var centre_y := t.origin.y - 0.5 + cos(angle) * extent.y * 0.5
	return [
		centre_x - box.x * 0.5,
		centre_y - box.y * 0.5,
		centre_x + box.x * 0.5,
		centre_y + box.y * 0.5
	]


func _overlaps_grown(plant: Dictionary, open: Array, margin: float) -> bool:
	var box := _plant_box(plant)
	for rect: Array in open:
		if (
			box[2] > float(rect[0]) - margin + 0.0001
			and box[0] < float(rect[2]) + margin - 0.0001
			and box[3] > float(rect[1]) - margin + 0.0001
			and box[1] < float(rect[3]) + margin - 0.0001
		):
			return true
	return false


func test_no_plant_reaches_an_opening_grown_by_the_margin() -> void:
	var windows := [[-0.5, 0.8, 0.5, 1.8], [1.2, 0.8, 2.0, 1.8], [-2.2, 0.0, -1.5, 2.0]]
	for width in [2.5, 4.0, 5.0, 7.0]:
		for height in [1.5, 2.5, 3.5]:
			var open := windows.filter(
				func(r: Array) -> bool:
					return r[0] >= -float(width) * 0.5 and r[2] <= float(width) * 0.5
			)
			var out := StructureDecor.placements(
				[_anchor("ivy", width, height, open)], _rows(), true
			)
			for plant in out:
				assert_false(
					_overlaps_grown(plant, open, StructureDecor.OPENING_MARGIN),
					(
						"%s x %s: a plant reaches an opening: at %s extent %s open %s"
						% [width, height, plant.transform.origin, plant.extent, open]
					)
				)


func test_a_wall_beside_a_window_keeps_plants_and_a_squeezed_gap_stays_bare() -> void:
	var window := [-0.5, 0.8, 0.5, 1.8]
	var beside := StructureDecor.placements([_anchor("ivy", 5.0, 2.5, [window])], _rows())
	var xs := beside.map(
		func(p: Dictionary) -> float: return (p.transform as Transform3D).origin.x - 2.0
	)
	assert_true(xs.any(func(x: float) -> bool: return x < -0.7), "ivy left of the window")
	assert_true(xs.any(func(x: float) -> bool: return x > 0.7), "ivy right of it")
	var squeezed := StructureDecor.placements(
		[_anchor("ivy", 1.0, 1.0, [[-0.3, 0.2, 0.3, 0.8]])], _rows()
	)
	assert_eq(squeezed.size(), 0, "no room left around it")
	var plain := _main_layer(StructureDecor.placements([_anchor("ivy", 5.0, 2.0)], _rows()))
	assert_eq(plain.size(), 3, "no opening: the largest class's tiles")


func test_the_triangle_cap_drops_ivy_first_smallest_then_highest() -> void:
	var anchors: Array[Dictionary] = [
		_anchor("ivy", 5.0, 5.0), _anchor("ivy", 1.1, 1.1), _anchor("box", 1.15, 0.2)
	]
	var placed := _main_layer(StructureDecor.placements(anchors, _rows()))
	var cost := {}
	for plant in placed:
		cost[plant.id] = 1000
	var total := placed.size() * 1000
	assert_eq(StructureDecor.cap_triangles(placed, cost, total).size(), placed.size(), "under")
	var capped := StructureDecor.cap_triangles(placed, cost, total - 1)
	assert_eq(capped.size(), placed.size() - 1)
	assert_eq(capped.filter(func(p: Dictionary) -> bool: return p.kind == "planter").size(), 1)
	var ivy := placed.filter(func(p: Dictionary) -> bool: return p.kind == "ivy")
	ivy.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a.extent.x * a.extent.y < b.extent.x * b.extent.y
	)
	assert_false(capped.has(ivy[0]), "the smallest ivy patch went first")
	assert_eq(StructureDecor.cap_triangles(placed, cost, 0).size(), 0, "a cap of 0 drops all")
	assert_eq(StructureDecor.MAX_TRIANGLES, 4500)


func _main_layer(placed: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plant in placed:
		if not bool(plant.get("under", false)):
			out.append(plant)
	return out


func test_an_under_layer_plant_sits_behind_a_smaller_one_inside_the_same_free_rectangle() -> void:
	var anchor := _anchor("ivy", 5.0, 2.5, [[-0.5, 0.8, 0.5, 1.8]])
	var placed := StructureDecor.placements([anchor], _rows(), true)
	var unders :=placed.filter(func(p: Dictionary) -> bool: return bool(p.get("under", false)))
	assert_gt(unders.size(), 0, "the probe has an under-layer")
	assert_lte(unders.size(), _main_layer(placed).size(), "at most one behind each plant")
	for plant in unders:
		var depth: float = 3.0 - (plant.transform as Transform3D).origin.z
		assert_between(
			depth, StructureDecor.UNDER_DEPTH_MIN - 0.0001, StructureDecor.UNDER_DEPTH_MAX + 0.0001
		)
		var scale: float = (plant.transform as Transform3D).basis.get_scale().x
		assert_lte(scale, 1.15 * StructureDecor.UNDER_SCALE + 0.0001, "smaller than a main plant")
	var again := StructureDecor.placements([anchor], _rows(), true)
	assert_eq(placed.size(), again.size(), "deterministic")


func test_the_cap_drops_the_under_layer_before_any_main_plant() -> void:
	var placed := StructureDecor.placements([_anchor("ivy", 5.0, 5.0)], _rows(), true)
	var cost := {}
	for plant in placed:
		cost[plant.id] = 100
	var main := _main_layer(placed).size()
	assert_lt(main, placed.size(), "the probe has unders")
	var capped := StructureDecor.cap_triangles(placed, cost, main * 100)
	assert_eq(capped.size(), main)
	assert_eq(_main_layer(capped).size(), main, "every main plant stayed")


func test_shaded_normals_turn_toward_down_and_stay_unit_length() -> void:
	var out := StructureDecor.shaded_normals(
		PackedVector3Array([Vector3(0, 0, 1), Vector3(0, 0.5, 0.8660254)])
	)
	assert_almost_eq(out[0].length(), 1.0, 0.0001)
	assert_lt(out[0].y, 0.0, "a wall normal now leans down")
	assert_lt(out[1].y, 0.5, "a normal that leaned up leans less")
	assert_gt(out[0].z, 0.5, "still mostly out of the wall")


func test_a_planter_is_drawn_larger_from_a_smaller_class_and_sits_at_the_anchor() -> void:
	var out := StructureDecor.placements([_anchor("box", 1.15, 0.2)], _rows())
	assert_eq(out.size(), 1)
	assert_eq(out[0].id, "decor:core:Planter_W08_v0", "the class nearest width / boost")
	var t: Transform3D = out[0].transform
	assert_true(t.origin.is_equal_approx(Vector3(2.0, 0.5, 3.0)), "anchored at its foot")
	assert_almost_eq(t.basis.get_scale().x, StructureDecor.PLANTER_BOOST, 0.0001)
	assert_almost_eq(t.basis.get_scale().y, t.basis.get_scale().x, 0.0001, "uniform")
	var huge := StructureDecor.placements([_anchor("box", 3.0, 0.2)], _rows())[0]
	assert_almost_eq(
		(huge.transform as Transform3D).basis.get_scale().x,
		StructureDecor.PLANTER_SCALE_MAX,
		0.0001
	)


func test_a_planter_is_never_wider_than_its_window_plus_ten_percent() -> void:
	for width in [0.6, 0.8, 0.95, 1.15, 1.4, 1.8, 3.0]:
		var plant := StructureDecor.placements([_anchor("box", width, 0.2)], _rows())[0]
		var wide: float = plant.extent.x
		var cap: float = width * (1.0 + StructureDecor.PLANTER_OVERHANG)
		# The floor scale of a tiny window may exceed the cap; no real planter box is that small.
		if width >= 0.8:
			assert_lte(wide, cap + 0.0001, "window %s" % width)
		assert_gte(
			(plant.transform as Transform3D).basis.get_scale().x,
			StructureDecor.PLANTER_SCALE_MIN - 0.0001
		)


func _dressed_wall(seed_value: int) -> Array[Dictionary]:
	var anchor := _anchor("ivy", 7.0, 5.2)
	anchor["seed"] = seed_value
	return StructureDecor.placements([anchor], _rows())


func test_dressing_is_deterministic_per_seed_and_changes_with_it() -> void:
	var a := _dressed_wall(4)
	var b := _dressed_wall(4)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].id, b[i].id)
		assert_eq(a[i].transform, b[i].transform)
	var other := _dressed_wall(11)
	var moved := false
	for i in mini(a.size(), other.size()):
		moved = moved or a[i].transform != other[i].transform
	assert_true(moved, "another seed dresses the wall differently")


func test_a_tiled_wall_is_not_a_grid() -> void:
	# 7.0 x 5.2 with no opening: four columns by two tiers of the largest class. The x offsets from
	# the grid columns must vary (variance above 2 cm), and no two plants stacked on each other
	# share an x.
	for seed_value in [1, 4, 9]:
		var out := _dressed_wall(seed_value)
		assert_eq(out.size(), 8, "four columns, two tiers")
		var offsets: Array[float] = []
		for plant in out:
			var x: float = (plant.transform as Transform3D).origin.x - 2.0
			var col := clampi(int(floor((x + 3.5) / 1.75)), 0, 3)
			offsets.append(x - (-3.5 + (col + 0.5) * 1.75))
		var mean := 0.0
		for o in offsets:
			mean += o / offsets.size()
		var variance := 0.0
		for o in offsets:
			variance += (o - mean) * (o - mean) / offsets.size()
		assert_gt(variance, 0.0004, "seed %s: tier x offsets vary" % seed_value)
		for i in out.size():
			for k in range(i + 1, out.size()):
				var pa: Transform3D = out[i].transform
				var pb: Transform3D = out[k].transform
				if absf(pa.origin.y - pb.origin.y) > 1.0 and absf(pa.origin.x - pb.origin.x) < 1.0:
					assert_gt(absf(pa.origin.x - pb.origin.x), 0.01, "stacked plants differ in x")


func test_every_dressed_plant_stays_within_the_turn_and_scale_limits() -> void:
	for seed_value in [1, 4, 9, 16]:
		for plant in _dressed_wall(seed_value):
			var t: Transform3D = plant.transform
			assert_lte(
				absf(float(plant.angle)), deg_to_rad(StructureDecor.MAX_TURN_DEGREES) + 0.0001
			)
			assert_true(
				t.basis.z.normalized().is_equal_approx(Vector3(0, 0, 1)), "turn about the normal"
			)
			var scale := t.basis.get_scale()
			assert_almost_eq(scale.x, scale.y, 0.0001)
			assert_almost_eq(scale.x, scale.z, 0.0001)
			assert_between(scale.x, StructureDecor.MIN_SCALE - 0.0001, 1.15 * 1.0 + 0.0001)
			assert_gte(_plant_box(plant)[1], -0.0001, "no leaf below the ground")


func test_neighbouring_plants_use_different_variants_when_there_are_some() -> void:
	var catalog := _catalog()
	catalog["Ivy_L_v1"] = _entry("ivy_l", "wall", [2.2, 2.6])
	catalog["Ivy_L_v2"] = _entry("ivy_l", "wall", [2.2, 2.6])
	var rows := StructureDecor.rows_of("core", catalog)
	for seed_value in [1, 4, 9]:
		var anchor := _anchor("ivy", 7.0, 5.2)
		anchor["seed"] = seed_value
		var out := StructureDecor.placements([anchor], rows)
		assert_eq(out.size(), 8)
		# Row-major: four columns by two tiers.
		for i in out.size():
			if i % 4 > 0:
				assert_ne(out[i].id, out[i - 1].id, "left neighbour differs")
			if i >= 4:
				assert_ne(out[i].id, out[i - 4].id, "the plant below differs")


func test_variants_follow_the_seed_and_nothing_is_placed_without_assets() -> void:
	var ids: Array[String] = ["a", "b", "c"]
	assert_eq(StructureDecor.variant_of(ids, 5, 1), StructureDecor.variant_of(ids, 5, 1))
	var seen := {}
	for seed_value in 12:
		seen[StructureDecor.variant_of(ids, seed_value, 0)] = true
	assert_gt(seen.size(), 1, "different seeds reach different variants")
	assert_eq(StructureDecor.variant_of([] as Array[String], 1, 1), "")
	assert_true(
		StructureDecor.placements([_anchor("ivy", 1.0, 1.0)], [] as Array[Dictionary]).is_empty()
	)


func test_an_anchor_counts_as_its_placed_kind() -> void:
	var anchors: Array[Dictionary] = [_anchor("ivy", 1, 1), _anchor("box", 1, 0.2)]
	var kinds := StructureDecor.placed_kinds_with([] as Array[String], anchors)
	assert_true(kinds.has("ivy"))
	assert_true(kinds.has("flower_boxes"))
	assert_eq(
		StructureDecor.placed_kinds_with(["vane"] as Array[String], [] as Array[Dictionary]),
		["vane"]
	)


# --- the library -------------------------------------------------------------------------------


func test_climber_is_a_wind_category_with_a_preset() -> void:
	assert_true("climber" in LibraryContracts.WIND_CATEGORIES)
	assert_true("climber" in PaletteLibrary.WIND_CATEGORIES)
	assert_true(WindFoliage.PRESETS.has("climber"))
	var preset: Dictionary = WindFoliage.PRESETS["climber"]
	assert_between(float(preset.sway_amplitude), 0.015, 0.03)
	assert_between(float(preset.flutter_amplitude), 0.02, 0.025)
	assert_between(float(preset.flutter_speed), 4.0, 5.0)
	assert_eq(float(preset.backlight), 0.0)
	assert_eq(LibraryContracts.export_json().contains('"climber"'), true, "the exported contract")


func test_the_placement_key_is_a_known_catalog_key() -> void:
	assert_true("placement" in LibraryContracts.CATALOG_ENTRY_KEYS)
	assert_false(LibraryContracts.scatters({"placement": {"scatter": false}}))
	assert_true(LibraryContracts.scatters({"placement": {"scatter": true}}))
	assert_true(LibraryContracts.scatters({}))
	assert_true(LibraryContracts.scatters({"placement": "bad"}))


func test_the_scatter_never_selects_a_decor_asset() -> void:
	var context := {"library": "core", "catalog": _catalog(), "folder": "", "deps": {}}
	var local := LibraryQuery.candidates(context).map(func(c: Dictionary) -> String: return c.local)
	assert_true("Oak_v0" in local)
	assert_true("Bush_v0" in local, "scatter true is selectable")
	assert_false("Ivy_S_v0" in local)
	assert_false("Planter_W12_v0" in local)
	# The shipped core: no biome's palette holds a decor asset.
	var palette := PaletteLibrary.base_for_serving(PaletteLibrary.DEFAULT_ROOT)
	for asset_id: String in palette.get("assets", {}):
		assert_false(asset_id.contains("IvyWall") or asset_id.contains("WindowPlanter"), asset_id)


func test_the_shipped_core_serves_its_decor_assets() -> void:
	var rows := AssetStore.decor_rows(PaletteLibrary.DEFAULT_ROOT)
	assert_eq(
		rows.size(), 25, "nineteen ivy (nine squares, six strips, four bands) and six planters"
	)
	assert_true(StructureDecor.available())
	for row in rows:
		assert_eq(row.wind_category, "climber")
		var mesh := AssetStore.mesh(str(row.library), str(row.id))
		assert_not_null(mesh, str(row.id))
	assert_false(StructureDecor.available("res://no_such_root"), "no assets: the fallback")
	assert_false(
		AssetStore.assets_of("core").any(func(id: String) -> bool: return id.begins_with("decor:"))
	)


# --- the build ---------------------------------------------------------------------------------


func _built(ref: String, params: Dictionary, decor: bool, seed_value: int = 7) -> Dictionary:
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	return StructureGeometry.build_one(
		_doc, Structure.make(1, ref, plan, seed_value, params), decor
	)


func _dressed() -> Dictionary:
	return StructureOrnaments.with_kinds({}, ["ivy", "flower_boxes"])


func test_anchors_are_in_the_parts_but_not_in_the_digest() -> void:
	var plain := _built(COTTAGE, _dressed(), false)
	var soft := _built(COTTAGE, _dressed(), true)
	assert_false(plain.decor)
	assert_true(soft.decor)
	assert_gt((soft.anchors as Array).size(), 0, "the cottage has room for ivy")
	# Anchors mode (procgen 657a90f) has no blob budget, so the decor switch's enlarged ivy options
	# (StructureOrnaments.DECOR_IVY) now make more patches than the plain build's (6 against 10).
	assert_gt((plain.anchors as Array).size(), 0, "anchors either way")
	assert_gte((soft.anchors as Array).size(), (plain.anchors as Array).size(), "decor adds patches")
	assert_lt(int(soft.triangles), int(plain.triangles), "the blobs are left out")
	assert_true((soft.placed_kinds as Array).has("ivy"))
	assert_true((plain.placed_kinds as Array).has("ivy"))
	var again := _built(COTTAGE, _dressed(), false)
	assert_eq(StructureGeometry.digest_of(plain), StructureGeometry.digest_of(again))
	# Without decor the build is what it always was: the digest of a bare building is unchanged.
	var bare := _built(COTTAGE, {}, true)
	assert_eq(
		StructureGeometry.digest_of(bare), StructureGeometry.digest_of(_built(COTTAGE, {}, false))
	)


func test_a_styles_own_ivy_is_softened_too() -> void:
	var plain := _built(MANOR, {}, false)
	var soft := _built(MANOR, {}, true)
	assert_gt((soft.anchors as Array).size(), 0)
	assert_lt(int(soft.triangles), int(plain.triangles), "ivy_manor's own blobs are left out")
	var kinds := {}
	for anchor: Dictionary in soft.anchors:
		kinds[anchor.kind] = true
	assert_true(kinds.has("ivy"))


func test_the_key_depends_on_the_decor_switch() -> void:
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	var s := Structure.make(1, COTTAGE, plan, 7, _dressed())
	assert_ne(StructureGeometry.key_of(_doc, s), StructureGeometry.key_of(_doc, s, {}, [], true))
	var memo := {}
	var doc := _doc
	doc.structures.append(s)
	assert_ne(
		StructureGeometry.keys_memoised(doc, memo, false)[1],
		StructureGeometry.keys_memoised(doc, memo, true)[1]
	)


func test_a_dressed_cottages_plants_stand_on_its_wall() -> void:
	var parts := _built(COTTAGE, _dressed(), true)
	var anchors: Array[Dictionary] = []
	anchors.assign(parts.anchors)
	var placed := StructureDecor.placements(
		anchors, AssetStore.decor_rows(PaletteLibrary.DEFAULT_ROOT)
	)
	assert_gt(placed.size(), 0)
	var walls: Array = parts.meshes.filter(
		func(m: Dictionary) -> bool: return str(m.role).begins_with("wall")
	)
	assert_gt(walls.size(), 0)
	var checked := 0
	for plant in placed:
		if plant.kind != StructureDecor.KIND_IVY:
			continue
		var t: Transform3D = plant.transform
		var out := t.basis.z.normalized()
		var hit := _wall_distance(walls, t.origin + out * 0.5 + Vector3.UP * 0.4, -out)
		assert_gt(hit.distance, 0.0, "a wall behind the plant")
		# A band under a sill or a strip by a frame may stand beside trim that is proud of the wall.
		assert_almost_eq(float(hit.distance), 0.5, 0.06, "ivy foot within 6 cm of the wall")
		assert_gt(out.dot(hit.normal), 0.99, "the plant faces out of the wall")
		checked += 1
	assert_gt(checked, 0)


## {distance, normal} of the first wall triangle `from` hits along `dir`, distance -1 on a miss.
func _wall_distance(walls: Array, from: Vector3, dir: Vector3) -> Dictionary:
	var best := {"distance": -1.0, "normal": Vector3.ZERO}
	for mesh: Dictionary in walls:
		var arrays: Array = mesh.arrays
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in index.size() / 3:
			var a := verts[index[t * 3]]
			var b := verts[index[t * 3 + 1]]
			var c := verts[index[t * 3 + 2]]
			var hit: Variant = Geometry3D.ray_intersects_triangle(from, dir, a, b, c)
			if hit == null:
				continue
			var d := from.distance_to(hit as Vector3)
			if best.distance < 0.0 or d < float(best.distance):
				var n := (b - a).cross(c - a).normalized()
				best = {"distance": d, "normal": n if n.dot(dir) < 0.0 else -n}
	return best
