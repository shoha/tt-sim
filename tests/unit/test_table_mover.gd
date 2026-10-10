extends GutTest

## TableMover and TableStates, the table moves and per-map session state: what a table had
## become is kept by shelf key and laid over the map's template when it is set out again
## (tokens, look, op log); a move never asks, it keeps the table and counts down; a changed
## map's shelf row offers Save into map and Discard changes, each behind a confirm, for a map
## that is out (the table) or not (a kept state); the notice names the move, who makes it and
## where the table goes, with a count that never moves the chip. The party is never part of a
## map's state. tests/net/enet_session_room.gd drives the whole move between real peers.

const KEY_A := "_table_moves_a"
const KEY_B := "_table_moves_b"
const DOC_FOLDER := "_table_moves_doc"
## A level folder this test writes into the library (removed after each test).
const SAVED := "_table_moves_saved"
const LONG_NAME := "The Drowned Lanterns of Upper Fenwick Mire and the Reeds Beyond"

var _controller: LevelPlayController
var _mover: TableMover
var _saves: Array[String] = []


func before_each() -> void:
	NetworkManager.session.reset()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	_saves.clear()
	_controller = autofree(LevelPlayController.new())
	_controller._save_level_impl = func() -> String:
		_saves.append("saved")
		return "user://saved/"
	_mover = TableMover.new()
	add_child_autofree(_mover)
	_mover.setup(_controller)
	for key in [KEY_A, KEY_B]:
		NetworkManager.session.shelve({"level_folder": key, "level_name": key.capitalize()})


func after_each() -> void:
	_mover.cancel()
	for dialog in _dialogs():
		dialog.free()
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager.clear_level_data()
	NetworkManager.session.reset()
	for folder in [DOC_FOLDER, SAVED]:
		_remove_folder(folder)


## A template with two placements, as LevelManager reads it from its folder.
func _template(key: String) -> LevelData:
	var level := LevelData.new()
	level.level_name = key.capitalize()
	level.level_folder = key
	for token_name in ["Goblin", "Ogre"]:
		var placement := TokenPlacement.new()
		placement.token_name = token_name
		placement.position = Vector3(1, 0, 2)
		level.add_token_placement(placement)
	return level


## SAVED written into the library as a template, and put on the shelf.
func _saved_map() -> LevelData:
	var level := _template(SAVED)
	level.level_name = "Old Mill"
	assert_ne(LevelManager.save_level_folder(level), "", "the test map is written")
	NetworkManager.session.shelve(level.to_dict())
	return level


## Puts `level` on the table, loaded, with the look it was saved with as the baseline.
func _on_table(level: LevelData) -> void:
	NetworkManager.session.note_table_out(level.to_dict())
	_controller.active_level_data = level
	_mover._on_level_loaded(level)


func _dialogs() -> Array[ConfirmationDialogUI]:
	var found: Array[ConfirmationDialogUI] = []
	for child in get_tree().root.get_children():
		if child is ConfirmationDialogUI and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _notice() -> TableMoveNotice:
	return _mover.get_node_or_null("TableMoveNotice") as TableMoveNotice


func _remove_folder(folder: String) -> void:
	var path := LevelManager.folder_path(folder)
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path.trim_suffix("/"))


# =============================================================================
# THE STATE OF A MAP
# =============================================================================


## A capture keeps the placements as a save would write them, the look and the op log, and
## overlay() lays them on a fresh template.
func test_a_capture_overlays_tokens_look_and_log_on_the_template() -> void:
	var table := _template(KEY_A)
	table.token_placements[0].position = Vector3(5, 0, 7)
	table.light_intensity_scale = 1.6
	table.grid_cell_size = 3.0
	var ops: Array[PackedByteArray] = [PackedByteArray([1, 2]), PackedByteArray([3])]
	var entry := TableStates.capture(table, {}, ops)
	ops.append(PackedByteArray([9]))
	assert_eq((entry.op_log as Array).size(), 2, "the log is a copy")
	var fresh := _template(KEY_A)
	TableStates.overlay(fresh, entry)
	assert_eq(fresh.token_placements.size(), 2)
	assert_eq(fresh.token_placements[0].position, Vector3(5, 0, 7))
	assert_eq(fresh.token_placements[0].placement_id, table.token_placements[0].placement_id)
	assert_eq(fresh.light_intensity_scale, 1.6)
	assert_eq(fresh.grid_cell_size, 3.0)
	assert_eq(TableStates.look_of(fresh), TableStates.look_of(table))
	assert_eq(TableStates.op_log_of(entry), [PackedByteArray([1, 2]), PackedByteArray([3])])


