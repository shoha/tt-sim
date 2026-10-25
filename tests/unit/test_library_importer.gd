extends GutTest

## LibraryImporter and LibraryInstall (step S6): a library zip or folder is judged BEFORE anything
## is written (caps, extensions, portable names, links, twins, bombs), staged in a quarantine
## folder, read and compiled in a dry run, and only then moved into `<libraries>/<id>/`. The
## hostile archives are written byte by byte (tests/unit/zip_builder.gd) because ZIPPacker only
## writes well-formed ones; the library they carry is the two-library world of library_world.gd.

const World := preload("res://tests/unit/library_world.gd")
const Zip := preload("res://tests/unit/zip_builder.gd")
const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const ROOT := "user://test_library_importer"
const SETTINGS := ROOT + "/settings.cfg"
const SOURCE := ROOT + "/source/alienworld"
const INBOX := ROOT + "/inbox"
const SYMLINK_MODE := 0xA1FF0000

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
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	# The library to import is a copy of the world's alienworld outside every scanned root; the
	# installed one is removed so a fresh import is an install, and put back by tests that want it.
	World.write_alien(SOURCE)
	World.edit_json(
		SOURCE + "/biomes/crystal_basin.json",
		func(biome: Dictionary) -> void: biome["ground"]["surface"] = "grass_alpine"
	)
	World.remove_tree(_paths["alien"])
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = SETTINGS
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	DirAccess.make_dir_recursive_absolute(INBOX)


# ---- helpers ----


func _entries(prefix: String = "") -> Array[Dictionary]:
	return Zip.entries_of(SOURCE, prefix)


func _zip(entries: Array, file_name: String = "pack.ttlib") -> String:
	var path := INBOX.path_join(file_name)
	Zip.write(path, entries)
	return path


func _plan_of(entries: Array) -> Dictionary:
	return LibraryImporter.inspect(_zip(entries))


func _extra(entries: Array[Dictionary], extra: Dictionary) -> Array:
	var out: Array = entries.duplicate()
	out.append(extra)
	return out


func _has_line(lines: Array, needle: String) -> bool:
	return lines.any(func(line: String) -> bool: return needle in line)


func _stage(plan: Dictionary) -> Dictionary:
	assert_true(plan["ok"], "plan is ok: %s" % str(plan["errors"]))
	var staged := LibraryImporter.stage(plan)
	assert_true(staged["ok"], str(staged["error"]))
	return staged


func _card_of(entries: Array) -> Dictionary:
	var staged := _stage(_plan_of(entries))
	return LibraryInstall.examine(staged["folder"])


func _refused(entries: Array, needle: String) -> void:
	var plan := _plan_of(entries)
	assert_false(plan["ok"], "refused: " + needle)
	assert_true(_has_line(plan["errors"], needle), "%s in %s" % [needle, str(plan["errors"])])
	# Nothing was extracted: inspect() never writes.
	assert_false(DirAccess.dir_exists_absolute(LibraryImporter.incoming_root()))


# ---- the happy path ----


