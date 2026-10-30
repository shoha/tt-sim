class_name StructureToolPane
extends VBoxContainer

## The Structure tool's pane in AuthoringPanel and the GM's Events pane: the structures the served
## libraries offer, one tile each (the library's rendered picture and the structure's name),
## grouped by family under the family's name, and a "Mix afresh" button that draws the next lot's
## look again (R). The picked tile is the brush's structure. No numbers: a lot is dragged to its
## size. Built in code; every interactive Control is named. docs/systems/structures.md "The tool".

## A tile was picked: the structure's reference (`<library>:<id>`).
signal structure_selected(ref: String)
## "Mix afresh" was pressed.
signal reroll_requested
## The selected building's bar (card S5): a variant tile (the reference), a stepper pressed (the
## parameter and -1 or 1), the door, redraw, copy, remove and done buttons.
signal variant_picked(ref: String)
signal param_stepped(param: String, direction: int)
signal door_requested
signal redraw_requested
signal copy_requested
signal remove_requested
signal done_requested
## The Decorate row (StructureOrnamentsSection): the ornaments now asked for and the history label,
## and the ivy amount let go at.
signal ornaments_requested(kinds: Array, label: String)
signal ivy_requested(amount: float)

const TILE_SIZE := Vector2(96, 92)
const VARIANT_TILE_SIZE := Vector2(96, 78)
const SELECTION_HINT := (
	"Drag a corner dot to resize, a tab to push a side, the body to move it. Click a tab to put the"
	+ " door there. Q and E turn it. Escape or a click on bare ground lets go."
)
## The recipe parameters the bar steps, in order, with their captions and how a value reads
## (value 0 of floors is the recipe's own, "Auto").
const STEPPED := [
	{"param": "floors", "caption": "Floors", "auto_zero": true},
	{"param": "roof_pitch", "caption": "Roof pitch", "auto_zero": false},
	{"param": "chimneys", "caption": "Chimneys", "auto_zero": false},
	{"param": "ridge", "caption": "Ridge", "auto_zero": true},
	{"param": "jetty", "caption": "Jetty", "auto_zero": false},
	{"param": "ruin", "caption": "Ruin", "auto_zero": false},
]
const TILE_COLUMNS := 2
const THUMB_PX := 56
const HINT := (
	"Click the ground to put the building down, or drag out a corner to size it. Q and E turn it,"
	+ " [ and ] shrink or grow it, R draws it afresh, right-click removes one."
)
const EMPTY := "No library this map uses offers a building."
const SEARCH_PLACEHOLDER := "Find a building"
const NO_MATCH := "No building matches that. Try a family such as cottage, inn or ruin."
const REROLL_TOOLTIP := "Draw the next building's look afresh (R); over a building, redraw that one"

## The family fields, in tile order.
var family_fields: Array[TileField] = []
var reroll_button: Button
## Filters the tiles by name, family and tags (StructurePalette.matches).
var search_edit: LineEdit

## The selected building's bar, shown in place of the palette while a building is selected.
var selection_box: VBoxContainer
var selection_title: Label
var variant_field: TileField
## Stepper rows by parameter name: {"row", "value" (Label), "minus", "plus" (Buttons)}.
var steppers: Dictionary = {}
var door_button: Button
var redraw_button: Button
var copy_button: Button
var remove_button: Button
var done_button: Button
## The Decorate row, between the steppers and the Style tiles.
var ornaments_section: StructureOrnamentsSection

var _hint: Label
var _empty: Label
var _no_match: Label
## The building picked (kept while a search hides its tile), how many the libraries serve, and
## whether the search found none.
var _picked: String = ""
var _served: int = 0
var _found_none: bool = false
var _tools_row: HBoxContainer
var _refs: Array[String] = []
var _variant_refs: Array[String] = []
var _selected_ref: String = ""


