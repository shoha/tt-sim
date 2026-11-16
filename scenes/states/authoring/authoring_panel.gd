class_name AuthoringPanel
extends DrawerContainer

## Authoring mode's tool drawer on the left edge, in detached rail mode (card ui-authoring3): a
## rounded rail capsule of seven tools that stands still, a separate rounded card beside it, and a
## small floating pill of session actions (AuthoringActions: Undo, Redo, Save, Leave) to the right
## of whichever is outermost. The card's content is the map's name, the one text field in
## authoring, over one pane per tool. The tools, their order, rail items and pane titles come from
## ToolRegistry (one ToolDescriptor each); the panes of the tools that predate it are built here
## (_build_pane), and a tool added since brings its own (ToolDescriptor.build_pane). Built in code;
## every interactive Control is named so the validation bridge can click it.
##
## Hubs. The rail lists seven tools; three of them are hubs whose card has top tabs
## (SegmentedTabs): Place (Add, Thin / Clear), Water (River, Pond, Crossing) and Build (Walls,
## Buildings, Villages). A tab is a former rail tool: it shows that tool's own pane and picks its
## brush, exactly as its rail item did, so every tool id, brush mode and pane is unchanged
## (ToolDescriptor.hub and tabs). A rail press or the tool's key opens the hub's last tab, and the
## key pressed again steps to the next tab. Signals still carry tool ids (tool_selected(&"bridge"));
## the rail item that is tinted and pressed is the hub's.
##
## The panel owns no map state. It relays what the author does as signals to
## AuthoringController and shows what the controller tells it (dirty, undo/redo
## availability). It is also authoring's Escape handler: registered with UIManager for the
## whole session, its request_close() closes the drawer when it is open and otherwise asks
## to leave (the controller prompts when there are unsaved changes).
##
## Tools. Picking a rail item selects that brush (tool_selected; the controller activates
## BrushTool), and picking a tile in a pane selects what it paints or places (biome_selected,
## place_selected), which also re-activates a brush the author had put down with a right
## click. Each pane says its gestures in its header caption and holds nothing else in the
## main flow: size and strength are gestures (Shift+wheel, dwell), and an Advanced foldout
## per brush pane has the exact size and strength rows, values hidden like the Visuals
## drawer's. The active tool's rail item stays tinted while the drawer is closed. Sculpt and
## Paint are disabled, with a tooltip saying why, on a dressed Blender map
## (set_sculpt_available, set_paint_available).
##
## Water (P4-4): the River and Pond tabs, then Ankle / Waist / Deep tiles with a hint line and
## the Width row; on a dressed Blender map it only erases water painted over it
## (set_water_available). Bridge (P4b-2) is Water's Crossing tab, its own tool and pane
## (set_bridge_available).
##
## Paint (P3-6): one TileField per surface role (Built, Ground, Rock) of palette surface swatches,
## one selection across the groups, built once by ensure_paint_tiles() (the controller calls it
## under the loading screen). The Built tiles are ordered for the map (order_paint_tiles): the
## path surfaces of the biomes on it first, then the rest in palette order; until the author
## picks a surface, the first of them is the one selected.

signal save_pressed
signal leave_pressed
signal undo_pressed
signal redo_pressed
signal name_changed(new_name: String)
signal biome_selected(biome_id: String)
signal tool_selected(tool_id: StringName)
## The Pick up button of the put-down notice: the tool whose brush was put down.
signal pick_up_requested(tool_id: StringName)
## A Place tile was picked: species `species_key` of palette biome `biome_id`.
signal place_selected(biome_id: String, species_key: String)
## A Sculpt tile was picked: HeightBrush.RAISE, SMOOTH, FLATTEN or TIER.
signal sculpt_selected(tile: int)
## A Paint tile was picked: palette surface `surface`.
signal paint_selected(surface: String)
## An Advanced row moved: brush radius (metres) or strength (flow multiplier).
signal brush_size_changed(radius: float)
signal brush_strength_changed(flow: float)
## A Water tile was picked: the shape (WaterBrush.Shape) or the depth (WaterBody.Depth).
signal water_shape_selected(shape: int)
signal water_depth_selected(depth: int)
## The Water Advanced flow row moved (WaterBody speed).
signal water_speed_changed(speed: float)
## A Bridge tile was picked: the crossing kind (Crossing.Kind).
signal bridge_kind_selected(kind: int)
## A tool's own pane was built, on its first show (or a tool_pane() request).
signal tool_pane_built(tool_id: StringName, pane: Control)

## The drawer width token (UI_TASTE S5), as the room drawer: at 320 the two-column biome
## tiles' longest labels (Riverside Wetland) ran within a few px of the tile edges at 720p.
## 364 virtual px is about 340 real px in a 1280x720 window; the Wall pane's tiles are the widest
## content (a narrower drawer pushed them a pixel past the name field).
const DRAWER_WIDTH := 364.0
const BIOME_TILE_SIZE := Vector2(64, 74)
const BIOME_THUMB_PX := 36
const BIOME_COLUMNS := 3
## The extra step over a section label after a hint paragraph (AuthoringPanes.section_gap).
const SECTION_ABOVE := 8
const PLACE_TILE_SIZE := Vector2(64, 56)
const PLACE_COLUMNS := 3
## Species size classes the Place picker offers; ground cover is only ever painted.
const PLACE_SIZE_CLASSES := ["large", "medium", "small"]
## Tile icon per palette species kind; anything else gets PLACE_DEFAULT_ICON.
const PLACE_ICONS := {"tree": "tree", "palm": "tree", "cactus": "tree", "grass": "leaf"}
const PLACE_DEFAULT_ICON := "grain"

