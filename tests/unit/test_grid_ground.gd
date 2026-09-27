extends GutTest

## The grid overlay's ground on Blender (GLB) maps (P3-3c): a GLB-like map's layer-1
## collision sampled into a GroundHeightField (DressingGround.begin_grid), misses filled from
## the nearest hit, the fixed Y = 0 band kept for maps with no collision or whose ground is at
## Y = 0 already, and the field plumbed through GameMap to GridOverlay's shader. The
## collision is built here: a planar ramp (y = RAMP_SLOPE * x + RAMP_BASE over 8 x 8 m) with a
## square hole in the middle, and a step (a box top at STEP_TOP for x < 0 beside a floor at
## Y = 0).

const RAMP_SLOPE := 0.25
const RAMP_BASE := 1.0
const HALF := 4.0
const HOLE := 1.0
const STEP_TOP := 1.5
const TOP := 50.0
const EPSILON := 0.001

var _container: Node3D = null
var _map: Node3D = null


func before_each() -> void:
	_container = Node3D.new()
	_container.name = "MapContainer"
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)


func _ramp_height(x: float) -> float:
	return RAMP_SLOPE * x + RAMP_BASE


func _ramp_point(x: float, z: float) -> Vector3:
	return Vector3(x, _ramp_height(x), z)


## Two triangles for the ramp over [x0, x1] x [z0, z1].
func _ramp_quad(x0: float, x1: float, z0: float, z1: float) -> PackedVector3Array:
	var a := _ramp_point(x0, z0)
	var b := _ramp_point(x1, z0)
	var c := _ramp_point(x1, z1)
	var d := _ramp_point(x0, z1)
	return PackedVector3Array([a, b, c, a, c, d])


func _add_body(shape: Shape3D, position: Vector3 = Vector3.ZERO, layer: int = 1) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	_map.add_child(body)


func _add_faces(faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	_add_body(shape)


## The ramp over the whole 8 x 8 m square except a HOLE-wide square hole at the centre.
func _add_ramp_with_hole() -> void:
	var faces := PackedVector3Array()
	faces.append_array(_ramp_quad(-HALF, HALF, -HALF, -HOLE))
	faces.append_array(_ramp_quad(-HALF, HALF, HOLE, HALF))
	faces.append_array(_ramp_quad(-HALF, -HOLE, -HOLE, HOLE))
	faces.append_array(_ramp_quad(HOLE, HALF, -HOLE, HOLE))
	_add_faces(faces)


## A step: a box whose top is at STEP_TOP over x < 0, a floor at Y = 0 over x > 0.
func _add_step() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(HALF, STEP_TOP, 2.0 * HALF)
	_add_body(box, Vector3(-HALF * 0.5, STEP_TOP * 0.5, 0.0))
	_add_faces(
		PackedVector3Array(
			[
				Vector3(0, 0, -HALF),
				Vector3(HALF, 0, -HALF),
				Vector3(HALF, 0, HALF),
				Vector3(0, 0, -HALF),
				Vector3(HALF, 0, HALF),
				Vector3(0, 0, HALF),
			]
		)
	)


## A visible mesh spanning the square, which is what the map's bounds are measured from.
func _add_visual() -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0 * HALF, 2.0 * HALF)
	mesh.mesh = plane
	_map.add_child(mesh)


func _grid() -> Dictionary:
	return GroundHeightField.grid_for_bounds(
		AABB(Vector3(-HALF, 0, -HALF), Vector3(2.0 * HALF, 0, 2.0 * HALF)), 0.5
	)


func _sample(grid: Dictionary) -> DressingGround:
	var sampler := DressingGround.begin_grid(
		_map.get_world_3d(),
		_map.global_transform,
		TOP,
		grid.origin,
		grid.step,
		grid.columns,
		grid.rows
	)
	var guard := 0
	while not sampler.step(1) and guard < 10000:
		guard += 1
	return sampler


func _field(grid: Dictionary, sampler: DressingGround) -> GroundHeightField:
	return GroundHeightField.for_glb(
		_map, sampler.heights, sampler.hits, grid.columns, grid.rows, grid.origin, grid.step
	)


# --- sampling a GLB-like collision -------------------------------------------------------


