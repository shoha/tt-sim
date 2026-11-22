extends GutTest

## The one snow builder over procgen's snow-top records (card snow-tops-builder; docs/systems/
## painter.md "One snow builder"): a body per record kind, a street's one body per lot, a body that
## rides with its asset, no snow without the switch, and an eave that clears the windows.

const SUMMER := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const WINTER := {"sheet": "core", "mood": "winter", "elevation": 45.0}


## A gable half: eave along x at y 3, rising to a ridge 2.5 m back (toward -z), 6 m long.
static func _slope(id: String, lot: String = "") -> Dictionary:
	var o := Vector3(-3.0, 3.0, 0.0)
	var v := Vector3(0.0, 1.0, -1.0).normalized()
	var u := Vector3.RIGHT
	var n := u.cross(v).normalized()
	if n.y < 0.0:
		n = -n
	var vl := 2.5
	var rec := {
		"id": id,
		"kind": "roof_slope",
		"material": "tile",
		"origin": o,
		"u": u,
		"v": v,
		"n": n,
		"u_len": 6.0,
		"v_len": vl,
		"edges":
		[
			{"kind": "eave", "a": o, "b": o + u * 6.0},
			{"kind": "verge", "a": o, "b": o + v * vl},
			{"kind": "verge", "a": o + u * 6.0, "b": o + u * 6.0 + v * vl},
			{"kind": "ridge", "a": o + v * vl, "b": o + u * 6.0 + v * vl},
		],
	}
	if lot != "":
		rec["lot"] = lot
	return rec


static func _cone() -> Dictionary:
	var ring: Array = []
	for i in 8:
		var a := TAU * i / 8.0
		ring.append(Vector3(cos(a) * 2.6, 2.4, sin(a) * 2.6))
	return {
		"id": "roof_round_3/cone",
		"kind": "roof_cone",
		"material": "thatch",
		"base": Vector3(0.0, 2.4, 0.0),
		"origin": Vector3(0.0, 2.4, 0.0),
		"apex": Vector3(0.0, 4.6, 0.0),
		"axis": Vector3.UP,
		"ring": ring,
		"sides": 8,
		"radius": 2.6,
		"apothem": 2.4,
		"wall_y": 2.6,
		"wall_apothem": 2.2,
		"rise": 2.0,
		"power": 1.3,
		"cap": 0.0,
		"up": 0.75,
	}


static func _coping() -> Dictionary:
	return {
		"id": "stone_wall_1/coping_line/run0",
		"kind": "coping_line",
		"material": "stone",
		"points": [Vector3(0, 1.0, 0), Vector3(2, 1.0, 0), Vector3(2, 1.1, 0), Vector3(4, 1.1, 0)],
		"u": Vector3.RIGHT,
		"width": 0.5,
		"height": 0.12,
		"length": 4.0,
	}


static func _pad(shape: String, at: Vector3) -> Dictionary:
	return {
		"id": "prop_1/prop/barrel/top0",
		"kind": "pad",
		"shape": shape,
		"centre": at,
		"origin": at - Vector3(0.3, 0.0, 0.25),
		"u": Vector3.RIGHT,
		"v": Vector3.BACK,
		"n": Vector3.UP,
		"u_len": 0.6,
		"v_len": 0.5,
		"radius": 0.3,
	}


static func _built(records: Array) -> Dictionary:
	var by_id := {}
	for rec: Dictionary in records:
		by_id[str(rec["id"])] = rec
	var src := PainterMannerSnow.source(by_id, {}, PackedStringArray(), {})
	return PainterMannerSnow.build(src)


func test_each_record_kind_gets_a_body() -> void:
	var cases := {
		"blanket": [_slope("roof_gable_1/slope/s0")],
		"cone": [_cone()],
		"coping": [_coping()],
		"top": [_pad("rect", Vector3(0, 1, 0))],
	}
	for kind: String in cases:
		var built := _built(cases[kind])
		assert_gt(int(built.by_kind[kind]), 0, "%s laid" % kind)
		assert_false((built.arrays as Array).is_empty(), "%s has arrays" % kind)
	var disc := _built([_pad("disc", Vector3(0, 1, 0))])
	assert_gt(int(disc.by_kind.top), 0, "a disc pad too")
	var tiny := _pad("disc", Vector3.ZERO)
	tiny["radius"] = 0.02
	assert_eq(int(_built([tiny]).by_kind.top), 0, "a top too small holds none")