## The ids of the seven tools that predate ToolRegistry (their descriptors own them).
const TOOL_BIOME := BiomeTool.ID
const TOOL_THIN := ThinTool.ID
const TOOL_PLACE := PlaceTool.ID
const TOOL_SCULPT := SculptTool.ID
const TOOL_PAINT := PaintTool.ID
const TOOL_WATER := WaterTool.ID
const TOOL_BRIDGE := BridgeTool.ID
## The panes the panel builds itself (_build_pane), when the drawer opens: the controller sets
## their fields during the open. Every other tool's pane is built on first show.
const OWN_PANES := [
	TOOL_BIOME, TOOL_THIN, TOOL_PLACE, TOOL_SCULPT, TOOL_PAINT, TOOL_WATER, TOOL_BRIDGE
]
const ACTION_UNDO := AuthoringChrome.ACTION_UNDO
const ACTION_REDO := AuthoringChrome.ACTION_REDO
const ACTION_SAVE := AuthoringChrome.ACTION_SAVE
const ACTION_LEAVE := AuthoringChrome.ACTION_LEAVE

## Rail tooltips of the tools a map can refuse, from their descriptors.
const SCULPT_TOOLTIP := SculptTool.LABEL
const SCULPT_UNAVAILABLE_TOOLTIP := SculptTool.UNAVAILABLE_TOOLTIP
const PAINT_TOOLTIP := PaintTool.LABEL
const PAINT_UNAVAILABLE_TOOLTIP := PaintTool.UNAVAILABLE_TOOLTIP
const WATER_TOOLTIP := WaterTool.LABEL
const WATER_UNAVAILABLE_TOOLTIP := WaterTool.UNAVAILABLE_TOOLTIP
const WATER_ERASE_ONLY_TOOLTIP := WaterToolPane.ERASE_ONLY_HINT
const BRIDGE_TOOLTIP := BridgeTool.LABEL
const BRIDGE_UNAVAILABLE_TOOLTIP := BridgeTool.UNAVAILABLE_TOOLTIP
## Paint groups in pane order: palette surface role and caption.
const PAINT_GROUPS: Array[Dictionary] = [
	{"role": "built", "caption": "Built"},
	{"role": "ground", "caption": "Ground"},
	{"role": "cliff", "caption": "Rock"},
]
const PAINT_TILE_SIZE := Vector2(64, 84)
const PAINT_THUMB_PX := 52
const PAINT_COLUMNS := 3
## Paint tile ids (and node names) are this prefix plus the palette surface name.
const PAINT_TILE_PREFIX := "paint_"
## The surface the Paint tool starts with: a path is what a new map most often wants. The legacy
## value of the `paint.default` library binding (LibraryBindings.paint_default).
const DEFAULT_PAINT_SURFACE := "dirt_road_packed"
## Sculpt tiles: id (the HeightBrush operation), label, icon, tooltip (SculptTool owns them).
const SCULPT_TILES: Array[Dictionary] = SculptTool.TILES
const SCULPT_TILE_SIZE := Vector2(64, 56)

## Palette root the biome tiles come from; tests point it elsewhere.
var palette_root: String = PaletteLibrary.DEFAULT_ROOT

var name_edit: LineEdit
var biome_field: TileField
var sculpt_field: TileField
## Place tiles, one TileRow per biome group; ids are "<biome id>|<species key>".
var place_rows: Dictionary = {}
## Paint tiles: role -> TileField (built by ensure_paint_tiles()).
var paint_fields: Dictionary = {}
## The Water tool's pane (its tiles and Advanced rows).
var water_pane: WaterToolPane
## The Bridge tool's pane (its kind tiles).
var bridge_pane: BridgeToolPane

var _stack: PaneStack
## The actions pill (AuthoringActions), which glides with the card.
var _actions: AuthoringActions
## The hubs' top tabs by rail id, the tab each last showed, and the shape Water's River and Pond
## tabs stand for (WaterBrush.Shape).
var _hub_tabs: Dictionary = {}
var _hub_last: Dictionary = {}
var _title_row: AuthoringTitleRow
var _water_shape: int = WaterBrush.Shape.RIVER
## Every Advanced size / strength row, kept in step with the brush.
var _size_rows: Array[PropertyRow] = []
var _strength_rows: Array[PropertyRow] = []
var _place_foldouts: Dictionary = {}
## The "Other biomes" caption in the Place pane: the current biome's group stands above it.
var _place_others: Control
## Paint tile buttons by surface, and the tooltip each has when it can be picked.
var _paint_tiles: Dictionary = {}
var _paint_tooltips: Dictionary = {}
## The Paint swatches' warm-up an open started (SwatchTextures.warm_start), {} when none.
var _swatch_job: Dictionary = {}
var _paint_surface: String = LibraryBindings.paint_default()
## True once the author picked a Paint tile; until then ordering may change the default.
var _paint_picked: bool = false
## The biomes the Built tiles were last ordered for (order_paint_tiles).
var _paint_order_biomes: PackedStringArray = PackedStringArray()
var _active_tool: StringName = &""
var _fit_queued: bool = false
## True while the controller's leave prompt is on screen, so Escape does not stack another.
var _leave_pending: bool = false
## The card a right click puts up while a brush is down (PutDownNotice).
var _put_down: PutDownNotice


