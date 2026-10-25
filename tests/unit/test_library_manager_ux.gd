extends GutTest

## The collections manager after the owner's review of 2026-10-25 (docs/systems/library.md
## "Collections manager"): the "Needs attention" pill and the aligned chip column, plain reasons,
## duplicate rows, the install card's relations (newer, same, older) and its FAILURE paths (the
## error stays on the card with Retry, the footer shows it, toasts draw above scrims), the layers
## the designer's picker and the toasts sit on, Verify Stop and Verify all, the keyboard, the
## rescan without a file watch, the mismatch dialog's link and import, Copy path and the words.
## The world is written at test time under a scratch folder (library_world.gd), as in
## test_library_manager.gd.

const World := preload("res://tests/unit/library_world.gd")
const Zip := preload("res://tests/unit/zip_builder.gd")
const ROOT := "user://test_library_manager_ux"
const SETTINGS := ROOT + "/settings.cfg"
const SOURCE := ROOT + "/source/alienworld"
const INBOX := ROOT + "/inbox"
const CANVAS := Vector2(1280.0, 720.0)
const TIMEOUT_S := 10.0

var _paths: Dictionary = {}
var _saved: Dictionary = {}
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
	World.remove_tree(_paths["alien"])
	World.write_alien(SOURCE, "0.3.1", [], false)
	LibraryImporter.limits = LibraryImporter.default_limits()
	LibraryImportFlow.serve_palette = false
	LibraryInstall.rename_override = Callable()
	LibraryInstall.make_dir_override = Callable()
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = SETTINGS
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	LevelManager.levels_dir = ROOT + "/levels/"
	DirAccess.make_dir_recursive_absolute(INBOX)
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "LibraryManagerUxScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_host = SubViewport.new()
	_host.size = Vector2i(CANVAS)
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_scene.add_child(_host)


func after_each() -> void:
	LibraryInstall.rename_override = Callable()
	LibraryInstall.make_dir_override = Callable()
	for panel in get_tree().root.find_children("*", "AnimatedCanvasLayerPanel", true, false):
		var backdrop := panel.get_node_or_null("ColorRect")
		if backdrop != null:
			UIManager.unregister_overlay(backdrop as Control)
	for node in get_tree().root.get_children():
		var ours := node is LibraryInstallCard or node is LibraryManager
		if ours or node is ConfirmationDialogUI or node is BiomeDesignerPicker:
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


func _serve() -> void:
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(_paths["base"])


func _settle() -> void:
	await wait_process_frames(2)
	for tween in get_tree().get_processed_tweens():
		tween.custom_step(3.0)
	await wait_process_frames(2)


## A user collection `folder_name` that needs `dependencies` (so it fails when they are unmet).
func _write_needy(folder_name: String, dependencies: Array) -> void:
	var folder: String = _paths["user"] + "/" + folder_name
	World.write_alien(folder, "0.1.0", dependencies, false)
	World.edit_json(
		folder + "/library.json",
		func(library: Dictionary) -> void:
			library["id"] = folder_name
			library["name"] = folder_name.capitalize()
	)


func _write_broken(folder_name: String) -> void:
	World.write_text(_paths["user"] + "/" + folder_name + "/library.json", "{ not json")


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


func _all_text(node: Node) -> String:
	var out := PackedStringArray()
	for label in node.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return " ".join(out)


