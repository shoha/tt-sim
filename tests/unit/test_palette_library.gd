extends GutTest

## PaletteLibrary (utils/palette_library.gd) against docs/ASSET_PIPELINE.md section 9, and
## the seam from a palette through ScatterGlbUtils.build_scatter().
##
## No palette binary is committed yet (the treecube build that makes the golden fixture
## does not exist), so before_all builds a small palette on the fly: three GLBs written by
## GLTFDocument and a matching palette.json under user://. The package is a birch biome on
## purpose: WindFoliage.classify_category() would call its grass "tree" because the id
## contains "birch", so the explicit manifest category is what these tests observe.

const ROOT := "user://test_palette_library"
const PACKAGE := "birch_woodland_summer_s1"
const GRASS_ID := PACKAGE + "/Grass_Tuft"
const TREE_ID := PACKAGE + "/Tree_Small"
const ROCK_ID := PACKAGE + "/Rock_Small"
const MISSING_FILE_ID := PACKAGE + "/Fern_Gone"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join("assets").path_join(PACKAGE))
	_write_glb("Grass_Tuft", _card_mesh(true, 1))
	_write_glb("Tree_Small", _card_mesh(true, 2))
	_write_glb("Rock_Small", BoxMesh.new())
	var file := FileAccess.open(ROOT.path_join("palette.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_valid_document()))
	file.close()


func after_all() -> void:
	PaletteLibrary.clear_cache()
	_remove_tree(ROOT)


func before_each() -> void:
	PaletteLibrary.clear_cache()


# --- fixture builders -------------------------------------------------------------


## Card-like triangles standing 2 m tall; `with_color` adds the COLOR_0 wind weights
## treecube writes on everything that sways (rocks carry none).
func _card_mesh(with_color: bool, surface_count: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in surface_count:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(0.5, 0, 0), Vector3(0, 2, 0)]
		)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		if with_color:
			arrays[Mesh.ARRAY_COLOR] = PackedColorArray(
				[Color(0, 0, 0.2), Color(0, 0, 0.4), Color(1, 1, 0.6)]
			)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, StandardMaterial3D.new())
	return mesh


func _write_glb(object_name: String, mesh: Mesh) -> void:
	var root := Node3D.new()
	root.name = "Root"
	var node := MeshInstance3D.new()
	node.name = object_name
	node.mesh = mesh
	root.add_child(node)
	node.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	var path := ROOT.path_join("assets").path_join(PACKAGE).path_join(object_name + ".glb")
	document.write_to_filesystem(state, path)
	root.free()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _asset_entry(object_name: String, category: String) -> Dictionary:
	return {
		"file": "assets/%s/%s.glb" % [PACKAGE, object_name],
		"node": object_name,
		"wind_category": category,
		"size_class": "small",
		"dimensions_m": [0.5, 2.0, 0.1],
	}


func _species(key: String, kind: String, assets: Array) -> Dictionary:
	return {
		"key": key,
		"kind": kind,
		"size_class": "small",
		"density_per_m2": 0.5,
		"min_spacing_m": 0.3,
		"slope_max_deg": 35.0,
		"scale_spread": 0.3,
		"scale_floor": null,
		"yaw_random_deg": 360.0,
		"align": "upright",
		"pattern": null,
		"clump": null,
		"near": [],
		"avoid": [],
		"assets": assets,
	}


func _surface(surface_name: String, kind: String, role: String, tile_m: float) -> Dictionary:
	var stem := "surfaces/%s/%s" % [surface_name, surface_name]
	return {
		"albedo": stem + "_albedo.png",
		"normal": stem + "_normal.png",
		"orm": stem + "_orm.png",
		"height": stem + "_height.png",
		"tile_m": tile_m,
		"kind": kind,
		"role": role,
	}


