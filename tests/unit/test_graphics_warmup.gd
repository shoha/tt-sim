extends GutTest

## GraphicsWarmup (utils/graphics_warmup.gd): the cache key, the skip rules, the marker and
## the shader lists. Samples are in test_graphics_warmup_samples.gd, the screen in
## test_graphics_warmup_screen.gd.

const MARKER := "user://test_graphics_warmup_marker.cfg"

const BASE_INPUTS := {
	"engine": "4.7.2-stable (official)",
	"method": "mobile",
	"adapter": "Apple M3",
	"vendor": "Apple",
	"api": "1.2",
	"driver": "",
	"shaders": "res://a.gdshader\ncode",
}


func after_each() -> void:
	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER))


func _run_inputs(overrides: Dictionary = {}) -> Dictionary:
	var inputs := {
		"display": "macos",
		"editor": false,
		"method": "mobile",
		"forced": false,
		"marker_key": "",
		"key": "k1",
	}
	inputs.merge(overrides, true)
	return inputs


func test_the_cache_key_is_stable_and_every_input_changes_it() -> void:
	var key := GraphicsWarmup.cache_key_for(BASE_INPUTS)
	assert_eq(key, GraphicsWarmup.cache_key_for(BASE_INPUTS.duplicate()), "stable")
	assert_eq(key.length(), 64, "a sha256 hex digest")
	for name in BASE_INPUTS:
		var changed := BASE_INPUTS.duplicate()
		changed[name] = str(changed[name]) + "x"
		assert_ne(GraphicsWarmup.cache_key_for(changed), key, "%s is in the key" % name)


func test_the_key_does_not_depend_on_input_order() -> void:
	var reordered := {}
	var names := BASE_INPUTS.keys()
	names.reverse()
	for name in names:
		reordered[name] = BASE_INPUTS[name]
	assert_eq(GraphicsWarmup.cache_key_for(reordered), GraphicsWarmup.cache_key_for(BASE_INPUTS))


func _reader(files: Dictionary) -> Callable:
	return func(path: String) -> String: return files[path]


func test_includes_are_followed_once_and_sorted() -> void:
	var files := {
		"res://b.gdshader": '#include "res://common.gdshaderinc"\nvoid b() {}',
		"res://a.gdshader": '#include "res://common.gdshaderinc"\nvoid a() {}',
		"res://common.gdshaderinc": '#include "res://leaf.gdshaderinc"\n',
		"res://leaf.gdshaderinc": "float leaf;",
	}
	var sources := GraphicsWarmup.shader_sources_for(
		["res://b.gdshader", "res://a.gdshader"], _reader(files)
	)
	assert_eq(sources.size(), 4, "each file once")
	var sorted := sources.duplicate()
	sorted.sort()
	assert_eq(sources, sorted, "sorted, so the key does not depend on list order")
	assert_true(sources[2].begins_with("res://common.gdshaderinc\n"), "path then code")


func test_an_include_only_edit_changes_the_key() -> void:
	var files := {
		"res://a.gdshader": '#include "res://inc.gdshaderinc"\nvoid a() {}',
		"res://inc.gdshaderinc": "float x = 1.0;",
	}
	var before := GraphicsWarmup.shader_sources_for(["res://a.gdshader"], _reader(files))
	files["res://inc.gdshaderinc"] = "float x = 2.0;"
	var after := GraphicsWarmup.shader_sources_for(["res://a.gdshader"], _reader(files))
	var inputs_before := BASE_INPUTS.duplicate()
	inputs_before["shaders"] = "\n".join(before)
	var inputs_after := BASE_INPUTS.duplicate()
	inputs_after["shaders"] = "\n".join(after)
	assert_ne(
		GraphicsWarmup.cache_key_for(inputs_before),
		GraphicsWarmup.cache_key_for(inputs_after),
		"an include edit re-warms"
	)


func test_the_real_shader_sources_include_the_includes() -> void:
	var joined := "\n".join(GraphicsWarmup.shader_sources())
	assert_string_contains(joined, "res://shaders/wind_foliage_include.gdshaderinc\n")
	assert_string_contains(joined, "res://shaders/occlusion_fade_include.gdshaderinc\n")
	assert_string_contains(joined, "res://shaders/authored_ground.gdshaderinc\n")


func test_the_skip_rules() -> void:
	assert_true(GraphicsWarmup.should_run_for(_run_inputs()), "no marker: run")
	assert_true(GraphicsWarmup.should_run_for(_run_inputs({"marker_key": "old"})), "stale")
	assert_false(GraphicsWarmup.should_run_for(_run_inputs({"marker_key": "k1"})), "current")
	for skip in [{"display": "headless"}, {"editor": true}, {"method": "gl_compatibility"}]:
		assert_false(GraphicsWarmup.should_run_for(_run_inputs(skip)), "skips on %s" % [skip])
		var forced: Dictionary = skip.duplicate()
		forced["forced"] = true
		forced["marker_key"] = "k1"
		assert_true(GraphicsWarmup.should_run_for(_run_inputs(forced)), "forced %s" % [skip])


