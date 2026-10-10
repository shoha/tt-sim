class_name TableMover
extends Node

## Moving the table between the session's maps, and what each map keeps of the session
## (Root's helper; docs/plans/2026-10-09-v0.2-evaluation/design/flow_recommendation_v2.md,
## "The model" and "The flow" 4). A map is a template: nothing a session does changes its level
## folder unless the GM picks Save into map. What the session did to a map (its tokens, its
## look, live terrain edits) stays with the session in `states` (TableStates) and comes back
## when the map is set out again, from the room (set_out()) or by moving the table. The
## session file (SessionKeeper) keeps `states` and the table as it stands (table_entry()), so a
## resumed session has them again.
##
## A move asks nothing (request_move(), host at a table): the table is kept as it is, and every
## peer sees the notice (TableMoveNotice, sent through SessionChannel.announce_move()) count
## NOTICE_S seconds down; the GM's Stay here calls it off for everyone, which is the move's undo
## (UI_TASTE I4). Then move_now() keeps the table and Root carries the move out: level_chosen
## with the next map's level (Root takes the party along, _on_play_level_requested), or
## room_chosen. Return everyone to the room is the same move with the room (ROOM) as the
## destination.
##
## What to do with a map's changes is the shelf's: a shelf row of a map with changes this
## session (changed_maps(): a kept state, or the table out now when it differs from its map)
## says so and offers Save into map (only for a map with a level folder here) and Discard
## changes, each behind a confirm that names its consequence (ask_save(), ask_discard()). A
## map that is not out is saved from its kept state (save_kept(): the placements and look laid
## over its template, the edited document captured when the table left) and discarded by
## forgetting it. The table that is out is saved as it stands (the HUD's save); when its terrain
## changed, the map file the table was set out from is rewritten, so the table is set out again
## from the saved map for everyone (a RELOAD move: a late joiner downloads the new file and the
## live edits' log starts from it). Discard on the table sets it out again from the map as it
## was saved (a RESET move, Stay here offered).
##
## Arriving at a map (_arrive()), its level is read from this host's library, its kept state
## is laid over it (TableStates.overlay()) and its op log handed to the table's live edits
## (LevelPlayController.replay_log), so the level broadcast, the late joiner's level snapshot
## and the log's catch-up carry the session's version of the map to every peer. The table is
## compared with the template: the look the map loaded with, and for a restored map the
## template's placements (LevelPlayController.set_saved_placements()); a save of the map moves
## the look's baseline and the terrain's (the ops before it are in the map now) with it.

## The level of the next table, for Root to set out (in the room) or move the table to.
signal level_chosen(level: LevelData)
## The table goes away and everyone returns to the room; Root opens it.
signal room_chosen
## A map's changes were kept, saved or discarded: the shelf rows read changed_maps() again.
signal changes_changed

## How the table being left is settled.
enum Choice { KEEP, SAVE, DISCARD }

## The destination of Return everyone to the room.
const ROOM := ""
## How long the notice counts down before the table moves.
const NOTICE_S := 3.0
const SAVE_TEXT := "Save into map"
const DISCARD_TEXT := "Discard changes"
## The confirms (W2: the action, then its consequence), the map's name in typographic quotes
## in the title only, so a long name is not read twice.
const SAVE_TITLE := "Save into “{map}”?"
const SAVE_MESSAGE := "Every later session sets it out as it is now."
const SAVE_RELOAD := " The table is set out again from it for everyone."
const DISCARD_TITLE := "Discard the changes to “{map}”?"
const DISCARD_MESSAGE := "It goes back to how it was saved."
## Both confirms hold the narrow sheet's width token (UI_TASTE S5).
const CONFIRM_WIDTH := 420.0
## Save into map failed (W3): what failed, why, then how to recover.
const SAVE_FAILED := "Could not save into “{map}”: {why}. {recover}"
const WHY_DOCUMENT := "its terrain file could not be written"
const WHY_LEVEL := "its map file could not be written"
const WHY_MISSING := "it is no longer in your maps folder"
const RECOVER_WRITE := (
	"Your changes are still kept. Check that your maps folder is not full or read-only, then"
	+ " try again."
)
const RECOVER_MISSING := "Your changes are still kept for this session."

## What the session keeps of each map it set out (host).
var states := TableStates.new()
## The session file of the hosted session, and Resume (a child, set up after this mover).
var keeper: SessionKeeper = null