func _init() -> void:
	name = "StructurePane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SPACE_2, the step every tool pane keeps between its parts.
	theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "StructureHeader"
	var tool := ToolRegistry.find(StructureTool.ID)
	header.setup(tool.label, tool.summary)
	add_child(header)
	_build_selection()
	_hint = _caption("StructureHint", HINT)
	add_child(_hint)
	_empty = _caption("StructureEmpty", EMPTY)
	add_child(_empty)
	# Search and Mix afresh share one row above the tiles, so neither is lost below 60 of them.
	_tools_row = HBoxContainer.new()
	_tools_row.name = "StructureTools"
	_tools_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tools_row)
	search_edit = LineEdit.new()
	search_edit.name = "StructureSearch"
	search_edit.placeholder_text = SEARCH_PLACEHOLDER
	search_edit.tooltip_text = "Type part of a name, a family or a tag to narrow the tiles"
	search_edit.clear_button_enabled = true
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_changed.connect(func(_text: String) -> void: refresh())
	_tools_row.add_child(search_edit)
	reroll_button = Button.new()
	reroll_button.name = "StructureReroll"
	reroll_button.text = "Mix afresh"
	reroll_button.tooltip_text = REROLL_TOOLTIP
	reroll_button.focus_mode = Control.FOCUS_NONE
	reroll_button.pressed.connect(reroll_requested.emit)
	_tools_row.add_child(reroll_button)
	_no_match = _caption("StructureNoMatch", NO_MATCH)
	_no_match.visible = false
	add_child(_no_match)
	refresh()


## True when the libraries serve `ref` (whether or not the search shows its tile).
func has_ref(ref: String) -> bool:
	return not LibraryStructureStore.structure(ref).is_empty()


## The references the pane lists, in tile order.
func refs() -> Array[String]:
	return _refs


## Fills the tiles from the served libraries again (after a library was imported or removed).
## The tile picked stays picked when its structure is still offered.
func refresh() -> void:
	var picked := picked_ref()
	for field in family_fields:
		remove_child(field)
		field.queue_free()
	family_fields.clear()
	_refs.clear()
	StructureRecipes.ensure_served()
	var rows := LibraryStructureStore.structures()
	var found := StructurePalette.sections(rows, search_edit.text)
	for section: Dictionary in found:
		var key := String(section["key"])
		var members: Array = section["rows"]
		var field := TileField.new()
		field.name = "StructureFamily_" + key.replace(":", "_")
		field.caption = StructurePalette.section_caption(String(section["family"]), members.size())
		field.tiles.photo_icons = true
		field.tiles.tile_min_size = TILE_SIZE
		field.tiles.columns = TILE_COLUMNS
		for row: Dictionary in members:
			var ref := String(row["ref"])
			field.tiles.add_tile(
				StringName(ref),
				String(row["name"]),
				"",
				_tooltip(row),
				StructureThumbnail.of(row, THUMB_PX)
			)
			_refs.append(ref)
		field.tiles.selection_changed.connect(_on_tile.bind(field))
		add_child(field)
		family_fields.append(field)
	_served = rows.size()
	_found_none = found.is_empty()
	var served_refs := PackedStringArray()
	for row: Dictionary in rows:
		served_refs.append(String(row["ref"]))
	if picked != "" and picked in served_refs:
		select_ref(picked)
	elif not _refs.is_empty():
		select_ref(_refs[0])
	else:
		_picked = ""
	_show_palette(not selection_box.visible)


## Shows `ref` picked, without emitting structure_selected. A pick the search hides stays the
## pane's pick (the brush still lays it); its tile shows again when the search lets it through.
func select_ref(ref: String) -> void:
	_picked = ref
	for field in family_fields:
		if field.tiles.has_tile(StringName(ref)):
			field.tiles.select(StringName(ref))
		else:
			field.tiles.clear_selection()


## The reference of the building picked, or "".
func picked_ref() -> String:
	return _picked