func _valid_document() -> Dictionary:
	var grass := _species("grass_tuft", "grass", [GRASS_ID])
	grass["align"] = "normal"
	grass["near"] = [
		{"species": "tree_small", "distance_m": 2.0, "transition_m": 1.0, "influence": 0.5}
	]
	grass["pattern"] = {
		"influence": 0.7,
		"scale_influence": 0.2,
		"geoscatter_pattern": {"texture": {"scale": 4.0, "kind": "NOISE"}, "sample_method": "x"},
	}
	var fern := _species("fern", "fern", [MISSING_FILE_ID])
	fern["clump"] = {
		"parents_per_m2": 0.02, "radius_m": 1.5, "transition_m": 0.5, "children_spacing_m": 0.2
	}
	return {
		"format": 1,
		"palette_version": "abc1234",
		"surfaces":
		{
			"grass_alpine":
			{
				"albedo": "surfaces/grass_alpine/grass_alpine_albedo.png",
				"normal": "surfaces/grass_alpine/grass_alpine_normal.png",
				"orm": "surfaces/grass_alpine/grass_alpine_orm.png",
				"height": "surfaces/grass_alpine/grass_alpine_height.png",
				"tile_m": 2.0,
				"kind": "grass",
				"role": "ground",
			},
			"cliff": _surface("cliff", "cliff", "cliff", 3.0),
			"cliff_basalt": _surface("cliff_basalt", "cliff", "cliff", 3.0),
			"gravel": _surface("gravel", "gravel", "ground", 2.0),
			"cobblestone": _surface("cobblestone", "cobblestone", "built", 2.0),
		},
		"biomes":
		[
			{
				"id": PACKAGE,
				"biome": "birch_woodland",
				"season": "summer",
				"seed": 1,
				"name": "Birch Woodland",
				"climate": "temperate",
				"thumbnail": "thumbnails/%s.jpg" % PACKAGE,
				"ground_surface": "grass_alpine",
				"cliff_surface": "cliff_basalt",
				"scree_surface": "gravel",
				"species":
				[
					_species("tree_small", "tree", [TREE_ID]),
					grass,
					_species("rock_small", "rock", [ROCK_ID]),
					fern,
				],
			}
		],
		"assets":
		{
			TREE_ID: _asset_entry("Tree_Small", "tree"),
			GRASS_ID: _asset_entry("Grass_Tuft", "grass"),
			ROCK_ID: _asset_entry("Rock_Small", ""),
			MISSING_FILE_ID: _asset_entry("Fern_Gone", "grass"),
		},
	}


func _rows(count: int) -> Array:
	var rows: Array = []
	for i in count:
		rows.append([float(i), 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _chunks(parent: Node3D, stem: String) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child in parent.get_children():
		if child is MultiMeshInstance3D and child.name.begins_with(stem + "_MultiMesh"):
			found.append(child as MultiMeshInstance3D)
	return found


# --- validation (pure) --------------------------------------------------------------


func test_a_valid_document_validates_without_warnings() -> void:
	var result := PaletteLibrary.validate_palette(_valid_document())
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	var palette: Dictionary = result.palette
	assert_eq(palette.palette_version, "abc1234")
	assert_eq(palette.assets.size(), 4)
	assert_eq(palette.biomes.size(), 1)
	assert_eq(palette.biomes[0].species.size(), 4)
	assert_eq(palette.surfaces["grass_alpine"]["tile_m"], 2.0)
	assert_eq(palette.assets[TREE_ID]["dimensions_m"], Vector3(0.5, 2.0, 0.1))


func test_anything_but_an_object_is_an_empty_palette() -> void:
	for garbage in [null, 3, "text", [1, 2]]:
		var result := PaletteLibrary.validate_palette(garbage)
		assert_eq(result.palette.biomes.size(), 0)
		assert_eq(result.palette.assets.size(), 0)
		assert_eq(result.warnings.size(), 1)


func test_an_unknown_format_is_an_empty_palette() -> void:
	var document := _valid_document()
	document["format"] = 2
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes.size(), 0)
	assert_eq(result.warnings.size(), 1)


func test_malformed_assets_are_skipped_and_the_rest_kept() -> void:
	var document := _valid_document()
	document.assets["no_slash"] = _asset_entry("X", "grass")
	document.assets[PACKAGE + "/Escape"] = _asset_entry("Escape", "grass")
	document.assets[PACKAGE + "/Escape"]["file"] = "../../outside.glb"
	document.assets[PACKAGE + "/NotGlb"] = _asset_entry("NotGlb", "grass")
	document.assets[PACKAGE + "/NotGlb"]["file"] = "assets/x.png"
	document.assets[PACKAGE + "/NoNode"] = _asset_entry("NoNode", "grass")
	document.assets[PACKAGE + "/NoNode"]["node"] = 7
	document.assets[PACKAGE + "/NotAnObject"] = "assets/x.glb"
	document.assets["x".repeat(PaletteLibrary.MAX_ID_LENGTH) + "/Long"] = _asset_entry("L", "")
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.assets.size(), 4, "only the four valid assets survive")
	assert_eq(result.warnings.size(), 6)


