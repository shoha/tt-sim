extends RefCounted

## Render-job probe (`call` op) for the library title (jobs/library.json, cards library-title
## and library-title-fix): the title as the library, its detail strip, New map's Advanced
## popover, the import check and the Replace prompt. Nothing is written under the real library:
## the staged maps are infos with no folder on disk, and the thumbnails, the import and Replace
## files and the level they replace live under PROBE_ROOT, with LevelManager.levels_dir and
## ImportSources.path pointed there until `cleanup`. `action`:
## - `thumbs`: start rendering real thumbnails (THUMBS: the shipped Oak's Lab map.glb, and
##   maps made here from a seed and a landform) into PROBE_ROOT/thumbs/; `stage` uses those
##   written by then. `thumbs_status` says how many are done.
## - `stage`: the library shows STAGED (seven maps of every source, one Bundled, played and
##   edited over the last fortnight; Willow Green's source newer in Blender), each strip's
##   size and Blender check staged as well.
## - `select` (`name`): click that map's card, as a player's click does (the grid scrolls the
##   row and its strip into view).
## - `menu` (`open`): the strip's "..." menu open or closed.
## - `advanced` (`width`, `depth`, `open`): New map's Advanced open on a custom size, or closed.
## - `import`: write a 150 x 100 ft map.glb whose ground floats 1.5 m above Y = 0 and open the
##   import check on it (one warning).
## - `replace`: a level edited with a prop near its far corner, and the Replace prompt for a
##   smaller map dropped on its card (keeping the edits removes the prop).
## - `close_panel`: close the open check.
## - `empty`: a first run: only the Bundled map, New map alone and larger over it.
## - `focus` (`target`: "card" or "name"): the keyboard focus on Willow Green's card, or in the
##   strip's name field.
## - `hover` (`target`: "card" or "description"): the pointer over Lantern Bay's card, or over
##   the strip's description field.
## - `delete`: Delete's confirm for the selected map; `cancel` closes it with Escape.
## - `cleanup`: close any check, delete PROBE_ROOT, put the paths back and show the real library.

const PROBE_ROOT := "user://_library_title_probe/"
const THUMB_DIR := PROBE_ROOT + "thumbs/"
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
## Real thumbnails: the staged map's name, then the shipped GLB, or a biome, landform and seed
## made here. The rest keep their painted placeholders, as a map with no picture yet does.
const THUMBS := [
	["Willow Green", "res://assets/models/maps/oakslabpainted.glb"],
	["Hayfield Rise", "grassland_meadow_summer_s1", "hilltop", 4],
	["Violet Fen", "temperate_forest_summer_s1", "lakeshore", 3],
	["Moonwell", "birch_woodland_summer_s1", "valley", 2],
]


static func run(base: Node, step: Dictionary) -> String:
	var title := base.get("_title_screen") as TitleScreen
	if title == null:
		return "no title"
	match String(step.get("action", "")):
		"thumbs":
			_render_thumbs(base.get_tree())
			return "rendering %d thumbnails into %s" % [THUMBS.size(), THUMB_DIR]
		"thumbs_status":
			return "%d of %d thumbnails written" % [_thumbs_done(), THUMBS.size()]
		"stage":
			return _stage(title)
		"select":
			return _select(title, String(step.get("name", "")))
		"menu":
			if bool(step.get("open", true)):
				title.strip.open_menu()
			else:
				title.strip.menu.hide()
			return "menu %s at %s" % [title.strip.menu.visible, title.strip.menu.position]
		"advanced":
			return _advanced(title, step)
		"import":
			return _import(title)
		"replace":
			return _replace(title)
		"close_panel":
			return _close_panel(title)
		"empty":
			return _empty(title)
		"focus":
			return _focus(title, String(step.get("target", "card")))
		"hover":
			return _hover(base, title, String(step.get("target", "card")))
		"delete":
			title._on_strip_action(title.strip.info, MapDetailStrip.ACTION_DELETE)
			return "delete confirm for %s" % title.strip.info.get("name", "")
		"cancel":
			for pressed in [true, false]:
				var escape := InputEventAction.new()
				escape.action = "ui_cancel"
				escape.pressed = pressed
				Input.parse_input_event(escape)
			return "escape"
		"cleanup":
			return _cleanup(title)
	return "unknown action %s" % step.get("action", "")


