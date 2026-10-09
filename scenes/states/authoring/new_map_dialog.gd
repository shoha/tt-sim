class_name NewMapDialog
extends AnimatedCanvasLayerPanel

## The one question before a new map opens in authoring mode: how big, what place to start
## from, and what shape. Three tile fields (size, starting biome from the palette thumbnails
## plus Bare ground, landform from StartingLandform.KINDS) and nothing to type; the ground
## surface follows from the biome and the landform's caption is named under its tiles, so
## each choice explains itself. Create is the one primary action.
##
## Emits map_chosen({"size_ft", "biome_id", "landform", "seed"}) and closes; Cancel, the
## header's close button and Escape close without choosing. Root builds the map from the
## spec (NewMap).

signal map_chosen(spec: Dictionary)
signal closed

const BARE_TILE := &"bare_ground"
## Preselected starting biome: a temperate forest reads as a place at once and suits most
## tabletop scenes. Falls back to the first palette biome, then to bare ground.
const DEFAULT_BIOME := "temperate_forest_summer_s1"
const SIZE_TILE_SIZE := Vector2(96, 56)
const BIOME_TILE_SIZE := Vector2(96, 96)
const BIOME_THUMB_PX := 64
const BIOME_COLUMNS := 3
const LANDFORM_TILE_SIZE := Vector2(80, 56)
const LANDFORM_PREFIX := "landform_"
const SIZE_HINTS := {
	100: "20 x 20 squares: a skirmish",
	150: "30 x 30 squares: room to manoeuvre",
	200: "40 x 40 squares: a whole battlefield",
}

var palette_root: String = PaletteLibrary.DEFAULT_ROOT
var header: MenuHeader
var size_field: TileField
var biome_field: TileField
var ground_caption: Label
var landform_field: TileField
var landform_caption: Label
var create_button: Button
var cancel_button: Button

var _size_ft: int = NewMap.DEFAULT_SIZE_FT
var _biome_id: String = NewMap.BARE_BIOME
var _landform: String = StartingLandform.DEFAULT
## The landform a biome map goes back to after Bare ground switched the row to Flat, and
## whether the row still shows that automatic Flat (an author's own pick clears it).
var _biome_landform: String = StartingLandform.DEFAULT
var _auto_flat: bool = false
var _closing: bool = false

@onready var _body: VBoxContainer = %Body


func _on_panel_ready() -> void:
	header = MenuHeader.new()
	header.name = "Header"
	header.setup("New map", "Pick a size, a place and a shape to start from.", true)
	header.close_requested.connect(_on_cancel_pressed)
	_body.add_child(header)

	size_field = TileField.new()
	size_field.name = "SizeField"
	size_field.caption = "Size"
	size_field.tiles.tile_min_size = SIZE_TILE_SIZE
	size_field.tiles.columns = NewMap.SIZES_FT.size()
	for feet in NewMap.SIZES_FT:
		size_field.tiles.add_tile(
			StringName("size_%d" % feet), "%d ft" % feet, "grid-dots", SIZE_HINTS.get(feet, "")
		)
	size_field.tiles.select(StringName("size_%d" % _size_ft))
	size_field.tiles.selection_changed.connect(_on_size_selected)
	_body.add_child(size_field)

	biome_field = TileField.new()
	biome_field.name = "BiomeField"
	biome_field.caption = "Start from"
	biome_field.tiles.photo_icons = true
	biome_field.tiles.tile_min_size = BIOME_TILE_SIZE
	biome_field.tiles.columns = BIOME_COLUMNS
	var biomes := PaletteLibrary.biomes(palette_root)
	for biome in biomes:
		biome_field.tiles.add_tile(
			StringName(biome["id"]),
			AuthoringPanel.short_name(String(biome["name"])),
			"",
			String(biome["name"]),
			SwatchTextures.palette_thumbnail(biome["thumbnail"], BIOME_THUMB_PX, palette_root)
		)
	var bare: Dictionary = PaletteLibrary.surfaces(palette_root).get(NewMap.BARE_SURFACE, {})
	biome_field.tiles.add_tile(
		BARE_TILE,
		"Bare ground",
		"",
		"Plain ground to paint on",
		SwatchTextures.palette_thumbnail(bare.get("albedo", ""), BIOME_THUMB_PX, palette_root)
	)
	_biome_id = _initial_biome(biomes)
	biome_field.tiles.select(_tile_for_biome(_biome_id))
	biome_field.tiles.selection_changed.connect(_on_biome_selected)
	_body.add_child(biome_field)

	ground_caption = Label.new()
	ground_caption.name = "GroundCaption"
	ground_caption.theme_type_variation = &"Caption"
	ground_caption.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_body.add_child(ground_caption)
	_refresh_ground_caption()

	landform_field = TileField.new()
	landform_field.name = "LandformField"
	landform_field.caption = "Landform"
	landform_field.tiles.tile_min_size = LANDFORM_TILE_SIZE
	landform_field.tiles.columns = StartingLandform.KINDS.size()
	for kind in StartingLandform.KINDS:
		landform_field.tiles.add_tile(
			landform_tile(kind),
			String(StartingLandform.NAMES[kind]),
			"landform-" + kind,
			String(StartingLandform.CAPTIONS[kind])
		)
	_auto_flat = _biome_id == NewMap.BARE_BIOME
	_landform = StartingLandform.FLAT if _auto_flat else _biome_landform
	landform_field.tiles.select(landform_tile(_landform))
	landform_field.tiles.selection_changed.connect(_on_landform_selected)
	_body.add_child(landform_field)

	landform_caption = Label.new()
	landform_caption.name = "LandformCaption"
	landform_caption.theme_type_variation = &"Caption"
	landform_caption.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_body.add_child(landform_caption)
	_refresh_landform_caption()

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override("separation", 12)
	cancel_button = _footer_button("CancelButton", "Cancel", &"Secondary", footer)
	cancel_button.pressed.connect(_on_cancel_pressed)
	create_button = _footer_button("CreateButton", "Create map", &"", footer)
	create_button.pressed.connect(_on_create_pressed)
	_body.add_child(HSeparator.new())
	_body.add_child(footer)
	UIManager.register_overlay($ColorRect as Control)


