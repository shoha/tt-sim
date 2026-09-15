class_name LevelEditOverrideRows
extends RefCounted

## Owns the "Overrides" row table for LevelEditPanel: which label maps to which
## environment_overrides key(s), per-row right-click reset, and the shared
## "erase these keys" rule (adjustment_enabled drops once no other
## adjustment_* key remains). Split out of level_edit_panel.gd to keep that
## file under the project's max-file-lines lint budget.

const OVERRIDE_INDICATOR_COLOR := Color("#db924b")  # color_accent

## Unique node name (%name) of each override row's label -> the
## environment_overrides key(s) it reflects.
const _KEYS_BY_LABEL_NAME := {
	"BgColorLabel": ["background_color"],
	"AmbientLabel": ["ambient_light_color", "ambient_light_energy"],
	"FogLabel": ["fog_enabled", "fog_light_color", "fog_density"],
	"GlowLabel": ["glow_enabled", "glow_intensity"],
	"ExposureLabel": ["tonemap_exposure"],
	"BrightnessLabel": ["adjustment_brightness"],
	"ContrastLabel": ["adjustment_contrast"],
	"SaturationLabel": ["adjustment_saturation"],
	"SkyLabel": ["sky_preset", "background_mode", "ambient_light_source"],
	"FogEnergyLabel": ["fog_light_energy"],
	"FogHeightLabel": ["fog_height"],
	"FogHDLabel": ["fog_height_density"],
	"TonemapLabel": ["tonemap_mode"],
	"TmWhiteLabel": ["tonemap_white"],
	"GlowStrLabel": ["glow_strength"],
	"GlowBloomLabel": ["glow_bloom"],
}

var _rows: Array[Array] = []


## Resolves each row's label from [param panel] by node name, then wires it
## for right-click reset via [param on_clear_keys].
func _init(panel: Node, on_clear_keys: Callable) -> void:
	for label_name in _KEYS_BY_LABEL_NAME:
		var label := panel.find_child(label_name, true, false) as Label
		_rows.append([label, _KEYS_BY_LABEL_NAME[label_name]])
	for row in _rows:
		var label: Label = row[0]
		var keys: Array = row[1]
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.gui_input.connect(_on_label_gui_input.bind(keys, on_clear_keys))


func _on_label_gui_input(event: InputEvent, keys: Array, on_clear_keys: Callable) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			on_clear_keys.call(keys)


## Tint each row label whose key(s) are overridden; gate [param clear_button].
func refresh(overrides: Dictionary, clear_button: Button) -> void:
	for row in _rows:
		var label: Label = row[0]
		var keys: Array = row[1]
		var overridden: bool = keys.any(func(k): return overrides.has(k))
		if overridden:
			label.add_theme_color_override("font_color", OVERRIDE_INDICATOR_COLOR)
		else:
			label.remove_theme_color_override("font_color")
		label.tooltip_text = (
			"Overridden. Right-click to reset to the preset value." if overridden else ""
		)
	clear_button.disabled = overrides.is_empty()


## Erase [param keys] from [param overrides]; drop adjustment_enabled too if
## that was the last remaining adjustment_* override. Returns true if at least
## one key was actually erased (false is a no-op: nothing to mark dirty over).
static func erase_keys(overrides: Dictionary, keys: Array) -> bool:
	var erased_any := false
	var cleared_adjustment_key := false
	for key in keys:
		if overrides.erase(key):
			erased_any = true
			if key.begins_with("adjustment_"):
				cleared_adjustment_key = true
	if cleared_adjustment_key and not _has_remaining_adjustment_override(overrides):
		overrides.erase("adjustment_enabled")
	return erased_any


static func _has_remaining_adjustment_override(overrides: Dictionary) -> bool:
	for key in overrides:
		if key != "adjustment_enabled" and key.begins_with("adjustment_"):
			return true
	return false
