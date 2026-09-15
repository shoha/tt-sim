extends GutTest

## Switching presets keeps the user's environment overrides (the layering model
## resolves preset then overrides), so trying another preset never throws away tuning.

const PANEL_SCENE := preload("res://scenes/states/playing/level_edit_panel.tscn")

var _host: Control
var _panel: LevelEditPanel


func before_each() -> void:
	_host = Control.new()
	_host.size = Vector2(1920, 1080)
	add_child_autofree(_host)
	_panel = PANEL_SCENE.instantiate()
	_host.add_child(_panel)
	_panel.initialize(LevelData.new())


## Freeing the host does not undo either side effect of a prompt: the discard
## dialog is parented to the tree root (layer 100, grabs focus, traps Tab) and
## the panel re-registers itself with UIManager. Both would leak into the rest
## of the suite.
func after_each() -> void:
	if not is_instance_valid(_panel):
		_panel = null
		return
	UIManager.unregister_overlay(_panel)
	_free_close_prompt()
	_panel = null


func _free_close_prompt() -> void:
	var prompt: Node = _panel._close_prompt
	if is_instance_valid(prompt) and not prompt.is_queued_for_deletion():
		prompt.queue_free()


func _select_preset_named(preset: String) -> void:
	for i in range(_panel.preset_dropdown.item_count):
		if _panel.preset_dropdown.get_item_metadata(i) == preset:
			_panel._on_preset_selected(i)
			return
	fail_test("preset not in dropdown: " + preset)


func test_preset_switch_keeps_overrides() -> void:
	_panel._on_env_override_changed(2.0, "ambient_light_energy")
	_select_preset_named("dungeon_dark")
	assert_eq(_panel.current_preset, "dungeon_dark")
	assert_eq(_panel.current_overrides.get("ambient_light_energy"), 2.0)


func test_preset_switch_emits_environment_changed_with_overrides() -> void:
	_panel._on_env_override_changed(2.0, "ambient_light_energy")
	watch_signals(_panel)
	_select_preset_named("outdoor_day")
	assert_signal_emitted(_panel, "environment_changed")
	var params: Array = get_signal_parameters(_panel, "environment_changed")
	assert_eq(params[0], "outdoor_day")
	assert_eq(params[1].get("ambient_light_energy"), 2.0)


func test_override_marks_its_row_label() -> void:
	_panel._on_env_override_changed(2.0, "ambient_light_energy")
	assert_true(_panel.get_node("%AmbientLabel").has_theme_color_override("font_color"))
	assert_false(_panel.get_node("%FogLabel").has_theme_color_override("font_color"))


func test_clear_override_keys_resets_row_and_emits() -> void:
	_panel._on_env_override_changed(2.0, "ambient_light_energy")
	watch_signals(_panel)
	_panel._clear_override_keys(["ambient_light_color", "ambient_light_energy"])
	assert_false(_panel.current_overrides.has("ambient_light_energy"))
	assert_false(_panel.get_node("%AmbientLabel").has_theme_color_override("font_color"))
	assert_signal_emitted(_panel, "environment_changed")


func test_clearing_a_row_with_no_override_leaves_the_panel_clean() -> void:
	_panel.mark_clean()
	watch_signals(_panel)
	_panel._clear_override_keys(["fog_enabled", "fog_light_color", "fog_density"])
	assert_false(_panel.is_dirty())
	assert_signal_not_emitted(_panel, "environment_changed")


func test_clearing_last_adjustment_key_drops_adjustment_enabled() -> void:
	_panel._on_adjustment_override_changed(1.2, "adjustment_brightness")
	assert_true(_panel.current_overrides.get("adjustment_enabled", false))
	_panel._clear_override_keys(["adjustment_brightness"])
	assert_false(_panel.current_overrides.has("adjustment_enabled"))


func test_clear_overrides_button_state_follows_overrides() -> void:
	assert_true(_panel.clear_overrides_button.disabled)
	_panel._on_env_override_changed(2.0, "ambient_light_energy")
	assert_false(_panel.clear_overrides_button.disabled)
	_panel._on_clear_overrides_pressed()
	assert_true(_panel.current_overrides.is_empty())
	assert_true(_panel.clear_overrides_button.disabled)