func _action(name_of_action: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name_of_action
	event.pressed = true
	return event


# ---- the list: pill, alignment, summary, duplicates (UX-4) ----


func test_failing_rows_show_a_pill_not_a_switch_and_every_chip_lines_up() -> void:
	_install_alien()
	_write_needy("needsfuture", [{"id": "core", "version": "^9.0"}])
	_write_broken("brokenworld")
	var manager := _manager()
	await _settle()
	var keys := manager.keys()
	assert_eq(keys.size(), 4, "core, alienworld and the two that fail")
	var chip_x: Array[float] = []
	var state_x: Array[float] = []
	for key in keys:
		var row := manager.library_row(key)
		chip_x.append(row.origin_chip.global_position.x)
		state_x.append(row.get_node("StateSlot").global_position.x)
	for x in chip_x:
		assert_almost_eq(x, chip_x[0], 0.5, "the origin chips share one column: %s" % [chip_x])
	for x in state_x:
		assert_almost_eq(x, state_x[0], 0.5, "the state column is one column: %s" % [state_x])
	for key in ["needsfuture", "brokenworld"]:
		var failing := manager.library_row(key)
		assert_not_null(failing.pill, "%s shows the pill" % key)
		assert_null(failing.toggle, "and no switch")
		assert_null(manager.toggle_of(key))
		var words := failing.pill.find_child("Label", true, false) as Label
		assert_eq(words.text, "Needs attention")
		assert_not_null(
			failing.pill.find_child("Icon", true, false), "an icon too, not colour alone"
		)
		assert_true(failing.pill.is_visible_in_tree())
		var text := failing.button.get_node("Inner/Text") as Control
		assert_lt(text.modulate.a, 1.0, "the row is dimmed")
		assert_almost_eq(failing.pill.modulate.a, 1.0, 0.001, "the pill is not")
	assert_not_null(manager.toggle_of("alienworld"), "a healthy row keeps its switch")
	assert_null(manager.library_row("alienworld").pill)
	var pill_a := manager.library_row("needsfuture").pill
	var pill_b := manager.library_row("brokenworld").pill
	assert_almost_eq(pill_a.global_position.x, pill_b.global_position.x, 0.5, "pills line up")


func test_the_list_says_how_many_collections_need_attention() -> void:
	var manager := _manager()
	await _settle()
	assert_false(manager.summary_box.visible, "none do")
	_write_needy("needsfuture", [{"id": "core", "version": "^9.0"}])
	_write_broken("brokenworld")
	manager.rescan(true)
	await _settle()
	assert_true(manager.summary_box.visible)
	assert_eq(manager.summary_label.text, "2 %s need attention" % LibraryNames.lower(2))
	assert_eq(LibraryNames.attention_summary(1), "1 %s needs attention" % LibraryNames.lower())
	assert_eq(LibraryNames.attention_summary(0), "")


func test_two_folders_with_one_id_are_two_rows_and_the_extra_one_can_be_removed() -> void:
	_install_alien()
	World.write_alien(_paths["user"] + "/alienworld_copy", "0.3.1", [], false)
	var manager := _manager()
	await _settle()
	var keys := manager.keys()
	assert_true("alienworld" in keys and "alienworld@alienworld_copy" in keys, str(keys))
	var twin := manager.row_of("alienworld@alienworld_copy")
	assert_not_null(twin)
	var caption := (twin.get_node("Inner/Text/Caption") as Label).text
	assert_true("alienworld_copy" in caption, "the folder tells the rows apart: " + caption)
	var winner_caption := (
		(manager.row_of("alienworld").get_node("Inner/Text/Caption") as Label).text
	)
	assert_true("folder alienworld" in winner_caption, winner_caption)
	manager.select("alienworld@alienworld_copy")
	var detail := manager.detail
	assert_eq(detail.key, "alienworld@alienworld_copy")
	assert_true(detail.remove_button.visible)
	assert_eq(detail.remove_button.theme_type_variation, &"Danger", "Remove is prominent")
	assert_eq(detail.get_node("Actions").get_child(0), detail.remove_button, "and first")
	# Removing the extra folder keeps the other copy: it goes by folder, not by id.
	manager._remove_confirmed("alienworld@alienworld_copy")
	assert_false(DirAccess.dir_exists_absolute(_paths["user"] + "/alienworld_copy"))
	assert_true(DirAccess.dir_exists_absolute(_paths["alien"]), "the other copy stays")
	assert_eq(manager.keys().count("alienworld"), 1)


# ---- plain reasons (UX-3) ----


func test_each_reason_has_a_plain_sentence_an_action_and_the_technical_text_behind() -> void:
	var cases := {
		"needs library 'core' ^9.0, but 1.0.0-dev is installed":
		{"kind": LibraryReasons.KIND_DEPENDENCY, "has": "Core 9 or newer; this game has 1.0"},
		"needs library 'frostworld' ^1.0, which is not installed":
		{"kind": LibraryReasons.KIND_DEPENDENCY, "has": "which is not installed"},
		"needs library 'core', which is disabled":
		{"kind": LibraryReasons.KIND_DEPENDENCY, "has": "turned off"},
		"duplicate library id 'alienworld': 'alienworld' is used instead":
		{"kind": LibraryReasons.KIND_DUPLICATE, "has": "Two folders hold the same"},
		"folder 'alienworld_copy' must be named after the library id 'alienworld'":
		{"kind": LibraryReasons.KIND_FOLDER, "has": "folder"},
		"library.json is not valid JSON (line 0: Expected value, got 'EOF')":
		{"kind": LibraryReasons.KIND_DAMAGED, "has": "damaged"},
		"assets/catalog.json is missing or empty":
		{"kind": LibraryReasons.KIND_DAMAGED, "has": "damaged"},
		"something nobody wrote a rule for": {"kind": LibraryReasons.KIND_OTHER, "has": "problem"},
	}
	for reason: String in cases:
		var explained := LibraryReasons.explain(reason)
		var want: Dictionary = cases[reason]
		assert_eq(explained["kind"], want["kind"], reason)
		var first := LibraryReasons.sentence(explained)
		assert_true(String(want["has"]) in first, "%s -> %s" % [reason, first])
		assert_ne(String(explained["action"]), "", "an action for: " + reason)
		assert_eq(explained["details"], reason, "the technical text is kept")
		for jargon in ["user://", "sha256", "JSON", "library '", "catalog", "^"]:
			assert_false(jargon in first, "%s in the first line of: %s" % [jargon, reason])
	var update := LibraryReasons.explain("needs library 'core' ^9.0, but 1.0.0-dev is installed")
	assert_eq(
		LibraryReasons.sentence(update),
		(
			"This %s needs Core 9 or newer; this game has 1.0. Update the game or remove it."
			% LibraryNames.lower()
		)
	)


func test_the_card_of_a_failing_collection_says_it_plainly_and_folds_the_details() -> void:
	_write_needy("needsfuture", [{"id": "core", "version": "^9.0"}])
	var manager := _manager()
	await _settle()
	manager.select("needsfuture")
	var notes := manager.detail.get_node("Notes")
	var first := _all_text(notes.get_node("Reason0"))
	assert_true("Core 9 or newer" in first, first)
	assert_false("needs library" in first)
	var details := manager.detail.details_box
	assert_not_null(details)
	assert_false(details.visible, "the technical text is folded away")
	assert_true("needs library 'core'" in _all_text(details), "and kept inside")
	var fold := notes.get_node("DetailsButton") as Button
	fold.button_pressed = true
	assert_true(details.visible, "Details opens it")
	assert_lt(
		notes.get_index(), manager.detail.get_node("Facts").get_index(), "the reasons come first"
	)


func test_the_verify_error_is_plain_too() -> void:
	assert_false(
		"sha256" in LibraryVerify.plain_error("the GLB does not match the catalog's sha256")
	)
	assert_eq(
		LibraryVerify.plain_error("the GLB does not match the catalog's sha256"),
		"this file has changed or is damaged"
	)


# ---- the install card: newer, same, older (UX-5) ----


func test_a_file_older_than_the_installed_copy_is_refused_with_a_plain_reason() -> void:
	_install_alien()
	World.write_alien(SOURCE, "0.2.0", [], false)
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	assert_null(card.confirm_button, "no way to install it")
	assert_eq(card.cancel_button.text, "Close")
	var want := (
		"This is version 0.2.0; 0.3.1 is installed. "
		+ "Remove the installed one first if you want the older version."
	)
	assert_true(want in _all_text(card), _all_text(card))
	assert_eq(card.card["relation"], LibraryInstall.RELATION_OLDER)
	assert_false(bool(card.card["can_install"]))
	card.cancel_button.pressed.emit()
	assert_eq(LibraryRegistry.info("alienworld")["version"], "0.3.1", "nothing changed")


func test_the_same_version_offers_reinstall_as_a_repair() -> void:
	_install_alien()
	var glb: String = _paths["alien"] + "/assets/tree/Crystal_Spire_v0.glb"
	World.write_text(glb, "damaged")
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	assert_eq(card.confirm_button.text, "Reinstall")
	assert_true("same version" in _all_text(card), _all_text(card))
	assert_true("repairs" in _all_text(card))
	card.confirm_button.pressed.emit()
	await wait_until(
		func() -> bool: return "updated" in manager.status_label.text, TIMEOUT_S, "reinstalled"
	)
	var repaired := FileAccess.get_file_as_bytes(glb)
	assert_gt(repaired.size(), 100, "a fresh copy is in place")


func test_a_newer_file_names_both_versions_and_what_changes() -> void:
	_install_alien()
	World.write_alien(SOURCE, "0.4.0", [], false)
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE), "alien_0_4_0.ttlib"))
	var card := await _ready_card(manager.flow)
	assert_eq(card.confirm_button.text, "Replace v0.3.1 with v0.4.0")
	var from_line := _all_text(card.facts)
	assert_true("alien_0_4_0.ttlib" in from_line, "the card says which file it read: " + from_line)
	card.cancel_button.pressed.emit()
	var synthetic := {
		"existing": {"asset_count": 2, "biome_count": 1}, "asset_count": 5, "biome_count": 1
	}
	assert_eq(
		LibraryInstall.change_line(synthetic), "It holds 3 more assets than the installed one."
	)
	synthetic["biome_count"] = 0
	assert_eq(
		LibraryInstall.change_line(synthetic),
		"It holds 3 more assets and 1 fewer biome than the installed one."
	)
	synthetic["asset_count"] = 2
	synthetic["biome_count"] = 1
	assert_eq(LibraryInstall.change_line(synthetic), "")