static func _folder_of(map_name: String) -> String:
	return "_library_title_" + map_name.to_snake_case()


static func _thumbs_done() -> int:
	var done := 0
	for entry: Array in THUMBS:
		if FileAccess.file_exists(THUMB_DIR + _folder_of(entry[0]) + ".png"):
			done += 1
	return done


## Renders THUMBS one after another (a coroutine: the job's next steps run meanwhile).
static func _render_thumbs(tree: SceneTree) -> void:
	DirAccess.make_dir_recursive_absolute(THUMB_DIR)
	for entry: Array in THUMBS:
		var image: Image = null
		if entry.size() == 2:
			image = await LevelThumbnail.render_glb_async(String(entry[1]), tree)
		else:
			var doc := NewMap.create(100, entry[1], int(entry[3]), PaletteLibrary.DEFAULT_ROOT, entry[2])
			if doc != null:
				var root := await MapSourceLoader.new(tree).build_async("", doc)
				if root != null:
					image = await LevelThumbnail.render_scene_async(root, tree)
		if image != null:
			image.save_png(THUMB_DIR + _folder_of(entry[0]) + ".png")


static func _stage(title: TitleScreen) -> String:
	var now := int(Time.get_unix_time_from_system())
	var levels: Array[Dictionary] = []
	var sizes := {}
	for sample: Array in STAGED:
		var folder := _folder_of(sample[0])
		var words: Array = DESCRIPTIONS.get(sample[0], ["", ""])
		var thumb := THUMB_DIR + folder + ".png"
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
				"thumbnail": thumb if FileAccess.file_exists(thumb) else "",
				"map_path": sample[2],
				"map_document": sample[3],
				LibraryFacts.UPDATED_KEY: folder.ends_with("willow_green"),
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
	return "staged %d maps (%d with real thumbnails), %s selected" % [
		title.grid.card_count(), _thumbs_done(), title.selected_level().get("name", "none")
	]


static func _card(title: TitleScreen, map_name: String) -> LevelCard:
	for card: LevelCard in title.grid._cards:
		if card.level_info.get("name", "") == map_name:
			return card
	return null


static func _select(title: TitleScreen, map_name: String) -> String:
	var card := _card(title, map_name)
	if card == null:
		return "no card %s (stage first)" % map_name
	card._on_pressed()
	var strip := title.strip
	return "selected %s: %s, %s, %s, %s; grid scrolled to %d" % [
		map_name,
		strip.source_label.text,
		strip.size_label.text,
		strip.tokens_label.text,
		strip.played_label.text,
		title.grid.scroll_vertical,
	]


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
		card.size_field.tiles.select(NewMapCard.SIZE_ANY)
		card._on_size_selected(NewMapCard.SIZE_ANY)
	return "advanced %s: %s; generate %s" % [
		open, card.size_line.text, "waits" if card.generate_button.disabled else "ready"
	]


static func _empty(title: TitleScreen) -> String:
	var shipped: Array[Dictionary] = []
	for info: Dictionary in title.grid.provider.call():
		if LibraryFacts.is_bundled(info):
			shipped.append(info)
	title.grid.provider = func() -> Array[Dictionary]: return shipped
	title.grid.refresh()
	title._refresh_actions()
	return "first run: %d Bundled, New map alone %s, %s selected" % [
		title.grid.card_count(),
		title.new_map_card.is_empty_library(),
		title.selected_level().get("name", "none"),
	]


static func _focus(title: TitleScreen, target: String) -> String:
	if target == "name":
		title.strip.name_edit.grab_focus()
		return "focus in the strip's name"
	var card := _card(title, "Willow Green")
	if card == null:
		return "no card"
	card.grab_focus()
	return "focus on Willow Green's card"


static func _hover(base: Node, title: TitleScreen, target: String) -> String:
	var control: Control = title.strip.description_edit
	if target == "card":
		control = _card(title, "Lantern Bay")
	if control == null:
		return "nothing to hover"
	var point := control.get_global_rect().get_center()
	base.get_viewport().warp_mouse(point)
	control.mouse_entered.emit()
	return "pointer over %s at %s" % [control.name, point]


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
	title.new_map_card.set_advanced(false)
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
