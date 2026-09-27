extends GutTest

## Sculpting the height grid (phase 3, P3-3a): HeightBrush's pure operations, HeightStroke's
## dabs, diffs, undo and cancel, the terrain's in-place vertex updates (checked against the
## engine's own vertex encoding), the triangle-matched ground the scatter stands on, and
## GroundSnap moving plants and props with the ground.

const GRASS := "grass"
const EPSILON := 1e-4


func _flat(cells: int = 20) -> MapDocument:
	return MapDocument.create_flat(Vector2i(cells, cells), GRASS, "test", 5)


## Rolling ground with slopes everywhere.
func _rolling(cells: int = 20) -> MapDocument:
	var doc := _flat(cells)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			doc.heights[doc.sample_index(x, z)] = sin(p.x * 0.35) * 1.2 + cos(p.y * 0.27) * 0.7
	return doc


func _height_at(doc: MapDocument, p: Vector2) -> float:
	var s := doc.world_to_sample(p).round()
	return doc.heights[doc.sample_index(int(s.x), int(s.y))]


# --- HeightBrush ---------------------------------------------------------------------


func test_raise_and_lower_are_linear_in_exposure_and_clamped() -> void:
	assert_almost_eq(HeightBrush.raise(1.0, 1.0, 2.0, 1.0, 0.6), 1.0 + 2.0 * 0.6, EPSILON)
	assert_almost_eq(HeightBrush.raise(1.0, 0.5, 1.0, -1.0, 0.6), 1.0 - 0.5 * 0.6, EPSILON)
	# The speed follows the brush, so a hill keeps its proportions at any size.
	assert_almost_eq(HeightBrush.raise_speed(5.0), 5.0 * HeightBrush.RAISE_PER_RADIUS, EPSILON)
	assert_eq(HeightBrush.raise_speed(0.5), HeightBrush.RAISE_MIN_M_PER_S, "small brushes")
	var top := MapDocument.MAX_ABS_HEIGHT_M
	assert_eq(HeightBrush.raise(top - 0.1, 1.0, 10.0), top, "never past the document limit")
	assert_eq(HeightBrush.raise(-top + 0.1, 1.0, 10.0, -1.0), -top)


func test_approach_operations_never_overshoot_their_goal() -> void:
	for op in [HeightBrush.SMOOTH, HeightBrush.FLATTEN, HeightBrush.TIER]:
		var h := 3.0
		for _step in 50:
			h = HeightBrush.apply(op, h, 1.0, 0.1, 1.0)
			assert_true(h >= 1.0 - EPSILON, "op %d stays above its goal" % op)
		assert_almost_eq(h, 1.0, 0.01, "op %d reaches its goal" % op)
	assert_eq(HeightBrush.apply(HeightBrush.FLATTEN, 2.0, 0.0, 1.0, 0.0), 2.0, "zero weight")


func test_tiers_take_full_weight_inside_the_ring() -> void:
	# A tier's shape is HeightBrush.tier_goal()'s (test_sculpt_tool.gd), not a falloff's.
	for op in [HeightBrush.TIER, HeightBrush.TIER_CUT]:
		assert_eq(HeightBrush.weight(op, 0.0), 1.0)
		assert_eq(HeightBrush.weight(op, 0.99), 1.0)
		assert_eq(HeightBrush.weight(op, 1.0), 0.0)
	assert_eq(HeightBrush.weight(HeightBrush.RAISE, 0.5), MaskBrush.falloff(0.5))


func test_box_mean_matches_a_brute_force_mean_with_clamped_edges() -> void:
	var width := 23
	var depth := 17
	var heights := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in width * depth:
		heights.append(rng.randf_range(-2.0, 2.0))
	for k in [1, 3]:
		var rect := Rect2i(0, 2, 9, 7)
		var means := HeightBrush.box_mean(heights, width, depth, rect, k)
		var worst := 0.0
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var sum := 0.0
				for dz in range(-k, k + 1):
					for dx in range(-k, k + 1):
						var sx := clampi(x + dx, 0, width - 1)
						var sz := clampi(z + dz, 0, depth - 1)
						sum += heights[sz * width + sx]
				var expected := sum / float((2 * k + 1) * (2 * k + 1))
				var got := means[(z - rect.position.y) * rect.size.x + x - rect.position.x]
				worst = maxf(worst, absf(got - expected))
		assert_lt(worst, 1e-4, "k %d" % k)