## The party is the session's: a member is on the board but out of the map's placements
## (SessionParty adopted it), so a map's state never holds it.
func test_the_party_is_not_kept_with_a_map() -> void:
	var table := _template(KEY_A)
	var member := BoardToken.new()
	member.network_id = "hero"
	autofree(member)
	var entry := TableStates.capture(table, {"hero": member}, [])
	var names: Array = (entry.placements as Array).map(func(p: Dictionary) -> String:
		return p.token_name
	)
	assert_eq(names, ["Goblin", "Ogre"])


## Keep stores what the table became, and the map comes back that way: the placements and
## the look laid over its template, the op log handed to the live edits, and the table
## compared with the template, not with what it was set out with.
func test_kept_state_comes_back_with_the_map() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	table.token_placements[1].position = Vector3(9, 0, 9)
	table.light_intensity_scale = 0.5
	assert_true(_mover.changes().look, "the look changed")
	assert_true(await _mover._leave_table(TableMover.Choice.KEEP))
	assert_true(_mover.states.has(KEY_A))
	var back := _template(KEY_A)
	_mover._arrive(KEY_A, back)
	assert_eq(back.token_placements[1].position, Vector3(9, 0, 9))
	assert_eq(back.light_intensity_scale, 0.5)
	assert_eq(_controller.replay_log, [] as Array[PackedByteArray])
	_controller.active_level_data = back
	_mover._on_level_loaded(back)
	assert_true(_mover.changes().look, "still differs from the map as saved")


## A table that is as its map was saved keeps nothing: the template comes back.
func test_an_unchanged_table_keeps_nothing() -> void:
	_on_table(_template(KEY_A))
	_mover.states.store(KEY_A, {"placements": [], "op_log": []})
	assert_false(_mover.changes().values().has(true))
	assert_true(await _mover._leave_table(TableMover.Choice.KEEP))
	assert_false(_mover.states.has(KEY_A))


## Discard forgets the map's state, so it comes back as its template.
func test_discard_brings_the_template_back() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	table.light_intensity_scale = 0.5
	_mover.states.store(KEY_A, TableStates.capture(table, {}, [PackedByteArray([1])]))
	assert_true(await _mover._leave_table(TableMover.Choice.DISCARD))
	assert_false(_mover.states.has(KEY_A))
	var back := _template(KEY_A)
	_mover._arrive(KEY_A, back)
	assert_eq(back.light_intensity_scale, 1.0)
	assert_eq(back.token_placements[0].position, Vector3(1, 0, 2))
	assert_true(_controller.replay_log.is_empty())


## With live edits, Save into map writes the edited document into the map's folder as
## authoring's save does.
func test_save_into_map_writes_the_edited_document() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "test", 7)
	doc.heights[0] = 2.5
	var editor := AuthoringEditor.new()
	editor.document = doc
	var level := LevelData.new()
	level.level_folder = DOC_FOLDER
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(DOC_FOLDER))
	assert_true(TableMover.write_document(editor, level))
	var read := MapDocumentIO.read(LevelManager.map_document_path(DOC_FOLDER))
	var saved := read.get("document") as MapDocument
	assert_not_null(saved, str(read))
	if saved != null:
		assert_almost_eq(saved.heights[0], 2.5, 0.01)
	level.level_folder = ""
	assert_false(TableMover.write_document(editor, level), "a map with no folder")


# =============================================================================
# THE MOVE: NO QUESTION, THE TABLE KEPT
# =============================================================================


