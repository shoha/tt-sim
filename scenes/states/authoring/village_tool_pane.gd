class_name VillageToolPane
extends VBoxContainer

## The Village tool's pane in AuthoringPanel (VillageTool): the gestures in a line, then the
## picked village's character as four picture tiles (each shows its road and its plaza ground
## split along a diagonal, VillageSwatch), a line naming those two surfaces, and the picked plaza's
## size (a slider the keys reach) with Remove. Several villages show a row of tiles to pick
## between; none shows what to do first. No state beyond what show_state was last given: the
## document is the truth (VillagePlazas.state_of). Built in code; every interactive Control is
## named.

## A village tile was picked (a Settlement id).
signal village_picked(village: int)
## A character tile was picked (a Settlement.KIND_NAMES entry): the picked village takes it.
signal kit_picked(kit: String)
## The size slider was let go (or keyed) at this radius in map metres.
signal radius_committed(radius: float)
signal remove_requested

const HINT := (
	"Click the ground to open a plaza, or drag to size it. Drag a plaza's edge to resize it and"
	+ " click inside to pick it; Delete removes it. The ground is repaved and the village furnishes"
	+ " it. Undo takes it all back."
)
const EMPTY := (
	"No village yet. Draw a street with the Wall tool and press Dress this street, then come back"
	+ " here to open a plaza on it."
)
const KIT_TIP := "%s: %s road, %s plaza"
const REMOVE_TIP := "Remove the picked plaza and its paving (Delete)"
const SIZE_TIP := "How wide the picked plaza is"
const THUMB_PX := 56
const KIT_TILE_SIZE := Vector2(104, 92)
const VILLAGE_TILE_SIZE := Vector2(104, 40)

var empty_note: Label
var village_field: TileField
var kit_field: TileField
var ground_note: Label
var plaza_box: VBoxContainer
var plaza_title: Label
var size_slider: HSlider
var size_value: Label
var remove_button: Button

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _village_ids: Array = []
var _syncing := false
var _dragging := false
var _unit_k := 1.0
var _unit_label := "m"


func _init(palette_root: String = PaletteLibrary.DEFAULT_ROOT) -> void:
	_palette_root = palette_root
	name = "VillagePane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "VillageHeader"
	var tool := ToolRegistry.find(VillageTool.ID)
	header.setup(tool.label, tool.summary)
	add_child(header)
	add_child(_caption("VillageHint", HINT))
	empty_note = _caption("VillageEmpty", EMPTY)
	add_child(empty_note)
	village_field = TileField.new()
	village_field.name = "VillageField"
	village_field.caption = "Village"
	village_field.visible = false
	add_child(village_field)
	_build_kit_field()
	ground_note = _caption("VillageGround", "")
	add_child(ground_note)
	_build_plaza_box()
	show_state(VillagePlazas.state_of(MapDocument.new(), -1, -1))


## Shows `state` (VillagePlazas.state_of) with the level's unit (`unit_k` display units per map
## metre, named `unit_label`). No signal fires.
func show_state(state: Dictionary, unit_k: float = 1.0, unit_label: String = "m") -> void:
	if is_inside_tree():
		ensure_tiles()
	_syncing = true
	_unit_k = unit_k
	_unit_label = unit_label
	var villages: Array = state["villages"]
	empty_note.visible = villages.is_empty()
	_show_villages(villages, int(state["village"]))
	var picked := int(state["village"]) >= 0
	for item in SettlementSection.CHIPS:
		kit_field.tiles.set_tile_disabled(_kit_id(String(item["kit"])), not picked)
	kit_field.visible = not villages.is_empty()
	if picked:
		kit_field.tiles.select(_kit_id(String(state["kit"])))
	else:
		kit_field.tiles.clear_selection()
	ground_note.visible = picked
	ground_note.text = "Road: %s. Plaza: %s." % [state["road"], state["plaza_ground"]]
	plaza_box.visible = picked
	plaza_title.text = "Plazas  %d of %d" % [int(state["plazas"]), Settlement.MAX_PLAZAS]
	var has_plaza := int(state["plaza"]) >= 0
	size_slider.editable = has_plaza
	remove_button.disabled = not has_plaza
	if has_plaza:
		size_slider.set_value_no_signal(float(state["radius"]))
	_show_size(size_slider.value if has_plaza else 0.0)
	_syncing = false


## Builds the four character tiles once, each with the picture of its kit's road and plaza
## ground (the palette is served by the time a pane is shown). Safe to call again.
func ensure_tiles() -> void:
	if kit_field.tiles.has_tile(_kit_id(String(SettlementSection.CHIPS[0]["kit"]))):
		return
	for item in SettlementSection.CHIPS:
		var kit := String(item["kit"])
		var ground := VillagePlazas.ground_of(kit)
		var tip := (
			KIT_TIP
			% [
				item["label"],
				VillagePlazas.surface_name(str(ground.get("road", ""))).to_lower(),
				VillagePlazas.surface_name(str(ground.get("plaza", ""))).to_lower(),
			]
		)
		kit_field.tiles.add_tile(
			_kit_id(kit),
			String(item["label"]),
			"",
			tip,
			VillageSwatch.kit_texture(kit, _palette_root, THUMB_PX)
		)


