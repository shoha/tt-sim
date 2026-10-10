class_name TableMover
extends Node

## Moving the table between the session's maps, and what each map keeps of the session
## (Root's helper; docs/plans/2026-10-09-v0.2-evaluation/design/flow_recommendation_v2.md,
## "The model" and "The flow" 4). A map is a template: nothing a session does changes its level
## folder unless the GM picks Save into map. What the session did to a map (its tokens, its
## look, live terrain edits) stays with the session in `states` (TableStates) and comes back
## when the map is set out again, from the room (set_out()) or by moving the table.
##
## A move is one calm operation (request_move(), host at a table). When the table differs
## from its map (changes()), the GM is asked once: Keep for this session (the default and
## focused), Save into map or Discard, and Escape stays. Then every peer sees the notice
## (TableMoveNotice, sent through SessionChannel.announce_move()) count NOTICE_S seconds down;
## the GM's Stay here calls it off for everyone, which is the move's undo (UI_TASTE I4). Then
## move_now() settles the table as chosen and Root carries the move out: level_chosen with the
## next map's level (Root takes the party along, _on_play_level_requested), or room_chosen.
## Return everyone to the room is the same move with the room (ROOM) as the destination.
##
## Arriving at a map (_arrive()), its level is read from this host's library, its kept state
## is laid over it (TableStates.overlay()) and its op log handed to the table's live edits
## (LevelPlayController.replay_log), so the level broadcast, the late joiner's level snapshot
## and the log's catch-up carry the session's version of the map to every peer. The table is
## compared with the template: the look the map loaded with, and for a restored map the
## template's placements (LevelPlayController.set_saved_placements()); a save of the map moves
## the look's baseline with it (the token baseline moves itself).

## The level of the next table, for Root to set out (in the room) or move the table to.
signal level_chosen(level: LevelData)
## The table goes away and everyone returns to the room; Root opens it.
signal room_chosen

## How the table being left is settled.
enum Choice { KEEP, SAVE, DISCARD }

## The destination of Return everyone to the room.
const ROOM := ""
## How long the notice counts down before the table moves.
const NOTICE_S := 3.0
const KEEP_TEXT := "Keep for this session"
const SAVE_TEXT := "Save into map"
const DISCARD_TEXT := "Discard"
const DOCUMENT_ERROR := "Could not save the terrain into the map: its file was not written."

## What the session keeps of each map it set out (host).
var states := TableStates.new()

var _controller: LevelPlayController = null
## The level _arrive() prepared, until it has loaded, with what its template had.
var _arriving: LevelData = null
var _restored := false
var _template_placements: Array = []
var _template_look: Dictionary = {}
## The look of the table's map as saved (TableStates.look_of()), for changes().
var _baseline_look: Dictionary = {}
## The move counting down: {"key", "choice"}, else {}.
var _pending: Dictionary = {}
var _notice: TableMoveNotice = null
var _prompt: Node = null


## Root's table, which lives as long as Root does.
func setup(controller: LevelPlayController) -> void:
	_controller = controller
	controller.level_loaded.connect(_on_level_loaded)
	LevelManager.level_saved.connect(_on_level_saved)
	NetworkManager.session.table_moving.connect(_on_table_moving)
	NetworkManager.session.table_move_cancelled.connect(_drop_notice)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)


# =============================================================================
# READ
# =============================================================================


## What differs between the table and its map: {"tokens", "look", "terrain"}, each true when
## that changed this session (the tokens a save writes, the Visuals drawer's look, the live
## edits' log). All false with no table.
func changes() -> Dictionary:
	var level: LevelData = _controller.active_level_data if _controller else null
	if level == null:
		return {"tokens": false, "look": false, "terrain": false}
	var edits := _controller.live_edits
	var gm_edits := is_instance_valid(edits) and edits.sends
	if gm_edits:
		edits.send_now()
	return {
		"tokens": _controller.has_unsaved_tokens(),
		"look": TableStates.look_of(level) != _baseline_look,
		"terrain": gm_edits and not edits.op_log.is_empty(),
	}


## True while a move is being asked about or counting down.
func is_moving() -> bool:
	return not _pending.is_empty() or is_instance_valid(_prompt)


## The prompt's title for leaving the map named `map_name`. Pure.
static func prompt_title(map_name: String) -> String:
	return "Keep the changes to %s?" % map_name