## A changed table moves without a question: the notice counts down with Stay here, and at
## its end the table is kept for the session and Root is sent to the room.
func test_a_move_never_asks_and_keeps_the_table() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	table.light_intensity_scale = 0.5
	var rooms: Array[bool] = []
	_mover.room_chosen.connect(func() -> void: rooms.append(true))
	_mover.request_move(TableMover.ROOM)
	assert_eq(_dialogs().size(), 0, "no prompt")
	var notice := _notice()
	assert_not_null(notice)
	assert_true(_mover.is_moving())
	assert_eq(notice.shown_text(), "Returning everyone to the room in 3")
	assert_not_null(notice.stay_button)
	_mover._on_notice_elapsed()
	await wait_physics_frames(1)
	assert_true(_mover.states.has(KEY_A), "kept without asking")
	assert_eq(rooms, [true] as Array[bool])


## Stay here calls the move off; a move to another map names it.
func test_stay_here_calls_the_move_off() -> void:
	_on_table(_template(KEY_A))
	_mover.request_move(KEY_B)
	assert_eq(_notice().shown_text(), "Moving the table to Table Moves B in 3")
	_notice().stay_button.pressed.emit()
	assert_false(_mover.is_moving(), "Stay here calls it off")
	_mover.request_move(KEY_A)
	assert_false(_mover.is_moving(), "never to the map already out")


## Save into map on the way out still writes the level through the play HUD's save; a save
## that fails keeps the table where it is and says what failed, why and what to do.
func test_save_on_leaving_writes_the_level_or_stops() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	table.light_intensity_scale = 0.5
	_mover.states.store(KEY_A, TableStates.capture(table, {}, []))
	assert_true(await _mover._leave_table(TableMover.Choice.SAVE))
	assert_eq(_saves, ["saved"] as Array[String])
	assert_false(_mover.states.has(KEY_A))
	_controller._save_level_impl = func() -> String: return ""
	_mover.states.store(KEY_A, TableStates.capture(table, {}, []))
	assert_false(await _mover._leave_table(TableMover.Choice.SAVE), "the move stops")
	assert_true(_mover.states.has(KEY_A), "nothing forgotten")
	assert_eq(
		TableMover.save_error("Old Mill", TableMover.WHY_LEVEL),
		(
			"Could not save into “Old Mill”: its map file could not be written. Your changes are"
			+ " still kept. Check that your maps folder is not full or read-only, then try again."
		)
	)


# =============================================================================
# THE SHELF ROWS: SAVE INTO MAP AND DISCARD CHANGES
# =============================================================================


## The changed maps: every kept state, and the table when it differs from its map now; Save
## into map only for a map with a level folder in this library.
func test_changed_maps_are_the_kept_states_and_the_changed_table() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	assert_eq(_mover.changed_maps(), {}, "nothing changed yet")
	_saved_map()
	_mover.states.store(SAVED, TableStates.capture(_template(SAVED), {}, []))
	_mover.states.store(KEY_B, TableStates.capture(_template(KEY_B), {}, []))
	table.light_intensity_scale = 0.5
	assert_eq(_mover.changed_maps(), {SAVED: true, KEY_B: false, KEY_A: false})
	_mover.states.store(KEY_A, TableStates.capture(table, {}, []))
	table.light_intensity_scale = 1.0
	assert_false(_mover.changed_maps().has(KEY_A), "the table as its map: its old state is stale")


## Save into map from the shelf, for a map that is not out: a confirm names the consequence;
## yes writes the kept placements and look into the level folder and forgets the state.
func test_save_from_the_shelf_confirms_then_writes_the_kept_state() -> void:
	var template := _saved_map()
	var kept := _template(SAVED)
	kept.token_placements = template.token_placements.duplicate()
	kept.token_placements[0].position = Vector3(6, 0, 4)
	kept.light_intensity_scale = 0.4
	_mover.states.store(SAVED, TableStates.capture(kept, {}, []))
	var changed: Array[bool] = []
	_mover.changes_changed.connect(func() -> void: changed.append(true))
	var dialog := _mover.ask_save(SAVED)
	assert_not_null(dialog)
	assert_eq(dialog.title_label.text, "Save into “Old Mill”?")
	assert_eq(dialog.message_label.text, "“Old Mill” itself changes for every later session.")
	assert_eq(dialog.confirm_button.text, TableMover.SAVE_TEXT)
	assert_eq(dialog.confirm_button.theme_type_variation, &"Primary")
	assert_eq(dialog.cancel_button.text, "Cancel")
	dialog.confirm_button.pressed.emit()
	await wait_physics_frames(1)
	assert_false(_mover.states.has(SAVED), "saved, so forgotten")
	assert_eq(changed.size(), 1)
	var read := LevelManager.load_level_folder(SAVED, false)
	assert_eq(read.token_placements[0].position, Vector3(6, 0, 4))
	assert_almost_eq(read.light_intensity_scale, 0.4, 0.001)
	assert_null(_mover.ask_save(KEY_B), "no level folder here: nothing to save into")