func _build_kit_field() -> void:
	kit_field = TileField.new()
	kit_field.name = "VillageKitField"
	kit_field.caption = "Character"
	kit_field.tiles.photo_icons = true
	kit_field.tiles.tile_min_size = KIT_TILE_SIZE
	kit_field.tiles.columns = 2
	kit_field.tiles.selection_changed.connect(_on_kit_tile)
	kit_field.visible = false
	add_child(kit_field)


func _build_plaza_box() -> void:
	plaza_box = VBoxContainer.new()
	plaza_box.name = "VillagePlazas"
	plaza_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaza_box.theme_type_variation = &"BoxContainerSnug"
	plaza_title = Label.new()
	plaza_title.name = "VillagePlazaTitle"
	plaza_title.theme_type_variation = &"SectionHeader"
	plaza_box.add_child(plaza_title)
	var row := HBoxContainer.new()
	row.name = "VillageSizeRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.tooltip_text = SIZE_TIP
	var caption := Label.new()
	caption.text = "Size"
	row.add_child(caption)
	size_slider = HSlider.new()
	size_slider.name = "VillageSize"
	size_slider.min_value = Settlement.PLAZA_MIN_RADIUS_M
	size_slider.max_value = Settlement.PLAZA_MAX_RADIUS_M
	size_slider.step = 0.5
	size_slider.custom_minimum_size = Vector2(110, 0)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_slider.tooltip_text = SIZE_TIP
	size_slider.drag_started.connect(func() -> void: _dragging = true)
	size_slider.drag_ended.connect(_on_drag_ended)
	size_slider.value_changed.connect(_on_size)
	row.add_child(size_slider)
	size_value = Label.new()
	size_value.name = "VillageSizeValue"
	size_value.custom_minimum_size = Vector2(76, 0)
	size_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(size_value)
	plaza_box.add_child(row)
	remove_button = Button.new()
	remove_button.name = "VillageRemove"
	remove_button.text = "Remove plaza"
	remove_button.tooltip_text = REMOVE_TIP
	remove_button.pressed.connect(remove_requested.emit)
	plaza_box.add_child(remove_button)
	add_child(plaza_box)


## Rebuilds the village tiles when the villages changed; the row is shown for two or more.
func _show_villages(villages: Array, picked: int) -> void:
	var ids: Array = villages.map(func(v: Dictionary) -> Variant: return [v["id"], v["kit"]])
	if ids != _village_ids:
		_village_ids = ids
		var old := village_field
		village_field = TileField.new()
		village_field.name = "VillageField"
		village_field.caption = "Village"
		village_field.tiles.tile_min_size = VILLAGE_TILE_SIZE
		village_field.tiles.columns = 2
		for v in villages:
			village_field.tiles.add_tile(
				_village_id(int(v["id"])),
				"%d  %s" % [int(v["id"]), v["label"]],
				"",
				"Open plazas for village %d" % int(v["id"])
			)
		village_field.tiles.selection_changed.connect(_on_village_tile)
		add_child(village_field)
		move_child(village_field, old.get_index())
		remove_child(old)
		old.queue_free()
	village_field.visible = villages.size() > 1
	if picked > 0:
		village_field.tiles.select(_village_id(picked))
	else:
		village_field.tiles.clear_selection()


func _show_size(radius: float) -> void:
	size_value.text = (
		"" if radius <= 0.0 else "%d %s" % [roundi(2.0 * radius * _unit_k), _unit_label]
	)


func _on_kit_tile(id: StringName) -> void:
	if _syncing:
		return
	for item in SettlementSection.CHIPS:
		if _kit_id(String(item["kit"])) == id:
			kit_picked.emit(String(item["kit"]))


func _on_village_tile(id: StringName) -> void:
	if _syncing:
		return
	var text := String(id).trim_prefix("village_")
	if text.is_valid_int():
		village_picked.emit(text.to_int())


func _on_size(value: float) -> void:
	_show_size(value)
	# A key press changes the value without a drag; a drag commits when it is let go.
	if _syncing or _dragging:
		return
	radius_committed.emit(value)


func _on_drag_ended(changed: bool) -> void:
	_dragging = false
	if changed and not _syncing:
		radius_committed.emit(size_slider.value)


static func _kit_id(kit: String) -> StringName:
	return StringName("village_kit_" + kit)


static func _village_id(village: int) -> StringName:
	return StringName("village_%d" % village)


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
