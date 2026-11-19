extends GutTest
## PainterOcclusion (card painter-grounding): the footprint raster, the sheet's grounding numbers.

const MOODS: Array[String] = ["summer", "dusk", "grimdark", "winter", "autumn"]


func _field(host: PainterOcclusion, w: int, h: int) -> PackedFloat32Array:
	host._origin = Vector2(-4.0, -4.0)
	host._size = Vector2i(w, h)
	var field := PackedFloat32Array()
	field.resize(w * h)
	return field


func _at(host: PainterOcclusion, field: PackedFloat32Array, x: float, z: float) -> float:
	var i := int((x - host._origin.x) / PainterOcclusion.TEXEL_M)
	var j := int((z - host._origin.y) / PainterOcclusion.TEXEL_M)
	return field[j * host._size.x + i]


func test_cover_is_half_at_the_reach() -> void:
	assert_eq(PainterOcclusion.cover(0.0), 1.0)
	assert_almost_eq(PainterOcclusion.cover(1.0), 0.5, 0.001)
	assert_eq(PainterOcclusion.cover(1.6), 0.0)


func test_disc_covers_its_middle_and_stops_past_its_reach() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host, 16, 16)
	host._disc(field, 0.0, 0.0, 1.0)
	assert_eq(_at(host, field, 0.25, 0.25), 1.0)
	assert_gt(_at(host, field, 0.75, 0.25), 0.4)
	assert_eq(_at(host, field, 3.25, 0.25), 0.0)


func test_disc_keeps_the_maximum_of_two() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host, 16, 16)
	host._disc(field, 0.0, 0.0, 1.0)
	var before := _at(host, field, 0.25, 0.25)
	host._disc(field, 0.5, 0.0, 0.3)
	assert_eq(_at(host, field, 0.25, 0.25), before)


func test_box_follows_its_turn() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host, 16, 16)
	# A long box (half 2 by 0.25) along x: its far end is covered, the same distance off axis is not.
	host._box(field, 0.0, 0.0, 0.0, Vector2(2.0, 0.25), 0.3)
	assert_eq(_at(host, field, 1.75, 0.25), 1.0)
	assert_eq(_at(host, field, 0.25, 1.75), 0.0)
	var turned := _field(host, 16, 16)
	host._box(turned, 0.0, 0.0, PI * 0.5, Vector2(2.0, 0.25), 0.3)
	assert_eq(_at(host, turned, 0.25, 1.75), 1.0)
	assert_eq(_at(host, turned, 1.75, 0.25), 0.0)


func test_a_rounded_box_cuts_its_corners() -> void:
	var host := PainterOcclusion.new()
	var square := _field(host, 16, 16)
	host._box(square, 0.0, 0.0, 0.0, Vector2(2.0, 1.5), 0.1)
	var rounded := _field(host, 16, 16)
	host._box(rounded, 0.0, 0.0, 0.0, Vector2(2.0, 1.5), 0.1, 1.5)
	# The texel at (1.75, 1.25) is inside the square box, outside its corner rounded by 1.5 m.
	assert_eq(_at(host, square, 1.75, 1.25), 1.0)
	assert_lt(_at(host, rounded, 1.75, 1.25), 0.5, "the rounded corner is cut")
	assert_eq(_at(host, rounded, 1.75, 0.25), 1.0, "the box's end on its axis is still covered")


func test_a_tree_the_painter_does_not_grow_gets_a_round_pool() -> void:
	var host := PainterOcclusion.new()
	var pool := _field(host, 16, 16)
	var core := _field(host, 16, 16)
	# Its foot at the origin, its crown's middle 1 m along x: the pool is a disc round (0.5, 0).
	host._tree(pool, core, Vector3.ZERO, Vector3(1.0, 3.0, 0.0), 2.0, 6.0)
	assert_eq(_at(host, pool, 0.25, 0.25), 1.0)
	var along := _at(host, pool, 1.75, 0.25)
	var across := _at(host, pool, 0.75, 1.25)
	assert_gt(along, 0.0)
	assert_almost_eq(along, across, 0.001, "as far along as across: round, not a box")
	assert_gt(_at(host, core, 0.25, 0.25), 0.5, "a seam at the trunk's foot")
	assert_eq(_at(host, core, 1.25, 0.25), 0.0, "the seam stays at the foot, under the pool")


