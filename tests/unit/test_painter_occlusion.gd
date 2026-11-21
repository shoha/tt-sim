extends GutTest
## PainterOcclusion (card painter-grounding): the footprint raster, the sheet's grounding numbers.

const MOODS: Array[String] = ["summer", "dusk", "grimdark", "winter", "autumn"]


const POOL := PainterOcclusion.POOL_CH
const CORE := PainterOcclusion.CORE_CH


## An empty field `cells` texels square whose first corner is at (-4, -4): 8 m at 32 texels.
func _field(host: PainterOcclusion, cells: int = 32) -> PackedFloat32Array:
	host.lay_out(Vector2(-4.0, -4.0), Vector2i(cells, cells))
	var field := PackedFloat32Array()
	field.resize(cells * cells * PainterOcclusion.CHANNELS)
	return field


## Writes `marks` into `field`.
func _lay(host: PainterOcclusion, field: PackedFloat32Array, marks: Array) -> void:
	for mark: Array in marks:
		host._draw(field, mark)


## A box's mark in one channel (0 the pool, 1 the seam).
func _box(
	ch: int, x: float, z: float, yaw: float, half: Vector2, reach: float, corner := 0.0
) -> Array:
	var reaches := Vector2(-1.0, -1.0)
	reaches[ch] = reach
	return PainterOcclusion.box(x, z, yaw, half, reaches, corner)


