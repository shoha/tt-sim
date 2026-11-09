extends GutTest

## TerrainCollision (card authcollide): the tile layout (square tiles that chain over the grid,
## the last on each axis ending on the edge), which tiles an edit marks, and the contract that
## made the tiles safe: after random sculpt strokes that only mark the tiles they touched, rays
## hit the tiled collision where they hit one HeightMapShape3D over the whole grid (the collision
## before tiles), on a grid of vertical rays through every tile border and shared corner and on
## slanted camera-like rays, for a square and an oblong map (overlapping last tiles). Every
## vertical ray hits the tiles; the whole shape of the oblong map (Jolt's triangle-mesh fallback
## for a non-square heightfield) let 40 of them through on two sample rows (measured 2026-11-08).

const GRASS := "grass"
## Jolt stores a heightfield's samples quantised against each shape's own height range, so a
## tile and the whole-grid shape agree to well under a millimetre rather than bit for bit (the
## worst measured was printed by the test; the collision itself is within a centimetre of the
## document, test_authored_terrain).
const HIT_TOLERANCE_M := 0.002
## Vertical rays hit the document's own triangles within a centimetre, as test_authored_terrain
## asks of the collision.
const DOCUMENT_TOLERANCE_M := 0.01
## The whole-grid reference shape sits on this physics layer only; the tiles are on layer 1.
const REFERENCE_LAYER := 2


func _sine(cells: Vector2i) -> MapDocument:
	var doc := MapDocument.create_flat(cells, GRASS, "test", 7)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			doc.heights[doc.sample_index(x, z)] = sin(p.x * 0.4) * 1.5 + cos(p.y * 0.3) * 0.8
	return doc


## One StaticBody3D with one HeightMapShape3D over the whole grid, on REFERENCE_LAYER.
func _whole_shape(doc: MapDocument) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = REFERENCE_LAYER
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = doc.samples_x()
	shape.map_depth = doc.samples_z()
	shape.map_data = TerrainMeshBuilder.collision_heights(doc)
	collision.shape = shape
	body.add_child(collision)
	body.transform = TerrainMeshBuilder.collision_transform(doc)
	return body


func test_tile_starts_chain_over_every_quad() -> void:
	for quads in [4, 31, 32, 33, 64, 122, 244, 390]:
		var size := mini(TerrainCollision.TILE_QUADS, quads)
		var starts := TerrainCollision.tile_starts(quads, size)
		assert_eq(starts[0], 0, "%d quads: first tile at the edge" % quads)
		assert_eq(starts[starts.size() - 1] + size, quads, "%d quads: last ends on the edge" % quads)
		for i in range(1, starts.size()):
			assert_true(
				starts[i] > starts[i - 1] and starts[i] - starts[i - 1] <= size,
				"%d quads: tile %d chains on without a gap" % [quads, i]
			)


func test_tile_size_is_square_and_fits_a_small_map() -> void:
	assert_eq(TerrainCollision.tile_size(391, 391), TerrainCollision.TILE_QUADS)
	assert_eq(TerrainCollision.tile_size(20, 50), 19, "the shorter side of a small map")


func test_an_edit_marks_only_the_tiles_holding_its_samples() -> void:
	var doc := _sine(Vector2i(20, 20))
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var size := TerrainCollision.tile_size(doc.samples_x(), doc.samples_z())
	assert_eq(terrain.update_collision_region(Rect2i(1, 1, 2, 2)), 1, "inside one tile")
	assert_eq(
		terrain.update_collision_region(Rect2i(size, size, 1, 1)),
		4,
		"a corner sample belongs to the four tiles that share it"
	)
	assert_eq(terrain.update_collision_region(Rect2i()), 0, "nothing for an empty rect")
	var everything := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	assert_eq(
		terrain.update_collision_region(everything),
		terrain.get_collision_bodies().size(),
		"the whole grid marks every tile"
	)


func test_tiled_collision_matches_one_whole_shape_after_random_strokes() -> void:
	for cells: Vector2i in [Vector2i(20, 20), Vector2i(26, 14)]:
		await _check_strokes(cells)