# ---- the install fails (S24, UX-2) ----


func test_install_codes_and_retry_flags_name_each_failure() -> void:
	var card := {"can_install": false, "id": "alienworld", "folder": ROOT + "/nowhere"}
	var refused := LibraryInstall.install(card)
	assert_eq(refused["code"], LibraryInstall.FAIL_REFUSED)
	assert_false(refused["retry"])
	card["can_install"] = true
	var gone := LibraryInstall.install(card)
	assert_eq(gone["code"], LibraryInstall.FAIL_GONE)
	assert_false(gone["retry"], "staged files that are gone cannot be retried")
	assert_true("staged files are gone" in String(gone["error"]))


func test_a_failed_install_stays_on_the_card_in_red_with_retry_and_the_footer_says_it() -> void:
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	LibraryInstall.rename_override = func(_from: String, _to: String) -> int:
		return ERR_FILE_NO_PERMISSION
	watch_signals(manager.flow)
	card.confirm_button.pressed.emit()
	assert_signal_emitted(manager.flow, "install_failed")
	assert_true(is_instance_valid(manager.flow.panel), "the card is still open")
	assert_false(card.busy)
	assert_not_null(card.error_label, "the reason is on the card")
	assert_true("could not be moved" in card.error_label.text, card.error_label.text)
	var icon_path := "CenterContainer/PanelContainer/Body/Notice/InstallError/ErrorIcon"
	assert_not_null(card.get_node_or_null(icon_path), "with an icon")
	assert_eq(card.confirm_button.text, LibraryInstallCard.LABEL_RETRY)
	assert_eq(card.cancel_button.text, LibraryInstallCard.LABEL_CLOSE)
	assert_eq(manager.status_kind, "error", "and in the footer")
	assert_true("could not be moved" in manager.status_label.text)
	assert_true(manager.status_icon.visible, "with an icon")
	assert_false(DirAccess.dir_exists_absolute(_paths["alien"]), "nothing half installed")
	# Retry once the cause is gone: the same staged files install.
	LibraryInstall.rename_override = Callable()
	card.confirm_button.pressed.emit()
	await wait_until(
		func() -> bool: return DirAccess.dir_exists_absolute(_paths["alien"]),
		TIMEOUT_S,
		"installed"
	)
	assert_eq(manager.status_kind, "ok")
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "card closed")