func test_a_trunk_seam_is_a_small_dab_that_grows_with_the_tree() -> void:
	# It shows in the sun too, so it stays well under a metre for a common tree (card
	# painter-tree-ground: a metre-wide seam read as a grey plate beside the trunk).
	assert_lt(PainterOcclusion.trunk_seam(10.0), 0.6)
	assert_gt(PainterOcclusion.trunk_seam(20.0), PainterOcclusion.trunk_seam(4.0))
	var sapling := PainterOcclusion.trunk_seam(2.0)
	assert_gt(sapling, PainterOcclusion.TEXEL_M * 0.5, "a sapling still has one")


func test_a_rectangle_fits_its_own_turned_rectangle_with_soft_corners() -> void:
	var turn := deg_to_rad(30.0)
	var u := Vector2(cos(turn), sin(turn))
	var v := Vector2(-u.y, u.x)
	var points := PackedVector2Array()
	for s: Vector2 in [Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)]:
		points.append(Vector2(10, 5) + u * s.x + v * s.y)
	var fit := PainterFootprint.fit(points)
	var half: Vector2 = fit["half"]
	assert_almost_eq((fit["centre"] as Vector2).distance_to(Vector2(10, 5)), 0.0, 0.001)
	assert_almost_eq(maxf(half.x, half.y), 3.0, 0.001)
	assert_almost_eq(minf(half.x, half.y), 2.0, 0.001)
	assert_almost_eq(sin(2.0 * (float(fit["yaw"]) - turn)), 0.0, 0.001, "its own turn")
	assert_almost_eq(float(fit["corner"]), PainterFootprint.MIN_CORNER_M, 0.001)


func test_a_round_plan_fits_a_disc() -> void:
	var points := PackedVector2Array()
	for i in 24:
		points.append(Vector2.from_angle(TAU * i / 24.0) * 3.0)
	var fit := PainterFootprint.fit(points)
	var half: Vector2 = fit["half"]
	assert_almost_eq(half.x, half.y, 0.15)
	assert_gt(float(fit["corner"]), 0.95 * minf(half.x, half.y), "rounded about right round")
	var hexagon := PackedVector2Array()
	for i in 6:
		hexagon.append(Vector2.from_angle(TAU * i / 6.0) * 2.6)
	var hex := PainterFootprint.fit(hexagon)
	var hex_half: Vector2 = hex["half"]
	assert_gt(float(hex["corner"]), 0.85 * minf(hex_half.x, hex_half.y), "a hex tower is about round")
	assert_true(PainterFootprint.fit(PackedVector2Array([Vector2.ZERO, Vector2.ONE])).is_empty())


func test_a_structure_footprint_is_its_walls_feet_not_its_roof_or_yard() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	# Walls 6 by 4 at x 10, z 0 up to 2.5 m; a roof 1 m wider each side from 2.5 to 4 m.
	var faces := PackedVector3Array()
	for y: float in [0.0, 2.5]:
		faces.append_array(_ring(Vector2(10, 0), Vector2(3, 2), y))
	for y: float in [2.5, 4.0]:
		faces.append_array(_ring(Vector2(10, 0), Vector2(4, 3), y))
	var body := StaticBody3D.new()
	body.name = "Collision"
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	# The yard's skirt, 14 m across: left out.
	var yard := MeshInstance3D.new()
	yard.name = "dressing_ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	yard.mesh = plane
	root.add_child(yard)
	var plan := PainterFootprint.of_structure(root)
	var half: Vector2 = plan["half"]
	assert_almost_eq((plan["centre"] as Vector2).distance_to(Vector2(10, 0)), 0.0, 0.001)
	assert_almost_eq(maxf(half.x, half.y), 3.0, 0.001, "the walls, not the roof's overhang")
	assert_almost_eq(minf(half.x, half.y), 2.0, 0.001)
	assert_almost_eq(float(plan["height"]), 4.0, 0.001)
	# Without collision the meshes' bounds stand in, still without the yard.
	root.remove_child(body)
	body.free()
	var walls := MeshInstance3D.new()
	walls.name = "wall_plaster"
	var box := BoxMesh.new()
	box.size = Vector3(6, 2.5, 4)
	walls.mesh = box
	walls.position = Vector3(10, 1.25, 0)
	root.add_child(walls)
	var bounds := PainterFootprint.of_structure(root)
	var bounds_half: Vector2 = bounds["half"]
	assert_almost_eq(maxf(bounds_half.x, bounds_half.y), 3.0, 0.001, "the yard is left out")


