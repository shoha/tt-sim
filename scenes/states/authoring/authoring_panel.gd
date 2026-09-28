class_name AuthoringPanel
extends DrawerContainer

## Authoring mode's tool drawer on the left edge, in rail mode: one rail item per tool
## (Biome, Thin / Clear, Place, Sculpt) above a footer of session actions (Undo, Redo, Save,
## Leave). The drawer content is the map's name, the one text field in authoring, over one
## pane per tool. Built in code; every interactive Control is named so the validation
## bridge can click it.
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
## Water (P4-4): River and Pond tiles, Ankle / Waist / Deep tiles with a hint line saying
## what the depth means for tokens, and an Advanced foldout with the exact width and flow.
## On a dressed Blender map the tool only erases water painted over it
## (set_water_available).
##
## Paint (P3-6): one TileField per surface role (Built, Ground, Rock; built first because
## paths and yards are what the tool is mostly for) of palette surface swatches, one
## selection across the groups. The swatches cost a texture decode each (the whole albedo
## tile, cropped and scaled), so they are built once, by ensure_paint_tiles(), which the
## controller calls under the loading screen and the pane calls on first show. The Built
## tiles are ordered for the map (order_paint_tiles, 2026-09-27): the path surfaces of the
## biomes on it first (palette path_surfaces, in biome order), then the rest in palette
## order, so a badlands map offers its caliche track and sandstone flags before the grey
## flagstone; until the author picks a surface, the first of them is the one selected.

signal save_pressed
signal leave_pressed
signal undo_pressed
signal redo_pressed
signal name_changed(new_name: String)
signal biome_selected(biome_id: String)
signal tool_selected(tool_id: StringName)
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

const DRAWER_WIDTH := 320.0
const BIOME_TILE_SIZE := Vector2(64, 84)
const BIOME_THUMB_PX := 52
const BIOME_COLUMNS := 2
const PLACE_TILE_SIZE := Vector2(64, 56)
const PLACE_COLUMNS := 3
## Species size classes the Place picker offers; ground cover is only ever painted.
const PLACE_SIZE_CLASSES := ["large", "medium", "small"]
## Tile icon per palette species kind; anything else gets PLACE_DEFAULT_ICON.
const PLACE_ICONS := {"tree": "tree", "palm": "tree", "cactus": "tree", "grass": "leaf"}
const PLACE_DEFAULT_ICON := "grain"

const TOOL_BIOME := &"biome"
const TOOL_THIN := &"thin_clear"
const TOOL_PLACE := &"place"
const TOOL_SCULPT := &"sculpt"
const TOOL_PAINT := &"paint"
const TOOL_WATER := &"water"
const ACTION_UNDO := &"undo"
const ACTION_REDO := &"redo"
const ACTION_SAVE := &"save_map"
const ACTION_LEAVE := &"leave_authoring"

