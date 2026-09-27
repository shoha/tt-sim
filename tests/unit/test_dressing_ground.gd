extends GutTest

## DressingGround (utils/dressing_ground.gd): a dressed GLB's ground sampled into the
## document's heights by downward rays on the terrain layer, misses filled from the nearest
## hit, and rows generated on the old flat heights settled onto the sampled ground. The
## collision is built here: a planar ramp (y = RAMP_SLOPE * x + RAMP_BASE over 8 x 8 m), a
## step (a box covering only x < 0), and a body on another layer that must be ignored.

const BIOME := "temperate_forest_summer_s1"
const OAK := BIOME + "/Tree_Oak_summer_01"
const GRASS := BIOME + "/Grass_Short_summer_19"
const RAMP_SLOPE := 0.25
const RAMP_BASE := 1.0
const TOP := 50.0
const BIG_BUDGET := 1_000_000_000

var _map: Node3D = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)


func _ramp_height(x: float) -> float:
	return RAMP_SLOPE * x + RAMP_BASE


func _add_body(shape: Shape3D, position: Vector3, layer: int = 1) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	body.position = position
	add_child_autofree(body)


func _add_ramp() -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	var a := Vector3(-4, _ramp_height(-4), -4)
	var b := Vector3(4, _ramp_height(4), -4)
	var c := Vector3(4, _ramp_height(4), 4)
	var d := Vector3(-4, _ramp_height(-4), 4)
	shape.set_faces(PackedVector3Array([a, b, c, a, c, d]))
	_add_body(shape, Vector3.ZERO)


func _add_box(size: Vector3, position: Vector3, layer: int = 1) -> void:
	var box := BoxShape3D.new()
	box.size = size
	_add_body(box, position, layer)


## A 2 x 2 cell dressing document (13 x 13 samples, about 3 m square) over the ramp.
func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(2, 2), "", "", 7)
	doc.has_base_map = true
	return doc


func _sample(doc: MapDocument, xf: Transform3D = Transform3D.IDENTITY) -> DressingGround:
	var sampler := DressingGround.begin(doc, _map.get_world_3d(), xf, TOP)
	var guard := 0
	while not sampler.step(1) and guard < 10000:
		guard += 1
	return sampler


func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


# --- sampling -----------------------------------------------------------------------


func test_samples_follow_a_ramp() -> void:
	_add_ramp()
	await get_tree().physics_frame
	var doc := _doc()
	var sampler := _sample(doc)
	assert_eq(sampler.miss_count(), 0, "every sample is over the ramp")
	assert_eq(sampler.heights.size(), doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			assert_almost_eq(sampler.heights[doc.sample_index(x, z)], _ramp_height(p.x), 0.001)


func test_samples_are_in_the_map_roots_frame() -> void:
	# A level's map scale and offset: the document is in the scaled root's frame.
	_add_ramp()
	await get_tree().physics_frame
	var doc := _doc()
	var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(2, 2, 2)), Vector3(0, 0.5, 0))
	var sampler := _sample(doc, xf)
	assert_eq(sampler.miss_count(), 0)
	var i := doc.sample_index(doc.samples_x() - 1, 3)
	var local := doc.sample_to_world(Vector2(doc.samples_x() - 1, 3))
	var expected := (_ramp_height(local.x * 2.0) - 0.5) / 2.0
	assert_almost_eq(sampler.heights[i], expected, 0.001)


func test_misses_take_the_nearest_hit_and_other_layers_are_ignored() -> void:
	# A step: ground only for x < 0 (top at 1.5); a taller body over x > 0 on layer 2.
	_add_box(Vector3(4, 1, 8), Vector3(-2, 1, 0))
	_add_box(Vector3(4, 10, 8), Vector3(2.2, 0, 0), 2)
	await get_tree().physics_frame
	var doc := _doc()
	var sampler := _sample(doc)
	assert_gt(sampler.miss_count(), 0, "the x > 0 half has no terrain")
	assert_lt(sampler.miss_count(), doc.sample_count())
	for h in sampler.heights:
		assert_almost_eq(h, 1.5, 0.001, "a miss takes the nearest hit's height")


