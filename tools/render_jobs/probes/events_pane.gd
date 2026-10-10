extends RefCounted

## Render-job probe for the GM's Events pane in play (PlayEvents, EventsPane): saves the open
## authoring map as a _gm_events_ test level, then on the table arms a play brush, holds a
## stroke of it on the board, releases it, undoes it through the live history, and stages the
## player's view. Used by jobs/events_pane.json.
##
## Actions (step "action"):
##   save        {"folder"}: the authoring map saved as that level (a _gm_events_ folder only)
##   window      {"size": "WxH"}: the window at that size, Interface size Auto for the run
##   open        the Visuals drawer open on its Events pane
##   arm         {"tool"}: PlayEvents.pick(tool id), the Sculpt tile set to "tile", the
##               brush radius to "radius" (m) and the palette's "biome"-th biome picked (its
##               tile, as a click picks it) if given
##   hover       {"at"} or {"screen"}: the brush's pointer there, not pressed (its ring)
##   press       {"at": [x, z]} or {"screen": [fx, fy]} (fractions of the board's viewport):
##               the play brush's pointer there, pressed, with "ctrl" as given (the drawer
##               steps aside, PlayEvents.stroke_started)
##   move        the pointer moved there ("at" or "screen"), still pressed
##   release     the stroke ends (recorded, sent to the table), reporting its entry's size
##   put_away    PlayEvents.put_away (Esc's path)
##   undo        PlayEvents.undo (Ctrl+Z's path), reporting the entry's size and is_large
##   redo        PlayEvents.redo (Ctrl+Y's path)
##   player      staged player's view: the brush put away, the GM's Visuals drawer concealed,
##               the GM's own HUD buttons hidden and the GM's toasts dismissed
##   dismiss     every toast on screen dismissed at once
##   cleanup     deletes every _gm_events_ level

const PREFIX := "_gm_events_"


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"save":
			return _save(base, String(step.get("folder", PREFIX + "table")))
		"cleanup":
			return _cleanup()
		"window":
			return _window(base, step.get("size", [1920, 1080]))
		"open":
			var panel := base.find_child("LevelEditPanel", true, false) as LevelEditPanel
			if panel == null:
				return "no Visuals drawer"
			if not panel.is_open or panel._rail.selected != LevelEditPanel.EVENTS_ID:
				panel._on_rail_item_pressed(LevelEditPanel.EVENTS_ID)
			return "Visuals drawer open on %s" % panel._rail.selected
	var events := _events(base)
	if events == null:
		return "no PlayEvents on the table"
	match String(step.get("action", "")):
		"arm":
			events.pick(StringName(String(step.get("tool", "sculpt"))))
			if step.has("tile") and events.brush() != null:
				SculptTool.of(events.brush()).tile = int(step.get("tile"))
			if step.has("radius") and events.brush() != null:
				events.brush().set_radius(float(step.get("radius")))
			if step.has("biome"):
				var biome := StringName(String(PaletteLibrary.biomes()[int(step.get("biome"))]["id"]))
				events.pane.biome_field.tiles.select(biome)
				if events.armed == &"":
					events._on_biome_selected(String(biome))
			return "armed %s (refusal: '%s')" % [events.armed, events.refusal()]
		"put_away":
			events.put_away()
			return "put away; armed '%s'" % events.armed
		"hover", "press", "move":
			var brush := events.brush()
			if brush == null or not brush.is_active():
				return "no brush out"
			if step.has("screen"):
				# A fraction of the board's viewport, so a point lands in view at any zoom.
				var map: GameMap = base.get("_game_map")
				var at: Array = step.get("screen")
				brush.pointer = Vector2(float(at[0]), float(at[1])) * Vector2(map.world_viewport.size)
				brush.has_pointer = true
			else:
				_point(base, brush, step.get("at", [0, 0]))
			if String(step.get("action")) == "press":
				brush.pressed = true
				brush.press_pending = true
				brush.press_ctrl = bool(step.get("ctrl", false))
				brush.press_shift = false
			return "pointer at %s" % str(brush.pointer)
		"release":
			var brush := events.brush()
			if brush == null:
				return "no brush"
			brush.pressed = false
			brush.finish_gesture()
			var stack: Array = brush.editor.history.get("_undo") if brush.editor else []
			if stack.is_empty():
				return "released, nothing recorded"
			var entry: Dictionary = stack.back()
			return (
				"released: %s, entry %d bytes, large %s"
				% [entry.get("label", ""), int(entry.get("bytes", 0)), PlayEvents.is_large(entry)]
			)
		"undo":
			var stack: Array = events.brush().editor.history.get("_undo")
			var held := int((stack.back() as Dictionary).get("bytes", 0)) if not stack.is_empty() else 0
			var large := PlayEvents.is_large(stack.back()) if not stack.is_empty() else false
			return "undone: %s (entry %d bytes, large %s)" % [events.undo(), held, large]
		"redo":
			return "redone: %s" % events.redo()
		"player":
			events.put_away()
			var panel := base.find_child("LevelEditPanel", true, false) as LevelEditPanel
			if panel != null:
				panel.close()
				panel.conceal()
			# The GM's own HUD buttons a player never has.
			for button_name in ["SaveLevelButton", "ToggleAssetBrowserButton"]:
				var button := base.find_child(button_name, true, false) as Control
				if button != null:
					button.visible = false
			# The GM's own toasts (the large edit's Undo, Undone) are not a player's.
			return "staged a player's view (%d toasts dismissed)" % _dismiss_toasts()
		"dismiss":
			return "%d toasts dismissed" % _dismiss_toasts()
	return "unknown action"


## Dismisses every toast on screen at once; returns how many.
static func _dismiss_toasts() -> int:
	var toasts: ToastContainer = UIManager.get("_toast_container")
	if toasts == null:
		return 0
	var shown: Array = toasts.get("_active_toasts").duplicate()
	for toast: Control in shown:
		toasts.call("_dismiss_toast", toast, true)
	return shown.size()


## The window at `size` ([w, h] or "WxH") with the Interface size at Auto for the run, as
## ui_primitives.gd's window step sets it (never saved).
static func _window(base: Node, size: Variant) -> String:
	var parts: PackedStringArray = (
		(size as String).split("x") if size is String else PackedStringArray([str(size[0]), str(size[1])])
	)
	var window := base.get_window()
	window.size = Vector2i(parts[0].to_int(), parts[1].to_int())
	UIManager.set("_interface_size", InterfaceSize.AUTO)
	UIManager.apply_interface_size()
	return "window %s, content scale %.2f" % [str(window.size), window.content_scale_factor]


static func _events(base: Node) -> PlayEvents:
	var map: GameMap = base.get("_game_map")
	if map == null:
		return null
	var menu := map.gameplay_menu.get_node_or_null("GameplayMenu")
	return menu.get("play_events") as PlayEvents if menu != null else null


## The brush's pointer on the ground at map point `at` ([x, z]).
static func _point(base: Node, brush: BrushTool, at: Array) -> void:
	var map: GameMap = base.get("_game_map")
	var world := Vector3(float(at[0]), 0.0, float(at[1]))
	if brush.editor != null:
		world.y = brush.editor.ground_height_at(world)
	brush.pointer = map.camera_node.unproject_position(world)
	brush.has_pointer = true


static func _save(base: Node, folder: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = "Events table"
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
