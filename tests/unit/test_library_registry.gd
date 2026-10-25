extends GutTest

## LibraryRegistry as a multi-library registry (step S4): the official and user roots are
## scanned in load order, an official library beats a user one with the same id, dependencies
## resolve against their version ranges (a library that cannot be served is an entry with
## reasons, never a crash), cross-library refs and the `<lib>__` runtime ids compile and serve,
## enabling and disabling persists in settings.cfg, aliases and retired ids are honoured, and a
## map's (library, asset ids) can be enumerated. The world is written at test time under a
## scratch folder (tests/unit/library_world.gd): `core` (official, 1.2.0) and `alienworld`
## (user, 0.3.1, depends on core ^1.0).

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_library_registry"
const SETTINGS := ROOT + "/settings.cfg"
const SPIRE := World.ALIEN_RUNTIME + "/Crystal_Spire_v0"
const NEEDS_CORE_AND_ZZ := [{"id": "core", "version": "^1"}, {"id": "zzbase", "version": "*"}]

var _paths: Dictionary = {}
var _saved_settings: String = ""
var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_settings = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = SETTINGS
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]


func _info(library_id: String) -> Dictionary:
	return LibraryRegistry.info(library_id, _paths["base"])


func _apply() -> Dictionary:
	return LibraryRegistry.apply(_paths["base"])


func _has_asset(asset_id: String) -> bool:
	return PaletteLibrary.get_palette(_paths["base"])["assets"].has(asset_id)


## The listed library whose folder ends with `suffix`.
func _by_folder(listed: Array[Dictionary], suffix: String) -> Dictionary:
	for item in listed:
		if String(item["folder"]).ends_with(suffix):
			return item
	return {}


func _has_line(lines: Array, needle: String) -> bool:
	return lines.any(func(line: String) -> bool: return needle in line)


func _ids(listed: Array[Dictionary]) -> Array:
	return listed.map(func(item: Dictionary) -> String: return item["id"])


# ---- scan order, sources, the list ----


func test_the_roots_are_scanned_core_first_and_official_is_derived_from_the_location() -> void:
	var listed := LibraryRegistry.refresh(_paths["base"])
	var ids := listed.map(func(item: Dictionary) -> String: return item["id"])
	assert_eq(ids, ["core", "alienworld"])
	assert_eq(listed[0]["source"], "official")
	assert_true(listed[0]["official"])
	assert_eq(listed[1]["source"], "user")
	assert_false(listed[1]["official"], "a user library cannot claim to be official")
	assert_eq(listed[1]["folder"], _paths["alien"])


func test_a_user_library_cannot_claim_official_in_its_own_file() -> void:
	World.edit_json(
		_paths["alien"] + "/library.json", func(d: Dictionary) -> void: d["official"] = true
	)
	var listed := LibraryRegistry.refresh(_paths["base"])
	assert_false(listed[1]["official"])
	assert_true(listed[1]["warnings"].any(func(w: String) -> bool: return "official" in w))


func test_list_describes_each_library_for_the_manager() -> void:
	_apply()
	var core := _info("core")
	var alien := _info("alienworld")
	assert_eq(alien["name"], "Alien World")
	assert_eq(alien["version"], "0.3.1")
	assert_eq(alien["author"], "Test Author")
	assert_eq(alien["license"], "CC0-1.0")
	assert_eq(alien["status"], "ok")
	assert_eq(alien["reasons"], [])
	assert_true(alien["enabled"])
	assert_true(alien["served"])
	assert_eq(alien["asset_count"], 2)
	assert_eq(alien["biome_count"], 1)
	assert_eq(alien["biomes"], [{"id": "crystal_basin", "name": "Crystal Basin"}])
	assert_eq(alien["biome_ids"], [World.ALIEN_RUNTIME])
	assert_eq(alien["default_biome"], World.ALIEN_RUNTIME)
	assert_eq(alien["dependencies"], [{"id": "core", "version": "^1.0"}])
	assert_eq(alien["provides"], {"core": "1.2.0"})
	assert_gt(alien["bytes"], 1000, "the size on disk")
	assert_ne(alien["hash"], "")
	assert_eq(core["biome_ids"], [World.CORE_RUNTIME])
	assert_eq(core["default_biome"], World.CORE_RUNTIME)


