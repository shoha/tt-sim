class_name LibraryInstallCard
extends AnimatedCanvasLayerPanel

## The sheet an import goes through before anything is installed (design 5.5): it opens reading
## the archive (a bar and Cancel), then shows what the file holds as a card (its name, author,
## licence, version, size, what it holds, what it needs, every warning), says in one line that a
## collection only holds art and settings, never programs, and asks. A collection whose id is
## already installed offers Replace with the two versions side by side; one the game refuses
## (a reserved id, a file that does not read) shows why and Close alone. Nothing is installed
## until Install or Replace is pressed.
##
## Built in code (no scene), over the manager's scrim when the manager is open (one scrim, UI
## taste G1). The flow (LibraryImportFlow) owns the files: this sheet only shows and asks.

signal install_confirmed(card: Dictionary, replace: bool)
signal cancelled
signal closed

const SHEET_WIDTH := 600.0
const ICON_PX := 20.0
const MAX_LINES := 6
const TITLE_READING := "Reading %s"
const TITLE_REFUSED := "This file cannot be imported"
const CAPTION_NOTHING := "Nothing is installed until you choose."
const RELATION_WORDS := {
	LibraryInstall.RELATION_NEWER: "a newer version",
	LibraryInstall.RELATION_OLDER: "an older version",
	LibraryInstall.RELATION_SAME: "the same version",
}

var header: MenuHeader
var facts: GridContainer
var progress_bar: ProgressBar
var progress_label: Label
var confirm_button: Button
var cancel_button: Button
var card: Dictionary = {}

var _closing := false
var _body: VBoxContainer
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: HBoxContainer
var _replace := false


func _init() -> void:
	name = "LibraryInstallCard"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = Constants.LAYER_DIALOG
	var scrim := Scrim.new()
	scrim.name = "ColorRect"
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.name = "CenterContainer"
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var sheet := PanelContainer.new()
	sheet.name = "PanelContainer"
	sheet.custom_minimum_size.x = SHEET_WIDTH
	centre.add_child(sheet)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.theme_type_variation = &"BoxContainerSpaced"
	sheet.add_child(_body)
	header = MenuHeader.new()
	header.name = "Header"
	_body.add_child(header)
	header.close_requested.connect(_on_cancel_pressed)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.theme_type_variation = &"BoxContainerSpaced"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_body.add_child(HSeparator.new())
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(_footer)


func _on_panel_ready() -> void:
	UIManager.register_overlay($ColorRect as Control)
	get_viewport().size_changed.connect(_fit_to_canvas)
	_content.minimum_size_changed.connect(_fit_to_canvas, CONNECT_DEFERRED)
	_fit_to_canvas()


func _exit_tree() -> void:
	super._exit_tree()
	if get_viewport() != null and get_viewport().size_changed.is_connected(_fit_to_canvas):
		get_viewport().size_changed.disconnect(_fit_to_canvas)


# ---- states ----


## The reading state: a bar that fills as the files are written, and Cancel.
func show_reading(source_name: String, total: int) -> void:
	_reset()
	header.setup(
		TITLE_READING % source_name, "Checking the file before anything is installed.", true
	)
	progress_label = _label("Reading...", &"Caption", _content)
	progress_label.name = "ProgressLabel"
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.show_percentage = false
	progress_bar.max_value = maxf(total, 1)
	_content.add_child(progress_bar)
	cancel_button = _button("CancelButton", "Cancel", &"Secondary")
	cancel_button.pressed.connect(_on_cancel_pressed)
	_fit_to_canvas()


func set_progress(done: int, total: int) -> void:
	if progress_bar == null or not is_instance_valid(progress_bar):
		return
	progress_bar.max_value = maxf(total, 1)
	progress_bar.value = done
	progress_label.text = (
		"Reading %s of %s..." % [LibraryImporter.size_text(done), LibraryImporter.size_text(total)]
	)