func test_a_zip_is_inspected_staged_examined_and_installed() -> void:
	var plan := _plan_of(_entries())
	assert_true(plan["ok"], str(plan["errors"]))
	assert_eq(plan["kind"], "zip")
	assert_eq(plan["prefix"], "")
	assert_gt((plan["files"] as Array).size(), 4)
	var staged := _stage(plan)
	var folder: String = staged["folder"]
	assert_true(LibraryImporter.is_quarantined(folder), "quarantined: " + folder)
	assert_true(FileAccess.file_exists(folder + "/library.json"))
	assert_true(FileAccess.file_exists(folder + "/assets/catalog.json"))
	var card := LibraryInstall.examine(folder)
	assert_true(card["can_install"], str(card["errors"]))
	assert_eq(card["id"], "alienworld")
	assert_eq(card["name"], "Alien World")
	assert_eq(card["author"], "Test Author")
	assert_eq(card["version"], "0.3.1")
	assert_eq(card["license"], "CC0-1.0")
	assert_eq(card["asset_count"], 2)
	assert_eq(card["biome_count"], 1)
	assert_eq(card["relation"], LibraryInstall.RELATION_NEW)
	assert_gt(card["bytes"], 0)
	var deps: Array = card["dependencies"]
	assert_eq(deps.size(), 1)
	assert_eq(deps[0]["state"], LibraryInstall.DEP_OK)
	var done := LibraryInstall.install(card)
	assert_true(done["ok"], str(done["error"]))
	assert_false(done["replaced"])
	assert_false(DirAccess.dir_exists_absolute(folder), "the staged folder was moved")
	LibraryRegistry.refresh()
	var info := LibraryRegistry.info("alienworld")
	assert_eq(info["status"], "ok")
	assert_eq(info["source"], "user")
	assert_false(info["official"], "official comes from the location, never from an import")
	assert_eq(info["version"], "0.3.1")
	assert_eq(info["asset_count"], 2)


func test_a_zip_made_from_the_libraries_folder_is_unwrapped() -> void:
	var plan := _plan_of(_entries("alienworld/"))
	assert_true(plan["ok"], str(plan["errors"]))
	assert_eq(plan["prefix"], "alienworld")
	for item: Dictionary in plan["files"]:
		assert_false(String(item["name"]).begins_with("alienworld/"))
	var card := LibraryInstall.examine(_stage(plan)["folder"])
	assert_true(card["can_install"], str(card["errors"]))


func test_a_folder_is_imported_like_a_zip_and_a_wrapping_folder_is_unwrapped() -> void:
	var plan := LibraryImporter.inspect(SOURCE)
	assert_true(plan["ok"], str(plan["errors"]))
	assert_eq(plan["kind"], "folder")
	assert_eq(LibraryInstall.examine(_stage(plan)["folder"])["id"], "alienworld")
	var parent := LibraryImporter.inspect(SOURCE.get_base_dir())
	assert_true(parent["ok"], "one folder holding the library: " + str(parent["errors"]))
	assert_eq(parent["prefix"], "alienworld")


func test_is_candidate_tells_a_library_from_anything_else() -> void:
	assert_true(LibraryImporter.is_candidate(SOURCE))
	assert_true(LibraryImporter.is_candidate(_zip(_entries())))
	assert_true(LibraryImporter.is_candidate(_zip(_entries("wrapped/"), "w.zip")))
	assert_false(LibraryImporter.is_candidate(_zip([{"name": "a.txt", "data": "x"}], "o.zip")))
	assert_false(LibraryImporter.is_candidate(_zip(_entries(), "x.glb")), "extension decides")
	assert_false(LibraryImporter.is_candidate(INBOX), "a folder without a library.json")
	assert_false(LibraryImporter.is_candidate(ROOT + "/nope.zip"))


func test_progress_counts_the_bytes_written() -> void:
	var plan := _plan_of(_entries())
	var progress := LibraryImporter.Progress.new()
	var staged := LibraryImporter.stage(plan, progress)
	assert_true(staged["ok"])
	assert_eq(progress.done, progress.total)
	assert_eq(progress.total, plan["total_bytes"])


func test_a_cancelled_stage_leaves_nothing_behind() -> void:
	var plan := _plan_of(_entries())
	var progress := LibraryImporter.Progress.new()
	progress.cancelled = true
	var staged := LibraryImporter.stage(plan, progress)
	assert_false(staged["ok"])
	assert_eq(DirAccess.get_directories_at(LibraryImporter.incoming_root()).size(), 0)


# ---- hostile archives ----


