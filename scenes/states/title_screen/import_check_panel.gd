class_name ImportCheckPanel
extends AnimatedCanvasLayerPanel

## The import check, shown before anything is written (contract: docs/ASSET_PIPELINE.md
## section 11): what a map file holds, read by GlbCheck, on a sheet over the library. Its rows
## are the file and its size in MB, the footprint in metres and feet, the floor, and what the
## scene extras hold; then each warning on a line of its own with the warning icon. Warnings
## never block. A refused file (a .gltf, a .tscn, anything that is not a self-contained .glb)
## shows its one sentence and Close alone.
##
## Two uses. Import (open_import): a name field (MapImport.default_name) and Add to library,
## which emits import_confirmed; the title runs MapImport.import_glb and selects the new card.
## Replace (open_replace, a .glb dropped on a card, or Reload from Blender): the level's
## dressing decides the choices. A dressing over a Blender map offers Keep dressing, captioned
## with what it drops (keep_preview: the props and generated plants off the new map, the sum
## of MapImport's props_dropped and scatter_dropped), beside Start fresh (the dressing kept
## aside as map.ttmap.bak); a map made here offers Start fresh only, and a map with no
## document one Replace map. replace_confirmed carries the mode.
##
## Built in code (no scene): the scrim, the centring and the sheet the base class expects.

signal import_confirmed(path: String, level_name: String)
signal replace_confirmed(folder: String, path: String, mode: String)
signal closed

const SHEET_WIDTH := 600.0
const IMPORT_TITLE := "Import a map"
const REPLACE_TITLE := "Replace the map under %s"
const REFUSED_TITLE := "This file cannot be imported"
const ADD := "Add to library"
const KEEP := "Keep dressing"
const FRESH := "Start fresh"
const REPLACE := "Replace map"
const KEEP_ALL := "Keeps your painting, props and plants."
const KEEP_ONE := "Keeps your painting; the one prop or plant off the new map is dropped."
const KEEP_SOME := "Keeps your painting; %d props and plants off the new map are dropped."
const FRESH_LINE := "Sets your dressing aside as map.ttmap.bak and starts from the new map."
const FRESH_CHOICE := "Start fresh sets it aside as map.ttmap.bak."
const MADE_HERE_LINE := (
	"This map's ground was made here, so only Start fresh can put a Blender map under it."
)

## The check shown.
var report: Dictionary = {}
var header: MenuHeader
var facts: GridContainer
var warnings_box: VBoxContainer
var name_edit: LineEdit
var choice_line: Label
## The sheet's one primary: Add to library, Keep dressing, Start fresh or Replace map.
var confirm_button: Button
## Start fresh beside Keep dressing (Replace with a dressing), or null.
var fresh_button: Button
var cancel_button: Button

var _folder := ""
var _closing := false
var _body: VBoxContainer
var _footer: HBoxContainer


func _init() -> void:
	name = "ImportCheckPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
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


## Shows `check` (GlbCheck.check) for a new level. Call before adding the panel to the tree.
func open_import(check: Dictionary) -> void:
	report = check
	_folder = ""


## Shows `check` for Replace on level folder `folder`. Call before adding it to the tree.
func open_replace(check: Dictionary, folder: String) -> void:
	report = check
	_folder = folder


func _on_panel_ready() -> void:
	header = MenuHeader.new()
	header.name = "Header"
	_body.add_child(header)
	header.close_requested.connect(_on_cancel_pressed)
	var refused := String(report.get("error", "")) != ""
	var file := String(report.get("path", "")).get_file()
	if refused:
		header.setup(REFUSED_TITLE, file, true)
		_add_line(String(report.error), "alert-circle", ThemeColors.DANGER)
	else:
		var title := IMPORT_TITLE if _folder == "" else REPLACE_TITLE % _level_name()
		header.setup(title, "Nothing is written until you choose.", true)
		_build_facts()
		_build_warnings()
		if _folder == "":
			_build_name()
	_build_footer(refused)
	UIManager.register_overlay($ColorRect as Control)