## Forty marks over the 8 m field (discs and footed boxes that overlap), the same for one seed.
func _marks(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var marks: Array = []
	for k in 40:
		var x := rng.randf_range(-3.5, 3.5)
		var z := rng.randf_range(-3.5, 3.5)
		if k % 3 == 0:
			marks.append(PainterOcclusion.disc(k % 2, x, z, rng.randf_range(0.2, 1.2)))
			continue
		var half := Vector2(rng.randf_range(0.1, 0.6), rng.randf_range(0.1, 0.6))
		var reach := PainterOcclusion.solid_reach(half)
		var foot := Vector2(rng.randf_range(0.0, 3.0), rng.randf_range(1.0, 4.0))
		var yaw := rng.randf_range(0.0, TAU)
		var corner := minf(half.x, half.y)
		marks.append(PainterOcclusion.box(x, z, yaw, half, Vector2(reach.y, reach.x), corner, foot))
	return marks


func test_a_partial_update_equals_a_whole_bake_bit_for_bit() -> void:
	var origin := Vector2(-12.0, -12.0)
	var size := Vector2i(96, 96)
	var host := PainterOcclusion.new()
	var marks := _marks(7)
	assert_eq(host.update(origin, size, marks.duplicate()), 96 * 96, "the first bake is whole")
	# One mark moves, one goes, one comes: a rock dragged, one removed, one placed.
	var edited := marks.duplicate()
	var moved: Array = (edited[4] as Array).duplicate()
	moved[2] = float(moved[2]) + 0.6
	edited[4] = moved
	edited.remove_at(20)
	edited.append(PainterOcclusion.box(1.0, -2.0, 0.4, Vector2(0.3, 0.2), Vector2(0.2, 0.1), 0.2))
	var texels := host.update(origin, size, edited.duplicate())
	assert_between(texels, 1, 96 * 96 / 3, "only the changed marks' rects are baked")
	var whole := PainterOcclusion.new()
	whole.update(origin, size, edited.duplicate())
	assert_true(host._data.to_byte_array() == whole._data.to_byte_array(), "bit for bit")
	# And back again: what the dropped marks left is wiped.
	host.update(origin, size, marks.duplicate())
	var first := PainterOcclusion.new()
	first.update(origin, size, marks.duplicate())
	assert_true(host._data.to_byte_array() == first._data.to_byte_array(), "and back")


func test_nothing_is_baked_when_no_footprint_moved_whatever_their_order() -> void:
	var origin := Vector2(-4.0, -4.0)
	var size := Vector2i(32, 32)
	var host := PainterOcclusion.new()
	var marks := _marks(11)
	host.update(origin, size, marks.duplicate())
	var before := host._data.duplicate()
	assert_eq(host.update(origin, size, marks.duplicate()), 0, "the same marks: nothing baked")
	var turned := marks.duplicate()
	turned.reverse()
	assert_eq(host.update(origin, size, turned), 0, "collected in another order: still nothing")
	var other := PainterOcclusion.new()
	var again := marks.duplicate()
	again.reverse()
	other.update(origin, size, again)
	assert_true(other._data == before, "the field does not depend on the order")
	# Many moved, or the layout changed: a whole bake.
	assert_eq(host.update(origin, size, _marks(12)), 32 * 32, "everything moved: whole")
	assert_eq(host.update(origin, Vector2i(40, 40), _marks(12)), 40 * 40, "a new layout: whole")


func test_rects_that_meet_are_joined() -> void:
	var rects: Array[Rect2i] = [
		Rect2i(0, 0, 4, 4), Rect2i(10, 10, 2, 2), Rect2i(3, 3, 4, 4), Rect2i(6, 6, 5, 5), Rect2i()
	]
	var joined := PainterOcclusion.joined(rects)
	assert_eq(joined.size(), 1, "a chain of rects that meet is one")
	assert_eq(joined[0], Rect2i(0, 0, 12, 12))


## Channel `ch` of the texel that holds world (x, z).
func _at(
	host: PainterOcclusion, field: PackedFloat32Array, x: float, z: float, ch: int = 0
) -> float:
	var i := int((x - host._origin.x) / PainterOcclusion.TEXEL_M)
	var j := int((z - host._origin.y) / PainterOcclusion.TEXEL_M)
	return field[(j * host._size.x + i) * PainterOcclusion.CHANNELS + ch]


func test_cover_is_half_at_the_reach() -> void:
	assert_eq(PainterOcclusion.cover(0.0, 1.0), 1.0)
	assert_almost_eq(PainterOcclusion.cover(1.0, 1.0), 0.5, 0.001)
	assert_eq(PainterOcclusion.cover(1.6, 1.0), 0.0)
	# A small footprint falls off over a texel, not over a share of its own reach.
	assert_almost_eq(PainterOcclusion.cover(0.1, 0.1), 0.5, 0.001)
	assert_gt(PainterOcclusion.cover(0.2, 0.1), 0.0, "still held half a texel past its reach")
	assert_eq(PainterOcclusion.cover(0.1 + 0.5 * PainterOcclusion.TEXEL_M, 0.1), 0.0)


func test_disc_covers_its_middle_and_stops_past_its_reach() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host)
	host._disc(field, POOL, 0.0, 0.0, 1.0)
	assert_eq(_at(host, field, 0.25, 0.25), 1.0)
	assert_gt(_at(host, field, 0.75, 0.25), 0.4)
	assert_eq(_at(host, field, 3.25, 0.25), 0.0)
	assert_eq(_at(host, field, 0.25, 0.25, CORE), 0.0, "the other channel is untouched")


func test_a_footprint_at_the_maps_edge_leaves_the_fields_rim_empty() -> void:
	# The ground reads the field with a clamped edge: a footprint that reached the last row was
	# repeated outward as a streak down the screen (card painter-trunk-streak).
	var host := PainterOcclusion.new()
	var extent := Vector2(49.0, 49.0)
	var layout := PainterOcclusion.field_layout(extent)
	host.lay_out(layout.position, Vector2i(roundi(layout.size.x), roundi(layout.size.y)))
	var field := PackedFloat32Array()
	field.resize(host._size.x * host._size.y * PainterOcclusion.CHANNELS)
	# A big crown's pool (nominal radius 4 m) standing on the map's far edge.
	host._disc(field, POOL, 0.0, extent.y * 0.5, 4.0)
	assert_gt(_at(host, field, 0.0, extent.y * 0.5), 0.9, "the disc is drawn at the edge")
	assert_gt(_at(host, field, 0.0, extent.y * 0.5 + 4.0), 0.3, "and carries on past it")
	var worst := 0.0
	var step := PainterOcclusion.CHANNELS
	for i in host._size.x:
		worst = maxf(worst, field[((host._size.y - 1) * host._size.x + i) * step])
		worst = maxf(worst, field[i * step])
	for j in host._size.y:
		worst = maxf(worst, field[j * host._size.x * step])
		worst = maxf(worst, field[(j * host._size.x + host._size.x - 1) * step])
	assert_eq(worst, 0.0, "no footprint reaches the rim the clamped edge would repeat")