func test_a_disk_that_cannot_make_the_folder_fails_the_same_way_and_close_cleans_up() -> void:
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	LibraryInstall.make_dir_override = func(_path: String) -> int: return ERR_FILE_CANT_WRITE
	card.confirm_button.pressed.emit()
	assert_true("folder cannot be created" in card.error_label.text, card.error_label.text)
	assert_eq(card.confirm_button.text, "Retry")
	card.cancel_button.pressed.emit()
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "card closed")
	assert_eq(DirAccess.get_directories_at(LibraryImporter.incoming_root()).size(), 0)
	assert_false(DirAccess.dir_exists_absolute(_paths["alien"]))


func test_staged_files_deleted_under_the_card_show_the_error_and_only_close() -> void:
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	World.remove_tree(String(card.card["folder"]))
	card.confirm_button.pressed.emit()
	assert_true(is_instance_valid(manager.flow.panel), "the card stays")
	assert_true("staged files are gone" in card.error_label.text, card.error_label.text)
	assert_null(card.confirm_button, "no Retry for files that are gone")
	assert_eq(card.cancel_button.text, "Close")
	assert_true("staged files are gone" in manager.status_label.text)
	card.cancel_button.pressed.emit()
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "card closed")


func test_the_title_flow_without_a_manager_shows_the_same_failure_on_the_card() -> void:
	var flow := LibraryImportFlow.new()
	flow.host = _host
	_host.add_child(flow)
	flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(flow)
	LibraryInstall.rename_override = func(_from: String, _to: String) -> int:
		return ERR_FILE_NO_PERMISSION
	card.confirm_button.pressed.emit()
	assert_true(is_instance_valid(flow.panel))
	assert_true("could not be moved" in card.error_label.text)
	card.cancel_button.pressed.emit()
	await wait_until(func() -> bool: return not flow.is_busy(), TIMEOUT_S, "card closed")