func _on_ready() -> void:
	name = "AuthoringPanel"
	edge = DrawerEdge.LEFT
	drawer_width = DRAWER_WIDTH
	tab_width = 44.0
	play_sounds = true
	start_revealed = false
	rail_items = ToolRegistry.rail_items(ToolDescriptor.AUTHORING)
	rail_item_size = AuthoringChrome.RAIL_ITEM_SIZE
	rail_group_gap = AuthoringChrome.RAIL_GROUP_GAP
	rail_chip = true
	rail_detached = true
	# A tall pane (Paint, Buildings) scrolls inside about four fifths of the board, not all of it
	# (0.85: at 720p, 0.8 left Buildings only one row and a half).
	max_height_fraction = 0.85

	margin_variation = &"DrawerMarginRoomy"

	_build_name_field()
	_put_down = PutDownNotice.new()
	_put_down.pick_up_requested.connect(func(id: StringName) -> void: pick_up_requested.emit(id))
	content_container.add_child(_put_down)
	_build_hub_tabs()
	_actions = AuthoringActions.new()
	_actions.visible = false
	_actions.action_pressed.connect(_on_action_pressed)
	add_child(_actions)
	_stack = PaneStack.new()
	_stack.name = "PaneStack"
	_stack.slide_from_right = false
	_stack.bar_in_margin = true
	_stack.more_below_fade = true
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(_stack)
	fit_height = AuthoringChrome.FIT_HEIGHT
	# The card is as tall as the pane on show: it follows a swap and anything that changes the
	# pane's height (a foldout, a filter, the put-down card).
	_stack.pane_changed.connect(func(_id: StringName) -> void: _queue_fit())
	_stack.pane_built.connect(
		func(id: StringName, pane: Control) -> void:
			pane.minimum_size_changed.connect(_queue_fit)
			AuthoringPanes.hide_titles(pane)
			tool_pane_built.emit(id, pane)
	)
	_margin.minimum_size_changed.connect(_queue_fit)
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		if tool.brush_mode == null:
			continue  # A hub with no brush (Build): its tabs' tools have the panes.
		if tool.id in OWN_PANES:
			var pane := tool.build_pane(self)
			if pane == null:
				pane = _build_pane(tool)
			pane.minimum_size_changed.connect(_queue_fit)
			AuthoringPanes.hide_titles(pane)
			_stack.add_pane(tool.id, pane)
		else:
			# A tool's own pane (fire's EventsPane, the structure and village tiles and their
			# thumbnails) is built when it is first shown, not in the open's first frame.
			_stack.add_pane_builder(tool.id, _tool_pane_builder.bind(tool))
	_stack.show_pane(TOOL_BIOME, false)
	_title_row.show_tool(ToolRegistry.find(TOOL_BIOME))

	pane_requested.connect(_on_pane_requested)


func _ready() -> void:
	super._ready()
	set_history_state(false, false)
	_place_actions(false)
	_queue_fit()
	var dimmer := CardDimmer.new()
	dimmer.name = "CardDimmer"
	dimmer.card = _panel
	dimmer.rail = _rail_panel
	dimmer.is_open = func() -> bool: return is_open
	add_child(dimmer)


## Asks for the card to be fitted once this frame's changes are in (one fit per frame).
func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit_to_pane.call_deferred()


func _fit_to_pane() -> void:
	_fit_queued = false
	if not fit_height or _stack == null:
		return
	var pane := _stack.get_pane(_stack.current) if _stack.current != &"" else null
	fit_panel_height(AuthoringChrome.panel_height(_margin, _stack, pane))


## The map's name, one field at the head of every pane. It has no caption line of its own (the
## pane's title is what the drawer is about): the tooltip and the accessible name say what it is.
func _build_name_field() -> void:
	name_edit = LineEdit.new()
	name_edit.name = "MapNameEdit"
	name_edit.tooltip_text = "Map name: click to rename"
	name_edit.accessibility_name = "Map name"
	name_edit.placeholder_text = NewMap.DEFAULT_NAME
	name_edit.text_changed.connect(func(text: String) -> void: name_changed.emit(text))
	name_edit.text_submitted.connect(func(_text: String) -> void: name_edit.release_focus())
	content_container.add_child(name_edit)
	content_container.add_child(HSeparator.new())


## Builds the pane of a tool that brings its own (ToolDescriptor.build_pane); a placeholder
## that says so when it brings none.
func _tool_pane_builder(tool: ToolDescriptor) -> Control:
	var pane := tool.build_pane(self)
	if pane == null:
		push_error("AuthoringPanel: tool %s has no pane" % tool.id)
		pane = VBoxContainer.new()
	return pane