func test_a_pool_reaches_further_for_a_larger_taller_building_and_differs_by_structure() -> void:
	var hut := PainterFootprint.reach(Vector2(2.5, 2.0), 4.0, "Structure_1")
	var barn := PainterFootprint.reach(Vector2(5.0, 3.5), 8.0, "Structure_1")
	assert_gt(barn, hut, "a barn's pool reaches further than a hut's")
	var spread := PainterFootprint.REACH_SPREAD
	for key in ["Structure_1", "Structure_2", "Structure_3"]:
		var r := PainterFootprint.reach(Vector2(2.5, 2.0), 4.0, key)
		assert_between(
			r,
			PainterFootprint.REACH_MIN_M * (1.0 - spread),
			PainterFootprint.REACH_MAX_M * (1.0 + spread)
		)
	var a := PainterFootprint.reach(Vector2(2.5, 2.0), 4.0, "Structure_1")
	var b := PainterFootprint.reach(Vector2(2.5, 2.0), 4.0, "Structure_2")
	assert_ne(a, b, "two huts of one plan are not the same")


## The four sides of a box (half extents `half` round `centre`) at height `y` as two triangles each
## (only the vertices matter to the footprint).
func _ring(centre: Vector2, half: Vector2, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1)]:
		out.append(Vector3(centre.x + s.x * half.x, y, centre.y + s.y * half.y))
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		out.append(Vector3(centre.x + s.x * half.x, y, centre.y + s.y * half.y))
	return out


func test_every_mood_has_the_grounding_numbers_in_range() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for mood in MOODS:
		for key in ["occ-pool", "occ-core", "occ-dark", "occ-soil", "occ-cool", "occ-shade", "base-dark"]:
			var v := PainterSheet.number(sheet, mood, key, 30.0)
			assert_between(v, 0.0, 1.0, "%s %s" % [mood, key])
		assert_eq(PainterSheet.number(sheet, "winter", "occ-soil", 30.0), 0.0, "snow bases take no soil")


func test_the_yard_wash_grounds_as_the_ground_does() -> void:
	# The yard wash repeats the ground's contact rule (the pool in the shade only, the seam leaning
	# down-sun); its constants must stay the ground's (card painter-tree-ground).
	var ground := _constants("res://painter/shaders/painter_ground.gdshader")
	var yard := _constants("res://painter/shaders/painter_yard_ground.gdshader")
	for key in ["SHADE_DEEP", "SEAM_LIT", "SEAM_LEAN_M"]:
		assert_true(ground.has(key), "the ground declares %s" % key)
		assert_eq(yard.get(key, -1.0), ground.get(key, -2.0), "the yard's %s is the ground's" % key)
	var deep := float(ground.get("SHADE_DEEP", 0.0))
	assert_between(deep, 0.5, 1.0, "the pool is a step below the shade")


## The `const float NAME = value;` lines of a shader's source.
func _constants(path: String) -> Dictionary:
	var out := {}
	var rx := RegEx.create_from_string("(?m)^const float (\\w+) = ([0-9.]+);")
	for m in rx.search_all(FileAccess.get_file_as_string(path)):
		out[m.get_string(1)] = float(m.get_string(2))
	return out