func test_toasts_and_the_designers_picker_draw_above_every_scrim() -> void:
	assert_gt(Constants.LAYER_TOAST, Constants.LAYER_DIALOG, "a toast is readable over a dialog")
	assert_gt(Constants.LAYER_TOAST, Constants.LAYER_SETTINGS)
	assert_lt(Constants.LAYER_TOAST, Constants.LAYER_TRANSITION)
	var toasts := UIManager.get("_toast_container") as CanvasLayer
	assert_not_null(toasts)
	assert_eq(toasts.layer, Constants.LAYER_TOAST)
	var picker := BiomeDesignerPicker.new()
	assert_gt(picker.layer, Constants.LAYER_DIALOG, "the picker is above the manager's scrim")
	assert_lt(picker.layer, Constants.LAYER_TOAST)
	picker.free()
	var manager := _manager()
	assert_eq(manager.layer, Constants.LAYER_DIALOG)
	assert_lt(manager.layer, Constants.LAYER_SUBDIALOG)


func test_the_install_card_leaves_the_manager_visible_but_dimmed_behind_it() -> void:
	var manager := _manager()
	await _settle()
	var sheet := manager.get_node("CenterContainer/PanelContainer") as Control
	assert_almost_eq(sheet.modulate.a, 1.0, 0.01)
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	await _settle()
	assert_true(sheet.visible, "the manager stays on screen")
	assert_almost_eq(sheet.modulate.a, AnimatedCanvasLayerPanel.DIM_ALPHA, 0.02, "stepped back")
	card.cancel_button.pressed.emit()
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "closed")
	await _settle()
	assert_almost_eq(sheet.modulate.a, 1.0, 0.01, "and back")


# ---- keyboard (UX-12) ----


func test_arrow_keys_move_through_the_list_and_into_the_switch() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	assert_eq(manager.selected_id, "core")
	manager.row_of("core").grab_focus()
	manager._input(_action("ui_down"))
	assert_eq(manager.selected_id, "alienworld", "Down selects the next collection")
	assert_true(manager.row_of("alienworld").has_focus(), "and the focus goes with it")
	manager._input(_action("ui_down"))
	assert_eq(manager.selected_id, "alienworld", "the last row stays")
	manager._input(_action("ui_up"))
	assert_eq(manager.selected_id, "core")
	manager.row_of("alienworld").grab_focus()
	manager._input(_action("ui_right"))
	assert_true(manager.toggle_of("alienworld").has_focus(), "Right reaches the switch")
	manager._input(_action("ui_left"))
	assert_true(manager.row_of("alienworld").has_focus(), "and Left comes back")
	manager.row_of("core").grab_focus()
	manager._input(_action("ui_right"))
	assert_true(manager.row_of("core").has_focus(), "core's switch is locked: focus stays")


func test_enter_on_a_switch_turns_it_and_on_a_row_selects_it() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	var toggle := manager.toggle_of("alienworld")
	toggle.grab_focus()
	assert_true(toggle.has_focus())
	assert_eq(toggle.focus_mode, Control.FOCUS_ALL, "Enter and Space reach it like any button")
	toggle.button_pressed = false
	assert_false(LibraryRegistry.is_enabled("alienworld"), "the switch turns it off")
	manager.row_of("alienworld").pressed.emit()
	assert_eq(manager.selected_id, "alienworld", "a row selects")


func test_escape_closes_an_open_card_first_then_the_manager() -> void:
	var manager := _manager()
	await _settle()
	manager.flow.begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(manager.flow)
	var escape := _action("ui_cancel")
	manager._unhandled_input(escape)
	assert_true(is_instance_valid(manager) and not manager._closing, "the sheet waits for the card")
	card._unhandled_input(escape)
	await wait_until(func() -> bool: return not manager.flow.is_busy(), TIMEOUT_S, "card closed")
	manager._unhandled_input(escape)
	assert_true(manager._closing, "the second Escape closes the sheet")