func test_smooth_kernel_scales_with_the_brush() -> void:
	assert_eq(HeightBrush.smooth_kernel(0.5, 0.25), 1, "at least one sample")
	assert_eq(HeightBrush.smooth_kernel(10.0, 0.25), 14)
	assert_gt(HeightBrush.smooth_kernel(12.0, 0.25), HeightBrush.smooth_kernel(4.0, 0.25))


func test_tier_levels_round_trip() -> void:
	assert_almost_eq(HeightBrush.tier_height(2, 1.524), 3.048, EPSILON)
	assert_eq(HeightBrush.tier_level(3.0, 1.524), 2)
	assert_eq(HeightBrush.tier_level(-0.7, 1.524), 0)


# --- HeightStroke --------------------------------------------------------------------


func test_raise_dab_builds_a_soft_hill_and_reports_its_rectangle() -> void:
	var doc := _flat()
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	assert_true(stroke.dab(Vector2.ZERO, Vector2.ZERO, 3.0, 1.0))
	var centre := _height_at(doc, Vector2.ZERO)
	assert_almost_eq(centre, HeightBrush.raise_speed(3.0), 0.01, "full weight at the centre")
	assert_almost_eq(_height_at(doc, Vector2(3.2, 0.0)), 0.0, EPSILON, "nothing past the rim")
	var half := _height_at(doc, Vector2(1.5, 0.0))
	assert_between(half, 0.4 * centre, 0.7 * centre, "falloff halfway")
	var pending := stroke.take_pending()
	assert_true(pending.has_area())
	assert_false(stroke.take_pending().has_area(), "taken once")
	var world := MaskBrush.sample_rect_to_world(doc, pending)
	assert_true(world.grow(0.01).has_point(Vector2(2.9, 0.0)))
	assert_false(world.has_point(Vector2(3.5, 0.0)))


func test_a_stroke_undoes_and_redoes_exactly() -> void:
	var doc := _rolling()
	var start := doc.heights.duplicate()
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(-5, -5), Vector2(8, 3), 4.0, 0.8)
	stroke.dab(Vector2(8, 3), Vector2(12, 12), 4.0, 0.5)
	var after := doc.heights.duplicate()
	var diff := stroke.finish()
	assert_false(diff.is_empty())
	assert_gt(int(diff.bytes), 0)
	var whole: Rect2i = diff.rect
	assert_true(whole.encloses(stroke.changed), "the diff covers every change")
	HeightStroke.apply_diff(doc, diff, false)
	assert_eq(doc.heights, start, "undo")
	HeightStroke.apply_diff(doc, diff, true)
	assert_eq(doc.heights, after, "redo")


func test_cancel_puts_every_height_back() -> void:
	var doc := _rolling()
	var start := doc.heights.duplicate()
	var stroke := HeightStroke.begin(doc, HeightBrush.LOWER)
	stroke.dab(Vector2(0, 0), Vector2(6, 0), 5.0, 1.0)
	assert_ne(doc.heights, start)
	var rect := stroke.revert()
	assert_true(rect.has_area())
	assert_eq(doc.heights, start)


func test_a_stroke_that_changes_nothing_leaves_no_diff() -> void:
	var doc := _flat()
	var stroke := HeightStroke.begin(doc, HeightBrush.FLATTEN, 0.0)
	assert_false(stroke.dab(Vector2.ZERO, Vector2(3, 0), 3.0, 1.0), "already flat at 0")
	assert_eq(stroke.finish(), {})


