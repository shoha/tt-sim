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
