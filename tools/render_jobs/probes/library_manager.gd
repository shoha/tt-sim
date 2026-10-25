extends RefCounted

## Render-job probe (`call` op) for the collections manager (content library step S6), for
## jobs/library_manager.json. It writes a second library into the run's own `user://libraries`
## (the worktree's user folder, never the player's) and drives the manager like a player would.
## step.action:
##   world                    writes `alienworld` (0.3.1, user) into the user libraries, three
##                            archives into user://_libmgr_inbox/ (betaworld.ttlib: a new
##                            collection; alienworld_new.ttlib: 0.4.0, a Replace; broken.ttlib:
##                            one that holds a script, a refusal) and serves the libraries.
##   open                     opens the manager over the current screen.
##   select {id}              selects a library in the list.
##   toggle {id, on}          presses a library's switch.
##   card {file}              starts the import of user://_libmgr_inbox/<file> through the
##                            manager's flow (the install card opens after the reading finishes).
##   confirm                  presses the install card's primary (Install or Replace).
##   card_close               closes the install card.
##   verify                   presses Verify on the selected library.
##   remove                   presses Remove on the selected library (the danger confirmation).
##   dialog_close             closes the confirmation (Cancel) if one is up.
##   close                    closes the manager.
##   close_new_map            cancels the New map dialog.
##   report                   logs the list, the selection, the card and the footer line.
##   cleanup                  removes everything `world` wrote and serves the libraries again.

const World := preload("res://tests/unit/library_world.gd")
const Zip := preload("res://tests/unit/zip_builder.gd")
const INBOX := "user://_libmgr_inbox"
const SURFACE := "grass_alpine"


static func run(base: Node, step: Dictionary) -> String:
	var root := base.get_tree().root
	match String(step.get("action", "report")):
		"world":
			return _world()
		"open":
			LibraryManager.open(root)
			return "manager open"
		"select":
			var manager := _manager(root)
			if manager == null:
				return "no manager"
			manager.select(String(step.get("id", "")))
			return "selected %s" % manager.selected_id
		"toggle":
			return _toggle(root, step)
		"card":
			var manager := _manager(root)
			if manager == null:
				return "no manager"
			manager.flow.begin(INBOX.path_join(String(step.get("file", ""))))
			return "import started"
		"confirm":
			var card := _card(root)
			if card == null or card.confirm_button == null:
				return "no card to confirm"
			card.confirm_button.pressed.emit()
			return "confirmed"
		"card_close":
			var card := _card(root)
			if card == null:
				return "no card"
			card.cancel_button.pressed.emit()
			return "card closed"
		"verify":
			var manager := _manager(root)
			manager.detail.verify_button.pressed.emit()
			return "verify pressed"
		"remove":
			var manager := _manager(root)
			manager.detail.remove_button.pressed.emit()
			return "remove pressed"
		"dialog_close":
			for child in root.get_children():
				if child is ConfirmationDialogUI:
					(child as ConfirmationDialogUI).cancel_button.pressed.emit()
					return "dialog closed"
			return "no dialog"
		"close":
			var manager := _manager(root)
			if manager != null:
				manager.close()
			return "closed"
		"close_new_map":
			var dialog := _find(root, "NewMapDialog") as NewMapDialog
			if dialog != null:
				dialog.cancel_button.pressed.emit()
			return "new map closed"
		"report":
			return _report(root)
		"cleanup":
			return _cleanup()
	return "unknown action"


static func _world() -> String:
	var user_root := LibraryRegistry.user_root
	World.remove_tree(user_root.path_join("alienworld"))
	_write_alien(user_root.path_join("alienworld"), "0.3.1")
	World.remove_tree(INBOX)
	var work := INBOX.path_join("src")
	_write_alien(work.path_join("alienworld"), "0.4.0")
	Zip.write(INBOX.path_join("alienworld_new.ttlib"), Zip.entries_of(work.path_join("alienworld")))
	_write_beta(work.path_join("betaworld"))
	Zip.write(INBOX.path_join("betaworld.ttlib"), Zip.entries_of(work.path_join("betaworld"), "betaworld/"))
	var broken := Zip.entries_of(work.path_join("betaworld"))
	broken.append({"name": "scripts/start.gd", "data": "extends Node"})
	broken.append({"name": "../escape.json", "data": "{}"})
	Zip.write(INBOX.path_join("broken.ttlib"), broken)
	LibraryImportFlow.refresh_all()
	var ids: Array = LibraryRegistry.list().map(func(item: Dictionary) -> String: return item["id"])
	return "libraries now %s, inbox %s" % [str(ids), ProjectSettings.globalize_path(INBOX)]