## The refusal: `errors` (plain sentences) and Close.
func show_refused(file_name: String, errors: Array) -> void:
	_reset()
	header.setup(TITLE_REFUSED, file_name, true)
	_lines(errors, "alert-circle", ThemeColors.DANGER, _content)
	cancel_button = _button("CloseButton", "Close", &"Secondary")
	cancel_button.pressed.connect(_on_cancel_pressed)
	_after_build()


## The card of `description` (LibraryInstall.examine's answer).
func show_card(description: Dictionary) -> void:
	_reset()
	card = description
	var named := String(card["name"]) if String(card["name"]) != "" else String(card["id"])
	var refused: bool = not bool(card["can_install"])
	header.setup(named if named != "" else TITLE_REFUSED, _caption(), true)
	if String(card["description"]) != "":
		var about := _label(String(card["description"]), &"Body", _content)
		about.name = "Description"
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not refused or String(card["id"]) != "":
		_add_facts()
	_lines(card["errors"], "alert-circle", ThemeColors.DANGER, _content)
	_lines(card["warnings"], "alert-triangle", ThemeColors.WARNING, _content)
	var existing: Dictionary = card["existing"]
	_replace = not existing.is_empty() and not bool(card["reserved"])
	if _replace:
		var note := _label(replace_line(card), &"Body", _content)
		note.name = "ReplaceNote"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var promise := _lines(
		[LibraryNames.only_art_and_settings()], "info-circle", ThemeColors.STATE, _content
	)
	promise.name = "Promise"
	cancel_button = _button("CancelButton", "Close" if refused else "Cancel", &"Secondary")
	cancel_button.pressed.connect(_on_cancel_pressed)
	if not refused:
		var label := replace_label(card) if _replace else "Install"
		confirm_button = _button("InstallButton", label, &"Primary")
		confirm_button.pressed.connect(_on_confirm_pressed)
	_after_build()


## "Installed: v0.3.1. This file: v0.4.0, newer." Pure.
static func replace_line(description: Dictionary) -> String:
	var installed := String((description["existing"] as Dictionary).get("version", ""))
	var incoming := String(description["version"])
	var tail := String(RELATION_WORDS.get(String(description["relation"]), ""))
	var line := "%s is already installed (v%s). " % [description["name"], installed]
	line += "This file is v%s, %s. " % [incoming, tail]
	return line + "Replacing keeps your maps; they use the new files."


## The primary's label when an installed copy exists: "Replace v0.3.1". Pure.
static func replace_label(description: Dictionary) -> String:
	var installed := String((description["existing"] as Dictionary).get("version", ""))
	return "Replace v%s" % installed if installed != "" else "Replace"


func _caption() -> String:
	var parts := PackedStringArray()
	if String(card["version"]) != "":
		parts.append("v" + String(card["version"]))
	if String(card["author"]) != "":
		parts.append("by " + String(card["author"]))
	return " ".join(parts) if not parts.is_empty() else CAPTION_NOTHING


func _add_facts() -> void:
	facts = GridContainer.new()
	facts.name = "Facts"
	facts.columns = 2
	facts.theme_type_variation = &"FactsGrid"
	_content.add_child(facts)
	_fact("Id", String(card["id"]))
	if String(card["license"]) != "":
		_fact("Licence", String(card["license"]))
	var assets := int(card["asset_count"])
	var biomes := int(card["biome_count"])
	_fact(
		"Holds",
		(
			"%d %s, %d %s"
			% [
				assets,
				"asset" if assets == 1 else "assets",
				biomes,
				"biome" if biomes == 1 else "biomes",
			]
		)
	)
	_fact("Size", LibraryImporter.size_text(int(card["bytes"])))
	var deps: Array = card["dependencies"]
	if not deps.is_empty():
		_fact_label("Needs")
		var needs := VBoxContainer.new()
		needs.name = "Needs"
		needs.theme_type_variation = &"BoxContainerTight"
		needs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts.add_child(needs)
		for dep: Dictionary in deps:
			var ok: bool = dep["state"] == LibraryInstall.DEP_OK
			var text := "%s %s" % [dep["id"], dep["version"]]
			if not ok:
				text = LibraryInstall.dependency_line(dep)
			var role := ThemeColors.SUCCESS if ok else ThemeColors.WARNING
			_lines([text], "circle-check" if ok else "alert-triangle", role, needs)
	if String(card["url"]) != "":
		_fact("Link", String(card["url"]))
	var names := PackedStringArray()
	for biome: Dictionary in card["biomes"]:
		names.append(String(biome["name"]))
	if not names.is_empty():
		_fact("Biomes", ", ".join(names))


