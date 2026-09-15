extends GutTest

## Dirty-state contract of the Visuals drawer: any live edit marks it dirty, only
## mark_clean() clears it, a dirty drawer refuses to close from its tab, and the badge
## follows the flag.

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


func test_starts_clean() -> void:
	assert_false(_panel.is_dirty())
	assert_true(_panel._can_close_from_tab())


func test_lofi_edit_marks_dirty_and_emits_once() -> void:
	watch_signals(_panel)
	_panel._on_lofi_override_changed(0.5, "pixelation")
	_panel._on_lofi_override_changed(0.6, "pixelation")
	assert_true(_panel.is_dirty())
	assert_signal_emit_count(_panel, "dirty_changed", 1)


func test_every_live_edit_marks_dirty() -> void:
	var edits: Array[Callable] = [
		func() -> void: _panel._on_intensity_changed(0.4),
		func() -> void: _panel._on_env_override_changed(1.5, "ambient_light_energy"),
		func() -> void: _panel._on_adjustment_override_changed(1.1, "adjustment_brightness"),
		func() -> void: _panel._on_weather_override_changed(0.3, "rain_intensity"),
		func() -> void: _panel._on_foliage_override_changed(2.0, "tree_sway_speed"),
		func() -> void: _panel._on_sun_energy_changed(0.7),
		func() -> void: _panel._on_grid_cell_size_changed(2.0),
	]
	for edit in edits:
		_panel.mark_clean()
		edit.call()
		assert_true(_panel.is_dirty(), str(edit))


func test_mark_clean_clears_and_allows_tab_close() -> void:
	_panel._on_weather_override_changed(0.3, "rain_intensity")
	_panel.mark_clean()
	assert_false(_panel.is_dirty())
	assert_true(_panel._can_close_from_tab())


func test_dirty_panel_refuses_tab_close() -> void:
	_panel._on_weather_override_changed(0.3, "rain_intensity")
	assert_false(_panel._can_close_from_tab(), "A dirty drawer must prompt instead of closing")


func test_initialize_does_not_clear_dirty() -> void:
	_panel._on_weather_override_changed(0.3, "rain_intensity")
	_panel.initialize(LevelData.new())
	assert_true(_panel.is_dirty(), "Reopening a dirty drawer keeps the unsaved state")
