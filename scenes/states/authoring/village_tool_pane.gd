class_name VillageToolPane
extends VBoxContainer

## The Village tool's pane in AuthoringPanel (VillageTool). One primary choice and what follows
## from it: when the map has two or more villages, a row naming them by number (the same "Village
## 2" the board's chips and the ghost's hint use) picks the one the pane is about; below it what a
## press lays (Fields, below) and that village's character, five tiles on one line, each a small
## painted vignette of its plaza over its name
## (VillageSwatch: the kit's paving on its own ground colour with a well, a stall, barrels or a
## lamp); then the village's plazas: how many more it can hold, and for the picked plaza (or the
## one a drag is sizing, read live) its size on a slider the keys reach, with Remove beside it.
## With no village it says what to do first. One line says the gesture; the ghost on the board
## teaches the rest. No state beyond what show_state was last given: the document is the truth
## (VillagePlazas.state_of). Built in code; every interactive Control is named.
##
## Fields (topic fields): one "Lay out" row of four picture tiles says what a press on bare ground
## lays: Plaza (the village's own plaza vignette, VillageSwatch.kit_texture) or a field of one
## kind, Crops, Orchard or Garden (VillageSwatch.field_texture). It is the most used row, so it
## stands above the character, in the pane's largest tiles, and the character row is compact. A
## kind the village's character does not keep is greyed (the theme's solid disabled role), its
## tooltip says why, and a line of its own under the tiles says it in words (the harbour town keeps
## no fields at all). The hint line under the header says the gesture for what is picked. The size
## row and Remove serve a picked field as they serve a plaza (VillageFields.with_fields).
##
## Boundary (topic bounds): one row of five text tiles under the character tiles, Auto (the
## character's own pick, the default; the caption line says what it gives: "Auto: hedge"), None,
## Hedge, Low wall or Wall. It is the picked village's own (Settlement.boundary_manual); Auto
## gives back what the kit draws.

## A village tile was picked (a Settlement id).
signal village_picked(village: int)
## The Lay row or a kind tile was picked: a press lays a field of `kind` ("" the village's
## default) when `field`, else a plaza.
signal lay_picked(field: bool, kind: String)
## A character tile was picked (a Settlement.KIND_NAMES entry): the picked village takes it.
signal kit_picked(kit: String)
## A Boundary choice was picked: AUTO_CHOICE, NONE_CHOICE or a VillageBoundary.KINDS entry.
signal boundary_picked(choice: String)
## The size slider was let go (or keyed) at this radius in map metres.
signal radius_committed(radius: float)
## Remove: the picked plaza or field, or (a piece picked, VillageFurnishBox) the picked piece.
signal remove_requested
## The furnishing buttons: Swap and Put back act on the picked piece, Restore on the village.
signal swap_requested
signal unpin_requested
signal restore_requested
## The pointer is over (true) or left (false) the Put back button.
signal restore_hover_changed(over: bool)