func test_zip_slip_and_absolute_paths_are_refused() -> void:
	var data := "{}"
	_refused(_extra(_entries(), {"name": "../evil.json", "data": data}), "evil.json")
	_refused(_extra(_entries(), {"name": "assets/../../evil.json", "data": data}), "evil.json")
	_refused(_extra(_entries(), {"name": "/etc/evil.json", "data": data}), "absolute")
	_refused(_extra(_entries(), {"name": "C:/Windows/evil.json", "data": data}), "absolute")
	_refused(_extra(_entries(), {"name": "C:evil.json", "data": data}), "absolute")
	_refused(_extra(_entries(), {"name": "a//b.json", "data": data}), "b.json")
	_refused(_extra(_entries(), {"name": "./x.json", "data": data}), "x.json")
	# Nothing outside the quarantine was written either.
	assert_false(FileAccess.file_exists(ROOT + "/evil.json"))
	assert_false(FileAccess.file_exists(ROOT + "/user/evil.json"))


func test_backslashes_are_refused() -> void:
	_refused(_extra(_entries(), {"name": "assets\\x.json", "data": "{}"}), "backslash")
	_refused(_extra(_entries(), {"name": "..\\x.json", "data": "{}"}), "backslash")


func test_a_zip_bomb_is_refused_by_ratio_before_anything_is_read() -> void:
	var bomb := {
		"name": "assets/big.png",
		"data": PackedByteArray([1, 2, 3]),
		"method": 8,
		"size": 40 * 1024 * 1024,
		"packed": 200,
	}
	var plan := _plan_of(_extra(_entries(), bomb))
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "expands more than"), str(plan["errors"]))
	assert_false(DirAccess.dir_exists_absolute(LibraryImporter.incoming_root()))


func test_a_total_expansion_over_the_archive_ratio_is_refused() -> void:
	var limits := LibraryImporter.limits
	limits["ratio"] = 2
	limits["json_bytes"] = 100 * 1024 * 1024
	var entries := _extra(_entries(), {"name": "notes.md", "data": "x".repeat(10)})
	var plan := _plan_of(entries)
	assert_true(plan["ok"], "normal files expand little: " + str(plan["errors"]))
	var bigger := {
		"name": "assets/more.json",
		"data": "y".repeat(10),
		"method": 8,
		"size": 60000,
		"packed": 3000
	}
	limits["ratio"] = 5
	plan = _plan_of(_extra(_entries(), bigger))
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "zip bomb"), str(plan["errors"]))


func test_too_many_entries_are_refused() -> void:
	LibraryImporter.limits["entries"] = 3
	var plan := _plan_of(_entries())
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "more than 3 files"), str(plan["errors"]))


func test_a_total_size_over_the_cap_is_refused() -> void:
	LibraryImporter.limits["uncompressed_bytes"] = 1000
	var plan := _plan_of(_entries())
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "expands to"), str(plan["errors"]))
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryImporter.limits["library_bytes"] = 1000
	plan = _plan_of(_entries())
	assert_true(_has_line(plan["errors"], "at most"), str(plan["errors"]))


func test_a_file_over_its_kind_s_cap_is_refused() -> void:
	LibraryImporter.limits["glb_bytes"] = 100
	var plan := _plan_of(_entries())
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "over the"), str(plan["errors"]))
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryImporter.limits["json_bytes"] = 50
	plan = _plan_of(_entries())
	assert_true(_has_line(plan["errors"], "library.json"), str(plan["errors"]))
	assert_eq(LibraryImporter.extension_cap("assets/catalog.json"), 4 * 1024 * 1024)
	assert_eq(LibraryImporter.extension_cap("x/y.glb"), 64 * 1024 * 1024)


func test_only_data_files_are_allowed() -> void:
	for bad in [
		"scripts/run.gd",
		"tool.exe",
		"lib.dll",
		"scene.tscn",
		"mat.tres",
		"pack.pck",
		"setup.bat",
		"Makefile",
		"page.html",
		"gltf/model.gltf",
	]:
		_refused(_extra(_entries(), {"name": bad, "data": "x"}), "not allowed")