const SCULPT_TOOLTIP := "Sculpt"
const SCULPT_UNAVAILABLE_TOOLTIP := "Sculpt: not on a Blender map, whose ground is the map file's"
const PAINT_TOOLTIP := "Paint"
const PAINT_UNAVAILABLE_TOOLTIP := "Paint: not on a Blender map, whose ground is the map file's"
const WATER_TOOLTIP := "Water"
const WATER_UNAVAILABLE_TOOLTIP := "Water: not on a Blender map, whose ground is the map file's"
const WATER_ERASE_ONLY_TOOLTIP := WaterToolPane.ERASE_ONLY_HINT
const RAIL_ITEMS: Array[Dictionary] = [
	{"id": TOOL_BIOME, "icon": "trees", "tooltip": "Biome"},
	{"id": TOOL_THIN, "icon": "eraser", "tooltip": "Thin / Clear"},
	{"id": TOOL_PLACE, "icon": "tree", "tooltip": "Place"},
	{"id": TOOL_SCULPT, "icon": "mountain", "tooltip": SCULPT_TOOLTIP},
	{"id": TOOL_PAINT, "icon": "brush", "tooltip": PAINT_TOOLTIP},
	{"id": TOOL_WATER, "icon": "droplet", "tooltip": WATER_TOOLTIP},
]
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
## The surface the Paint tool starts with: a path is what a new map most often wants.
const DEFAULT_PAINT_SURFACE := "dirt_road_packed"
## Readable names for the built-in palette's surfaces (surface_label(); the rest are
## prettified ids).
const SURFACE_LABELS := {
	"cliff": "Rock",
	"cliff_basalt": "Basalt",
	"cliff_sandstone": "Sandstone",
	"cobblestone": "Cobblestone",
	"dirt": "Dirt",
	"dirt_peat": "Peat",
	"dirt_road_packed": "Dirt track",
	"flagstone": "Flagstone",
	"forest_floor": "Forest floor",
	"grass": "Grass",
	"grass_alpine": "Alpine grass",
	"grass_savanna": "Dry grass",
	"gravel": "Gravel",
	"gravel_sandstone": "Red gravel",
	"moss": "Moss",
	"mud": "Mud",
	"pine_duff": "Pine needles",
	"planks": "Planks",
	"riverbed": "Riverbed",
	"sand": "Sand",
	"sand_red": "Red sand",
	"snow": "Snow",
	"stone_tiles": "Stone tiles",
}
## Sculpt tiles: id (the HeightBrush operation), label, icon, tooltip.
const SCULPT_TILES: Array[Dictionary] = [
	{
		"op": HeightBrush.RAISE,
		"label": "Raise",
		"icon": "arrow-bar-up",
		"tooltip": "Raise a mound; hold Ctrl as you press to lower",
	},
	{
		"op": HeightBrush.SMOOTH,
		"label": "Smooth",
		"icon": "wave-sine",
		"tooltip": "Soften slopes, edges and faces (Shift with any tile)",
	},
	{
		"op": HeightBrush.FLATTEN,
		"label": "Flatten",
		"icon": "fold",
		"tooltip": "Level the ground to the height where you press",
	},
	{
		"op": HeightBrush.TIER,
		"label": "Tier",
		"icon": "stairs-up",
		"tooltip": "Build a rock-faced level one tier up; hold Ctrl as you press to cut one down",
	},
]
const SCULPT_TILE_SIZE := Vector2(64, 56)
const RAIL_FOOTER_ITEMS: Array[Dictionary] = [
	{"id": ACTION_UNDO, "icon": "arrow-back-up", "tooltip": "Undo (Ctrl+Z)"},
	{"id": ACTION_REDO, "icon": "arrow-forward-up", "tooltip": "Redo (Ctrl+Y)"},
	{"id": ACTION_SAVE, "icon": "device-floppy", "tooltip": "Save map"},
	{"id": ACTION_LEAVE, "icon": "door-exit", "tooltip": "Leave map building"},
]
## Tools whose panes exist but whose brushes are not built yet (none since phase 2 T6).
const TOOLS_NOT_READY: Array[StringName] = []

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

var _stack: PaneStack
## Every Advanced size / strength row, kept in step with the brush.
var _size_rows: Array[PropertyRow] = []
var _strength_rows: Array[PropertyRow] = []
var _place_foldouts: Dictionary = {}
## Paint tile buttons by surface, and the tooltip each has when it can be picked.
var _paint_tiles: Dictionary = {}
var _paint_tooltips: Dictionary = {}
var _paint_surface: String = DEFAULT_PAINT_SURFACE
## True once the author picked a Paint tile; until then ordering may change the default.
var _paint_picked: bool = false
## The biomes the Built tiles were last ordered for (order_paint_tiles).
var _paint_order_biomes: PackedStringArray = PackedStringArray()
var _active_tool: StringName = &""
## True while the controller's leave prompt is on screen, so Escape does not stack another.
var _leave_pending: bool = false