const HINT := "Click or drag beside a street to open a plaza."
const FIELD_HINT := "Click or drag the ground at the village's edge to lay %s."
## What the field hint calls each kind.
## No-break spaces hold the noun to "lay" on the hint's last line (no widowed "field.").
const FIELD_NOUNS := {
	"crops": "a crop field", "orchard": "an orchard", "garden": "a garden"
}
const NO_KIND_NOTE := "%s keeps no %s"
const EMPTY := (
	"No village yet. Draw a street with the Wall tool and press Dress this street, then come back"
	+ " here to open a plaza on it."
)
const PICK_NOTE := (
	"Drag a plaza to move it, its edge to size it. Click a barrel or stall to move or swap it."
)
const ROOM := "Room for %d more plazas"
const ROOM_ONE := "Room for 1 more plaza"
const ROOM_NONE := "Four plazas: the village is full"
const FIELD_ROOM := "Room for %d more fields"
const FIELD_ROOM_ONE := "Room for 1 more field"
const FIELD_ROOM_NONE := "Four fields: the village is full"
const FIELD_PICK_NOTE := "Click a field on the board to size or remove it."
const LAY_PLAZA_TIP := "A click on the ground beside the street opens a plaza"
const NO_FIELDS_TIP := "%s keeps no fields"
const REMOVE_FIELD_TIP := "Remove the picked field and its paint (Delete)"
## The Lay out tiles are the pane's largest (round 4: the most used row was the smallest); the
## character row below them is compact, a small picture above each name.
const KIND_TILE_SIZE := Vector2(76, 92)
const KIND_THUMB_PX := 54
const KIT_TIP := "%s: %s streets round a %s plaza"
const REMOVE_TIP := "Remove the picked plaza and its paving (Delete)"
const SIZE_TIP := "How wide the picked plaza is"
## The character tile's picture, at the Tile variation's own icon size, so five tiles fit one line
## at 720 with their names under them.
const THUMB_PX := 24
## The Boundary row: Auto (the character's own pick, the default), None, then the kinds from the
## lightest to the strongest. Each is [choice, label, tooltip]; the Auto tooltip is completed with
## what the village's character would draw (AUTO_TIP).
const AUTO_CHOICE := "auto"
const NONE_CHOICE := "none"
const AUTO_NOTE := "Auto: %s"
const AUTO_TIP := "Auto: the village's character and seed choose, as a Dress does (here: %s)"
const BOUNDARY_CHOICES: Array[Array] = [
	[AUTO_CHOICE, "Auto", ""],
	[NONE_CHOICE, "None", "No line round the village"],
	[VillageBoundary.HEDGE, "Hedge", "A hedge round the village, gaps where streets leave"],
	[VillageBoundary.LOW_WALL, "Low wall", "A low wall round the village, gates where streets leave"],
	[VillageBoundary.WALL, "Wall", "A tall wall round the village, gates where streets leave"],
]
const BOUNDARY_TILE_SIZE := Vector2(60, 40)
## A character tile: the width is the row's share (five to a line); the height is what a Button
## needs for the picture over a name on two lines (it counts one font height more than the text).
const KIT_TILE_SIZE := Vector2(60, 86)
const VILLAGE_TILE_SIZE := Vector2(96, 40)

var empty_note: Label
var village_field: TileField
var kit_field: TileField
## The Lay out row: Plaza and the three field kinds.
var lay_field: TileField
## What the village's character does not keep, on its own line under the Lay out tiles.
var lay_note: Label
## The Boundary row: a caption (with a note saying what Auto gives) over five tiles.
var boundary_field: TileField
var hint: Label
var plaza_box: VBoxContainer
var plaza_title: Label
var pick_note: Label
var size_row: HBoxContainer
var size_slider: HSlider
var size_value: Label
var remove_button: Button
## The picked piece's name and buttons, and the village's Put back (topic villages4).
var furnish_box: VillageFurnishBox

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _village_ids: Array = []
var _syncing := false
var _dragging := false
var _unit_k := 1.0
var _unit_label := "m"
## The kit whose plaza the Plaza tile pictures, and the pictures made so far (kit: texture).
var _plaza_kit := ""
var _plaza_pictures: Dictionary = {}


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
	hint = _caption("VillageHint", HINT)
	add_child(hint)
	empty_note = _caption("VillageEmpty", EMPTY)
	add_child(empty_note)
	village_field = TileField.new()
	village_field.name = "VillageField"
	village_field.caption = "Village"
	village_field.visible = false
	add_child(village_field)
	# Lay out first: it is the row an author comes back to; the character is picked once.
	_build_lay_fields()
	_build_kit_field()
	_build_boundary_row()
	_build_plaza_box()
	show_state(VillagePlazas.state_of(MapDocument.new(), -1, -1))