func test_flatten_and_smooth_pull_toward_their_goals() -> void:
	var doc := _rolling()
	var flatten := HeightStroke.begin(doc, HeightBrush.FLATTEN, 0.5)
	for _frame in 60:
		flatten.dab(Vector2.ZERO, Vector2.ZERO, 4.0, 0.05)
	assert_almost_eq(_height_at(doc, Vector2.ZERO), 0.5, 0.01, "centre flattened to the target")
	var spike := _flat()
	var i := spike.sample_index(spike.samples_x() / 2, spike.samples_z() / 2)
	spike.heights[i] = 4.0
	var smooth := HeightStroke.begin(spike, HeightBrush.SMOOTH)
	smooth.dab(Vector2.ZERO, Vector2.ZERO, 3.0, 0.5)
	assert_lt(spike.heights[i], 2.0, "a spike is pulled toward the local mean")
	assert_gt(spike.heights[i + 1], 0.0, "and its neighbours toward it")


func test_heights_stay_within_the_document_limits() -> void:
	var doc := _flat()
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2.ZERO, Vector2.ZERO, 2.0, 10000.0)
	assert_eq(_height_at(doc, Vector2.ZERO), MapDocument.MAX_ABS_HEIGHT_M)


# --- Triangle-matched ground ---------------------------------------------------------


func test_triangle_height_follows_the_mesh_diagonal() -> void:
	# A saddle: bilinear reads 0.5 at the quad centre, the triangles read the diagonal's
	# mean, (h10 + h01) / 2.
	var grid := PackedFloat32Array([0.0, 1.0, 0.0, 0.0])
	assert_almost_eq(ScatterGenerator.triangle_height(grid, 2, 2, Vector2(0.5, 0.5)), 0.5, EPSILON)
	grid = PackedFloat32Array([1.0, 0.0, 0.0, 1.0])
	assert_almost_eq(ScatterGenerator.triangle_height(grid, 2, 2, Vector2(0.5, 0.5)), 0.0, EPSILON)
	assert_almost_eq(ScatterGenerator.triangle_height(grid, 2, 2, Vector2(0.2, 0.2)), 0.6, EPSILON)
	assert_almost_eq(ScatterGenerator.triangle_height(grid, 2, 2, Vector2(0.8, 0.8)), 0.6, EPSILON)
	assert_almost_eq(ScatterGenerator.triangle_height(grid, 2, 2, Vector2(1.0, 1.0)), 1.0, EPSILON)
	assert_almost_eq(ScatterGenerator.triangle_height(grid, 2, 2, Vector2(-3, 9)), 0.0, EPSILON)


func test_document_heights_match_the_mesh_triangles() -> void:
	var doc := _rolling()
	var fields := ScatterGenerator.document_fields(doc, "")
	var worst := 0.0
	for cell in [Vector2i(0, 0), Vector2i(-2, 1)]:
		var arrays := TerrainMeshBuilder.build_chunk_arrays(doc, cell)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size(), 3 * 97):
			var a := vertices[indices[t]]
			var b := vertices[indices[t + 1]]
			var c := vertices[indices[t + 2]]
			var p := (a + b + c) / 3.0
			worst = maxf(worst, absf(fields.height_at.call(Vector2(p.x, p.z)) - p.y))
	assert_lt(worst, 1e-4, "a row at a triangle's centroid stands on that triangle")


func test_triangle_normal_is_the_vertex_normal_at_a_vertex_and_smooth_between() -> void:
	var doc := _rolling()
	var fields := ScatterGenerator.document_fields(doc, "")
	var sample := Vector2i(40, 33)
	var at := doc.sample_to_world(Vector2(sample))
	var expected := TerrainMeshBuilder.sample_normal(doc, sample.x, sample.y)
	assert_true((fields.normal_at.call(at) as Vector3).is_equal_approx(expected))
	var step := doc.sample_step().x
	var a: Vector3 = fields.normal_at.call(at + Vector2(step * 0.49, step * 0.5))
	var b: Vector3 = fields.normal_at.call(at + Vector2(step * 0.51, step * 0.5))
	assert_lt(a.angle_to(b), 0.01, "no jump across the diagonal")