func test_every_state_has_a_cue_that_is_not_colour() -> void:
	_install_alien()
	_write_needy("needsfuture", [{"id": "core", "version": "^9.0"}])
	LibraryRegistry.set_enabled("alienworld", false)
	var manager := _manager()
	await _settle()
	var off := (manager.row_of("alienworld").get_node("Inner/Text/Caption") as Label).text
	assert_true(off.begins_with("Off"), "off says Off: " + off)
	assert_false(manager.toggle_of("alienworld").button_pressed, "and the switch is down")
	assert_not_null(manager.library_row("needsfuture").pill.find_child("Icon", true, false))
	var selected := manager.library_row(manager.selected_id)
	assert_almost_eq(selected.marker.modulate.a, 1.0, 0.01, "the selected row has its marker")
	var other := manager.library_row("alienworld")
	assert_almost_eq(other.marker.modulate.a, 0.0, 0.01)


# ---- verify: Stop and Verify all (UX-11) ----


func test_verify_stop_ends_the_check_early() -> void:
	_install_alien()
	_serve()
	var manager := _manager()
	manager.verify_slice_usec = 0
	await _settle()
	manager.select("alienworld")
	manager.detail.verify_button.pressed.emit()
	assert_true(manager.detail.verify_cancel_button.visible, "Stop shows while it runs")
	manager.detail.verify_cancel_button.pressed.emit()
	await wait_until(
		func() -> bool: return not manager.detail.verify_button.disabled, TIMEOUT_S, "stopped"
	)
	assert_true(manager.detail.verify_label.text.begins_with("Stopped after"))
	assert_false(manager.detail.verify_cancel_button.visible)


func test_verify_all_checks_every_collection_and_lists_one_result_each() -> void:
	_install_alien()
	# A second collection that is turned off is listed as not checked.
	_write_needy("betaworld", [])
	LibraryRegistry.set_enabled("betaworld", false)
	_serve()
	var manager := _manager()
	await _settle()
	manager.verify_all.button.pressed.emit()
	await wait_until(
		func() -> bool: return not manager.verify_all.running and manager.verify_all.box.visible,
		TIMEOUT_S,
		"verify all finished"
	)
	var words := _all_text(manager.verify_all.results_box)
	assert_true("Alien World: all 2 files check out" in words, words)
	assert_true("tt-sim Core: all 2 files check out" in words, words)
	assert_true("Betaworld: not checked (turned off)" in words, words)
	assert_false(manager.verify_all.bar.visible)
	assert_false(manager.verify_all.stop_button.visible)
	assert_true(manager.verify_all.label.text.begins_with("Checked"), manager.verify_all.label.text)


func test_verify_all_names_the_file_that_failed_and_stop_ends_it() -> void:
	_install_alien()
	var glb: String = _paths["alien"] + "/assets/tree/Crystal_Spire_v0.glb"
	var file := FileAccess.open(glb, FileAccess.READ_WRITE)
	file.seek_end()
	file.store_8(7)
	file.close()
	_serve()
	var manager := _manager()
	await _settle()
	manager.verify_all.button.pressed.emit()
	await wait_until(func() -> bool: return not manager.verify_all.running, TIMEOUT_S, "done")
	var words := _all_text(manager.verify_all.results_box)
	assert_true("Alien World: 1 of 2 files have a problem" in words, words)
	assert_true("Crystal_Spire_v0" in words)
	assert_false("sha256" in words)
	manager.verify_slice_usec = 0
	manager.verify_all.button.pressed.emit()
	assert_true(manager.verify_all.running)
	assert_true(manager.verify_all.stop_button.visible)
	manager.verify_all.stop_button.pressed.emit()
	await wait_until(func() -> bool: return not manager.verify_all.running, TIMEOUT_S, "stopped")
	assert_true(manager.verify_all.label.text.begins_with("Stopped after"))


# ---- rescanning without a file watch ----