## A kept state whose map left the library stays kept, and the error says why.
func test_a_save_from_the_shelf_that_fails_keeps_the_state() -> void:
	_mover.states.store(KEY_B, TableStates.capture(_template(KEY_B), {}, []))
	assert_false(_mover.save_kept(KEY_B))
	assert_true(_mover.states.has(KEY_B))
	var terrain := TableStates.capture(_saved_map(), {}, [PackedByteArray([1])])
	_mover.states.store(SAVED, terrain)
	assert_false(_mover.save_kept(SAVED), "terrain ops and no document to write")
	assert_true(_mover.states.has(SAVED))


## Discard changes from the shelf: a danger confirm, the action set apart at the left and
## Cancel alone at the right, on the 420 width token; yes forgets the state.
func test_discard_from_the_shelf_confirms_then_forgets() -> void:
	_mover.states.store(KEY_B, TableStates.capture(_template(KEY_B), {}, []))
	var dialog := _mover.ask_discard(KEY_B)
	await wait_physics_frames(1)
	assert_eq(dialog.title_label.text, "Discard the changes to “Table Moves B”?")
	assert_eq(dialog.message_label.text, "“Table Moves B” goes back to how it was saved.")
	assert_eq(dialog.confirm_button.theme_type_variation, &"Danger")
	var row := dialog.confirm_button.get_parent()
	assert_eq(dialog.confirm_button.get_index(), 0, "the action at the left")
	assert_eq(row.get_child(1).name, &"Apart")
	assert_eq(dialog.cancel_button.get_index(), row.get_child_count() - 1)
	var sheet := dialog.get_node("CenterContainer/PanelContainer") as Control
	assert_eq(sheet.custom_minimum_size.x, TableMover.CONFIRM_WIDTH)
	dialog.confirm_button.pressed.emit()
	assert_false(_mover.states.has(KEY_B))


## A long map name wraps in the confirm's title rather than widen the sheet.
func test_a_long_name_keeps_the_confirm_on_its_width() -> void:
	NetworkManager.session.shelve({"level_folder": "_table_moves_long", "level_name": LONG_NAME})
	_mover.states.store("_table_moves_long", {"placements": [], "op_log": []})
	var dialog := _mover.ask_discard("_table_moves_long")
	await wait_physics_frames(2)
	var sheet := dialog.get_node("CenterContainer/PanelContainer") as Control
	assert_eq(sheet.size.x, TableMover.CONFIRM_WIDTH)
	assert_eq(dialog.title_label.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)


## Discard changes on the table that is out sets it out again from its map, after the notice
## (Stay here offered): the template comes back for everyone.
func test_discard_on_the_table_sets_its_map_out_again() -> void:
	var template := _saved_map()
	var table := LevelManager.load_level_folder(SAVED, false)
	_on_table(table)
	table.light_intensity_scale = 0.3
	_mover.states.store(SAVED, TableStates.capture(table, {}, []))
	var chosen: Array[LevelData] = []
	_mover.level_chosen.connect(func(level: LevelData) -> void: chosen.append(level))
	_mover.discard_changes(SAVED)
	assert_eq(_notice().shown_text(), "Putting Old Mill back as it was saved in 3")
	assert_not_null(_notice().stay_button)
	_mover._on_notice_elapsed()
	await wait_physics_frames(1)
	assert_eq(chosen.size(), 1)
	assert_almost_eq(chosen[0].light_intensity_scale, template.light_intensity_scale, 0.001)
	assert_false(_mover.states.has(SAVED))