func test_no_hits_leaves_zero() -> void:
	await get_tree().physics_frame
	var doc := _doc()
	var sampler := _sample(doc)
	assert_eq(sampler.miss_count(), doc.sample_count())
	for h in sampler.heights:
		assert_eq(h, 0.0)


func test_fill_misses_takes_the_nearest_sample() -> void:
	var values := PackedFloat32Array([5, 9, 9, 9, 7])
	var hits := PackedByteArray([1, 0, 0, 0, 1])
	var filled := DressingGround.fill_misses(values, hits, 5, 1)
	assert_eq(Array(filled), [5.0, 5.0, 5.0, 7.0, 7.0])
	assert_eq(Array(values), [5.0, 9.0, 9.0, 9.0, 7.0], "the input is not modified")


func test_sampling_runs_in_slices() -> void:
	_add_ramp()
	await get_tree().physics_frame
	var sampler := DressingGround.begin(_doc(), _map.get_world_3d(), Transform3D.IDENTITY, TOP)
	var steps := 1
	while not sampler.step(0):
		steps += 1
	assert_eq(steps, 13, "a zero budget casts one row of samples per step")


# --- rows on the ground ---------------------------------------------------------------


func test_generated_rows_stand_on_the_sampled_ground() -> void:
	_add_ramp()
	await get_tree().physics_frame
	var doc := _doc()
	doc.heights = _sample(doc).heights
	doc.biome_ids = PackedStringArray([BIOME])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(1)
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(255)
	doc.biome_slots = slots
	doc.biome_density = density
	var cells := ScatterGenerator.cells_in_bounds(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var rows_by_asset := ScatterGenerator.generate_for_document(doc, BIOME, cells)
	var count := 0
	for asset_id in rows_by_asset:
		var rows: PackedFloat32Array = rows_by_asset[asset_id]
		for b in range(0, rows.size(), MapDocument.ROW_STRIDE):
			assert_almost_eq(rows[b + 1], _ramp_height(rows[b]), 0.002)
			count += 1
	assert_gt(count, 0, "the painted biome generates rows")


func test_a_flat_legacy_document_is_settled_onto_the_ground() -> void:
	_add_ramp()
	await get_tree().physics_frame
	var doc := _doc()
	var scatter := AuthoredScatter.create()
	scatter.budget = BIG_BUDGET
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	var points := [Vector2(-1.2, 0.3), Vector2(0.4, -0.9), Vector2(1.1, 1.3)]
	scatter.build_all({OAK: _rows(points), GRASS: _rows(points)})
	var sampled := _sample(doc).heights
	var moved := DressingGround.settle(doc, sampled, scatter, {GRASS: true})
	assert_eq(moved, 6, "every row stood at Y = 0 above or below the ramp")
	assert_eq(doc.heights, sampled, "the document takes the sampled ground")
	var ramp_normal := Vector3(-RAMP_SLOPE, 1.0, 0.0).normalized()
	var rows := scatter.rows_by_asset()
	for asset_id in [OAK, GRASS]:
		var flat: PackedFloat32Array = rows[asset_id]
		assert_eq(flat.size(), points.size() * MapDocument.ROW_STRIDE)
		for b in range(0, flat.size(), MapDocument.ROW_STRIDE):
			assert_almost_eq(flat[b + 1], _ramp_height(flat[b]), 0.001, "on the ground")
			var q := Quaternion(flat[b + 3], flat[b + 4], flat[b + 5], flat[b + 6])
			var up := q * Vector3.UP
			if asset_id == GRASS:
				assert_almost_eq(up.angle_to(ramp_normal), 0.0, 0.001, "aligned follows slope")
			else:
				assert_almost_eq(up.angle_to(Vector3.UP), 0.0, 0.0001, "upright stays upright")
	assert_eq(
		DressingGround.settle(doc, sampled, scatter, {GRASS: true}),
		0,
		"a document already on its ground has nothing to settle (no dirty reopen)"
	)


func test_snap_rows_keeps_unmoved_arrays() -> void:
	var doc := _doc()
	var fields := ScatterGenerator.document_fields(doc, "")
	var rows := {OAK: _rows([Vector2(0.2, 0.2)])}
	var snapped := DressingGround.snap_rows(rows, fields, fields, {})
	assert_eq(snapped.moved, 0)
	assert_eq(snapped.rows[OAK], rows[OAK])
