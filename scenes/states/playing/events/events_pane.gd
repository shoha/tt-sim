class_name EventsPane
extends VBoxContainer

## The GM's Events pane: the Visuals drawer's "events" rail item (LevelEditPanel), so it is the
## GM's alone; players never see the drawer. It changes the map for everyone at the table,
## live and undoable (UI_TASTE I4), with the map-building brushes that exist in play
## (ToolRegistry.tools(ToolDescriptor.PLAY): Biome, Thin / Clear, Sculpt, Paint, Water,
## Bridge). PlayEvents arms and puts away the brush and tells the pane what to show; the pane
## owns no map state.
##
## Layout, top down: the header (its subtitle says what the pane does; how to work and undo
## is the picked brush's gesture line and the hint bar's, so no intro repeats them), a
## notice line for a map that takes no live edits (a Blender map without a document,
## LiveEdits.refusal), the Brushes tiles, then the picked brush's own controls, built from
## the authoring panes'
## parts: the Sculpt tiles (AuthoringPanel.SCULPT_TILES), the palette biome and surface tiles
## (thumbnails and labels as AuthoringPanel draws them), WaterToolPane and BridgeToolPane as
## they are (their own headers hidden: the tile above names the brush), and one Advanced
## foldout with the exact size and strength. The presets with spectacle (EventPresets: a bridge
## dropping, trees toppling) have their own field above Brushes, under EventPresets.HEADING;
## the picked tool's controls stand directly under its own field (show_tool moves them), so a
## picked preset's gesture line, and Topple's Advanced size, sit under the preset tiles rather
## than two rows away under the Brushes grid.
##
## The preset and Brushes tiles toggle: pressing the armed one's tile again puts it away, so
## they are multi-select TileRows kept to one pressed tile across both by hand. A preset put
## away takes its controls with it (PlayEvents forgets the pick), so the pane is as fresh;
## a brush put away keeps its controls, whose picks arm it again.
##
## Spacing (UI_TASTE S4): a group's heading has more room above it than below. The groups,
## and a brush's gesture line and its own tiles' heading, stand BoxContainerSpaced apart
## (SPACE_3); every heading sits SPACE_1 above its tiles (TileField).

## A preset or Brushes tile was pressed: `on` picks the tool, off puts it away.
signal tool_toggled(tool_id: StringName, on: bool)
signal sculpt_selected(op: int)
signal biome_selected(biome_id: String)
signal paint_selected(surface: String)
signal water_shape_selected(shape: int)
signal water_depth_selected(depth: int)
signal water_speed_changed(speed: float)
signal bridge_kind_selected(kind: int)
signal brush_size_changed(radius: float)
signal brush_strength_changed(flow: float)

const TITLE := "Events"
const SUMMARY := "Change the map for everyone at the table."
const TOOL_TILE_SIZE := Vector2(64, 56)
const TOOL_COLUMNS := 3
const BIOME_COLUMNS := 3
## Each brush's gesture line. Water and Bridge show theirs in place of their authoring panes'
## paragraph, which repeats the hint bar's keys at length.
const TOOL_HINTS := {
	BiomeTool.ID: "Pick a biome, then drag on the board; linger to thicken it.",
	ThinTool.ID: "Drag to thin trees and plants out; hold Ctrl as you press to clear the ground.",
	SculptTool.ID:
	"Drag to shape the ground; linger to build. Hold Ctrl as you press to lower, Shift to smooth.",
	PaintTool.ID: "Pick a surface, then drag on the board. Hold Ctrl as you press to erase paint.",
	WaterTool.ID:
	(
		"Draw a river from where the water comes to where it goes, or paint a pond."
		+ " Hold Ctrl as you press to erase water."
	),
	BridgeTool.ID:
	"Drag a line across a river or pond, bank to bank. Hold Ctrl and click a crossing to remove it.",
	EventPresets.COLLAPSE: "Click a bridge: it breaks and falls into the water for everyone.",
	EventPresets.TOPPLE:
	"Click in a forest: the marked trees fall away from the click. Drag out for a wider stand.",
}