func test_the_cone_follows_its_profile_and_closes_at_the_apex() -> void:
	var cone := _cone()
	var at_eave := PainterSnowForms.cone_profile(cone, 2.6)
	var at_apex := PainterSnowForms.cone_profile(cone, 0.0)
	assert_almost_eq(at_eave.x, 2.4, 0.01, "pinned to the eave ring")
	assert_almost_eq(at_apex.x, 4.6, 0.01, "and to the apex")
	var built := _built([cone])
	var verts: PackedVector3Array = built.arrays[Mesh.ARRAY_VERTEX]
	var top := -INF
	for p in verts:
		top = maxf(top, p.y)
	assert_between(top, 4.6, 5.0, "one point a little over the apex")


func test_the_cone_sits_on_its_roof_and_shows_its_edge() -> void:
	var cone := _cone()
	cone["thickness"] = 0.2
	var verts: PackedVector3Array = _built([cone]).arrays[Mesh.ARRAY_VERTEX]
	var reach := 0.0
	var low := INF
	for p in verts:
		reach = maxf(reach, Vector2(p.x, p.z).length())
		low = minf(low, p.y)
	# The ring (2.6) already carries the overhang: the lip adds a few centimetres, no cushion.
	assert_lt(reach, 2.6 + PainterSnowForms.LIP_M * 1.5 + 0.02, "the rim stays at the eave")
	assert_gt(low, 2.4 - 0.2 * PainterSnowForms.RIM_SHARE - 0.01, "the roof's edge shows under it")


func test_a_street_gives_one_body_per_lot() -> void:
	var records := [
		_slope("row_1/left/lot0/roof_gable_1/slope/s0", "left/lot0"),
		_slope("row_1/left/lot1/roof_gable_1/slope/s0", "left/lot1"),
		_coping(),
	]
	var bodies := PainterSnowTops.bodies_of(records)
	assert_eq(bodies.size(), 3, "two lots and the free-standing run")
	var lots := []
	for b: Dictionary in bodies:
		lots.append(str(b.lot))
	assert_eq(lots, ["", "left/lot0", "left/lot1"])


func test_a_real_street_and_wall_bring_their_records() -> void:
	StructureRecipes.ensure_served()
	var doc := MapDocument.create_flat(Vector2i(60, 60), "grass", "v", 9)
	var street := Wall.make(
		7, Wall.Kind.ROW, PackedVector2Array([Vector2(-14, 0), Vector2(14, 0)]), false, 3.0
	)
	street.side = ProcgenRow.SIDE_BOTH
	street.preset = ProcgenRow.PRESET_MIXED
	street.seed_value = 5
	var parts := WallGeometry.build_one(doc, street, true)
	var tops: Array = parts.get("snow_tops", [])
	assert_gt(tops.size(), 0, "a street evaluated with the manner data keeps its lots' records")
	var bodies := PainterSnowTops.bodies_of(tops)
	var lots := WallGeometry.row_lots(doc, street)
	assert_eq(bodies.size(), lots.size(), "one body per standing lot")
	for rec: Dictionary in tops:
		assert_false(rec.has("_surface"), "no evaluator keys kept")
	var plain := WallGeometry.build_one(doc, street)
	assert_false(plain.has("snow_tops"), "no records without the switch")
	assert_eq(
		(plain.roof[Mesh.ARRAY_VERTEX] as PackedVector3Array),
		(parts.roof[Mesh.ARRAY_VERTEX] as PackedVector3Array),
		"the mesh is the same either way"
	)
	var wall := Wall.make(
		8, Wall.Kind.STONE, PackedVector2Array([Vector2(-6, 10), Vector2(6, 10)]), false, 1.2
	)
	var copings := 0
	for rec: Dictionary in WallGeometry.build_one(doc, wall, true).get("snow_tops", []):
		copings += 1 if str(rec.kind) == "coping_line" else 0
	assert_gt(copings, 0, "a stone wall declares its coping runs")


func test_a_round_hut_declares_a_cone_and_gets_its_body() -> void:
	StructureRecipes.ensure_served()
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var plan := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		plan.append(Vector2(cos(a), sin(a)) * 2.5)
	var record := Structure.make(1, "core:round_hut", plan, 5)
	var feed := PainterMannerSource.evaluate(doc, record, false)
	assert_false(feed.is_empty(), "the hut has records")
	var src := PainterMannerSnow.source(feed.records, feed.meshes, feed.table, {})
	assert_gt((src.cones as Array).size(), 0, "a cone record")
	var built := PainterMannerSnow.build(src)
	assert_gt(int(built.by_kind.cone), 0, "and its one grid")


