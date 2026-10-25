extends GutTest

## The collections manager (step S6): the title's Collections tool opens it, its list shows every
## library with its badge and switch (core always on), the card of the selected one carries
## Verify, Show in folder and Remove (a library the player installed only), an import goes through
## the install card (new, Replace, refused) and a drop on the title or the manager starts one,
## and the New map dialog hears of every change. The world is written at test time under a scratch
## folder (library_world.gd): `core` official 1.2.0, `alienworld` user 0.3.1. Imports run the real
## flow, thread included, over generated zips (zip_builder.gd).

const World := preload("res://tests/unit/library_world.gd")
const Zip := preload("res://tests/unit/zip_builder.gd")
const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const NEW_MAP_SCENE := preload("res://scenes/states/authoring/new_map_dialog.tscn")
const ROOT := "user://test_library_manager"
const SETTINGS := ROOT + "/settings.cfg"
const SOURCE := ROOT + "/source/alienworld"
const INBOX := ROOT + "/inbox"
const CANVAS := Vector2(1280.0, 720.0)
const TIMEOUT_S := 10.0
## Files the manager and the importer may not hold a literal of the display word in.
const WORDED_FILES: Array[String] = [
	"res://scenes/ui/library_manager/library_manager.gd",
	"res://scenes/ui/library_manager/library_detail.gd",
	"res://scenes/ui/library_manager/library_install_card.gd",
	"res://scenes/ui/library_manager/library_import_flow.gd",
	"res://utils/library/library_importer.gd",
	"res://utils/library/library_install.gd",
	"res://utils/library/library_verify.gd",
	"res://scenes/states/title_screen/title_screen.gd",
	"res://scenes/states/authoring/new_map_dialog.gd",
	"res://scenes/ui/library_transfer_ui.gd",
	"res://utils/library/library_transfer_consent.gd",
	"res://scenes/ui/library_manager/library_cache_section.gd",
	"res://utils/library/library_from_host.gd",
	"res://utils/library/library_transfer_install.gd",
]

var _paths: Dictionary = {}
var _saved: Dictionary = {}
var _levels: Array[Dictionary] = []
var _host: SubViewport
var _scene: Node
var _old_scene: Node


func before_all() -> void:
	_saved = {
		"settings": LibraryRegistry.settings_path,
		"official": LibraryRegistry.official_root,
		"user": LibraryRegistry.user_root,
		"levels": LevelManager.levels_dir,
	}


func after_all() -> void:
	LibraryRegistry.settings_path = _saved["settings"]
	LibraryRegistry.official_root = _saved["official"]
	LibraryRegistry.user_root = _saved["user"]
	LevelManager.levels_dir = _saved["levels"]
	LibraryImportFlow.serve_palette = true
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	# The library under test starts outside every scanned root; a test installs it when it needs it.
	World.remove_tree(_paths["alien"])
	World.write_alien(SOURCE, "0.3.1", [], false)
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryImportFlow.serve_palette = false
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = SETTINGS
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	LevelManager.levels_dir = ROOT + "/levels/"
	DirAccess.make_dir_recursive_absolute(INBOX)
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "LibraryManagerTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_host = SubViewport.new()
	_host.size = Vector2i(CANVAS)
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_scene.add_child(_host)


func after_each() -> void:
	for panel in get_tree().root.find_children("*", "AnimatedCanvasLayerPanel", true, false):
		var backdrop := panel.get_node_or_null("ColorRect")
		if backdrop != null:
			UIManager.unregister_overlay(backdrop as Control)
	for node in get_tree().root.get_children():
		if node is LibraryInstallCard or node is LibraryManager or node is ConfirmationDialogUI:
			node.free()
	get_tree().current_scene = _old_scene
	_scene.queue_free()
	EventBus.foliage_library_changed.emit("")


# ---- helpers ----


func _manager() -> LibraryManager:
	var manager := LibraryManager.new()
	manager.palette_root = _paths["base"]
	_host.add_child(manager)
	return manager


func _zip(entries: Array, file_name: String = "pack.ttlib") -> String:
	var path := INBOX.path_join(file_name)
	Zip.write(path, entries)
	return path


func _install_alien() -> void:
	DirAccess.rename_absolute(SOURCE, _paths["alien"])
	World.write_alien(SOURCE, "0.3.1", [], false)


## Serves the libraries over a fresh palette, as FoliageLibrary.refresh_libraries does.
func _serve() -> void:
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(_paths["base"])


func _settle() -> void:
	await wait_process_frames(2)
	for tween in get_tree().get_processed_tweens():
		tween.custom_step(3.0)
	await wait_process_frames(2)


func _has(lines: Array, needle: String) -> bool:
	return lines.any(func(line: String) -> bool: return needle in line)


