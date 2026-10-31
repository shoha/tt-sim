extends GutTest

## The Licences page's data file (data/third_party.json) against what the repository says it
## ships: every item THIRD_PARTY_LICENSES.md names has an entry, every notice file exists and
## reaches the export, every addon folder is either listed or left out of the export, and the
## engine's own notices are non-empty.

const MD_PATH := "res://THIRD_PARTY_LICENSES.md"
const PRESETS_PATH := "res://export_presets.cfg"
## The headings of THIRD_PARTY_LICENSES.md whose tables name one item per row; any other heading
## is itself the name of one item.
const TABLE_HEADINGS: Array[String] = ["Fonts", "Vendored addons", "Native scatter library"]
## Headings that are not an item at all.
const NOTE_HEADINGS: Array[String] = ["Licences page"]


func test_the_data_file_parses_and_every_entry_is_complete() -> void:
	var entries := LicenceCatalog.raw_entries()
	assert_gt(entries.size(), 8, "the data file lists the shipped items")
	var ids := {}
	for entry in entries:
		var id := str(entry.get("id", ""))
		assert_ne(id, "", "an entry has an id")
		assert_false(ids.has(id), "id %s is unique" % id)
		ids[id] = true
		for key in ["group", "name", "what", "licence"]:
			assert_ne(str(entry.get(key, "")), "", "%s has %s" % [id, key])
		var inline := str(entry.get("text", "")) != ""
		var from_file := str(entry.get("text_path", "")) != ""
		assert_true(inline != from_file, "%s has its text inline or in a file, not both" % id)


func test_every_text_path_exists_and_has_text() -> void:
	for entry in LicenceCatalog.shipped_entries():
		assert_ne(entry["text"], "", "%s has a notice" % entry["id"])
		assert_ne(entry["text"], LicenceCatalog.MISSING_TEXT, "%s: its text file reads" % entry["id"])
	for entry in LicenceCatalog.raw_entries():
		var path := str(entry.get("text_path", ""))
		if path != "":
			assert_true(FileAccess.file_exists(path), "%s exists" % path)


func test_every_item_the_markdown_names_has_an_entry() -> void:
	var covered := {}
	for entry in LicenceCatalog.raw_entries():
		for item in entry.get("covers", []):
			covered[str(item)] = true
	for record in LicenceCatalog.not_shipped():
		covered[str(record.get("name", ""))] = true
	var names := _markdown_names()
	assert_gt(names.size(), 10, "the markdown parses into item names")
	for item in names:
		assert_true(covered.has(item), "THIRD_PARTY_LICENSES.md names %s: add it to the data file" % item)


func test_no_entry_covers_a_name_the_markdown_dropped() -> void:
	var names := _markdown_names()
	for entry in LicenceCatalog.raw_entries():
		for item in entry.get("covers", []):
			assert_true(names.has(str(item)), "%s: %s is not in the markdown" % [entry["id"], item])


func test_every_addon_folder_is_listed_or_left_out_of_the_export() -> void:
	var accounted := {}
	for entry in LicenceCatalog.raw_entries():
		for path in entry.get("paths", []):
			accounted[str(path)] = true
	for record in LicenceCatalog.not_shipped():
		accounted[str(record.get("path", ""))] = true
	var dir := DirAccess.open("res://addons")
	assert_not_null(dir)
	for folder in dir.get_directories():
		assert_true(accounted.has("addons/" + folder), "addons/%s has no entry in the data file" % folder)


func test_the_addons_left_out_are_excluded_in_every_preset_and_the_listed_ones_are_not() -> void:
	var presets := _presets()
	assert_gt(presets.size(), 0)
	for preset in presets:
		var excludes: String = preset["exclude_filter"]
		for record in LicenceCatalog.not_shipped():
			var path := str(record["path"])
			assert_true(
				excludes.contains(path + "/*"), "%s is excluded from %s" % [path, preset["name"]]
			)
		for entry in LicenceCatalog.raw_entries():
			for path in entry.get("paths", []):
				assert_false(
					excludes.contains(str(path) + "/*"),
					"%s ships in %s, so it is listed" % [path, preset["name"]]
				)