func _build_pane(tool: ToolDescriptor) -> Control:
	match tool.id:
		TOOL_BIOME:
			return AuthoringPanes.biome(self, tool)
		TOOL_PLACE:
			return AuthoringPanes.place(self, tool)
		TOOL_SCULPT:
			return AuthoringPanes.sculpt(self, tool)
		TOOL_PAINT:
			return AuthoringPanes.paint(self, tool)
		TOOL_WATER:
			return AuthoringPanes.water(self)
		TOOL_BRIDGE:
			return AuthoringPanes.bridge(self)
	return null


## A tool's pane (ToolRegistry id), built now if it was not yet, or null.
func tool_pane(id: StringName) -> Control:
	return _stack.get_pane(id)


## Whether a tool's pane has been built (a tool's own pane is built on first show).
func is_tool_pane_built(id: StringName) -> bool:
	return _stack.is_built(id)


## Enables a tool's rail item with its tooltip, or disables it with the descriptor's
## unavailable_tooltip saying why.
func set_tool_available(id: StringName, available: bool) -> void:
	var tool := ToolRegistry.find(id)
	if tool == null:
		return
	if tool.on_rail:
		set_rail_item_enabled(id, available)
		set_rail_item_tooltip(id, tool.rail_tip_for(available))
		return
	# A tab of a hub (Bridge, Wall, Structure, Village, Thin / Clear): its tab, with the reason.
	var strip: SegmentedTabs = _hub_tabs.get(tool.hub)
	var tab_id := _tab_id_for(tool.hub, id)
	if strip != null and tab_id != &"":
		var tip := String(_tab_of(tool.hub, tab_id)["tip"])
		strip.set_tab_enabled(
			tab_id, available, tip if available else tool.unavailable_tooltip
		)


## Shows the Water tool's exact width (metres, the full channel) and flow, without signals.
func set_water_values(width: float, speed: float) -> void:
	water_pane.set_values(width, speed)


## Enables the Water tool: fully where water can be carved; where it cannot (a dressed
## Blender map) only when the map already has water to erase, with the River and Pond tiles
## disabled and the tooltips and hint saying why; otherwise disabled with a tooltip.
func set_water_available(carves: bool, has_water: bool) -> void:
	set_tool_available(TOOL_WATER, carves or has_water)
	if not carves and has_water:
		set_rail_item_tooltip(TOOL_WATER, WATER_ERASE_ONLY_TOOLTIP)
	water_pane.set_carves(carves)


## Enables the Bridge tool, or disables it with a tooltip saying why (a dressed Blender map
## with no water painted over it: crossings snap to the document's water). `has_water`: the
## pane's line saying to make water first shows while it is false.
func set_bridge_available(available: bool, has_water: bool) -> void:
	set_tool_available(TOOL_BRIDGE, available)
	bridge_pane.set_has_water(has_water)


## Collects start_paint_swatches()'s warm-up ahead of ensure_paint_tiles(), starting one if none.
func warm_paint_swatches_async(tree: SceneTree, is_superseded: Callable) -> void:
	if _paint_tiles.is_empty():
		if _swatch_job.is_empty():
			start_paint_swatches()
		var job := _swatch_job
		_swatch_job = {}
		await SwatchTextures.warm_finish_async(job, tree, is_superseded)


## Starts the Paint swatches on workers as an open begins (SwatchTextures.warm_start, no bakes).
func start_paint_swatches() -> void:
	if _paint_tiles.is_empty():
		SwatchTextures.drop(_swatch_job)
		var albedos := SwatchTextures.paint_albedos(PAINT_GROUPS, palette_root)
		_swatch_job = SwatchTextures.warm_start(albedos, PAINT_THUMB_PX, palette_root)


## Builds the Paint tiles once (palette surfaces by role, swatches from each surface's
## albedo; see the header). Safe to call again.
func ensure_paint_tiles() -> void:
	if not _paint_tiles.is_empty():
		return
	var surfaces := PaletteLibrary.surfaces(palette_root)
	for group in PAINT_GROUPS:
		var field: TileField = paint_fields[group.role]
		for surface in PaletteLibrary.surfaces_with_role(String(group.role), palette_root):
			var tooltip := paint_tooltip(surface, String(group.role))
			var tile := field.tiles.add_tile(
				paint_tile_id(surface),
				surface_label(surface),
				"",
				tooltip,
				SwatchTextures.palette_thumbnail(
					surfaces.get(surface, {}).get("albedo", ""), PAINT_THUMB_PX, palette_root
				)
			)
			_paint_tiles[surface] = tile
			_paint_tooltips[surface] = tooltip
	select_paint_surface(_paint_surface)
	_apply_paint_order()


## Orders the Built tiles for a map with the palette biomes `biome_ids` on it (see the
## header); a no-op when they are unchanged. Returns true when the selected surface changed
## because the author has not picked one yet (the caller hands it to the brush).
func order_paint_tiles(biome_ids: PackedStringArray) -> bool:
	if biome_ids == _paint_order_biomes:
		return false
	_paint_order_biomes = biome_ids.duplicate()
	var before := _paint_surface
	_apply_paint_order()
	return _paint_surface != before