var _controller: LevelPlayController = null
## The level _arrive() prepared, until it has loaded, with what its template had.
var _arriving: LevelData = null
var _restored := false
var _template_placements: Array = []
var _template_look: Dictionary = {}
## The look of the table's map as saved (TableStates.look_of()), for changes().
var _baseline_look: Dictionary = {}
## How many ops of the table's live edits log are in its map as saved (a save moves it).
var _terrain_base := 0
## The move counting down: {"key", "choice"}, else {}.
var _pending: Dictionary = {}
var _notice: TableMoveNotice = null
## True while save_kept() writes a map that is not the table's (its level_saved is not ours).
var _saving_elsewhere := false


## Root's table, which lives as long as Root does.
func setup(controller: LevelPlayController) -> void:
	_controller = controller
	controller.level_loaded.connect(_on_level_loaded)
	LevelManager.level_saved.connect(_on_level_saved)
	NetworkManager.session.table_moving.connect(_on_table_moving)
	NetworkManager.session.table_move_cancelled.connect(_drop_notice)
	NetworkManager.connection_state_changed.connect(_on_connection_state_changed)
	# After this mover's handler, which forgets every kept state when hosting starts; the
	# keeper's then restores a resumed session's.
	keeper = SessionKeeper.new()
	keeper.name = "SessionKeeper"
	add_child(keeper)
	keeper.setup(self)


## Root leaves the table (PLAYING): the session file keeps it as it stands first (the host
## ending the session here; a move has kept it already), and a move counting down goes with it.
func table_closing() -> void:
	if keeper:
		keeper.save_now(true)
	cancel()


## A room panel (the room's or the drawer's, Root's) shows the changed maps: it reads them
## from changed_maps() on each refresh and again whenever they change, and its rows' Save into
## map and Discard changes come here.
func attach_panel(panel: RoomPanel) -> void:
	panel.changes_source = changed_maps
	panel.save_changes_requested.connect(ask_save)
	panel.discard_changes_requested.connect(ask_discard)
	if panel.connect_network:
		changes_changed.connect(panel.refresh)
		panel.refresh()


# =============================================================================
# READ
# =============================================================================


## What differs between the table and its map: {"tokens", "look", "terrain"}, each true when
## that changed this session (the tokens a save writes, the Visuals drawer's look, the live
## edits' ops since the map was last saved). All false with no table. With `settle` the live
## edits' recorded entries become ops first (their height work finished at once); without it
## (a shelf row's read, which may come mid-stroke) an edit not yet sent counts as a change.
func changes(settle := true) -> Dictionary:
	var level: LevelData = _controller.active_level_data if _controller else null
	if level == null:
		return {"tokens": false, "look": false, "terrain": false}
	var edits := _controller.live_edits
	var gm_edits := is_instance_valid(edits) and edits.sends
	if gm_edits and settle:
		edits.send_now()
	var terrain := gm_edits and (edits.op_log.size() > _terrain_base or not edits.is_settled())
	return {
		"tokens": _controller.has_unsaved_tokens(),
		"look": TableStates.look_of(level) != _baseline_look,
		"terrain": terrain,
	}


## The shelf maps with changes this session (host): shelf key -> true when Save into map is
## offered for it (can_save()). Every map with a kept state, and the map on the table when it
## differs from its map now (changes()); the table's kept state is in the table.
func changed_maps() -> Dictionary:
	var out := {}
	for key: String in states.keys():
		out[key] = can_save(key)
	var table := NetworkManager.session.get_table() if NetworkManager.is_host() else ""
	if table != "" and _controller and _controller.active_level_data != null:
		out.erase(table)
		if not _controller.is_loading() and changes(false).values().has(true):
			out[table] = can_save(table)
	return out


## True when the shelf map `key` can be saved into: it has a level folder in this host's
## library.
func can_save(key: String) -> bool:
	var folder := _shelf_folder(key)
	return folder != "" and FileAccess.file_exists(LevelManager.json_path(folder))