func test_core_is_an_official_folder_listed_first_and_nothing_stands_in_for_it() -> void:
	var listed := LibraryRegistry.list(_paths["base"])
	assert_eq(listed[0]["id"], "core")
	assert_eq(listed[0]["source"], "official")
	assert_true(listed[0]["official"])
	assert_eq(listed[0]["version"], "1.2.0", "the version of its library.json")
	# Without the folder there is no core: nothing is listed for it and a library that needs it is
	# an error like any missing dependency (step S10 retired the built-in core).
	DirAccess.remove_absolute(_paths["core"] + "/library.json")
	World.remove_tree(_paths["core"])
	LibraryRegistry.refresh(_paths["base"])
	assert_true(_info("core").is_empty())
	assert_eq(_info("alienworld")["status"], "error")
	assert_string_contains(String(_info("alienworld")["reasons"][0]), "needs library 'core'")


# ---- serving ----


func test_a_non_core_library_is_served_with_prefixed_ids() -> void:
	var result := _apply()
	assert_true(result["ok"], str(result["errors"]))
	assert_eq(result["libraries"], ["core", "alienworld"])
	var base: String = _paths["base"]
	var biome := PaletteLibrary.biome(World.ALIEN_RUNTIME, base)
	assert_eq(biome["biome"], "alienworld__crystal_basin", "the biome field carries the library")
	assert_eq(biome["season"], "summer")
	var assets: Dictionary = PaletteLibrary.get_palette(base)["assets"]
	assert_true(assets.has(World.ALIEN_RUNTIME + "/Crystal_Spire_v0"))
	assert_true(assets.has(World.ALIEN_RUNTIME + "/Crystal_Shard_v0"))
	# Core's own biome replaced the palette's biome of the same id, ids unprefixed.
	assert_true(assets.has("forest_summer_s1/Tree_Oak_v0"))
	assert_false(assets.has("forest_summer_s1/Oak"), "the replaced biome's own assets went")
	assert_true(PaletteLibrary.biome("meadow_summer_s1", base) != {}, "another biome is left alone")


func test_a_cross_library_ref_resolves_through_the_dependency() -> void:
	_apply()
	var spire_rule: Dictionary = PaletteLibrary.species(World.ALIEN_RUNTIME, _paths["base"])[0]
	var shared := World.ALIEN_RUNTIME + "/core__Tree_Oak_v0"
	assert_true(shared in spire_rule["assets"], str(spire_rule["assets"]))
	assert_eq(AssetStore.library_of(shared, _paths["base"]), "core", "the GLB is core's")
	assert_eq(AssetStore.library_of(SPIRE, _paths["base"]), "alienworld")
	assert_string_starts_with(AssetStore.path_of(shared, _paths["base"]), _paths["core"])
	assert_eq(shared.get_slice("/", 0), World.ALIEN_RUNTIME, "live edits need the whole biome id")


func test_a_ref_to_a_library_that_is_not_a_dependency_is_skipped() -> void:
	World.edit_json(
		_paths["alien"] + "/biomes/crystal_basin.json",
		func(d: Dictionary) -> void:
			d["rules"][0]["query"]["match"].append({"ref": "stranger:Anything"})
	)
	var result := _apply()
	assert_true(result["ok"])
	assert_true(result["warnings"].any(func(w: String) -> bool: return "does not depend on" in w))
	assert_eq(_info("alienworld")["status"], "ok")