func _card_of(flow: LibraryImportFlow) -> LibraryInstallCard:
	await wait_until(
		func() -> bool: return is_instance_valid(flow.panel) and flow.panel.cancel_button != null,
		TIMEOUT_S,
		"the install card opened"
	)
	return flow.panel


func _ready_card(flow: LibraryImportFlow) -> LibraryInstallCard:
	var panel := await _card_of(flow)
	await wait_until(
		func() -> bool: return panel.progress_bar == null, TIMEOUT_S, "the file was read"
	)
	return panel


# ---- the list ----


func test_the_list_shows_every_library_with_its_badge_and_switch() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	assert_not_null(manager.row_of("core"))
	assert_not_null(manager.row_of("alienworld"))
	assert_eq(manager.list_box.get_child_count(), 2)
	var alien := manager.row_of("alienworld")
	assert_eq((alien.get_node("Inner/Text/Name") as Label).text, "Alien World")
	assert_eq((alien.get_node("Inner/Text/Caption") as Label).text, "v0.3.1 by Test Author")
	var facts := (alien.get_node("Inner/Text/Facts") as Label).text
	assert_true(facts.begins_with("2 assets, 1 biome · "), facts)
	assert_eq((alien.get_node("Inner/Origin/Label") as Label).text, "Yours")
	var core := manager.row_of("core")
	assert_eq((core.get_node("Inner/Origin/Label") as Label).text, LibraryDetail.BADGE_BUILTIN)
	assert_eq(LibraryDetail.BADGE_BUILTIN, "Built in")
	assert_true(manager.toggle_of("core").disabled, "core cannot be turned off")
	assert_true(manager.toggle_of("core").button_pressed)
	assert_false(manager.toggle_of("alienworld").disabled)
	assert_true(manager.toggle_of("alienworld").button_pressed)
	assert_eq(manager.selected_id, "core", "the first one is selected")


func test_the_selected_library_has_a_card_and_only_a_users_can_be_removed() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	var detail := manager.detail
	assert_eq(detail.heading.text, "Alien World")
	assert_true(detail.remove_button.visible)
	assert_true(detail.folder_button.visible)
	assert_eq(detail.get_node("Subtitle").text, "v0.3.1 by Test Author · CC0-1.0")
	assert_eq((detail.get_node("Chips/Origin/Label") as Label).text, "Yours")
	assert_eq((detail.get_node("Chips/State/Label") as Label).text, "On")
	manager.select("core")
	assert_eq(detail.heading.text, "tt-sim Core")
	assert_false(detail.remove_button.visible, "the game's own cannot be removed")
	assert_false(detail.folder_button.visible)
	assert_true(detail.verify_button.visible)


func test_dependencies_are_shown_with_their_state() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	var needs := manager.detail.get_node("Facts/Needs") as VBoxContainer
	assert_true("core ^1.0" in _all_text(needs))
	assert_true("installed 1.2.0" in _all_text(needs))


func _all_text(node: Node) -> String:
	var out := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return " ".join(out)


func test_a_library_that_fails_shows_why_in_its_row_and_card() -> void:
	_install_alien()
	World.edit_json(
		_paths["alien"] + "/library.json",
		func(library: Dictionary) -> void:
			library["dependencies"] = [{"id": "core", "version": "^9"}]
	)
	var manager := _manager()
	await _settle()
	var row := manager.row_of("alienworld")
	assert_not_null(row.get_node_or_null("Inner/Problem"), "a mark on the row")
	assert_true("core" in (row.get_node("Inner/Text/Facts") as Label).text, "why, in the row")
	manager.select("alienworld")
	assert_not_null(manager.detail.get_node_or_null("Notes"), "the reasons are listed")
	assert_eq((manager.detail.get_node("Chips/State/Label") as Label).text, "Needs attention")


func test_the_switch_turns_a_library_off_and_on_and_keeps_it() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	manager.toggle_of("alienworld").button_pressed = false
	assert_false(LibraryRegistry.is_enabled("alienworld"), "saved in the settings")
	assert_true("turned off" in manager.status_label.text, manager.status_label.text)
	assert_true(
		"Off" in (manager.row_of("alienworld").get_node("Inner/Text/Caption") as Label).text
	)
	manager.select("alienworld")
	assert_eq((manager.detail.get_node("Chips/State/Label") as Label).text, "Off")
	manager.toggle_of("alienworld").button_pressed = true
	assert_true(LibraryRegistry.is_enabled("alienworld"))
	assert_true("turned on" in manager.status_label.text)


func test_every_change_tells_the_open_pickers() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	watch_signals(manager)
	manager.toggle_of("alienworld").button_pressed = false
	assert_signal_emitted(manager, "libraries_changed")