# --- Terrain in place ----------------------------------------------------------------


func test_vertex_mirror_matches_the_engine_encoding() -> void:
	var doc := _rolling()
	var cell := Vector2i(0, -1)
	var mesh := TerrainMeshBuilder.build_chunk_mesh(doc, cell, null)
	var surface := RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var engine: PackedByteArray = surface["vertex_data"]
	var mirror := TerrainMeshBuilder.chunk_vertex_mirror(doc, cell)
	var rows := int(mirror.rows)
	var bytes := TerrainMeshBuilder.vertex_rows_bytes(mirror, 0, rows - 1)
	var positions: PackedByteArray = bytes.positions
	var normals: PackedByteArray = bytes.normals
	assert_eq(bytes.normal_offset, positions.size())
	assert_eq(positions.size() + normals.size(), engine.size(), "same stream size")
	assert_true(positions == engine.slice(0, positions.size()), "positions bit-identical")
	assert_true(normals == engine.slice(positions.size()), "normals and tangents bit-identical")


func test_partial_update_equals_a_fresh_mirror() -> void:
	var doc := _rolling()
	var cell := Vector2i(0, 0)
	var mirror := TerrainMeshBuilder.chunk_vertex_mirror(doc, cell)
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(3, 3), Vector2(6, 4), 2.0, 1.0)
	var changed := stroke.take_pending()
	TerrainMeshBuilder.write_vertex_region(doc, mirror, changed.grow(1))
	var fresh := TerrainMeshBuilder.chunk_vertex_mirror(doc, cell)
	assert_eq(mirror.positions, fresh.positions)
	assert_eq(mirror.normals, fresh.normals, "normals one sample around the edit too")


func test_terrain_updates_in_place_then_settles() -> void:
	var doc := _flat()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var chunk := terrain.get_chunk(Vector2i(0, 0))
	var mesh := chunk.mesh
	assert_eq(chunk.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "flat")
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(5, 5), Vector2(5, 5), 3.0, 5.0)
	terrain.queue_heights(stroke.take_pending())
	assert_true(terrain.has_height_work())
	assert_true(terrain.process_heights(-1), "all done without a budget")
	assert_eq(chunk.mesh, mesh, "updated in place, not rebuilt")
	assert_gt((mesh as ArrayMesh).custom_aabb.end.y, 1.0, "culling sees the raised ground")
	assert_eq(chunk.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_almost_eq(terrain.height_range().y, _height_at(doc, Vector2(5, 5)), 0.01)
	assert_true(terrain.has_unsettled_chunks())
	terrain.settle_heights()
	terrain.process_heights(-1)
	assert_false(terrain.has_unsettled_chunks())
	assert_ne(chunk.mesh, mesh, "settled by a rebuild")
	assert_almost_eq(chunk.mesh.get_aabb().end.y, terrain.height_range().y, EPSILON, "exact AABB")


func test_a_budget_spreads_chunks_over_calls() -> void:
	var doc := _flat(40)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(-8, -8), Vector2(8, 8), 6.0, 1.0)
	terrain.queue_heights(stroke.take_pending())
	terrain.process_heights(0)
	assert_eq(terrain.last_heights_chunks, 1, "a spent budget still makes progress")
	assert_true(terrain.has_height_work())
	var calls := 1
	while not terrain.process_heights(0):
		calls += 1
	assert_gt(calls, 4)


func test_skirt_follows_an_edge_edit_without_a_new_material() -> void:
	var doc := _flat()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var skirt := terrain.get_skirt()
	var material := skirt.mesh.surface_get_material(0)
	var edge := -doc.extent_m().x * 0.5
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(edge, 0), Vector2(edge, 0), 3.0, 1.0)
	terrain.queue_heights(stroke.take_pending())
	terrain.process_heights(-1)
	assert_eq(terrain.get_skirt(), skirt, "same node")
	assert_eq(skirt.mesh.surface_get_material(0), material, "same material, not a duplicate")
	# The skirt is updated in place; headless mesh reads do not see in-place updates, so read
	# its vertex copy (test_authored_terrain checks the copy against a rebuild and the
	# engine's layout).
	var positions: PackedFloat32Array = (terrain.get("_skirt_mirror") as Dictionary).positions
	var top := 0.0
	for i in range(1, positions.size(), 3):
		top = maxf(top, positions[i])
	assert_almost_eq(top, _height_at(doc, Vector2(edge, 0)), 0.01, "the ring rises with the edge")


