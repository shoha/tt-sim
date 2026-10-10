extends RefCounted

## Small map GLBs for the import tests (test_glb_check.gd, test_map_import.gd), written at
## test time into the test's own folder rather than committed: GLTFDocument writes real
## ones, and write_glb() writes a GLB from a glTF JSON dictionary alone, for shapes the
## exporter cannot make (external files, a matrix node, a scatter source far off the map).
## Not a test file itself (GUT only collects test_*.gd). Preload it as a const.

const GLB_MAGIC := 0x46546C67
const CHUNK_JSON := 0x4E4F534A
## The scatter source every write_map() GLB names in tt_scatter_instances.
const ROCK := "Rock_Source"
## Where write_map() leaves the scatter source, far off the map as Blender may.
const ROCK_AT := Vector3(500.0, 0.0, 0.0)


## Writes a map GLB to `path` with GLTFDocument: a flat ground `size` metres (X by Z, 0.5 m
## thick, top at `top_y`) as the visual mesh "Ground" and its collision twin
## "Ground-colonly", plus the scatter source ROCK at ROCK_AT, named in the scene extras'
## tt_scatter_instances with `rocks` instances on the ground. OK or the write's error.
static func write_map(path: String, size: Vector2, top_y: float = 0.0, rocks: int = 2) -> Error:
	var root := Node3D.new()
	root.name = "Map"
	var ground_size := Vector3(size.x, 0.5, size.y)
	var ground_at := Vector3(0.0, top_y - 0.25, 0.0)
	root.add_child(_box("Ground", ground_size, ground_at))
	root.add_child(_box("Ground-colonly", ground_size, ground_at))
	root.add_child(_box(ROCK, Vector3.ONE * 0.5, ROCK_AT))
	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err := gltf.append_from_scene(root, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, path)
	root.free()
	if err != OK:
		return err
	var rows: Array = []
	for i in rocks:
		rows.append([float(i), top_y, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	var extras := {"tt_scatter_instances": {ROCK: rows}, "tt_ambient_light_energy": 0.8}
	return patch_scene_extras(path, extras)


## Sets the default scene's extras of the GLB at `path`, as terrain-paint does after export.
static func patch_scene_extras(path: String, extras: Dictionary) -> Error:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 20:
		return ERR_FILE_CORRUPT
	var json_length := bytes.decode_u32(12)
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	if not parsed is Dictionary:
		return ERR_PARSE_ERROR
	var gltf: Dictionary = parsed
	var scenes: Array = gltf.get("scenes", [])
	if scenes.is_empty():
		return ERR_PARSE_ERROR
	scenes[int(gltf.get("scene", 0))]["extras"] = extras
	return write_glb(path, gltf, bytes.slice(20 + json_length))


## Writes a GLB of the glTF JSON `gltf`, followed by `tail` (a BIN chunk with its header, or
## nothing).
static func write_glb(
	path: String, gltf: Dictionary, tail: PackedByteArray = PackedByteArray()
) -> Error:
	var json := JSON.stringify(gltf).to_utf8_buffer()
	while json.size() % 4 != 0:
		json.append(0x20)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, GLB_MAGIC)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + json.size() + tail.size())
	out.encode_u32(12, json.size())
	out.encode_u32(16, CHUNK_JSON)
	out.append_array(json)
	out.append_array(tail)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(out)
	file.close()
	return OK


## A glTF JSON dictionary with one mesh whose POSITION bounds are `low` to `high`, used by
## every node of `nodes` that has a "mesh" key; the default scene's roots are `roots`.
static func gltf_with(
	nodes: Array, roots: Array, low: Vector3, high: Vector3, extras: Dictionary = {}
) -> Dictionary:
	var scene := {"nodes": roots}
	if not extras.is_empty():
		scene["extras"] = extras
	return {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [scene],
		"nodes": nodes,
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
		"accessors":
		[
			{
				"componentType": 5126,
				"count": 2,
				"type": "VEC3",
				"min": [low.x, low.y, low.z],
				"max": [high.x, high.y, high.z],
			}
		],
	}


static func _box(node_name: String, size: Vector3, at: Vector3) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	box.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.position = at
	return box