func test_retired_and_aliased_dependency_ids() -> void:
	World.edit_json(
		_paths["core"] + "/library.json",
		func(d: Dictionary) -> void:
			d["aliases"] = {"Old_Oak": "Tree_Oak_v1"}
			d["retired"] = ["Gone_Oak"]
	)
	World.edit_json(
		_paths["alien"] + "/biomes/crystal_basin.json",
		func(d: Dictionary) -> void:
			d["rules"][0]["query"]["match"].append({"ref": "core:Old_Oak"})
			d["rules"][0]["query"]["match"].append({"ref": "core:Gone_Oak"})
	)
	var result := _apply()
	var rule: Dictionary = PaletteLibrary.species(World.ALIEN_RUNTIME, _paths["base"])[0]
	assert_true(World.ALIEN_RUNTIME + "/core__Tree_Oak_v1" in rule["assets"], "an alias resolves")
	assert_true(result["warnings"].any(func(w: String) -> bool: return "retired" in w))


func test_non_core_libraries_do_not_rebind_the_games_named_things() -> void:
	World.edit_json(
		_paths["alien"] + "/library.json",
		func(d: Dictionary) -> void: d["bindings"] = {"fire": {"burnt_biome": "ember"}}
	)
	_apply()
	assert_eq(LibraryBindings.fire_burnt_biome(), LibraryBindings.default_of("fire.burnt_biome"))


func test_served_records_each_library() -> void:
	_apply()
	var served := LibraryRegistry.served()
	assert_eq(served.keys().size(), 2)
	assert_eq(served["alienworld"]["biome_ids"], [World.ALIEN_RUNTIME])
	assert_eq(served["alienworld"]["assets"], 3, "two of its own and the dependency's oak")
	assert_eq(served["alienworld"]["source"], "user")
	assert_eq(served["core"]["official"], true)


func test_foliage_library_serves_the_installed_libraries_without_a_dev_override() -> void:
	var applied := FoliageLibrary.apply(_paths["base"])
	assert_true(applied["ok"])
	assert_eq(applied["content_library"]["libraries"], ["core", "alienworld"])
	assert_true(LibraryRegistry.discoverable())
	assert_true(_has_asset(SPIRE))
	# Dropping the libraries and applying again puts the base palette back.
	LibraryRegistry.clear()
	LibraryRegistry.official_root = ROOT + "/nowhere"
	LibraryRegistry.user_root = ROOT + "/nowhere_either"
	FoliageLibrary.apply(_paths["base"])
	assert_false(_has_asset(SPIRE))
	assert_false(LibraryRegistry.discoverable())


func test_an_empty_world_changes_nothing() -> void:
	LibraryRegistry.official_root = ROOT + "/nowhere"
	LibraryRegistry.user_root = ROOT + "/nowhere_either"
	var before := PaletteLibrary.get_palette(_paths["base"])
	var result := _apply()
	assert_true(result["ok"])
	assert_false(result["applied"])
	assert_same(PaletteLibrary.get_palette(_paths["base"]), before)
	assert_eq(LibraryRegistry.served(), {})


# ---- duplicates ----


func test_an_official_library_beats_a_user_library_with_the_same_id() -> void:
	World.write_core(_paths["user"] + "/core", "9.0.0")
	var listed := LibraryRegistry.refresh(_paths["base"])
	var by_folder := {}
	for item in listed:
		by_folder[item["folder"]] = item
	assert_eq(by_folder[_paths["core"]]["status"], "ok")
	var shadow: Dictionary = by_folder[_paths["user"] + "/core"]
	assert_eq(shadow["status"], "error")
	assert_true(_has_line(shadow["reasons"], "duplicate library id 'core'"))
	assert_true(_has_line(shadow["reasons"], "official"))
	_apply()
	assert_eq(LibraryRegistry.served()["core"]["version"], "1.2.0", "the official one is served")


func test_the_folder_must_be_named_after_the_library_id() -> void:
	DirAccess.rename_absolute(_paths["alien"], _paths["user"] + "/renamed")
	var listed := LibraryRegistry.refresh(_paths["base"])
	var renamed := _by_folder(listed, "renamed")
	assert_eq(renamed["status"], "error")
	assert_true(_has_line(renamed["reasons"], "named after"))


func test_a_dot_folder_is_an_import_in_progress_and_is_not_scanned() -> void:
	World.write_alien(_paths["user"] + "/.incoming", "0.1.0")
	assert_eq(_ids(LibraryRegistry.refresh(_paths["base"])), ["core", "alienworld"])