func test_remove_asks_naming_the_saved_maps_that_use_it_and_then_deletes() -> void:
	_install_alien()
	var doc := Fixtures.full_doc()
	doc.libraries = [{"id": "alienworld", "version": "0.3.1", "hash": "ab12cd34"}]
	doc.scatter["alienworld__crystal_basin_summer_s1/Crystal_Spire_v0"] = PackedFloat32Array(
		[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
	)
	DirAccess.make_dir_recursive_absolute(ROOT + "/levels/uses")
	assert_eq(MapDocumentIO.write(doc, ROOT + "/levels/uses/map.ttmap"), OK)
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	manager.detail.remove_button.pressed.emit()
	var dialog: ConfirmationDialogUI = null
	for node in get_tree().root.get_children():
		if node is ConfirmationDialogUI:
			dialog = node
	assert_not_null(dialog, "the danger confirmation opened")
	await wait_process_frames(2)
	assert_true("1 saved map uses it" in dialog.message_label.text, dialog.message_label.text)
	assert_true(DirAccess.dir_exists_absolute(_paths["alien"]), "nothing is deleted yet")
	manager._remove_confirmed("alienworld")
	assert_false(DirAccess.dir_exists_absolute(_paths["alien"]))
	assert_null(manager.row_of("alienworld"))
	assert_eq(manager.selected_id, "core")
	assert_true("removed" in manager.status_label.text)


func test_remove_words_count_the_maps() -> void:
	assert_true("No saved map uses it" in LibraryManager.remove_message("Alien World", 0))
	assert_true("1 saved map uses it" in LibraryManager.remove_message("Alien World", 1))
	assert_true("3 saved maps use it" in LibraryManager.remove_message("Alien World", 3))


func test_a_library_turned_off_and_removed_comes_back_on_when_added_again() -> void:
	_install_alien()
	LibraryRegistry.set_enabled("alienworld", false)
	var manager := _manager()
	await _settle()
	manager._remove_confirmed("alienworld")
	assert_true(LibraryRegistry.is_enabled("alienworld"))


# ---- verify ----


func test_verify_checks_every_file_of_a_served_library() -> void:
	_install_alien()
	_serve()
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	manager.detail.verify_button.pressed.emit()
	await wait_until(
		func() -> bool:
			return (
				manager.detail.verify_button.disabled == false
				and "check out" in manager.detail.verify_label.text
			),
		TIMEOUT_S,
		"verify finished"
	)
	assert_eq(manager.detail.verify_label.text, "All 2 files check out.")


func test_verify_names_a_file_that_no_longer_matches() -> void:
	_install_alien()
	var glb: String = _paths["alien"] + "/assets/tree/Crystal_Spire_v0.glb"
	var file := FileAccess.open(glb, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_8(7)
	file.close()
	_serve()
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	manager.detail.verify_button.pressed.emit()
	await wait_until(
		func() -> bool: return "problem" in manager.detail.verify_label.text, TIMEOUT_S, "verify"
	)
	assert_eq(manager.detail.verify_label.text, "1 of 2 files have a problem.")
	assert_not_null(manager.detail.verify_box.get_node_or_null("Failure0"))
	assert_true("Crystal_Spire_v0" in _all_text(manager.detail.verify_box))


func test_verify_cannot_run_on_a_library_that_is_off_or_built_in() -> void:
	_install_alien()
	LibraryRegistry.set_enabled("alienworld", false)
	_serve()
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	manager.detail.verify_button.pressed.emit()
	assert_true("Turn it on" in manager.detail.verify_label.text)
	assert_false(manager.detail.verify_bar.visible)


# ---- importing ----


func test_an_import_goes_through_the_card_and_installs() -> void:
	var path := _zip(Zip.entries_of(SOURCE))
	var manager := _manager()
	await _settle()
	watch_signals(manager.flow)
	manager.flow.begin(path)
	assert_true(manager.import_file_button.disabled, "the buttons wait while a card is open")
	var card := await _ready_card(manager.flow)
	assert_not_null(card.confirm_button, "an Install button")
	assert_eq(card.confirm_button.text, "Install")
	assert_eq(card.header.title_label.text, "Alien World")
	var words := _all_text(card)
	for needle in ["Test Author", "CC0-1.0", "0.3.1", "2 assets, 1 biome", "core ^1.0"]:
		assert_true(needle in words, needle)
	assert_true(LibraryNames.only_art_and_settings() in words, "the promise is on the card")
	assert_false(DirAccess.dir_exists_absolute(_paths["alien"]), "nothing installed yet")
	card.confirm_button.pressed.emit()
	await wait_until(
		func() -> bool: return DirAccess.dir_exists_absolute(_paths["alien"]), TIMEOUT_S, "moved"
	)
	assert_signal_emitted(manager.flow, "installed")
	assert_eq(LibraryRegistry.info("alienworld")["status"], "ok")
	assert_not_null(manager.row_of("alienworld"), "the list shows it")
	assert_eq(manager.selected_id, "alienworld")
	assert_true("added" in manager.status_label.text, manager.status_label.text)
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "card closed")
	assert_false(manager.import_file_button.disabled)
	assert_eq(DirAccess.get_directories_at(LibraryImporter.incoming_root()).size(), 0)


func test_cancel_leaves_nothing_installed_or_staged() -> void:
	var path := _zip(Zip.entries_of(SOURCE))
	var manager := _manager()
	await _settle()
	manager.flow.begin(path)
	var card := await _ready_card(manager.flow)
	card.cancel_button.pressed.emit()
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "card closed")
	assert_false(DirAccess.dir_exists_absolute(_paths["alien"]))
	assert_eq(DirAccess.get_directories_at(LibraryImporter.incoming_root()).size(), 0)


