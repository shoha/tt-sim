extends GutTest

## The windmill's turning parts (topic range_look, 2026-10-30; procgen docs/style_range.md "Host
## contract"): StructureMill cuts the `sails/...` pieces and the cap out of a build's meshes, the
## digest and triangle count still cover everything, and MillMotion turns the pivots.
## Summary: docs/systems/structures.md "Windmills".

const WINDMILLS: Array[String] = ["windmill_tower", "windmill_dutch"]

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _parts(id: String, seed_value: int = 5) -> Dictionary:
	var row := LibraryStructureStore.structure("core:" + id)
	var diameter := float((row.get("default_size_m", [6.0, 6.0]) as Array)[0])
	var plan := StructurePlacement.lot_plan(
		Vector2.ZERO, Vector2(diameter, diameter), 0.0, StructurePlacement.sides_of(row)
	)
	return StructureGeometry.build_one(_doc, Structure.make(1, "core:" + id, plan, seed_value))


func _vertices_tagged(meshes: Array, table: PackedStringArray, test: Callable) -> int:
	var count := 0
	for mesh: Dictionary in meshes:
		var tags: PackedInt32Array = mesh.tags
		for tag in tags:
			if tag >= 0 and test.call(table[tag]):
				count += 1
	return count


func _triangles(meshes: Array) -> int:
	var total := 0
	for mesh: Dictionary in meshes:
		total += (mesh.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


func test_every_sails_vertex_lands_in_the_wheel() -> void:
	for id in WINDMILLS:
		var parts := _parts(id)
		assert_eq(parts.problem, "", id)
		var mill: Dictionary = parts.mill
		assert_false(mill.is_empty(), "%s has turning parts" % id)
		var is_sail := func(path: String) -> bool: return StructureMill.in_group(path, "sails/")
		assert_eq(
			_vertices_tagged(parts.meshes, parts.tag_table, is_sail), 0, "%s: none left behind" % id
		)
		assert_eq(
			_vertices_tagged(mill.cap, parts.tag_table, is_sail), 0, "%s: none in the cap" % id
		)
		assert_gt(_vertices_tagged(mill.wheel, parts.tag_table, is_sail), 100, "%s: the wheel" % id)
		var is_hub := func(path: String) -> bool: return StructureMill.is_slot(path, "sails/hub")
		assert_gt(_vertices_tagged(mill.wheel, parts.tag_table, is_hub), 0, "%s: the hub" % id)


func test_the_counts_add_up_and_the_digest_covers_the_whole() -> void:
	for id in WINDMILLS:
		var parts := _parts(id)
		var mill: Dictionary = parts.mill
		var all := _triangles(parts.meshes) + _triangles(mill.wheel) + _triangles(mill.cap)
		assert_eq(StructureGeometry.triangle_count(parts), all, id)
		assert_eq(all, parts.triangles, "%s: the geometry's own count" % id)
		assert_gt(_triangles(mill.wheel), 200, "%s: a wheel" % id)
		assert_gt(_triangles(mill.cap), 20, "%s: a cap" % id)
		assert_eq(StructureGeometry.digest_of(parts), StructureGeometry.digest_of(_parts(id)), id)
		assert_ne(
			StructureGeometry.digest_of(parts),
			StructureGeometry.digest_of(_parts(id, 6)),
			"%s: the seed still moves it" % id
		)


func test_the_cap_is_roofing_above_the_curb_and_the_axis_is_horizontal() -> void:
	for id in WINDMILLS:
		var parts := _parts(id)
		var mill: Dictionary = parts.mill
		assert_true(is_finite(float(mill.curb_top)), "%s has a curb" % id)
		for mesh: Dictionary in mill.cap:
			assert_eq(mesh.role, StructureLook.ROOF, id)
			for vertex: Vector3 in mesh.arrays[Mesh.ARRAY_VERTEX]:
				assert_gte(vertex.y, float(mill.curb_top) - 0.1, "%s: the cap is above the curb" % id)
		var axis: Vector3 = mill.axis
		assert_almost_eq(axis.length(), 1.0, 0.001, id)
		assert_eq(axis.y, 0.0, "%s: horizontal" % id)
		var hub: Vector3 = mill.hub
		var centre: Vector3 = mill.centre
		var reach := Vector3(hub.x - centre.x, 0.0, hub.z - centre.z).normalized()
		assert_gt(reach.dot(axis), 0.999, "%s: from the centre to the hub" % id)
		assert_gt(hub.y, float(mill.curb_top), "%s: the hub is up the roof" % id)


func test_a_house_has_no_mill_and_its_meshes_are_whole() -> void:
	var parts := _parts("toon_cafe")
	assert_true((parts.mill as Dictionary).is_empty())
	assert_eq(StructureGeometry.triangle_count(parts), _triangles(parts.meshes))
	assert_true(StructureMill.split(parts.meshes, parts.tag_table).is_empty())


func test_slots_match_whole_segments() -> void:
	assert_true(StructureMill.is_slot("sails_3/sails/hub", "sails/hub"))
	assert_false(StructureMill.is_slot("sails_3/xsails/hub", "sails/hub"))
	assert_true(StructureMill.in_group("sails_3/sails/arm0/cloth", "sails/"))
	assert_false(StructureMill.in_group("sails_3/windmill/curb", "sails/"))
	assert_true(StructureMill.is_slot("sails_3/windmill/curb", "windmill/curb"))


func test_the_mill_node_turns_its_pivots() -> void:
	var parts := _parts("windmill_tower")
	var nodes := AuthoredStructures.new()
	add_child_autofree(nodes)
	var pivot := nodes.mill_node(parts.mill, 1, "", "")
	add_child_autofree(pivot)
	assert_not_null(pivot.wheel, "the wheel pivot")
	assert_eq(pivot.wheel, pivot.get_node("Wheel"))
	assert_eq(pivot.position, parts.mill.centre)
	assert_eq(pivot.wheel.position, parts.mill.hub - parts.mill.centre)
	assert_gt(pivot.wheel.get_child_count(), 0, "the sails are under the wheel")
	var before: Basis = pivot.wheel.basis
	pivot.step(1.0)
	var turned: float = pivot.spin()
	assert_gt(turned, 0.1, "the wheel has turned")
	assert_ne(pivot.wheel.basis, before)
	# The turn is about the axis: the axis itself does not move.
	var axis: Vector3 = parts.mill.axis
	assert_lt(((pivot.wheel.basis * axis) - axis).length(), 0.001)
	# The meshes keep their map-frame vertices and sit at minus the pivot, so the pose at rest is the
	# built one.
	var instance := pivot.wheel.get_child(0) as MeshInstance3D
	assert_eq(instance.position, -(parts.mill.hub as Vector3))
	for k in 50:
		pivot.step(0.5)
	assert_lt(pivot.spin(), TAU, "the spin wraps")


func test_the_cap_faces_the_wind() -> void:
	var built := Vector3(0.0, 0.0, 1.0)
	var upwind := MillMotion.WIND_FROM.normalized()
	var angle := MillMotion.facing_angle(built, upwind)
	assert_lt((Basis(Vector3.UP, angle) * built - upwind).length(), 0.001, "the turn lands on it")
	assert_eq(MillMotion.facing_angle(Vector3.ZERO, upwind), 0.0, "no axis, no turn")
	var parts := _parts("windmill_dutch")
	var nodes := AuthoredStructures.new()
	add_child_autofree(nodes)
	var pivot := nodes.mill_node(parts.mill, 2, "", "")
	add_child_autofree(pivot)
	var facing := pivot.basis * (parts.mill.axis as Vector3)
	var cone := cos(StructureWind.MILL_CONE_RAD)
	assert_gt(facing.dot(upwind), cone - 0.001, "the sails stay within the cone about WIND_FROM")


func test_mills_are_not_in_step_and_a_built_structure_carries_the_pivot() -> void:
	var a := _parts("windmill_dutch")
	var nodes := AuthoredStructures.new()
	add_child_autofree(nodes)
	var first := nodes.mill_node(a.mill, 1, "", "")
	var second := nodes.mill_node(a.mill, 2, "", "")
	add_child_autofree(first)
	add_child_autofree(second)
	assert_ne(first.spin_speed, second.spin_speed, "the seed varies the speed")
	var node := nodes._structure_node(1, a)
	add_child_autofree(node)
	assert_not_null(node.get_node_or_null("Mill/Wheel"), "the structure node holds the pivots")
	assert_not_null(node.get_node_or_null("Collision"), "and its collision")