func _apply_paint_order() -> void:
	if _paint_tiles.is_empty():
		return
	var field: TileField = paint_fields.get("built")
	var built := PaletteLibrary.surfaces_with_role("built", palette_root)
	var order := paint_order(built, _paint_order_biomes, palette_root)
	for index in order.size():
		var tile: Button = _paint_tiles.get(order[index])
		if tile != null:
			field.tiles.move_child(tile, index)
	if not _paint_picked:
		var listed := listed_paths(built, _paint_order_biomes, palette_root)
		select_paint_surface(
			listed[0] if not listed.is_empty() else LibraryBindings.paint_default()
		)


## The Built tiles' order for a map with `biome_ids` on it: every listed biome's
## path_surfaces, in biome order and deduplicated, then the other `built` surfaces in their
## own (palette) order. Only surfaces in `built` appear; with no paths listed it is `built`.
static func paint_order(
	built: Array[String], biome_ids: PackedStringArray, root: String
) -> Array[String]:
	var order := listed_paths(built, biome_ids, root)
	for surface in built:
		if not surface in order:
			order.append(surface)
	return order


## The path surfaces `biome_ids` list (in biome order, deduplicated) that are in `built`.
static func listed_paths(
	built: Array[String], biome_ids: PackedStringArray, root: String
) -> Array[String]:
	var listed: Array[String] = []
	for biome_id in biome_ids:
		for surface in PaletteLibrary.path_surfaces(biome_id, root):
			if surface in built and not surface in listed:
				listed.append(surface)
	return listed


## A palette surface's readable name ("dirt_road_packed" -> "Dirt track"): the Paint tiles'
## labels and the history labels of Paint strokes. The name is the `label` in the surface's
## surface.json (SurfaceStore.label_of); a surface without one is its id spelled out.
static func surface_label(surface: String) -> String:
	var library_label := SurfaceStore.label_of(surface)
	if library_label != "":
		return library_label
	return species_label(surface)


## A Paint tile's tooltip: the surface's name and what painting it does.
static func paint_tooltip(surface: String, role: String) -> String:
	var label := surface_label(surface)
	match role:
		"built":
			return "%s: a walkable built surface; clears the plants under it" % label
		"cliff":
			return "%s: rock; restyles a cliff face, or bares rock anywhere" % label
	return "%s: ground; covers walkable ground, rock faces stay rock" % label


## The tile id (and node name) of a Paint tile.
static func paint_tile_id(surface: String) -> StringName:
	return StringName(PAINT_TILE_PREFIX + surface)


## The surface of a Paint tile id, or "".
static func paint_tile_surface(id: StringName) -> String:
	var text := String(id)
	return text.trim_prefix(PAINT_TILE_PREFIX) if text.begins_with(PAINT_TILE_PREFIX) else ""


func _on_paint_tile(id: StringName, source: TileRow) -> void:
	# One selection across the groups: picking in one clears the others.
	for field: TileField in paint_fields.values():
		if field.tiles != source:
			field.tiles.select(&"")
	var surface := paint_tile_surface(id)
	if surface != "":
		_paint_surface = surface
		_paint_picked = true
		paint_selected.emit(surface)


## Selects a Paint tile without emitting paint_selected.
func select_paint_surface(surface: String) -> void:
	_paint_surface = surface
	for field: TileField in paint_fields.values():
		var id := paint_tile_id(surface)
		field.tiles.select(id if field.tiles.has_tile(id) else &"")


## The surface picked in the Paint pane.
func get_paint_surface() -> String:
	return _paint_surface


## Shows which Paint tiles can be picked: with every paint slot taken (`full_reason` not
## ""), the surfaces not in `in_use` are disabled and their tooltip says why; else all are
## enabled with their own tooltips.
func set_paint_limits(full_reason: String, in_use: PackedStringArray) -> void:
	for surface in _paint_tiles:
		var tile: Button = _paint_tiles[surface]
		var blocked: bool = full_reason != "" and not surface in in_use
		tile.disabled = blocked
		tile.tooltip_text = full_reason if blocked else String(_paint_tooltips[surface])


## Enables Paint, or disables it with a tooltip saying why (a dressed Blender map).
func set_paint_available(available: bool) -> void:
	set_tool_available(TOOL_PAINT, available)


## The tile id of a Sculpt tile's operation ("sculpt_raise", ...; also its node name), or
## &"" for an operation without a tile.
static func sculpt_tile_id(op: int) -> StringName:
	for tile in SCULPT_TILES:
		if int(tile.op) == op:
			return StringName("sculpt_" + String(tile.label).to_lower())
	return &""


## The Sculpt operation of a tile id, or -1.
static func sculpt_tile_op(id: StringName) -> int:
	for tile in SCULPT_TILES:
		if sculpt_tile_id(int(tile.op)) == id:
			return int(tile.op)
	return -1


## Enables Sculpt, or disables it with a tooltip saying why (a dressed Blender map, whose
## ground is the GLB's own).
func set_sculpt_available(available: bool) -> void:
	set_tool_available(TOOL_SCULPT, available)


## The species of a biome the Place picker offers (PLACE_SIZE_CLASSES), in palette order.
static func place_species(biome_id: String, root: String) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	for rule in PaletteLibrary.species(biome_id, root):
		if String(rule.get("size_class", "")) in PLACE_SIZE_CLASSES:
			picked.append(rule)
	return picked


## A readable tile label for a species key: "dwarf_pine" -> "Dwarf pine".
static func species_label(key: String) -> String:
	var words := key.replace("_", " ").strip_edges()
	return words.left(1).to_upper() + words.substr(1) if words != "" else key