func _on_ready() -> void:
	name = "AuthoringPanel"
	edge = DrawerEdge.LEFT
	drawer_width = DRAWER_WIDTH
	tab_width = 44.0
	play_sounds = true
	start_revealed = false
	rail_items = RAIL_ITEMS.duplicate()
	rail_footer_items = RAIL_FOOTER_ITEMS.duplicate()

	var margin_node := _panel.get_child(0) as MarginContainer
	if margin_node:
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			margin_node.add_theme_constant_override(side, 16)

	_build_name_field()
	_stack = PaneStack.new()
	_stack.name = "PaneStack"
	_stack.slide_from_right = false
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(_stack)
	_stack.add_pane(TOOL_BIOME, _build_biome_pane())
	_stack.add_pane(TOOL_THIN, _build_thin_pane())
	_stack.add_pane(TOOL_PLACE, _build_place_pane())
	_stack.add_pane(TOOL_SCULPT, _build_sculpt_pane())
	_stack.add_pane(TOOL_PAINT, _build_paint_pane())
	_stack.add_pane(TOOL_WATER, _build_water_pane())
	_stack.show_pane(TOOL_BIOME, false)

	pane_requested.connect(_on_pane_requested)
	rail_footer_pressed.connect(_on_footer_pressed)


func _ready() -> void:
	super._ready()
	for tool_id in TOOLS_NOT_READY:
		set_rail_item_enabled(tool_id, false)
	set_history_state(false, false)


func _build_name_field() -> void:
	var caption := Label.new()
	caption.name = "MapNameCaption"
	caption.text = "Map name"
	caption.theme_type_variation = &"Caption"
	content_container.add_child(caption)
	name_edit = LineEdit.new()
	name_edit.name = "MapNameEdit"
	name_edit.placeholder_text = NewMap.DEFAULT_NAME
	name_edit.text_changed.connect(func(text: String) -> void: name_changed.emit(text))
	name_edit.text_submitted.connect(func(_text: String) -> void: name_edit.release_focus())
	content_container.add_child(name_edit)
	content_container.add_child(HSeparator.new())


func _build_biome_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.name = "BiomePane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "BiomeHeader"
	header.setup("Biome", "Paint a place onto the map.")
	pane.add_child(header)
	pane.add_child(
		_hint(
			"BiomeHint",
			(
				"Pick a biome, then drag on the map. Linger to thicken it; Shift+wheel or"
				+ " [ and ] size the brush; right-click puts it down."
			)
		)
	)
	biome_field = TileField.new()
	biome_field.name = "BiomeField"
	biome_field.caption = "Biomes"
	biome_field.tiles.photo_icons = true
	biome_field.tiles.tile_min_size = BIOME_TILE_SIZE
	biome_field.tiles.columns = BIOME_COLUMNS
	for biome in PaletteLibrary.biomes(palette_root):
		var id := String(biome["id"])
		biome_field.tiles.add_tile(
			StringName(id),
			short_name(String(biome["name"])),
			"",
			String(biome["name"]),
			SwatchTextures.palette_thumbnail(biome["thumbnail"], BIOME_THUMB_PX, palette_root)
		)
	biome_field.tiles.selection_changed.connect(
		func(id: StringName) -> void: biome_selected.emit(String(id))
	)
	pane.add_child(biome_field)
	pane.add_child(_build_advanced("Biome"))
	return pane


func _build_thin_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.name = "ThinPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "ThinHeader"
	header.setup("Thin / Clear", "Open up what grows.")
	pane.add_child(header)
	pane.add_child(
		_hint(
			"ThinHint",
			(
				"Drag to thin trees and plants out. Hold Ctrl as you press to clear the ground"
				+ " completely. Works on a Blender map's own scatter too."
			)
		)
	)
	pane.add_child(_build_advanced("Thin"))
	return pane


