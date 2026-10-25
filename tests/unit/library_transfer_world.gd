extends RefCounted

## The world the library transfer tests share (not a test file): the two-library world of
## library_world.gd, with `alienworld` grown into a library worth trimming. Beside
## `Crystal_Spire_v0` and `Crystal_Shard_v0` it has `Crystal_Unused_v0` and a second biome
## `ice_flats` that only uses the unused one, and its biome `crystal_basin` takes its ground
## from the library's own surface `crystal_dust`. A map using only the Spire in `crystal_basin`
## therefore needs: the Spire's GLB, the `crystal_basin` biome-def cut to its Spire rule, and the
## `crystal_dust` surface; and the core asset `Tree_Oak_v0` that one rule names (core is
## official, so it is not sent).

const World := preload("res://tests/unit/library_world.gd")
const SPIRE := World.ALIEN_RUNTIME + "/Crystal_Spire_v0"
const SHARD := World.ALIEN_RUNTIME + "/Crystal_Shard_v0"
const CORE_OAK := World.ALIEN_RUNTIME + "/core__Tree_Oak_v0"
const ICE_RUNTIME := "alienworld__ice_flats_summer_s1"


## Builds the world under `root` (host side): returns World.build's paths.
static func build(root: String) -> Dictionary:
	var paths := World.build(root)
	var alien: String = paths["alien"]
	var library := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": "alienworld",
		"name": "Alien World",
		"description": "A test collection.",
		"version": "0.3.1",
		"contract": 1,
		"license": "CC0-1.0",
		"author": "Test Author",
		"thumbnail": "cover.png",
		"stats": {"assets": 3},
		"dependencies": [{"id": "core", "version": "^1.0"}],
		"default_biome": "crystal_basin",
	}
	var basin: Dictionary = World._biome(
		"crystal_basin",
		"Crystal Basin",
		["Crystal_Spire_v0", "core:Tree_Oak_v0"],
		["Crystal_Shard_v0"]
	)
	basin["surfaces"] = "library"
	basin["ground"] = {"surface": "crystal_dust", "paths": []}
	(
		World
		. write_library(
			alien,
			library,
			[
				World._asset("Crystal_Spire_v0", "tree", "tree", "large"),
				World._asset("Crystal_Shard_v0", "rock", "", "small"),
				World._asset("Crystal_Unused_v0", "rock", "", "small"),
			],
			basin
		)
	)
	var ice: Dictionary = World._biome(
		"ice_flats", "Ice Flats", ["Crystal_Unused_v0"], ["Crystal_Unused_v0"]
	)
	World.write_json(alien.path_join("biomes/ice_flats.json"), ice)
	write_surface(alien, "crystal_dust")
	write_surface(alien, "night_rock")
	return paths


## surfaces/<name>/ with four 8 by 8 PNGs and a surface.json.
static func write_surface(library_folder: String, surface_name: String) -> void:
	var base := library_folder.path_join("surfaces/" + surface_name)
	DirAccess.make_dir_recursive_absolute(base)
	for kind in ["albedo", "normal", "orm", "height"]:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.4, 0.5, 0.6))
		image.save_png(base.path_join(kind + ".png"))
	World.write_json(
		base.path_join("surface.json"),
		{"label": surface_name, "kind": "dust", "role": "ground", "tile_m": 2.0}
	)


## A document that uses only the Spire in `crystal_basin` (and the core oak a rule names), painted
## in that biome and the library's surface, claiming `version` and `hash` of alienworld.
static func map_using_spire(
	version: String = "0.3.1", hash_text: String = "abc12345"
) -> MapDocument:
	var doc := MapDocument.new()
	doc.scatter[SPIRE] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	doc.scatter[CORE_OAK] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	doc.biome_ids = PackedStringArray([World.ALIEN_RUNTIME])
	doc.surface_ids = PackedStringArray(["alienworld__crystal_dust"])
	doc.libraries = (
		[{"id": "alienworld", "version": version, "hash": hash_text}] as Array[Dictionary]
	)
	return doc


## The request a client would send for `doc` (the plan's only request).
static func request_for(doc: MapDocument, view: Dictionary, assets: Dictionary) -> Dictionary:
	var plan := LibraryTransfer.plan(doc, view, assets)
	return plan["requests"][0] if not (plan["requests"] as Array).is_empty() else {}