func _stagger_targets() -> Array[Control]:
	return UiMotion.visible_children(_body)


func _on_after_animate_in() -> void:
	create_button.grab_focus()


func _on_after_animate_out() -> void:
	UIManager.unregister_overlay($ColorRect as Control)
	closed.emit()
	queue_free()


static func _footer_button(
	node_name: String, label: String, variation: StringName, parent: Control
) -> Button:
	var button := AnimatedButton.new()
	button.name = node_name
	button.text = label
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(120, 0)
	button.set_meta("ui_silent", true)
	parent.add_child(button)
	return button


func _initial_biome(biomes: Array[Dictionary]) -> String:
	for biome in biomes:
		if biome["id"] == DEFAULT_BIOME:
			return DEFAULT_BIOME
	return String(biomes[0]["id"]) if not biomes.is_empty() else NewMap.BARE_BIOME


static func _tile_for_biome(biome_id: String) -> StringName:
	return BARE_TILE if biome_id == NewMap.BARE_BIOME else StringName(biome_id)


static func landform_tile(kind: String) -> StringName:
	return StringName(LANDFORM_PREFIX + kind)


## What the author has chosen so far: {"size_ft", "biome_id", "landform", "seed"} (a fresh
## seed each call).
func current_spec() -> Dictionary:
	return {
		"size_ft": _size_ft,
		"biome_id": _biome_id,
		"landform": _landform,
		"seed": NewMap.random_seed(),
	}


func _on_size_selected(id: StringName) -> void:
	_size_ft = int(String(id).trim_prefix("size_"))


## Bare ground starts Flat (plain ground to shape by hand); picking a biome again brings
## back the landform the row showed before, unless the author has picked one since.
func _on_biome_selected(id: StringName) -> void:
	var was_bare := _biome_id == NewMap.BARE_BIOME
	_biome_id = NewMap.BARE_BIOME if id == BARE_TILE else String(id)
	_refresh_ground_caption()
	if _biome_id == NewMap.BARE_BIOME and not was_bare:
		_biome_landform = _landform
		_auto_flat = true
		_set_landform(StartingLandform.FLAT)
	elif _biome_id != NewMap.BARE_BIOME and was_bare and _auto_flat:
		_auto_flat = false
		_set_landform(_biome_landform)


func _on_landform_selected(id: StringName) -> void:
	_auto_flat = false
	_landform = String(id).trim_prefix(LANDFORM_PREFIX)
	_refresh_landform_caption()


func _set_landform(kind: String) -> void:
	_landform = kind
	landform_field.tiles.select(landform_tile(kind))
	_refresh_landform_caption()


func _refresh_landform_caption() -> void:
	landform_caption.text = String(StartingLandform.CAPTIONS.get(_landform, ""))


## "Ground: forest floor" -- the surface the map will start on, derived from the biome.
func _refresh_ground_caption() -> void:
	var surface := NewMap.BARE_SURFACE
	if _biome_id != NewMap.BARE_BIOME:
		var biome_surface: String = PaletteLibrary.biome(_biome_id, palette_root).get(
			"ground_surface", ""
		)
		if biome_surface != "":
			surface = biome_surface
	ground_caption.text = "Ground: %s" % surface.replace("_", " ")


func _on_create_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"confirm")
	map_chosen.emit(current_spec())
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
