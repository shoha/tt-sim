extends GutTest

## The warm-up samples (GraphicsWarmup.collect_samples and each owner's warmup_samples):
## well formed, and with the vertex layout of the real builder's surface, since a pipeline is
## keyed by it. The foliage layout guard is here too.


func _format_of(sample: Dictionary) -> int:
	return int(GraphicsWarmup.surface_data(sample)["format"])


func _assert_well_formed(samples: Array[Dictionary]) -> void:
	assert_false(samples.is_empty(), "at least one sample")
	for sample in samples:
		assert_true(GraphicsWarmup.valid_sample(sample), "well formed: %s" % sample.get("name"))
		assert_false((sample.arrays as Array).is_empty(), "%s has geometry" % sample.name)


func test_terrain_samples_match_the_real_ground_and_skirt() -> void:
	var samples := TerrainMeshBuilder.warmup_samples()
	_assert_well_formed(samples)
	assert_eq(samples.map(func(s): return s.name), ["terrain_chunk", "terrain_skirt"])
	var doc := TerrainMeshBuilder.warmup_document()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	# The document names no palette surface, so the real terrain warns and uses a plain ground.
	assert_engine_error(1, "one warning naming the missing surface")
	var chunk := terrain.get_chunk(TerrainMeshBuilder.chunk_cells(doc)[0])
	assert_not_null(chunk, "the real terrain has that chunk")
	assert_eq(_format_of(samples[0]), chunk.mesh.surface_get_format(0), "ground layout")
	assert_eq(
		_format_of(samples[1]), terrain.get_skirt().mesh.surface_get_format(0), "skirt layout"
	)
	assert_eq((samples[0].material as ShaderMaterial).shader, AuthoredTerrain.GROUND_SHADER)
	assert_eq((samples[1].material as ShaderMaterial).shader, AuthoredTerrain.SKIRT_SHADER)


func test_the_water_sample_matches_the_real_water_surface() -> void:
	var samples := AuthoredWater.warmup_samples()
	_assert_well_formed(samples)
	assert_eq(samples.size(), 1)
	assert_eq(samples[0].name, "water")
	var water := AuthoredWater.create(AuthoredWater.warmup_document())
	add_child_autofree(water)
	var instance := water.get_mesh_instance()
	assert_not_null(instance, "the warm-up document has water")
	assert_eq(_format_of(samples[0]), instance.mesh.surface_get_format(0), "water layout")
	assert_eq((samples[0].material as ShaderMaterial).shader, AuthoredWater.WATER_SHADER)