func test_disc_keeps_the_maximum_of_two() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host)
	host._disc(field, POOL, 0.0, 0.0, 1.0)
	var before := _at(host, field, 0.25, 0.25)
	host._disc(field, POOL, 0.5, 0.0, 0.3)
	assert_eq(_at(host, field, 0.25, 0.25), before)


func test_box_follows_its_turn() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host)
	# A long box (half 2 by 0.25) along x: its far end is covered, the same distance off axis is not.
	host._draw(field, _box(POOL, 0.0, 0.0, 0.0, Vector2(2.0, 0.25), 0.3))
	assert_eq(_at(host, field, 1.75, 0.2), 1.0)
	assert_eq(_at(host, field, 0.2, 1.75), 0.0)
	var turned := _field(host)
	host._draw(turned, _box(POOL, 0.0, 0.0, PI * 0.5, Vector2(2.0, 0.25), 0.3))
	assert_eq(_at(host, turned, 0.2, 1.75), 1.0)
	assert_eq(_at(host, turned, 1.75, 0.2), 0.0)


func test_a_rounded_box_cuts_its_corners() -> void:
	var host := PainterOcclusion.new()
	var square := _field(host)
	host._draw(square, _box(POOL, 0.0, 0.0, 0.0, Vector2(2.0, 1.5), 0.1))
	var rounded := _field(host)
	host._draw(rounded, _box(POOL, 0.0, 0.0, 0.0, Vector2(2.0, 1.5), 0.1, 1.5))
	# The texel at (1.8, 1.3) is inside the square box, outside its corner rounded by 1.5 m.
	assert_eq(_at(host, square, 1.8, 1.3), 1.0)
	assert_lt(_at(host, rounded, 1.8, 1.3), 0.5, "the rounded corner is cut")
	assert_eq(_at(host, rounded, 1.8, 0.2), 1.0, "the box's end on its axis is still covered")


func test_a_tree_the_painter_does_not_grow_gets_a_round_pool() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host)
	# Its foot at the origin, its crown's middle 1 m along x: the pool is a disc round (0.5, 0).
	var marks: Array = []
	host._tree(marks, Vector3.ZERO, Vector3(1.0, 3.0, 0.0), 2.0, 6.0)
	_lay(host, field, marks)
	assert_eq(_at(host, field, 0.3, 0.3), 1.0)
	var along := _at(host, field, 1.8, 0.1)
	var across := _at(host, field, 0.6, 1.3)
	assert_gt(along, 0.0)
	assert_almost_eq(along, across, 0.001, "as far along as across: round, not a box")
	assert_gt(_at(host, field, 0.1, 0.1, CORE), 0.5, "a seam at the trunk's foot")
	assert_eq(_at(host, field, 1.3, 0.3, CORE), 0.0, "the seam stays at the foot, under the pool")


func test_a_small_stone_takes_a_mark_of_its_own_size_at_its_foots_height() -> void:
	var host := PainterOcclusion.new()
	var field := _field(host)
	# Two stones 0.5 m across, 2 m apart, their feet at 5 m.
	var marks: Array = []
	for x: float in [-1.0, 1.0]:
		host._solid(marks, Vector3(x, 5.15, 0.0), 0.0, Vector3(0.25, 0.15, 0.25))
	_lay(host, field, marks)
	assert_gt(_at(host, field, 0.95, 0.1, CORE), 0.9, "a seam under the stone")
	assert_eq(_at(host, field, 0.1, 0.1, CORE), 0.0, "none between the two")
	assert_eq(_at(host, field, 0.95, 0.7, CORE), 0.0, "none half a metre off the stone")
	assert_eq(_at(host, field, 0.1, 0.1, POOL), 0.0, "the pool is the stone's too, not the group's")
	var weight := _at(host, field, 0.95, 0.1, PainterOcclusion.FOOT_CH + 1)
	assert_gt(weight, 0.0, "the mark knows its height")
	var foot := _at(host, field, 0.95, 0.1, PainterOcclusion.FOOT_CH) / weight
	assert_between(foot, 5.0, 5.15, "between the stone's underside and its middle")
	assert_lt(1.0 / weight, 0.6, "and reaches about the stone's own size up and down")
	# A pebble the field cannot hold leaves no mark.
	var none := _field(host)
	var pebble: Array = []
	host._solid(pebble, Vector3(0.0, 0.0, 0.0), 0.0, Vector3(0.05, 0.05, 0.05))
	assert_true(pebble.is_empty(), "no mark at all")
	_lay(host, none, pebble)
	assert_eq(_at(host, none, 0.01, 0.01, CORE), 0.0)


