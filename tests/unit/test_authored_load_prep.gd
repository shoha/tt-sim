extends GutTest

## AuthoredLoadPrep (P4b-0): the pure data an authored map's load computes on worker threads
## (wet dressing, water geometry, rule fields, chunk and skirt arrays) equals what the
## synchronous build computes, and the terrain and water built from it equal the ones built
## without it.

const RIVER_LEVEL := -0.2
const BED := -1.0


## A flat 20 x 20 cell map with a channel carved to BED along X holding a waist-deep river, a
## bump for some relief, and a painted biome corner.
func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 7)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			var i := doc.sample_index(x, z)
			if absf(p.x) <= 10.0 and absf(p.y) <= 1.5:
				heights[i] = BED
			heights[i] += 0.8 * exp(-(p - Vector2(6, 8)).length_squared() / 8.0)
	doc.heights = heights
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5, 1.5])
	doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, RIVER_LEVEL))
	return doc


func test_workers_compute_what_the_calling_thread_does() -> void:
	var doc := _doc()
	var threaded := AuthoredLoadPrep.start(doc).finish()
	var direct := AuthoredLoadPrep.compute(doc)
	for part in [
		AuthoredLoadPrep.DRESSING,
		AuthoredLoadPrep.WATER,
		AuthoredLoadPrep.FIELDS,
		AuthoredLoadPrep.CHUNKS,
		AuthoredLoadPrep.SKIRT
	]:
		assert_true(threaded.has(part), "worker part %s" % part)
		assert_eq(str(threaded.get(part)).hash(), str(direct.get(part)).hash(), "same %s" % part)
	assert_eq(threaded[AuthoredLoadPrep.DRESSING], WaterDressing.field_of(doc))
	assert_false((threaded[AuthoredLoadPrep.DRESSING] as PackedByteArray).is_empty(), "wet")
	assert_true(doc.water_dressing.is_empty(), "the workers leave the document alone")
	assert_eq(
		(threaded[AuthoredLoadPrep.CHUNKS] as Dictionary).size(),
		TerrainMeshBuilder.chunk_cells(doc).size(),
		"every chunk"
	)


func test_no_water_part_without_water() -> void:
	var doc := MapDocument.create_flat(Vector2i(8, 8), "grass", "test", 1)
	var prepared := AuthoredLoadPrep.start(doc).finish()
	assert_false(prepared.has(AuthoredLoadPrep.WATER))
	assert_true((prepared[AuthoredLoadPrep.DRESSING] as PackedByteArray).is_empty())
	assert_eq(AuthoredLoadPrep.start(doc).finish().size(), prepared.size(), "repeatable")


func test_terrain_and_water_from_prep_match_the_synchronous_build() -> void:
	var doc := _doc()
	var plain := AuthoredTerrain.create(doc)
	var plain_dressing := doc.water_dressing.duplicate()
	var prepared := AuthoredLoadPrep.start(doc).finish()
	doc.water_dressing = PackedByteArray()
	var from_prep := AuthoredTerrain.create(doc, PaletteLibrary.DEFAULT_ROOT, true, prepared)
	assert_eq(doc.water_dressing, plain_dressing, "the dressing lands in the document")
	assert_eq(from_prep.ground_layers(), plain.ground_layers(), "same layer plan")
	var chunks := 0
	for child in plain.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null:
			continue
		var twin := from_prep.get_node_or_null(NodePath(mesh_node.name)) as MeshInstance3D
		assert_not_null(twin, "the prepared terrain has %s" % mesh_node.name)
		if twin == null:
			continue
		var a: Array = mesh_node.mesh.surface_get_arrays(0)
		var b: Array = twin.mesh.surface_get_arrays(0)
		assert_eq(a[Mesh.ARRAY_VERTEX], b[Mesh.ARRAY_VERTEX], "vertices of %s" % mesh_node.name)
		assert_eq(
			a[Mesh.ARRAY_TEX_UV2], b[Mesh.ARRAY_TEX_UV2], "rule fields of %s" % mesh_node.name
		)
		chunks += 1
	assert_gt(chunks, 1, "chunks and skirt compared")
	var water := AuthoredWater.create(doc)
	var water_prep := AuthoredWater.create(doc, prepared[AuthoredLoadPrep.WATER])
	assert_eq(water_prep.levels, water.levels, "same levels")
	assert_eq(water_prep.get_child_count(), water.get_child_count(), "same nodes")
	var surface_a := water.get_mesh_instance().mesh.surface_get_arrays(0)
	var surface_b := water_prep.get_mesh_instance().mesh.surface_get_arrays(0)
	assert_eq(surface_a[Mesh.ARRAY_VERTEX], surface_b[Mesh.ARRAY_VERTEX], "same surface")
	for node in [plain, from_prep, water, water_prep]:
		node.free()


func test_a_height_edit_drops_unused_prepared_chunks() -> void:
	var doc := _doc()
	var prepared := AuthoredLoadPrep.start(doc).finish()
	var terrain := AuthoredTerrain.create(doc, PaletteLibrary.DEFAULT_ROOT, false, prepared)
	var heights := doc.heights.duplicate()
	heights[doc.sample_index(40, 40)] += 2.0
	doc.heights = heights
	terrain.queue_heights(Rect2i(40, 40, 1, 1))
	var cell: Vector2i = TerrainMeshBuilder.chunk_cells(doc)[0]
	for candidate in TerrainMeshBuilder.chunk_cells(doc):
		if TerrainMeshBuilder.chunk_sample_rect(doc, candidate).has_point(Vector2i(40, 40)):
			cell = candidate
	terrain.rebuild_chunks([cell] as Array[Vector2i])
	var fresh := TerrainMeshBuilder.build_chunk_arrays(doc, cell, terrain.get("_fields"))
	var chunk_name := AuthoredTerrain.CHUNK_NAME_PREFIX + ScatterChunker.cell_suffix(cell)
	var chunk := terrain.get_node(NodePath(chunk_name)) as MeshInstance3D
	assert_eq(
		chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],
		fresh[Mesh.ARRAY_VERTEX],
		"built from the edited heights, not the stale worker arrays"
	)
	terrain.free()