## The rows a filled report shows: [[label, value], ...]. Pure.
static func fact_rows(check: Dictionary) -> Array:
	var rows: Array = []
	rows.append(["File", String(check.get("path", "")).get_file()])
	rows.append(["Size", "%.1f MB" % float(check.get("mb", 0.0))])
	if bool(check.get("has_bounds", false)):
		var metres: Vector2 = check.footprint_m
		var feet: Vector2 = check.footprint_ft
		rows.append(
			[
				"Footprint",
				"%.1f x %.1f m (%d x %d ft)" % [metres.x, metres.y, roundi(feet.x), roundi(feet.y)]
			]
		)
		rows.append(["Floor", "Lowest ground at %.2f m" % float(check.floor_m)])
	rows.append(["Holds", holds_text(check)])
	return rows


## What the file holds besides its ground, in words: meshes, water, scatter, the scene's light.
## Pure.
static func holds_text(check: Dictionary) -> String:
	var parts := PackedStringArray()
	var meshes := int(check.get("meshes", 0))
	parts.append("1 mesh" if meshes == 1 else "%d meshes" % meshes)
	var water := int(check.get("water_planes", 0))
	if water > 0:
		parts.append("water" if water == 1 else "%d water planes" % water)
	var extras: Dictionary = check.get("extras", {})
	var instances := int(extras.get("scatter_instances", 0))
	if instances > 0:
		var kinds := int(extras.get("scatter_species", 0))
		var of_kinds := "1 kind" if kinds == 1 else "%d kinds" % kinds
		parts.append("%d scattered plants and rocks of %s" % [instances, of_kinds])
	if bool(extras.get("ambient_light", false)) or bool(extras.get("background_color", false)):
		parts.append("the scene's light")
	return ", ".join(parts)


## What Keep dressing drops from level folder `folder` over the map `check` reads, without
## writing: {"dressed": the level has a dressing over a Blender map, "made_here": its document
## is a map made here, "dropped": props and generated rows off the new map}.
static func keep_preview(folder: String, check: Dictionary) -> Dictionary:
	var out := {"dressed": false, "made_here": false, "dropped": 0}
	var path := LevelManager.map_document_path(folder)
	if folder == "" or not FileAccess.file_exists(path):
		return out
	var doc: MapDocument = MapDocumentIO.read(path).document
	if doc == null:
		return out
	if not doc.has_base_map:
		out.made_here = true
		return out
	out.dressed = true
	if bool(check.get("has_bounds", false)):
		var kept := DressingReconcile.keep(doc, check.bounds)
		out.dropped = int(kept.props_dropped) + int(kept.scatter_dropped)
	return out


func _build_facts() -> void:
	facts = GridContainer.new()
	facts.name = "Facts"
	facts.columns = 2
	_body.add_child(facts)
	for row: Array in fact_rows(report):
		var label := Label.new()
		label.text = String(row[0])
		label.theme_type_variation = &"Caption"
		facts.add_child(label)
		var value := Label.new()
		value.text = String(row[1])
		value.theme_type_variation = &"Body"
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		facts.add_child(value)


func _build_warnings() -> void:
	warnings_box = VBoxContainer.new()
	warnings_box.name = "Warnings"
	warnings_box.theme_type_variation = &"BoxContainerTight"
	_body.add_child(warnings_box)
	for warning: Dictionary in report.get("warnings", []):
		_add_line(String(warning.text), "alert-triangle", ThemeColors.WARNING, warnings_box)
	warnings_box.visible = warnings_box.get_child_count() > 0


func _build_name() -> void:
	var row := HBoxContainer.new()
	row.name = "NameRow"
	row.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(row)
	var label := Label.new()
	label.text = "Name"
	label.theme_type_variation = &"Caption"
	row.add_child(label)
	name_edit = LineEdit.new()
	name_edit.name = "Name"
	name_edit.text = MapImport.default_name(String(report.get("path", "")))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_text: String) -> void: _on_confirm_pressed())
	row.add_child(name_edit)


