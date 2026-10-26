extends GutTest

## The procgen plank bridge against CrossingGeometry's own, on the crossings test_crossings.gd
## builds (a narrow river, a wide one, a diagonal over it). What must be equal: the deck
## collision (it feeds the grid and tokens), the highest walkable point, and how many boards,
## beams, posts, rails and piles stand (box counts: the module follows the same rules against
## the same ground). What may differ: the jitter (another random stream), so the bounds agree
## within a hand's width, not exactly. See docs/systems/procgen.md.

const RIVER_LEVEL := -0.2
const BED := -1.0
const BOX_VERTICES := 24
const BOUNDS_TOLERANCE_M := 0.15
## Vertices of one stepping stone: 9 sides, 9 facets a side, 3 vertices a facet.
const STONE_VERTICES := 9 * 9 * 3


func _doc(half_width: float) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and absf(p.y) <= half_width:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([half_width, half_width, half_width])
	var depth := WaterBody.Depth.WAIST
	doc.water_bodies.append(WaterBody.river(1, line, widths, depth, RIVER_LEVEL))
	return doc


func _placed(
	doc: MapDocument,
	from: Vector2,
	to: Vector2,
	width: float = -1.0,
	kind: Crossing.Kind = Crossing.Kind.PLANK
) -> Crossing:
	var placed := CrossingPlacement.place(doc, from, to, kind, width)
	assert_eq(placed.refusal, &"", "placed")
	var crossing: Crossing = placed.crossing
	crossing.id = 1
	doc.crossings.append(crossing)
	return crossing


func _check_against_crossing_geometry(
	doc: MapDocument, crossing: Crossing, label: String
) -> Dictionary:
	var recipe := ProcgenCrossing.load_recipe()
	assert_not_null(recipe, "%s: the recipe loads" % label)
	var ours := CrossingGeometry.build_one(doc, crossing)
	var theirs := ProcgenCrossing.build(doc, crossing, recipe)
	assert_eq(theirs.errors, [], "%s: the recipe evaluates cleanly" % label)

	# The walking surface: the same faces in the same order, and the same top.
	var faces: PackedVector3Array = ours.collision
	var module_faces: PackedVector3Array = theirs.collision
	assert_eq(module_faces.size(), faces.size(), "%s: same number of collision points" % label)
	var worst := 0.0
	for k in mini(faces.size(), module_faces.size()):
		worst = maxf(worst, faces[k].distance_to(module_faces[k]))
	assert_lt(worst, 0.0001, "%s: collision points agree (worst %f m)" % [label, worst])
	assert_almost_eq(float(theirs.top), float(ours.top), 0.00001, "%s: same top" % label)

	# The wood: how many boxes, and roughly where.
	var wood: Array = theirs.surfaces.get("wood", [])
	assert_false(wood.is_empty(), "%s: the module builds wood" % label)
	var our_vertices: PackedVector3Array = (ours.wood as Array)[Mesh.ARRAY_VERTEX]
	var their_vertices: PackedVector3Array = wood[Mesh.ARRAY_VERTEX]
	assert_eq(
		their_vertices.size() / BOX_VERTICES,
		our_vertices.size() / BOX_VERTICES,
		"%s: same number of boxes (boards, beams, posts, rails, piles)" % label
	)
	var our_box := _bounds(our_vertices)
	var their_box := _bounds(their_vertices)
	for pair in [[our_box.position, their_box.position], [our_box.end, their_box.end]]:
		assert_lt(
			(pair[0] as Vector3).distance_to(pair[1]),
			BOUNDS_TOLERANCE_M * 1.8,
			"%s: bounds agree within a hand's width" % label
		)
	return {"wood": wood, "boxes": their_vertices.size() / BOX_VERTICES}


func _bounds(vertices: PackedVector3Array) -> AABB:
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	return box


func test_a_short_bridge_over_a_narrow_river() -> void:
	var doc := _doc(1.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1))
	var built := _check_against_crossing_geometry(doc, crossing, "narrow")
	assert_lt(crossing.span_m(), 5.5, "a short span has no piles")
	assert_gt(built.boxes, 40, "boards, beams, sills and rails")


func test_a_long_bridge_gets_piles_where_the_ground_is_far_below() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1))
	assert_gt(crossing.span_m(), 5.5, "a long span")
	var built := _check_against_crossing_geometry(doc, crossing, "wide")
	assert_gt(built.boxes, 100, "piles add boxes")


func test_a_diagonal_bridge_and_a_wide_deck() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(-2, -8), Vector2(2, 8), 2.6)
	_check_against_crossing_geometry(doc, crossing, "diagonal")
	assert_almost_eq(crossing.width_m, 2.6, 0.0001, "the width came through")


