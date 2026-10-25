extends RefCounted

## The small library the biome designer's tests are written against, built from strings (no files
## but the folder a test saves into): `mini` 0.2.0 with eight catalog groups (oak, birch, pine
## trees of two variants each, two rocks, a bush) and one biome `meadow` of three rules (an oak
## rule by refs, a stones rule by a category filter taking one group, a bush rule) in two seasons.
## Not a test file itself; preload it as a const.


static func entry(
	id: String, group: String, category: String, size_class: String, tags: Array
) -> Dictionary:
	return {
		"id": id,
		"group": group,
		"name": group,
		"category": category,
		"subtype": group,
		"tags": tags,
		"seasons": [],
		"roles": [],
		"size_class": size_class,
		"wind_category": "tree" if category == "tree" else "",
		"dimensions_m": [3.0, 5.0, 3.0],
		"triangles": 100,
		"file": "assets/%s.glb" % id,
		"node": id + "_LOD0",
	}


static func catalog() -> Dictionary:
	var assets: Array = []
	for group in ["oak", "birch", "pine"]:
		for v in 2:
			assets.append(entry("Tree_%s_v%d" % [group, v], group, "tree", "large", ["deciduous"]))
	for group in ["rock_a", "rock_b"]:
		assets.append(entry("Rock_%s" % group, group, "rock", "small", ["mineral"]))
	assets.append(entry("Bush_a", "bush_a", "bush", "medium", ["shrub"]))
	return {"format": "ttsim-catalog", "format_version": 1, "assets": assets}


static func biome() -> Dictionary:
	return {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": "meadow",
		"name": "Meadow",
		"surfaces": "legacy",
		"seasons": [{"id": "summer", "seed": 1}, {"id": "autumn", "seed": 2}],
		"ground": {"surface": "grass", "paths": []},
		"rules":
		[
			{
				"key": "oak",
				"role": "canopy_tree",
				"weight": 1,
				"density_per_m2": 0.01,
				"spacing_m": 4.5,
				"slope_max_deg": 35,
				"near": [],
				"avoid": [],
				"query": {"match": [{"ref": "Tree_oak_v0"}, {"ref": "Tree_oak_v1"}]},
			},
			{
				"key": "stones",
				"role": "stones",
				"density_per_m2": 0.06,
				"near": [{"rule": "oak", "distance_m": 3, "influence": 0.4, "transition_m": 2}],
				"avoid": [],
				"query": {"match": [{"category": "rock"}], "count": 1},
			},
			{
				"key": "bushes",
				"role": "shrub",
				"density_per_m2": 0.05,
				"near": [],
				"avoid": [{"rule": "stones", "distance_m": 1, "influence": 0.5, "transition_m": 1}],
				"query": {"match": [{"ref": "Bush_a"}]},
			},
		],
	}


static func context(folder: String, writable: bool = true) -> Dictionary:
	var library := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": "mini",
		"name": "Mini",
		"version": "0.2.0",
		"contract": 1,
	}
	var read := (
		LibraryReader
		. read(
			{
				"library": JSON.stringify(library),
				"catalog": JSON.stringify(catalog()),
				"biomes": {"meadow.json": JSON.stringify(biome())},
			}
		)
	)
	return {
		"ok": true,
		"id": "mini",
		"name": "Mini",
		"version": "0.2.0",
		"source": "user" if writable else "official",
		"official": not writable,
		"writable": writable,
		"folder": folder,
		"read": read,
		"files": [],
		"hash": "abc12345",
		"dependencies": {},
		"dependency_list": [],
		"biomes": ["meadow"],
		"surfaces": {},
	}