## The table's state as it stands, for the session file (SessionKeeper): null when there is no
## table to read (none out, or one loading), {} when it is as its map, else capture()'s entry
## with the ops since its map was last saved and, when the terrain changed on a map with a
## level folder, the edited document if the editor has settled (none this time otherwise).
## With `settle` (the session ends at this table) the recorded entries become ops first.
func table_entry(settle := false) -> Variant:
	var key := NetworkManager.session.get_table()
	var level: LevelData = _controller.active_level_data if _controller else null
	if key == "" or level == null or _controller.is_loading():
		return null
	var edits := _controller.live_edits
	var gm_edits := is_instance_valid(edits) and edits.sends
	if gm_edits and settle:
		edits.send_now()
	var changed := changes(false)
	if not changed.values().has(true):
		return {}
	var ops: Array[PackedByteArray] = []
	if gm_edits:
		ops.assign(edits.op_log.slice(_terrain_base))
	var entry := TableStates.capture(level, _controller.spawned_tokens, ops)
	if changed.terrain and gm_edits and can_save(key) and edits.is_settled():
		var scatter := edits.editor.scatter
		if not (is_instance_valid(scatter) and scatter.is_regenerating()):
			entry["document"] = document_of(edits.editor)
	return entry


## True while a move counts down.
func is_moving() -> bool:
	return not _pending.is_empty()


## The confirm's message for Save into map (the title names the map), and that the table is
## set out again when `reloads`. Pure.
static func save_message(reloads: bool) -> String:
	return SAVE_MESSAGE + (SAVE_RELOAD if reloads else "")


## What Save into map says when it failed: the map, why (a WHY_ constant) and how to recover.
## Pure.
static func save_error(map_name: String, why: String, recover := RECOVER_WRITE) -> String:
	return SAVE_FAILED.format({"map": map_name, "why": why, "recover": recover})


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


## Host, at a table: move the table to the shelf map `key`, or to the room (ROOM), keeping the
## table as it is: the move counts down on every peer, and Stay here calls it off. Nothing
## happens while another move is under way, while a map loads, or to the map already on the
## table.
func request_move(key: String) -> void:
	if not _can_move() or (key != ROOM and key == NetworkManager.session.get_table()):
		return
	_count_down(TableMoveNotice.Kind.ROOM if key == ROOM else TableMoveNotice.Kind.MAP, key)


## Calls off the move counting down (Stay here, or the table went away first) for every
## peer, and closes the notice this peer shows.
func cancel() -> void:
	_drop_notice()
	if _pending.is_empty():
		return
	_pending = {}
	NetworkManager.session.cancel_move()


## Host: settle the table as `choice` says and move it to the shelf map `key` or the room, at
## once (the end of the notice; the net scenarios call it directly). `key` may be the map on
## the table, which sets it out again. Returns false, the table left as it is, when the map is
## not in this host's library or Save into map failed.
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


func _can_move() -> bool:
	if not NetworkManager.is_host() or is_moving() or _controller == null:
		return false
	return _controller.active_level_data != null and not _controller.is_loading()


func _count_down(kind: TableMoveNotice.Kind, key: String, choice := Choice.KEEP) -> void:
	_pending = {"key": key, "choice": choice}
	var map_name := "" if key == ROOM else _shelf_name(key)
	NetworkManager.session.announce_move(kind, map_name, NOTICE_S)
	_show_notice(kind, map_name, NOTICE_S, "")


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
			var changed := changes()
			if changed.values().has(true):
				states.store(key, await _capture(level, changed.terrain and can_save(key)))
			else:
				states.erase(key)
	changes_changed.emit()
	return true


## The table's state to keep (TableStates.capture()): the ops since its map was last saved,
## and with `with_document` the edited document as it stands, for a later Save into map from
## the shelf (the map is no longer out to save from).
func _capture(level: LevelData, with_document: bool) -> Dictionary:
	var edits := _controller.live_edits
	var ops: Array[PackedByteArray] = []
	if is_instance_valid(edits) and edits.sends:
		ops.assign(edits.op_log.slice(_terrain_base))
	var document: MapDocument = null
	if with_document:
		document = await _settled_document()
	var entry := TableStates.capture(level, _controller.spawned_tokens, ops)
	if document != null:
		entry["document"] = document
	return entry


# =============================================================================
# SAVE INTO MAP AND DISCARD CHANGES (the shelf rows)
# =============================================================================


## Host: ask to save the shelf map `key`'s changes into it (the row's Save into map), with a
## confirm that names the consequence. Returns the confirm, or null when it cannot be saved.
func ask_save(key: String) -> ConfirmationDialogUI:
	if not NetworkManager.is_host() or is_moving() or not can_save(key):
		return null
	var map_name := _shelf_name(key)
	var reloads := _on_table(key) and bool(changes().terrain)
	var dialog := (
		UIManager.show_confirmation(
			SAVE_TITLE.format({"map": map_name}),
			save_message(reloads),
			SAVE_TEXT,
			"Cancel",
			save_changes.bind(key),
		)
		as ConfirmationDialogUI
	)
	dialog.hold_width(CONFIRM_WIDTH)
	return dialog