func test_a_same_id_import_offers_replace_with_the_installed_version() -> void:
	_install_alien()
	World.write_alien(SOURCE, "0.4.0", [], false)
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	assert_eq(card.confirm_button.text, "Replace v0.3.1")
	assert_not_null(
		card.get_node_or_null(
			"%s" % "CenterContainer/PanelContainer/Body/Scroll/Content/ReplaceNote"
		)
	)
	assert_true("newer version" in _all_text(card))
	card.confirm_button.pressed.emit()
	await wait_until(
		func() -> bool: return LibraryRegistry.info("alienworld")["version"] == "0.4.0",
		TIMEOUT_S,
		"replaced"
	)
	assert_true("updated" in manager.status_label.text, manager.status_label.text)


func test_a_hostile_archive_shows_why_and_installs_nothing() -> void:
	var entries := Zip.entries_of(SOURCE)
	entries.append({"name": "scripts/run.gd", "data": "extends Node"})
	entries.append({"name": "../escape.json", "data": "{}"})
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(entries))
	var card := await _card_of(manager.flow)
	assert_null(card.confirm_button, "no way to install it")
	assert_eq(card.cancel_button.text, "Close")
	assert_eq(card.header.title_label.text, LibraryInstallCard.TITLE_REFUSED)
	var words := _all_text(card)
	assert_true("run.gd" in words and "escape.json" in words, words)
	assert_false(
		DirAccess.dir_exists_absolute(LibraryImporter.incoming_root()), "nothing extracted"
	)
	assert_false(FileAccess.file_exists(ROOT + "/user/escape.json"))
	card.cancel_button.pressed.emit()


func test_a_reserved_id_shows_why() -> void:
	World.edit_json(
		SOURCE + "/library.json", func(library: Dictionary) -> void: library["id"] = "core"
	)
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	assert_null(card.confirm_button)
	assert_true("belongs to the game" in _all_text(card), _all_text(card))
	card.cancel_button.pressed.emit()
	assert_false(DirAccess.dir_exists_absolute(_paths["user"] + "/core"))


func test_a_second_import_while_a_card_is_open_is_ignored() -> void:
	var first := _zip(Zip.entries_of(SOURCE), "first.ttlib")
	var second := _zip(Zip.entries_of(SOURCE), "second.ttlib")
	var manager := _manager()
	await _settle()
	manager.flow.begin(first)
	var card := await _ready_card(manager.flow)
	manager.flow.begin(second)
	assert_eq(manager.flow.panel, card, "still the first card")
	card.cancel_button.pressed.emit()


func test_a_file_dropped_on_the_manager_opens_the_card() -> void:
	var path := _zip(Zip.entries_of(SOURCE))
	var manager := _manager()
	await _settle()
	manager._on_files_dropped(PackedStringArray([path]))
	var card := await _ready_card(manager.flow)
	assert_not_null(card.confirm_button)
	card.cancel_button.pressed.emit()


func test_a_file_that_is_not_a_collection_dropped_on_the_manager_is_refused_on_the_card() -> void:
	var junk := INBOX.path_join("notes.txt")
	World.write_text(junk, "hello")
	var manager := _manager()
	await _settle()
	manager._on_files_dropped(PackedStringArray([junk]))
	var card := await _card_of(manager.flow)
	assert_null(card.confirm_button)
	assert_eq(card.header.title_label.text, LibraryInstallCard.TITLE_REFUSED)
	card.cancel_button.pressed.emit()


func test_a_folder_dropped_on_the_manager_installs_like_a_zip() -> void:
	var manager := _manager()
	await _settle()
	manager._on_files_dropped(PackedStringArray([SOURCE]))
	var card := await _ready_card(manager.flow)
	assert_not_null(card.confirm_button)
	card.confirm_button.pressed.emit()
	await wait_until(
		func() -> bool: return DirAccess.dir_exists_absolute(_paths["alien"]),
		TIMEOUT_S,
		"installed"
	)