func test_the_allowed_extensions_are_judged_without_regard_to_case() -> void:
	var plan := _plan_of(_extra(_entries(), {"name": "LICENSE.TXT", "data": "x"}))
	assert_true(plan["ok"], str(plan["errors"]))
	_refused(_extra(_entries(), {"name": "run.GD", "data": "x"}), "not allowed")


func test_a_symbolic_link_entry_is_refused() -> void:
	var link := {
		"name": "assets/link.json", "data": "../../secret", "host": 3, "external": SYMLINK_MODE
	}
	_refused(_extra(_entries(), link), "symbolic link")
	var reparse := {"name": "assets/point.json", "data": "x", "external": 0x400}
	_refused(_extra(_entries(), reparse), "link")
	var device := {"name": "assets/tty.json", "data": "", "host": 3, "external": 0x21B60000}
	_refused(_extra(_entries(), device), "not an ordinary file")


func test_a_regular_unix_file_mode_is_fine() -> void:
	var file := {"name": "notes.md", "data": "x", "host": 3, "external": 0x81A40000}
	assert_true(_plan_of(_extra(_entries(), file))["ok"])


func test_names_that_differ_only_by_case_are_refused() -> void:
	var one := {"name": "assets/tree/Oak.glb", "data": "a"}
	var two := {"name": "assets/tree/oak.glb", "data": "b"}
	var entries := _extra(_extra(_entries(), one), two)
	_refused(entries, "differ only by case")
	var again := _extra(_extra(_entries(), one), one)
	_refused(again, "appears twice")


func test_windows_device_names_and_odd_endings_are_refused() -> void:
	for bad in ["assets/con.glb", "aux.json", "assets/NUL.png", "prn.txt", "com1.md", "LPT3.json"]:
		_refused(_extra(_entries(), {"name": bad, "data": "x"}), "reserved device name")
	_refused(_extra(_entries(), {"name": "assets/x.png.", "data": "x"}), "ends with a dot")
	_refused(_extra(_entries(), {"name": "assets/x.png ", "data": "x"}), "ends with a dot")


func test_a_path_over_the_length_cap_is_refused() -> void:
	var long_name := "assets/" + "d".repeat(130) + ".json"
	_refused(_extra(_entries(), {"name": long_name, "data": "{}"}), "characters")
	var deep := "a/b/c/d/e/f/g/h/i/j/k.json"
	_refused(_extra(_entries(), {"name": deep, "data": "{}"}), "nested deeper")


func test_an_archive_without_a_library_json_is_refused() -> void:
	var entries: Array = _entries().filter(
		func(entry: Dictionary) -> bool: return entry["name"] != "library.json"
	)
	var plan := _plan_of(entries)
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "library.json"), str(plan["errors"]))
	var nested := _entries("one/")
	nested.append({"name": "two/library.json", "data": "{}"})
	assert_false(_plan_of(nested)["ok"], "two top folders: no library at the top")


func test_encrypted_and_unsupported_entries_are_refused() -> void:
	_refused(_extra(_entries(), {"name": "secret.md", "data": "x", "flags": 1}), "encrypted")
	_refused(_extra(_entries(), {"name": "odd.md", "data": "x", "method": 12}), "not supported")


func test_files_whose_sizes_disagree_are_refused() -> void:
	var lying := {"name": "notes.md", "data": "abc", "size": 10, "packed": 3}
	_refused(_extra(_entries(), lying), "sizes that disagree")


func test_a_truncated_or_unreadable_archive_is_refused() -> void:
	var good := Zip.build(_entries())
	var path := INBOX.path_join("cut.ttlib")
	for cut in [20, 40, good.size() / 2]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(good.slice(0, good.size() - cut))
		file.close()
		var plan := LibraryImporter.inspect(path)
		assert_false(plan["ok"], "cut %d bytes" % cut)
		assert_eq((plan["files"] as Array).size(), 0)
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("this is not a zip file at all")
	junk.close()
	assert_false(LibraryImporter.inspect(path)["ok"])
	FileAccess.open(path, FileAccess.WRITE).close()
	assert_false(LibraryImporter.inspect(path)["ok"], "an empty file")
	assert_false(LibraryImporter.inspect(INBOX.path_join("missing.ttlib"))["ok"])