## Host: ask to discard the shelf map `key`'s changes (the row's Discard changes), a danger
## confirm with the action set apart at the left and Cancel focused. Returns the confirm.
func ask_discard(key: String) -> ConfirmationDialogUI:
	if not NetworkManager.is_host() or is_moving():
		return null
	var map_name := _shelf_name(key)
	var dialog := (
		UIManager.show_confirmation(
			DISCARD_TITLE.format({"map": map_name}),
			DISCARD_MESSAGE,
			DISCARD_TEXT,
			"Cancel",
			discard_changes.bind(key),
			Callable(),
			"Danger",
		)
		as ConfirmationDialogUI
	)
	dialog.hold_width(CONFIRM_WIDTH)
	dialog.set_confirm_apart()
	return dialog


## Host: save the shelf map `key`'s changes into it now. The table that is out is saved as it
## stands, and set out again from the saved map when its terrain was written; a map that is
## not out is saved from its kept state (save_kept()). False when nothing was saved.
func save_changes(key: String) -> bool:
	if not _on_table(key):
		return save_kept(key)
	var reloads := bool(changes().terrain)
	if not await _save_into_map():
		return false
	states.erase(key)
	changes_changed.emit()
	if reloads and _can_move():
		_count_down(TableMoveNotice.Kind.RELOAD, key)
	return true


## Host: forget the shelf map `key`'s changes, so it comes back as it was saved. On the table
## that is out, the table is set out again from its map for everyone, after the notice.
func discard_changes(key: String) -> void:
	if _on_table(key):
		if _can_move():
			_count_down(TableMoveNotice.Kind.RESET, key, Choice.DISCARD)
		return
	states.erase(key)
	changes_changed.emit()
	UIManager.show_success("Discarded the changes to “%s”" % _shelf_name(key))


## Host: write the kept state of the shelf map `key`, which is not out, into its level folder:
## the edited document captured when the table left (when its terrain changed), then the level
## with the kept placements and look laid over its template. The thumbnail stays as it was.
## Says how it went; false (the state still kept) when it did not save.
func save_kept(key: String) -> bool:
	var entry := states.entry_for(key)
	var map_name := _shelf_name(key)
	if entry.is_empty():
		return false
	var held := [LevelManager.current_level, LevelManager.current_level_path]
	var level := LevelManager.load_level_folder(_shelf_folder(key), false) if can_save(key) else null
	var why := _write_kept(level, entry) if level != null else WHY_MISSING
	LevelManager.current_level = held[0]
	LevelManager.current_level_path = held[1]
	if why != "":
		var recover := RECOVER_MISSING if why == WHY_MISSING else RECOVER_WRITE
		UIManager.show_error(save_error(map_name, why, recover))
		return false
	states.erase(key)
	changes_changed.emit()
	UIManager.show_success("Saved into “%s”" % map_name)
	return true


## Writes `entry` into `level` (its template, just read) and its folder; "" when it did, else
## why not (a WHY_ constant).
func _write_kept(level: LevelData, entry: Dictionary) -> String:
	var document := entry.get("document") as MapDocument
	if not TableStates.op_log_of(entry).is_empty():
		if document == null or level.map_document == "":
			return WHY_DOCUMENT
		var path := LevelManager.map_document_path(level.level_folder)
		if MapDocumentIO.write(document, path) != OK:
			return WHY_DOCUMENT
	TableStates.overlay(level, entry)
	_saving_elsewhere = true
	var saved := LevelManager.save_level_folder(level)
	_saving_elsewhere = false
	return "" if saved != "" else WHY_LEVEL


## Save into map for the table that is out: when the terrain changed, the edited map document
## goes to map.ttmap first (MapDocumentIO.write, the writer of authoring's save, with the
## scatter and props as they stand once any regrowth has landed); then the tokens and the look
## go into the level as the play HUD's Save map writes them. Says how it went; false when it
## did not save.
func _save_into_map() -> bool:
	var level := _controller.active_level_data
	var edits := _controller.live_edits
	if changes().terrain:
		var document := await _settled_document()
		var written := (
			document != null
			and level.level_folder != ""
			and level.map_document != ""
			and (
				MapDocumentIO.write(document, LevelManager.map_document_path(level.level_folder))
				== OK
			)
		)
		if not written:
			UIManager.show_error(save_error(level.level_name, WHY_DOCUMENT))
			return false
		_terrain_base = edits.op_log.size()
	if _controller.save_level_with_thumbnail() == "":
		UIManager.show_error(save_error(level.level_name, WHY_LEVEL))
		return false
	UIManager.show_success("Saved into “%s”" % level.level_name)
	return true