## Shows the bar for `structure` (a record of the open document: its recipe and parameters), or,
## with null, the palette again. The palette steps aside while a building is selected, since a
## click then edits that building rather than laying a new one.
func show_selection(structure: Structure) -> void:
	selection_box.visible = structure != null
	_show_palette(structure == null)
	if structure == null:
		_selected_ref = ""
		return
	StructureRecipes.ensure_served()
	_selected_ref = structure.recipe
	var row := LibraryStructureStore.structure(structure.recipe)
	selection_title.text = String(row.get("name", structure.recipe.get_slice(":", 1).capitalize()))
	_show_variants(structure.recipe)
	ornaments_section.show_for(structure)
	var recipe := StructureRecipes.document(structure.recipe)
	var interface: Array = recipe.interface if recipe != null else []
	var exposed: Array = row.get("expose", [])
	for item: Dictionary in STEPPED:
		var param := String(item["param"])
		var stepper: Dictionary = steppers[param]
		var spec := StructureEdit.param_spec(interface, param)
		var offered := not spec.is_empty() and param in exposed
		(stepper["row"] as Control).visible = offered
		if not offered:
			continue
		var value := StructureEdit.param_value(structure.params, interface, param)
		(stepper["value"] as Label).text = _value_text(item, value)
		(stepper["minus"] as Button).disabled = value <= float(spec.get("min", value)) + 0.001
		(stepper["plus"] as Button).disabled = value >= float(spec.get("max", value)) - 0.001


## How a stepped value reads: whole numbers plain, floors and the ridge 0 as "Auto", pitch in
## degrees, the ridge 1 as "Eave" (the eave to the front) and 2 as "Gable" (a gable to it), a ruin
## in percent and a jetty in metres.
static func _value_text(item: Dictionary, value: float) -> String:
	if bool(item["auto_zero"]) and value < 0.5:
		return "Auto"
	if String(item["param"]) == "ridge":
		return "Eave" if value < 1.5 else "Gable"
	if String(item["param"]) == "ruin":
		return "%d %%" % roundi(value * 100.0)
	if String(item["param"]) == "jetty":
		return "%.1f m" % value
	var text := str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
	return text + " deg" if String(item["param"]) == "roof_pitch" else text


## The tiles of the selected building's family (its variants), the building's own picked; none
## when it has no other recipe in its family.
func _show_variants(ref: String) -> void:
	var rows := StructureEdit.variants_of(ref)
	var refs: Array[String] = []
	for row in rows:
		refs.append(String(row["ref"]))
	if refs != _variant_refs:
		_variant_refs = refs
		if variant_field != null:
			selection_box.remove_child(variant_field)
			variant_field.queue_free()
			variant_field = null
		if not rows.is_empty():
			variant_field = TileField.new()
			variant_field.name = "StructureVariants"
			variant_field.caption = "Style"
			variant_field.tiles.photo_icons = true
			variant_field.tiles.tile_min_size = VARIANT_TILE_SIZE
			variant_field.tiles.columns = 2
			for row in rows:
				variant_field.tiles.add_tile(
					StringName(String(row["ref"])),
					String(row["variant"]),
					"",
					"%s: swap the look, keep the footprint." % row["name"],
					StructureThumbnail.of(row, THUMB_PX)
				)
			variant_field.tiles.selection_changed.connect(
				func(id: StringName) -> void: variant_picked.emit(String(id))
			)
			selection_box.add_child(variant_field)
	if variant_field != null:
		variant_field.tiles.select(StringName(ref))


## Shows or hides the palette parts (the hint, the family tiles, Mix afresh).
func _show_palette(shown: bool) -> void:
	_hint.visible = shown
	for field in family_fields:
		if is_instance_valid(field):
			field.visible = shown
	_tools_row.visible = shown and _served > 0
	reroll_button.visible = _tools_row.visible
	_no_match.visible = shown and _served > 0 and _found_none
	_empty.visible = shown and _served == 0


