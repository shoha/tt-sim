class_name SkyPane
extends LevelEditPane

## Sky preset, background, ambient and fog, with fog colour and fog shape
## under Advanced. Environment fields live on the shared EnvironmentEditModel;
## this pane is the one that writes preset + overrides into the state on
## Save. Sky tiles show a thumbnail; a preview strip and caption under them
## show the hovered or selected sky before it is applied.

signal revert_to_map_defaults_requested

const AMBIENT_KEYS := ["ambient_light_color", "ambient_light_energy"]
const FOG_KEYS := ["fog_enabled", "fog_light_color", "fog_density"]
const SKY_KEYS := ["sky_preset", "background_mode", "ambient_light_source"]
## [sky preset key, label, icon for non-painted tiles]. Sky presets get their
## thumbnail from SwatchTextures instead of an icon.
const SKY_TILES := [
	["", "None", "circle-off"],
	["map_default", "Map", "map"],
	["clear_day", "Clear", ""],
	["cloudy", "Cloudy", ""],
	["overcast", "Overcast", ""],
	["morning", "Morning", ""],
	["sunset", "Sunset", ""],
	["dusk", "Dusk", ""],
	["storm", "Storm", ""],
	["night_sky", "Night", ""],
]
const PREVIEW_HEIGHT := 70
const CAPTION_NONE := "No sky: background colour only"
const CAPTION_MAP := "The map's own sky"

var _model: EnvironmentEditModel
var _has_map_defaults: bool = false
var _preset_row: PropertyRow
var _preset_dropdown: OptionButton
var _revert_button: IconButton
var _clear_button: IconButton
var _preset_caption: Label
var _sky_field: TileField
var _bg_row: PropertyRow
var _ambient_row: PropertyRow
var _fog_row: PropertyRow
var _sky_tiles: TileRow
var _sky_preview: TextureRect
var _sky_caption: Label
var _hover_key: StringName = &""
var _is_hovering: bool = false
var _fog_color_row: PropertyRow
var _fog_energy_row: PropertyRow
var _fog_height_row: PropertyRow
var _fog_height_density_row: PropertyRow


func set_model(model: EnvironmentEditModel) -> void:
	_model = model
	_model.changed.connect(_on_model_changed)
	_model.reloaded.connect(_sync_from_model)


func _build() -> void:
	_build_header()

	_sky_field = _add_tile_field("Sky", [])
	# Ten tiles as two even rows of five.
	_sky_field.tiles.tile_min_size = Vector2(52, 52)
	_sky_field.tiles.columns = 5
	for spec in SKY_TILES:
		var key: String = spec[0]
		var painted: Texture2D = null
		if EnvironmentPresets.SKY_PRESETS.has(key):
			painted = SwatchTextures.sky_gradient(key)
		_sky_field.tiles.add_tile(
			StringName(key),
			spec[1],
			spec[2],
			EnvironmentPresets.get_sky_preset_description(key),
			painted
		)
	_sky_tiles = _sky_field.tiles
	_sky_tiles.set_tile_visible(&"map_default", false)
	_sky_tiles.selection_changed.connect(_on_sky_selected)
	_sky_field.reset_requested.connect(_on_reset_requested.bind(SKY_KEYS))
	_sky_tiles.tile_hovered.connect(_on_sky_tile_hovered)
	_sky_tiles.tile_unhovered.connect(_on_sky_tile_unhovered)

	_sky_preview = TextureRect.new()
	_sky_preview.name = "SkyPreview"
	_sky_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_sky_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sky_preview.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	_sky_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_preview.resized.connect(_on_preview_resized)
	add_child(_sky_preview)
	_sky_caption = _add_caption("")

	_preset_row = _add_row("Look", 0.0, 1.0, 1.0, 0.0, {"show_slider": false})
	_preset_dropdown = OptionButton.new()
	_preset_dropdown.item_selected.connect(_on_preset_selected)
	_preset_row.set_control(_preset_dropdown)
	_preset_caption = _add_caption("")
	_populate_presets(false)

	_fog_row = _add_row(
		"Fog",
		0.0001,
		0.1,
		0.0001,
		0.01,
		{
			"show_check": true,
			"exp_edit": true,
			"allow_greater": true,
			"hint_low": "Thin",
			"hint_high": "Thick",
		}
	)
	_fog_row.toggled.connect(_on_override_toggle.bind("fog_enabled"))
	_fog_row.value_changed.connect(_on_override_value.bind("fog_density"))
	_fog_row.reset_requested.connect(_on_reset_requested.bind(FOG_KEYS))

	var foldout := _add_foldout()
	var body := foldout.body
	_bg_row = _add_row(
		"Background", 0.0, 1.0, 1.0, 0.0, {"show_slider": false, "show_color": true, "parent": body}
	)
	_bg_row.color_changed.connect(_on_override_color.bind("background_color"))
	_bg_row.reset_requested.connect(_on_reset_requested.bind(["background_color"]))

	_ambient_row = _add_row(
		"Ambient",
		0.0,
		2.0,
		0.01,
		0.5,
		{
			"show_color": true,
			"allow_greater": true,
			"parent": body,
			"hint_low": "Dark",
			"hint_high": "Bright",
		}
	)
	_ambient_row.color_changed.connect(_on_override_color.bind("ambient_light_color"))
	_ambient_row.value_changed.connect(_on_override_value.bind("ambient_light_energy"))
	_ambient_row.reset_requested.connect(_on_reset_requested.bind(AMBIENT_KEYS))

	_fog_color_row = _add_row(
		"Fog colour", 0.0, 1.0, 1.0, 0.0, {"show_slider": false, "show_color": true, "parent": body}
	)
	_fog_color_row.color_changed.connect(_on_override_color.bind("fog_light_color"))
	_fog_color_row.reset_requested.connect(_on_reset_requested.bind(["fog_light_color"]))

	_fog_energy_row = _add_row(
		"Fog energy",
		0.0,
		2.0,
		0.01,
		1.0,
		{"allow_greater": true, "parent": body, "hint_low": "Dim", "hint_high": "Bright"}
	)
	_fog_energy_row.value_changed.connect(_on_override_value.bind("fog_light_energy"))
	_fog_energy_row.reset_requested.connect(_on_reset_requested.bind(["fog_light_energy"]))
	_fog_height_row = _add_row(
		"Fog height",
		-10.0,
		10.0,
		0.1,
		0.0,
		{
			"allow_greater": true,
			"allow_lesser": true,
			"parent": body,
			"hint_low": "Low",
			"hint_high": "High",
		}
	)
	_fog_height_row.value_changed.connect(_on_override_value.bind("fog_height"))
	_fog_height_row.reset_requested.connect(_on_reset_requested.bind(["fog_height"]))
	_fog_height_density_row = _add_row(
		"Fog falloff",
		0.0,
		10.0,
		0.01,
		0.0,
		{
			"allow_greater": true,
			"parent": body,
			"hint_low": "Low",
			"hint_high": "High",
			"tooltip": "How quickly the fog thins with height",
		}
	)
	_fog_height_density_row.value_changed.connect(_on_override_value.bind("fog_height_density"))
	_fog_height_density_row.reset_requested.connect(
		_on_reset_requested.bind(["fog_height_density"])
	)


