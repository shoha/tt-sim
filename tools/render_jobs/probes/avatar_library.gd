extends RefCounted

## Render-job probe (`call` op) for the avatar library (AvatarLibrary, AvatarRoster, the
## Avatar tab), for jobs/avatar_library_look.json. The running game's library is pointed
## at a test directory under PREFIX first, so the player's own avatars are never read or
## written. `action`:
## - `use` (`dir`, a name after PREFIX; `seed` [preset indices], `names`): points the
##   library at user://<PREFIX><dir>/ and, with `seed`, empties it and saves one avatar per
##   preset (AvatarPresets) under `names`.
## - `roster`: opens the title screen's roster (AvatarRoster).
## - `edit` (`index`): opens the builder from the roster on the index-th avatar.
## - `close`: cancels any open builder and closes the roster.
## - `browser`: opens the Add Token browser on its Avatar tab (in play).
## - `place` (`index`): places the index-th saved avatar as the tab's click does.
## - `report`: the library's avatars and how many thumbnails are drawn.
## - `cleanup`: deletes every user://<PREFIX>* directory and points the library back at
##   user://avatars/.

const PREFIX := "_avatarlib_"


static func run(base: Node, step: Dictionary) -> String:
	var root := base.get_tree().root
	match String(step.get("action", "report")):
		"use":
			return _use(step)
		"roster":
			AvatarRoster.open(root)
			return "roster open on %s" % AvatarLibrary.directory
		"edit":
			var roster := _find(root, "AvatarRoster") as AvatarRoster
			var entries := AvatarLibrary.list()
			var index := int(step.get("index", 0))
			if roster == null or index >= entries.size():
				return "no roster or no avatar %d" % index
			roster.edit(entries[index])
			return "editing %s" % entries[index].name
		"close":
			var builder := _find(root, "AvatarBuilder") as AvatarBuilder
			if builder != null:
				builder.cancel()
			var roster := _find(root, "AvatarRoster") as AvatarRoster
			if roster != null:
				roster.close()
			return "closed"
		"browser":
			var toggle := root.find_child("ToggleAssetBrowserButton", true, false) as Button
			if toggle == null:
				return "no Add Token button"
			toggle.button_pressed = true
			return "browser open"
		"place":
			var tab: AvatarTab = null
			for node in root.find_children(AvatarTab.TAB_TITLE, "MarginContainer", true, false):
				if node is AvatarTab:
					tab = node
			var entries := AvatarLibrary.list()
			var index := int(step.get("index", 0))
			if tab == null or index >= entries.size():
				return "no Avatar tab or no avatar %d" % index
			var card := tab.grid.card_for(String(entries[index].id))
			if card == null:
				return "no card for %s" % entries[index].name
			card.pressed.emit()
			return "pressed %s's card" % entries[index].name
		"report":
			return _report(root)
		"cleanup":
			return _cleanup()
	return "unknown action %s" % step.get("action", "")


static func _find(root: Node, type_name: String) -> Node:
	for node in root.get_children():
		if node.get_script() != null and node.is_class("CanvasLayer"):
			var script: Script = node.get_script()
			if script.get_global_name() == type_name and not node.is_queued_for_deletion():
				return node
	return null


static func _use(step: Dictionary) -> String:
	var dir := "user://%s%s/" % [PREFIX, String(step.get("dir", "look"))]
	AvatarLibrary.directory = dir
	if not step.has("seed"):
		return "library at %s (%d avatars)" % [dir, AvatarLibrary.list().size()]
	for entry in AvatarLibrary.list():
		AvatarLibrary.delete(String(entry.id))
	var names: Array = step.get("names", [])
	var seeds: Array = step.seed
	for i in seeds.size():
		var preset := int(seeds[i]) % AvatarPresets.PRESETS.size()
		var name := (
			String(names[i]) if i < names.size() else String(AvatarPresets.PRESETS[preset].name)
		)
		AvatarLibrary.save(name, AvatarPresets.recipe(preset))
	return "library at %s seeded with %d avatars" % [dir, AvatarLibrary.list().size()]


static func _report(root: Node) -> String:
	var names := PackedStringArray()
	var drawn := 0
	for entry in AvatarLibrary.list():
		names.append(String(entry.name))
		if AvatarThumbnails.cached(entry.recipe) != null:
			drawn += 1
	var roster := _find(root, "AvatarRoster") != null
	return (
		"library %s: %s; %d thumbnails drawn; roster open %s"
		% [AvatarLibrary.directory, ", ".join(names), drawn, str(roster)]
	)


static func _cleanup() -> String:
	AvatarLibrary.directory = AvatarLibrary.DEFAULT_DIRECTORY
	var removed := PackedStringArray()
	var users := DirAccess.open("user://")
	if users == null:
		return "no user folder"
	for folder in users.get_directories():
		if not folder.begins_with(PREFIX):
			continue
		var path := "user://" + folder
		var dir := DirAccess.open(path)
		if dir != null:
			for file in dir.get_files():
				dir.remove(file)
		DirAccess.remove_absolute(path)
		removed.append(folder)
	return "removed %s; library back at %s" % [str(removed), AvatarLibrary.directory]