# ---- the title and the New map dialog ----


func _title() -> TitleScreen:
	var title: TitleScreen = TITLE_SCENE.instantiate()
	title.level_provider = func() -> Array[Dictionary]: return _levels
	title.plays_provider = func() -> Dictionary: return {}
	title.session_provider = func() -> Array[Dictionary]: return []
	_host.add_child(title)
	return title


func test_the_title_has_the_tool_and_it_opens_the_manager() -> void:
	var title := _title()
	assert_eq(title.libraries_button.text, LibraryNames.title(2))
	assert_eq(title.libraries_button.get_parent().name, "Tools")
	title.libraries_button.pressed.emit()
	var manager := get_tree().root.find_child("LibraryManager", true, false) as LibraryManager
	assert_not_null(manager, "opened over the title")
	manager.free()


func test_a_library_dropped_on_the_title_opens_the_install_card() -> void:
	var title := _title()
	var path := _zip(Zip.entries_of(SOURCE))
	title._on_files_dropped(PackedStringArray([path]))
	assert_true(title.library_flow.is_busy())
	assert_null(title.imports.panel, "not a map import")
	var card := await _ready_card(title.library_flow)
	assert_not_null(card.confirm_button)
	card.cancel_button.pressed.emit()


func test_a_map_dropped_on_the_title_still_goes_to_the_map_import() -> void:
	var title := _title()
	var glb := INBOX.path_join("river.glb")
	World.write_text(glb, "not really a glb")
	title._on_files_dropped(PackedStringArray([glb]))
	assert_false(title.library_flow.is_busy(), "a .glb is not a collection")
	assert_not_null(title.imports.panel, "the map check opened")
	title.imports.panel.free()
	var other := _zip([{"name": "notes.txt", "data": "x"}], "other.zip")
	title._on_files_dropped(PackedStringArray([other]))
	assert_false(title.library_flow.is_busy(), "a zip with no library.json is not one either")
	if is_instance_valid(title.imports.panel):
		title.imports.panel.free()


func test_the_new_map_dialog_links_to_the_manager_and_follows_its_changes() -> void:
	_install_alien()
	_serve()
	var dialog := NEW_MAP_SCENE.instantiate() as NewMapDialog
	dialog.palette_root = _paths["base"]
	_host.add_child(dialog)
	await _settle()
	assert_eq(dialog.library_fields.size(), 1, "alienworld has its field")
	assert_eq(dialog.manage_button.text, "Manage %s..." % LibraryNames.lower(2))
	LibraryRegistry.set_enabled("alienworld", false)
	_serve()
	EventBus.foliage_library_changed.emit("")
	await wait_process_frames(2)
	assert_eq(dialog.library_fields.size(), 0, "the field left without reopening the dialog")
	assert_eq(dialog.biome_field.get_parent().name, "BiomeFields")
	LibraryRegistry.set_enabled("alienworld", true)
	_serve()
	EventBus.foliage_library_changed.emit("")
	await wait_process_frames(2)
	assert_eq(dialog.library_fields.size(), 1, "and came back")
	dialog.manage_button.pressed.emit()
	assert_not_null(get_tree().root.find_child("LibraryManager", true, false))


func test_the_new_map_dialog_keeps_its_pick_through_a_rebuild() -> void:
	_install_alien()
	_serve()
	var dialog := NEW_MAP_SCENE.instantiate() as NewMapDialog
	dialog.palette_root = _paths["base"]
	_host.add_child(dialog)
	await _settle()
	var pick := StringName(World.ALIEN_RUNTIME)
	dialog.library_fields[0].tiles.select(pick)
	dialog._on_biome_selected(pick)
	EventBus.foliage_library_changed.emit("")
	await wait_process_frames(2)
	assert_eq(dialog.current_spec()["biome_id"], World.ALIEN_RUNTIME, "kept")
	LibraryRegistry.set_enabled("alienworld", false)
	_serve()
	EventBus.foliage_library_changed.emit("")
	await wait_process_frames(2)
	assert_ne(dialog.current_spec()["biome_id"], World.ALIEN_RUNTIME, "gone, so the default")


# ---- the display name ----