func _fact(label: String, value: String) -> void:
	_fact_label(label)
	var words := Label.new()
	words.theme_type_variation = &"Body"
	words.text = value
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.custom_minimum_size.x = 160
	facts.add_child(words)


func _fact_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Caption"
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	facts.add_child(label)


# ---- building blocks ----


## Clears the content and the footer for the next state.
func _reset() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	facts = null
	progress_bar = null
	progress_label = null
	confirm_button = null
	cancel_button = null


func _after_build() -> void:
	rebuild_focus_trap()
	_fit_to_canvas()
	if is_inside_tree() and confirm_button != null:
		confirm_button.grab_focus()
	elif is_inside_tree() and cancel_button != null:
		cancel_button.grab_focus()


## Lines with a tinted icon, up to MAX_LINES; returns the box they are in.
func _lines(lines: Array, icon: String, role: StringName, parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.theme_type_variation = &"BoxContainerTight"
	parent.add_child(box)
	for i in mini(lines.size(), MAX_LINES):
		var row := HBoxContainer.new()
		row.theme_type_variation = &"BoxContainerSpaced"
		box.add_child(row)
		var mark := TextureRect.new()
		mark.texture = IconButton.load_icon(icon)
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mark.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
		var words := _label(String(lines[i]), &"Body", row)
		words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.custom_minimum_size.x = 160
		_tint_when_ready(mark, row, role)
	if lines.size() > MAX_LINES:
		_label("... and %d more." % (lines.size() - MAX_LINES), &"Caption", box)
	box.visible = not lines.is_empty()
	return box


func _tint_when_ready(mark: TextureRect, row: Control, role: StringName) -> void:
	if row.is_inside_tree():
		mark.self_modulate = ThemeColors.of(row, role)
	else:
		row.tree_entered.connect(func() -> void: mark.self_modulate = ThemeColors.of(row, role))


func _label(text: String, variation: StringName, parent: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	parent.add_child(label)
	return label


func _button(node_name: String, text: String, variation: StringName) -> Button:
	var button := AnimatedButton.new()
	button.name = node_name
	button.text = text
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(120, 0)
	button.set_meta("ui_silent", true)
	_footer.add_child(button)
	return button


## The sheet at most as tall as the canvas allows; the content scrolls inside it.
func _fit_to_canvas() -> void:
	if not is_instance_valid(_scroll) or not is_inside_tree():
		return
	var canvas := get_viewport().get_visible_rect().size
	var sheet := $CenterContainer/PanelContainer as PanelContainer
	var margin := sheet.get_theme_constant(&"space_5", &"Space")
	sheet.custom_minimum_size.x = minf(SHEET_WIDTH, canvas.x - 2.0 * margin)
	var chrome := sheet.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	var room := canvas.y - 2.0 * margin - chrome
	var wanted := _content.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(wanted, 0.0, maxf(room, 0.0))


func _on_after_animate_in() -> void:
	if confirm_button != null:
		confirm_button.grab_focus()
	elif cancel_button != null:
		cancel_button.grab_focus()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


## Closes the sheet (after an install, or when the flow is done with it).
func dismiss() -> void:
	if _closing:
		return
	_closing = true
	animate_out()


func _on_confirm_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"confirm")
	install_confirmed.emit(card, _replace)
	animate_out()


func _on_cancel_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"cancel")
	cancelled.emit()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