func test_a_file_of_another_kind_is_refused() -> void:
	var path := INBOX.path_join("map.glb")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(Zip.build(_entries()))
	file.close()
	var plan := LibraryImporter.inspect(path)
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], ".ttlib"), str(plan["errors"]))


func test_a_damaged_entry_fails_the_stage_and_cleans_up() -> void:
	# The directory says 40 bytes, the entry holds 10: reading it cannot give the size claimed.
	var entries := _extra(
		_entries(), {"name": "notes.md", "data": "0123456789", "size": 40, "packed": 40}
	)
	var plan := _plan_of(entries)
	assert_true(plan["ok"], "inspection reads only the directory")
	var staged := LibraryImporter.stage(plan)
	assert_false(staged["ok"])
	assert_eq(DirAccess.get_directories_at(LibraryImporter.incoming_root()).size(), 0)


func test_junk_a_zip_tool_adds_is_left_out_not_extracted() -> void:
	var entries := _entries()
	entries.append({"name": "__MACOSX/._library.json", "data": "x"})
	entries.append({"name": ".DS_Store", "data": "x"})
	entries.append({"name": "assets/Thumbs.db", "data": "x"})
	entries.append({"name": ".git/config", "data": "x"})
	var plan := _plan_of(entries)
	assert_true(plan["ok"], str(plan["errors"]))
	assert_eq((plan["ignored"] as Array).size(), 4)
	var folder: String = _stage(plan)["folder"]
	assert_false(FileAccess.file_exists(folder + "/.DS_Store"))
	assert_false(DirAccess.dir_exists_absolute(folder + "/__MACOSX"))
	assert_false(DirAccess.dir_exists_absolute(folder + "/.git"))


func test_a_folder_with_a_link_or_a_bad_name_is_refused() -> void:
	var bad := ROOT + "/folderbad"
	World.write_alien(bad)
	World.write_text(bad + "/run.gd", "extends Node")
	var plan := LibraryImporter.inspect(bad)
	assert_false(plan["ok"])
	assert_true(_has_line(plan["errors"], "not allowed"), str(plan["errors"]))
	# A hidden .git folder is junk, not a refusal; a library nested too deep is.
	DirAccess.remove_absolute(bad + "/run.gd")
	World.write_text(bad + "/.git/config", "x")
	plan = LibraryImporter.inspect(bad)
	assert_true(plan["ok"], str(plan["errors"]))
	assert_true(".git" in plan["ignored"])
	World.write_text(bad + "/a/b/c/d/e/f/g/h/i/j.json", "{}")
	plan = LibraryImporter.inspect(bad)
	assert_false(plan["ok"])


# ---- reading what was staged ----


func test_a_library_that_does_not_read_is_described_with_its_errors() -> void:
	var entries: Array = _entries().filter(
		func(entry: Dictionary) -> bool: return entry["name"] != "assets/catalog.json"
	)
	var card := _card_of(entries)
	assert_false(card["can_install"])
	assert_gt((card["errors"] as Array).size(), 0)
	var broken := _entries().map(
		func(entry: Dictionary) -> Dictionary:
			if entry["name"] == "library.json":
				return {"name": "library.json", "data": "{not json"}
			return entry
	)
	assert_false(_card_of(broken)["can_install"])