## The table's edited document with its scatter and props rows as they stand once the
## editor's height work and any regrowth have landed (document_of()), or null with no live
## edits on this side or when the table went away meanwhile.
func _settled_document() -> MapDocument:
	var level := _controller.active_level_data
	var edits := _controller.live_edits
	if not is_instance_valid(edits) or not edits.sends:
		return null
	var editor := edits.editor
	editor.finish_height_work()
	while is_instance_valid(editor.scatter) and editor.scatter.is_regenerating():
		await get_tree().process_frame
	if not is_instance_valid(edits) or level != _controller.active_level_data:
		return null
	return document_of(editor)


## `editor`'s document with its scatter and props rows as they stand.
static func document_of(editor: AuthoringEditor) -> MapDocument:
	var doc := editor.document
	if is_instance_valid(editor.scatter) and is_instance_valid(editor.props):
		doc.scatter = editor.scatter.rows_by_asset()
		doc.props = editor.props.rows_by_asset()
	return doc


## Writes `editor`'s document, with its scatter and props rows as they stand, to `level`'s
## map.ttmap. False for a level without a folder or a document, or when the write failed.
static func write_document(editor: AuthoringEditor, level: LevelData) -> bool:
	if level.level_folder == "" or level.map_document == "":
		return false
	var path := LevelManager.map_document_path(level.level_folder)
	return MapDocumentIO.write(document_of(editor), path) == OK


# =============================================================================
# THE SHELF
# =============================================================================


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


## True when the shelf map `key` is the one on the table now.
func _on_table(key: String) -> bool:
	return (
		key != ""
		and key == NetworkManager.session.get_table()
		and _controller != null
		and _controller.active_level_data != null
	)


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


## The level folder of the shelf map `key`, or "".
func _shelf_folder(key: String) -> String:
	for ref in NetworkManager.session.get_shelf():
		if SessionChannel.ref_key(ref) == key:
			return str(ref.get("folder", ""))
	return ""


## The name of the shelf map `key`, for the notice and the confirms.
func _shelf_name(key: String) -> String:
	for ref in NetworkManager.session.get_shelf():
		if SessionChannel.ref_key(ref) == key and str(ref.get("name", "")) != "":
			return str(ref.name)
	return "the next map"


# =============================================================================
# THE NOTICE AND THE BASELINE
# =============================================================================


## Shows the notice for a move of `kind` to `map_name`: the GM's own (`mover` "", with Stay
## here except for a RELOAD, which follows a save already made) or a player's naming `mover`.
func _show_notice(
	kind: TableMoveNotice.Kind, map_name: String, seconds: float, mover: String
) -> void:
	_drop_notice()
	var own := mover == ""
	var can_cancel := own and kind != TableMoveNotice.Kind.RELOAD
	_notice = TableMoveNotice.create(kind, map_name, seconds, mover, can_cancel)
	if own:
		_notice.elapsed.connect(_on_notice_elapsed)
		_notice.cancelled.connect(cancel)
	add_child(_notice)


## A client: the host announced a move (the kind and name are untrusted; an unknown kind is
## worded as a move to a map).
func _on_table_moving(kind: int, map_name: String, seconds: float) -> void:
	var move: int = kind if TableMoveNotice.Kind.values().has(kind) else TableMoveNotice.Kind.MAP
	var gm := RoomModel.gm_name(RoomModel.players(NetworkManager.session.summary(), ""))
	var mover := gm if gm != "" else TableMoveNotice.SOMEONE
	_show_notice(move as TableMoveNotice.Kind, map_name, seconds, mover)


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
	_terrain_base = 0
	_arriving = null
	_template_placements = []


## A save writes the table's look into its map, so the map now looks like the table.
func _on_level_saved(_path: String) -> void:
	if _saving_elsewhere:
		return
	if _controller and _controller.active_level_data != null:
		_baseline_look = TableStates.look_of(_controller.active_level_data)


## A session began or ended: no map keeps anything from another session.
func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	if new_state != NetworkManager.ConnectionState.CONNECTING:
		states.clear()
		changes_changed.emit()
	if new_state == NetworkManager.ConnectionState.OFFLINE:
		cancel()
