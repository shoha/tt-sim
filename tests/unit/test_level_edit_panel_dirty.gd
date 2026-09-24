extends GutTest

## Dirty-state contract of the Visuals drawer: any live edit in any pane marks
## it dirty and badges that pane's rail item, only mark_clean() clears both, a
## dirty drawer refuses to close from its rail, and pane signals are relayed
## under the panel's public names.

const PANEL_SCENE := preload("res://scenes/states/playing/level_edit_panel.tscn")
const TEMP_SETTINGS := "user://test_panel_ui_preferences.cfg"

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


## Freeing the host does not undo either side effect of a prompt: the discard
## dialog is parented to the tree root (layer 100, grabs focus, traps Tab) and
## the panel re-registers itself with UIManager. Both would leak into the rest
## of the suite. Also restores UiPreferences to the real settings path so the
## per-user preference redirect never leaks into the rest of the suite.
func after_each() -> void:
	if FileAccess.file_exists(TEMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	UiPreferences.settings_path = Paths.SETTINGS_PATH
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


func _badge(id: StringName) -> bool:
	return _panel._rail._buttons[id].badge


func test_starts_clean() -> void:
	assert_false(_panel.is_dirty())
	assert_true(_panel._can_close_from_tab())
	for id in LevelEditPanel.PANE_IDS:
		assert_false(_badge(id), str(id))


func test_rail_has_one_item_per_pane() -> void:
	for id in LevelEditPanel.PANE_IDS:
		assert_true(_panel._rail.has_item(id), str(id))
		assert_not_null(_panel._stack.get_pane(id), str(id))


func test_film_edit_marks_dirty_and_badges_only_film() -> void:
	_panel.film_pane._on_row_changed(0.5, "pixelation")
	assert_true(_panel.is_dirty())
	assert_true(_badge(&"film"))
	assert_false(_badge(&"sun"))


func test_every_live_edit_marks_dirty() -> void:
	var edits: Array[Callable] = [
		func() -> void: _panel.color_pane._on_intensity_changed(0.4),
		func() -> void: _panel.sky_pane._on_override_value(1.5, "ambient_light_energy"),
		func() -> void: _panel.color_pane._on_row_changed(1.1, "adjustment_brightness", true),
		func() -> void: _panel.weather_pane._on_intensity_changed(0.3, "rain"),
		func() -> void: _panel.world_pane._on_foliage_changed(2.0, "tree_sway_speed"),
		func() -> void: _panel.sun_pane._on_energy_changed(0.7),
		func() -> void: _panel.world_pane._on_cell_size_changed(2.0),
		func() -> void: _panel.film_pane._on_row_changed(0.2, "grain_intensity"),
	]
	for edit in edits:
		_panel.mark_clean()
		edit.call()
		assert_true(_panel.is_dirty(), str(edit))


func test_mark_clean_clears_dirty_badges_and_allows_rail_close() -> void:
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	_panel.sun_pane._on_energy_changed(0.7)
	_panel.mark_clean()
	assert_false(_panel.is_dirty())
	assert_false(_badge(&"weather"))
	assert_false(_badge(&"sun"))
	assert_true(_panel._can_close_from_tab())


func test_dirty_panel_refuses_rail_close() -> void:
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	assert_false(_panel._can_close_from_tab(), "A dirty drawer must prompt instead of closing")
	assert_true(is_instance_valid(_panel._close_prompt), "The discard prompt must be on screen")
	_free_close_prompt()


func test_second_close_request_reuses_the_open_prompt() -> void:
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	_panel.request_close()
	var first_prompt: Node = _panel._close_prompt
	_panel.request_close()
	assert_eq(_panel._close_prompt, first_prompt, "A second request must not stack a second dialog")
	_free_close_prompt()


func test_close_request_during_animation_keeps_the_overlay_registered() -> void:
	UIManager.unregister_overlay(_panel)
	var before: int = UIManager.get_overlay_count()
	_panel._is_animating = true
	_panel.request_close()
	assert_eq(
		UIManager.get_overlay_count(), before + 1, "Escape mid-animation must keep the Escape route"
	)


func test_initialize_does_not_clear_dirty() -> void:
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	_panel.initialize(LevelData.new())
	assert_true(_panel.is_dirty(), "Reopening a dirty drawer keeps the unsaved state")


func test_mark_clean_dismisses_open_close_prompt() -> void:
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	_panel.request_close()
	var prompt: Node = _panel._close_prompt
	assert_true(is_instance_valid(prompt), "The discard prompt must be on screen before mark_clean")

	_panel.mark_clean()

	assert_eq(_panel._close_prompt, null, "mark_clean must drop the close-prompt reference")
	assert_true(
		not is_instance_valid(prompt) or prompt.is_queued_for_deletion(),
		"mark_clean must queue_free the stale prompt"
	)


func test_discard_confirm_lets_the_prompt_animate_out() -> void:
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	_panel.request_close()
	var prompt: Node = _panel._close_prompt
	assert_true(is_instance_valid(prompt), "The discard prompt must be on screen")
	_panel.cancel_requested.connect(_panel.mark_clean)

	_panel._on_discard_confirmed()

	assert_eq(_panel._close_prompt, null, "Discard must drop the prompt reference")
	assert_false(_panel.is_dirty(), "The controller's mark_clean must still run")
	assert_true(
		is_instance_valid(prompt) and not prompt.is_queued_for_deletion(),
		"The dialog must be left to animate itself out"
	)
	prompt.queue_free()


func test_pane_signals_are_relayed_under_public_names() -> void:
	watch_signals(_panel)
	_panel.sun_pane._on_energy_changed(0.7)
	assert_signal_emitted(_panel, "sun_changed")
	_panel.film_pane._on_row_changed(0.5, "pixelation")
	assert_signal_emitted(_panel, "lofi_changed")
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	assert_signal_emitted(_panel, "weather_changed")
	_panel.world_pane._on_foliage_changed(2.0, "tree_sway_speed")
	assert_signal_emitted(_panel, "foliage_changed")
	_panel.water_pane._on_motion_selected(&"rough")
	assert_signal_emitted(_panel, "water_changed")
	var water: Array = get_signal_parameters(_panel, "water_changed")
	assert_almost_eq(float(water[0]["wave_speed"]), 1.4, 0.001)
	_panel.world_pane._on_cell_size_changed(2.0)
	assert_signal_emitted(_panel, "scale_config_changed")
	_panel.color_pane._on_intensity_changed(0.4)
	assert_signal_emitted_with_parameters(_panel, "intensity_changed", [0.4])
	_panel.color_pane._on_row_changed(1.5, "tonemap_exposure", false)
	assert_signal_emitted(_panel, "environment_changed")
	_panel.sun_pane._aim_button.button_pressed = true
	assert_signal_emitted_with_parameters(_panel, "aim_sun_toggled", [true])


func test_build_state_collects_every_pane() -> void:
	_panel.film_pane._on_row_changed(0.5, "pixelation")
	_panel.world_pane._on_cell_size_changed(2.0)
	_panel.sun_pane._on_energy_changed(0.7)
	_panel.color_pane._on_intensity_changed(0.4)
	_panel.color_pane._on_row_changed(1.5, "tonemap_exposure", false)
	_panel.weather_pane._on_intensity_changed(0.3, "rain")
	var state: LevelVisualState = _panel._build_state()
	assert_eq(state.lofi.pixelation, 0.5)
	assert_eq(state.grid_cell_size, 2.0)
	assert_eq(state.sun.energy, 0.7)
	assert_eq(state.light_intensity_scale, 0.4)
	assert_eq(state.environment_overrides.get("tonemap_exposure"), 1.5)
	assert_eq(state.weather.rain_intensity, 0.3)


func test_gizmo_forwards_reach_the_sun_pane() -> void:
	_panel.set_sun_direction_from_gizmo(30.0, 40.0)
	assert_eq(_panel.sun_pane._azimuth_row.value, 30.0)
	_panel.set_aim_sun_pressed(true)
	assert_true(_panel.sun_pane._aim_button.button_pressed)
	_panel.initialize(LevelData.new())
	assert_false(_panel.sun_pane._aim_button.button_pressed, "initialize clears the aim toggle")


func test_values_toggle_flips_every_row_and_persists() -> void:
	var rows: Array[Node] = _panel._stack.find_children("*", "PropertyRow", true, false)
	assert_true(rows.has(_panel.color_pane._rows["glow_bloom"]), "Advanced color row collected")
	assert_true(
		rows.has(_panel.world_pane._foliage_rows["grass_sway_amplitude"]),
		"Advanced foliage row collected"
	)
	assert_true(rows.size() >= 30, "panes expose their rows, including Advanced foldouts")
	for row in rows:
		assert_false(row.values_visible)
	_panel._on_rail_footer_pressed(&"values")
	for row in rows:
		assert_true(row.values_visible)
	assert_true(UiPreferences.load_show_values())
	assert_true(_panel._footer_rail._buttons[&"values"].active)
	assert_eq(_panel._footer_rail._buttons[&"values"].tooltip_text, "Hide values")
	_panel._on_rail_footer_pressed(&"values")
	assert_false(UiPreferences.load_show_values())
	assert_eq(_panel._footer_rail._buttons[&"values"].tooltip_text, "Show values")
