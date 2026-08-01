extends GutTest

## Unit tests for LevelEnvironmentManager.extract_and_strip_map_environment()'s
## handling of Blender-authored ambient light glTF extras (see GlbUtils
## .extract_lighting_config()) as a map-defaults source alongside embedded
## WorldEnvironment nodes.

const _TEST_GLB_PATH := "user://test_level_environment_manager_lighting_extras.glb"


## Minimal single-scene GLB builder, mirroring
## tests/unit/test_glb_utils_lighting_extras.gd's helper of the same name -- kept
## as a local copy since GDScript test scripts have no shared-helper mechanism.
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


## End-to-end test crossing the GlbUtils -> LevelEnvironmentManager boundary: loads
## a real (minimal) GLB with lighting extras via GlbUtils.load_glb(), then feeds the
## resulting scene straight into LevelEnvironmentManager, mirroring the actual
## production data flow rather than hand-constructing meta on a bare Node3D.
func test_end_to_end_glb_with_extras_feeds_map_defaults() -> void:
	var bytes := _build_minimal_glb({"tt_ambient_light_energy": 3.25})
	var file := FileAccess.open(_TEST_GLB_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

	var scene := GlbUtils.load_glb(_TEST_GLB_PATH)
	assert_not_null(scene)

	var manager := LevelEnvironmentManager.new()
	var config := manager.extract_and_strip_map_environment(scene)

	assert_eq(config.get("ambient_light_energy"), 3.25)

	scene.free()


func test_uses_lighting_extras_as_map_defaults_with_no_world_environment() -> void:
	var root := Node3D.new()
	root.set_meta(
		"tt_gltf_scene_extras",
		{"tt_ambient_light_color": [0.1, 0.2, 0.3], "tt_ambient_light_energy": 1.5}
	)
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_eq(config.get("ambient_light_color"), Color(0.1, 0.2, 0.3))
	assert_eq(config.get("ambient_light_energy"), 1.5)

	root.free()


func test_world_environment_overrides_lighting_extras_on_conflicting_keys() -> void:
	var root := Node3D.new()
	root.set_meta("tt_gltf_scene_extras", {"tt_ambient_light_energy": 1.5})
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_energy = 9.0
	world_env.environment = env
	root.add_child(world_env)
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_eq(config.get("ambient_light_energy"), 9.0)

	root.free()


func test_returns_empty_dict_with_no_extras_and_no_world_environment() -> void:
	var root := Node3D.new()
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_true(config.is_empty())

	root.free()


func test_lighting_extras_survive_world_environment_node_with_no_environment_resource() -> void:
	var root := Node3D.new()
	root.set_meta("tt_gltf_scene_extras", {"tt_ambient_light_energy": 2.5})
	var world_env := WorldEnvironment.new()
	root.add_child(world_env)
	var manager := LevelEnvironmentManager.new()

	var config := manager.extract_and_strip_map_environment(root)

	assert_eq(config.get("ambient_light_energy"), 2.5)

	root.free()