func test_the_reserved_ids_are_refused() -> void:
	for id in ["core", "legacy", "draft", "dev"]:
		var entries := _entries().map(
			func(entry: Dictionary) -> Dictionary:
				if entry["name"] != "library.json":
					return entry
				var library: Dictionary = JSON.parse_string(
					(entry["data"] as PackedByteArray).get_string_from_utf8()
				)
				library["id"] = id
				return {"name": "library.json", "data": JSON.stringify(library)}
		)
		var card := _card_of(entries)
		assert_false(card["can_install"], id)
		assert_true(_has_line(card["errors"], "'%s'" % id) or _has_line(card["errors"], id), id)
	var as_core := _entries().map(
		func(entry: Dictionary) -> Dictionary:
			if entry["name"] != "library.json":
				return entry
			var library: Dictionary = JSON.parse_string(
				(entry["data"] as PackedByteArray).get_string_from_utf8()
			)
			library["id"] = "core"
			return {"name": "library.json", "data": JSON.stringify(library)}
	)
	var card := _card_of(as_core)
	assert_true(card["reserved"], "core is reserved")
	assert_false(card["can_install"])
	assert_true(_has_line(card["errors"], "belongs to the game"), str(card["errors"]))


func test_a_missing_or_unmet_dependency_is_a_warning_on_the_card() -> void:
	World.write_alien(SOURCE, "0.3.1", [{"id": "zzmissing", "version": "^1.0"}], false)
	var card := _card_of(_entries())
	var deps: Array = card["dependencies"]
	assert_eq(deps[0]["state"], LibraryInstall.DEP_MISSING)
	assert_true(_has_line(card["warnings"], "not installed"), str(card["warnings"]))
	World.write_alien(SOURCE, "0.3.1", [{"id": "core", "version": "^9.0"}], false)
	card = _card_of(_entries())
	assert_eq((card["dependencies"] as Array)[0]["state"], LibraryInstall.DEP_UNMET)
	assert_eq((card["dependencies"] as Array)[0]["installed"], "1.2.0")
	assert_true(_has_line(card["warnings"], "1.2.0 is installed"), str(card["warnings"]))


func test_a_disabled_dependency_is_reported() -> void:
	World.write_alien(SOURCE, "0.3.1", [{"id": "beta", "version": "*"}], false)
	(
		World
		. write_library(
			_paths["user"] + "/beta",
			{
				"format": "ttsim-library",
				"format_version": 1,
				"id": "beta",
				"name": "Beta",
				"version": "1.0.0",
				"contract": 1,
			},
			[{"id": "Rock_A", "category": "rock", "wind": "", "size": "small"}],
			{
				"format": "ttsim-biome",
				"format_version": 1,
				"id": "stony",
				"name": "Stony",
				"surfaces": "legacy",
				"seasons": [{"id": "summer", "seed": 1}],
				"ground": {"surface": "grass_alpine", "paths": []},
				"rules":
				[
					{
						"key": "r",
						"role": "stones",
						"density_per_m2": 0.1,
						"query": {"match": [{"ref": "Rock_A"}]}
					}
				],
			}
		)
	)
	LibraryRegistry.set_enabled("beta", false)
	var card := _card_of(_entries())
	assert_eq((card["dependencies"] as Array)[0]["state"], LibraryInstall.DEP_DISABLED)


# ---- installing, replacing, removing ----


func _install_once() -> Dictionary:
	var card := _card_of(_entries())
	var done := LibraryInstall.install(card)
	assert_true(done["ok"], str(done["error"]))
	return done


func test_an_id_clash_offers_replace_with_the_versions_compared() -> void:
	_install_once()
	LibraryRegistry.refresh()
	World.write_alien(SOURCE, "0.4.0")
	var card := _card_of(_entries())
	assert_true(card["can_install"])
	assert_eq(card["relation"], LibraryInstall.RELATION_NEWER)
	assert_eq(String(card["existing"]["version"]), "0.3.1")
	var refused := LibraryInstall.install(card)
	assert_false(refused["ok"], "no replacing without asking")
	assert_true(DirAccess.dir_exists_absolute(card["folder"]), "the staged files are kept")
	var done := LibraryInstall.install(card, true)
	assert_true(done["ok"], str(done["error"]))
	assert_true(done["replaced"])
	LibraryRegistry.refresh()
	assert_eq(LibraryRegistry.info("alienworld")["version"], "0.4.0")
	assert_eq(
		DirAccess.get_directories_at(LibraryImporter.incoming_root()).size(),
		0,
		"set-aside copy gone"
	)
	World.write_alien(SOURCE, "0.2.0")
	var older := _card_of(_entries())
	assert_eq(older["relation"], LibraryInstall.RELATION_OLDER)
	World.write_alien(SOURCE, "0.4.0")
	assert_eq(_card_of(_entries())["relation"], LibraryInstall.RELATION_SAME)