# ---- dependencies and unavailable reasons ----


func test_a_dependency_range_that_the_installed_version_does_not_meet_is_unavailable() -> void:
	World.write_alien(_paths["alien"], "0.3.1", [{"id": "core", "version": "^2.0"}])
	var alien := LibraryRegistry.refresh(_paths["base"])[1]
	assert_eq(alien["status"], "error")
	assert_eq(alien["reasons"].size(), 1)
	assert_string_contains(alien["reasons"][0], "needs library 'core' ^2.0, but 1.2.0 is installed")
	var result := _apply()
	assert_true(result["ok"], "a user library that fails is not the developer's override")
	assert_eq(result["libraries"], ["core"])
	assert_true(_has_line(result["errors"], "library alienworld:"))
	assert_eq(PaletteLibrary.biome(World.ALIEN_RUNTIME, _paths["base"]), {})


func test_a_missing_dependency_is_named() -> void:
	World.write_alien(_paths["alien"], "0.3.1", [{"id": "ghostlib", "version": "^1.0"}], false)
	var alien := LibraryRegistry.refresh(_paths["base"])[1]
	assert_eq(alien["status"], "error")
	assert_string_contains(alien["reasons"][0], "'ghostlib'")
	assert_string_contains(alien["reasons"][0], "not installed")


func test_tilde_exact_and_comparator_ranges_resolve() -> void:
	for range_text in ["~1.2", "1.2.0", "1.2", ">=1.0.0 <2.0.0", "*", ">1.1"]:
		World.write_alien(_paths["alien"], "0.3.1", [{"id": "core", "version": range_text}], false)
		assert_eq(LibraryRegistry.refresh(_paths["base"])[1]["status"], "ok", range_text)
	for range_text in ["~1.3", "1.3.0", "<1.2.0", "^1.3"]:
		World.write_alien(_paths["alien"], "0.3.1", [{"id": "core", "version": range_text}], false)
		assert_eq(LibraryRegistry.refresh(_paths["base"])[1]["status"], "error", range_text)


func test_a_dependency_on_a_broken_library_is_unavailable_not_a_crash() -> void:
	World.write_text(_paths["user"] + "/brokenlib/library.json", "{not json")
	var needs := [{"id": "core", "version": "^1"}, {"id": "brokenlib", "version": "*"}]
	World.write_alien(_paths["alien"], "0.3.1", needs, false)
	var listed := LibraryRegistry.refresh(_paths["base"])
	assert_eq(_by_folder(listed, "brokenlib")["status"], "error")
	assert_eq(_info("alienworld")["status"], "error")
	var result := _apply()
	assert_eq(result["libraries"], ["core"])


func test_a_dependency_cycle_is_an_error_for_both() -> void:
	var needs := [{"id": "core", "version": "^1"}, {"id": "pinglib", "version": "*"}]
	World.write_alien(_paths["alien"], "0.3.1", needs, false)
	var ping := _lib("pinglib", [{"id": "alienworld", "version": "*"}])
	World.write_library(_paths["user"] + "/pinglib", ping[0], ping[1], ping[2])
	var listed := LibraryRegistry.refresh(_paths["base"])
	for item in listed:
		if item["id"] in ["alienworld", "pinglib"]:
			assert_eq(item["status"], "error", item["id"])
	var reasons: Array = []
	for item in listed:
		reasons.append_array(item["reasons"])
	assert_true(_has_line(reasons, "dependency cycle"), str(reasons))


func test_dependency_chains_are_limited_in_depth() -> void:
	# core <- l1 <- l2 <- l3 <- l4 <- l5: l5 is five levels above the built-in core.
	var previous := "core"
	for i in range(1, 6):
		var parts := _lib("chain%d" % i, [{"id": previous, "version": "*"}])
		World.write_library(_paths["user"] + "/chain%d" % i, parts[0], parts[1], parts[2])
		previous = "chain%d" % i
	var by_id := {}
	for item in LibraryRegistry.refresh(_paths["base"]):
		by_id[item["id"]] = item
	assert_eq(by_id["chain3"]["status"], "ok")
	assert_eq(by_id["chain5"]["status"], "error")
	assert_true(_has_line(by_id["chain5"]["reasons"], "deeper than"))