## Save into map on the table that is out, with no terrain written, saves as the HUD does and
## leaves the table where it is (no notice).
func test_save_on_the_table_saves_in_place() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	table.light_intensity_scale = 0.5
	assert_true(await _mover.save_changes(KEY_A))
	assert_eq(_saves, ["saved"] as Array[String])
	assert_null(_notice(), "nothing moves")


# =============================================================================
# THE SHELF ROWS IN THE ROOM PANEL
# =============================================================================


func _shelf_summary() -> Dictionary:
	return {
		"open": false,
		"table": KEY_A,
		"shelf": [
			{"folder": KEY_A, "map_path": "", "hashes": {}, "name": "Mossy Hollow"},
			{"folder": KEY_B, "map_path": "", "hashes": {}, "name": "Old Mill"},
		],
		"players": {"enet-1": {"name": "Marigold", "peer_id": 1}},
		"holdings": {},
	}


## The GM's rows say which maps changed; the selected one has its actions under it (Save into
## map only where it can be saved), and each sends its key. A player sees neither.
func test_the_shelf_rows_show_changes_and_their_actions() -> void:
	var panel := RoomPanel.new()
	panel.connect_network = false
	panel.in_drawer = true
	add_child_autofree(panel)
	panel.show_session(_shelf_summary(), "enet-1", true)
	panel.show_changes({KEY_A: true, KEY_B: false})
	var caption := func(key: String) -> String:
		var row := panel.shelf_rows.get_node("Map_%s" % key)
		return (row.find_child("Caption", true, false) as Label).text
	assert_eq(caption.call(KEY_A), "On the table · changed this session")
	assert_eq(caption.call(KEY_B), "Changed this session")
	var line := panel.shelf_rows.get_node_or_null("Changes_%s" % KEY_A)
	assert_not_null(line, "the table is selected in the drawer, its actions under it")
	assert_eq(line.get_index(), panel.shelf_rows.get_node("Map_%s" % KEY_A).get_index() + 1)
	var saved: Array[String] = []
	var discarded: Array[String] = []
	panel.save_changes_requested.connect(func(key: String) -> void: saved.append(key))
	panel.discard_changes_requested.connect(func(key: String) -> void: discarded.append(key))
	(line.find_child("SaveIntoMap", true, false) as Button).pressed.emit()
	panel.select(KEY_B)
	line = panel.shelf_rows.get_node_or_null("Changes_%s" % KEY_B)
	assert_null(line.find_child("SaveIntoMap", true, false), "no level folder: no Save into map")
	(line.find_child("DiscardChanges", true, false) as Button).pressed.emit()
	assert_eq(saved, [KEY_A] as Array[String])
	assert_eq(discarded, [KEY_B] as Array[String])
	assert_null(panel.shelf_rows.get_node_or_null("Changes_%s" % KEY_A), "one line, the selected")
	panel.show_session(_shelf_summary(), "enet-wren", false)
	assert_eq(caption.call(KEY_B), "", "a player's rows do not say")
	assert_null(panel.shelf_rows.get_node_or_null("Changes_%s" % KEY_B))


## The actions' line takes one row in the 396 drawer, and the drawer's column still fits, so
## its caption sits right under the shelf rather than pinned to the foot.
func test_the_actions_keep_the_drawer_column_fitting() -> void:
	var host := Control.new()
	host.size = Vector2(RoomDrawer.WIDTH, 900)
	add_child_autofree(host)
	var panel := RoomPanel.new()
	panel.connect_network = false
	panel.in_drawer = true
	host.add_child(panel)
	panel.size = host.size
	panel.show_session(_shelf_summary(), "enet-1", true)
	panel.show_changes({KEY_A: true})
	await wait_physics_frames(4)
	var line := panel.shelf_rows.get_node("Changes_%s" % KEY_A) as Control
	var save := line.find_child("SaveIntoMap", true, false) as Control
	var discard := line.find_child("DiscardChanges", true, false) as Control
	assert_eq(save.global_position.y, discard.global_position.y, "one row")
	assert_true(panel.drawer_rest.visible, "the column fits: the caption follows the shelf")