func _on_place_tile(id: StringName, source: TileRow) -> void:
	# One selection across every group: picking in one clears the others.
	for row: TileRow in place_rows.values():
		if row != source:
			row.select(&"")
	var parts := String(id).split("|")
	if parts.size() == 2:
		place_selected.emit(parts[0], parts[1])


## A brush pane's Size row, in the main flow under the header (the picker and the size are the
## basics, ui-authoring3; they were behind Advanced): the label over a full-width slider, values
## hidden. It follows the brush (set_brush_values), as do all the panes' rows.
func build_size_row(prefix: String) -> PropertyRow:
	var size_row := PropertyRow.new()
	size_row.name = prefix + "BrushSize"
	size_row.label = "Size"
	# Stacked as every drawer slider row is: the label over a full-width slider.
	size_row.stacked = true
	size_row.min_value = BrushTool.MIN_RADIUS
	size_row.max_value = BrushTool.MAX_RADIUS
	size_row.step = 0.1
	size_row.value = BrushTool.session_radius
	size_row.hint_low = "Small"
	size_row.hint_high = "Large"
	size_row.formatter = func(value: float) -> String: return "%.1f m" % value
	size_row.value_changed.connect(func(value: float) -> void: brush_size_changed.emit(value))
	_size_rows.append(size_row)
	return size_row


## The Advanced foldout of a brush pane: the strength row, value hidden by default. Its row
## follows the brush (set_brush_values); a tool's own pane (FireToolPane) adds one too.
func build_advanced(prefix: String) -> Foldout:
	var foldout := Foldout.new()
	foldout.name = prefix + "Advanced"
	foldout.title = "Advanced"
	var strength_row := PropertyRow.new()
	strength_row.name = prefix + "BrushStrength"
	strength_row.label = "Strength"
	strength_row.stacked = true
	strength_row.min_value = BrushTool.MIN_FLOW
	strength_row.max_value = BrushTool.MAX_FLOW
	strength_row.step = 0.05
	strength_row.value = BrushTool.session_flow
	strength_row.hint_low = "Gentle"
	strength_row.hint_high = "Strong"
	strength_row.value_changed.connect(
		func(value: float) -> void: brush_strength_changed.emit(value)
	)
	foldout.add_child(strength_row)
	_strength_rows.append(strength_row)
	return foldout


## A tile label short enough for a two-column tile: at most the last two words of the
## palette's name ("Temperate Deciduous Forest" shows "Deciduous Forest"; the tooltip has
## the whole name). Two-word names are what the palette mostly uses and stay whole.
static func short_name(full_name: String) -> String:
	var words := full_name.split(" ", false)
	if words.size() <= 2:
		return full_name
	return " ".join(words.slice(words.size() - 2))


## Goes to a tool as its rail item does when pressed (a pane's own button, such as the Village
## pane's "Draw a street"): the rail selects it and its pane shows.
func request_tool(id: StringName) -> void:
	if not is_open:
		return
	var rail_id := ToolRegistry.hub_of(id)
	if not _hub_tabs.has(rail_id):
		_on_rail_item_pressed(id)
		return
	_hub_last[rail_id] = _tab_id_for(rail_id, id)
	if _rail.selected == rail_id:
		# Already on this hub (the Village pane's "Draw a street" goes to Walls): only the tab
		# changes, and the rail item pressed again would close the card.
		_open_tab(_hub_last[rail_id], rail_id)
	else:
		_on_rail_item_pressed(rail_id)


## A rail item was pressed (the rail's id: a tool, or a hub): its pane shows and its tool is picked.
func _on_pane_requested(rail_id: StringName) -> void:
	_enter_rail(rail_id, false)


## Shows the pane of tool `id` (a rail tool or a tab's tool; the controller follows a tool chosen by
## other means), with its hub's tabs and the tab marked.
func show_tool_pane(id: StringName) -> void:
	if id == TOOL_PAINT:
		ensure_paint_tiles()
	var rail_id := ToolRegistry.hub_of(id)
	_show_hub_tabs(rail_id)
	_mark_tab(rail_id, id)
	_stack.show_pane(id)


## Picks rail tool `rail_id` as its key does: the rail item is selected (while the card is open),
## the pane shows, and a hub opens on its last tab, or on the next one when this tool is the one
## already out (the key pressed again steps through Build's Walls, Buildings, Villages).
func pick_rail_tool(rail_id: StringName) -> void:
	var again := _active_tool != &"" and ToolRegistry.hub_of(_active_tool) == rail_id
	if is_open and _rail != null and _rail.has_item(rail_id):
		_rail.select(rail_id)
	_enter_rail(rail_id, again)


## The tab of hub `rail_id` that is showing (&"" for a tool without tabs).
func current_tab(rail_id: StringName) -> StringName:
	var strip: SegmentedTabs = _hub_tabs.get(rail_id)
	return strip.selected if strip != null else &""


## The hub's top tabs (SegmentedTabs), or null for a tool without tabs.
func hub_tabs(rail_id: StringName) -> SegmentedTabs:
	return _hub_tabs.get(rail_id)


