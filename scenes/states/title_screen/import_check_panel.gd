class_name ImportCheckPanel
extends AnimatedCanvasLayerPanel

## The import check, shown before anything is written (contract: docs/ASSET_PIPELINE.md
## section 11): what a map file holds, read by GlbCheck, on a sheet over the library. Its rows
## are the file and its size, the map's size in feet and metres (with the current map's size
## beside it on Replace), where its ground sits against Y = 0, and what it holds in plain
## words; then each warning on a line of its own with the warning icon in the warning role,
## each saying what to do about it. Warnings never block. A refused file (a .gltf, a .tscn,
## anything that is not a self-contained .glb) shows its one sentence and Close alone.
##
## Two uses. Import (open_import): a name field (MapImport.default_name) and Add to library,
## which emits import_confirmed; the title runs MapImport.import_glb and selects the new card.
## Replace (open_replace: a .glb dropped on a card, Replace map file..., or Reload from
## Blender): the level's edits decide the choices, and every button names its action. Edits
## over a Blender map (painting, props and plants: LibraryFacts' one word for them) offer
## "Replace, keep edits", captioned with what it removes (keep_preview: the props and the
## generated plants outside the new map, MapImport's props_dropped and scatter_dropped),
## beside "Replace, start fresh" (the edits set aside); a map made here offers starting fresh
## only, and a map with no edits one Replace map. replace_confirmed carries the mode. No
## file name of the game's own appears in the copy.
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
const KEEP := "Replace, keep edits"
const FRESH := "Replace, start fresh"
const REPLACE := "Replace map"
const KEEP_ALL := "Keeping your edits keeps all of your painting, props and plants."
## What keeping the edits removes: "... 1 prop sits outside the new map and will be removed."
const KEEP_SOME := (
	"Keeping your edits keeps your painting; %s outside the new map and will be removed."
)
const FRESH_LINE := "Sets your edits aside and starts again from the new map"
const FRESH_CHOICE := "Starting fresh sets your edits aside."
const MADE_HERE_LINE := (
	"This map was made here, so a Blender map can only replace it from a fresh start."
)
const UNDER_TENTH_MB := "under 0.1 MB"
## Below this the ground is at Y = 0, as far as the facts say.
const LEVEL_M := 0.05

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


## The rows a filled report shows: [[label, value], ...]. On Replace `now_ft` is the current
## map's size in feet, shown beside the new one (Vector2.ZERO: a new map). Pure.
static func fact_rows(check: Dictionary, now_ft := Vector2.ZERO) -> Array:
	var rows: Array = []
	rows.append(["File", String(check.get("path", "")).get_file()])
	rows.append(["File size", mb_text(float(check.get("mb", 0.0)))])
	if bool(check.get("has_bounds", false)):
		var metres: Vector2 = check.footprint_m
		var feet := LibraryFacts.size_text(check.footprint_ft)
		var size := "%s (%.1f × %.1f m)" % [feet, metres.x, metres.y]
		if now_ft != Vector2.ZERO:
			rows.append(["Map size now", LibraryFacts.size_text(now_ft)])
			rows.append(["New map size", size])
		else:
			rows.append(["Map size", size])
		rows.append(["Ground", floor_text(float(check.floor_m))])
	rows.append(["Contents", holds_text(check)])
	return rows


## "2.4 MB", or UNDER_TENTH_MB for a file that would round to 0.0. Pure.
static func mb_text(mb: float) -> String:
	return UNDER_TENTH_MB if mb < 0.05 else "%.1f MB" % mb


## Where the lowest ground sits against Y = 0, the same way above and below: "At Y = 0",
## "1.5 m above Y = 0", "3.0 m below Y = 0". Pure.
static func floor_text(floor_m: float) -> String:
	if absf(floor_m) < LEVEL_M:
		return "Lowest point at Y = 0"
	var side := "above" if floor_m > 0.0 else "below"
	return "Lowest point %.1f m %s Y = 0" % [absf(floor_m), side]


## What the file holds, in plain words: the ground (in pieces when it is several), water, the
## plants and rocks scattered on it and its own light and sky. Pure.
static func holds_text(check: Dictionary) -> String:
	var parts := PackedStringArray()
	var meshes := int(check.get("meshes", 0))
	parts.append("the ground" if meshes <= 1 else "the ground in %d pieces" % meshes)
	if int(check.get("water_planes", 0)) > 0:
		parts.append("water")
	var extras: Dictionary = check.get("extras", {})
	var instances := int(extras.get("scatter_instances", 0))
	if instances > 0:
		var kinds := int(extras.get("scatter_species", 0))
		var of_kinds := "1 kind" if kinds == 1 else "%d kinds" % kinds
		parts.append("%d plants and rocks of %s" % [instances, of_kinds])
	if bool(extras.get("ambient_light", false)) or bool(extras.get("background_color", false)):
		parts.append("its own light and sky")
	var last := parts[parts.size() - 1]
	var text := last
	if parts.size() > 1:
		text = ", ".join(parts.slice(0, parts.size() - 1)) + " and " + last
	return text.substr(0, 1).to_upper() + text.substr(1)


## What keeping the edits of level folder `folder` removes over the map `check` reads, without
## writing: {"dressed": the level has edits over a Blender map, "made_here": its document is
## a map made here, "props" and "plants": those outside the new map, "dropped": their sum}.
static func keep_preview(folder: String, check: Dictionary) -> Dictionary:
	var out := {"dressed": false, "made_here": false, "props": 0, "plants": 0, "dropped": 0}
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
		out.props = int(kept.props_dropped)
		out.plants = int(kept.scatter_dropped)
		out.dropped = out.props + out.plants
	return out


func _build_facts() -> void:
	facts = GridContainer.new()
	facts.name = "Facts"
	facts.columns = 2
	facts.theme_type_variation = &"FactsGrid"
	_body.add_child(facts)
	var now_ft := Vector2.ZERO
	if _folder != "":
		now_ft = LibraryFacts.footprint_ft(LevelManager.folder_info(_folder))
	for row: Array in fact_rows(report, now_ft):
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
		_show_choice(keep_line(int(preview.props), int(preview.plants)) + " " + FRESH_CHOICE)
	else:
		confirm_button = _button("ReplaceButton", REPLACE, &"Primary")
		confirm_button.pressed.connect(_choose.bind(MapImport.KEEP_DRESSING))


## The caption of keeping the edits, for `props` props and `plants` plants outside the new
## map. Pure.
static func keep_line(props: int, plants: int = 0) -> String:
	if props + plants <= 0:
		return KEEP_ALL
	return KEEP_SOME % removed_words(props, plants)


## "1 prop sits", "3 plants sit", "1 prop and 2 plants sit": what lies outside a new map. Pure.
static func removed_words(props: int, plants: int) -> String:
	var parts := PackedStringArray()
	if props > 0:
		parts.append("1 prop" if props == 1 else "%d props" % props)
	if plants > 0:
		parts.append("1 plant" if plants == 1 else "%d plants" % plants)
	var verb := "sits" if props + plants == 1 else "sit"
	return "%s %s" % [" and ".join(parts), verb]


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