func _marked_inputs() -> Dictionary:
	return _run_inputs({"marker_key": GraphicsWarmup.read_marker(MARKER)})


func test_the_marker_round_trip() -> void:
	assert_eq(GraphicsWarmup.read_marker(MARKER), "", "missing reads as no marker")
	assert_true(GraphicsWarmup.should_run_for(_marked_inputs()), "missing: run")
	assert_true(GraphicsWarmup.write_marker("old", MARKER))
	assert_true(GraphicsWarmup.should_run_for(_marked_inputs()), "stale: run")
	assert_true(GraphicsWarmup.write_marker("k1", MARKER))
	assert_eq(GraphicsWarmup.read_marker(MARKER), "k1")
	assert_false(GraphicsWarmup.should_run_for(_marked_inputs()), "current: skip")


func test_a_corrupt_marker_reads_as_missing() -> void:
	var file := FileAccess.open(MARKER, FileAccess.WRITE)
	file.store_string("[warmup\nkey = = =\u0001")
	file.close()
	assert_eq(GraphicsWarmup.read_marker(MARKER), "", "a parse failure means warm again")
	assert_engine_error(1, "ConfigFile reports the parse error")


func test_an_unwritable_marker_path_warns_and_returns_false() -> void:
	assert_false(GraphicsWarmup.write_marker("k1", "user://no_such_dir/deeper/marker.cfg"))
	assert_engine_error(1, "our push_warning")


func test_every_project_shader_is_covered_or_excluded() -> void:
	var on_disk: Array[String] = []
	for file in DirAccess.get_files_at("res://shaders/"):
		if file.ends_with(".gdshader"):
			on_disk.append("res://shaders/" + file)
	for path in on_disk:
		var covered := GraphicsWarmup.COVERED_SHADERS.has(path)
		var excluded := GraphicsWarmup.EXCLUDED_SHADERS.has(path)
		assert_true(covered != excluded, "%s is in exactly one list" % path)
	for path in GraphicsWarmup.COVERED_SHADERS:
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
	for path in GraphicsWarmup.EXCLUDED_SHADERS:
		assert_true(ResourceLoader.exists(path), "%s exists" % path)
		assert_false(
			String(GraphicsWarmup.EXCLUDED_SHADERS[path]).is_empty(), "%s has a reason" % path
		)


func test_only_texture_blit_shaders_compile_on_the_worker() -> void:
	assert_true(GraphicsWarmup.compiles_on_worker(load("res://shaders/texel_copy_blit.gdshader")))
	assert_false(GraphicsWarmup.compiles_on_worker(load("res://shaders/water.gdshader")))
	assert_false(GraphicsWarmup.compiles_on_worker(load("res://shaders/lofi_canvas.gdshader")))


func test_format_flags_keep_only_the_flag_bits() -> void:
	var format := (
		Mesh.ARRAY_FORMAT_VERTEX
		| Mesh.ARRAY_FORMAT_NORMAL
		| Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		| RenderingServer.ARRAY_FLAG_FORMAT_VERSION_2
	)
	assert_eq(GraphicsWarmup.format_flags(format), Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)


func test_valid_sample_checks_the_shape() -> void:
	var sample := {
		"name": "tri",
		"primitive": Mesh.PRIMITIVE_TRIANGLES,
		"arrays": [],
		"material": ShaderMaterial.new(),
		"multimesh": false,
	}
	assert_true(GraphicsWarmup.valid_sample(sample))
	for missing in sample:
		var broken := sample.duplicate()
		broken.erase(missing)
		assert_false(GraphicsWarmup.valid_sample(broken), "needs %s" % missing)
	var bad_flags := sample.duplicate()
	bad_flags["flags"] = "x"
	assert_false(GraphicsWarmup.valid_sample(bad_flags), "flags is an int")


func test_surface_data_matches_an_array_mesh_surface() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var sample := {
		"name": "tri",
		"primitive": Mesh.PRIMITIVE_TRIANGLES,
		"arrays": arrays,
		"material": ShaderMaterial.new(),
		"multimesh": false,
	}
	var mesh := GraphicsWarmup.sample_mesh(sample)
	var data := GraphicsWarmup.surface_data(sample)
	assert_eq(int(data["format"]), mesh.surface_get_format(0), "same vertex layout")
	assert_eq(data["material"], (sample.material as Material).get_rid(), "material attached")
	assert_eq(mesh.surface_get_material(0), sample.material)
	var rid := RenderingServer.mesh_create_from_surfaces([data])
	assert_true(rid.is_valid())
	RenderingServer.free_rid(rid)