## Shows `state` (VillagePlazas.state_of, or with_preview while a drag sizes a plaza) with the
## level's unit (`unit_k` display units per map metre, named `unit_label`). No signal fires.
func show_state(state: Dictionary, unit_k: float = 1.0, unit_label: String = "m") -> void:
	if is_inside_tree():
		ensure_tiles()
	_syncing = true
	_unit_k = unit_k
	_unit_label = unit_label
	var villages: Array = state["villages"]
	var village := int(state["village"])
	empty_note.visible = villages.is_empty()
	_show_villages(villages, village)
	var picked := village >= 0
	for item in SettlementSection.CHIPS:
		kit_field.tiles.set_tile_disabled(_kit_id(String(item["kit"])), not picked)
	kit_field.visible = not villages.is_empty()
	kit_field.caption = (
		"Character of %s" % VillagePlazas.village_name(village).to_lower()
		if picked and villages.size() > 1
		else "Character"
	)
	if picked:
		kit_field.tiles.select(_kit_id(String(state["kit"])))
	else:
		kit_field.tiles.clear_selection()
	boundary_field.visible = picked
	if picked:
		_show_boundary(state, villages.size() > 1)
	plaza_box.visible = picked
	var laying := bool(state.get("lay_field", false))
	_show_lay(state, picked, laying)
	var sizing := bool(state.get("sizing", false))
	var has_plaza := int(state["plaza"]) >= 0
	# The count, the note and the size follow the picked disc, else what a press lays.
	var on_fields: bool = (
		state.get("group", VillageFields.GROUP_PLAZAS) == VillageFields.GROUP_FIELDS
		if has_plaza or sizing
		else laying
	)
	var count := int(state.get("fields", 0)) if on_fields else int(state["plazas"])
	plaza_title.text = field_room_text(count) if on_fields else room_text(count)
	pick_note.text = FIELD_PICK_NOTE if on_fields else PICK_NOTE
	size_row.visible = has_plaza or sizing
	remove_button.visible = has_plaza and not sizing
	remove_button.tooltip_text = REMOVE_FIELD_TIP if on_fields else REMOVE_TIP
	pick_note.visible = not size_row.visible and count > 0
	size_slider.editable = has_plaza and not sizing
	remove_button.disabled = not has_plaza
	var kind := str(state.get("picked_kind", ""))
	if on_fields and kind == "":
		kind = str(state.get("field_kind", ""))
	var floor_m := VillagePlazas.min_radius(String(state["kit"]))
	size_slider.max_value = Settlement.PLAZA_MAX_RADIUS_M
	if on_fields:
		floor_m = VillageFields.clamp_radius(0.0, kind)
		size_slider.max_value = VillageFields.clamp_radius(INF, kind)
	# A disc made under its floor elsewhere still shows its own size.
	size_slider.min_value = minf(
		floor_m, float(state["radius"]) if has_plaza else Settlement.PLAZA_MAX_RADIUS_M
	)
	if has_plaza or sizing:
		size_slider.set_value_no_signal(float(state["radius"]))
	_show_size(float(state["radius"]) if (has_plaza or sizing) else 0.0)
	# A picked piece stands in the place of the size row (it is the only thing picked).
	var prop: Dictionary = state.get("prop", {})
	furnish_box.show_state(prop)
	if bool(prop.get("picked", false)):
		size_row.visible = false
		pick_note.visible = false
	_syncing = false


## The plaza count line for a village holding `plazas`: how many more it can take.
static func room_text(plazas: int) -> String:
	var more := Settlement.MAX_PLAZAS - plazas
	if more <= 0:
		return ROOM_NONE
	return ROOM_ONE if more == 1 else ROOM % more


## The field count line for a village holding `fields`.
static func field_room_text(fields: int) -> String:
	var more := Settlement.MAX_FIELDS - fields
	if more <= 0:
		return FIELD_ROOM_NONE
	return FIELD_ROOM_ONE if more == 1 else FIELD_ROOM % more


## The Lay row: the Plaza tile pictures the village's own plaza, the kinds its character lacks
## are greyed and named on the caption line, and the tile lit is what a press lays (the kit's
## default kind until the author picks one). The hint says that gesture.
func _show_lay(state: Dictionary, picked: bool, laying: bool) -> void:
	var kit := String(state["kit"])
	var kinds: Array = state.get("kinds", [])
	lay_field.visible = picked
	if picked and is_inside_tree():
		_show_plaza_picture(kit)
	var kit_label := VillagePlazas.kit_label(kit)
	for kind in Settlement.FIELD_KINDS:
		var kept := kinds.has(kind)
		lay_field.tiles.set_tile_disabled(_kind_id(kind), not picked or not kept)
		lay_field.tiles.set_tile_tooltip(
			_kind_id(kind),
			(
				str(VillageFields.KIND_TIPS[kind])
				if kept
				else NO_KIND_NOTE % [kit_label, str(VillageFields.KIND_LABELS[kind]).to_lower()]
			)
		)
	lay_note.text = missing_note(kit, kinds) if picked else ""
	lay_note.visible = lay_note.text != ""
	var current := str(state.get("field_kind", ""))
	var on_field := laying and current != "" and kinds.has(current)
	lay_field.tiles.select(_kind_id(current) if on_field else &"village_lay_plaza")
	hint.text = FIELD_HINT % FIELD_NOUNS.get(current, "a field") if on_field else HINT