func test_an_unknown_wind_category_places_the_asset_without_sway() -> void:
	var document := _valid_document()
	document.assets[TREE_ID]["wind_category"] = "bush"
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.assets[TREE_ID]["wind_category"], "")
	assert_eq(result.warnings.size(), 1)


func test_a_species_whose_assets_do_not_resolve_is_dropped() -> void:
	var document := _valid_document()
	document.biomes[0].species[0]["assets"] = [PACKAGE + "/Nope", 5]
	var result := PaletteLibrary.validate_palette(document)
	var keys: Array = result.palette.biomes[0].species.map(
		func(s: Dictionary) -> String: return s.key
	)
	assert_false("tree_small" in keys)
	# Two unresolvable ids, the dropped species, and grass's relation to it.
	assert_eq(result.warnings.size(), 4)
	var grass: Dictionary = result.palette.biomes[0].species[0]
	assert_eq(grass.key, "grass_tuft")
	assert_eq(grass.near, [], "a relation to a dropped species is dropped with it")


func test_a_species_missing_required_fields_is_skipped() -> void:
	var document := _valid_document()
	document.biomes[0].species[2].erase("density_per_m2")
	document.biomes[0].species[3]["kind"] = ["not", "text"]
	document.biomes[0].species.append("not an object")
	document.biomes[0].species.append(_species("grass_tuft", "grass", [GRASS_ID]))
	var result := PaletteLibrary.validate_palette(document)
	var keys: Array = result.palette.biomes[0].species.map(
		func(s: Dictionary) -> String: return s.key
	)
	assert_eq(keys, ["tree_small", "grass_tuft"])
	assert_eq(result.warnings.size(), 4, "missing density, bad kind, non-object, duplicate")


func test_numbers_are_clamped_to_the_contract_range_and_wrong_types_fall_back() -> void:
	var document := _valid_document()
	var tree: Dictionary = document.biomes[0].species[0]
	tree["scale_spread"] = 5.0
	tree["slope_max_deg"] = -10.0
	tree["min_spacing_m"] = "wide"
	tree["yaw_random_deg"] = true
	tree["align"] = "sideways"
	var result := PaletteLibrary.validate_palette(document)
	var rule: Dictionary = result.palette.biomes[0].species[0]
	assert_eq(rule.scale_spread, 0.9)
	assert_eq(rule.slope_max_deg, 0.0)
	assert_eq(rule.min_spacing_m, 0.0)
	assert_eq(rule.yaw_random_deg, 360.0)
	assert_eq(rule.align, "upright")
	assert_eq(result.warnings.size(), 3, "two wrong types and one unknown align")


func test_counts_over_the_cap_are_truncated() -> void:
	var document := _valid_document()
	var many: Array = []
	for i in PaletteLibrary.MAX_SPECIES_PER_BIOME + 5:
		many.append(_species("rock_%d" % i, "rock", [ROCK_ID]))
	document.biomes[0]["species"] = many
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes[0].species.size(), PaletteLibrary.MAX_SPECIES_PER_BIOME)
	assert_eq(result.warnings.size(), 1)


func test_duplicate_biome_ids_and_unknown_ground_surfaces_are_rejected() -> void:
	var document := _valid_document()
	document.biomes.append(document.biomes[0].duplicate(true))
	document.biomes[0]["ground_surface"] = "lava"
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes.size(), 1)
	assert_eq(result.palette.biomes[0].ground_surface, "")
	assert_eq(result.warnings.size(), 2)


func test_surface_paths_cannot_escape_the_palette_root() -> void:
	var document := _valid_document()
	document.surfaces["grass_alpine"]["normal"] = "C:/Windows/evil.png"
	document.surfaces["grass_alpine"]["height"] = "surfaces/../../x.png"
	document.surfaces["sand_red"] = {"albedo": "/abs.png", "tile_m": 1.0}
	var result := PaletteLibrary.validate_palette(document)
	var surface: Dictionary = result.palette.surfaces["grass_alpine"]
	assert_eq(surface.normal, "")
	assert_eq(surface.height, "")
	assert_false(result.palette.surfaces.has("sand_red"), "an escaping albedo drops the surface")


