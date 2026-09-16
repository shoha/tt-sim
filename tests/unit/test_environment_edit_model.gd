extends GutTest

## EnvironmentEditModel owns preset + overrides for the Sky and Color panes.
## User edits emit changed; loads emit reloaded only; erasing the last
## adjustment_* override also drops adjustment_enabled.


func _model() -> EnvironmentEditModel:
	var model := EnvironmentEditModel.new()
	model.load_from("outdoor_day", {}, {})
	return model


func test_load_from_emits_reloaded_not_changed() -> void:
	var model := EnvironmentEditModel.new()
	watch_signals(model)
	model.load_from("cave", {"fog_enabled": true}, {})
	assert_signal_emitted(model, "reloaded")
	assert_signal_not_emitted(model, "changed")
	assert_eq(model.preset, "cave")
	assert_true(model.is_overridden(["fog_enabled"]))


func test_set_override_emits_with_current_dict() -> void:
	var model := _model()
	watch_signals(model)
	model.set_override("ambient_light_energy", 2.0)
	var params: Array = get_signal_parameters(model, "changed")
	assert_eq(params[0], "outdoor_day")
	assert_eq(params[1].get("ambient_light_energy"), 2.0)


func test_set_preset_keeps_overrides() -> void:
	var model := _model()
	model.set_override("ambient_light_energy", 2.0)
	model.set_preset("dungeon_dark")
	assert_eq(model.preset, "dungeon_dark")
	assert_eq(model.overrides.get("ambient_light_energy"), 2.0)


func test_adjustment_override_enables_adjustments() -> void:
	var model := _model()
	model.set_adjustment_override("adjustment_brightness", 1.2)
	assert_true(model.overrides.get("adjustment_enabled", false))


func test_erasing_last_adjustment_drops_the_flag() -> void:
	var model := _model()
	model.set_adjustment_override("adjustment_brightness", 1.2)
	model.set_adjustment_override("adjustment_contrast", 1.1)
	assert_true(model.erase_keys(["adjustment_brightness"]))
	assert_true(model.overrides.has("adjustment_enabled"), "another adjustment remains")
	assert_true(model.erase_keys(["adjustment_contrast"]))
	assert_false(model.overrides.has("adjustment_enabled"))


func test_erasing_nothing_is_silent_and_false() -> void:
	var model := _model()
	watch_signals(model)
	assert_false(model.erase_keys(["fog_density"]))
	assert_signal_not_emitted(model, "changed")


func test_clear_all() -> void:
	var model := _model()
	assert_false(model.clear_all())
	model.set_override("fog_density", 0.05)
	watch_signals(model)
	assert_true(model.clear_all())
	assert_true(model.overrides.is_empty())
	assert_signal_emit_count(model, "changed", 1)


func test_sky_preset_switches_background_and_ambient_modes() -> void:
	var model := _model()
	model.set_sky_preset("clear_day")
	assert_eq(model.overrides["background_mode"], Environment.BG_SKY)
	assert_eq(model.overrides["ambient_light_source"], Environment.AMBIENT_SOURCE_SKY)
	model.set_sky_preset("")
	assert_eq(model.overrides["background_mode"], Environment.BG_COLOR)
	assert_eq(model.overrides["ambient_light_source"], Environment.AMBIENT_SOURCE_COLOR)


func test_resolve_applies_override_on_top_of_preset() -> void:
	var model := _model()
	var base: float = model.resolve()["ambient_light_energy"]
	model.set_override("ambient_light_energy", base + 1.0)
	assert_eq(model.resolve()["ambient_light_energy"], base + 1.0)