## A line with a tinted icon (a warning, a refusal), under `parent` (the body by default).
func _add_line(text: String, icon: String, role: StringName, parent: Control = null) -> void:
	var row := HBoxContainer.new()
	row.theme_type_variation = &"BoxContainerSpaced"
	(parent if parent != null else _body).add_child(row)
	var mark := TextureRect.new()
	mark.texture = IconButton.load_icon(icon)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(20, 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mark.self_modulate = ThemeColors.of(row, role)
	row.add_child(mark)
	var words := Label.new()
	words.text = text
	words.theme_type_variation = &"Body"
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.custom_minimum_size.x = 200
	row.add_child(words)


func _build_footer(refused: bool) -> void:
	choice_line = Label.new()
	choice_line.name = "ChoiceLine"
	choice_line.theme_type_variation = &"Caption"
	choice_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_line.visible = false
	_body.add_child(choice_line)
	_body.add_child(HSeparator.new())
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.alignment = BoxContainer.ALIGNMENT_END
	_footer.theme_type_variation = &"BoxContainerSpaced"
	_body.add_child(_footer)
	cancel_button = _button("CancelButton", "Close" if refused else "Cancel", &"Secondary")
	cancel_button.pressed.connect(_on_cancel_pressed)
	if refused:
		return
	if _folder == "":
		confirm_button = _button("AddButton", ADD, &"Primary")
		confirm_button.pressed.connect(_on_confirm_pressed)
		return
	var preview := keep_preview(_folder, report)
	if preview.made_here:
		confirm_button = _button("FreshButton", FRESH, &"Primary")
		confirm_button.pressed.connect(_choose.bind(MapImport.START_FRESH))
		_show_choice(MADE_HERE_LINE)
	elif preview.dressed:
		fresh_button = _button("FreshButton", FRESH, &"Secondary")
		fresh_button.tooltip_text = FRESH_LINE
		fresh_button.pressed.connect(_choose.bind(MapImport.START_FRESH))
		confirm_button = _button("KeepButton", KEEP, &"Primary")
		confirm_button.pressed.connect(_choose.bind(MapImport.KEEP_DRESSING))
		_show_choice(keep_line(int(preview.dropped)) + " " + FRESH_CHOICE)
	else:
		confirm_button = _button("ReplaceButton", REPLACE, &"Primary")
		confirm_button.pressed.connect(_choose.bind(MapImport.KEEP_DRESSING))


## Keep dressing's caption for `dropped` props and plants off the new map. Pure.
static func keep_line(dropped: int) -> String:
	if dropped <= 0:
		return KEEP_ALL
	if dropped == 1:
		return KEEP_ONE
	return KEEP_SOME % dropped


func _show_choice(text: String) -> void:
	choice_line.text = text
	choice_line.visible = true


func _button(node_name: String, label: String, variation: StringName) -> Button:
	var button := AnimatedButton.new()
	button.name = node_name
	button.text = label
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(120, 0)
	button.set_meta("ui_silent", true)
	_footer.add_child(button)
	return button


func _level_name() -> String:
	var info := LevelManager.folder_info(_folder)
	return "“%s”" % String(info.get("name", _folder))


func _on_after_animate_in() -> void:
	if name_edit != null:
		name_edit.grab_focus()
		name_edit.select_all()
	elif confirm_button != null:
		confirm_button.grab_focus()
	else:
		cancel_button.grab_focus()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


func _on_confirm_pressed() -> void:
	if _closing or _folder != "":
		return
	_closing = true
	AudioManager.play(&"confirm")
	import_confirmed.emit(String(report.get("path", "")), name_edit.text.strip_edges())
	animate_out()


func _choose(mode: String) -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"confirm")
	replace_confirmed.emit(_folder, String(report.get("path", "")), mode)
	animate_out()


func _on_cancel_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"cancel")
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
