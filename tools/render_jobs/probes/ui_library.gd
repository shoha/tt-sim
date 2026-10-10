extends RefCounted

## Render-job probe (`call` op) for the library title (jobs/library.json, card library-title):
## the title as the library, its detail strip, New map's Advanced, the import check and the
## Replace prompt. Nothing is written under the real library: the staged maps are infos with
## no folder on disk, and the import and Replace files and the level they replace live under
## PROBE_ROOT, with LevelManager.levels_dir and ImportSources.path pointed there until
## `cleanup`. `action`:
## - `stage`: the library shows STAGED (seven maps of every source, one Bundled, played and
##   edited over the last fortnight), each strip's size and Blender check staged as well.
## - `select` (`name`): click that map's card, as a player's click does.
## - `menu` (`open`): the strip's "..." menu open or closed.
## - `advanced` (`width`, `depth`, `open`): New map's Advanced open on a custom size, or closed.
## - `import`: write a 150 x 100 ft map.glb whose ground floats 1.5 m above Y = 0 and open the
##   import check on it (one warning).
## - `replace`: a level dressed with a prop near its far corner, and the Replace prompt for a
##   smaller map dropped on its card (Keep dressing drops the prop).
## - `close_panel`: close the open check.
## - `empty`: the library empty.
## - `cleanup`: close any check, delete PROBE_ROOT, put the paths back and show the real library.

const PROBE_ROOT := "user://_library_title_probe/"
const DAY_S := 86400
## Name, preset, map_path, map_document, days since played (-1 never), days since edited,
## tokens, footprint in feet.
const STAGED := [
	["Willow Green", "forest", "map.glb", "map.ttmap", 1, 6, 4, Vector2(150, 100)],
	["Hayfield Rise", "outdoor_day", "", "map.ttmap", 3, 3, 0, Vector2(200, 200)],
	["Lantern Bay", "outdoor_sunset", "map.glb", "", -1, 4, 6, Vector2(120, 90)],
	["Violet Fen", "ethereal", "", "map.ttmap", 7, 9, 2, Vector2(150, 150)],
	["Misty Tarn", "outdoor_overcast", "map.glb", "", 10, 12, 1, Vector2(100, 100)],
	["Moonwell", "outdoor_night", "", "map.ttmap", 12, 14, 3, Vector2(300, 120)],
	["Old Mill", "", "res://maps/old_mill.glb", "", -1, 30, 5, Vector2(100, 100)],
]
const DESCRIPTIONS := {
	"Willow Green": ["A ford under old willows, where the road meets the river", "Hannah"],
	"Violet Fen": ["Reed beds and a sunken causeway at dusk", ""],
}


static func run(base: Node, step: Dictionary) -> String:
	var title := base.get("_title_screen") as TitleScreen
	if title == null:
		return "no title"
	match String(step.get("action", "")):
		"stage":
			return _stage(title)
		"select":
			return _select(title, String(step.get("name", "")))
		"menu":
			if bool(step.get("open", true)):
				title.strip.more_button.show_popup()
			else:
				title.strip.more_button.get_popup().hide()
			return "menu %s" % title.strip.more_button.get_popup().visible
		"advanced":
			return _advanced(title, step)
		"import":
			return _import(title)
		"replace":
			return _replace(title)
		"close_panel":
			return _close_panel(title)
		"empty":
			title.grid.provider = func() -> Array[Dictionary]: return []
			title.grid.refresh()
			return "empty: %d cards, New map alone %s" % [
				title.grid.card_count(), title.new_map_card.is_empty_library()
			]
		"cleanup":
			return _cleanup(title)
	return "unknown action %s" % step.get("action", "")


static func _stage(title: TitleScreen) -> String:
	var now := int(Time.get_unix_time_from_system())
	var levels: Array[Dictionary] = []
	var sizes := {}
	for sample: Array in STAGED:
		var folder := "_library_title_" + String(sample[0]).to_snake_case()
		var words: Array = DESCRIPTIONS.get(sample[0], ["", ""])
		levels.append(
			{
				"path": "user://levels/%s/" % folder,
				"folder": folder,
				"is_folder_based": true,
				"name": sample[0],
				"description": words[0],
				"author": words[1],
				"token_count": sample[6],
				"modified_at": now - int(sample[5]) * DAY_S,
				"played_at": now - int(sample[4]) * DAY_S if int(sample[4]) >= 0 else 0,
				"environment_preset": sample[1],
				"thumbnail": "",
				"map_path": sample[2],
				"map_document": sample[3],
			}
		)
		sizes[folder] = sample[7]
	var ordered := LibraryFacts.ordered(levels, {})
	title.strip.footprint = func(info: Dictionary) -> Vector2:
		return sizes.get(info.folder, Vector2.ZERO)
	title.strip.is_updated = func(folder: String) -> bool: return folder.ends_with("willow_green")
	title.grid.provider = func() -> Array[Dictionary]: return ordered
	title.grid.refresh()
	title._preselect_most_recent()
	title._refresh_actions()
	return "staged %d maps, %s selected" % [title.grid.card_count(), title.selected_level().name]