var palette_root: String = PaletteLibrary.DEFAULT_ROOT
var preset_field: TileField
var tool_field: TileField
var notice: Label
var biome_field: TileField
var sculpt_field: TileField
## Paint tiles by role (AuthoringPanel.PAINT_GROUPS), filled on first show (ensure_paint_tiles).
var paint_fields: Dictionary = {}
var water_pane: WaterToolPane
var bridge_pane: BridgeToolPane

## Each brush's controls by tool id; only the picked brush's show, in _options_holder.
var _options: Dictionary = {}
var _options_holder: VBoxContainer
var _advanced: Foldout
var _size_row: PropertyRow
var _strength_row: PropertyRow
var _paint_surfaces: Array[String] = []


func _init() -> void:
	name = "EventsPane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"BoxContainerSpaced"


func _ready() -> void:
	var header := MenuHeader.new()
	header.name = "EventsHeader"
	header.setup(TITLE, SUMMARY)
	add_child(header)
	notice = _caption("EventsNotice", "")
	notice.visible = false
	add_child(notice)
	preset_field = _tiles_field("EventsPresetField", EventPresets.HEADING, EventPresets.all())
	add_child(preset_field)
	tool_field = _tiles_field("EventsToolField", "Brushes", ToolRegistry.tools(ToolDescriptor.PLAY))
	add_child(tool_field)
	_build_options()
	_advanced = _build_advanced()
	add_child(_advanced)
	show_tool(&"")


## The ids of the brushes the pane lists, in tile order.
func tool_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for tool in ToolRegistry.tools(ToolDescriptor.PLAY):
		ids.append(tool.id)
	return ids


## The ids of the presets the pane lists, in tile order.
func preset_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for preset in EventPresets.all():
		ids.append(preset.id)
	return ids


## Shows `tool_id`'s controls (&"" for none; a brush or a preset) directly under its own
## field, its tile pressed while `pressed` (it is out, or waits on a pick in its controls).
## A preset's Advanced holds the size alone (no strength: an event has none). Silent.
func show_tool(tool_id: StringName, pressed: bool = true) -> void:
	for id in tool_ids():
		tool_field.tiles.set_tile_on(id, pressed and id == tool_id)
	for id in preset_ids():
		preset_field.tiles.set_tile_on(id, pressed and id == tool_id)
	for id: StringName in _options:
		(_options[id] as Control).visible = id == tool_id
	var preset := EventPresets.find(tool_id) != null
	var field := preset_field if preset else tool_field
	move_child(_options_holder, field.get_index() + 1)
	move_child(_advanced, _options_holder.get_index() + 1)
	var sized := tool_id != &"" and not tool_id in [WaterTool.ID, BridgeTool.ID]
	_advanced.visible = sized and tool_id != EventPresets.COLLAPSE
	_strength_row.visible = not preset
	if tool_id == PaintTool.ID:
		ensure_paint_tiles()


## The notice line: `text` says why the map takes no live edits ("" hides it, and with it the
## brushes stay enabled as available_tools() leaves them).
func set_notice(text: String) -> void:
	notice.text = text
	notice.visible = text != ""


## Enables the Presets and Brushes tiles in `available` (tool id -> true) and disables the
## rest, with the tool's unavailable tooltip saying why.
func set_available(available: Dictionary) -> void:
	var listed: Array[ToolDescriptor] = EventPresets.all().duplicate()
	listed.append_array(ToolRegistry.tools(ToolDescriptor.PLAY))
	for tool in listed:
		var field := preset_field if EventPresets.find(tool.id) != null else tool_field
		var tile := field.tiles.get_node_or_null(NodePath(String(tool.id))) as Button
		if tile == null:
			continue
		var on := bool(available.get(tool.id, false))
		tile.disabled = not on
		var why := tool.unavailable_tooltip if tool.unavailable_tooltip != "" else tool.summary
		# Through the row, so a refit (the drawer opening) keeps it.
		field.tiles.set_tile_tooltip(tool.id, tool.summary if on else why)


## Shows the brush's size and strength in the Advanced rows, without signals.
func set_brush_values(radius: float, flow: float) -> void:
	_size_row.set_value_no_signal(radius)
	_strength_row.set_value_no_signal(flow)