func test_the_manager_rescans_on_open_on_focus_and_on_refresh_never_in_the_background() -> void:
	var manager := _manager()
	await _settle()
	assert_eq(manager.keys(), ["core"])
	assert_false(manager.rescan(), "nothing changed: the check is only a listing")
	_install_alien()
	assert_true(manager.rescan(), "a folder appeared: rescanned")
	assert_true("alienworld" in manager.keys())
	assert_false(manager.rescan(), "and quiet again")
	# The window coming back to the front looks again.
	_write_needy("needsfuture", [{"id": "core", "version": "^9.0"}])
	manager._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true("needsfuture" in manager.keys())
	# The Refresh button always looks.
	World.remove_tree(_paths["user"] + "/needsfuture")
	manager.refresh_button.pressed.emit()
	assert_false("needsfuture" in manager.keys())
	assert_true("Looked at the folders again" in manager.status_label.text)
	# A sheet that opens later reads what is on disk.
	var second := _manager()
	await _settle()
	assert_true("alienworld" in second.keys())
	assert_eq(manager.find_children("*", "Timer", true, false).size(), 0, "no timer, no watch")


func test_the_disk_signature_follows_the_folders_and_costs_no_read() -> void:
	LibraryRegistry.refresh()
	var before := LibraryRegistry.disk_signature()
	assert_eq(before, LibraryRegistry.seen_signature(), "refresh remembers it")
	assert_eq(LibraryRegistry.disk_signature(), before, "stable while nothing changes")
	_install_alien()
	assert_ne(LibraryRegistry.disk_signature(), before)


# ---- the mismatch dialog (UX-7) ----


func _missing_report(url: String = "") -> Dictionary:
	var claimed: Array[Dictionary] = [
		{"id": "alienworld", "version": "0.3.1", "hash": "", "url": url}
	]
	return MapLibraries.check(claimed)


func test_the_mismatch_dialog_shows_the_link_and_offers_import_in_place() -> void:
	var asker := LibraryMismatchDialog.show(_missing_report("https://example.org/alien"), _host)
	await wait_process_frames(2)
	var dialog := asker.dialog()
	assert_not_null(dialog)
	assert_true("alienworld v0.3.1 is not installed." in dialog.message_label.text)
	assert_false("plant" in dialog.message_label.text.to_lower())
	assert_false("plant" in dialog.title_label.text.to_lower())
	var link := dialog.find_child("Link_alienworld", true, false) as Button
	assert_not_null(link, "the record's link")
	assert_eq(link.get_meta("uri"), "https://example.org/alien")
	assert_not_null(dialog.find_child("ImportFileButton", true, false))
	assert_not_null(dialog.find_child("ImportFolderButton", true, false))
	assert_eq(dialog.confirm_button.text, LibraryNames.open_without())
	var without_link := LibraryMismatchDialog.show(_missing_report(), _host)
	await wait_process_frames(2)
	var bare := without_link.dialog().find_child("Link_alienworld", true, false)
	assert_null(bare, "no link, none shown")
	without_link.dialog().cancel_button.pressed.emit()
	dialog.cancel_button.pressed.emit()


func test_importing_from_the_mismatch_dialog_ends_it_with_a_retry() -> void:
	var asker := LibraryMismatchDialog.show(_missing_report(), _host)
	var answers: Array = []
	asker.answered.connect(func(result: Variant) -> void: answers.append(result))
	await wait_process_frames(2)
	asker.flow().begin(_zip(Zip.entries_of(SOURCE)))
	var card := await _ready_card(asker.flow())
	card.confirm_button.pressed.emit()
	await wait_until(func() -> bool: return answers.size() == 1, TIMEOUT_S, "answered")
	assert_eq(answers[0], MapLibraryGate.RETRY, "the open is re-run")
	assert_true(DirAccess.dir_exists_absolute(_paths["alien"]), "and the collection is installed")


func test_manage_collections_opens_the_manager_over_its_own_scrim() -> void:
	var asker := LibraryMismatchDialog.show(_missing_report(), _host)
	var answers: Array = []
	asker.answered.connect(func(result: Variant) -> void: answers.append(result))
	await wait_process_frames(2)
	var manage := asker.dialog().find_child("AlternateButton", true, false) as Button
	manage.pressed.emit()
	await _settle()
	assert_eq(answers, [false])
	var manager := get_tree().root.find_child("LibraryManager", true, false) as LibraryManager
	assert_not_null(manager)
	var backdrop := manager.get_node("ColorRect") as CanvasItem
	assert_almost_eq(
		backdrop.self_modulate.a, 1.0, 0.01, "its own scrim, not the leaving dialog's shared one"
	)
	assert_almost_eq(backdrop.modulate.a, 1.0, 0.01)


# ---- the words and the small additions ----