static func _select(title: TitleScreen, map_name: String) -> String:
	for card: LevelCard in title.grid._cards:
		if card.level_info.get("name", "") == map_name:
			card._on_pressed()
			var strip := title.strip
			return "selected %s: %s, %s, %s, %s; strip at flow index %d" % [
				map_name,
				strip.source_label.text,
				strip.size_label.text,
				strip.tokens_label.text,
				strip.played_label.text,
				strip.get_index(),
			]
	return "no card %s (stage first)" % map_name


static func _advanced(title: TitleScreen, step: Dictionary) -> String:
	var card := title.new_map_card
	var open := bool(step.get("open", true))
	card.set_advanced(open)
	if open:
		card.size_field.tiles.select(NewMapCard.SIZE_CUSTOM)
		card._on_size_selected(NewMapCard.SIZE_CUSTOM)
		card.width_box.value = float(step.get("width", 300))
		card.depth_box.value = float(step.get("depth", 120))
		card.seed_edit.text = String(step.get("seed", ""))
	else:
		card.size_field.tiles.select(NewMapCard.SIZE_DRAWN)
		card._on_size_selected(NewMapCard.SIZE_DRAWN)
	return "advanced %s: %s; generate %s" % [
		open, card.size_line.text, "waits" if card.generate_button.disabled else "ready"
	]


static func _paths() -> void:
	DirAccess.make_dir_recursive_absolute(PROBE_ROOT + "levels/")
	DirAccess.make_dir_recursive_absolute(PROBE_ROOT + "blender/harbour/")
	if not LevelManager.levels_dir.begins_with(PROBE_ROOT):
		Engine.set_meta(&"library_probe_paths", [LevelManager.levels_dir, ImportSources.path])
	LevelManager.levels_dir = PROBE_ROOT + "levels/"
	ImportSources.path = PROBE_ROOT + "import_sources.cfg"


static func _fixture() -> GDScript:
	return load("res://tests/unit/glb_fixtures.gd") as GDScript


static func _import(title: TitleScreen) -> String:
	_paths()
	var path := PROBE_ROOT + "blender/harbour/map.glb"
	var err: Error = _fixture().call("write_map", path, Vector2(45.72, 30.48), 2.0)
	var panel := title.imports.check_import(path)
	if panel == null:
		return "no panel (written %s)" % error_string(err)
	return "import check: %d warnings, %s" % [
		(panel.report.warnings as Array).size(), panel.confirm_button.text
	]


static func _replace(title: TitleScreen) -> String:
	_paths()
	var source := PROBE_ROOT + "blender/harbour/map.glb"
	_fixture().call("write_map", source, Vector2(40.0, 40.0))
	var made := MapImport.write_import(source, "Harbour")
	if not made.ok:
		return "no level: %s" % made.error
	var folder := String(made.folder)
	var bounds := AABB(Vector3(-20, 0, -20), Vector3(40, 1, 40))
	var doc := NewMap.create_dressing(bounds, 3)
	var rock := "birch_woodland_summer_s1/Rock_Small"
	doc.props = {
		rock:
		PackedFloat32Array([18, 0, 18, 0, 0, 0, 1, 1, 1, 1, 2, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	}
	MapDocumentIO.write(doc, LevelManager.map_document_path(folder))
	var level := LevelManager.load_level_folder(folder, false)
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	LevelManager.save_level_folder(level, folder)
	LevelManager.current_level = null
	LevelManager.current_level_path = ""
	var smaller := PROBE_ROOT + "blender/harbour/harbour_v2.glb"
	_fixture().call("write_map", smaller, Vector2(30.0, 30.0))
	var panel := title.imports.drop(PackedStringArray([smaller]), folder)
	if panel == null:
		return "no panel"
	return "replace prompt: %s / %s; %s" % [
		panel.confirm_button.text,
		panel.fresh_button.text if panel.fresh_button else "-",
		panel.choice_line.text,
	]


static func _close_panel(title: TitleScreen) -> String:
	var panel := title.imports.panel
	if is_instance_valid(panel):
		panel._on_cancel_pressed()
		return "closed"
	return "no panel"


static func _cleanup(title: TitleScreen) -> String:
	_close_panel(title)
	var held: Array = Engine.get_meta(&"library_probe_paths", [])
	if not held.is_empty():
		LevelManager.levels_dir = held[0]
		ImportSources.path = held[1]
		Engine.remove_meta(&"library_probe_paths")
	_remove_tree(PROBE_ROOT)
	title.strip.footprint = LibraryFacts.footprint_ft
	title.strip.is_updated = MapImport.is_updated_in_blender
	title.grid.provider = title.library
	title.grid.refresh()
	title._preselect_most_recent()
	title._refresh_actions()
	return "cleaned %s; real library, %d maps" % [PROBE_ROOT, title.grid.card_count()]


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path + sub + "/")
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + file_name)
	DirAccess.remove_absolute(path.trim_suffix("/"))