func test_a_ramp_is_sampled_and_the_field_follows_it_between_samples() -> void:
	_add_ramp_with_hole()
	await get_tree().physics_frame
	var grid := _grid()
	var sampler := _sample(grid)
	var field := _field(grid, sampler)
	assert_not_null(field, "a ramp from Y = 0 to 2 is not the fixed band's ground")
	for z in grid.rows:
		for x in grid.columns:
			var i: int = z * grid.columns + x
			if sampler.hits[i] == 0:
				continue
			var p: Vector2 = grid.origin + Vector2(x, z) * grid.step
			assert_almost_eq(sampler.heights[i], _ramp_height(p.x), EPSILON)
	# Between samples, off the hole: a plane interpolates exactly.
	for p in [Vector2(-3.1, 2.3), Vector2(2.7, -3.45), Vector2(3.3, 0.2)]:
		assert_almost_eq(field.world_height_at(p), _ramp_height(p.x), EPSILON)


func test_a_hole_takes_the_nearest_hit_so_the_grid_stays_continuous() -> void:
	_add_ramp_with_hole()
	await get_tree().physics_frame
	var grid := _grid()
	var sampler := _sample(grid)
	var centre: int = (grid.rows / 2) * grid.columns + grid.columns / 2
	assert_eq(sampler.hits[centre], 0, "the hole's centre has no collision")
	assert_gt(sampler.miss_count(), 0)
	for z in grid.rows:
		for x in grid.columns:
			var i: int = z * grid.columns + x
			if sampler.hits[i] != 0:
				continue
			var p: Vector2 = grid.origin + Vector2(x, z) * grid.step
			# The nearest hit is at most the hole's half width plus a step away along X.
			var reach: float = RAMP_SLOPE * (HOLE + grid.step.x) + EPSILON
			assert_almost_eq(sampler.heights[i], _ramp_height(p.x), reach)


func test_a_step_keeps_both_levels() -> void:
	_add_step()
	await get_tree().physics_frame
	var grid := _grid()
	var sampler := _sample(grid)
	assert_eq(sampler.miss_count(), 0)
	var field := _field(grid, sampler)
	assert_not_null(field, "half the ground is 1.5 m up")
	assert_almost_eq(field.world_height_at(Vector2(-2.2, 1.3)), STEP_TOP, EPSILON)
	assert_almost_eq(field.world_height_at(Vector2(2.2, -1.3)), 0.0, EPSILON)


func test_other_layers_are_not_ground() -> void:
	# Tokens (layer 2) and anything else off layer 1 are not sampled; only the floor is.
	_add_faces(
		PackedVector3Array(
			[
				Vector3(-HALF, -1.2, -HALF),
				Vector3(HALF, -1.2, -HALF),
				Vector3(HALF, -1.2, HALF),
				Vector3(-HALF, -1.2, -HALF),
				Vector3(HALF, -1.2, HALF),
				Vector3(-HALF, -1.2, HALF),
			]
		)
	)
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	_add_body(box, Vector3.ZERO, 2)
	await get_tree().physics_frame
	var grid := _grid()
	var sampler := _sample(grid)
	for h in sampler.heights:
		assert_almost_eq(h, -1.2, EPSILON)


func test_no_collision_keeps_the_fixed_band() -> void:
	await get_tree().physics_frame
	var grid := _grid()
	var sampler := _sample(grid)
	assert_eq(sampler.miss_count(), sampler.heights.size())
	assert_null(_field(grid, sampler), "no layer-1 collision: the fixed band as before")


func test_a_floor_at_y0_keeps_the_fixed_band() -> void:
	_add_faces(
		PackedVector3Array(
			[
				Vector3(-HALF, 0, -HALF),
				Vector3(HALF, 0, -HALF),
				Vector3(HALF, 0, HALF),
				Vector3(-HALF, 0, -HALF),
				Vector3(HALF, 0, HALF),
				Vector3(-HALF, 0, HALF),
			]
		)
	)
	await get_tree().physics_frame
	var grid := _grid()
	assert_null(_field(grid, _sample(grid)), "a flat Y = 0 map looks exactly as before")


# --- keeps_fixed_band -----------------------------------------------------------------


