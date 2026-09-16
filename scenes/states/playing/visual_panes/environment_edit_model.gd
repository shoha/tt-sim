class_name EnvironmentEditModel
extends RefCounted

## The Visuals drawer's working copy of the environment layering inputs:
## preset name, user overrides and the map's extracted defaults. The Sky and
## Color panes both edit it. Every user edit emits [signal changed], which the
## panel relays as environment_changed; [signal reloaded] fires for silent
## loads (initialize, apply_environment_state) so panes resync their controls
## without the panel re-broadcasting anything.

signal changed(preset: String, overrides: Dictionary)
signal reloaded

var preset: String = ""
var overrides: Dictionary = {}
var map_defaults: Dictionary = {}


## Replace every input silently and tell panes to resync.
func load_from(new_preset: String, new_overrides: Dictionary, new_map_defaults: Dictionary) -> void:
	preset = new_preset
	overrides = new_overrides.duplicate()
	map_defaults = new_map_defaults
	reloaded.emit()


func has_map_defaults() -> bool:
	return not map_defaults.is_empty()


## The final config the live environment sees (PROPERTY_DEFAULTS -> map
## defaults -> preset -> overrides).
func resolve() -> Dictionary:
	return EnvironmentPresets.get_environment_config(preset, overrides, map_defaults)


func is_overridden(keys: Array) -> bool:
	for key in keys:
		if overrides.has(key):
			return true
	return false


func set_preset(new_preset: String) -> void:
	preset = new_preset
	_emit_changed()


func set_override(key: String, value: Variant) -> void:
	overrides[key] = value
	_emit_changed()


## Adjustment overrides also switch the adjustment system on.
func set_adjustment_override(key: String, value: Variant) -> void:
	overrides[key] = value
	overrides["adjustment_enabled"] = true
	_emit_changed()


## A sky selects BG_SKY and sky ambient; "" reverts to the flat colour.
func set_sky_preset(sky_name: String) -> void:
	overrides["sky_preset"] = sky_name
	if sky_name != "":
		overrides["background_mode"] = Environment.BG_SKY
		overrides["ambient_light_source"] = Environment.AMBIENT_SOURCE_SKY
	else:
		overrides["background_mode"] = Environment.BG_COLOR
		overrides["ambient_light_source"] = Environment.AMBIENT_SOURCE_COLOR
	_emit_changed()


## Erase [param keys]; drop adjustment_enabled too if that was the last
## adjustment_* override. Returns true (and emits) only if something was erased.
func erase_keys(keys: Array) -> bool:
	var erased_any := false
	var cleared_adjustment_key := false
	for key in keys:
		if overrides.erase(key):
			erased_any = true
			if String(key).begins_with("adjustment_"):
				cleared_adjustment_key = true
	if cleared_adjustment_key and not _has_remaining_adjustment_override():
		overrides.erase("adjustment_enabled")
	if erased_any:
		_emit_changed()
	return erased_any


func clear_all() -> bool:
	if overrides.is_empty():
		return false
	overrides.clear()
	_emit_changed()
	return true


func _has_remaining_adjustment_override() -> bool:
	for key in overrides:
		if key != "adjustment_enabled" and String(key).begins_with("adjustment_"):
			return true
	return false


func _emit_changed() -> void:
	changed.emit(preset, overrides)
