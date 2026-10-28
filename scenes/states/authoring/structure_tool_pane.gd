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

const TILE_SIZE := Vector2(96, 92)
const VARIANT_TILE_SIZE := Vector2(96, 78)
const SELECTION_HINT := (
	"Drag a corner dot to resize, or a tab to push a side. Click a tab to put the door on that"
	+ " side. Drag the building to move it. Q and E turn it, R redraws it, Ctrl+D copies it, Delete"
	+ " removes it. Escape or a click on bare ground lets go."
)
## The recipe parameters the bar steps, in order, with their captions and how a value reads
## (value 0 of floors is the recipe's own, "Auto").
const STEPPED := [
	{"param": "floors", "caption": "Floors", "auto_zero": true},
	{"param": "roof_pitch", "caption": "Roof pitch", "auto_zero": false},
	{"param": "chimneys", "caption": "Chimneys", "auto_zero": false},
]
const TILE_COLUMNS := 2
const THUMB_PX := 56
const HINT := (
	"Pick a building, then click the ground to put it down, or drag out a corner to size it. It"
	+ " settles on the nearest dry, level ground. Q and E turn it, [ and ] make a click's building"
	+ " smaller or bigger, R draws it afresh. Right-click or Delete removes the one under the"
	+ " cursor."
)
const EMPTY := "No library this map uses offers a building."
const REROLL_TOOLTIP := "Draw the next building's look afresh (R); over a building, redraw that one"

## The family fields, in tile order.
var family_fields: Array[TileField] = []
var reroll_button: Button

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

var _hint: Label
var _empty: Label
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
	reroll_button = Button.new()
	reroll_button.name = "StructureReroll"
	reroll_button.text = "Mix afresh"
	reroll_button.tooltip_text = REROLL_TOOLTIP
	reroll_button.focus_mode = Control.FOCUS_NONE
	reroll_button.pressed.connect(reroll_requested.emit)
	add_child(reroll_button)
	refresh()


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
	var by_family: Dictionary = {}
	for row in rows:
		var key := "%s:%s" % [row["library"], row["family"]]
		if not by_family.has(key):
			by_family[key] = []
		(by_family[key] as Array).append(row)
	for key: String in by_family:
		var members: Array = by_family[key]
		var field := TileField.new()
		field.name = "StructureFamily_" + key.replace(":", "_")
		field.caption = String(members[0]["family"]).capitalize()
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
		move_child(field, reroll_button.get_index())
		family_fields.append(field)
	_empty.visible = rows.is_empty()
	reroll_button.visible = not rows.is_empty()
	if picked != "" and picked in _refs:
		select_ref(picked)
	elif not _refs.is_empty():
		select_ref(_refs[0])
	_show_palette(not selection_box.visible)


## Shows `ref` picked, without emitting structure_selected.
func select_ref(ref: String) -> void:
	for field in family_fields:
		if field.tiles.has_tile(StringName(ref)):
			field.tiles.select(StringName(ref))
		else:
			field.tiles.clear_selection()


## The reference of the tile picked, or "".
func picked_ref() -> String:
	for field in family_fields:
		if is_instance_valid(field) and field.tiles.selected != &"":
			return String(field.tiles.selected)
	return ""


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


## How a stepped value reads: whole numbers plain, floors 0 as "Auto", pitch in degrees.
static func _value_text(item: Dictionary, value: float) -> String:
	if bool(item["auto_zero"]) and value < 0.5:
		return "Auto"
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
			selection_box.move_child(variant_field, selection_title.get_index() + 1)
	if variant_field != null:
		variant_field.tiles.select(StringName(ref))


## Shows or hides the palette parts (the hint, the family tiles, Mix afresh).
func _show_palette(shown: bool) -> void:
	_hint.visible = shown
	for field in family_fields:
		if is_instance_valid(field):
			field.visible = shown
	reroll_button.visible = shown and not _refs.is_empty()
	_empty.visible = shown and _refs.is_empty()


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
	door_button = _action_button(
		"SelectionDoor",
		"Door to the next side",
		"Put the door on the next side round",
		door_requested
	)
	redraw_button = _action_button(
		"SelectionRedraw", "Redraw", "Draw this building afresh (R)", redraw_requested
	)
	copy_button = _action_button(
		"SelectionCopy", "Copy", "A copy beside it (Ctrl+D)", copy_requested
	)
	remove_button = _action_button(
		"SelectionRemove", "Remove", "Take this building away (Delete)", remove_requested
	)
	done_button = _action_button(
		"SelectionDone", "Done", "Let go of the building (Escape)", done_requested
	)


func _stepper_button(button_name: String, text: String, tip: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 0)
	return button


func _action_button(button_name: String, text: String, tip: String, done: Signal) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(done.emit)
	selection_box.add_child(button)
	return button


func _on_tile(id: StringName, from_field: TileField) -> void:
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