func _build_hub_tabs() -> void:
	_title_row = AuthoringTitleRow.new()
	content_container.add_child(_title_row)
	for tool in ToolRegistry.rail_tools(ToolDescriptor.AUTHORING):
		if tool.tabs.is_empty():
			continue
		var strip := SegmentedTabs.new()
		strip.name = String(tool.id).capitalize() + "Tabs"
		strip.visible = false
		for tab in tool.tabs:
			strip.add_tab(StringName(tab["id"]), String(tab["label"]), String(tab["tip"]))
		strip.tab_selected.connect(_open_tab.bind(tool.id))
		content_container.add_child(strip)
		_hub_tabs[tool.id] = strip
		_hub_last[tool.id] = StringName(tool.tabs[0]["id"])


## Shows only hub `rail_id`'s tabs (&"" or a tool without tabs: none), and names the tool in the
## card's title row (AuthoringTitleRow).
func _show_hub_tabs(rail_id: StringName) -> void:
	for id: StringName in _hub_tabs:
		(_hub_tabs[id] as Control).visible = id == rail_id
	_title_row.show_tool(ToolRegistry.find(rail_id) if rail_id != &"" else null)


## Opens rail tool `rail_id`: a plain tool shows its pane and is picked; a hub opens its last tab,
## or with `step` the next enabled one (and its first enabled one when the last is disabled).
func _enter_rail(rail_id: StringName, step: bool) -> void:
	var strip: SegmentedTabs = _hub_tabs.get(rail_id)
	if strip == null:
		_show_hub_tabs(rail_id)
		if rail_id == TOOL_PAINT:
			ensure_paint_tiles()
		_stack.show_pane(rail_id)
		tool_selected.emit(rail_id)
		return
	var tab_id: StringName = _hub_last[rail_id]
	if step or strip.tab(tab_id).disabled:
		tab_id = strip.next_enabled(tab_id)
	_open_tab(tab_id, rail_id)


## Shows tab `tab_id` of hub `rail_id` and picks its tool as the old rail item did: Water's River
## and Pond set the brush's shape, any other tab selects its tool.
func _open_tab(tab_id: StringName, rail_id: StringName) -> void:
	var tab := _tab_of(rail_id, tab_id)
	if tab.is_empty():
		return
	_hub_last[rail_id] = tab_id
	_show_hub_tabs(rail_id)
	(_hub_tabs[rail_id] as SegmentedTabs).select(tab_id)
	var tool_id := StringName(tab["tool"])
	if tool_id == TOOL_PAINT:
		ensure_paint_tiles()
	_stack.show_pane(tool_id)
	_quiet_header(tool_id)
	if tab.has("shape"):
		_water_shape = int(tab["shape"])
		if water_pane != null:
			water_pane.show_shape(_water_shape)
		water_shape_selected.emit(_water_shape)
	else:
		tool_selected.emit(tool_id)


## A tab's pane keeps its summary line but not its title: the tab above it is the title ("Walls"
## over a pane headed "Wall" read as two names for one thing, and the line is height a 720p card
## needs).
func _quiet_header(tool_id: StringName) -> void:
	var pane := _stack.get_pane(tool_id)
	if pane == null:
		return
	for header: Node in pane.find_children("*", "MenuHeader", true, false):
		(header as MenuHeader).title_label.visible = false


## Hub `rail_id`'s tab `tab_id` as the descriptor declares it, {} when there is none.
func _tab_of(rail_id: StringName, tab_id: StringName) -> Dictionary:
	var rail_tool := ToolRegistry.find(rail_id)
	if rail_tool != null:
		for tab in rail_tool.tabs:
			if StringName(tab["id"]) == tab_id:
				return tab
	return {}


## The id of the tab of hub `rail_id` that runs tool `tool_id`, preferring the River or Pond tab
## that matches the Water shape, or &"" when there is none.
func _tab_id_for(rail_id: StringName, tool_id: StringName) -> StringName:
	var rail_tool := ToolRegistry.find(rail_id)
	if rail_tool == null:
		return &""
	var found: StringName = &""
	for tab in rail_tool.tabs:
		if StringName(tab["tool"]) != tool_id:
			continue
		if found == &"":
			found = StringName(tab["id"])
		if tab.has("shape") and int(tab["shape"]) == _water_shape:
			return StringName(tab["id"])
	return found


## Marks the tab of hub `rail_id` for tool `tool_id` as the one showing, without a signal.
func _mark_tab(rail_id: StringName, tool_id: StringName) -> void:
	var tab_id := _tab_id_for(rail_id, tool_id)
	if tab_id == &"":
		return
	_hub_last[rail_id] = tab_id
	(_hub_tabs[rail_id] as SegmentedTabs).select(tab_id)


## Water's tabs follow a shape picked another way (Tab on the board), without a signal.
func select_water_shape(shape: int) -> void:
	_water_shape = shape
	if water_pane != null:
		water_pane.show_shape(shape)
	var strip: SegmentedTabs = _hub_tabs.get(TOOL_WATER)
	if strip == null or strip.selected == BridgeTool.ID:
		return
	_mark_tab(TOOL_WATER, TOOL_WATER)


func _on_action_pressed(id: StringName) -> void:
	match id:
		ACTION_UNDO:
			undo_pressed.emit()
		ACTION_REDO:
			redo_pressed.emit()
		ACTION_SAVE:
			save_pressed.emit()
		ACTION_LEAVE:
			leave_pressed.emit()


