class_name LibraryDetail
extends VBoxContainer

## The manager's detail column: the library selected in the list, in plain words. A heading with
## its version, author and licence, whether it is the game's or the player's and whether it is
## on, its description, what it holds and needs (each dependency with its state), its biomes
## as the pictures the New map dialog uses, every reason it failed and every warning the reader
## and the compiler had, and the actions that belong to it: Verify (every file against the
## catalog's hash, with progress and Cancel), Show in folder and Remove (a library the player
## installed only). Built in code; the manager owns one and calls show_library().

signal verify_requested(library_id: String)
signal verify_cancelled
signal folder_requested(folder: String)
signal remove_requested(library_id: String)
## "New biome from this...": the biome designer's copy flow for a biome of this library.
signal new_biome_requested(library_id: String)

## "Built in": every official library, that is `core` and anything else the game ships under
## res://libraries (the badge used to be "Official" for those and "Built in" for the palette).
const BADGE_YOURS := "Yours"
const BADGE_BUILTIN := "Built in"
const BADGE_RECEIVED := "From host"
const STATE_ON := "On"
const STATE_OFF := "Off"
const STATE_PROBLEM := "Needs attention"
const STRIP_PX := Vector2i(168, 56)
const MAX_LINES := 6
const ICON_PX := 20.0

var library_id: String = ""
var heading: Label
var verify_button: Button
var folder_button: Button
var remove_button: Button
var design_button: Button
var verify_box: VBoxContainer
var verify_bar: ProgressBar
var verify_label: Label
var verify_cancel_button: Button
var facts: GridContainer

var _info: Dictionary = {}
var _body: VBoxContainer


func _init() -> void:
	name = "Detail"
	theme_type_variation = &"BoxContainerSpaced"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Shows `info` (a LibraryRegistry.list() entry); an empty one shows the invitation to pick.
func show_library(info: Dictionary) -> void:
	_info = info
	library_id = String(info.get("id", ""))
	for child in get_children():
		remove_child(child)
		child.queue_free()
	verify_box = null
	if info.is_empty():
		_add_label("Pick a %s to see what it holds." % LibraryNames.lower(), &"Caption")
		return
	heading = _add_label(String(info["name"]), &"Heading")
	heading.name = "Heading"
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.tooltip_text = String(info["name"])
	_add_label(subtitle_of(info), &"Caption").name = "Subtitle"
	_add_chips(info)
	if String(info["description"]) != "":
		var words := _add_label(String(info["description"]), &"Body")
		words.name = "Description"
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bool(info.get("received", false)):
		var sent := "The host sent this %s for this session. It holds only what the map uses."
		var note := _add_label(sent % LibraryNames.lower(), &"Body")
		note.name = "ReceivedNote"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_facts(info)
	_add_biomes(info)
	_add_notes(info)
	_add_actions(info)


## "v0.3.1 by Test Author · CC0-1.0": the parts that exist, in that order. Pure.
static func subtitle_of(info: Dictionary) -> String:
	var parts := PackedStringArray()
	var version := String(info.get("version", ""))
	var author := String(info.get("author", ""))
	if version != "":
		parts.append("v" + version + (" by " + author if author != "" else ""))
	elif author != "":
		parts.append("by " + author)
	if String(info.get("license", "")) != "":
		parts.append(String(info["license"]))
	return " · ".join(parts)


## "2 assets, 1 biome". Pure.
static func contents_text(info: Dictionary) -> String:
	var assets := int(info.get("asset_count", 0))
	var biomes := int(info.get("biome_count", 0))
	return (
		"%d %s, %d %s"
		% [
			assets,
			"asset" if assets == 1 else "assets",
			biomes,
			"biome" if biomes == 1 else "biomes"
		]
	)


## The badge for where a library came from. Pure.
static func origin_badge(info: Dictionary) -> String:
	match String(info.get("source", "")):
		"official":
			return BADGE_BUILTIN
		"received":
			return BADGE_RECEIVED
	return BADGE_YOURS


## Whether the biome designer can start from a biome of this library: it is served from a folder
## on this machine (not one the host sent for the session), works, and has a biome. Pure.
static func can_design(info: Dictionary) -> bool:
	return (
		String(info.get("status", "")) == LibraryResolver.OK
		and String(info.get("folder", "")) != ""
		and int(info.get("biome_count", 0)) > 0
		and not bool(info.get("received", false))
	)


## "On", "Off" or "Needs attention". Pure.
static func state_badge(info: Dictionary) -> String:
	if String(info.get("status", "")) == LibraryResolver.ERROR:
		return STATE_PROBLEM
	return STATE_ON if bool(info.get("enabled", true)) else STATE_OFF


