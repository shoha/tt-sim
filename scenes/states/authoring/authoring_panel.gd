class_name AuthoringPanel
extends DrawerContainer

## Authoring mode's tool drawer on the left edge, in rail mode: one rail item per tool
## (Biome, Thin / Clear, Place) above a footer of session actions (Undo, Redo, Save,
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
## Tools. The brush tools arrive with phase 2 T6: the Biome pane already lists the palette
## biomes (a picked tile is `biome_selected`, the brush's input) and Thin / Clear and Place
## are present but disabled.

signal save_pressed
signal leave_pressed
signal undo_pressed
signal redo_pressed
signal name_changed(new_name: String)
signal biome_selected(biome_id: String)
signal tool_selected(tool_id: StringName)

const DRAWER_WIDTH := 320.0
const BIOME_TILE_SIZE := Vector2(64, 84)
const BIOME_THUMB_PX := 52
const BIOME_COLUMNS := 2

const TOOL_BIOME := &"biome"
const TOOL_THIN := &"thin_clear"
const TOOL_PLACE := &"place"
const ACTION_UNDO := &"undo"
const ACTION_REDO := &"redo"
const ACTION_SAVE := &"save_map"
const ACTION_LEAVE := &"leave_authoring"

const RAIL_ITEMS: Array[Dictionary] = [
	{"id": TOOL_BIOME, "icon": "trees", "tooltip": "Biome"},
	{"id": TOOL_THIN, "icon": "eraser", "tooltip": "Thin / Clear (coming soon)"},
	{"id": TOOL_PLACE, "icon": "tree", "tooltip": "Place (coming soon)"},
]
const RAIL_FOOTER_ITEMS: Array[Dictionary] = [
	{"id": ACTION_UNDO, "icon": "arrow-back-up", "tooltip": "Undo (Ctrl+Z)"},
	{"id": ACTION_REDO, "icon": "arrow-forward-up", "tooltip": "Redo (Ctrl+Y)"},
	{"id": ACTION_SAVE, "icon": "device-floppy", "tooltip": "Save map"},
	{"id": ACTION_LEAVE, "icon": "door-exit", "tooltip": "Leave map building"},
]
## Tools whose panes exist but whose brushes are not built yet.
const TOOLS_NOT_READY: Array[StringName] = [TOOL_THIN, TOOL_PLACE]

## Palette root the biome tiles come from; tests point it elsewhere.
var palette_root: String = PaletteLibrary.DEFAULT_ROOT

var name_edit: LineEdit
var biome_field: TileField

var _stack: PaneStack
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
	_stack.add_pane(TOOL_THIN, _build_placeholder_pane("ThinPane", "Thin / Clear"))
	_stack.add_pane(TOOL_PLACE, _build_placeholder_pane("PlacePane", "Place"))
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
	header.setup("Biome", "Pick a biome to paint with.")
	pane.add_child(header)
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
	return pane


func _build_placeholder_pane(pane_name: String, title: String) -> Control:
	var pane := VBoxContainer.new()
	pane.name = pane_name
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header := MenuHeader.new()
	header.setup(title, "Coming with the brush tools.")
	pane.add_child(header)
	return pane


## A tile label short enough for a two-column tile: at most the last two words of the
## palette's name ("Temperate Deciduous Forest" shows "Deciduous Forest"; the tooltip has
## the whole name). Two-word names are what the palette mostly uses and stay whole.
static func short_name(full_name: String) -> String:
	var words := full_name.split(" ", false)
	if words.size() <= 2:
		return full_name
	return " ".join(words.slice(words.size() - 2))


func _on_pane_requested(id: StringName) -> void:
	_stack.show_pane(id)
	tool_selected.emit(id)


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


## Selects a biome tile without emitting biome_selected.
func select_biome(biome_id: String) -> void:
	biome_field.tiles.select(StringName(biome_id))


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