func test_surface_kind_and_role_and_biome_cliff_and_scree_are_exposed() -> void:
	var result := PaletteLibrary.validate_palette(_valid_document())
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	var surfaces: Dictionary = result.palette.surfaces
	assert_eq(surfaces["grass_alpine"].kind, "grass")
	assert_eq(surfaces["grass_alpine"].role, "ground")
	assert_eq(surfaces["cliff_basalt"].kind, "cliff")
	assert_eq(surfaces["cliff_basalt"].role, "cliff")
	assert_eq(surfaces["cobblestone"].role, "built")
	var biome: Dictionary = result.palette.biomes[0]
	assert_eq(biome.cliff_surface, "cliff_basalt")
	assert_eq(biome.scree_surface, "gravel")


func test_an_unknown_role_warns_and_is_ground() -> void:
	var document := _valid_document()
	document.surfaces["cobblestone"]["role"] = "wall"
	document.surfaces["gravel"]["role"] = 3
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.surfaces["cobblestone"].role, "ground")
	assert_eq(result.palette.surfaces["gravel"].role, "ground")
	assert_eq(result.warnings.size(), 2, str(result.warnings))


func test_a_palette_from_before_roles_loads_silently_as_ground() -> void:
	var document := _valid_document()
	for surface_name in document.surfaces:
		document.surfaces[surface_name].erase("role")
		document.surfaces[surface_name].erase("kind")
	document.biomes[0].erase("cliff_surface")
	document.biomes[0].erase("scree_surface")
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	assert_eq(result.palette.surfaces["cliff"].role, "ground")
	assert_eq(result.palette.surfaces["cliff"].kind, "")
	assert_eq(result.palette.biomes[0].cliff_surface, "", "no cliff surface at all: none")
	assert_eq(result.palette.biomes[0].scree_surface, "", "no scree: the foot keeps the ground")


func test_a_missing_cliff_surface_falls_back_to_the_first_cliff_silently() -> void:
	var document := _valid_document()
	document.biomes[0].erase("cliff_surface")
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	assert_eq(
		result.palette.biomes[0].cliff_surface, "cliff", "first role-cliff surface in file order"
	)


func test_cliff_and_scree_surfaces_with_the_wrong_role_or_absent_warn_and_fall_back() -> void:
	var document := _valid_document()
	document.biomes[0]["cliff_surface"] = "gravel"
	document.biomes[0]["scree_surface"] = "cliff"
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes[0].cliff_surface, "cliff")
	assert_eq(result.palette.biomes[0].scree_surface, "")
	assert_eq(result.warnings.size(), 2, str(result.warnings))
	document.biomes[0]["cliff_surface"] = "lava"
	document.biomes[0]["scree_surface"] = ["not", "text"]
	result = PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes[0].cliff_surface, "cliff")
	assert_eq(result.palette.biomes[0].scree_surface, "")
	assert_eq(result.warnings.size(), 2, str(result.warnings))


## _valid_document() plus a moss ground surface, a second built surface, and the biome's
## ground accents and path surfaces (contract section 9, 2026-09-27).
func _document_with_accents() -> Dictionary:
	var document := _valid_document()
	document.surfaces["moss"] = _surface("moss", "moss", "ground", 2.0)
	document.surfaces["flagstone"] = _surface("flagstone", "flagstone", "built", 2.0)
	document.biomes[0]["ground_accents"] = [
		{"surface": "moss", "coverage": 0.3, "scale_m": 8.0},
		{"surface": "gravel", "coverage": 0.1, "scale_m": 4.0},
	]
	document.biomes[0]["path_surfaces"] = ["flagstone", "cobblestone"]
	return document


func test_accents_and_path_surfaces_are_parsed_in_order() -> void:
	var result := PaletteLibrary.validate_palette(_document_with_accents())
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	var biome: Dictionary = result.palette.biomes[0]
	assert_eq(
		biome.ground_accents,
		[
			{"surface": "moss", "coverage": 0.3, "scale_m": 8.0},
			{"surface": "gravel", "coverage": 0.1, "scale_m": 4.0},
		]
	)
	assert_eq(biome.path_surfaces, ["flagstone", "cobblestone"])


