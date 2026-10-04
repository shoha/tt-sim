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
	assert_eq(samples.size(), 2)
	assert_eq(samples[0].name, "water")
	var water := AuthoredWater.create(AuthoredWater.warmup_document())
	add_child_autofree(water)
	var instance := water.get_mesh_instance()
	assert_not_null(instance, "the warm-up document has water")
	assert_eq(_format_of(samples[0]), instance.mesh.surface_get_format(0), "water layout")
	assert_eq((samples[0].material as ShaderMaterial).shader, AuthoredWater.WATER_SHADER)


## The falls sample (P4c-4) draws the real falls mesh's layout on the waterfall shader, from
## a warm-up document whose river falls over a tier.
func test_the_falls_sample_matches_the_real_falls_mesh() -> void:
	var samples := AuthoredWater.warmup_samples()
	assert_eq(samples[1].name, "falls")
	var doc := AuthoredWater.warmup_falls_document()
	var falls := WaterFalls.falls(doc)
	assert_eq(falls.size(), 1, "one fall at the tier's brink")
	assert_gt(float(falls[0].top) - float(falls[0].bottom), WaterFalls.FALL_MIN_DROP_M)
	var water := AuthoredWater.create(doc)
	add_child_autofree(water)
	var instance := water.get_falls_instance()
	assert_not_null(instance, "the warm-up falls document has a curtain")
	assert_eq(_format_of(samples[1]), instance.mesh.surface_get_format(0), "falls layout")
	assert_eq((samples[1].material as ShaderMaterial).shader, AuthoredWater.FALLS_SHADER)
	assert_eq(AuthoredWater.fall_material().shader, AuthoredWater.FALLS_SHADER)


func _triangle(with_colors: bool) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	if with_colors:
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func test_the_representatives_are_wind_assets() -> void:
	var asset_ids := WindFoliage.representative_assets()
	assert_eq(asset_ids.size(), 2, "a first wind asset and a flower")
	for asset_id in asset_ids:
		var category := String(PaletteLibrary.asset(asset_id).get("wind_category", ""))
		assert_true(WindFoliage.PRESETS.has(category), "%s is wind foliage" % asset_id)
	assert_true(asset_ids[1].get_file().begins_with("Flower_"), "the second is a flower")


func test_pick_representatives_takes_one_flower_unless_the_first_is_one() -> void:
	var flower_first: Array[String] = ["a/Flower_A", "b/Flower_B", "c/Tree_C"]
	assert_eq(WindFoliage.pick_representatives(flower_first), ["a/Flower_A"] as Array[String])
	var no_flower: Array[String] = ["a/Tree_A", "b/Grass_B"]
	assert_eq(WindFoliage.pick_representatives(no_flower), ["a/Tree_A"] as Array[String])
	var normal: Array[String] = ["a/Tree_A", "b/Grass_B", "c/Flower_C", "d/Flower_D"]
	assert_eq(WindFoliage.pick_representatives(normal), ["a/Tree_A", "c/Flower_C"] as Array[String])
	var none: Array[String] = []
	assert_eq(WindFoliage.pick_representatives(none), [] as Array[String])


func test_foliage_samples_cover_both_wind_shaders_with_the_real_layouts() -> void:
	var samples := WindFoliage.warmup_samples()
	_assert_well_formed(samples)
	var meshes: Array[ArrayMesh] = []
	var layouts := {}
	for asset_id in WindFoliage.representative_assets():
		var template := PaletteLibrary.resolve(asset_id)
		var mesh := template.mesh as ArrayMesh
		WindFoliage.apply_material(mesh, template.wind_category)
		meshes.append(mesh)
		for i in mesh.get_surface_count():
			if mesh.surface_get_material(i) is ShaderMaterial:
				layouts[mesh.surface_get_format(i)] = {}
	assert_gt(layouts.size(), 1, "the representatives bring more than one layout")
	var shaders := {}
	for sample in samples:
		assert_true(sample.multimesh, "foliage draws as a MultiMesh")
		var representative := int(String(sample.name).get_slice("_", 0).trim_prefix("foliage"))
		var surface := int(String(sample.name).get_slice("_", 1))
		var format := meshes[representative].surface_get_format(surface)
		assert_eq(_format_of(sample), format, "%s layout" % sample.name)
		var shader := (sample.material as ShaderMaterial).shader
		shaders[shader] = true
		layouts[format][shader] = true
	assert_true(shaders.has(WindFoliage.get_shader()), "the AA shader")
	assert_true(shaders.has(WindFoliage.get_shader_no_aa()), "the no-AA shader")
	for format in layouts:
		assert_eq(layouts[format].size(), 2, "layout %d is warmed on both shaders" % format)


func test_unwarmed_formats_names_only_new_layouts() -> void:
	var plain := _triangle(false)
	var colored := _triangle(true)
	var warmed: Array[int] = [plain.surface_get_format(0)]
	assert_eq(WindFoliage.unwarmed_formats(plain, warmed), [] as Array[int])
	assert_eq(WindFoliage.unwarmed_formats(colored, warmed), [colored.surface_get_format(0)])


func test_every_wind_asset_has_a_layout_the_representatives_warm() -> void:
	var warmed: Array[int] = []
	for asset_id in WindFoliage.representative_assets():
		var rep := PaletteLibrary.resolve(asset_id).mesh as ArrayMesh
		warmed.append_array(WindFoliage.unwarmed_formats(rep, warmed))
	var seen := {}
	for biome in PaletteLibrary.biomes():
		for rule in PaletteLibrary.species(String(biome.id)):
			for asset_id in rule.get("assets", []):
				if seen.has(asset_id):
					continue
				seen[asset_id] = true
				var entry := PaletteLibrary.asset(String(asset_id))
				if not WindFoliage.PRESETS.has(String(entry.get("wind_category", ""))):
					continue
				var mesh := PaletteLibrary.resolve(String(asset_id)).mesh as ArrayMesh
				if mesh == null:
					continue
				assert_eq(
					WindFoliage.unwarmed_formats(mesh, warmed),
					[] as Array[int],
					"%s draws with a layout the warm-up does not" % asset_id
				)


func test_collect_samples_has_every_owner_once() -> void:
	var samples := GraphicsWarmup.collect_samples()
	_assert_well_formed(samples)
	var names := {}
	var shaders := {}
	for sample in samples:
		assert_false(names.has(sample.name), "unique name %s" % sample.name)
		names[sample.name] = true
		shaders[(sample.material as ShaderMaterial).shader.resource_path] = true
	for path in [
		"res://shaders/authored_ground.gdshader",
		"res://shaders/authored_ground_skirt.gdshader",
		"res://shaders/water.gdshader",
		"res://shaders/waterfall.gdshader",
		"res://shaders/wind_foliage.gdshader",
		"res://shaders/wind_foliage_no_aa.gdshader",
	]:
		assert_true(shaders.has(path), "a sample draws %s" % path)