## The picked Paint surface, or "" before the tiles are built and none is picked.
func paint_surface() -> String:
	for field: TileField in paint_fields.values():
		var surface := AuthoringPanel.paint_tile_surface(field.tiles.selected)
		if surface != "":
			return surface
	return ""


## Builds the Paint tiles once (each costs a texture decode, so not before Paint is shown),
## the Built group first and its first path picked, as the authoring pane starts.
func ensure_paint_tiles() -> void:
	if not _paint_surfaces.is_empty():
		return
	var surfaces := PaletteLibrary.surfaces(palette_root)
	for group in AuthoringPanel.PAINT_GROUPS:
		var field: TileField = paint_fields[group.role]
		for surface in PaletteLibrary.surfaces_with_role(String(group.role), palette_root):
			field.tiles.add_tile(
				AuthoringPanel.paint_tile_id(surface),
				AuthoringPanel.surface_label(surface),
				"",
				AuthoringPanel.paint_tooltip(surface, String(group.role)),
				SwatchTextures.palette_thumbnail(
					surfaces.get(surface, {}).get("albedo", ""),
					AuthoringPanel.PAINT_THUMB_PX,
					palette_root
				)
			)
			_paint_surfaces.append(surface)
	select_paint_surface(AuthoringPanel.DEFAULT_PAINT_SURFACE)


## Selects a Paint tile without emitting paint_selected.
func select_paint_surface(surface: String) -> void:
	var id := AuthoringPanel.paint_tile_id(surface)
	for field: TileField in paint_fields.values():
		field.tiles.select(id if field.tiles.has_tile(id) else &"")


func _on_tool_tile(id: StringName, on: bool) -> void:
	tool_toggled.emit(id, on)


## A toggling tile field of `tools` (presets or brushes) under `caption`.
func _tiles_field(node_name: String, caption: String, tools: Array[ToolDescriptor]) -> TileField:
	var field := TileField.new()
	field.name = node_name
	field.caption = caption
	field.tiles.multi_select = true
	field.tiles.tile_min_size = TOOL_TILE_SIZE
	field.tiles.columns = TOOL_COLUMNS
	for tool in tools:
		field.tiles.add_tile(tool.id, tool.label, tool.icon, tool.summary)
	field.tiles.tile_toggled.connect(_on_tool_tile)
	return field


func _build_options() -> void:
	var holder := VBoxContainer.new()
	holder.name = "EventsOptions"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.theme_type_variation = &"BoxContainerSpaced"
	add_child(holder)
	_options_holder = holder
	var listed: Array[ToolDescriptor] = EventPresets.all().duplicate()
	listed.append_array(ToolRegistry.tools(ToolDescriptor.PLAY))
	for tool in listed:
		var box := _build_tool_options(tool.id)
		if box != null:
			holder.add_child(box)
			_options[tool.id] = box


func _build_tool_options(tool_id: StringName) -> Control:
	match tool_id:
		WaterTool.ID:
			water_pane = WaterToolPane.new()
			water_pane.get_node("WaterHeader").visible = false
			(water_pane.get_node("WaterHint") as Label).text = String(TOOL_HINTS[tool_id])
			water_pane.shape_selected.connect(water_shape_selected.emit)
			water_pane.depth_selected.connect(water_depth_selected.emit)
			water_pane.speed_changed.connect(water_speed_changed.emit)
			water_pane.width_changed.connect(
				func(width: float) -> void: brush_size_changed.emit(width * 0.5)
			)
			return water_pane
		BridgeTool.ID:
			bridge_pane = BridgeToolPane.new()
			bridge_pane.get_node("BridgeHeader").visible = false
			(bridge_pane.get_node("BridgeHint") as Label).text = String(TOOL_HINTS[tool_id])
			bridge_pane.kind_selected.connect(bridge_kind_selected.emit)
			return bridge_pane
	var box := VBoxContainer.new()
	box.name = String(tool_id).to_pascal_case() + "Options"
	# The gesture line belongs to the group under it (S2), but its tiles' heading still has
	# more room above than below (S4).
	box.theme_type_variation = &"BoxContainerSpaced"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_caption(box.name + "Hint", String(TOOL_HINTS.get(tool_id, ""))))
	match tool_id:
		BiomeTool.ID:
			biome_field = _biome_field()
			box.add_child(biome_field)
		SculptTool.ID:
			sculpt_field = _sculpt_field()
			box.add_child(sculpt_field)
		PaintTool.ID:
			for group in AuthoringPanel.PAINT_GROUPS:
				var field := TileField.new()
				field.name = "EventsPaint" + String(group.caption) + "Field"
				field.caption = String(group.caption)
				field.tiles.photo_icons = true
				field.tiles.tile_min_size = AuthoringPanel.PAINT_TILE_SIZE
				field.tiles.columns = AuthoringPanel.PAINT_COLUMNS
				field.tiles.selection_changed.connect(_on_paint_tile.bind(field.tiles))
				box.add_child(field)
				paint_fields[group.role] = field
	return box