func _flat_values(count: int, value: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(count)
	values.fill(value)
	return values


func _all_hit(count: int) -> PackedByteArray:
	var hit := PackedByteArray()
	hit.resize(count)
	hit.fill(1)
	return hit


func test_keeps_fixed_band_rules() -> void:
	var identity := Transform3D.IDENTITY
	var o := Vector2.ZERO
	var s := Vector2.ONE
	var none := PackedByteArray()
	none.resize(20)
	assert_true(
		GroundHeightField.keeps_fixed_band(_flat_values(20, 0.0), none, 5, o, s, identity),
		"nothing hit"
	)
	assert_true(
		GroundHeightField.keeps_fixed_band(_flat_values(20, 0.0), _all_hit(20), 5, o, s, identity),
		"a floor at Y = 0"
	)
	assert_false(
		GroundHeightField.keeps_fixed_band(_flat_values(20, -1.2), _all_hit(20), 5, o, s, identity),
		"ground 1.2 m down"
	)
	# A room: 17 of 20 samples floor, 3 on walls 3 m up (85 %).
	var room := _flat_values(20, 0.0)
	for i in [0, 1, 2]:
		room[i] = 3.0
	assert_true(GroundHeightField.keeps_fixed_band(room, _all_hit(20), 5, o, s, identity))
	# Half up, half down.
	var split := _flat_values(20, 0.0)
	for i in 10:
		split[i] = 1.5
	assert_false(GroundHeightField.keeps_fixed_band(split, _all_hit(20), 5, o, s, identity))
	# Misses do not count: 2 hits both at Y = 0.
	var sparse := _flat_values(20, -5.0)
	var hit := PackedByteArray()
	hit.resize(20)
	hit[3] = 1
	hit[7] = 1
	sparse[3] = 0.0
	sparse[7] = 0.0
	assert_true(GroundHeightField.keeps_fixed_band(sparse, hit, 5, o, s, identity))


func test_keeps_fixed_band_uses_the_world_height() -> void:
	var down := Transform3D(Basis.IDENTITY, Vector3(0, -1.2, 0))
	assert_false(
		GroundHeightField.keeps_fixed_band(
			_flat_values(4, 0.0), _all_hit(4), 2, Vector2.ZERO, Vector2.ONE, down
		),
		"a flat map lowered by the level offset is not at world Y = 0"
	)
	assert_true(
		GroundHeightField.keeps_fixed_band(
			_flat_values(4, 1.2), _all_hit(4), 2, Vector2.ZERO, Vector2.ONE, down
		)
	)


# --- grid_for_bounds -------------------------------------------------------------------


func test_grid_for_bounds_spacing_and_edges() -> void:
	var grid := GroundHeightField.grid_for_bounds(AABB(Vector3(-25, -1, -25), Vector3(50, 1, 50)))
	assert_eq(grid.columns, 201)
	assert_eq(grid.rows, 201)
	assert_eq(grid.origin, Vector2(-25, -25))
	assert_almost_eq(grid.step.x, 0.25, 1e-6)
	var odd := GroundHeightField.grid_for_bounds(AABB(Vector3(-10.07, 0, 2), Vector3(20.14, 0, 3)))
	assert_eq(odd.columns, 82)
	assert_almost_eq(odd.origin.x + (odd.columns - 1) * odd.step.x, 10.07, 1e-4, "far edge")
	assert_almost_eq(odd.origin.y + (odd.rows - 1) * odd.step.y, 5.0, 1e-4, "far edge")
	assert_lte(odd.step.x, GroundHeightField.SPACING_M)


func test_grid_for_bounds_widens_for_a_big_map() -> void:
	var grid := GroundHeightField.grid_for_bounds(AABB(Vector3(-100, 0, -60), Vector3(200, 0, 120)))
	var count: int = grid.columns * grid.rows
	assert_lte(count, int(GroundHeightField.MAX_SAMPLES * 1.02), "about the cap")
	assert_gt(count, int(GroundHeightField.MAX_SAMPLES * 0.9), "not far under it")
	assert_gt(grid.step.x, GroundHeightField.SPACING_M)


func test_grid_for_bounds_of_nothing_is_still_a_grid() -> void:
	var grid := GroundHeightField.grid_for_bounds(AABB())
	assert_eq(grid.columns, 2)
	assert_eq(grid.rows, 2)
	assert_gt(grid.step.x, 0.0)


# --- plumbing: GridOverlay and GameMap ------------------------------------------------------


func _overlay() -> GridOverlay:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	return GridOverlay.create(camera)


func _sampled_field(frame: Node3D) -> GroundHeightField:
	# 3 x 2 samples 2 m apart from (-2, -1): heights rise 1 m per column.
	var values := PackedFloat32Array([0.0, 1.0, 2.0, 0.0, 1.0, 2.0])
	return GroundHeightField.from_samples(frame, values, 3, 2, Vector2(-2, -1), Vector2(2, 2))


func test_overlay_reads_a_sampled_field() -> void:
	var overlay := _overlay()
	var frame := Node3D.new()
	frame.position = Vector3(0, -1.0, 0)
	add_child_autofree(frame)
	var field := _sampled_field(frame)
	overlay.set_ground(field)
	var mat := overlay.material_override as ShaderMaterial
	assert_true(overlay.follows_ground())
	assert_true(mat.get_shader_parameter("ground_heights_enabled"))
	assert_eq(mat.get_shader_parameter("ground_grid_origin"), Vector2(-2, -1))
	assert_eq(mat.get_shader_parameter("ground_grid_step"), Vector2(2, 2))
	assert_eq(mat.get_shader_parameter("ground_map_to_world"), frame.global_transform)
	var texture := mat.get_shader_parameter("ground_heights") as Texture2D
	assert_eq(Vector2i(texture.get_size()), Vector2i(3, 2))
	assert_almost_eq(
		field.world_height_at(Vector2(1.0, 0.0)), 0.5, EPSILON, "1.5 m in the map frame, 1 m down"
	)
	overlay.set_ground(null)
	assert_false(mat.get_shader_parameter("ground_heights_enabled"), "back to the fixed band")


func test_a_freed_map_turns_the_ground_off() -> void:
	var overlay := _overlay()
	var frame := Node3D.new()
	add_child(frame)
	overlay.set_ground(_sampled_field(frame))
	frame.free()
	assert_false(overlay.follows_ground())
	overlay._sync_ground()
	var mat := overlay.material_override as ShaderMaterial
	assert_false(mat.get_shader_parameter("ground_heights_enabled"))


func test_overlay_reads_authored_terrain_through_the_same_field() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "test", 5)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var field := GroundHeightField.from_terrain(terrain)
	assert_eq(field.origin, -doc.extent_m() * 0.5)
	assert_eq(field.step, doc.sample_step())
	assert_same(field.get_texture(), terrain.get_height_texture())
	var overlay := _overlay()
	overlay.set_ground(field)
	assert_true(overlay.follows_ground())
	assert_null(GroundHeightField.from_terrain(null))