func test_collision_follows_a_sculpt_update() -> void:
	var doc := _flat()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	await wait_physics_frames(2)
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(1, 1), Vector2(1, 1), 3.0, 1.0)
	terrain.update_collision()
	var space := terrain.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(1, 50, 1), Vector3(1, -50, 1), 1)
	var hit := space.intersect_ray(query)
	assert_false(hit.is_empty())
	if not hit.is_empty():
		var expected := ScatterGenerator.triangle_height(
			doc.heights, doc.samples_x(), doc.samples_z(), doc.world_to_sample(Vector2(1, 1))
		)
		assert_almost_eq(
			hit.position.y, expected, 0.01, "the same frame's query hits the new ground"
		)


func test_the_cpu_ray_march_agrees_with_the_collision() -> void:
	var doc := _rolling()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	await wait_physics_frames(2)
	var space := terrain.get_world_3d().direct_space_state
	var span := terrain.height_range()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	var normal_worst := 0.0
	var disagreements := 0
	for _i in 200:
		var target := Vector3(rng.randf_range(-14, 14), 0.0, rng.randf_range(-14, 14))
		# Camera-like rays: steep to shallow, from every side.
		var direction := Vector3(
			rng.randf_range(-1, 1), -rng.randf_range(0.3, 1.5), rng.randf_range(-1, 1)
		)
		var origin := target - direction.normalized() * 60.0
		var marched := TerrainMeshBuilder.raycast(doc, origin, direction, 200.0, span)
		var query := PhysicsRayQueryParameters3D.create(
			origin, origin + direction.normalized() * 200.0, 1
		)
		var hit := space.intersect_ray(query)
		if hit.is_empty() != marched.is_empty():
			disagreements += 1
			continue
		if hit.is_empty():
			continue
		worst = maxf(worst, (hit.position - (marched.position as Vector3)).length())
		normal_worst = maxf(normal_worst, (hit.normal as Vector3).angle_to(marched.normal))
	assert_eq(disagreements, 0, "hit and miss agree")
	assert_lt(worst, 0.005, "same point as the physics ray")
	assert_lt(normal_worst, 0.01, "same facet normal")
	assert_true(
		TerrainMeshBuilder.raycast(doc, Vector3(0, 50, 0), Vector3.UP, 100.0, span).is_empty(),
		"a ray pointing away misses"
	)
	var vertical := TerrainMeshBuilder.raycast(doc, Vector3(2, 50, 3), Vector3.DOWN, 100.0, span)
	assert_almost_eq(
		(vertical.position as Vector3).y,
		ScatterGenerator.triangle_height(
			doc.heights, doc.samples_x(), doc.samples_z(), doc.world_to_sample(Vector2(2, 3))
		),
		1e-4,
		"straight down"
	)


# --- Flat-ground assumptions ---------------------------------------------------------


func test_the_zoom_fit_leaves_room_for_ground_below_zero() -> void:
	var basis := Basis.from_euler(Vector3(-0.6, PI / 4.0, 0.0))
	var aspect := CameraController.REFERENCE_ASPECT
	var level := CameraController.fit_size_for_extent(basis, Vector2(60, 60), 12.0)
	assert_eq(
		CameraController.fit_size_for_extent(basis, Vector2(60, 60), 12.0, aspect, 0.0), level
	)
	assert_eq(
		CameraController.fit_size_for_extent(basis, Vector2(60, 60), 12.0, aspect, 3.0),
		level,
		"a floor above zero never shrinks the fit"
	)
	assert_gt(
		CameraController.fit_size_for_extent(basis, Vector2(60, 60), 12.0, aspect, -8.0), level
	)


