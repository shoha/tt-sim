extends RefCounted

## A small multi-library world for the registry, asset store, map and dialog tests, written at
## test time under a scratch folder: a palette root (one `grass` surface and a `forest_summer_s1`
## biome, as test_library_compile's), an OFFICIAL root holding `core` (the miniature core
## library: biome `forest`, assets `Tree_Oak_v0` and `Tree_Oak_v1`, version 1.2.0) and a USER
## root holding `alienworld` (biome `crystal_basin`, assets `Crystal_Spire_v0` and
## `Crystal_Shard_v0`, depends on core ^1.0, one rule also names the core asset `core:Tree_Oak_v0`).
## The GLBs are real (GLTFDocument writes them), the catalog carries each one's bytes and sha256.
## Not a test file itself (GUT only collects test_*.gd). Preload it as a const.

const ALIEN_RUNTIME := "alienworld__crystal_basin_summer_s1"
const CORE_RUNTIME := "forest_summer_s1"


## Builds the world under `root` and returns {base, official, user, core, alien} (folders).
static func build(root: String) -> Dictionary:
	var world := {
		"base": root + "/base",
		"official": root + "/official",
		"user": root + "/user",
		"core": root + "/official/core",
		"alien": root + "/user/alienworld",
	}
	write_base(world["base"])
	write_core(world["core"])
	write_alien(world["alien"])
	return world


static func write_core(folder: String, version: String = "1.2.0") -> void:
	var library := _library("core", version, "tt-sim Core")
	library["default_biome"] = "forest"
	write_library(
		folder,
		library,
		[_asset("Tree_Oak_v0", "tree", "tree", "large"), _asset("Tree_Oak_v1", "tree", "tree", "large")],
		_biome("forest", "Forest", ["Tree_Oak_v0", "Tree_Oak_v1"], ["Tree_Oak_v0"])
	)


static func write_alien(
	folder: String, version: String = "0.3.1", dependencies: Array = [], with_core_ref: bool = true
) -> void:
	var library := _library("alienworld", version, "Alien World")
	library["dependencies"] = (
		dependencies if not dependencies.is_empty() else [{"id": "core", "version": "^1.0"}]
	)
	library["default_biome"] = "crystal_basin"
	library["author"] = "Test Author"
	var refs: Array = ["Crystal_Spire_v0"]
	if with_core_ref:
		refs.append("core:Tree_Oak_v0")
	write_library(
		folder,
		library,
		[
			_asset("Crystal_Spire_v0", "tree", "tree", "large"),
			_asset("Crystal_Shard_v0", "rock", "", "small"),
		],
		_biome("crystal_basin", "Crystal Basin", refs, ["Crystal_Shard_v0"])
	)


## Writes a library folder: library.json, assets/catalog.json (with each GLB's bytes and sha256),
## the GLBs themselves and biomes/<biome id>.json. `assets` entries are _asset()'s.
static func write_library(
	folder: String, library: Dictionary, assets: Array, biome: Dictionary
) -> void:
	var entries: Array = []
	for item: Dictionary in assets:
		var relative := "assets/%s/%s.glb" % [item["category"], item["id"]]
		var node_name := "%s_LOD0" % item["id"]
		write_glb(folder.path_join(relative), node_name)
		var bytes := FileAccess.get_file_as_bytes(folder.path_join(relative))
		entries.append(
			{
				"id": item["id"],
				"category": item["category"],
				"wind_category": item["wind"],
				"size_class": item["size"],
				"dimensions_m": [2.0, 4.0, 2.0],
				"file": relative,
				"node": node_name,
				"bytes": bytes.size(),
				"sha256": sha256_of(bytes),
			}
		)
	write_json(
		folder.path_join("assets/catalog.json"),
		{"format": "ttsim-catalog", "format_version": 1, "assets": entries}
	)
	write_json(folder.path_join("library.json"), library)
	write_json(folder.path_join("biomes/%s.json" % biome["id"]), biome)


static func _library(id: String, version: String, display: String) -> Dictionary:
	return {
		"format": "ttsim-library",
		"format_version": 1,
		"id": id,
		"name": display,
		"version": version,
		"contract": 1,
		"license": "CC0-1.0",
		"dependencies": [],
	}


static func _asset(id: String, category: String, wind: String, size: String) -> Dictionary:
	return {"id": id, "category": category, "wind": wind, "size": size}


static func _biome(id: String, display: String, tree_refs: Array, stone_refs: Array) -> Dictionary:
	var matches: Array = []
	for ref: String in tree_refs:
		matches.append({"ref": ref})
	var stones: Array = []
	for ref: String in stone_refs:
		stones.append({"ref": ref})
	return {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": id,
		"name": display,
		"climate": "temperate",
		"surfaces": "legacy",
		"seasons": [{"id": "summer", "seed": 1}],
		"ground": {"surface": "grass", "paths": []},
		"rules":
		[
			{
				"key": "trees",
				"role": "canopy_tree",
				"density_per_m2": 0.02,
				"query": {"match": matches},
			},
			{
				"key": "stones",
				"role": "stones",
				"density_per_m2": 0.05,
				"query": {"match": stones},
			},
		],
	}


## A one-triangle GLB whose single mesh node is `node_name`.
static func write_glb(path: String, node_name: String) -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(0.5, 0, 0.2), Vector3(0, 2, 0.1)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var scene_root := Node3D.new()
	scene_root.name = "Root"
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	scene_root.add_child(node)
	node.owner = scene_root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(scene_root, state)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	document.write_to_filesystem(state, path)
	scene_root.free()


static func write_json(path: String, data: Variant) -> void:
	write_text(path, JSON.stringify(data))


static func write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


static func write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


static func sha256_of(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


## Rewrites JSON file `path` through `edit` (a Callable taking the parsed Dictionary).
static func edit_json(path: String, edit: Callable) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	edit.call(data)
	write_json(path, data)


## A palette root of its own: one surface (`grass`) and a forest biome.
static func write_base(base: String) -> void:
	var surface := {
		"albedo": "surfaces/grass/albedo.png",
		"normal": "surfaces/grass/normal.png",
		"orm": "surfaces/grass/orm.png",
		"height": "surfaces/grass/height.png",
		"tile_m": 2.0,
		"kind": "grass",
		"role": "ground",
	}
	var rule := {
		"key": "oak",
		"kind": "tree",
		"size_class": "large",
		"density_per_m2": 0.01,
		"assets": ["forest_summer_s1/Oak"],
	}
	var document := {
		"format": 1,
		"palette_version": "base",
		"surfaces": {"grass": surface},
		"biomes":
		[
			{
				"id": "forest_summer_s1",
				"biome": "forest",
				"season": "summer",
				"seed": 1,
				"name": "Forest",
				"ground_surface": "grass",
				"species": [rule],
			},
			{
				"id": "meadow_summer_s1",
				"biome": "meadow",
				"season": "summer",
				"seed": 1,
				"name": "Meadow",
				"ground_surface": "grass",
				"species": [rule],
			},
		],
		"assets":
		{
			"forest_summer_s1/Oak":
			{
				"file": "assets/forest_summer_s1/Oak.glb",
				"node": "Oak",
				"wind_category": "tree",
				"size_class": "large",
				"dimensions_m": [5, 7, 5],
			}
		},
	}
	write_json(base.path_join("palette.json"), document)


static func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
