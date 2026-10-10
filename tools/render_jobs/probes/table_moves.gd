extends RefCounted

## Render-job probe for the table moves (TableMover): saves the open authoring map as a
## _table_moves_ test level, then on the table stages the move's notice, as the GM sees it
## (with Stay here) and as a player does, and the three-way prompt for leaving a changed
## table. Used by jobs/table_moves.json. Staged: the table is played solo, so the notice and
## the prompt are shown the way TableMover shows them in a session, without hosting.
##
## Actions (step "action"):
##   save     {"folder", "name"}: the authoring map saved as that level (a _table_moves_ folder)
##   window   {"size": "WxH"}: the window at that size, Interface size Auto for the run
##   notice   {"to": map name, or "room": true; "player": true for a player's chip}: the
##            notice counting down TableMover.NOTICE_S
##   prompt   {"tokens", "look", "terrain"}: the prompt for leaving the table with those changed
##   close    the notice or the prompt taken away
##   cleanup  deletes every _table_moves_ level

const PREFIX := "_table_moves_"


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"save":
			return _save(base, String(step.get("folder", PREFIX + "table")), step)
		"cleanup":
			return _cleanup()
		"window":
			return _window(base, step.get("size", "1920x1080"))
	var mover := base.get("_table_mover") as TableMover
	if mover == null:
		return "no TableMover"
	match String(step.get("action", "")):
		"notice":
			var text := (
				TableMoveNotice.ROOM_TEXT
				if bool(step.get("room", false))
				else TableMoveNotice.moving_text(String(step.get("to", "Fen Crossing")))
			)
			mover.call("_show_notice", text, TableMover.NOTICE_S, not bool(step.get("player", false)))
			return "notice: %s" % text
		"prompt":
			var changed := {
				"tokens": bool(step.get("tokens", true)),
				"look": bool(step.get("look", false)),
				"terrain": bool(step.get("terrain", true)),
			}
			var dialog: Node = mover.call("_ask", changed, "_table_moves_elsewhere")
			mover.set("_prompt", dialog)
			return "prompt: %s" % TableMover.prompt_message(changed)
		"close":
			mover.cancel()
			for child in base.get_tree().root.get_children():
				if child is ConfirmationDialogUI:
					child.queue_free()
			return "closed"
	return "unknown action"


## The window at `size` ("WxH") with the Interface size at Auto for the run, as
## ui_primitives.gd's window step sets it (never saved).
static func _window(base: Node, size: Variant) -> String:
	var parts := String(size).split("x")
	var window := base.get_window()
	window.size = Vector2i(parts[0].to_int(), parts[1].to_int())
	UIManager.set("_interface_size", InterfaceSize.AUTO)
	UIManager.apply_interface_size()
	return "window %s, content scale %.2f" % [str(window.size), window.content_scale_factor]


static func _save(base: Node, folder: String, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = String(step.get("name", "Old Mill"))
	saved.level_folder = folder
	ctrl.call("_sync_document")
	return "saved %s: %s" % [folder, str(AuthoringController.write_level(saved, ctrl.document, null))]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