## Starts the Verify display: a bar at 0 of `total` and a Cancel.
func begin_verify(total: int) -> void:
	if verify_box == null:
		return
	verify_box.visible = true
	verify_bar.visible = true
	verify_bar.max_value = maxf(total, 1)
	verify_bar.value = 0
	verify_label.text = "Checking %d %s..." % [total, "file" if total == 1 else "files"]
	verify_cancel_button.visible = true
	verify_button.disabled = true
	_clear_results()


func set_verify_progress(done: int, total: int) -> void:
	if verify_box == null:
		return
	verify_bar.value = done
	verify_label.text = "Checking %d of %d..." % [done, total]


## Ends the display with `summary` (LibraryVerify.summarize) and a line per failing file.
func finish_verify(summary: Dictionary, cancelled: bool = false) -> void:
	if verify_box == null:
		return
	verify_bar.visible = false
	verify_cancel_button.visible = false
	verify_button.disabled = false
	_clear_results()
	if cancelled:
		verify_label.text = "Stopped after %d files." % int(summary["checked"])
	else:
		verify_label.text = LibraryVerify.summary_text(summary)
	var failed: Array = summary["failed"]
	for i in mini(failed.size(), MAX_LINES):
		var result: Dictionary = failed[i]
		var line := "%s: %s" % [LibraryVerify.short_name(String(result["asset"])), result["error"]]
		_add_note(line, "alert-circle", ThemeColors.DANGER, verify_box).name = "Failure%d" % i
	if failed.size() > MAX_LINES:
		var more := _add_label(
			"... and %d more." % (failed.size() - MAX_LINES), &"Caption", verify_box
		)
		more.name = "More"


## A Verify that cannot run, with the reason in the box.
func say_cannot_verify(text: String) -> void:
	if verify_box == null:
		return
	verify_box.visible = true
	verify_bar.visible = false
	verify_cancel_button.visible = false
	verify_label.text = text
	_clear_results()


# ---- building ----