func test_every_module_triangle_faces_its_normal_clockwise() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(-2, -8), Vector2(2, 8))
	var built := ProcgenCrossing.build(doc, crossing, ProcgenCrossing.load_recipe())
	var arrays: Array = built.surfaces.wood
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var wrong := 0
	for t in indices.size() / 3:
		var a := vertices[indices[t * 3]]
		var b := vertices[indices[t * 3 + 1]]
		var c := vertices[indices[t * 3 + 2]]
		if (b - a).cross(c - a).dot(normals[indices[t * 3]]) >= 0.0:
			wrong += 1
	assert_eq(wrong, 0, "every triangle is clockwise seen from its normal's side")


func test_the_build_is_deterministic_and_worker_safe() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1))
	var recipe := ProcgenCrossing.load_recipe()
	var first := ProcgenCrossing.build(doc, crossing, recipe)
	var results: Array[Dictionary] = []
	results.resize(4)
	var task := WorkerThreadPool.add_group_task(
		func(i: int) -> void: results[i] = ProcgenCrossing.build(doc, crossing, recipe), 4
	)
	WorkerThreadPool.wait_for_group_task_completion(task)
	for built in results:
		assert_eq(built.collision, first.collision, "collision repeats")
		var wood: Array = built.surfaces.wood
		assert_eq(wood[Mesh.ARRAY_VERTEX], first.surfaces.wood[Mesh.ARRAY_VERTEX], "wood repeats")


# --- the switch ------------------------------------------------------------------------


func after_each() -> void:
	ProcgenCrossing.enabled = false


func test_the_switch_is_off_by_default_and_routes_build_one_when_on() -> void:
	assert_false(ProcgenCrossing.enabled, "off unless a rollout turns it on")
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1))
	var legacy := CrossingGeometry.build_one(doc, crossing)
	ProcgenCrossing.enabled = true
	var routed := CrossingGeometry.build_one(doc, crossing)
	assert_ne(
		(routed.wood as Array)[Mesh.ARRAY_VERTEX],
		(legacy.wood as Array)[Mesh.ARRAY_VERTEX],
		"the module's boards are a different set of vertices"
	)
	assert_eq(routed.collision, legacy.collision, "the walking surface is the same")
	assert_almost_eq(float(routed.top), float(legacy.top), 0.00001, "and so is the top")
	assert_true((routed.stone as Array).is_empty(), "a plank bridge has no stone")


func test_routed_wood_carries_unit_tangents_for_the_normal_map() -> void:
	var doc := _doc(1.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1))
	ProcgenCrossing.enabled = true
	var wood: Array = CrossingGeometry.build_one(doc, crossing).wood
	var vertices: PackedVector3Array = wood[Mesh.ARRAY_VERTEX]
	var tangents: PackedFloat32Array = wood[Mesh.ARRAY_TANGENT]
	assert_eq(tangents.size(), vertices.size() * 4, "four floats a vertex")
	var worst := 0.0
	for k in vertices.size():
		var t := Vector3(tangents[k * 4], tangents[k * 4 + 1], tangents[k * 4 + 2])
		worst = maxf(worst, absf(t.length() - 1.0))
		assert_true(absf(tangents[k * 4 + 3]) == 1.0, "binormal sign is plus or minus one")
	assert_lt(worst, 0.001, "unit tangents")


func test_the_cache_key_changes_with_the_switch_for_the_kinds_the_module_builds() -> void:
	var doc := _doc(1.5)
	var plank := _placed(doc, Vector2(0.3, -1), Vector2(0, 1))
	var off := CrossingCache.key_of(doc, plank)
	ProcgenCrossing.enabled = true
	assert_ne(CrossingCache.key_of(doc, plank), off, "a plank is rebuilt when the switch flips")
	var stones := Crossing.new()
	stones.id = 2
	stones.kind = Crossing.Kind.STONES
	stones.start = plank.start
	stones.end = plank.end
	stones.levels = plank.levels
	ProcgenCrossing.enabled = false
	var stones_off := CrossingCache.key_of(doc, stones)
	ProcgenCrossing.enabled = true
	assert_ne(CrossingCache.key_of(doc, stones), stones_off, "stones are rebuilt too")
	var ford := Crossing.new()
	ford.id = 3
	ford.kind = Crossing.Kind.FORD
	ford.start = plank.start
	ford.end = plank.end
	ford.levels = plank.levels
	var ford_on := CrossingCache.key_of(doc, ford)
	ProcgenCrossing.enabled = false
	assert_eq(
		CrossingCache.key_of(doc, ford), ford_on, "a kind with no recipe does not depend on it"
	)


# --- stepping stones -------------------------------------------------------------------