## The prompt's message for `changed` (changes()' shape): what changed, then the three ways
## to settle it. Pure.
static func prompt_message(changed: Dictionary) -> String:
	var parts: Array[String] = []
	for item in [["tokens", "the tokens"], ["look", "the look"], ["terrain", "the terrain"]]:
		if bool(changed.get(item[0], false)):
			parts.append(item[1])
	var what := ""
	if parts.size() > 1:
		what = ", ".join(PackedStringArray(parts.slice(0, -1))) + " and " + str(parts.back())
	elif parts.size() == 1:
		what = parts[0]
	else:
		what = "the map"
	return (
		"%s%s changed this session. Keep the changes for when the table comes back, save them "
		% [what.left(1).to_upper(), what.substr(1)]
		+ "into the map, or discard them."
	)


# =============================================================================
# MOVING
# =============================================================================


## Host, in the room: set the shelf map `key` out with what this session kept of it.
func set_out(key: String) -> void:
	if not NetworkManager.is_host():
		return
	var level := _load_shelf_map(key)
	if level != null:
		_arrive(key, level)
		level_chosen.emit(level)


## Host, at a table: move the table to the shelf map `key`, or to the room (ROOM). Asks how to
## settle the table when it differs from its map, then counts the move down on every peer.
## Nothing happens while another move is under way, while a map loads, or to the map already
## on the table.
func request_move(key: String) -> void:
	if not NetworkManager.is_host() or is_moving() or _controller == null:
		return
	if _controller.active_level_data == null or _controller.is_loading():
		return
	if key != ROOM and key == NetworkManager.session.get_table():
		return
	var changed := changes()
	if changed.values().has(true):
		_prompt = _ask(changed, key)
	else:
		_count_down(Choice.KEEP, key)


## Calls off the move counting down (Stay here, or the table went away first) for every
## peer, and closes the prompt or the notice this peer shows.
func cancel() -> void:
	if is_instance_valid(_prompt):
		_prompt.queue_free()
	_prompt = null
	_drop_notice()
	if _pending.is_empty():
		return
	_pending = {}
	NetworkManager.session.cancel_move()


## Host: settle the table as `choice` says and move it to the shelf map `key` or the room, at
## once (the end of the notice; the net scenarios call it directly). Returns false, the table
## left as it is, when the map is not in this host's library or Save into map failed.
func move_now(key: String, choice: Choice = Choice.KEEP) -> bool:
	if not NetworkManager.is_host():
		return false
	var level: LevelData = null
	if key != ROOM:
		level = _load_shelf_map(key)
		if level == null:
			return false
	if not await _leave_table(choice):
		return false
	if key == ROOM:
		room_chosen.emit()
	else:
		_arrive(key, level)
		level_chosen.emit(level)
	return true


## The three-way prompt, Keep for this session focused (Escape: stay). Save into map only for
## a map in the library (a level folder to write).
func _ask(changed: Dictionary, key: String) -> Node:
	var level := _controller.active_level_data
	var dialog: ConfirmationDialogUI = UIManager.show_confirmation(
		prompt_title(level.level_name),
		prompt_message(changed),
		KEEP_TEXT,
		"",
		_count_down.bind(Choice.KEEP, key),
	)
	dialog.cancel_button.hide()
	dialog.add_alternate_action(DISCARD_TEXT, _count_down.bind(Choice.DISCARD, key))
	if level.level_folder != "":
		dialog.add_alternate_action(SAVE_TEXT, _count_down.bind(Choice.SAVE, key))
	return dialog


func _count_down(choice: Choice, key: String) -> void:
	_prompt = null
	_pending = {"key": key, "choice": choice}
	var text := (
		TableMoveNotice.ROOM_TEXT if key == ROOM else TableMoveNotice.moving_text(_shelf_name(key))
	)
	NetworkManager.session.announce_move(text, NOTICE_S)
	_show_notice(text, NOTICE_S, true)


func _on_notice_elapsed() -> void:
	_notice = null
	var pending := _pending
	_pending = {}
	if not pending.is_empty():
		move_now(pending.key, pending.choice)


## Settles the table on the table pointer before it goes: kept (stored when it differs from
## its map, else forgotten), saved into its map (and forgotten), or discarded (forgotten, so the
## template comes back next time). False when Save into map failed.
func _leave_table(choice: Choice) -> bool:
	var key := NetworkManager.session.get_table()
	var level := _controller.active_level_data
	if key == "" or level == null:
		return true
	match choice:
		Choice.SAVE:
			if not await _save_into_map():
				return false
			states.erase(key)
		Choice.DISCARD:
			states.erase(key)
		_:
			if changes().values().has(true):
				var edits := _controller.live_edits
				var ops: Array[PackedByteArray] = []
				if is_instance_valid(edits) and edits.sends:
					ops = edits.op_log
				states.store(key, TableStates.capture(level, _controller.spawned_tokens, ops))
			else:
				states.erase(key)
	return true


