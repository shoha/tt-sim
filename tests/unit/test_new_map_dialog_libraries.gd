extends GutTest

## The New map dialog's biome picker with content libraries (step S4): core's biomes keep their
## field, every other library that supplies a biome gets a field of its own headed by its name
## (alphabetical, its default biome first), one pick spans all the fields, and the dialog is
## unchanged while core is the only library.

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_new_map_dialog_libraries"
const SETTINGS := ROOT + "/settings.cfg"
const DIALOG_SCENE := "res://scenes/states/authoring/new_map_dialog.tscn"

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
	LibraryRegistry.official_root = ROOT + "/nowhere"
	LibraryRegistry.user_root = ROOT + "/nowhere_either"


## The dialog over the scratch palette root, with the libraries of the world served or not.
func _dialog(with_libraries: bool) -> NewMapDialog:
	if with_libraries:
		LibraryRegistry.official_root = _paths["official"]
		LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.apply(_paths["base"])
	var dialog: NewMapDialog = load(DIALOG_SCENE).instantiate()
	dialog.palette_root = _paths["base"]
	add_child_autofree(dialog)
	return dialog


func _tile_ids(field: TileField) -> Array:
	var ids: Array = []
	for tile in field.tiles.get_children():
		ids.append(String(tile.name))
	return ids


func test_with_core_alone_the_dialog_is_as_it_was() -> void:
	var dialog := _dialog(false)
	assert_eq(dialog.library_fields.size(), 0)
	assert_eq(_tile_ids(dialog.biome_field), ["forest_summer_s1", "meadow_summer_s1", "bare_ground"])
	assert_null(dialog.biome_field.note, "no library name beside the caption")
	assert_eq(dialog.biome_field.caption, "Start from")


func test_another_librarys_biomes_get_a_field_headed_by_its_name() -> void:
	var dialog := _dialog(true)
	assert_eq(dialog.library_fields.size(), 1)
	var field := dialog.library_fields[0]
	assert_eq(field.caption, "Alien World")
	assert_eq(_tile_ids(field), [World.ALIEN_RUNTIME])
	assert_eq(field.note.text, "v0.3.1 by Test Author")
	assert_eq(dialog.biome_field.note.text, "tt-sim Core", "core is named once there are two")
	assert_true(
		_tile_ids(dialog.biome_field).has("bare_ground"), "Bare ground stays in the first field"
	)
	var tile: Button = field.tiles.get_node(World.ALIEN_RUNTIME)
	assert_string_contains(tile.tooltip_text, "Alien World 0.3.1")
	assert_eq(tile.text, "Crystal Basin")
	assert_not_null(tile.icon, "the strip painted from the biome")
	var core_tile: Button = dialog.biome_field.tiles.get_node("forest_summer_s1")
	assert_eq(core_tile.tooltip_text, "Forest", "core's tooltips are unchanged")


func test_core_stays_first_and_libraries_follow_alphabetically() -> void:
	var zeta: String = _paths["user"] + "/zeta"
	var alpha: String = _paths["user"] + "/alpha"
	for item in [[zeta, "zeta", "Zeta Land"], [alpha, "alpha", "Alpha Land"]]:
		World.write_alien(item[0], "1.0.0", [{"id": "core", "version": "*"}], false)
		World.edit_json(
			item[0] + "/library.json",
			func(d: Dictionary) -> void:
				d["id"] = item[1]
				d["name"] = item[2]
		)
	var dialog := _dialog(true)
	var captions: Array = dialog.library_fields.map(func(f: TileField) -> String: return f.caption)
	assert_eq(captions, ["Alien World", "Alpha Land", "Zeta Land"])
	assert_lt(dialog.biome_field.get_index(), dialog.library_fields[0].get_index())
	assert_lt(dialog.library_fields[0].get_index(), dialog.library_fields[1].get_index())


func test_one_pick_spans_every_field() -> void:
	var dialog := _dialog(true)
	var field := dialog.library_fields[0]
	# A pick in the library's field.
	var tile: Button = field.tiles.get_node(World.ALIEN_RUNTIME)
	tile.button_pressed = true
	assert_eq(dialog.current_spec()["biome_id"], World.ALIEN_RUNTIME)
	for core_id in ["forest_summer_s1", "meadow_summer_s1", "bare_ground"]:
		var core_tile: Button = dialog.biome_field.tiles.get_node(core_id)
		assert_false(core_tile.button_pressed, "%s is not shown picked" % core_id)
	assert_true(tile.button_pressed)
	# Then a pick in core's: the library's tile lets go.
	var forest: Button = dialog.biome_field.tiles.get_node("forest_summer_s1")
	forest.button_pressed = true
	assert_eq(dialog.current_spec()["biome_id"], "forest_summer_s1")
	assert_false(tile.button_pressed)
	# Bare ground is the same kind of pick.
	dialog._on_biome_selected(NewMapDialog.BARE_TILE)
	assert_eq(dialog.current_spec()["biome_id"], NewMap.BARE_BIOME)
	assert_false(tile.button_pressed)
	# And back to the library's tile, which must fire again (it let go silently).
	tile.button_pressed = true
	assert_eq(dialog.current_spec()["biome_id"], World.ALIEN_RUNTIME)
	assert_eq(dialog.ground_caption.text, "Ground: grass")


func test_the_default_pick_is_the_games_default_not_a_librarys() -> void:
	var dialog := _dialog(true)
	assert_eq(LibraryBindings.default_biome(), "forest_summer_s1", "core's default_biome")
	assert_eq(dialog.biome_field.tiles.selected, &"forest_summer_s1")
	assert_eq(dialog.current_spec()["biome_id"], "forest_summer_s1")
	var alien_tile: Button = dialog.library_fields[0].tiles.get_node(World.ALIEN_RUNTIME)
	assert_false(alien_tile.button_pressed, "alienworld's own default does not take over")
