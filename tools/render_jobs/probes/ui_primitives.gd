extends RefCounted

## Render-job probe (`call` op) for the UI primitive fixes (card U1): the Foldout
## chevron, the IconRail underline and the input hint bar, for
## jobs/ui_primitives_look.json. `action`:
## - `settings` (`section`, optional): open Settings (UIManager.open_settings) when
##   it is not open, then select that rail section.
## - `foldout` (`expanded`, default true): expand or collapse the first Foldout on
##   the open Settings menu's current section.
## - `close_settings`: close the open Settings menu (its own animate_out).
## - `report`: the open Settings menu's rail underline against its selected item's
##   centre and the visible Foldout's chevron rect against its title; the input
##   hint bar's rect against the window and its chip keys.
## - `save` (`folder`, `replace`): write the open authoring map as a `_u1_ui_` level.
## - `cleanup`: delete every `_u1_ui_*` level folder.

const PREFIX := "_u1_ui_"


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


# --- test level ------------------------------------------------------------------------------


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", PREFIX + "hud"))
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not a %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
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
