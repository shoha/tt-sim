class_name ColorPane
extends LevelEditPane

## Tone and colour grading: exposure, brightness, contrast, saturation, glow,
## and (advanced) tonemap mode, white point, glow strength, bloom. Every
## control is an environment override on the shared EnvironmentEditModel; the
## Sky pane writes those overrides into the state on Save. This pane
## additionally owns light_intensity_scale ("Light energy"), which is not
## part of the model and is the only field its own write_state carries.

signal intensity_changed(new_scale: float)

const TONEMAP_MODES := {
	"Linear": Environment.TONE_MAPPER_LINEAR,
	"Reinhardt": Environment.TONE_MAPPER_REINHARDT,
	"Filmic": Environment.TONE_MAPPER_FILMIC,
	"ACES": Environment.TONE_MAPPER_ACES,
}
## [label, override key, min, max, step, allow_greater, is_adjustment, hint_low, hint_high]
const ROWS := [
	["Brightness", "tonemap_exposure", 0.1, 4.0, 0.01, true, false, "Darker", "Brighter"],
	["Contrast", "adjustment_contrast", 0.1, 3.0, 0.01, false, true, "Flat", "Punchy"],
	["Saturation", "adjustment_saturation", 0.0, 3.0, 0.01, false, true, "Grey", "Vivid"],
]
const ADVANCED_ROWS := [
	["Fine brightness", "adjustment_brightness", 0.1, 3.0, 0.01, false, true, "Darker", "Brighter"],
	["White point", "tonemap_white", 0.1, 16.0, 0.01, true, false, "Soft", "Hard"],
	["Glow strength", "glow_strength", 0.0, 2.0, 0.01, true, false, "Subtle", "Intense"],
	["Bloom", "glow_bloom", 0.0, 1.0, 0.01, false, false, "Subtle", "Intense"],
]
const GLOW_KEYS := ["glow_enabled", "glow_intensity"]

var light_intensity_scale: float = 1.0

var _model: EnvironmentEditModel
var _rows: Dictionary = {}
var _glow_row: PropertyRow
var _tonemap_row: PropertyRow
var _tonemap_dropdown: OptionButton
var _foldout: Foldout
var _intensity_row: PropertyRow


func set_model(model: EnvironmentEditModel) -> void:
	_model = model
	_model.changed.connect(_on_model_changed)
	_model.reloaded.connect(_sync_from_model)


func _build() -> void:
	_add_heading("Color")
	for spec in ROWS:
		_add_override_row(spec, self)

	_glow_row = _add_row(
		"Glow",
		0.0,
		2.0,
		0.01,
		0.8,
		{
			"show_check": true,
			"allow_greater": true,
			"hint_low": "Subtle",
			"hint_high": "Intense",
		}
	)
	_glow_row.toggled.connect(_on_glow_toggled)
	_glow_row.value_changed.connect(_on_glow_value_changed)
	_glow_row.reset_requested.connect(_on_reset_requested.bind(GLOW_KEYS))

	_foldout = _add_foldout()
	_intensity_row = _add_row(
		"Light energy",
		0.0001,
		2.0,
		0.0001,
		1.0,
		{
			"exp_edit": true,
			"allow_greater": true,
			"parent": _foldout.body,
			"hint_low": "Dim",
			"hint_high": "Bright",
			"formatter": ColorPane.format_percent,
			"tooltip": "Scales every light in the map",
		}
	)
	_intensity_row.value_changed.connect(_on_intensity_changed)
	_tonemap_row = _add_row(
		"Tonemap", 0.0, 1.0, 1.0, 0.0, {"show_slider": false, "parent": _foldout.body}
	)
	_tonemap_dropdown = OptionButton.new()
	var idx := 0
	for label in TONEMAP_MODES:
		_tonemap_dropdown.add_item(label, idx)
		_tonemap_dropdown.set_item_metadata(idx, TONEMAP_MODES[label])
		idx += 1
	_tonemap_dropdown.item_selected.connect(_on_tonemap_selected)
	_tonemap_row.set_control(_tonemap_dropdown)
	_tonemap_row.reset_requested.connect(_on_reset_requested.bind(["tonemap_mode"]))
	for spec in ADVANCED_ROWS:
		_add_override_row(spec, _foldout.body)


func _add_override_row(spec: Array, parent: Node) -> PropertyRow:
	var key: String = spec[1]
	var row := _add_row(
		spec[0],
		spec[2],
		spec[3],
		spec[4],
		spec[3],
		{"allow_greater": spec[5], "parent": parent, "hint_low": spec[7], "hint_high": spec[8]}
	)
	row.value_changed.connect(_on_row_changed.bind(key, spec[6]))
	row.reset_requested.connect(_on_reset_requested.bind([key]))
	_rows[key] = row
	return row


func load_state(state: LevelVisualState) -> void:
	light_intensity_scale = state.light_intensity_scale
	_intensity_row.set_value_no_signal(light_intensity_scale)
	_sync_from_model()


func write_state(state: LevelVisualState) -> void:
	state.light_intensity_scale = light_intensity_scale


func _sync_from_model() -> void:
	if not _model or not is_node_ready():
		return
	var config := _model.resolve()
	for key in _rows:
		_rows[key].set_value_no_signal(config.get(key, _rows[key].value))
		_rows[key].overridden = _model.is_overridden([key])
	_glow_row.set_checked_no_signal(config.get("glow_enabled", false))
	_glow_row.set_value_no_signal(config.get("glow_intensity", 0.8))
	_glow_row.overridden = _model.is_overridden(GLOW_KEYS)
	var tm_mode: int = config.get("tonemap_mode", Environment.TONE_MAPPER_FILMIC)
	OptionButtonUtils.select_by_metadata(_tonemap_dropdown, tm_mode)
	_tonemap_row.overridden = _model.is_overridden(["tonemap_mode"])


func _on_model_changed(_preset: String, _overrides: Dictionary) -> void:
	_sync_from_model()


func _on_row_changed(value: float, key: String, adjustment: bool) -> void:
	if adjustment:
		_model.set_adjustment_override(key, value)
	else:
		_model.set_override(key, value)
	changed.emit()


func _on_glow_toggled(on: bool) -> void:
	_model.set_override("glow_enabled", on)
	changed.emit()


func _on_glow_value_changed(value: float) -> void:
	_model.set_override("glow_intensity", value)
	changed.emit()


func _on_tonemap_selected(index: int) -> void:
	_model.set_override("tonemap_mode", _tonemap_dropdown.get_item_metadata(index))
	changed.emit()


func _on_reset_requested(keys: Array) -> void:
	if _model.erase_keys(keys):
		changed.emit()


static func format_percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


func _on_intensity_changed(value: float) -> void:
	light_intensity_scale = value
	intensity_changed.emit(value)
	changed.emit()