## Place: one foldout per palette biome (headed by its thumbnail), holding a tile per
## species big enough to place by hand. The selected biome's group starts open.
func _build_place_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.name = "PlacePane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "PlaceHeader"
	header.setup("Place", "Set a hero tree, rock or log.")
	pane.add_child(header)
	pane.add_child(
		_hint(
			"PlaceHint",
			(
				"Pick one, then click the map. Drag while pressed to turn it. Over a placed one,"
				+ " Shift+wheel resizes it and right-click or Delete removes it."
			)
		)
	)
	for biome in PaletteLibrary.biomes(palette_root):
		var biome_id := String(biome["id"])
		var groups := place_species(biome_id, palette_root)
		if groups.is_empty():
			continue
		var foldout := Foldout.new()
		foldout.name = "Place_" + biome_id.validate_node_name()
		foldout.title = String(biome["name"])
		foldout.icon = SwatchTextures.palette_thumbnail(biome["thumbnail"], 28, palette_root)
		var row := TileRow.new()
		row.name = "PlaceTiles"
		row.tile_min_size = PLACE_TILE_SIZE
		row.columns = PLACE_COLUMNS
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for rule in groups:
			var key := String(rule.get("key", ""))
			row.add_tile(
				StringName(biome_id + "|" + key),
				species_label(key),
				PLACE_ICONS.get(String(rule.get("kind", "")), PLACE_DEFAULT_ICON),
				"%s (%s)" % [species_label(key), String(biome["name"])]
			)
		row.selection_changed.connect(_on_place_tile.bind(row))
		foldout.add_child(row)
		pane.add_child(foldout)
		place_rows[biome_id] = row
		_place_foldouts[biome_id] = foldout
	return pane


## Sculpt: four tiles (Raise, Smooth, Flatten, Tier), Raise preselected; the gestures and
## modifiers in the hint line.
func _build_sculpt_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.name = "SculptPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "SculptHeader"
	header.setup("Sculpt", "Shape the ground.")
	pane.add_child(header)
	pane.add_child(
		_hint(
			"SculptHint",
			(
				"Pick a brush, then drag on the map; linger to build. Hold Ctrl as you press"
				+ " to lower or cut down, Shift to smooth. Tier steps up a level from where you"
				+ " press, or extends the level whose edge you start on."
			)
		)
	)
	sculpt_field = TileField.new()
	sculpt_field.name = "SculptField"
	sculpt_field.caption = "Brush"
	sculpt_field.tiles.tile_min_size = SCULPT_TILE_SIZE
	sculpt_field.tiles.columns = SCULPT_TILES.size()
	for tile in SCULPT_TILES:
		sculpt_field.tiles.add_tile(
			sculpt_tile_id(int(tile.op)),
			String(tile.label),
			String(tile.icon),
			String(tile.tooltip)
		)
	sculpt_field.tiles.select(sculpt_tile_id(HeightBrush.RAISE))
	sculpt_field.tiles.selection_changed.connect(
		func(id: StringName) -> void:
			var op := sculpt_tile_op(id)
			if op >= 0:
				sculpt_selected.emit(op)
	)
	pane.add_child(sculpt_field)
	pane.add_child(_build_advanced("Sculpt"))
	return pane


## Paint: the header, the gestures, and the surface groups (filled by ensure_paint_tiles()),
## ending in the Advanced foldout.
func _build_paint_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.name = "PaintPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_theme_constant_override("separation", 8)
	var header := MenuHeader.new()
	header.name = "PaintHeader"
	header.setup("Paint", "Lay paths, yards and rock.")
	pane.add_child(header)
	pane.add_child(
		_hint(
			"PaintHint",
			(
				"Pick a surface, then drag on the map; linger to cover it fully. Hold Ctrl as you"
				+ " press to erase paint back to the natural ground. Paths stop at rock faces:"
				+ " climb them with a ramp. Built surfaces clear the plants under them."
			)
		)
	)
	for group in PAINT_GROUPS:
		var field := TileField.new()
		field.name = "Paint" + String(group.caption) + "Field"
		field.caption = String(group.caption)
		field.tiles.photo_icons = true
		field.tiles.tile_min_size = PAINT_TILE_SIZE
		field.tiles.columns = PAINT_COLUMNS
		field.tiles.selection_changed.connect(_on_paint_tile.bind(field.tiles))
		pane.add_child(field)
		paint_fields[group.role] = field
	pane.add_child(_build_advanced("Paint"))
	return pane


## Water (P4-4): WaterToolPane, its signals relayed (the width row sets the brush radius).
func _build_water_pane() -> Control:
	water_pane = WaterToolPane.new()
	water_pane.shape_selected.connect(func(shape: int) -> void: water_shape_selected.emit(shape))
	water_pane.depth_selected.connect(func(depth: int) -> void: water_depth_selected.emit(depth))
	water_pane.speed_changed.connect(func(speed: float) -> void: water_speed_changed.emit(speed))
	water_pane.width_changed.connect(
		func(width: float) -> void: brush_size_changed.emit(width * 0.5)
	)
	return water_pane