func test_stepping_stones_match_in_count_top_and_place() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1), -1.0, Crossing.Kind.STONES)
	var ours := CrossingGeometry.build_one(doc, crossing)
	ProcgenCrossing.enabled = true
	var theirs := CrossingGeometry.build_one(doc, crossing)
	var our_vertices: PackedVector3Array = (ours.stone as Array)[Mesh.ARRAY_VERTEX]
	var their_vertices: PackedVector3Array = (theirs.stone as Array)[Mesh.ARRAY_VERTEX]
	assert_gt(our_vertices.size(), 0, "stones exist")
	assert_eq(their_vertices.size(), our_vertices.size(), "the same number of stones")
	assert_eq(their_vertices.size() % STONE_VERTICES, 0, "whole stones of 81 triangles")
	assert_eq(theirs.collision.size(), ours.collision.size(), "collision is the stones' triangles")
	assert_lt(absf(float(theirs.top) - float(ours.top)), 0.05, "tops agree within the jitter")
	var our_box := _bounds(our_vertices)
	var their_box := _bounds(their_vertices)
	assert_lt(our_box.position.distance_to(their_box.position), 0.45, "near bounds agree")
	assert_lt(our_box.end.distance_to(their_box.end), 0.45, "far bounds agree")
	assert_true((theirs.wood as Array).is_empty(), "stones have no wood")


func test_module_stones_face_their_normals_clockwise_and_are_rooted() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1), -1.0, Crossing.Kind.STONES)
	ProcgenCrossing.enabled = true
	var arrays: Array = CrossingGeometry.build_one(doc, crossing).stone
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var wrong := 0
	for tri in indices.size() / 3:
		var a := vertices[indices[tri * 3]]
		var b := vertices[indices[tri * 3 + 1]]
		var c := vertices[indices[tri * 3 + 2]]
		if (b - a).cross(c - a).dot(normals[indices[tri * 3]]) >= 0.0:
			wrong += 1
	assert_eq(wrong, 0, "every facet is clockwise seen from its normal's side")
	assert_lt(_bounds(vertices).position.y, BED, "the roots go under the bed")


# --- stone arch ------------------------------------------------------------------------


func _keyed_vertices(arrays: Array) -> int:
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var keyed := 0
	for uv in uvs:
		if uv != Vector2.ZERO:
			keyed += 1
	return keyed


func _check_arch(doc: MapDocument, crossing: Crossing, label: String) -> void:
	var ours := CrossingGeometry.build_one(doc, crossing)
	ProcgenCrossing.enabled = true
	var theirs := CrossingGeometry.build_one(doc, crossing)
	ProcgenCrossing.enabled = false
	# The walking surface is the deck strip.
	assert_eq(theirs.collision.size(), ours.collision.size(), "%s: collision size" % label)
	var worst := 0.0
	for k in mini(ours.collision.size(), theirs.collision.size()):
		worst = maxf(worst, (ours.collision[k] as Vector3).distance_to(theirs.collision[k]))
	assert_lt(worst, 0.0001, "%s: collision points agree (worst %f m)" % [label, worst])
	assert_almost_eq(float(theirs.top), float(ours.top), 0.00001, "%s: same top" % label)
	# The same construction, so the same number of facets in each material.
	for part in ["stone", "paving"]:
		var a: Array = ours[part]
		var b: Array = theirs[part]
		assert_false(b.is_empty(), "%s: the module builds %s" % [label, part])
		assert_eq(
			(b[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			(a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"%s: same number of %s vertices" % [label, part]
		)
		assert_eq(
			(b[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
			(a[Mesh.ARRAY_INDEX] as PackedInt32Array).size(),
			"%s: same number of %s indices" % [label, part]
		)
		var box_a := _bounds(a[Mesh.ARRAY_VERTEX])
		var box_b := _bounds(b[Mesh.ARRAY_VERTEX])
		assert_lt(
			box_a.position.distance_to(box_b.position), 0.25, "%s: %s near bounds" % [label, part]
		)
		assert_lt(box_a.end.distance_to(box_b.end), 0.25, "%s: %s far bounds" % [label, part])
	assert_eq(
		_keyed_vertices(theirs.stone),
		_keyed_vertices(ours.stone),
		"%s: same moss-keyed facets" % label
	)
	# The moss keys are in the map frame: near the crossing, not near the local origin.
	var uvs: PackedVector2Array = (theirs.stone as Array)[Mesh.ARRAY_TEX_UV]
	var near := Rect2(crossing.start, Vector2.ZERO).expand(crossing.end).grow(9.0)
	for uv in uvs:
		if uv != Vector2.ZERO:
			assert_true(
				near.has_point(uv), "%s: a moss key lies by the crossing (%s)" % [label, uv]
			)
			break


func test_a_short_arch_matches() -> void:
	var doc := _doc(1.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1), -1.0, Crossing.Kind.ARCH)
	assert_lt(crossing.span_m(), 9.0, "no pier")
	_check_arch(doc, crossing, "arch")


func test_a_long_arch_with_a_pier_matches() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(0.3, -1), Vector2(0, 1), -1.0, Crossing.Kind.ARCH)
	assert_gt(crossing.span_m(), 9.0, "a pier")
	_check_arch(doc, crossing, "pier arch")


func test_a_diagonal_arch_with_a_wide_deck_matches() -> void:
	var doc := _doc(5.5)
	var crossing := _placed(doc, Vector2(-2, -8), Vector2(2, 8), 2.8, Crossing.Kind.ARCH)
	_check_arch(doc, crossing, "diagonal arch")