static func _write_alien(folder: String, version: String) -> void:
	World.write_alien(folder, version, [], false)
	World.edit_json(
		folder.path_join("biomes/crystal_basin.json"),
		func(biome: Dictionary) -> void: biome["ground"]["surface"] = SURFACE
	)
	World.edit_json(
		folder.path_join("library.json"),
		func(library: Dictionary) -> void:
			library["description"] = (
				"Glassy blue spires and shards on a pale basin floor: a place for the tabletop "
				+ "that never grew leaves."
			)
			library["url"] = "https://example.com/alienworld"
	)


static func _write_beta(folder: String) -> void:
	var library := {
		"format": "ttsim-library",
		"format_version": 1,
		"id": "betaworld",
		"name": "Beta Marsh",
		"version": "2.1.0",
		"contract": 1,
		"author": "Jo Marsh",
		"license": "CC-BY-4.0",
		"description": "Reeds, stepping stones and a still, brown marsh.",
		"dependencies": [{"id": "core", "version": "^1.0"}],
	}
	var assets := [
		{"id": "Reed_Tall_v0", "category": "ground_cover", "wind": "grass", "size": "ground"},
		{"id": "Stone_Flat_v0", "category": "rock", "wind": "", "size": "small"},
		{"id": "Willow_Low_v0", "category": "tree", "wind": "tree", "size": "large"},
	]
	var biome := {
		"format": "ttsim-biome",
		"format_version": 1,
		"id": "beta_marsh",
		"name": "Beta Marsh",
		"surfaces": "legacy",
		"seasons": [{"id": "summer", "seed": 1}],
		"ground": {"surface": SURFACE, "paths": []},
		"rules":
		[
			{"key": "willows", "role": "canopy_tree", "density_per_m2": 0.01, "query": {"match": [{"ref": "Willow_Low_v0"}]}},
			{"key": "stones", "role": "stones", "density_per_m2": 0.05, "query": {"match": [{"ref": "Stone_Flat_v0"}]}},
		],
	}
	World.write_library(folder, library, assets, biome)


static func _toggle(root: Node, step: Dictionary) -> String:
	var manager := _manager(root)
	if manager == null:
		return "no manager"
	var toggle := manager.toggle_of(String(step.get("id", "")))
	if toggle == null:
		return "no row"
	toggle.button_pressed = bool(step.get("on", true))
	return "toggled"


static func _report(root: Node) -> String:
	var manager := _manager(root)
	var lines := PackedStringArray()
	for item in LibraryRegistry.list():
		lines.append(
			"%s [%s] v%s %s enabled=%s assets=%s biomes=%s %s"
			% [item["id"], item["source"], item["version"], item["status"], item["enabled"],
				item["asset_count"], item["biome_count"], str(item["reasons"])]
		)
	if manager != null:
		lines.append("selected=%s status='%s'" % [manager.selected_id, manager.status_label.text])
	var card := _card(root)
	if card != null:
		lines.append("card: %s" % JSON.stringify(card.card.get("id", "")))
	return "\n".join(lines)


static func _cleanup() -> String:
	var user_root := LibraryRegistry.user_root
	for id in ["alienworld", "betaworld"]:
		World.remove_tree(user_root.path_join(id))
		LibraryRegistry.set_enabled(id, true)
	World.remove_tree(INBOX)
	LibraryImporter.sweep_incoming()
	LibraryImportFlow.refresh_all()
	return "cleaned"


static func _manager(root: Node) -> LibraryManager:
	return _find(root, "LibraryManager") as LibraryManager


static func _card(root: Node) -> LibraryInstallCard:
	return _find(root, "LibraryInstallCard") as LibraryInstallCard


static func _find(root: Node, node_name: String) -> Node:
	return root.find_child(node_name, true, false)