func test_dependencies_are_laid_before_the_libraries_that_need_them() -> void:
	# alienworld sorts before zzbase, but depends on it: zzbase is laid first.
	var parts := _lib("zzbase", [])
	World.write_library(_paths["user"] + "/zzbase", parts[0], parts[1], parts[2])
	World.write_alien(_paths["alien"], "0.3.1", NEEDS_CORE_AND_ZZ, false)
	var result := _apply()
	assert_eq(result["libraries"], ["core", "zzbase", "alienworld"])


func test_at_most_sixteen_libraries_are_served() -> void:
	for i in 16:
		var parts := _lib("bulk%02d" % i, [])
		World.write_library(_paths["user"] + "/bulk%02d" % i, parts[0], parts[1], parts[2])
	var result := _apply()
	assert_eq((result["libraries"] as Array).size(), LibraryContracts.MAX_ACTIVE_LIBRARIES)
	assert_true(result["errors"].any(func(e: String) -> bool: return "more than 16" in e))


## [library, assets, biome] for a tiny library `id` with its own biome `home`.
func _lib(id: String, dependencies: Array) -> Array:
	var library := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": id,
		"name": id,
		"version": "1.0.0",
		"contract": 1,
		"dependencies": dependencies,
	}
	var assets := [{"id": "Plant_v0", "category": "tree", "wind": "tree", "size": "large"}]
	var biome := {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": "home",
		"name": "Home",
		"seasons": [{"id": "summer", "seed": 1}],
		"ground": {"surface": "grass"},
		"rules":
		[
			{
				"key": "plants",
				"role": "canopy_tree",
				"density_per_m2": 0.02,
				"query": {"match": [{"ref": "Plant_v0"}]},
			}
		],
	}
	return [library, assets, biome]


# ---- enabling ----


func test_all_libraries_are_enabled_by_default() -> void:
	assert_eq(LibraryRegistry.disabled_ids(), PackedStringArray())
	assert_true(LibraryRegistry.is_enabled("alienworld"))
	assert_true(_info("alienworld")["enabled"])


func test_disabling_persists_in_settings_and_removes_the_library_from_service() -> void:
	assert_true(LibraryRegistry.set_enabled("alienworld", false))
	var config := ConfigFile.new()
	assert_eq(config.load(SETTINGS), OK)
	assert_eq(config.get_value("library", "disabled"), PackedStringArray(["alienworld"]))
	assert_eq(LibraryRegistry.disabled_ids(), PackedStringArray(["alienworld"]))
	var alien := LibraryRegistry.refresh(_paths["base"])[1]
	assert_eq(alien["status"], "disabled")
	assert_false(alien["enabled"])
	var result := _apply()
	assert_eq(result["libraries"], ["core"])
	assert_eq(PaletteLibrary.biome(World.ALIEN_RUNTIME, _paths["base"]), {})
	# Back on: persisted and served again.
	assert_true(LibraryRegistry.set_enabled("alienworld", true))
	assert_eq(LibraryRegistry.disabled_ids(), PackedStringArray())
	LibraryRegistry.clear()
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	assert_eq(_apply()["libraries"], ["core", "alienworld"])


func test_core_cannot_be_disabled_and_other_settings_survive() -> void:
	var config := ConfigFile.new()
	config.set_value("foliage", "library", "plantgen")
	config.save(SETTINGS)
	assert_false(LibraryRegistry.set_enabled("core", false))
	assert_false(LibraryRegistry.set_enabled("Bad Id", false))
	assert_true(LibraryRegistry.set_enabled("alienworld", false))
	config.load(SETTINGS)
	assert_eq(config.get_value("foliage", "library"), "plantgen", "other sections are kept")