func test_a_palette_without_accents_or_paths_loads_silently_empty() -> void:
	var result := PaletteLibrary.validate_palette(_valid_document())
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	assert_eq(result.palette.biomes[0].ground_accents, [])
	assert_eq(result.palette.biomes[0].path_surfaces, [])
	var empty := _document_with_accents()
	empty.biomes[0]["ground_accents"] = []
	empty.biomes[0]["path_surfaces"] = []
	result = PaletteLibrary.validate_palette(empty)
	assert_eq(result.warnings.size(), 0, str(result.warnings))
	assert_eq(result.palette.biomes[0].ground_accents, [])


func test_bad_accent_entries_warn_and_are_dropped() -> void:
	var document := _document_with_accents()
	document.biomes[0]["ground_accents"] = [
		"moss",
		{"surface": "lava", "coverage": 0.2},
		{"surface": "cliff", "coverage": 0.2},
		{"surface": "cobblestone", "coverage": 0.2},
		{"surface": "grass_alpine", "coverage": 0.2},
		{"surface": "moss", "coverage": true},
		{"surface": "moss", "coverage": 0.2},
		{"surface": "moss", "coverage": 0.1},
	]
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(
		result.palette.biomes[0].ground_accents,
		[{"surface": "moss", "coverage": 0.2, "scale_m": PaletteLibrary.DEFAULT_ACCENT_SCALE_M}]
	)
	# Not an object, absent, cliff, built, the biome's own ground, a bool coverage, and the
	# second moss.
	assert_eq(result.warnings.size(), 7, str(result.warnings))
	document.biomes[0]["ground_accents"] = [{"surface": "moss"}]
	result = PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes[0].ground_accents, [], "no coverage is malformed")
	assert_eq(result.warnings.size(), 1, str(result.warnings))


func test_accent_numbers_are_clamped_and_a_bad_scale_becomes_the_default() -> void:
	var document := _document_with_accents()
	document.biomes[0]["ground_accents"] = [
		{"surface": "moss", "coverage": 1.7, "scale_m": -3.0},
		{"surface": "gravel", "coverage": -0.2, "scale_m": "big"},
	]
	var result := PaletteLibrary.validate_palette(document)
	var accents: Array = result.palette.biomes[0].ground_accents
	assert_eq(accents[0].coverage, 1.0)
	assert_eq(accents[1].coverage, 0.0)
	assert_eq(accents[0].scale_m, PaletteLibrary.DEFAULT_ACCENT_SCALE_M)
	assert_eq(accents[1].scale_m, PaletteLibrary.DEFAULT_ACCENT_SCALE_M)
	assert_eq(result.warnings.size(), 2, str(result.warnings))


func test_bad_path_surfaces_warn_and_duplicates_are_ignored() -> void:
	var document := _document_with_accents()
	document.biomes[0]["path_surfaces"] = ["cobblestone", "gravel", "lava", 4, "cobblestone"]
	var result := PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes[0].path_surfaces, ["cobblestone"])
	assert_eq(result.warnings.size(), 3, "gravel is ground, lava absent, 4 not a name")
	document.biomes[0]["path_surfaces"] = "cobblestone"
	document.biomes[0]["ground_accents"] = {"surface": "moss"}
	result = PaletteLibrary.validate_palette(document)
	assert_eq(result.palette.biomes[0].path_surfaces, [])
	assert_eq(result.palette.biomes[0].ground_accents, [])
	assert_eq(result.warnings.size(), 2, str(result.warnings))


func test_accent_and_path_getters() -> void:
	assert_eq(PaletteLibrary.ground_accents(PACKAGE, ROOT), [])
	assert_eq(PaletteLibrary.path_surfaces(PACKAGE, ROOT), [])
	assert_eq(PaletteLibrary.ground_accents("nope", ROOT), [])
	PaletteLibrary._palettes[ROOT] = (
		PaletteLibrary.validate_palette(_document_with_accents()).palette
	)
	assert_eq(PaletteLibrary.ground_accents(PACKAGE, ROOT).size(), 2)
	assert_eq(PaletteLibrary.path_surfaces(PACKAGE, ROOT), ["flagstone", "cobblestone"])


func test_surfaces_with_role_from_disk() -> void:
	assert_eq(PaletteLibrary.surfaces_with_role("cliff", ROOT), ["cliff", "cliff_basalt"])
	assert_eq(PaletteLibrary.surfaces_with_role("built", ROOT), ["cobblestone"])
	assert_eq(PaletteLibrary.surfaces_with_role("ground", ROOT), ["grass_alpine", "gravel"])
	assert_eq(PaletteLibrary.biome(PACKAGE, ROOT).cliff_surface, "cliff_basalt")