func test_the_display_word_lives_in_one_place() -> void:
	assert_eq(LibraryNames.title(), LibraryNames.TITLE_SINGULAR)
	assert_eq(LibraryNames.title(2), LibraryNames.TITLE_PLURAL)
	assert_eq(LibraryNames.lower(2), LibraryNames.TITLE_PLURAL.to_lower())
	assert_eq(LibraryNames.counted(0), "no " + LibraryNames.lower(2))
	assert_eq(LibraryNames.counted(1), "1 " + LibraryNames.lower())
	assert_eq(LibraryNames.counted(3), "3 " + LibraryNames.lower(2))
	assert_true(LibraryNames.article().ends_with(LibraryNames.lower()))
	var word := LibraryNames.TITLE_SINGULAR.to_lower()
	var plural := LibraryNames.TITLE_PLURAL.to_lower()
	for path in WORDED_FILES:
		for literal in _string_literals(FileAccess.get_file_as_string(path)):
			var lowered := literal.to_lower()
			assert_false(
				word in lowered or plural in lowered, '%s: "%s"' % [path.get_file(), literal]
			)


## The text inside the double-quoted literals of `source`, comments cut off first.
func _string_literals(source: String) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string('"((?:[^"\\\\\\n]|\\\\.)*)"')
	for line in source.split("\n"):
		var code := line
		var in_string := false
		var cut := -1
		for i in line.length():
			if line[i] == '"' and (i == 0 or line[i - 1] != "\\"):
				in_string = not in_string
			elif line[i] == "#" and not in_string:
				cut = i
				break
		if cut >= 0:
			code = line.substr(0, cut)
		for found in pattern.search_all(code):
			out.append(found.get_string(1))
	return out


func test_changing_the_word_changes_every_label() -> void:
	# The strings are built from LibraryNames at call time: the manager's caption and the
	# install card's promise name the word they are given.
	assert_true(LibraryNames.lower(2) in LibraryNames.manager_caption().to_lower())
	assert_true(LibraryNames.lower() in LibraryNames.only_art_and_settings())
	assert_true(LibraryNames.lower() in LibraryNames.article())


# ---- fit ----


func test_the_manager_and_the_install_card_fit_the_smallest_canvas() -> void:
	_install_alien()
	World.write_alien(SOURCE, "0.4.0", [], false)
	var manager := _manager()
	manager.select("core")
	await _settle()
	_assert_inside(manager, "the manager")
	manager.select("alienworld")
	await _settle()
	_assert_inside(manager, "the manager on a user library")
	manager.flow.host = _host
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	await _settle()
	_assert_inside(card, "the install card")
	card.cancel_button.pressed.emit()


func _assert_inside(node: Node, what: String) -> void:
	var bounds := Rect2(Vector2.ZERO, CANVAS)
	for control in node.find_children("*", "Control", true, false):
		var item := control as Control
		if not item.is_visible_in_tree() or item is Scrim or item is ScrollContainer:
			continue
		if item.get_parent() is ScrollContainer or _inside_scroll(item):
			continue
		var rect := item.get_global_rect()
		var outside := (
			rect.position.x < -0.5
			or rect.position.y < -0.5
			or rect.end.x > bounds.end.x + 0.5
			or rect.end.y > bounds.end.y + 0.5
		)
		if outside and rect.size.x > 0.0 and rect.size.y > 0.0:
			fail_test("%s: %s at %s is outside the canvas" % [what, item.name, str(rect)])
			return
	assert_true(true, "%s fits" % what)


func _inside_scroll(item: Control) -> bool:
	var parent := item.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


# ---- the missing-library dialog ----


func test_the_missing_library_dialog_offers_the_manager() -> void:
	var libraries: Array[Dictionary] = [{"id": "zzmissing", "version": "1.0.0", "hash": ""}]
	var report := MapLibraries.check(libraries)
	var answers: Array = []
	var asked := func() -> void:
		var proceed: bool = await MapLibraryGate.ask_dialog(report)
		answers.append(proceed)
	asked.call()
	await wait_process_frames(2)
	var dialog: ConfirmationDialogUI = null
	for node in get_tree().root.get_children():
		if node is ConfirmationDialogUI:
			dialog = node
	assert_not_null(dialog)
	var alternate := dialog.find_child("AlternateButton", true, false) as Button
	assert_not_null(alternate, "a third choice")
	assert_eq(alternate.text, "Manage %s" % LibraryNames.lower(2))
	alternate.pressed.emit()
	await wait_process_frames(2)
	assert_eq(answers, [false], "the open is cancelled, as the title it returns to expects")
	assert_not_null(get_tree().root.find_child("LibraryManager", true, false), "the manager opened")


# ---- a collection a host sent ----