func test_a_boulder_keeps_its_seam_and_a_stone_gets_one_its_size() -> void:
	var boulder := PainterOcclusion.solid_reach(Vector2(1.0, 1.0))
	assert_almost_eq(boulder.x, PainterOcclusion.SEAM_M, 0.001)
	assert_almost_eq(boulder.y, 0.45 + 0.35 * sqrt(2.0), 0.001)
	var stone := PainterOcclusion.solid_reach(Vector2(0.2, 0.3))
	assert_almost_eq(stone.x, 0.1, 0.001, "half its narrower half")
	assert_almost_eq(stone.y, 0.2, 0.001, "and a pool no wider than the stone")


func test_a_mesh_of_three_stones_is_three_islands() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for at: Vector3 in [Vector3(0, 0, 0), Vector3(1.0, 0, 0.2), Vector3(0.4, 0, 1.1)]:
		_tetra(st, at, 0.2)
	# A shell inside the first stone: the same footprint, not a fourth.
	_tetra(st, Vector3(0.02, 0, 0.02), 0.1)
	var bodies := PainterOcclusion.islands(st.commit())
	assert_eq(bodies.size(), 3)
	for body: AABB in bodies:
		assert_lt(maxf(body.size.x, body.size.z), 0.5, "each its own stone's size")
	var one := SurfaceTool.new()
	one.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tetra(one, Vector3.ZERO, 1.0)
	assert_eq(PainterOcclusion.islands(one.commit()).size(), 1)
	assert_eq(PainterOcclusion.islands(BoxMesh.new()).size(), 1, "not an ArrayMesh: its box")


func test_stones_set_side_by_side_stay_apart_though_their_boxes_overlap() -> void:
	# The core library's stone cluster: five stones whose boxes overlap at the corners. Joined on
	# any overlap they were one box, and its mark a metre-wide oval round the group.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for at: Vector3 in [Vector3(0, 0, 0), Vector3(0.5, 0, 0.5), Vector3(0.5, 0, -0.1)]:
		_tetra(st, at, 0.3)
	var bodies := PainterOcclusion.islands(st.commit())
	assert_eq(bodies.size(), 3)
	for body: AABB in bodies:
		assert_almost_eq(body.size.x, 0.6, 0.001, "each its own stone's box")
	var a := Rect2(0.0, 0.0, 1.0, 1.0)
	assert_false(PainterOcclusion.nested(a, Rect2(0.8, 0.8, 1.0, 1.0)), "a corner's overlap")
	assert_false(PainterOcclusion.nested(a, Rect2(2.0, 0.0, 1.0, 1.0)), "apart")
	assert_true(PainterOcclusion.nested(a, Rect2(0.2, 0.2, 0.4, 0.4)), "a shell inside")
	assert_true(PainterOcclusion.nested(a, Rect2(0.7, 0.2, 0.5, 0.4)), "a chip, more in than out")
	assert_true(PainterOcclusion.nested(a, Rect2(0.5, 0.0, 0.0, 1.0)), "a flat sheet inside")


## A tetrahedron of half size `r` standing at `at`, as four unshared triangles (a flat-shaded mesh).
func _tetra(st: SurfaceTool, at: Vector3, r: float) -> void:
	var p := [
		at + Vector3(-r, 0, -r), at + Vector3(r, 0, -r), at + Vector3(0, 0, r), at + Vector3(0, r, 0)
	]
	for face: Array in [[0, 1, 2], [0, 1, 3], [1, 2, 3], [2, 0, 3]]:
		for k: int in face:
			st.add_vertex(p[k])


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