func test_shelf_caption_orders_its_parts() -> void:
	var caption := RoomModel.shelf_caption(false, true, "3 of 4 have it")
	assert_eq(caption, "Changed this session · 3 of 4 have it")
	assert_eq(RoomModel.shelf_caption(true, false, "3 of 4 have it"), "On the table")
	assert_eq(RoomModel.shelf_caption(false, false, ""), "")


# =============================================================================
# THE NOTICE
# =============================================================================


## The notice counts whole seconds and ends by itself.
func test_the_notice_counts_down() -> void:
	var text := TableMoveNotice.sentence(TableMoveNotice.Kind.MAP, "Old Mill")
	assert_eq(TableMoveNotice.countdown_text(text, 2.2), "Moving the table to Old Mill in 3")
	assert_eq(TableMoveNotice.countdown_text(text, 0.01), "Moving the table to Old Mill in 1")
	var notice := TableMoveNotice.create(TableMoveNotice.Kind.ROOM, "", 0.05, "Marigold")
	var fired: Array[bool] = []
	notice.elapsed.connect(func() -> void: fired.append(true))
	add_child(notice)
	assert_null(notice.stay_button, "a player cannot call it off")
	await wait_seconds(0.6)
	assert_eq(fired, [true] as Array[bool])
	assert_false(is_instance_valid(notice), "it takes itself away")


## A player's chip names who moves the table and where; a client words the host's move itself.
func test_a_players_chip_names_the_gm_and_the_destination() -> void:
	assert_eq(
		TableMoveNotice.sentence(TableMoveNotice.Kind.MAP, "Fen Crossing", "Marigold"),
		"Marigold is moving the table to Fen Crossing in {n}"
	)
	assert_eq(
		TableMoveNotice.sentence(TableMoveNotice.Kind.ROOM, "", "Marigold"),
		"Marigold is returning everyone to the room in {n}"
	)
	_mover._on_table_moving(TableMoveNotice.Kind.MAP, "Fen Crossing", 3.0)
	assert_eq(_notice().shown_text(), "The GM is moving the table to Fen Crossing in 3")
	assert_null(_notice().stay_button)
	_mover._on_table_moving(99, "Fen Crossing", 3.0)
	assert_eq(_notice().shown_text(), "The GM is moving the table to Fen Crossing in 3", "unknown")


## The count is semibold with tabular figures, so 3, 2 and 1 take one width; a long name is
## shortened with an ellipsis to keep the chip in bounds, whole in the tooltip; Stay here is
## framed at 3:1 (the track role).
func test_the_chip_keeps_its_width() -> void:
	var notice := TableMoveNotice.create(TableMoveNotice.Kind.MAP, LONG_NAME, 3.0)
	add_child_autofree(notice)
	await wait_physics_frames(1)
	var font := notice.count_label.get_theme_font(&"font") as FontVariation
	var tnum := TextServerManager.get_primary_interface().name_to_tag("tnum")
	assert_eq(font.opentype_features.get(tnum), 1)
	var size := notice.count_label.get_theme_font_size(&"font_size")
	var widths := ["1", "2", "3"].map(
		func(digit: String) -> float: return font.get_string_size(digit, 0, -1, size).x
	)
	assert_eq(widths[0], widths[2])
	assert_eq(widths[1], widths[2])
	assert_string_contains(notice.before_label.text, "…")
	assert_eq((notice.find_child("Chip", true, false) as Control).tooltip_text, LONG_NAME)
	var body := notice.before_label.get_theme_font(&"font")
	var body_size := notice.before_label.get_theme_font_size(&"font_size")
	var width := body.get_string_size(notice.before_label.text, 0, -1, body_size).x
	assert_lte(width, TableMoveNotice.MAX_SENTENCE_WIDTH)
	var box := notice.stay_button.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_eq(box.border_color, ThemeColors.of(notice.stay_button, ThemeColors.TRACK))
	assert_gt(box.border_width_left, 0)
	# A player's chip gives the GM's name way first: their first name, the map's kept longer.
	var player := TableMoveNotice.create(
		TableMoveNotice.Kind.MAP, LONG_NAME, 3.0, "Marigold Thistlewood-Ash"
	)
	add_child_autofree(player)
	await wait_physics_frames(1)
	assert_string_starts_with(player.before_label.text, "Marigold is moving the table to The")