# ============================================================================
# The actions pill
# ============================================================================


## Slides the pill and the card together: both follow the board's free edge, so the pill stands
## right of whichever is outermost (the rail alone when the card is shut, the card when open).
func _animate_to_state() -> void:
	super._animate_to_state()
	_place_actions(true)


## Puts the pill beside the rail, or the card while it is open, level with their tops, and shows it
## once the drawer is revealed. `animate`: it eases with the card (cut under Reduce motion).
func _place_actions(animate: bool) -> void:
	if _actions == null:
		return
	var x := FLOAT_MARGIN + tab_width + FLOAT_GAP
	if is_open:
		x += drawer_width + FLOAT_GAP
	var seconds := slide_duration if is_open else UiMotion.PANEL_OUT_S
	_actions.glide_to(Vector2(x, tab_top_margin), is_revealed, seconds if animate else 0.0)


## The actions pill (AuthoringActions).
func actions() -> AuthoringActions:
	return _actions


# ============================================================================
# State shown by the controller
# ============================================================================


## Shows the map's name without emitting name_changed.
func set_map_name(map_name: String) -> void:
	name_edit.text = map_name


func get_map_name() -> String:
	var text := name_edit.text.strip_edges()
	return text if text != "" else NewMap.DEFAULT_NAME


## Badges Save while there are unsaved changes.
func set_dirty(dirty: bool) -> void:
	_actions.set_dirty(dirty, AuthoringChrome.save_tip(dirty))


## Undo and Redo are drawn live only while they have something to do, and their tooltips say
## what: "Undo Raise (Ctrl+Z)" while there is an edit to take back, "Nothing to undo" when not.
## `undo_label` and `redo_label` name the edit each would act on ("" when unknown).
func set_history_state(
	can_undo: bool, can_redo: bool, undo_label: String = "", redo_label: String = ""
) -> void:
	_actions.set_history(
		can_undo,
		can_redo,
		AuthoringChrome.history_tip("Undo", "Ctrl+Z", can_undo, undo_label),
		AuthoringChrome.history_tip("Redo", "Ctrl+Y", can_redo, redo_label)
	)


## Selects a biome tile without emitting biome_selected, and opens that biome's Place group, which
## leads the Place pane (just above the "Other biomes" caption).
func select_biome(biome_id: String) -> void:
	biome_field.tiles.select(StringName(biome_id))
	var chosen: Foldout = _place_foldouts.get(biome_id)
	if chosen == null:
		return
	chosen.expanded = true
	AuthoringPanes.lead_place(_place_others, chosen)


## Selects a Sculpt tile without emitting sculpt_selected.
func select_sculpt_tile(op: int) -> void:
	sculpt_field.tiles.select(sculpt_tile_id(op))


## Selects a Place tile without emitting place_selected ("" clears every group).
func select_place(biome_id: String, species_key: String) -> void:
	for group_id in place_rows:
		var row: TileRow = place_rows[group_id]
		row.select(StringName(biome_id + "|" + species_key) if group_id == biome_id else &"")


## Tints the rail item of the active brush tool (&"" for none).
func set_active_tool(tool_id: StringName) -> void:
	if _active_tool != &"":
		set_rail_item_active(ToolRegistry.hub_of(_active_tool), false)
	_active_tool = tool_id
	if tool_id != &"":
		var rail_id := ToolRegistry.hub_of(tool_id)
		set_rail_item_active(rail_id, true)
		if _hub_tabs.has(rail_id):
			_mark_tab(rail_id, tool_id)
		hide_put_down()


## Says the brush of tool `tool_id` was put down with a right click and how to pick it up
## (PutDownNotice): a card above the pane, and the pane's tiles drawn unpicked, until a brush is
## out again.
func show_put_down(tool_id: StringName) -> void:
	var tool := ToolRegistry.find(tool_id)
	if tool != null:
		_put_down.show_for(tool, tool_pane(tool_id))


func hide_put_down() -> void:
	if _put_down != null:
		_put_down.hide_notice()


## True while the put-down notice is showing.
func is_put_down_shown() -> bool:
	return _put_down != null and _put_down.visible


func get_active_tool() -> StringName:
	return _active_tool


## Shows the brush's size and strength in every Advanced foldout, without signals.
func set_brush_values(radius: float, flow: float) -> void:
	for row in _size_rows:
		row.set_value_no_signal(radius)
	for row in _strength_rows:
		row.set_value_no_signal(flow)


# ============================================================================
# Escape
# ============================================================================


## Shows the rail and takes over Escape for the session.
func begin_session() -> void:
	reveal()
	UIManager.register_overlay(self)


## Releases Escape (the session is over).
func end_session() -> void:
	UIManager.unregister_overlay(self)


## UIManager pops the overlay before calling this, so every branch that stays in authoring
## re-registers it, or the next Escape would find nothing to close.
func request_close() -> void:
	UIManager.register_overlay(self)
	if _is_animating or _leave_pending:
		return
	if is_open:
		close()
		return
	leave_pressed.emit()


## The controller brackets its leave prompt with these, so Escape during the prompt goes
## to the prompt alone.
func set_leave_pending(pending: bool) -> void:
	_leave_pending = pending