func test_the_geoscatter_pattern_is_kept_verbatim_but_bounded() -> void:
	var document := _valid_document()
	var pattern: Dictionary = document.biomes[0].species[1]["pattern"]
	pattern.geoscatter_pattern["deep"] = {"a": {"b": {"c": {"d": 1}}}}
	pattern.geoscatter_pattern["long"] = "x".repeat(PaletteLibrary.MAX_TEXT_LENGTH + 1)
	var result := PaletteLibrary.validate_palette(document)
	var kept: Dictionary = result.palette.biomes[0].species[1].pattern.geoscatter_pattern
	assert_eq(kept.texture, {"scale": 4.0, "kind": "NOISE"})
	assert_eq(kept.sample_method, "x")
	assert_eq(kept.deep, {"a": {"b": {}}}, "nesting is cut at MAX_VERBATIM_DEPTH")
	assert_false(kept.has("long"))


# --- loading and read access ---------------------------------------------------------


func test_a_root_without_a_palette_is_empty_and_warns_once() -> void:
	var missing := "user://no_palette_here"
	assert_eq(PaletteLibrary.biomes(missing).size(), 0)
	assert_eq(PaletteLibrary.surfaces(missing), {})
	assert_eq(PaletteLibrary.palette_version(missing), "")
	assert_engine_error(1, "one warning for the missing palette, not one per call")


func test_read_access_from_disk() -> void:
	var biomes := PaletteLibrary.biomes(ROOT)
	assert_eq(biomes.size(), 1)
	assert_eq(biomes[0].name, "Birch Woodland")
	assert_eq(PaletteLibrary.biome(PACKAGE, ROOT).season, "summer")
	assert_eq(PaletteLibrary.biome("nope", ROOT), {})
	var rules := PaletteLibrary.species(PACKAGE, ROOT)
	assert_eq(rules.size(), 4)
	assert_eq(rules[1].near[0].species, "tree_small")
	assert_eq(rules[3].clump.children_spacing_m, 0.2)
	assert_true(PaletteLibrary.surfaces(ROOT).has("grass_alpine"))
	assert_eq(PaletteLibrary.asset(ROCK_ID, ROOT).wind_category, "")


func test_read_access_hands_out_copies() -> void:
	PaletteLibrary.biomes(ROOT)[0]["name"] = "changed"
	PaletteLibrary.species(PACKAGE, ROOT)[0]["key"] = "changed"
	assert_eq(PaletteLibrary.biome(PACKAGE, ROOT).name, "Birch Woodland")
	assert_eq(PaletteLibrary.species(PACKAGE, ROOT)[0].key, "tree_small")


# --- resolve --------------------------------------------------------------------------


func test_resolve_returns_the_manifest_category_and_a_node_safe_name() -> void:
	var grass := PaletteLibrary.resolve(GRASS_ID, ROOT)
	assert_true(grass.mesh is Mesh)
	assert_eq(grass.wind_category, "grass", "explicit, although the id contains 'birch'")
	assert_eq(grass.name, PACKAGE + "_Grass_Tuft")
	assert_eq(PaletteLibrary.resolve(ROCK_ID, ROOT).wind_category, "")


func test_resolve_an_unknown_id_is_empty_with_a_warning() -> void:
	assert_eq(PaletteLibrary.resolve(PACKAGE + "/Nope", ROOT), {})
	assert_engine_error(1)


func test_an_asset_whose_file_is_missing_resolves_empty_and_warns_once() -> void:
	assert_eq(PaletteLibrary.resolve(MISSING_FILE_ID, ROOT), {})
	assert_eq(PaletteLibrary.resolve(MISSING_FILE_ID, ROOT), {})
	assert_engine_error(1, "a failed load is cached, so it warns once")


func test_every_resolve_hands_out_a_fresh_mesh() -> void:
	var first: Mesh = PaletteLibrary.resolve(TREE_ID, ROOT).mesh
	var second: Mesh = PaletteLibrary.resolve(TREE_ID, ROOT).mesh
	assert_ne(first, second)
	assert_ne(first.get_rid(), second.get_rid())
	assert_eq(first.get_surface_count(), 2)


# --- the seam: palette -> build_scatter ----------------------------------------------