## The caption-line note for a village of `kit` keeping `kinds`: what its character does not
## keep, or "" when it keeps every kind.
static func missing_note(kit: String, kinds: Array) -> String:
	var label := VillagePlazas.kit_label(kit)
	if kinds.is_empty():
		return NO_FIELDS_TIP % label
	var missing: Array[String] = []
	for kind in Settlement.FIELD_KINDS:
		if not kinds.has(kind):
			missing.append(str(VillageFields.KIND_LABELS[kind]).to_lower())
	return "" if missing.is_empty() else NO_KIND_NOTE % [label, " or ".join(missing)]


## Puts the vignette of `kit`'s plaza on the Plaza tile (made once per kit).
func _show_plaza_picture(kit: String) -> void:
	if kit == _plaza_kit:
		return
	_plaza_kit = kit
	if not _plaza_pictures.has(kit):
		_plaza_pictures[kit] = VillageSwatch.kit_texture(kit, _palette_root, KIND_THUMB_PX)
	var tile := lay_field.tiles.get_node_or_null(^"village_lay_plaza") as Button
	if tile != null:
		tile.icon = _plaza_pictures[kit]


## Builds the five character tiles once, each with the vignette of its kit's plaza (the
## palette is served by the time a pane is shown). Safe to call again.
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
		var tile := kit_field.tiles.add_tile(
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
	# Every character on one line, the name breaking between its words under the picture.
	kit_field.tiles.wrap_labels = true
	kit_field.tiles.columns = SettlementSection.CHIPS.size()
	kit_field.tiles.selection_changed.connect(_on_kit_tile)
	kit_field.visible = false
	add_child(kit_field)


## The Lay row, Plaza then the field kinds, all picture tiles. The Plaza tile's picture is a
## blank until the pane first shows a village (the palette its paving reads is served by then).
func _build_lay_fields() -> void:
	lay_field = TileField.new()
	lay_field.name = "VillageLayField"
	lay_field.caption = "Lay out"
	lay_field.tiles.photo_icons = true
	lay_field.tiles.tile_min_size = KIND_TILE_SIZE
	lay_field.tiles.columns = 1 + Settlement.FIELD_KINDS.size()
	var blank := Image.create(KIND_THUMB_PX, KIND_THUMB_PX, false, Image.FORMAT_RGBA8)
	lay_field.tiles.add_tile(
		&"village_lay_plaza", "Plaza", "", LAY_PLAZA_TIP, ImageTexture.create_from_image(blank)
	)
	for kind in Settlement.FIELD_KINDS:
		lay_field.tiles.add_tile(
			_kind_id(kind),
			str(VillageFields.KIND_LABELS[kind]),
			"",
			str(VillageFields.KIND_TIPS[kind]),
			VillageSwatch.field_texture(kind, KIND_THUMB_PX)
		)
	lay_field.tiles.selection_changed.connect(_on_lay_tile)
	lay_field.visible = false
	add_child(lay_field)
	lay_note = _caption("VillageLayNote", "")
	lay_note.visible = false
	add_child(lay_note)


## The Boundary row under the character tiles: a caption over five text tiles, in the pane's own
## tile primitive. The caption line's note says what Auto would give. Shown for a picked village.
func _build_boundary_row() -> void:
	boundary_field = TileField.new()
	boundary_field.name = "VillageBoundaryField"
	boundary_field.caption = "Boundary"
	boundary_field.tiles.tile_min_size = BOUNDARY_TILE_SIZE
	boundary_field.tiles.columns = BOUNDARY_CHOICES.size()
	for choice in BOUNDARY_CHOICES:
		boundary_field.tiles.add_tile(
			_boundary_id(str(choice[0])), str(choice[1]), "", str(choice[2])
		)
	boundary_field.tiles.selection_changed.connect(_on_boundary_tile)
	boundary_field.show_note("")
	boundary_field.visible = false
	add_child(boundary_field)


## Selects the tile the picked village is on, names what Auto would give it on the caption line
## and in the Auto tile's tooltip.
func _show_boundary(state: Dictionary, several: bool) -> void:
	var auto_name := boundary_name(str(state.get("boundary_auto", "")))
	boundary_field.caption = (
		"Boundary of %s" % VillagePlazas.village_name(int(state["village"])).to_lower()
		if several
		else "Boundary"
	)
	boundary_field.note.text = AUTO_NOTE % auto_name
	boundary_field.tiles.set_tile_tooltip(_boundary_id(AUTO_CHOICE), AUTO_TIP % auto_name)
	var choice := AUTO_CHOICE
	if bool(state.get("boundary_manual", false)):
		choice = str(state.get("boundary", ""))
		if choice == "":
			choice = NONE_CHOICE
	boundary_field.tiles.select(_boundary_id(choice))


## The lower-case words for boundary `kind` ("" is "none"), as the Auto note names it.
static func boundary_name(kind: String) -> String:
	if kind == "":
		return "none"
	for choice in BOUNDARY_CHOICES:
		if choice[0] == kind:
			return str(choice[1]).to_lower()
	return "none"


static func _boundary_id(choice: String) -> StringName:
	return StringName("village_boundary_" + choice)


func _on_boundary_tile(id: StringName) -> void:
	if _syncing:
		return
	boundary_picked.emit(String(id).trim_prefix("village_boundary_"))


## A Lay tile was picked: Plaza lays plazas, a kind tile fields of that kind.
func _on_lay_tile(id: StringName) -> void:
	if _syncing:
		return
	if id == &"village_lay_plaza":
		lay_picked.emit(false, "")
	else:
		lay_picked.emit(true, String(id).trim_prefix("village_kind_"))


static func _kind_id(kind: String) -> StringName:
	return StringName("village_kind_" + kind)


func _build_plaza_box() -> void:
	plaza_box = VBoxContainer.new()
	plaza_box.name = "VillagePlazas"
	plaza_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaza_box.theme_type_variation = &"BoxContainerSnug"
	plaza_title = Label.new()
	plaza_title.name = "VillagePlazaTitle"
	plaza_title.theme_type_variation = &"Caption"
	plaza_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plaza_title.custom_minimum_size = Vector2(1, 0)
	plaza_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaza_box.add_child(plaza_title)
	pick_note = _caption("VillagePickNote", PICK_NOTE)
	plaza_box.add_child(pick_note)
	size_row = HBoxContainer.new()
	size_row.name = "VillageSizeRow"
	size_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_row.tooltip_text = SIZE_TIP
	var caption := Label.new()
	caption.text = "Size"
	size_row.add_child(caption)
	size_slider = HSlider.new()
	size_slider.name = "VillageSize"
	size_slider.min_value = VillagePlazas.MIN_RADIUS_M
	size_slider.max_value = Settlement.PLAZA_MAX_RADIUS_M
	size_slider.step = 0.5
	size_slider.custom_minimum_size = Vector2(90, 0)
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_slider.tooltip_text = SIZE_TIP
	size_slider.drag_started.connect(func() -> void: _dragging = true)
	size_slider.drag_ended.connect(_on_drag_ended)
	size_slider.value_changed.connect(_on_size)
	size_row.add_child(size_slider)
	size_value = Label.new()
	size_value.name = "VillageSizeValue"
	size_value.custom_minimum_size = Vector2(52, 0)
	size_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_row.add_child(size_value)
	remove_button = Button.new()
	remove_button.name = "VillageRemove"
	remove_button.text = "Remove"
	remove_button.tooltip_text = REMOVE_TIP
	remove_button.pressed.connect(remove_requested.emit)
	size_row.add_child(remove_button)
	plaza_box.add_child(size_row)
	furnish_box = VillageFurnishBox.new()
	furnish_box.swap_requested.connect(swap_requested.emit)
	furnish_box.unpin_requested.connect(unpin_requested.emit)
	furnish_box.remove_requested.connect(remove_requested.emit)
	furnish_box.restore_requested.connect(restore_requested.emit)
	furnish_box.restore_hover_changed.connect(restore_hover_changed.emit)
	plaza_box.add_child(furnish_box)
	add_child(plaza_box)


## Rebuilds the village tiles when the villages changed; the row is shown for two or more.
func _show_villages(villages: Array, picked: int) -> void:
	var ids: Array = villages.map(func(v: Dictionary) -> Variant: return v["id"])
	if ids != _village_ids:
		_village_ids = ids
		var old := village_field
		village_field = TileField.new()
		village_field.name = "VillageField"
		village_field.caption = "Village"
		village_field.tiles.tile_min_size = VILLAGE_TILE_SIZE
		village_field.tiles.columns = 3
		for v in villages:
			var id := int(v["id"])
			village_field.tiles.add_tile(
				_village_id(id),
				VillagePlazas.village_name(id),
				"",
				"Work on village %d (its number chip on the board)" % id
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