func test_every_notice_file_reaches_the_export() -> void:
	for preset in _presets():
		var filters := _filters(preset["include_filter"])
		var excludes := _filters(preset["exclude_filter"])
		for entry in LicenceCatalog.raw_entries():
			var path := str(entry.get("text_path", ""))
			if path == "":
				continue
			var relative := path.trim_prefix("res://")
			var imported := FileAccess.file_exists(path + ".import")
			assert_true(
				imported or _matches_any(relative, filters),
				"%s: %s is neither imported nor in include_filter" % [preset["name"], relative]
			)
			assert_false(
				_matches_any(relative, excludes),
				"%s: %s is excluded from the export" % [preset["name"], relative]
			)


func test_the_engine_supplies_its_notices() -> void:
	var engine := LicenceCatalog.engine_entries()
	assert_eq(engine.size(), 3)
	for entry in engine:
		assert_eq(entry["group"], LicenceCatalog.GROUP_ENGINE)
		assert_ne(str(entry["text"]).strip_edges(), "", "%s has text" % entry["id"])
	assert_string_contains(engine[0]["text"], "Permission is hereby granted")


func test_components_text_names_each_component_and_licence() -> void:
	var info: Array[Dictionary] = [
		{
			"name": "ThingLib",
			"parts":
			[{"files": ["a.c"], "copyright": ["2020 Someone", "2021 Another"], "license": "Zlib"}]
		}
	]
	var text := LicenceCatalog.components_text(info)
	assert_string_contains(text, "ThingLib")
	assert_string_contains(text, "Copyright 2021 Another")
	assert_string_contains(text, "Licence: Zlib")
	assert_false(text.contains("a.c"), "file lists are left out")


func test_reflow_joins_wrapped_lines_and_keeps_the_structure() -> void:
	var notice := LicenceCatalog.reflow("Copyright 1\nCopyright 2\ntext\nmore")
	assert_eq(notice, "Copyright 1\nCopyright 2 text more")
	var wrapped := "one\ntwo\n\n- item a\n  more\n- item b\n\nPREAMBLE\nThe goals\nof it."
	var expected := "one two\n\n- item a more\n- item b\n\nPREAMBLE\nThe goals of it."
	assert_eq(LicenceCatalog.reflow(wrapped), expected)
	assert_eq(LicenceCatalog.reflow("# Licence\n\nsee `core`\nhere"), "Licence\n\nsee core here")
	var mit := "AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED\nSOFTWARE."
	assert_eq(LicenceCatalog.reflow(mit), mit.replace("\n", " "), "a capitals paragraph joins")


func test_licence_texts_are_sorted_under_their_ids() -> void:
	var text := LicenceCatalog.licence_texts({"MIT": "mit text", "Apache-2.0": "apache text"})
	assert_true(text.find("Apache-2.0") < text.find("MIT"))
	assert_string_contains(text, "mit text")


## The names THIRD_PARTY_LICENSES.md gives the items: a heading without a table is one item (its
## title without the folder in brackets), a table heading names its rows (the first cell, up to
## the first ", " or " (").
func _markdown_names() -> Dictionary:
	var names := {}
	var heading := ""
	for line in FileAccess.get_file_as_string(MD_PATH).split("\n"):
		var text := line.strip_edges()
		if text.begins_with("## "):
			heading = text.trim_prefix("## ")
			var title := heading.split(" (")[0]
			heading = title
			if not TABLE_HEADINGS.has(title) and not NOTE_HEADINGS.has(title):
				names[title] = true
		elif TABLE_HEADINGS.has(heading) and text.begins_with("|"):
			var cell := text.split("|")[1].strip_edges().replace("`", "")
			if cell == "" or cell.begins_with("-") or cell in ["Addon", "File", "Source"]:
				continue
			names[cell.split(", ")[0].split(" (")[0]] = true
	return names


## The export presets as {name, include_filter, exclude_filter}.
func _presets() -> Array[Dictionary]:
	var config := ConfigFile.new()
	assert_eq(config.load(PRESETS_PATH), OK)
	var out: Array[Dictionary] = []
	for section in config.get_sections():
		if section.ends_with(".options"):
			continue
		out.append(
			{
				"name": str(config.get_value(section, "name", section)),
				"include_filter": str(config.get_value(section, "include_filter", "")),
				"exclude_filter": str(config.get_value(section, "exclude_filter", "")),
			}
		)
	return out


func _filters(list: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in list.split(","):
		var pattern := part.strip_edges()
		if pattern != "":
			out.append(pattern)
	return out


func _matches_any(path: String, patterns: PackedStringArray) -> bool:
	for pattern in patterns:
		if path.match(pattern):
			return true
	return false