func _add_chips(info: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "Chips"
	row.theme_type_variation = &"BoxContainerTight"
	add_child(row)
	row.add_child(chip(origin_badge(info), "Origin"))
	row.add_child(chip(state_badge(info), "State"))


## A small raised label ("Official", "On") in the Chip panel.
static func chip(text: String, node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = &"Chip"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = "Label"
	label.theme_type_variation = &"Caption"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel


func _add_facts(info: Dictionary) -> void:
	facts = GridContainer.new()
	facts.name = "Facts"
	facts.columns = 2
	facts.theme_type_variation = &"FactsGrid"
	add_child(facts)
	_fact("Holds", contents_text(info))
	if bool(info.get("official", false)):
		_fact("Where", "Part of the game")
	else:
		_fact("Size", LibraryImporter.size_text(int(info["bytes"])))
	var deps: Array = info["dependencies"]
	if not deps.is_empty():
		var states := LibraryInstall.dependency_states({"dependencies": deps})
		_fact_label("Needs")
		var needs := VBoxContainer.new()
		needs.name = "Needs"
		needs.theme_type_variation = &"BoxContainerTight"
		needs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts.add_child(needs)
		for dep in states:
			var ok: bool = dep["state"] == LibraryInstall.DEP_OK
			var text := "%s %s" % [dep["id"], dep["version"]]
			if ok:
				text += " (installed %s)" % dep["installed"]
			else:
				text = LibraryInstall.dependency_line(dep)
			var icon := "circle-check" if ok else "alert-triangle"
			_add_note(text, icon, ThemeColors.SUCCESS if ok else ThemeColors.WARNING, needs)
	if String(info["url"]) != "":
		_fact("Link", String(info["url"]), true)
	if String(info["source"]) == "user" or String(info["source"]) == "dev":
		_fact("Folder", ProjectSettings.globalize_path(String(info["folder"])), true)


func _fact(label: String, value: String, ellipsize: bool = false) -> void:
	_fact_label(label)
	var words := Label.new()
	words.theme_type_variation = &"Body"
	words.text = value
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.custom_minimum_size.x = 120
	if ellipsize:
		words.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		words.tooltip_text = value
	else:
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.add_child(words)


func _fact_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	facts.add_child(label)


func _add_biomes(info: Dictionary) -> void:
	var biomes: Array = info["biomes"]
	if biomes.is_empty():
		return
	_add_label("Biomes", &"H3").name = "BiomesHeading"
	var flow := HFlowContainer.new()
	flow.name = "Biomes"
	flow.theme_type_variation = &"FactsFlow"
	add_child(flow)
	var served := bool(info["served"])
	var by_local := _runtime_by_local(info)
	for biome: Dictionary in biomes:
		var tile := VBoxContainer.new()
		tile.name = "Biome_%s" % String(biome["id"]).validate_node_name()
		tile.theme_type_variation = &"BoxContainerTight"
		flow.add_child(tile)
		var runtime := String(by_local.get(biome["id"], biome["id"]))
		var picture := picture_of(runtime) if served else null
		if picture != null:
			var rect := TextureRect.new()
			rect.texture = picture
			rect.custom_minimum_size = Vector2(STRIP_PX)
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tile.add_child(rect)
		_add_label(String(biome["name"]), &"Caption", tile)


## The first runtime biome id of each local biome id of a list() entry (its first season).
static func _runtime_by_local(info: Dictionary) -> Dictionary:
	var out := {}
	for runtime: String in info["biome_ids"]:
		var local := String(LibraryIds.parse_runtime_biome(runtime).get("biome", ""))
		if local != "" and not out.has(local):
			out[local] = runtime
	return out


## The strip picture of the served biome `runtime_id`, or null when the palette lacks it.
static func picture_of(runtime_id: String) -> Texture2D:
	var biome := PaletteLibrary.biome(runtime_id)
	if biome.is_empty():
		return null
	return BiomeThumbnail.strip(biome, STRIP_PX)


func _add_notes(info: Dictionary) -> void:
	var reasons: Array = info["reasons"]
	var warnings: Array = info["warnings"]
	if reasons.is_empty() and warnings.is_empty():
		return
	var box := VBoxContainer.new()
	box.name = "Notes"
	box.theme_type_variation = &"BoxContainerTight"
	add_child(box)
	_add_lines(box, reasons, "alert-circle", ThemeColors.DANGER)
	_add_lines(box, warnings, "alert-triangle", ThemeColors.WARNING)


func _add_lines(box: VBoxContainer, lines: Array, icon: String, role: StringName) -> void:
	for i in mini(lines.size(), MAX_LINES):
		_add_note(String(lines[i]), icon, role, box)
	if lines.size() > MAX_LINES:
		_add_label("... and %d more." % (lines.size() - MAX_LINES), &"Caption", box)


func _add_actions(info: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.theme_type_variation = &"BoxContainerSpaced"
	add_child(row)
	verify_button = _action("Verify", "circle-check", row)
	verify_button.tooltip_text = "Check every file against the %s's own list" % LibraryNames.lower()
	verify_button.pressed.connect(func() -> void: verify_requested.emit(library_id))
	var is_user := String(info["source"]) == "user"
	folder_button = _action("Show in folder", "folder", row)
	folder_button.visible = is_user
	folder_button.pressed.connect(func() -> void: folder_requested.emit(String(info["folder"])))
	remove_button = _action("Remove", "x", row)
	remove_button.visible = is_user
	remove_button.pressed.connect(func() -> void: remove_requested.emit(library_id))
	design_button = _action("New biome from this...", "wand", row)
	design_button.name = "DesignButton"
	design_button.visible = can_design(info)
	design_button.tooltip_text = (
		"Open the biome designer on one of its biomes, as a copy in a new %s of yours."
		% LibraryNames.lower()
	)
	design_button.pressed.connect(func() -> void: new_biome_requested.emit(library_id))
	verify_box = VBoxContainer.new()
	verify_box.name = "VerifyBox"
	verify_box.theme_type_variation = &"BoxContainerTight"
	verify_box.visible = false
	add_child(verify_box)
	verify_label = _add_label("", &"Caption", verify_box)
	verify_label.name = "VerifyLabel"
	verify_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bar_row := HBoxContainer.new()
	bar_row.theme_type_variation = &"BoxContainerSpaced"
	verify_box.add_child(bar_row)
	verify_bar = ProgressBar.new()
	verify_bar.name = "VerifyBar"
	verify_bar.show_percentage = false
	verify_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	verify_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(verify_bar)
	verify_cancel_button = _action("Stop", "x", bar_row)
	verify_cancel_button.name = "VerifyCancel"
	verify_cancel_button.pressed.connect(func() -> void: verify_cancelled.emit())


func _clear_results() -> void:
	for child in verify_box.get_children():
		if child.name.begins_with("Failure") or child.name == "More":
			verify_box.remove_child(child)
			child.queue_free()


func _action(label: String, icon: String, parent: Control) -> Button:
	var button := AnimatedButton.new()
	button.name = label.replace(" ", "") + "Button"
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(0, UiActions.SECONDARY_HEIGHT)
	parent.add_child(button)
	return button


func _add_label(text: String, variation: StringName, parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	(parent if parent != null else self).add_child(label)
	return label


## A line with a tinted icon (a warning, a failure, a met dependency), under `parent`.
func _add_note(text: String, icon: String, role: StringName, parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"BoxContainerSpaced"
	parent.add_child(row)
	var mark := TextureRect.new()
	mark.texture = IconButton.load_icon(icon)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var words := Label.new()
	words.text = text
	words.theme_type_variation = &"Body"
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.custom_minimum_size.x = 160
	row.add_child(words)
	if row.is_inside_tree():
		mark.self_modulate = ThemeColors.of(row, role)
	else:
		row.tree_entered.connect(func() -> void: mark.self_modulate = ThemeColors.of(row, role))
	return row
