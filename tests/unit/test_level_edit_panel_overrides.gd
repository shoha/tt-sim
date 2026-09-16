extends GutTest

## Switching presets keeps the user's environment overrides (the layering model
## resolves preset then overrides), so trying another preset never throws away
## tuning. Override rows tint, reset by key, and the clear button follows the
## override dictionary.

const PANEL_SCENE := preload("res://scenes/states/playing/level_edit_panel.tscn")
const TEMP_SETTINGS := "user://test_panel_overrides_ui_preferences.cfg"

var _host: Control
var _panel: LevelEditPanel


func before_each() -> void:
	UiPreferences.settings_path = TEMP_SETTINGS
	if FileAccess.file_exists(TEMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	_host = Control.new()
	_host.size = Vector2(1920, 1080)
	add_child_autofree(_host)
	_panel = PANEL_SCENE.instantiate()
	_host.add_child(_panel)
	_panel.initialize(LevelData.new())


func after_each() -> void:
	if FileAccess.file_exists(TEMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	UiPreferences.settings_path = Paths.SETTINGS_PATH
	if not is_instance_valid(_panel):
		_panel = null
		return
	UIManager.unregister_overlay(_panel)
	var prompt: Node = _panel._close_prompt
	if is_instance_valid(prompt) and not prompt.is_queued_for_deletion():
		prompt.queue_free()
	_panel = null


func _overrides() -> Dictionary:
	return _panel._env_model.overrides


func _select_preset_named(preset: String) -> void:
	var dropdown: OptionButton = _panel.sky_pane._preset_dropdown
	for i in range(dropdown.item_count):
		if dropdown.get_item_metadata(i) == preset:
			_panel.sky_pane._on_preset_selected(i)
			return
	fail_test("preset not in dropdown: " + preset)


func test_preset_switch_keeps_overrides() -> void:
	_panel.sky_pane._on_override_value(2.0, "ambient_light_energy")
	_select_preset_named("dungeon_dark")
	assert_eq(_panel._env_model.preset, "dungeon_dark")
	assert_eq(_overrides().get("ambient_light_energy"), 2.0)


func test_preset_switch_emits_environment_changed_with_overrides() -> void:
	_panel.sky_pane._on_override_value(2.0, "ambient_light_energy")
	watch_signals(_panel)
	_select_preset_named("outdoor_day")
	assert_signal_emitted(_panel, "environment_changed")
	var params: Array = get_signal_parameters(_panel, "environment_changed")
	assert_eq(params[0], "outdoor_day")
	assert_eq(params[1].get("ambient_light_energy"), 2.0)


func test_override_marks_its_row() -> void:
	_panel.sky_pane._on_override_value(2.0, "ambient_light_energy")
	assert_true(_panel.sky_pane._ambient_row.overridden)
	assert_false(_panel.sky_pane._fog_row.overridden)


func test_reset_clears_row_and_emits() -> void:
	_panel.sky_pane._on_override_value(2.0, "ambient_light_energy")
	watch_signals(_panel)
	_panel.sky_pane._on_reset_requested(SkyPane.AMBIENT_KEYS)
	assert_false(_overrides().has("ambient_light_energy"))
	assert_false(_panel.sky_pane._ambient_row.overridden)
	assert_signal_emitted(_panel, "environment_changed")


func test_resetting_a_row_with_no_override_leaves_the_panel_clean() -> void:
	_panel.mark_clean()
	watch_signals(_panel)
	_panel.sky_pane._on_reset_requested(SkyPane.FOG_KEYS)
	assert_false(_panel.is_dirty())
	assert_signal_not_emitted(_panel, "environment_changed")


func test_clearing_last_adjustment_key_drops_adjustment_enabled() -> void:
	_panel.color_pane._on_row_changed(1.2, "adjustment_brightness", true)
	assert_true(_overrides().get("adjustment_enabled", false))
	_panel.color_pane._on_reset_requested(["adjustment_brightness"])
	assert_false(_overrides().has("adjustment_enabled"))


func test_clear_overrides_button_state_follows_overrides() -> void:
	assert_true(_panel.sky_pane._clear_button.disabled)
	_panel.sky_pane._on_override_value(2.0, "ambient_light_energy")
	assert_false(_panel.sky_pane._clear_button.disabled)
	_panel.sky_pane._on_clear_pressed()
	assert_true(_overrides().is_empty())
	assert_true(_panel.sky_pane._clear_button.disabled)


func test_apply_environment_state_resyncs_without_broadcasting() -> void:
	watch_signals(_panel)
	_panel.apply_environment_state("cave", {"fog_density": 0.05})
	assert_eq(_panel._env_model.preset, "cave")
	assert_true(_panel.sky_pane._fog_row.overridden)
	assert_signal_not_emitted(_panel, "environment_changed")


func test_single_override_edit_broadcasts_environment_changed_once() -> void:
	watch_signals(_panel)
	_panel.sky_pane._on_override_value(2.0, "ambient_light_energy")
	assert_signal_emit_count(_panel, "environment_changed", 1)
	_panel.color_pane._on_row_changed(1.5, "tonemap_exposure", false)
	assert_signal_emit_count(_panel, "environment_changed", 2)