func test_a_moved_cell_keeps_its_body() -> void:
	var cell := MeshInstance3D.new()
	cell.set_meta(AuthoredSettlements.SNOW_TOPS_META, [_pad("disc", Vector3(1, 0.8, 1))])
	add_child_autofree(cell)
	var tops := PainterSnowTops.new()
	var material := ShaderMaterial.new()
	tops.dress_cell(cell, material)
	await wait_until(func() -> bool: return not tops.busy(), 10.0)
	assert_eq(tops.builds, 1, "one body")
	var body := cell.get_node_or_null(PainterSnowTops.NODE) as MeshInstance3D
	assert_not_null(body, "a child of its cell")
	cell.position = Vector3(5.0, 0.0, -3.0)
	tops.dress_cell(cell, material)
	await wait_frames(2)
	assert_eq(tops.builds, 1, "nothing built again when it moves")
	assert_eq(cell.get_node_or_null(PainterSnowTops.NODE), body, "the same body rides with it")
	PainterSnowTops.enabled = false
	assert_eq(tops.shown(), 1, "the A/B switch reaches the body laid")
	assert_false(body.visible, "and hides it")
	var other := MeshInstance3D.new()
	other.set_meta(AuthoredSettlements.SNOW_TOPS_META, [_pad("disc", Vector3(1, 0.8, 1))])
	add_child_autofree(other)
	tops.dress_cell(other, material)
	assert_false(tops.busy(), "and lays no new one")
	PainterSnowTops.enabled = true
	tops.shown()
	assert_true(body.visible, "on again")
	tops.clear()


func test_no_snow_switch_builds_nothing() -> void:
	var sheet := PainterSheet.load_sheet("core")
	assert_eq(PainterBuildings.snow_switch(sheet, "summer", 45.0), 0.0, "summer is off")
	assert_eq(PainterBuildings.snow_switch(sheet, "winter", 45.0), 1.0, "winter is on, whole")
	var buildings := PainterBuildings.new()
	buildings.applied = SUMMER.duplicate()
	assert_false(buildings.snow_on())
	var cell := MeshInstance3D.new()
	cell.set_meta(AuthoredSettlements.SNOW_TOPS_META, [_pad("rect", Vector3.ZERO)])
	add_child_autofree(cell)
	buildings._snow_cell(cell)
	assert_false(buildings.snow_tops.busy(), "nothing asked for")
	assert_eq(buildings.snow_tops.laid().size(), 0, "no body without roof snow")
	buildings.applied = WINTER.duplicate()
	assert_true(buildings.snow_on())


func test_the_eave_never_hangs_below_a_window_top() -> void:
	var slope := _slope("roof_gable_1/slope/s0")
	# A wall face under the eave (at z = -0.4, 0.4 m in from the eave's edge) whose window top lies
	# 5 cm under the eave's edge.
	var face := {
		"id": "wall/side0",
		"kind": "wall_face",
		"side": 0,
		"origin": Vector3(-2.6, 0.0, -0.4),
		"u": Vector3.RIGHT,
		"v": Vector3.UP,
		"n": Vector3.BACK,
		"u_len": 5.2,
		"v_len": 2.95,
		"holes": [{"u0": 2.0, "u1": 3.0, "v0": 2.0, "v1": 2.95, "door": false}],
	}
	var window_a := Vector3(-0.6, 2.95, -0.4)
	var window_b := Vector3(0.4, 2.95, -0.4)
	var bare := _built([slope])
	var clear := _built([slope, face])
	var low := func(built: Dictionary) -> float:
		var lowest := INF
		for p: Vector3 in built.arrays[Mesh.ARRAY_VERTEX]:
			var q := Geometry2D.get_closest_point_to_segment(
				Vector2(p.x, p.z), Vector2(window_a.x, window_a.z), Vector2(window_b.x, window_b.z)
			)
			if q.distance_to(Vector2(p.x, p.z)) < PainterSnowForms.WINDOW_REACH_M:
				lowest = minf(lowest, p.y)
		return lowest
	assert_lt(float(low.call(bare)), 2.95, "without the window the lip hangs below its top")
	assert_gte(
		float(low.call(clear)), 2.95 + PainterSnowForms.WINDOW_CLEAR_M - 0.001, "with it, never"
	)
	PainterMannerSnow.blanket = false
	var strips := _built([slope, face])
	PainterMannerSnow.blanket = true
	assert_gte(float(low.call(strips)), 2.95, "nor the strips' lip")


## Plan distance from `p` to polygon `poly`'s outline, positive outside it.
static func _outline_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return -best if Geometry2D.is_point_in_polygon(p, poly) else best


## How many of `points` (a closed outline) turn by more than `degrees`.
static func _corners(points: PackedVector2Array, degrees: float) -> int:
	var count := 0
	for i in points.size():
		var a := points[(i + points.size() - 1) % points.size()]
		var b := points[i]
		var c := points[(i + 1) % points.size()]
		if absf((b - a).angle_to(c - b)) > deg_to_rad(degrees):
			count += 1
	return count