## Writes a collection a host sent into the user's folder: an ordinary library folder with the
## ownership marker and the from-host record (and the partial block when `partial`).
func _from_host(id: String, host: String, last_used: int = 5, partial: bool = true) -> void:
	var folder: String = _paths["user"] + "/" + id
	World.write_alien(folder, "0.3.1", [], false)
	World.edit_json(
		folder + "/library.json",
		func(d: Dictionary) -> void:
			d["id"] = id
			d["name"] = id.capitalize()
			if partial:
				d["partial"] = {
					"format": 1,
					"source_version": "0.3.1",
					"source_hash": "abc12345",
					"assets": ["Crystal_Spire_v0"],
					"biomes": ["crystal_basin"],
					"surfaces": [],
					"assets_only": false,
					"bytes": 1,
				}
	)
	assert_true(SafeDelete.mark(folder, "test", _paths["user"]))
	assert_true(
		(
			LibraryFromHost
			. write_record(
				folder,
				{
					"format": 1,
					"id": id,
					"host": host,
					"version": "0.3.1",
					"source_hash": "abc12345",
					"received_at": last_used,
					"last_used": last_used,
					"assets": ["Crystal_Spire_v0"],
					"partial": partial,
					"assets_only": false,
					"auto_delta": true,
				}
			)
		)
	)


func _cache_section(manager: LibraryManager) -> LibraryCacheSection:
	return manager.get_node("CenterContainer/PanelContainer/Body/CacheSection")


func test_a_collection_from_a_host_is_an_ordinary_one_that_is_only_marked() -> void:
	_from_host("alienworld", "Ann")
	var manager := _manager()
	await _settle()
	var row := manager.row_of("alienworld")
	assert_not_null(row, "listed")
	assert_eq((row.get_node("Inner/Origin/Label") as Label).text, LibraryDetail.BADGE_RECEIVED)
	assert_false(manager.toggle_of("alienworld").disabled, "it can be switched like any other")
	manager.select("alienworld")
	assert_true(manager.detail.remove_button.visible, "and removed")
	assert_true(manager.detail.folder_button.visible)
	watch_signals(manager)
	manager.toggle_of("alienworld").button_pressed = false
	assert_signal_emitted(manager, "libraries_changed")
	assert_false(LibraryRegistry.is_enabled("alienworld"))


func test_the_card_names_the_host_and_says_the_copy_is_partial() -> void:
	_from_host("alienworld", "Ann")
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	var note := manager.detail.get_node_or_null("ReceivedNote") as Label
	assert_not_null(note)
	assert_eq(note.text, "From host: Ann")
	var chips := manager.detail.get_node("Chips")
	assert_not_null(chips.get_node_or_null("Partial"), "the Partial copy chip")
	assert_eq(chips.get_node("Partial/Label").text, LibraryDetail.BADGE_PARTIAL)
	var line := manager.detail.get_node_or_null("PartialNote") as Label
	assert_eq(line.text, "Holds only what the host's maps used.")
	assert_false(manager.detail.design_button.visible, "a partial copy is not a designer base")


func test_a_whole_collection_from_a_host_is_not_called_partial() -> void:
	_from_host("alienworld", "Ann", 5, false)
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	assert_not_null(manager.detail.get_node_or_null("ReceivedNote"))
	assert_null(manager.detail.get_node_or_null("PartialNote"))
	assert_null(manager.detail.get_node("Chips").get_node_or_null("Partial"))


func test_removing_one_says_what_happens_to_the_maps_and_that_the_host_asks_first() -> void:
	_from_host("alienworld", "Ann")
	var manager := _manager()
	await _settle()
	manager.select("alienworld")
	manager.detail.remove_button.pressed.emit()
	var dialog: ConfirmationDialogUI = null
	for node in get_tree().root.get_children():
		if node is ConfirmationDialogUI:
			dialog = node
	assert_not_null(dialog)
	await wait_process_frames(2)
	assert_string_contains(dialog.message_label.text, "No saved map uses it")
	assert_string_contains(dialog.message_label.text, LibraryCacheSection.REMOVE_NOTE.strip_edges())
	manager._remove_confirmed("alienworld")
	assert_false(DirAccess.dir_exists_absolute(_paths["user"] + "/alienworld"))


func test_the_cache_row_counts_the_downloaded_collections_and_their_size() -> void:
	var manager := _manager()
	await _settle()
	assert_false(_cache_section(manager).visible, "nothing downloaded: nothing to manage")
	_from_host("alienworld", "Ann")
	_from_host("spirelands", "Bob")
	LibraryImportFlow.refresh_all()
	manager.refresh_list()
	manager.libraries_changed.emit()  # what every change the manager makes ends with
	var section := _cache_section(manager)
	assert_true(section.visible)
	var total := LibraryFromHost.total_bytes()
	assert_gt(total, 0)
	assert_eq(
		section.summary_label.text,
		LibraryCacheSection.summary_text(2, total, LibraryFromHost.cap_bytes())
	)
	assert_string_contains(section.summary_label.text, "2 collections downloaded from hosts")
	assert_false(section.clear_button.disabled)
	assert_eq(section.clear_button.text, "Clear downloaded collections")