func _check_strokes(cells: Vector2i) -> void:
	var doc := _sine(cells)
	var terrain := AuthoredTerrain.create(doc)
	add_child(terrain)
	assert_gt(terrain.get_collision_bodies().size(), 4, "%s: several tiles" % cells)
	var reference := _whole_shape(doc)
	add_child(reference)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var half := doc.extent_m() * 0.5
	var operations := [HeightBrush.RAISE, HeightBrush.LOWER, HeightBrush.SMOOTH, HeightBrush.FLATTEN]
	for s in 12:
		var stroke := HeightStroke.begin(doc, operations[s % 4], rng.randf_range(-1.0, 2.0))
		var at := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		var radius := rng.randf_range(1.0, 5.0)
		for _d in 6:
			var next := (at + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))).clamp(
				-half, half
			)
			stroke.dab(at, next, radius, 0.15)
			terrain.mark_collision(stroke.take_pending())
			at = next
		# Flushed every few strokes, as HeightEditor does once a stroke has ended.
		if s % 3 == 2:
			terrain.flush_collision()
	terrain.flush_collision()
	var shape: HeightMapShape3D = (reference.get_child(0) as CollisionShape3D).shape
	shape.map_data = TerrainMeshBuilder.collision_heights(doc)
	await wait_physics_frames(2)
	var space := terrain.get_world_3d().direct_space_state
	var worst := 0.0
	var worst_doc := 0.0
	var worst_whole_doc := 0.0
	var only_tiled := 0
	var rays := 0
	for ray: Array in _probe_rays(doc, rng):
		var tiled := _hit(space, ray[0], ray[1], 1)
		var whole := _hit(space, ray[0], ray[1], REFERENCE_LAYER)
		rays += 1
		var from: Vector3 = ray[0]
		var to: Vector3 = ray[1]
		if from.x == to.x and from.z == to.z:
			assert_false(tiled.is_empty(), "%s: no crack under a vertical ray at %s" % [cells, from])
			var ground := TerrainMeshBuilder.world_ground_height(
				doc, Transform3D.IDENTITY, Vector2(from.x, from.z)
			)
			if not tiled.is_empty():
				worst_doc = maxf(worst_doc, absf(tiled.position.y - ground))
			if not whole.is_empty():
				worst_whole_doc = maxf(worst_whole_doc, absf(whole.position.y - ground))
		if whole.is_empty():
			# The whole shape of an oblong grid is Jolt's triangle-mesh fallback, which lets rays
			# exactly on some sample rows through; the square tiles do not.
			only_tiled += 0 if tiled.is_empty() else 1
			continue
		assert_false(tiled.is_empty(), "%s: the tiles hit where the whole shape hit %s" % [cells, ray])
		if not tiled.is_empty():
			worst = maxf(worst, (tiled.position as Vector3).distance_to(whole.position))
	gut.p(
		(
			(
				"%s: %d rays, worst tiled-whole %.6f m, tiled-document %.6f m, whole-document %.6f m,"
				+ " %d rays only the tiles hit"
			)
			% [cells, rays, worst, worst_doc, worst_whole_doc, only_tiled]
		)
	)
	if cells.x == cells.y:
		assert_eq(only_tiled, 0, "%s: a square grid's whole shape is a heightfield too" % cells)
	assert_lt(worst, HIT_TOLERANCE_M, "%s: tiled hits match the whole shape's" % cells)
	assert_lt(worst_doc, DOCUMENT_TOLERANCE_M, "%s: tiled hits lie on the document surface" % cells)
	# Both maps sit at the origin: the next one must not see this one's shapes.
	terrain.free()
	reference.free()
	await wait_physics_frames(1)


func _hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


## [from, to] pairs: vertical rays on every tile border sample, either side of it and at every
## shared corner, a few at random, and slanted rays from every side.
func _probe_rays(doc: MapDocument, rng: RandomNumberGenerator) -> Array:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var size := TerrainCollision.tile_size(columns, rows)
	var along := func(samples: int) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		for start in TerrainCollision.tile_starts(samples - 1, size):
			for offset in [0.0, 0.37, -0.41, float(size)]:
				out.append(clampf(start + offset, 0.01, samples - 1.01))
		for _i in 6:
			out.append(rng.randf_range(0.01, samples - 1.01))
		return out
	var rays := []
	for sz in along.call(rows):
		for sx in along.call(columns):
			var p := doc.sample_to_world(Vector2(sx, sz))
			rays.append([Vector3(p.x, 50.0, p.y), Vector3(p.x, -50.0, p.y)])
	var half := doc.extent_m() * 0.45
	for _i in 300:
		var target := Vector3(rng.randf_range(-half.x, half.x), 0.0, rng.randf_range(-half.y, half.y))
		var direction := Vector3(
			rng.randf_range(-1, 1), -rng.randf_range(0.3, 1.5), rng.randf_range(-1, 1)
		).normalized()
		rays.append([target - direction * 40.0, target + direction * 40.0])
	return rays