func test_the_far_ground_depth_reaches_sunken_ground() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	add_child_autofree(camera)
	camera.look_at_from_position(Vector3(20, 25, 20), Vector3.ZERO, Vector3.UP)
	var viewport := Vector2(1920, 1080)
	var level := LevelEnvironmentManager.far_ground_depth(camera, viewport)
	assert_gt(level, 0.0)
	assert_eq(LevelEnvironmentManager.far_ground_depth(camera, viewport, 0.0), level)
	assert_gt(LevelEnvironmentManager.far_ground_depth(camera, viewport, -5.0), level)
	assert_lt(LevelEnvironmentManager.far_ground_depth(camera, viewport, 5.0), level)


# --- Snapping rows -------------------------------------------------------------------


func _row(p: Vector3, up: Vector3, yaw: float) -> PackedFloat32Array:
	return PropRows.make_row(p, up, true, yaw, 1.0)


func test_snap_rows_follow_the_ground_and_keep_yaw_and_lean() -> void:
	var doc := _flat()
	var before := doc.heights.duplicate()
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(0, 0), Vector2(0, 0), 4.0, 1.0)
	var grid := GroundSnap.grid_of(doc)
	var lean := Vector3(0.1, 1.0, 0.0).normalized()
	var rows := _row(Vector3(1.5, 0.0, 0.5), lean, 0.7)
	rows.append_array(_row(Vector3(9.0, 0.0, 9.0), Vector3.UP, 0.2))
	var window := Rect2(-5, -5, 10, 10)
	var snapped := GroundSnap.snap_rows(rows, rows, before, doc.heights, grid, true, window)
	assert_eq(snapped.moved, PackedInt32Array([0]), "only the row on the hill")
	var out: PackedFloat32Array = snapped.rows
	var fields := ScatterGenerator.document_fields(doc, "")
	assert_almost_eq(out[1], fields.height_at.call(Vector2(1.5, 0.5)), 1e-5, "on the ground")
	var q_before := Quaternion(rows[3], rows[4], rows[5], rows[6])
	var q_after := Quaternion(out[3], out[4], out[5], out[6])
	var ground: Vector3 = fields.normal_at.call(Vector2(1.5, 0.5))
	var turned := Quaternion(Vector3.UP, ground)
	assert_true((turned * q_before).is_equal_approx(q_after), "turned by the ground's arc")
	assert_eq(out.slice(10), rows.slice(10), "the far row is untouched")
	var upright := GroundSnap.snap_rows(rows, rows, before, doc.heights, grid, false, window)
	var kept: PackedFloat32Array = upright.rows
	assert_eq(kept.slice(3, 7), rows.slice(3, 7), "upright species do not tilt")


func test_rebed_props_moves_only_props_whose_ground_changed() -> void:
	var doc := _flat()
	var before := doc.heights.duplicate()
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(0, 0), Vector2(0, 0), 3.0, 1.0)
	var grid := GroundSnap.grid_of(doc)
	var rows := _row(Vector3(1.0, 0.0, 0.0), Vector3.UP, 1.1)
	rows.append_array(_row(Vector3(6.0, 0.0, 6.0), Vector3.UP, -0.4))
	var window := Rect2(-10, -10, 20, 20)
	var bedded := GroundSnap.rebed_props(rows, rows, before, doc.heights, grid, true, window)
	assert_eq(bedded.moved, PackedInt32Array([0]))
	var row := PropRows.row_at(bedded.rows, 0)
	var fields := ScatterGenerator.document_fields(doc, "")
	assert_almost_eq(row[1], fields.height_at.call(Vector2(1.0, 0.0)), 1e-5)
	assert_almost_eq(PropRows.row_yaw(row), 1.1, 1e-4, "yaw kept")
	var normal: Vector3 = fields.normal_at.call(Vector2(1.0, 0.0))
	assert_almost_eq(PropRows.row_up(row).angle_to(normal), 0.0, 1e-4, "stands on the new normal")