func test_a_library_that_needs_a_disabled_one_says_so() -> void:
	var parts := _lib("zzbase", [])
	World.write_library(_paths["user"] + "/zzbase", parts[0], parts[1], parts[2])
	World.write_alien(_paths["alien"], "0.3.1", NEEDS_CORE_AND_ZZ, false)
	LibraryRegistry.set_enabled("zzbase", false)
	LibraryRegistry.refresh(_paths["base"])
	var alien := _info("alienworld")
	assert_eq(alien["status"], "error")
	assert_string_contains(alien["reasons"][0], "which is disabled")


# ---- aliases and maps ----


func test_a_saved_runtime_id_resolves_through_aliases_before_it_is_missing() -> void:
	World.edit_json(
		_paths["alien"] + "/library.json",
		func(d: Dictionary) -> void:
			d["aliases"] = {"Crystal_Spire_Old": "Crystal_Spire_v0", "old_basin": "crystal_basin"}
	)
	_apply()
	var base: String = _paths["base"]
	var old_basin := "alienworld__old_basin_summer_s1"
	var old_spire := World.ALIEN_RUNTIME + "/Crystal_Spire_Old"
	assert_eq(LibraryRegistry.resolve_asset_alias(old_spire, base), SPIRE)
	assert_eq(LibraryRegistry.resolve_asset_alias(SPIRE, base), SPIRE, "a present id is untouched")
	assert_eq(
		LibraryRegistry.resolve_asset_alias(old_basin + "/Crystal_Spire_Old", base),
		SPIRE,
		"a renamed biome and a renamed asset"
	)
	assert_eq(LibraryRegistry.resolve_biome_alias(old_basin, base), World.ALIEN_RUNTIME)
	var unknown := old_basin + "/Unknown"
	assert_eq(LibraryRegistry.resolve_asset_alias(unknown, base), unknown)


func test_assets_used_by_a_map_are_enumerated_per_library() -> void:
	var doc := MapDocument.new()
	var rows := PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	doc.scatter[World.ALIEN_RUNTIME + "/Crystal_Spire_v0"] = rows
	doc.scatter[World.ALIEN_RUNTIME + "/core__Tree_Oak_v0"] = rows
	doc.scatter["forest_summer_s1/Tree_Oak_v0"] = rows
	doc.props[World.ALIEN_RUNTIME + "/Crystal_Shard_v0"] = rows
	var used := LibraryRegistry.assets_used_by(doc)
	assert_eq(used.keys().size(), 2)
	assert_eq(used["alienworld"], PackedStringArray([
		World.ALIEN_RUNTIME + "/Crystal_Shard_v0",
		World.ALIEN_RUNTIME + "/Crystal_Spire_v0",
		World.ALIEN_RUNTIME + "/core__Tree_Oak_v0",
	]))
	assert_eq(used["core"], PackedStringArray(["forest_summer_s1/Tree_Oak_v0"]))


func test_record_of_gives_the_served_version_and_hash() -> void:
	_apply()
	var alien := LibraryRegistry.record_of("alienworld")
	assert_eq(alien["version"], "0.3.1")
	assert_eq(alien["hash"], _info("alienworld")["hash"])
	assert_eq(LibraryRegistry.record_of("nobody"), {})
	assert_eq(LibraryRegistry.record_of("core")["version"], "1.2.0", "core is served like the rest")
	LibraryRegistry.clear()
	assert_eq(LibraryRegistry.record_of("core"), {}, "nothing answers for a library not served")


# ---- the developer override still layers over everything ----


func test_the_dev_override_is_laid_after_the_installed_libraries() -> void:
	var dev := ROOT + "/dev_library"
	World.write_alien(dev, "9.9.9")
	World.edit_json(dev + "/library.json", func(d: Dictionary) -> void: d["id"] = "devworld")
	LibraryRegistry.set_dev_override(dev)
	var result := _apply()
	assert_true(result["ok"], str(result["errors"]))
	assert_eq(result["libraries"], ["core", "alienworld", "devworld"], "the override is last")
	var dev_entry := _info("devworld")
	assert_eq(dev_entry["source"], "dev")
	assert_false(dev_entry["official"])
	assert_true(PaletteLibrary.biome("devworld__crystal_basin_summer_s1", _paths["base"]) != {})
	LibraryRegistry.set_dev_override(ROOT + "/missing_folder")
	var broken := _apply()
	assert_false(broken["ok"], "a developer override that cannot be served is reported")
	assert_string_contains(broken["error"], "not a folder")
	assert_eq(broken["libraries"], ["core", "alienworld"], "the installed libraries are still served")


