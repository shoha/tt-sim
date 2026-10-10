extends GutTest

## TableMover and TableStates, the table moves and per-map session state: what a table had
## become is kept by shelf key and laid over the map's template when it is set out again
## (tokens, look, op log); the GM is asked Keep for this session, Save into map or Discard
## only when the table changed; Save into map writes the level and the edited document;
## Discard brings the template back; the party is never part of a map's state.
## tests/net/enet_session_room.gd drives the whole move between real peers.

const KEY_A := "_table_moves_a"
const KEY_B := "_table_moves_b"
const DOC_FOLDER := "_table_moves_doc"

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
	_remove_doc_folder()


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


func _remove_doc_folder() -> void:
	var path := LevelManager.map_document_path(DOC_FOLDER)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(LevelManager.folder_path(DOC_FOLDER).trim_suffix("/"))


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


## Save into map writes the level through the play HUD's save and forgets the kept state; a
## save that fails keeps the table where it is.
func test_save_into_map_writes_the_level() -> void:
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
# THE MOVE
# =============================================================================


## An unchanged table moves without a question: the notice counts down, with Stay here.
func test_an_unchanged_table_moves_without_asking() -> void:
	_on_table(_template(KEY_A))
	_mover.request_move(KEY_B)
	assert_eq(_dialogs().size(), 0, "no prompt")
	var notice := _notice()
	assert_not_null(notice)
	assert_true(_mover.is_moving())
	assert_eq(notice.label.text, "Moving the table to Table Moves B in 3")
	assert_not_null(notice.stay_button)
	assert_eq(notice.stay_button.text, TableMoveNotice.STAY_HERE)
	notice.stay_button.pressed.emit()
	assert_false(_mover.is_moving(), "Stay here calls it off")


## A changed table asks once, with three verbs, Keep for this session the confirm (focused)
## and no Cancel button (Escape stays); Keep then counts the move down.
func test_a_changed_table_asks_keep_save_or_discard() -> void:
	var table := _template(KEY_A)
	_on_table(table)
	table.light_intensity_scale = 0.5
	_mover.request_move(TableMover.ROOM)
	var dialogs := _dialogs()
	assert_eq(dialogs.size(), 1)
	var dialog := dialogs[0]
	assert_eq(dialog.title_label.text, "Keep the changes to Table Moves A?")
	assert_string_contains(dialog.message_label.text, "The look changed this session.")
	assert_eq(dialog.confirm_button.text, TableMover.KEEP_TEXT)
	assert_eq(dialog.confirm_button.theme_type_variation, &"Primary")
	assert_false(dialog.cancel_button.visible)
	var row := dialog.confirm_button.get_parent()
	var verbs: Array = row.get_children().filter(func(b: Node) -> bool: return b.visible).map(
		func(b: Node) -> String: return (b as Button).text
	)
	assert_eq(verbs, [TableMover.DISCARD_TEXT, TableMover.SAVE_TEXT, TableMover.KEEP_TEXT])
	assert_true(_mover.is_moving())
	dialog.confirm_button.pressed.emit()
	assert_not_null(_notice())
	assert_eq(_notice().label.text, TableMoveNotice.ROOM_TEXT + " in 3")


## The message names what changed.
func test_the_prompt_names_what_changed() -> void:
	assert_eq(
		TableMover.prompt_message({"tokens": true, "look": false, "terrain": true}).get_slice(".", 0),
		"The tokens and the terrain changed this session"
	)
	assert_eq(
		TableMover.prompt_message({"tokens": true, "look": true, "terrain": true}).get_slice(".", 0),
		"The tokens, the look and the terrain changed this session"
	)


## The notice counts whole seconds and ends by itself.
func test_the_notice_counts_down() -> void:
	assert_eq(TableMoveNotice.countdown_text("Go", 2.2), "Go in 3")
	assert_eq(TableMoveNotice.countdown_text("Go", 0.01), "Go in 1")
	var notice := TableMoveNotice.create("Go", 0.05, false)
	var fired: Array[bool] = []
	notice.elapsed.connect(func() -> void: fired.append(true))
	add_child(notice)
	assert_null(notice.stay_button, "a player cannot call it off")
	await wait_seconds(0.6)
	assert_eq(fired, [true] as Array[bool])
	assert_false(is_instance_valid(notice), "it takes itself away")
