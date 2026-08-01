extends GutTest

## Unit tests for GlbUtils' scene-level glTF "extras" lighting extraction -- the
## mechanism that carries a Blender-authored World Background ambient light setting
## (see terrain-paint's engine/world_lighting.py) into tt-sim's environment config
## without a second sidecar file alongside the map's .glb.

const _TEST_GLB_PATH := "user://test_lighting_extras.glb"


func _build_minimal_glb(scene_extras: Variant) -> PackedByteArray:
	var gltf_json := {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [{"nodes": [0], "extras": scene_extras}],
		"nodes": [{"name": "Empty"}],
	}
	var json_bytes := JSON.stringify(gltf_json).to_utf8_buffer()
	while json_bytes.size() % 4 != 0:
		json_bytes.append(0x20)  # space-pad JSON chunk per glTF spec

	var json_chunk_header := PackedByteArray()
	json_chunk_header.resize(8)
	json_chunk_header.encode_u32(0, json_bytes.size())
	json_chunk_header.encode_u32(4, 0x4E4F534A)  # "JSON"

	# Godot's GLB parser unconditionally tries to read a second chunk header after the
	# JSON chunk -- with no BIN chunk at all it reads past EOF and emits a "Reading
	# less data than requested" warning (harmless to the parse result, but GUT treats
	# any warning as a test failure). An explicit, zero-length BIN chunk avoids this.
	var bin_bytes := PackedByteArray()
	var bin_chunk_header := PackedByteArray()
	bin_chunk_header.resize(8)
	bin_chunk_header.encode_u32(0, bin_bytes.size())
	bin_chunk_header.encode_u32(4, 0x004E4942)  # "BIN\0"

	var body := json_chunk_header + json_bytes + bin_chunk_header + bin_bytes
	var header := PackedByteArray()
	header.resize(12)
	header.encode_u32(0, 0x46546C67)  # "glTF"
	header.encode_u32(4, 2)
	header.encode_u32(8, 12 + body.size())

	return header + body


func before_each() -> void:
	if FileAccess.file_exists(_TEST_GLB_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_GLB_PATH))


func after_each() -> void:
	if FileAccess.file_exists(_TEST_GLB_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_TEST_GLB_PATH))


func test_load_glb_attaches_scene_extras_as_meta() -> void:
	var bytes := _build_minimal_glb(
		{"tt_ambient_light_color": [0.1, 0.2, 0.3], "tt_ambient_light_energy": 1.5}
	)
	var file := FileAccess.open(_TEST_GLB_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var scene := GlbUtils.load_glb(_TEST_GLB_PATH)

	assert_not_null(scene)
	assert_true(scene.has_meta("tt_gltf_scene_extras"))
	var extras: Dictionary = scene.get_meta("tt_gltf_scene_extras")
	assert_eq(extras.get("tt_ambient_light_energy"), 1.5)

	scene.free()


func test_load_glb_with_no_extras_has_empty_meta() -> void:
	var bytes := _build_minimal_glb({})
	var file := FileAccess.open(_TEST_GLB_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var scene := GlbUtils.load_glb(_TEST_GLB_PATH)

	assert_not_null(scene)
	var extras: Dictionary = scene.get_meta("tt_gltf_scene_extras", {})
	assert_true(extras.is_empty())

	scene.free()


func test_load_glb_with_no_extras_does_not_set_meta() -> void:
	var bytes := _build_minimal_glb({})
	var file := FileAccess.open(_TEST_GLB_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var scene := GlbUtils.load_glb(_TEST_GLB_PATH)

	assert_not_null(scene)
	assert_false(scene.has_meta("tt_gltf_scene_extras"))

	scene.free()


func test_extract_lighting_config_maps_known_keys() -> void:
	var root := Node3D.new()
	root.set_meta(
		"tt_gltf_scene_extras",
		{"tt_ambient_light_color": [0.1, 0.2, 0.3], "tt_ambient_light_energy": 1.5}
	)

	var config := GlbUtils.extract_lighting_config(root)

	assert_eq(config.get("ambient_light_color"), Color(0.1, 0.2, 0.3))
	assert_eq(config.get("ambient_light_energy"), 1.5)

	root.free()


func test_extract_lighting_config_returns_empty_dict_with_no_extras() -> void:
	var root := Node3D.new()

	var config := GlbUtils.extract_lighting_config(root)

	assert_true(config.is_empty())

	root.free()


func test_extract_scene_extras_ignores_non_dictionary_extras() -> void:
	# Per the glTF 2.0 spec, "extras" may be any JSON value, not necessarily an
	# object -- an Array is spec-legal but malformed for our purposes.
	var bytes := _build_minimal_glb(["not", "a", "dictionary"])
	var file := FileAccess.open(_TEST_GLB_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var scene := GlbUtils.load_glb(_TEST_GLB_PATH)

	assert_not_null(scene)
	assert_false(scene.has_meta("tt_gltf_scene_extras"))

	scene.free()


func test_extract_lighting_config_ignores_non_array_color() -> void:
	var root := Node3D.new()
	root.set_meta("tt_gltf_scene_extras", {"tt_ambient_light_color": "not an array"})

	var config := GlbUtils.extract_lighting_config(root)

	assert_false(config.has("ambient_light_color"))

	root.free()


func test_extract_lighting_config_ignores_too_short_color_array() -> void:
	var root := Node3D.new()
	root.set_meta("tt_gltf_scene_extras", {"tt_ambient_light_color": [0.1, 0.2]})

	var config := GlbUtils.extract_lighting_config(root)

	assert_false(config.has("ambient_light_color"))

	root.free()


func test_extract_lighting_config_ignores_non_numeric_energy_string() -> void:
	var root := Node3D.new()
	root.set_meta("tt_gltf_scene_extras", {"tt_ambient_light_energy": "bright"})

	var config := GlbUtils.extract_lighting_config(root)

	assert_false(config.has("ambient_light_energy"))

	root.free()


func test_extract_lighting_config_ignores_non_numeric_energy_dictionary() -> void:
	var root := Node3D.new()
	root.set_meta("tt_gltf_scene_extras", {"tt_ambient_light_energy": {"nested": 1.0}})

	var config := GlbUtils.extract_lighting_config(root)

	assert_false(config.has("ambient_light_energy"))

	root.free()


func test_load_glb_async_attaches_scene_extras_as_meta() -> void:
	var bytes := _build_minimal_glb(
		{"tt_ambient_light_color": [0.1, 0.2, 0.3], "tt_ambient_light_energy": 1.5}
	)
	var file := FileAccess.open(_TEST_GLB_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var result := await GlbUtils.load_glb_async(_TEST_GLB_PATH)

	assert_true(result.success)
	assert_not_null(result.scene)
	assert_true(result.scene.has_meta("tt_gltf_scene_extras"))
	var extras: Dictionary = result.scene.get_meta("tt_gltf_scene_extras")
	assert_eq(extras.get("tt_ambient_light_energy"), 1.5)

	result.scene.free()