func test_two_loads_with_different_overrides_get_different_wind_parameters() -> void:
	var level_a := Node3D.new()
	var level_b := Node3D.new()
	var groups := {GRASS_ID: _rows(3)}
	var resolve := PaletteLibrary.resolver(ROOT)
	ScatterGlbUtils.build_scatter(level_a, groups, resolve, {"grass_sway_speed": 4.4})
	ScatterGlbUtils.build_scatter(level_b, groups, resolve, {"grass_sway_speed": 0.5})
	var stem := PACKAGE + "_Grass_Tuft"
	var mesh_a: Mesh = _chunks(level_a, stem)[0].multimesh.mesh
	var mesh_b: Mesh = _chunks(level_b, stem)[0].multimesh.mesh
	var material_a := mesh_a.surface_get_material(0) as ShaderMaterial
	var material_b := mesh_b.surface_get_material(0) as ShaderMaterial
	assert_not_null(material_a)
	assert_not_null(material_b)
	assert_almost_eq(float(material_a.get_shader_parameter("sway_speed")), 4.4, 0.0001)
	assert_almost_eq(float(material_b.get_shader_parameter("sway_speed")), 0.5, 0.0001)
	assert_true(material_a.get_shader_parameter("use_vertex_wind"), "COLOR_0 survived the GLB")
	level_a.free()
	level_b.free()


func test_the_cached_source_mesh_keeps_its_standard_materials() -> void:
	var level := Node3D.new()
	ScatterGlbUtils.build_scatter(
		level, {TREE_ID: _rows(2), GRASS_ID: _rows(2)}, PaletteLibrary.resolver(ROOT)
	)
	# A fresh resolve is a duplicate of the cached source, so its surfaces show the
	# source's: still the imported StandardMaterial3D, not the wind ShaderMaterial the
	# build just applied to its own copy.
	for asset_id in [TREE_ID, GRASS_ID]:
		var fresh: Mesh = PaletteLibrary.resolve(asset_id, ROOT).mesh
		for surface in fresh.get_surface_count():
			assert_true(fresh.surface_get_material(surface) is StandardMaterial3D, asset_id)
	var source: Mesh = PaletteLibrary._source_meshes[ROOT + "|" + TREE_ID]
	assert_true(is_instance_valid(source), "build_scatter frees nothing the palette owns")
	assert_true(source.surface_get_material(0) is StandardMaterial3D)
	level.free()


func test_palette_rows_build_chunks_with_the_manifest_categories() -> void:
	var level := Node3D.new()
	var groups := {GRASS_ID: _rows(25), TREE_ID: _rows(5), ROCK_ID: _rows(12)}
	var built := ScatterGlbUtils.build_scatter(
		level, groups, PaletteLibrary.resolver(ROOT), {}, 10.0
	)
	assert_eq(built.size(), 3)
	var grass := _chunks(level, PACKAGE + "_Grass_Tuft")
	var tree := _chunks(level, PACKAGE + "_Tree_Small")
	var rock := _chunks(level, PACKAGE + "_Rock_Small")
	assert_eq(grass.size(), 3, "x = 0..24 at chunk 10 is three cells")
	assert_eq(tree.size(), 1)
	assert_eq(rock.size(), 2)
	assert_eq(level.get_child_count(), 6, "only chunks are added under the parent")
	for chunk in grass:
		assert_eq(chunk.get_meta("wind_foliage_category"), "grass")
		assert_eq(chunk.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(tree[0].get_meta("wind_foliage_category"), "tree")
	assert_true(tree[0].multimesh.mesh.surface_get_material(1) is ShaderMaterial)
	for chunk in rock:
		assert_eq(chunk.get_meta("wind_foliage_category"), "")
		assert_true(chunk.multimesh.mesh.surface_get_material(0) is StandardMaterial3D)
	level.free()


func test_rows_naming_a_missing_asset_are_skipped_and_the_rest_built() -> void:
	var level := Node3D.new()
	var groups := {PACKAGE + "/Nope": _rows(3), GRASS_ID: _rows(3)}
	var built := ScatterGlbUtils.build_scatter(level, groups, PaletteLibrary.resolver(ROOT))
	assert_eq(built.size(), 1)
	assert_eq(built[0], GRASS_ID)
	assert_eq(level.get_child_count(), 1)
	assert_engine_error(1, "the unknown id warns")
	level.free()