func test_a_library_with_the_id_of_an_official_one_is_refused() -> void:
	World.write_core(SOURCE.get_base_dir() + "/core")
	var card := _card_of(Zip.entries_of(SOURCE.get_base_dir() + "/core"))
	assert_false(card["can_install"])
	assert_true(card["reserved"])


func test_install_refuses_files_outside_the_quarantine_and_an_unchecked_card() -> void:
	var card := _card_of(_entries())
	var elsewhere := card.duplicate()
	elsewhere["folder"] = SOURCE
	assert_false(LibraryInstall.install(elsewhere)["ok"])
	var unchecked := card.duplicate()
	unchecked["can_install"] = false
	assert_false(LibraryInstall.install(unchecked)["ok"])
	var odd_id := card.duplicate()
	odd_id["id"] = "../escape"
	assert_false(LibraryInstall.install(odd_id)["ok"])
	assert_false(DirAccess.dir_exists_absolute(ROOT + "/escape"))


func test_discard_and_sweep_only_touch_the_quarantine() -> void:
	var staged := _stage(_plan_of(_entries()))
	LibraryImporter.discard(SOURCE)
	assert_true(DirAccess.dir_exists_absolute(SOURCE), "outside the quarantine: untouched")
	LibraryImporter.discard(staged["folder"])
	assert_false(DirAccess.dir_exists_absolute(staged["folder"]))
	var one := _stage(_plan_of(_entries()))
	var two := _stage(_plan_of(_entries()))
	assert_eq(LibraryImporter.sweep_incoming(one["folder"]), 1)
	assert_true(DirAccess.dir_exists_absolute(one["folder"]))
	assert_false(DirAccess.dir_exists_absolute(two["folder"]))


func test_the_quarantine_is_never_scanned_as_a_library() -> void:
	_stage(_plan_of(_entries()))
	LibraryRegistry.refresh()
	var ids: Array = LibraryRegistry.list().map(func(item: Dictionary) -> String: return item["id"])
	assert_false("alienworld" in ids, "a staged library is not served")
	assert_true(_paths["user"] + "/.incoming" == LibraryImporter.incoming_root())


func test_remove_deletes_a_user_library_and_refuses_everything_else() -> void:
	_install_once()
	LibraryRegistry.refresh()
	assert_eq(LibraryRegistry.info("alienworld")["source"], "user")
	var cached := SurfaceCache.root + "/alienworld/abcd1234/crystal_albedo.ttimg"
	World.write_text(cached, "x")
	var done := LibraryInstall.remove("alienworld")
	assert_true(done["ok"], str(done["error"]))
	assert_false(DirAccess.dir_exists_absolute(_paths["user"] + "/alienworld"))
	assert_false(FileAccess.file_exists(cached), "its baked surfaces go with it")
	assert_false(LibraryInstall.remove("alienworld")["ok"], "not installed any more")
	assert_false(LibraryInstall.remove("core")["ok"])
	assert_false(LibraryInstall.remove("../official")["ok"])
	assert_false(LibraryInstall.remove("")["ok"])
	assert_true(DirAccess.dir_exists_absolute(_paths["core"]), "the official library is untouched")