func test_clear_asks_naming_collections_size_and_saved_maps_then_removes_only_those() -> void:
	_install_alien()
	_from_host("spirelands", "Bob")
	_from_host("glowmoss", "Ann")
	var doc := Fixtures.full_doc()
	doc.libraries = [{"id": "spirelands", "version": "0.3.1", "hash": "abc12345"}]
	doc.scatter["spirelands__crystal_basin_summer_s1/Crystal_Spire_v0"] = PackedFloat32Array(
		[0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
	)
	DirAccess.make_dir_recursive_absolute(ROOT + "/levels/uses")
	assert_eq(MapDocumentIO.write(doc, ROOT + "/levels/uses/map.ttmap"), OK)
	var manager := _manager()
	await _settle()
	var section := _cache_section(manager)
	var plan := section.describe_clear()
	assert_eq(plan["count"], 2)
	assert_eq(plan["maps"], 1, "one saved map uses a downloaded collection")
	assert_string_contains(plan["message"], "2 collections")
	assert_string_contains(plan["message"], LibraryCacheSection.size_text(int(plan["bytes"])))
	assert_string_contains(plan["message"], "1 saved map use")
	assert_string_contains(plan["message"], "Your own collections are not touched")
	section.clear_button.pressed.emit()
	var dialog: ConfirmationDialogUI = null
	for node in get_tree().root.get_children():
		if node is ConfirmationDialogUI:
			dialog = node
	assert_not_null(dialog, "a confirmation, not an immediate clear")
	await wait_process_frames(2)
	assert_eq(dialog.message_label.text, plan["message"])
	assert_true(DirAccess.dir_exists_absolute(_paths["user"] + "/spirelands"), "nothing yet")
	watch_signals(manager)
	var report := section.clear_now()
	assert_eq(report["removed"].size(), 2)
	assert_false(DirAccess.dir_exists_absolute(_paths["user"] + "/spirelands"))
	assert_false(DirAccess.dir_exists_absolute(_paths["user"] + "/glowmoss"))
	assert_true(DirAccess.dir_exists_absolute(_paths["alien"]), "the player's own is untouched")
	assert_true(DirAccess.dir_exists_absolute(_paths["core"]), "and core")
	assert_not_null(manager.row_of("alienworld"))
	assert_null(manager.row_of("spirelands"))
	assert_false(section.visible, "nothing left to manage")
	assert_signal_emitted(manager, "libraries_changed")


func test_the_cache_words_count_and_pluralise() -> void:
	assert_eq(
		LibraryCacheSection.clear_message(1, 3 * 1024 * 1024, 0),
		(
			"1 collection (3.0 MB) that hosts sent you will be deleted from this computer. "
			+ "No saved map uses them. Your own collections are not touched."
		)
	)
	assert_string_contains(LibraryCacheSection.clear_message(3, 100, 2), "2 saved maps use them")
	assert_string_contains(LibraryCacheSection.clear_message(3, 100, 1), "1 saved map use them")
	assert_eq(LibraryCacheSection.size_text(1536 * 1024 * 1024), "1.5 GB")
	assert_eq(LibraryCacheSection.size_text(5 * 1024 * 1024), "5.0 MB")


func test_the_size_limit_is_a_setting_and_defaults_to_one_gigabyte() -> void:
	assert_eq(LibraryFromHost.cap_bytes(), 1024 * 1024 * 1024)
	_from_host("alienworld", "Ann")
	var manager := _manager()
	await _settle()
	var section := _cache_section(manager)
	assert_eq(section.cap_option.get_item_text(section.cap_option.selected), "1.0 GB")
	var at := section.cap_option.get_item_index(512)
	section.cap_option.select(at)
	section.cap_option.item_selected.emit(at)
	assert_eq(LibraryFromHost.cap_bytes(), 512 * 1024 * 1024)
	var config := ConfigFile.new()
	assert_eq(config.load(SETTINGS), OK)
	assert_eq(config.get_value("library", "cache_cap_mb"), 512)
	assert_true(LibraryFromHost.set_cap_mb(1))
	assert_eq(LibraryFromHost.cap_bytes(), 64 * 1024 * 1024, "never below the floor")


func test_no_transfer_or_cache_text_says_plants_or_keep() -> void:
	for path in [
		"res://scenes/ui/library_transfer_ui.gd",
		"res://utils/library/library_transfer_consent.gd",
		"res://scenes/ui/library_manager/library_cache_section.gd",
		"res://utils/library/library_from_host.gd",
		"res://utils/library/library_transfer_install.gd",
		"res://autoloads/library_transfer_channel.gd",
	]:
		for literal in _string_literals(FileAccess.get_file_as_string(path)):
			var lowered := literal.to_lower()
			assert_false("plants" in lowered, '%s: "%s"' % [path.get_file(), literal])
			assert_false(lowered.strip_edges() == "keep", path.get_file())
