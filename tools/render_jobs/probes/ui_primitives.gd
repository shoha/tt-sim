extends RefCounted

## Render-job probe (`call` op) for UI captures: the primitive fixes of card U1
## (jobs/ui_primitives_look.json) and the UI tour (jobs/ui_tour.json), which takes every top
## screen at each window size for the tt-sim-ui-critic agent. `action`:
## - `settings` (`section`, optional): open Settings (UIManager.open_settings) when
##   it is not open, then select that rail section.
## - `foldout` (`expanded`, default true): expand or collapse the first Foldout on
##   the open Settings menu's current section.
## - `close_settings`: close the open Settings menu (its own animate_out).
## - `report`: the open Settings menu's rail underline against its selected item's
##   centre and the visible Foldout's chevron rect against its title; the input
##   hint bar's rect against the window and its chip keys.
## - `window` (`size` [w, h] or "WxH", `content_scale` default 1.0): resize the game window
##   (run.gd forces 1920x1080 at start) and set its content_scale_factor, the knob an
##   Interface size setting would turn. Logs the size the window actually took.
## - `host_lobby` (`folder`): the host lobby as a host sees it after hosting, without
##   hosting (LobbyHost.start_hosting false, so no Steam lobby is made): the title hidden, the
##   test level as its level, a sample room code through the real code path and a sample
##   player list. `close_host_lobby` frees it and shows the title again.
## - `drawer` (`which` "authoring" or "visuals", `pane`, `open` default true): open a rail
##   drawer on a pane as a rail click does (the authoring tool drawer, or the play Visuals
##   drawer), or close it.
## - `toasts`: one toast of each kind, with copy the game uses.
## - `danger`: the Remove token danger confirmation, with the game's copy.
## - `dismiss`: cancel every open confirmation dialog.
## - `browser` (`open`, default true): open or close the Add Token browser.
## - `save` (`folder`, `name`, `replace`): write the open authoring map as a test level
##   (`_u1_ui_` or `_ui_tour_` folders only), shown under `name` (default the folder).
## - `cleanup`: delete every `_u1_ui_*` and `_ui_tour_*` level folder.

const PREFIXES: Array[String] = ["_u1_ui_", "_ui_tour_"]
const LOBBY_HOST_SCENE := preload("res://scenes/states/lobby/lobby_host.tscn")
## A Steam lobby id of the usual magnitude, for a room code in the real format.
const SAMPLE_LOBBY_ID := 109775244321098765
const SAMPLE_PLAYERS: Array[String] = ["Marigold", "Ranger", "Starling"]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "report")):
		"settings":
			return _settings(base, step)
		"foldout":
			return _foldout(base, bool(step.get("expanded", true)))
		"close_settings":
			return _close_settings(base)
		"report":
			return _report(base)
		"window":
			return _window(base, step)
		"host_lobby":
			return _host_lobby(base, step)
		"close_host_lobby":
			return _close_host_lobby(base)
		"drawer":
			return _drawer(base, step)
		"toasts":
			return _toasts()
		"danger":
			return _danger()
		"dismiss":
			return _dismiss(base)
		"browser":
			return _browser(base, bool(step.get("open", true)))
		"save":
			return _save(base, step)
		"cleanup":
			return _cleanup()
	return "unknown action %s" % step.get("action", "")


static func _menu(base: Node) -> SettingsMenu:
	for child in base.get_tree().root.get_children():
		if child is SettingsMenu and not child.is_queued_for_deletion():
			return child
	return null


static func _settings(base: Node, step: Dictionary) -> String:
	var menu := _menu(base)
	if menu == null:
		menu = UIManager.open_settings() as SettingsMenu
	var section := String(step.get("section", ""))
	if not section.is_empty():
		menu.section_rail.select(StringName(section))
	return "settings open on %s" % menu.section_rail.selected


static func _visible_foldout(menu: SettingsMenu) -> Foldout:
	for node in menu.find_children("*", "Foldout", true, false):
		var foldout := node as Foldout
		if foldout.is_visible_in_tree():
			return foldout
	return null


static func _foldout(base: Node, expanded: bool) -> String:
	var menu := _menu(base)
	var foldout := _visible_foldout(menu) if menu else null
	if foldout == null:
		return "no visible Foldout"
	foldout.expanded = expanded
	return "foldout %s expanded %s" % [foldout.title, str(expanded)]


static func _close_settings(base: Node) -> String:
	var menu := _menu(base)
	if menu == null:
		return "settings not open"
	menu.animate_out()
	return "settings closing"


static func _report(base: Node) -> String:
	var parts := PackedStringArray()
	var menu := _menu(base)
	if menu:
		var rail := menu.section_rail
		var item: Control = rail._items.get(rail.selected)
		if item:
			var centre := item.position.x + item.size.x / 2.0
			parts.append(
				(
					"rail %s underline x %.1f, item centre x %.1f"
					% [rail.selected, rail._indicator_pos, centre]
				)
			)
		var foldout := _visible_foldout(menu)
		if foldout:
			parts.append(
				(
					"foldout %s chevron %s, title at x %.1f"
					% [
						foldout.title,
						str(foldout._chevron.get_global_rect()),
						foldout._title_label.get_global_rect().position.x
					]
				)
			)
	var hints: InputHints = UIManager.get("_input_hints")
	if hints:
		var keys := PackedStringArray()
		for chip in hints.hints_container.get_children():
			keys.append(String(chip.name).trim_prefix("Hint_"))
		parts.append(
			(
				"hint bar %s in window %s, alpha %.2f, chips %s"
				% [
					str(hints._bar.get_global_rect()),
					str(base.get_viewport().get_visible_rect().size),
					hints._bar.modulate.a,
					str(keys)
				]
			)
		)
	return "; ".join(parts)