## Save into map: when the terrain changed, the edited map document goes to map.ttmap first
## (MapDocumentIO.write, the writer of authoring's save, with the scatter and props as they
## stand once any regrowth has landed); then the tokens and the look go into the level as the
## play HUD's Save map writes them. Says how it went; false when it did not save.
func _save_into_map() -> bool:
	var level := _controller.active_level_data
	var edits := _controller.live_edits
	if is_instance_valid(edits) and edits.sends and not edits.op_log.is_empty():
		var editor := edits.editor
		editor.finish_height_work()
		while is_instance_valid(editor.scatter) and editor.scatter.is_regenerating():
			await get_tree().process_frame
		if not is_instance_valid(edits) or level != _controller.active_level_data:
			return false
		if not write_document(editor, level):
			UIManager.show_error(DOCUMENT_ERROR)
			return false
	if _controller.save_level_with_thumbnail() == "":
		UIManager.show_error(
			preload("res://scenes/states/playing/gameplay_menu_controller.gd").SAVE_ERROR
		)
		return false
	UIManager.show_success("Saved into %s" % level.level_name)
	return true


## Writes `editor`'s document, with its scatter and props rows as they stand, to `level`'s
## map.ttmap. False for a level without a folder or a document, or when the write failed.
static func write_document(editor: AuthoringEditor, level: LevelData) -> bool:
	if level.level_folder == "" or level.map_document == "":
		return false
	var doc := editor.document
	if is_instance_valid(editor.scatter) and is_instance_valid(editor.props):
		doc.scatter = editor.scatter.rows_by_asset()
		doc.props = editor.props.rows_by_asset()
	return MapDocumentIO.write(doc, LevelManager.map_document_path(level.level_folder)) == OK


## Lays map `key`'s kept state over `level` (its template, just read) and keeps what the
## template had, for the baseline once it has loaded.
func _arrive(key: String, level: LevelData) -> void:
	var entry := states.entry_for(key)
	_arriving = level
	_restored = not entry.is_empty()
	_template_placements = level.token_placements.duplicate()
	_template_look = TableStates.look_of(level)
	TableStates.overlay(level, entry)
	_controller.replay_log = TableStates.op_log_of(entry)


## The level of the shelf map `key` from this host's library, or null (with the reason shown)
## when it is not on the shelf or has no level folder here.
func _load_shelf_map(key: String) -> LevelData:
	for ref in NetworkManager.session.get_shelf():
		if SessionChannel.ref_key(ref) != key:
			continue
		var folder := str(ref.get("folder", ""))
		var level := LevelManager.load_level_folder(folder, false) if folder != "" else null
		if level == null:
			UIManager.show_error("That map is not in your library")
		return level
	UIManager.show_error("That map is not on the shelf")
	return null


## The name of the shelf map `key`, for the notice.
func _shelf_name(key: String) -> String:
	for ref in NetworkManager.session.get_shelf():
		if SessionChannel.ref_key(ref) == key and str(ref.get("name", "")) != "":
			return str(ref.name)
	return "the next map"


# =============================================================================
# THE NOTICE AND THE BASELINE
# =============================================================================


func _show_notice(text: String, seconds: float, can_cancel: bool) -> void:
	_drop_notice()
	_notice = TableMoveNotice.create(text, seconds, can_cancel)
	if can_cancel:
		_notice.elapsed.connect(_on_notice_elapsed)
		_notice.cancelled.connect(cancel)
	add_child(_notice)


## A client: the host announced a move.
func _on_table_moving(text: String, seconds: float) -> void:
	_show_notice(text, seconds, false)


func _drop_notice() -> void:
	if is_instance_valid(_notice):
		_notice.dismiss()
	_notice = null


func _on_level_loaded(level: LevelData) -> void:
	if level == _arriving and _restored:
		_controller.set_saved_placements(_template_placements)
		_baseline_look = _template_look
	else:
		_baseline_look = TableStates.look_of(level)
	_arriving = null
	_template_placements = []


## A save writes the table's look into its map, so the map now looks like the table.
func _on_level_saved(_path: String) -> void:
	if _controller and _controller.active_level_data != null:
		_baseline_look = TableStates.look_of(_controller.active_level_data)


## A session began or ended: no map keeps anything from another session.
func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	if new_state != NetworkManager.ConnectionState.CONNECTING:
		states.clear()
	if new_state == NetworkManager.ConnectionState.OFFLINE:
		cancel()