func test_the_manager_says_how_to_add_collections_and_hides_the_catalog_link() -> void:
	var manager := _manager()
	await _settle()
	assert_eq(manager.hint_label.text, LibraryNames.drop_hint())
	assert_true(manager.hint_label.is_visible_in_tree(), "always, not only when core is alone")
	_install_alien()
	manager.rescan()
	assert_true(manager.hint_label.is_visible_in_tree())
	assert_eq(LibraryNames.CATALOG_URL, "", "the owner has not named a catalogue yet")
	assert_null(manager.catalog_button, "so the link is hidden")


func test_copy_path_is_offered_for_a_folder_the_player_can_reach() -> void:
	_install_alien()
	var manager := _manager()
	await _settle()
	manager.select("core")
	assert_null(manager.detail.copy_button, "core's folder is inside the game")
	manager.select("alienworld")
	assert_not_null(manager.detail.copy_button)
	watch_signals(manager.detail)
	manager.detail.copy_button.pressed.emit()
	assert_signal_emitted(manager.detail, "path_copied")
	assert_eq(manager.status_label.text, "Folder path copied.")


func test_counts_are_pluralised_and_one_term_names_the_game_own_collection() -> void:
	assert_eq(LibraryNames.count_of(1, "asset"), "1 asset")
	assert_eq(LibraryNames.count_of(0, "asset"), "0 assets")
	assert_eq(LibraryNames.count_of(2, "biome"), "2 biomes")
	assert_eq(LibraryNames.count_of(2, "mouse", "mice"), "2 mice")
	assert_eq(LibraryDetail.BADGE_BUILTIN, "Built in")
	_install_alien()
	var manager := _manager()
	await _settle()
	assert_true("Built in" in _all_text(manager.detail.facts), "the card says Built in, once")
	var source := FileAccess.get_file_as_string("res://scenes/ui/library_manager/library_detail.gd")
	for literal in _string_literals(source):
		assert_ne(literal, "Part of the game", "one term for it")


func test_the_placeholder_licence_reads_as_included_with_the_game() -> void:
	assert_eq(
		LibraryNames.license_text("TBD (to be decided by the owner)"), LibraryNames.LICENSE_INCLUDED
	)
	assert_eq(LibraryNames.license_text("CC0-1.0"), "CC0-1.0")
	assert_eq(LibraryNames.license_text(""), "")
	var info := {"version": "1.0.0-dev", "author": "A", "license": "TBD (to be decided)"}
	assert_eq(LibraryDetail.subtitle_of(info), "v1.0.0-dev by A · Included with the game")


func test_no_dialog_string_says_plants() -> void:
	for path in [
		"res://scenes/ui/library_manager/library_manager.gd",
		"res://scenes/ui/library_manager/library_detail.gd",
		"res://scenes/ui/library_manager/library_install_card.gd",
		"res://scenes/ui/library_manager/library_import_flow.gd",
		"res://scenes/ui/library_manager/library_row.gd",
		"res://scenes/ui/library_manager/library_verify_all.gd",
		"res://scenes/ui/library_manager/library_mismatch_dialog.gd",
		"res://utils/library/library_reasons.gd",
		"res://utils/library/library_install.gd",
		"res://utils/library/library_importer.gd",
		"res://utils/library/map_libraries.gd",
		"res://utils/map_library_gate.gd",
		"res://utils/library/library_transfer_consent.gd",
		"res://utils/library/library_transfer.gd",
		"res://scenes/ui/library_transfer_ui.gd",
	]:
		for literal in _string_literals(FileAccess.get_file_as_string(path)):
			assert_false("plant" in literal.to_lower(), '%s: "%s"' % [path.get_file(), literal])


func test_the_transfer_dialogs_name_the_collection_through_the_one_word() -> void:
	# libcache owns library_transfer_ui.gd and the received store; this scan is explicit about
	# the one file it can read. When libcache's work lands it adds its own files to the list in
	# test_library_manager.gd (WORDED_FILES) and this note goes away.
	var source := FileAccess.get_file_as_string("res://scenes/ui/library_transfer_ui.gd")
	for literal in _string_literals(source):
		var lowered := literal.to_lower()
		assert_false(
			LibraryNames.lower() in lowered or LibraryNames.lower(2) in lowered,
			'library_transfer_ui.gd: "%s"' % literal
		)
	assert_eq(
		LibraryNames.host_uses_title(), "The host uses %s you do not have" % LibraryNames.lower(2)
	)
	pending("libcache: add its transfer files to WORDED_FILES once they use LibraryNames")


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