# --- UI tour ---------------------------------------------------------------------------------


## [w, h] from an array or a "WxH" string (the tour's `expand` values are strings).
static func _size_of(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	var parts := String(value).split("x")
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i.ZERO


static func _window(base: Node, step: Dictionary) -> String:
	var size := _size_of(step.get("size", [1920, 1080]))
	if size == Vector2i.ZERO:
		return "bad size %s" % str(step.get("size"))
	var window := base.get_window()
	window.size = size
	window.content_scale_factor = float(step.get("content_scale", 1.0))
	return (
		"window asked %s, took %s, content scale %.2f, canvas %s"
		% [
			str(size),
			str(window.size),
			window.content_scale_factor,
			str(base.get_viewport().get_visible_rect().size)
		]
	)


static func _host_lobby(base: Node, step: Dictionary) -> String:
	var level := LevelManager.load_level_folder(String(step.get("folder", "")), false)
	if level == null:
		return "no level %s" % step.get("folder", "")
	var title: CanvasLayer = base.get("_title_screen")
	if title:
		title.visible = false
	var lobby := LOBBY_HOST_SCENE.instantiate() as LobbyHost
	lobby.name = "UiTourHostLobby"
	lobby.start_hosting = false
	base.add_child(lobby)
	lobby.set_level(level)
	lobby._on_room_code_received(LobbyCode.encode(SAMPLE_LOBBY_ID))
	lobby.player_list.clear()
	lobby.player_list.add_item("%s (Host)" % NetworkManager.get_player_name())
	for player in SAMPLE_PLAYERS:
		lobby.player_list.add_item(player)
	lobby.status_label.text = "%d player(s) connected" % (SAMPLE_PLAYERS.size() + 1)
	return "host lobby on %s, code %s" % [level.level_name, lobby.room_code_value.text]


static func _close_host_lobby(base: Node) -> String:
	var lobby := base.get_node_or_null("UiTourHostLobby")
	if lobby:
		base.remove_child(lobby)
		lobby.queue_free()
	var title: CanvasLayer = base.get("_title_screen")
	if title:
		title.visible = true
	return "host lobby closed" if lobby else "no host lobby"


static func _drawer(base: Node, step: Dictionary) -> String:
	var drawer: DrawerContainer = null
	var which := String(step.get("which", "authoring"))
	if which == "authoring":
		var ctrl: AuthoringController = base.get("_authoring_controller")
		drawer = ctrl.panel if ctrl else null
	else:
		var game_map: GameMap = base.get("_game_map")
		var menu: Node = (
			game_map.gameplay_menu.get_node_or_null("GameplayMenu") if game_map else null
		)
		drawer = menu.get("level_edit_panel") if menu else null
	if drawer == null:
		return "no %s drawer" % which
	if not bool(step.get("open", true)):
		drawer.close()
		return "%s drawer closing" % which
	var pane := StringName(String(step.get("pane", "")))
	if pane.is_empty():
		drawer.open()
	elif not drawer.is_open or drawer._rail.selected != pane:
		drawer._on_rail_item_pressed(pane)
	return "%s drawer open on %s" % [which, drawer._rail.selected]


static func _toasts() -> String:
	UIManager.show_success("Level saved")
	UIManager.show_info("Undone: Move token")
	UIManager.show_warning("Maps are built offline. Leave the game to build or edit a map.")
	UIManager.show_error("Could not load that level")
	return "four toasts"


static func _danger() -> String:
	UIManager.show_danger_confirmation(
		"Remove token",
		'Remove "Marigold" from the board? Ctrl+Z undoes it.',
		Callable(),
		"Remove"
	)
	return "danger confirmation"


static func _dismiss(base: Node) -> String:
	var count := 0
	for child in base.get_tree().root.get_children():
		if child is ConfirmationDialogUI and not child.is_queued_for_deletion():
			(child as ConfirmationDialogUI)._on_cancel_pressed()
			count += 1
	return "dismissed %d" % count


static func _browser(base: Node, open: bool) -> String:
	var toggle := base.find_child("ToggleAssetBrowserButton", true, false) as Button
	if toggle == null:
		return "no Add Token button"
	toggle.button_pressed = open
	return "browser %s" % ("open" if open else "closed")


# --- test levels -----------------------------------------------------------------------------


static func _is_test_folder(folder: String) -> bool:
	for prefix in PREFIXES:
		if folder.begins_with(prefix):
			return true
	return false


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", PREFIXES[0] + "hud"))
	if ctrl == null or not _is_test_folder(folder):
		return "no authoring controller, or not a test folder %s" % str(PREFIXES)
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = String(step.get("name", folder))
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if _is_test_folder(folder):
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