func _build_header() -> void:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	var heading := Label.new()
	heading.text = "Sky"
	heading.theme_type_variation = &"SectionHeader"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_revert_button = IconButton.new()
	_revert_button.icon_name = "restore"
	_revert_button.tooltip_text = "Revert to the map's own lighting"
	_revert_button.visible = false
	_revert_button.pressed.connect(_on_revert_pressed)
	header.add_child(_revert_button)
	_clear_button = IconButton.new()
	_clear_button.icon_name = "eraser"
	_clear_button.tooltip_text = "Clear every override"
	_clear_button.disabled = true
	_clear_button.pressed.connect(_on_clear_pressed)
	header.add_child(_clear_button)


func _populate_presets(has_map_defaults: bool) -> void:
	_has_map_defaults = has_map_defaults
	_preset_dropdown.clear()
	var idx := 0
	var no_preset_text := EnvironmentPresets.display_name("") if has_map_defaults else "No preset"
	var no_preset_tooltip := (
		"Use the map's embedded lighting"
		if has_map_defaults
		else "Engine defaults, no preset applied"
	)
	_preset_dropdown.add_item(no_preset_text, idx)
	_preset_dropdown.set_item_tooltip(idx, no_preset_tooltip)
	_preset_dropdown.set_item_metadata(idx, "")
	idx += 1
	for group in EnvironmentPresets.PRESET_GROUPS:
		_preset_dropdown.add_separator(group)
		idx += 1
		for preset_name in EnvironmentPresets.PRESET_GROUPS[group]:
			_preset_dropdown.add_item(EnvironmentPresets.display_name(preset_name), idx)
			_preset_dropdown.set_item_icon(idx, SwatchTextures.preset_swatch(preset_name))
			_preset_dropdown.set_item_tooltip(
				idx, EnvironmentPresets.get_preset_description(preset_name)
			)
			_preset_dropdown.set_item_metadata(idx, preset_name)
			idx += 1


## Called by the panel from initialize(): the map may carry its own
## environment (revert button, "Map Defaults" preset) and its own sky.
func set_map_options(has_map_defaults: bool, has_map_sky: bool) -> void:
	_populate_presets(has_map_defaults)
	_revert_button.visible = has_map_defaults
	_sky_tiles.set_tile_visible(&"map_default", has_map_sky)
	_sync_from_model()


func load_state(_state: LevelVisualState) -> void:
	_sync_from_model()