func test_levels_using_finds_the_maps_that_name_a_library() -> void:
	var levels := ROOT + "/levels"
	DirAccess.make_dir_recursive_absolute(levels + "/uses")
	DirAccess.make_dir_recursive_absolute(levels + "/plain")
	var doc := Fixtures.full_doc()
	doc.libraries = [{"id": "alienworld", "version": "0.3.1", "hash": "ab12cd34"}]
	var rows := PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	doc.scatter["alienworld__crystal_basin_summer_s1/Crystal_Spire_v0"] = rows
	assert_eq(MapDocumentIO.write(doc, levels + "/uses/map.ttmap"), OK)
	var plain := Fixtures.full_doc()
	assert_eq(MapDocumentIO.write(plain, levels + "/plain/map.ttmap"), OK)
	DirAccess.make_dir_recursive_absolute(levels + "/empty")
	assert_eq(LibraryInstall.levels_using("alienworld", levels), ["uses"])
	assert_eq(LibraryInstall.levels_using("nobody", levels), [])
	assert_eq(LibraryInstall.levels_using("alienworld", ROOT + "/none"), [])


func test_the_importer_loads_no_resource_and_runs_nothing() -> void:
	for path in [
		"res://utils/library/library_importer.gd",
		"res://utils/library/library_install.gd",
		"res://utils/library/library_names.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		for forbidden in [
			"load(",
			"preload(",
			"ResourceLoader",
			"OS.execute",
			"OS.create_process",
			"Engine.get_main_loop",
			"get_tree"
		]:
			assert_false(forbidden in _code_of(source), "%s uses %s" % [path.get_file(), forbidden])


func _code_of(source: String) -> String:
	var lines := PackedStringArray()
	for line in source.split("\n"):
		var at := line.find("#")
		lines.append(line if at < 0 else line.substr(0, at))
	return "\n".join(lines)


func test_a_partial_copy_from_the_host_is_said_not_replaced() -> void:
	World.write_alien(LibraryRegistry.received_root() + "/alienworld", "0.2.0", [], false)
	var card := _card_of(_entries())
	assert_true(card["can_install"], str(card["errors"]))
	assert_true(
		card["existing"].is_empty(), "nothing to replace: the received copy is not installed"
	)
	assert_eq(card["relation"], LibraryInstall.RELATION_NEW)
	assert_true(_has_line(card["warnings"], "came from the host"), str(card["warnings"]))
	var done := LibraryInstall.install(card)
	assert_true(done["ok"], str(done["error"]))
	assert_true(DirAccess.dir_exists_absolute(LibraryRegistry.received_root() + "/alienworld"))


func test_nothing_outside_the_user_folders_is_ever_deleted() -> void:
	# Pins the guard that stands between an empty or relative quarantine root and a deletion of
	# the working directory (a worktree was emptied that way on 2026-10-24).
	for bad in ["", "abc", ".incoming", "res://x/y/z", "C:/", "D:", "user://", "/", "../x/y/z/w/v"]:
		assert_false(LibraryImporter.is_safe_path(bad), "'%s' is not safe" % bad)
	for good in ["user://libraries/.incoming/ab12", "D:/dev/tabletop/scratch/x/y"]:
		assert_true(LibraryImporter.is_safe_path(good), good)
	var saved := LibraryRegistry.user_root
	LibraryRegistry.user_root = ""
	assert_eq(LibraryImporter.sweep_incoming(), 0, "no root, no sweep")
	var plan := _plan_of(_entries())
	var staged := LibraryImporter.stage(plan)
	assert_false(staged["ok"], "nowhere to stage")
	assert_false(LibraryImporter.is_quarantined(SOURCE))
	# A relative path that does not exist, never the project's own folders: if the guard were
	# broken this test must not be the one that deletes them.
	assert_false(LibraryImporter.remove_tree("zz_not_a_folder"))
	assert_push_error("refusing to delete")
	assert_false(
		LibraryInstall.install({"can_install": true, "id": "alienworld", "folder": SOURCE})["ok"]
	)
	LibraryRegistry.user_root = saved
	assert_true(DirAccess.dir_exists_absolute("res://scenes"), "the project is still there")