func test_game_map_hands_the_ground_to_the_grid() -> void:
	var game_map: GameMap = autofree(GameMap.new())
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "test", 5)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	game_map.set_ground_terrain(terrain)
	assert_not_null(game_map.get_grid_ground(), "authored terrain's field")
	game_map.set_ground_terrain(null)
	assert_null(game_map.get_grid_ground(), "a Blender map starts on the fixed band")
	var field := _sampled_field(_map)
	game_map.set_grid_ground(field)
	assert_same(game_map.get_grid_ground(), field)


# --- MapSourceLoader.fit_grid_ground_async -----------------------------------------------


func _game_map() -> GameMap:
	var game_map: GameMap = autofree(GameMap.new())
	game_map.map_container = _container
	return game_map


func test_fit_samples_a_glb_maps_ground_for_the_grid() -> void:
	_add_ramp_with_hole()
	_add_visual()
	var game_map := _game_map()
	var loader := MapSourceLoader.new(get_tree())
	var fit: Dictionary = await loader.fit_grid_ground_async(_map, game_map)
	assert_true(fit.get("follows_ground", false))
	assert_eq(fit.samples, fit.columns * fit.rows)
	var field := game_map.get_grid_ground()
	assert_not_null(field)
	assert_almost_eq(field.world_height_at(Vector2(-2.9, 3.1)), _ramp_height(-2.9), 0.01)


func test_fit_leaves_a_map_without_collision_on_the_band() -> void:
	_add_visual()
	var game_map := _game_map()
	var loader := MapSourceLoader.new(get_tree())
	var fit: Dictionary = await loader.fit_grid_ground_async(_map, game_map)
	assert_false(fit.get("follows_ground", true))
	assert_null(game_map.get_grid_ground())


func test_fit_skips_authored_terrain_and_superseded_loads() -> void:
	var doc := MapDocument.create_flat(Vector2i(2, 2), "grass", "test", 5)
	_map.add_child(AuthoredTerrain.create(doc))
	var loader := MapSourceLoader.new(get_tree())
	assert_eq(await loader.fit_grid_ground_async(_map, _game_map()), {})
	var other := Node3D.new()
	_container.add_child(other)
	_add_ramp_with_hole()
	loader.is_superseded = func() -> bool: return true
	assert_eq(await loader.fit_grid_ground_async(other, _game_map()), {})