func write_state(state: LevelVisualState) -> void:
	state.environment_preset = _model.preset
	state.environment_overrides = _model.overrides.duplicate()


func _sync_from_model() -> void:
	if not _model or not is_node_ready():
		return
	OptionButtonUtils.select_by_metadata(_preset_dropdown, _model.preset)
	if _model.preset.is_empty():
		_preset_caption.text = (
			"The map's own lighting" if _has_map_defaults else "No preset: engine defaults"
		)
	else:
		_preset_caption.text = EnvironmentPresets.get_preset_description(_model.preset)
	var config := _model.resolve()
	_bg_row.set_color_no_signal(config.get("background_color", Color(0.3, 0.3, 0.3)))
	_bg_row.overridden = _model.is_overridden(["background_color"])
	_ambient_row.set_color_no_signal(config.get("ambient_light_color", Color(0.4, 0.4, 0.45)))
	_ambient_row.set_value_no_signal(config.get("ambient_light_energy", 0.5))
	_ambient_row.overridden = _model.is_overridden(AMBIENT_KEYS)
	_fog_row.set_checked_no_signal(config.get("fog_enabled", false))
	_fog_row.set_value_no_signal(config.get("fog_density", 0.01))
	_fog_row.overridden = _model.is_overridden(FOG_KEYS)
	_sky_tiles.select(StringName(config.get("sky_preset", "")))
	_sky_field.overridden = _model.is_overridden(SKY_KEYS)
	_refresh_sky_preview()
	_fog_color_row.set_color_no_signal(config.get("fog_light_color", Color(0.5, 0.5, 0.55)))
	_fog_color_row.overridden = _model.is_overridden(["fog_light_color"])
	_fog_energy_row.set_value_no_signal(config.get("fog_light_energy", 1.0))
	_fog_energy_row.overridden = _model.is_overridden(["fog_light_energy"])
	_fog_height_row.set_value_no_signal(config.get("fog_height", 0.0))
	_fog_height_row.overridden = _model.is_overridden(["fog_height"])
	_fog_height_density_row.set_value_no_signal(config.get("fog_height_density", 0.0))
	_fog_height_density_row.overridden = _model.is_overridden(["fog_height_density"])
	_clear_button.disabled = _model.overrides.is_empty()


func _on_model_changed(_preset: String, _overrides: Dictionary) -> void:
	_sync_from_model()


func _on_preset_selected(index: int) -> void:
	_model.set_preset(_preset_dropdown.get_item_metadata(index))
	changed.emit()
	if not _model.overrides.is_empty():
		UIManager.show_info("Preset changed. %d override(s) kept." % _model.overrides.size())


func _on_override_value(value: float, key: String) -> void:
	_model.set_override(key, value)
	changed.emit()


func _on_override_color(color: Color, key: String) -> void:
	_model.set_override(key, color)
	changed.emit()


func _on_override_toggle(on: bool, key: String) -> void:
	_model.set_override(key, on)
	changed.emit()


func _on_sky_selected(id: StringName) -> void:
	_model.set_sky_preset(String(id))
	changed.emit()


func _on_sky_tile_hovered(id: StringName) -> void:
	_is_hovering = true
	_hover_key = id
	_refresh_sky_preview()


func _on_sky_tile_unhovered(id: StringName) -> void:
	if _hover_key != id:
		return
	_is_hovering = false
	_refresh_sky_preview()


## The strip and caption show the hovered tile, else the selected one. Hover is
## never an edit: nothing here touches the model or the scene.
func _refresh_sky_preview() -> void:
	if not _sky_preview:
		return
	var key := String(_hover_key) if _is_hovering else String(_sky_tiles.selected)
	if key == "map_default":
		_sky_preview.visible = false
		_sky_caption.text = CAPTION_MAP
	elif key.is_empty():
		_sky_preview.visible = false
		_sky_caption.text = CAPTION_NONE
	else:
		_sky_preview.texture = SwatchTextures.sky_preview(key)
		_sky_preview.visible = true
		_sky_caption.text = EnvironmentPresets.get_sky_preset_description(key)


## Keep the strip at the preview's 4:1 aspect as the pane width changes.
func _on_preview_resized() -> void:
	var height := maxf(_sky_preview.size.x / 4.0, float(PREVIEW_HEIGHT))
	if not is_equal_approx(_sky_preview.custom_minimum_size.y, height):
		_sky_preview.custom_minimum_size = Vector2(0, height)


func _on_reset_requested(keys: Array) -> void:
	if _model.erase_keys(keys):
		changed.emit()


## Reverting is an edit like any other: the controller rewrites the live level
## data and then calls apply_environment_state(), so the drawer has unsaved
## work afterwards.
func _on_revert_pressed() -> void:
	revert_to_map_defaults_requested.emit()
	changed.emit()


func _on_clear_pressed() -> void:
	if _model.clear_all():
		UIManager.show_info("Overrides cleared.")
		changed.emit()
