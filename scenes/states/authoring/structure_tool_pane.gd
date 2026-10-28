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

const TILE_SIZE := Vector2(96, 92)
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

var _hint: Label
var _empty: Label
var _refs: Array[String] = []


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