func _biome_field() -> TileField:
	var field := TileField.new()
	field.name = "EventsBiomeField"
	field.caption = "Biomes"
	field.tiles.photo_icons = true
	field.tiles.tile_min_size = AuthoringPanel.BIOME_TILE_SIZE
	field.tiles.columns = BIOME_COLUMNS
	for biome in PaletteLibrary.biomes(palette_root):
		field.tiles.add_tile(
			StringName(String(biome["id"])),
			AuthoringPanel.short_name(String(biome["name"])),
			"",
			String(biome["name"]),
			BiomeThumbnail.of(biome, AuthoringPanel.BIOME_THUMB_PX, palette_root)
		)
	field.tiles.selection_changed.connect(
		func(id: StringName) -> void: biome_selected.emit(String(id))
	)
	return field


func _sculpt_field() -> TileField:
	var field := TileField.new()
	field.name = "EventsSculptField"
	# "Shape", not authoring's "Brush": the field above is the Brushes.
	field.caption = "Shape"
	field.tiles.tile_min_size = AuthoringPanel.SCULPT_TILE_SIZE
	field.tiles.columns = AuthoringPanel.SCULPT_TILES.size()
	for tile in AuthoringPanel.SCULPT_TILES:
		field.tiles.add_tile(
			AuthoringPanel.sculpt_tile_id(int(tile.op)),
			String(tile.label),
			String(tile.icon),
			String(tile.tooltip)
		)
	field.tiles.select(AuthoringPanel.sculpt_tile_id(HeightBrush.RAISE))
	field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			var op := AuthoringPanel.sculpt_tile_op(id)
			if op >= 0:
				sculpt_selected.emit(op)
	)
	return field


func _on_paint_tile(id: StringName, source: TileRow) -> void:
	# One selection across the groups, as in the authoring pane.
	for field: TileField in paint_fields.values():
		if field.tiles != source:
			field.tiles.select(&"")
	var surface := AuthoringPanel.paint_tile_surface(id)
	if surface != "":
		paint_selected.emit(surface)


## The exact size and strength, values hidden like the authoring panes' Advanced rows.
func _build_advanced() -> Foldout:
	var foldout := Foldout.new()
	foldout.name = "EventsAdvanced"
	foldout.title = "Advanced"
	_size_row = PropertyRow.new()
	_size_row.name = "EventsBrushSize"
	_size_row.label = "Size"
	_size_row.min_value = BrushTool.MIN_RADIUS
	_size_row.max_value = BrushTool.MAX_RADIUS
	_size_row.step = 0.1
	_size_row.value = BrushTool.session_radius
	_size_row.hint_low = "Small"
	_size_row.hint_high = "Large"
	_size_row.formatter = func(value: float) -> String: return "%.1f m" % value
	_size_row.value_changed.connect(func(value: float) -> void: brush_size_changed.emit(value))
	foldout.add_child(_size_row)
	_strength_row = PropertyRow.new()
	_strength_row.name = "EventsBrushStrength"
	_strength_row.label = "Strength"
	_strength_row.min_value = BrushTool.MIN_FLOW
	_strength_row.max_value = BrushTool.MAX_FLOW
	_strength_row.step = 0.05
	_strength_row.value = BrushTool.session_flow
	_strength_row.hint_low = "Gentle"
	_strength_row.hint_high = "Strong"
	_strength_row.value_changed.connect(
		func(value: float) -> void: brush_strength_changed.emit(value)
	)
	foldout.add_child(_strength_row)
	return foldout


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
