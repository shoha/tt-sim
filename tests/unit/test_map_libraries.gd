extends GutTest

## What a map says about its content libraries and what this install makes of it (step S4):
## MapLibraries (the libraries a document uses, the record and format number written, check()
## against the served libraries, "Open without those plants", aliases) and MapLibraryGate (the
## step between reading a document and building it: a missing or incompatible library is asked
## about or reported, never quietly substituted), plus the saved map end to end through
## MapDocumentIO and LibraryGroups (the New map dialog's grouping, pure).

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_map_libraries"
const SETTINGS := ROOT + "/settings.cfg"
const ROWS := [0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
const SPIRE := World.ALIEN_RUNTIME + "/Crystal_Spire_v0"
const OAK := "forest_summer_s1/Tree_Oak_v0"

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
	LibraryRegistry.apply(_paths["base"])


## A document with a core plant and an alienworld plant, painted with both biomes.
func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_alpine", "v", 7)
	doc.scatter[OAK] = PackedFloat32Array(ROWS)
	doc.scatter[SPIRE] = PackedFloat32Array(ROWS)
	doc.props[World.ALIEN_RUNTIME + "/Crystal_Shard_v0"] = PackedFloat32Array(ROWS)
	doc.biome_ids = PackedStringArray([World.CORE_RUNTIME, World.ALIEN_RUNTIME])
	return doc


func _core_claim(version: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": "core", "version": version, "hash": ""}]
	return out


func _ids(items: Array) -> Array:
	return items.map(func(item: Dictionary) -> String: return item["id"])


func _claims(version: String, hash: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"id": "alienworld", "version": version, "hash": hash}]
	return out


# ---- what a document uses, and what is written ----


func test_used_ids_come_from_biomes_assets_props_and_surfaces() -> void:
	assert_eq(MapLibraries.used_ids(_doc()), ["alienworld", "core"])
	var core_only := MapDocument.create_flat(Vector2i(20, 20), "grass_alpine", "v", 7)
	core_only.scatter[OAK] = PackedFloat32Array(ROWS)
	assert_eq(MapLibraries.used_ids(core_only), ["core"])
	var painted := MapDocument.create_flat(Vector2i(20, 20), "", "v", 7)
	painted.surface_ids = PackedStringArray(["alienworld__crystal"])
	assert_eq(MapLibraries.used_ids(painted), ["alienworld"], "a library surface counts")
	assert_eq(MapLibraries.surface_library("grass_alpine"), "core")
	assert_eq(MapLibraries.surface_library("alienworld__crystal"), "alienworld")


func test_the_record_carries_the_version_and_hash_the_registry_serves() -> void:
	var record := MapLibraries.record_for(_doc())
	assert_eq(record.size(), 2)
	assert_eq(record[0]["id"], "alienworld")
	assert_eq(record[0]["version"], "0.3.1")
	assert_eq(record[0]["hash"], LibraryRegistry.info("alienworld", _paths["base"])["hash"])
	assert_eq(record[1]["id"], "core")
	assert_eq(record[1]["version"], "1.2.0")
	assert_eq(MapLibraries.format_for(record), 3)
	assert_eq(MapLibraries.format_for([record[1]]), 2)
	assert_eq(MapLibraries.format_for([] as Array[Dictionary]), 2)


func test_a_saved_map_records_its_libraries_in_the_manifest() -> void:
	var path := ROOT + "/saved.ttmap"
	assert_eq(MapDocumentIO.write(_doc(), path), OK)
	var peeked := MapDocumentIO.peek_libraries(path)
	assert_eq(peeked.size(), 2)
	assert_eq(peeked[0]["id"], "alienworld")
	assert_eq(peeked[0]["version"], "0.3.1")
	var read: MapDocument = MapDocumentIO.read(path)["document"]
	assert_eq(read.libraries, peeked)
	assert_true(MapLibraries.check(read.libraries)["ok"])


# ---- check ----


func test_a_matching_install_is_ok() -> void:
	var report := MapLibraries.check(MapLibraries.record_for(_doc()))
	assert_true(report["ok"])
	assert_eq(report["missing"], [])
	assert_eq(report["incompatible"], [])
	assert_eq(report["warnings"], [])


func test_a_library_that_is_not_installed_is_missing_with_its_name_and_version() -> void:
	var claimed: Array[Dictionary] = [{"id": "ghostworld", "version": "2.1.0", "hash": ""}]
	var report := MapLibraries.check(claimed)
	assert_false(report["ok"])
	assert_eq(report["missing"][0]["id"], "ghostworld")
	assert_eq(report["missing"][0]["version"], "2.1.0")
	assert_eq(report["missing"][0]["reason"], "not installed")
	assert_eq(report["blocked"], ["ghostworld"])
	var text := MapLibraries.describe(report)
	assert_string_contains(text, "ghostworld v2.1.0 is not installed.")
	assert_false("plant" in text.to_lower(), "no 'plants' in a dialog")


func test_a_turned_off_or_failed_library_is_missing_with_the_reason() -> void:
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var report := MapLibraries.check(_claims("0.3.1"))
	assert_eq(report["missing"][0]["reason"], "installed but turned off")
	assert_eq(report["missing"][0]["name"], "Alien World")
	assert_string_contains(MapLibraries.describe(report), "Alien World v0.3.1 by Test Author")
	assert_string_contains(MapLibraries.describe(report), "turned off")
	LibraryRegistry.set_enabled("alienworld", true)
	World.write_alien(_paths["alien"], "0.3.1", [{"id": "core", "version": "^5"}], false)
	LibraryRegistry.apply(_paths["base"])
	var failed := MapLibraries.check(_claims("0.3.1"))
	assert_string_contains(failed["missing"][0]["reason"], "needs library 'core' ^5")


func test_another_major_version_is_incompatible_a_newer_minor_is_fine() -> void:
	var incompatible := MapLibraries.check(_claims("1.0.0"))
	assert_false(incompatible["ok"])
	assert_eq(incompatible["incompatible"][0]["wanted"], "1.0.0")
	assert_eq(incompatible["incompatible"][0]["have"], "0.3.1")
	assert_string_contains(MapLibraries.describe(incompatible), "saved with version 1.0.0")
	assert_string_contains(MapLibraries.describe(incompatible), "has version 0.3.1")
	var older := MapLibraries.check(_core_claim("1.0.0"))
	assert_true(older["ok"], "the installed core is newer in the minor: ids are never removed")
	assert_false(MapLibraries.check(_core_claim("2.0.0"))["ok"])


func test_a_different_hash_at_the_same_version_only_warns() -> void:
	var report := MapLibraries.check(_claims("0.3.1", "deadbeef"))
	assert_true(report["ok"])
	assert_eq(report["warnings"].size(), 1)
	assert_string_contains(report["warnings"][0], "alienworld 0.3.1")


# ---- opening without those plants ----


func test_without_libraries_drops_their_rows_and_points_their_biomes_at_the_fallback() -> void:
	var doc := _doc()
	doc.mass_anchors["x"] = PackedFloat32Array([1.0, 2.0])
	var dropped := MapLibraries.without_libraries(doc, ["alienworld"], World.CORE_RUNTIME)
	assert_eq(dropped, {"rows": 2, "biomes": 1})
	assert_eq(doc.scatter.keys(), [OAK], "core's plants stay")
	assert_eq(doc.props.size(), 0)
	assert_eq(doc.biome_ids, PackedStringArray([World.CORE_RUNTIME, World.CORE_RUNTIME]))
	assert_eq(doc.mass_anchors.size(), 0)
	var untouched := _doc()
	MapLibraries.without_libraries(untouched, ["alienworld"], "")
	assert_eq(untouched.biome_ids[1], World.ALIEN_RUNTIME, "no fallback keeps the ids")


func test_aliases_rename_rows_and_biomes_of_a_served_library() -> void:
	World.edit_json(
		_paths["alien"] + "/library.json",
		func(d: Dictionary) -> void: d["aliases"] = {"Crystal_Old": "Crystal_Spire_v0"}
	)
	LibraryRegistry.apply(_paths["base"])
	var doc := _doc()
	doc.scatter[World.ALIEN_RUNTIME + "/Crystal_Old"] = PackedFloat32Array(ROWS)
	assert_eq(MapLibraries.apply_aliases(doc, _paths["base"]), 1)
	assert_false(doc.scatter.has(World.ALIEN_RUNTIME + "/Crystal_Old"))
	assert_eq(doc.scatter[SPIRE].size(), 20, "the rows joined the renamed asset's")


# ---- the gate ----


func _saved_with_alien() -> Array:
	var doc := _doc()
	var path := ROOT + "/gate.ttmap"
	MapDocumentIO.write(doc, path)
	return [path, doc]


func test_the_gate_lets_a_matching_map_through_untouched() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	var gate: Dictionary = await MapLibraryGate.run(read, Callable(), _paths["base"])
	assert_true(gate["proceed"])
	assert_false(gate["changed"])
	assert_true(read.scatter.has(SPIRE))


func test_the_gate_asks_and_cancel_changes_nothing() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var asked := [0]
	var cancel := func(report: Dictionary) -> bool:
		asked[0] += 1
		assert_eq(report["missing"][0]["id"], "alienworld")
		return false
	var gate: Dictionary = await MapLibraryGate.run(read, cancel, _paths["base"])
	assert_eq(asked[0], 1)
	assert_false(gate["proceed"])
	assert_true(read.scatter.has(SPIRE), "a cancelled open touches nothing")


func test_open_without_those_plants_drops_them_and_says_so() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	# Core is a folder like any library (step S10): the game with only its own core installed.
	LibraryRegistry.user_root = ROOT + "/nowhere"
	LibraryRegistry.apply(_paths["base"])
	var accept := func(_report: Dictionary) -> bool: return true
	var gate: Dictionary = await MapLibraryGate.run(read, accept, _paths["base"])
	assert_true(gate["proceed"])
	assert_true(gate["changed"])
	assert_eq(gate["dropped"]["rows"], 2)
	assert_false(read.scatter.has(SPIRE))
	assert_true(read.scatter.has(OAK))
	assert_eq(read.biome_ids[1], "forest_summer_s1", "the area falls back to the default biome")
	var text := MapLibraryGate.toast_text(
		gate["report"], gate["dropped"], "forest_summer_s1", _paths["base"]
	)
	assert_string_contains(text, "alienworld")
	assert_string_contains(text, "2 left out")
	assert_string_contains(text, "1 areas now use Forest")


func test_without_a_chooser_the_map_opens_without_those_plants_and_still_says_so() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var gate: Dictionary = await MapLibraryGate.run(read, Callable(), _paths["base"])
	assert_true(gate["proceed"])
	assert_false(read.scatter.has(SPIRE))
	assert_false(gate["report"]["ok"], "the substitution is reported, not silent")


func test_an_install_from_the_dialog_reruns_the_check_and_opens_the_map_whole() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var asked := [0]
	# The player turned the collection on from the dialog (as an import would add it): the choice
	# answers RETRY, the gate checks again, finds nothing lacking and never drops a row.
	var import_it := func(_report: Dictionary) -> Variant:
		asked[0] += 1
		LibraryRegistry.set_enabled("alienworld", true)
		LibraryRegistry.apply(_paths["base"])
		return MapLibraryGate.RETRY
	var gate: Dictionary = await MapLibraryGate.run(read, import_it, _paths["base"])
	assert_eq(asked[0], 1, "asked once")
	assert_true(gate["proceed"])
	assert_true(gate["report"]["ok"], "the second check passes")
	assert_eq(gate["dropped"], {}, "nothing was dropped")
	assert_true(read.scatter.has(SPIRE))


func test_a_retry_that_still_lacks_the_library_asks_again() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var answers: Array = [MapLibraryGate.RETRY, false]
	var asked := [0]
	var choose := func(_report: Dictionary) -> Variant:
		asked[0] += 1
		return answers.pop_front()
	var gate: Dictionary = await MapLibraryGate.run(read, choose, _paths["base"])
	assert_eq(asked[0], 2)
	assert_false(gate["proceed"])


func test_no_dialog_string_of_the_gate_says_plants() -> void:
	var made := _saved_with_alien()
	var read: MapDocument = MapDocumentIO.read(made[0])["document"]
	LibraryRegistry.set_enabled("alienworld", false)
	LibraryRegistry.apply(_paths["base"])
	var gate: Dictionary = await MapLibraryGate.run(read, Callable(), _paths["base"])
	var text := MapLibraryGate.toast_text(gate["report"], gate["dropped"], "", _paths["base"])
	assert_false("plant" in text.to_lower(), text)
	assert_false("plant" in LibraryNames.mismatch_title().to_lower())
	assert_false("plant" in LibraryNames.open_without().to_lower())
	assert_false("plant" in LibraryNames.host_uses_title().to_lower())
	assert_true(LibraryNames.lower(2) in LibraryNames.open_without())


# ---- the link a record may carry ----


func test_a_record_carries_the_libraries_link_and_the_report_hands_it_on() -> void:
	World.edit_json(
		_paths["alien"] + "/library.json",
		func(d: Dictionary) -> void: d["url"] = "https://example.org/alienworld"
	)
	LibraryRegistry.apply(_paths["base"])
	var record := MapLibraries.record_for(_doc())
	assert_eq(record[0]["url"], "https://example.org/alienworld")
	assert_false(record[1].has("url"), "core has no link: no key")
	var path := ROOT + "/linked.ttmap"
	assert_eq(MapDocumentIO.write(_doc(), path), OK)
	var peeked := MapDocumentIO.peek_libraries(path)
	assert_eq(peeked[0]["url"], "https://example.org/alienworld", "kept in the manifest")
	# Another install, where the library is not installed at all: the report names the record's.
	var claimed: Array[Dictionary] = [
		{"id": "frostworld", "version": "1.0.0", "hash": "", "url": "https://example.org/frost"}
	]
	var report := MapLibraries.check(claimed)
	assert_eq(report["missing"][0]["url"], "https://example.org/frost")
	assert_true(MapLibraries.is_link("https://example.org/x"))
	assert_false(MapLibraries.is_link("javascript:alert(1)"))
	assert_false(MapLibraries.is_link("https://example.org/a b"))
	assert_false(MapLibraries.is_link("ftp://example.org"))


# ---- LibraryGroups ----


func test_biomes_are_grouped_by_library_core_first_then_alphabetically() -> void:
	var biomes: Array[Dictionary] = [
		{"id": "savanna_summer_s1", "name": "Savanna", "season": "summer"},
		{"id": "zeta__dunes_summer_s1", "name": "Dunes", "season": "summer"},
		{"id": "alienworld__basin_summer_s1", "name": "Basin", "season": "summer"},
		{"id": "alienworld__basin_winter_s1", "name": "Basin", "season": "winter"},
		{"id": "alienworld__crater_summer_s1", "name": "Crater", "season": "summer"},
		{"id": "meadow_summer_s1", "name": "Meadow", "season": "summer"},
	]
	var libraries: Array[Dictionary] = [
		{
			"id": "core",
			"name": "tt-sim Core",
			"version": "1.0.0",
			"status": "ok",
			"default_biome": ""
		},
		{
			"id": "alienworld",
			"name": "Alien World",
			"version": "0.3.1",
			"author": "A",
			"status": "ok",
			"default_biome": "alienworld__crater_summer_s1",
		},
		{"id": "zeta", "name": "Alpha Zeta", "version": "2.0.0", "status": "ok"},
	]
	var groups := LibraryGroups.group(biomes, libraries)
	assert_eq(_ids(groups), ["core", "alienworld", "zeta"])
	assert_eq(groups[1]["name"], "Alien World")
	var core_order := ["savanna_summer_s1", "meadow_summer_s1"]
	assert_eq(_ids(groups[0]["biomes"]), core_order, "core keeps the palette's order")
	var alien_ids := _ids(groups[1]["biomes"])
	assert_eq(alien_ids[0], "alienworld__crater_summer_s1", "the library's default biome is first")
	assert_eq(groups[1]["labels"]["alienworld__basin_summer_s1"], "Basin (summer)")
	assert_eq(groups[1]["labels"]["alienworld__crater_summer_s1"], "Crater")
	assert_eq(groups[1]["default_biome"], "alienworld__crater_summer_s1")


func test_a_library_the_list_does_not_know_is_shown_by_its_id() -> void:
	var biomes: Array[Dictionary] = [{"id": "stranger__home_summer_s1", "name": "Home"}]
	var groups := LibraryGroups.group(biomes, [] as Array[Dictionary])
	assert_eq(groups[0]["name"], "stranger")
	assert_eq(groups[0]["version"], "")