## The selected building's bar: its name, the variant tiles (made when a selection shows), a
## stepper per recipe parameter the library exposes, and the buttons.
func _build_selection() -> void:
	selection_box = VBoxContainer.new()
	selection_box.name = "StructureSelection"
	selection_box.theme_type_variation = &"BoxContainerSnug"
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.visible = false
	add_child(selection_box)
	selection_title = Label.new()
	selection_title.name = "SelectionTitle"
	selection_title.theme_type_variation = &"Heading"
	selection_box.add_child(selection_title)
	selection_box.add_child(_caption("SelectionHint", SELECTION_HINT))
	for item: Dictionary in STEPPED:
		var param := String(item["param"])
		var row := HBoxContainer.new()
		row.name = "Stepper_" + param
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := Label.new()
		caption.text = String(item["caption"])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var minus := _stepper_button("Stepper_%s_less" % param, "-", "Fewer or less")
		minus.pressed.connect(func() -> void: param_stepped.emit(param, -1))
		row.add_child(minus)
		var value := Label.new()
		value.name = "Stepper_%s_value" % param
		value.custom_minimum_size = Vector2(64, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := _stepper_button("Stepper_%s_more" % param, "+", "More or higher")
		plus.pressed.connect(func() -> void: param_stepped.emit(param, 1))
		row.add_child(plus)
		selection_box.add_child(row)
		steppers[param] = {"row": row, "value": value, "minus": minus, "plus": plus}
	ornaments_section = StructureOrnamentsSection.new()
	ornaments_section.ornaments_requested.connect(ornaments_requested.emit)
	ornaments_section.ivy_requested.connect(ivy_requested.emit)
	add_selection_section(ornaments_section)
	# The buttons sit in pairs, the safe ones first, Remove apart from Done. New actions add a row
	# or a section to selection_box before the buttons: use add_selection_section().
	var door_row := _button_row("SelectionRowDoor")
	door_button = _action_button(
		door_row,
		"SelectionDoor",
		"Door to the next side",
		"Put the door on the next side round (or click a side tab)",
		door_requested
	)
	var make_row := _button_row("SelectionRowMake")
	redraw_button = _action_button(
		make_row, "SelectionRedraw", "Redraw", "Draw this building afresh (R)", redraw_requested
	)
	copy_button = _action_button(
		make_row, "SelectionCopy", "Copy", "A copy beside it (Ctrl+D)", copy_requested
	)
	var end_row := _button_row("SelectionRowEnd")
	remove_button = _action_button(
		end_row, "SelectionRemove", "Remove", "Take this building away (Delete)", remove_requested
	)
	done_button = _action_button(
		end_row, "SelectionDone", "Done", "Let go of the building (Escape)", done_requested
	)
	# The buttons go right under the name (Redraw and Copy, the door, then Remove and Done): the
	# Style tiles below are long, and a button must never be a scroll away.
	for at in 3:
		selection_box.move_child([make_row, door_row, end_row][at], 1 + at)


func _stepper_button(button_name: String, text: String, tip: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 0)
	return button


## The extension point for the selected building's bar: adds `section` (a Control, named and
## built by the caller, filled in show_selection's wake from selection_changed) below the
## steppers and above the Style tiles, and returns it. The buttons stay at the top, so Done and
## Remove never scroll away behind a long tile grid.
func add_selection_section(section: Control) -> Control:
	selection_box.add_child(section)
	if variant_field != null:
		selection_box.move_child(section, variant_field.get_index())
	return section


func _button_row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.add_child(row)
	return row


func _action_button(
	row: HBoxContainer, button_name: String, text: String, tip: String, done: Signal
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(done.emit)
	row.add_child(button)
	return button


func _on_tile(id: StringName, from_field: TileField) -> void:
	_picked = String(id)
	for field in family_fields:
		if field != from_field:
			field.tiles.clear_selection()
	structure_selected.emit(String(id))


## A tile's tooltip: what the structure is, its tags, and the size it starts at.
static func _tooltip(row: Dictionary) -> String:
	var size := StructurePlacement.default_size(row)
	var tags := PackedStringArray()
	for tag: Variant in row.get("tags", []):
		tags.append(String(tag))
	return (
		"%s: %s, about %d x %d m. Drag it out to make it bigger or smaller."
		% [row["name"], ", ".join(tags), roundi(size.x), roundi(size.y)]
	)


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
