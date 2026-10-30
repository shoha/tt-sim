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
	assert_true(t.origin.is_equal_approx(Vector3(2.0, 0.5, 3.0)))
	assert_true(t.basis.x.is_equal_approx(Vector3(1, 0, 0)), "x along the wall")
	assert_true(t.basis.y.is_equal_approx(Vector3.UP))
	assert_true(t.basis.z.is_equal_approx(Vector3(0, 0, 1)), "z out of the wall")
	assert_almost_eq(t.basis.get_scale().x, 1.0, 0.0001)


func test_a_plant_is_scaled_uniformly_and_never_below_the_floor() -> void:
	var tiny := StructureDecor.placements([_anchor("ivy", 0.5, 0.4)], _rows())[0]
	var scale: Vector3 = (tiny.transform as Transform3D).basis.get_scale()
	assert_almost_eq(scale.x, StructureDecor.MIN_SCALE, 0.0001)
	assert_almost_eq(scale.y, scale.x, 0.0001)
	assert_almost_eq(scale.z, scale.x, 0.0001)
	var near := StructureDecor.placements([_anchor("ivy", 1.1, 1.1)], _rows())[0]
	var near_scale: Vector3 = (near.transform as Transform3D).basis.get_scale()
	assert_almost_eq(near_scale.x, 1.1 / 1.2, 0.0001, "a patch a little under S scales to fit")


func test_a_patch_bigger_than_the_largest_class_is_tiled() -> void:
	var out := StructureDecor.placements([_anchor("ivy", 5.0, 2.0)], _rows())
	assert_eq(out.size(), 3, "three tiles across, one up")
	var xs: Array[float] = []
	for plant in out:
		xs.append((plant.transform as Transform3D).origin.x)
		assert_true(plant.size.x <= 2.2 + 0.001)
	xs.sort()
	# along is +x: the tiles are centred at -2.5 + (i + 0.5) * 5/3 along it.
	assert_almost_eq(xs[0], 2.0 + (-2.5 + 0.5 * 5.0 / 3.0), 0.001)
	assert_almost_eq(xs[2], 2.0 + (-2.5 + 2.5 * 5.0 / 3.0), 0.001)
	var tall := StructureDecor.placements([_anchor("ivy", 1.0, 5.0)], _rows())
	assert_eq(tall.size(), 2)
	var ys: Array[float] = []
	for plant in tall:
		ys.append((plant.transform as Transform3D).origin.y)
	ys.sort()
	assert_almost_eq(ys[1] - ys[0], 2.5, 0.001, "the second tile starts where the first ends")


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
	assert_eq(rects.size(), 4, "the wall left of it, the band below, the band above, the wall right")
	for i in 4:
		for k in 4:
			assert_almost_eq(float(rects[i][k]), float(want[i][k]), 0.0001, "rect %d edge %d" % [i, k])
	assert_eq(StructureDecor.free_rects(2.0, 1.0, [], 0.2).size(), 1, "no opening: the patch")
	assert_eq(
		StructureDecor.free_rects(1.0, 1.0, [[-0.5, 0.0, 0.5, 1.0]], 0.2).size(), 0, "all covered"
	)
	var door := StructureDecor.free_rects(4.0, 2.6, [[-0.4, 0.0, 0.4, 1.9]], 0.2)
	assert_eq(door.size(), 3, "a door from the foot: both sides and the strip over it")


func test_the_margin_is_more_than_the_leaf_overhang() -> void:
	assert_gt(StructureDecor.OPENING_MARGIN, 0.1, "the baked leaves overhang the patch by 0.1 m")


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


func _overlaps_grown(plant: Dictionary, open: Array, margin: float) -> bool:
	var t: Transform3D = plant.transform
	var extent: Vector2 = plant.extent
	var x0 := t.origin.x - 2.0 - extent.x * 0.5
	var y0 := t.origin.y - 0.5
	for rect: Array in open:
		if (
			x0 + extent.x > float(rect[0]) - margin + 0.0001
			and x0 < float(rect[2]) + margin - 0.0001
			and y0 + extent.y > float(rect[1]) - margin + 0.0001
			and y0 < float(rect[3]) + margin - 0.0001
		):
			return true
	return false


func test_no_plant_reaches_an_opening_grown_by_the_margin() -> void:
	var windows := [[-0.5, 0.8, 0.5, 1.8], [1.2, 0.8, 2.0, 1.8], [-2.2, 0.0, -1.5, 2.0]]
	for width in [2.5, 4.0, 5.0, 7.0]:
		for height in [1.5, 2.5, 3.5]:
			var open := windows.filter(
				func(r: Array) -> bool: return r[0] >= -float(width) * 0.5 and r[2] <= float(width) * 0.5
			)
			var out := StructureDecor.placements([_anchor("ivy", width, height, open)], _rows())
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
	var plain := StructureDecor.placements([_anchor("ivy", 5.0, 2.0)], _rows())
	assert_eq(plain.size(), 3, "no opening: the largest class's tiles")


func test_the_triangle_cap_drops_ivy_first_smallest_then_highest() -> void:
	var anchors: Array[Dictionary] = [
		_anchor("ivy", 5.0, 5.0), _anchor("ivy", 1.1, 1.1), _anchor("box", 1.15, 0.2)
	]
	var placed := StructureDecor.placements(anchors, _rows())
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
	assert_eq(StructureDecor.MAX_TRIANGLES, 3000)


func test_a_planter_takes_the_class_of_its_box_and_sits_at_the_anchor() -> void:
	var out := StructureDecor.placements([_anchor("box", 1.15, 0.2)], _rows())
	assert_eq(out.size(), 1)
	assert_eq(out[0].id, "decor:core:Planter_W12_v0")
	var t: Transform3D = out[0].transform
	assert_true(t.origin.is_equal_approx(Vector3(2.0, 0.5, 3.0)))
	assert_almost_eq(t.basis.get_scale().x, 1.15 / 1.2, 0.0001)
	var huge := StructureDecor.placements([_anchor("box", 3.0, 0.2)], _rows())[0]
	assert_almost_eq(
		(huge.transform as Transform3D).basis.get_scale().x,
		StructureDecor.PLANTER_SCALE_MAX,
		0.0001
	)


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
	assert_eq(rows.size(), 15, "nine ivy and six planters")
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
	assert_eq(
		(plain.anchors as Array).size(), (soft.anchors as Array).size(), "same anchors either way"
	)
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
		assert_almost_eq(float(hit.distance), 0.5, 0.03, "ivy foot within 3 cm of the wall")
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