## Shows the Water tool's exact width (metres, the full channel) and flow, without signals.
func set_water_values(width: float, speed: float) -> void:
	water_pane.set_values(width, speed)


## Enables the Water tool: fully where water can be carved; where it cannot (a dressed
## Blender map) only when the map already has water to erase, with the River and Pond tiles
## disabled and the tooltips and hint saying why; otherwise disabled with a tooltip.
func set_water_available(carves: bool, has_water: bool) -> void:
	set_rail_item_enabled(TOOL_WATER, carves or has_water)
	var tooltip := WATER_TOOLTIP
	if not carves:
		tooltip = WATER_UNAVAILABLE_TOOLTIP if not has_water else WATER_ERASE_ONLY_TOOLTIP
	set_rail_item_tooltip(TOOL_WATER, tooltip)
	water_pane.set_carves(carves)


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
		select_paint_surface(listed[0] if not listed.is_empty() else DEFAULT_PAINT_SURFACE)


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
## labels and the history labels of Paint strokes.
static func surface_label(surface: String) -> String:
	var named: String = SURFACE_LABELS.get(surface, "")
	if named != "":
		return named
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
	set_rail_item_enabled(TOOL_PAINT, available)
	set_rail_item_tooltip(TOOL_PAINT, PAINT_TOOLTIP if available else PAINT_UNAVAILABLE_TOOLTIP)


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
	set_rail_item_enabled(TOOL_SCULPT, available)
	set_rail_item_tooltip(TOOL_SCULPT, SCULPT_TOOLTIP if available else SCULPT_UNAVAILABLE_TOOLTIP)


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


## A wrapped caption line saying a pane's gestures.
func _hint(hint_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = hint_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## The Advanced foldout of a brush pane: exact size and strength, values hidden by default.
func _build_advanced(prefix: String) -> Foldout:
	var foldout := Foldout.new()
	foldout.name = prefix + "Advanced"
	foldout.title = "Advanced"
	var size_row := PropertyRow.new()
	size_row.name = prefix + "BrushSize"
	size_row.label = "Size"
	size_row.min_value = BrushTool.MIN_RADIUS
	size_row.max_value = BrushTool.MAX_RADIUS
	size_row.step = 0.1
	size_row.value = BrushTool.session_radius
	size_row.hint_low = "Small"
	size_row.hint_high = "Large"
	size_row.formatter = func(value: float) -> String: return "%.1f m" % value
	size_row.value_changed.connect(func(value: float) -> void: brush_size_changed.emit(value))
	foldout.add_child(size_row)
	var strength_row := PropertyRow.new()
	strength_row.name = prefix + "BrushStrength"
	strength_row.label = "Strength"
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
	_size_rows.append(size_row)
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


func _on_pane_requested(id: StringName) -> void:
	if id == TOOL_PAINT:
		ensure_paint_tiles()
	_stack.show_pane(id)
	tool_selected.emit(id)


## Shows a tool's pane (the controller follows a tool chosen by other means).
func show_tool_pane(id: StringName) -> void:
	if id == TOOL_PAINT:
		ensure_paint_tiles()
	_stack.show_pane(id)


func _on_footer_pressed(id: StringName) -> void:
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
	set_footer_badge(ACTION_SAVE, dirty)
	set_footer_item_tooltip(
		ACTION_SAVE, "Save map (unsaved changes)" if dirty else "Save map (all changes saved)"
	)


func set_history_state(can_undo: bool, can_redo: bool) -> void:
	set_footer_item_enabled(ACTION_UNDO, can_undo)
	set_footer_item_enabled(ACTION_REDO, can_redo)


## Selects a biome tile without emitting biome_selected, and opens that biome's Place group.
func select_biome(biome_id: String) -> void:
	biome_field.tiles.select(StringName(biome_id))
	for group_id in _place_foldouts:
		if group_id == biome_id:
			(_place_foldouts[group_id] as Foldout).expanded = true


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
		set_rail_item_active(_active_tool, false)
	_active_tool = tool_id
	if tool_id != &"":
		set_rail_item_active(tool_id, true)


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