# ---- a library biome's own thumbnail ----


func _write_thumbnail(side: int, extension: String = "jpg") -> String:
	var picture := Image.create(side, side, false, Image.FORMAT_RGB8)
	picture.fill(Color(0.8, 0.3, 0.6))
	var relative := "biomes/thumbs/crystal_basin." + extension
	var file: String = _paths["alien"] + "/" + relative
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	if extension == "png":
		picture.save_png(file)
	else:
		picture.save_jpg(file)
	World.edit_json(
		_paths["alien"] + "/biomes/crystal_basin.json",
		func(d: Dictionary) -> void: d["thumbnail"] = relative
	)
	return relative


func test_a_biomes_own_thumbnail_is_served_without_an_editor_import() -> void:
	_write_thumbnail(64)
	_apply()
	var biome := PaletteLibrary.biome(World.ALIEN_RUNTIME, _paths["base"])
	var path: String = biome["thumbnail"]
	assert_eq(path, "thumbnails/%s.jpg" % World.ALIEN_RUNTIME)
	var base: String = _paths["base"]
	assert_true(SurfaceStore.available(base, path))
	var texture := SurfaceStore.texture(base, path)
	assert_not_null(texture)
	assert_eq(texture.get_width(), 64)
	assert_same(SurfaceStore.texture(base, path), texture, "cached")
	assert_not_null(BiomeThumbnail.strip(biome, Vector2i(168, 56), base))


func test_a_thumbnail_that_is_listed_but_oversized_or_not_an_image_is_ignored() -> void:
	_write_thumbnail(8, "png")
	var file: String = _paths["alien"] + "/biomes/thumbs/crystal_basin.png"
	# A PNG header claiming 30000 px a side: refused from the header, never decoded.
	var head := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
	head.append_array("IHDR".to_utf8_buffer())
	head.append_array(PackedByteArray([0, 0, 0x75, 0x30, 0, 0, 0x75, 0x30, 8, 6, 0, 0, 0]))
	World.write_bytes(file, head)
	_apply()
	var path: String = PaletteLibrary.biome(World.ALIEN_RUNTIME, _paths["base"])["thumbnail"]
	assert_null(SurfaceStore.texture(_paths["base"], path))
	World.write_text(file, "not an image")
	LibraryRegistry.apply(_paths["base"])
	assert_null(SurfaceStore.texture(_paths["base"], path))


func test_a_thumbnail_outside_the_file_list_or_with_a_bad_path_falls_back_to_legacy() -> void:
	World.edit_json(
		_paths["alien"] + "/biomes/crystal_basin.json",
		func(d: Dictionary) -> void:
			d["thumbnail"] = "biomes/thumbs/not_there.jpg"
			d["legacy"] = {"thumbnail": "thumbnails/old.jpg"}
	)
	_apply()
	var biome := PaletteLibrary.biome(World.ALIEN_RUNTIME, _paths["base"])
	assert_eq(biome["thumbnail"], "thumbnails/old.jpg")


# ---- the foliage library's refresh ----


func test_refresh_libraries_serves_again_and_persists_nothing() -> void:
	LibraryRegistry.official_root = ROOT + "/nowhere"
	LibraryRegistry.user_root = ROOT + "/nowhere_either"
	watch_signals(EventBus)
	var result := FoliageLibrary.refresh_libraries()
	assert_true(result["ok"], str(result["error"]))
	assert_signal_emitted(EventBus, "foliage_library_changed")
	assert_false(FileAccess.file_exists(SETTINGS), "nothing was persisted")
	FoliageLibrary.apply()