func test_the_cones_rim_follows_the_eave_polygon() -> void:
	# Card snow-calm-cells (owner: "The hut's rim needs work"): a round body sat inside the roof's
	# sides and left a wedge of its top at every corner; each ring now follows the eave's polygon.
	var cone := _cone()
	var poly := PackedVector2Array()
	for p: Vector3 in cone["ring"]:
		poly.append(Vector2(p.x, p.z))
	var cols: PackedVector2Array = PainterSnowForms.cone_columns(cone)["points"]
	assert_eq(_corners(cols, 10.0), int(cone["sides"]), "a column at every corner of the ring")
	var g := PainterMannerSnow.Strips.new()
	assert_gt(PainterSnowForms.lay_cone(g, cone, 1.0, Vector3.ZERO, 7), 0)
	var stride := cols.size() + 1
	# Rows 0 to 2 the lip (tuck, front, roll), row 3 the eave ring on the roof's top face.
	for row in 4:
		var ring := PackedVector2Array()
		var lo := INF
		var hi := -INF
		for ci in cols.size():
			var p := g.pos[row * stride + ci]
			ring.append(Vector2(p.x, p.z))
			var d := _outline_distance(poly, Vector2(p.x, p.z))
			lo = minf(lo, d)
			hi = maxf(hi, d)
		assert_eq(_corners(ring, 10.0), int(cone["sides"]), "row %d has the ring's corners" % row)
		assert_lt(hi, 0.08, "row %d stays at the eave" % row)
		# The lip's roll (its outer edge) runs parallel to the eave's sides, a few centimetres off
		# them; a round row strayed by the corners' reach past the sides (0.2 m here). (The tuck and
		# the front sit under the roof's edge by the depth, which swells along the ring.)
		if row >= 2:
			assert_lt(hi - lo, 0.05, "row %d follows the eave polygon" % row)
		if row == 3:
			assert_lt(maxf(absf(lo), absf(hi)), 0.005, "the eave ring lies on the polygon")
	# Shaded round the axis: neighbouring columns' normals turn smoothly at the corners too (the
	# polygon's own faces would turn 45 degrees there).
	var steepest := 0.0
	for row in range(4, 8):
		for ci in cols.size():
			var a := g.nor[row * stride + ci]
			var b := g.nor[row * stride + (ci + 1) % cols.size()]
			steepest = maxf(steepest, rad_to_deg(a.angle_to(b)))
	assert_lt(steepest, 15.0, "no tone step between columns")


func test_a_real_huts_cone_has_its_roofs_corners() -> void:
	StructureRecipes.ensure_served()
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var plan := PackedVector2Array()
	for i in 8:
		plan.append(Vector2.from_angle(TAU * i / 8.0) * 2.5)
	var feed := PainterMannerSource.evaluate(doc, Structure.make(1, "core:round_hut", plan, 5), false)
	var cones: Array = PainterMannerSnow.source(feed.records, feed.meshes, feed.table, {}).cones
	assert_gt(cones.size(), 0, "a cone record")
	for cone: Dictionary in cones:
		var cols: PackedVector2Array = PainterSnowForms.cone_columns(cone)["points"]
		assert_eq(_corners(cols, 5.0), int(cone["sides"]), "the snow has the roof's corners")


func test_the_calm_paint_defaults_are_the_owners_pick() -> void:
	# Card snow-calm-cells: spike 8's cells at the verdict settings the owner saw (2026-11-22: cell
	# 2.2, shift 1.8, wash 1.35), with the card's one tuning round toward calmer (edge 0.3 -> 0.5,
	# turn 0.6 -> 0.4, tone 0.35 -> 0.22: the cells read as flat angular planes at zoom 16).
	var code := (load(PainterMannerHost.SHADER) as Shader).code
	var want := {
		"calm_cell": 2.2,
		"calm_shift": 1.8,
		"calm_edge": 0.5,
		"calm_turn": 0.4,
		"calm_cell_tone": 0.22,
		"calm_wash": 1.35,
	}
	var re := RegEx.create_from_string("uniform float (calm_\\w+) = ([0-9.]+);")
	var got := {}
	for m in re.search_all(code):
		got[m.get_string(1)] = float(m.get_string(2))
	for key: String in want:
		assert_almost_eq(float(got.get(key, -1.0)), float(want[key]), 1e-6, key)
	assert_true(code.contains("vec4 sp = calm_paint(v_ap, sf, broad);"), "the bodies take it")
	assert_false(code.contains("snow_bend"), "no bend")
