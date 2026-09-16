extends GutTest

## SunPane ports LevelEditSunSection: time of day regenerates direction,
## colour and energy while keeping mode and shadow choices; any other edit
## while in auto promotes the mode to on; the regenerate button shows only
## when values diverge from the generator; gizmo drags update the rows.


func _pane() -> SunPane:
	var pane := SunPane.new()
	add_child_autofree(pane)
	var state := LevelVisualState.new()
	state.sun = DefaultSun.settings_for_time(10.0)
	state.sun.mode = "auto"
	state.sun.shadows_enabled = true
	state.sun.softness = 1.5
	pane.load_state(state)
	return pane


func test_round_trip_every_field() -> void:
	var pane := _pane()
	var state := LevelVisualState.new()
	state.sun.mode = "on"
	state.sun.azimuth_degrees = 123.0
	state.sun.elevation_degrees = 33.0
	state.sun.color = Color(1.0, 0.9, 0.8)
	state.sun.energy = 1.7
	state.sun.shadows_enabled = false
	state.sun.softness = 2.0
	state.sun.shadow_darkness = 0.4
	state.sun.time_of_day = 7.5
	pane.load_state(state)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.sun.to_dict(), state.sun.to_dict())
	assert_ne(out.sun, state.sun)


func test_load_is_silent_and_syncs_controls() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane.load_state(LevelVisualState.new())
	assert_signal_not_emitted(pane, "sun_changed")
	assert_signal_not_emitted(pane, "changed")
	assert_eq(pane._mode_tiles.selected, &"auto")
	assert_eq(pane._time_row.value, DefaultSun.DEFAULT_TIME_OF_DAY)


func test_time_of_day_regenerates_and_keeps_user_choices() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_time_changed(17.0)
	var generated := DefaultSun.settings_for_time(17.0)
	var params: Array = get_signal_parameters(pane, "sun_changed")
	var settings: SunSettings = params[0]
	assert_eq(settings.azimuth_degrees, generated.azimuth_degrees)
	assert_eq(settings.energy, generated.energy)
	assert_eq(settings.softness, 1.5, "shadow choices carry across")
	assert_eq(settings.mode, "on", "editing while auto promotes to on")
	assert_eq(pane._azimuth_row.value, generated.azimuth_degrees)
	assert_false(pane._regenerate_button.visible)


func test_manual_edit_diverges_and_shows_regenerate() -> void:
	var pane := _pane()
	pane._on_azimuth_changed(200.0)
	assert_true(pane._regenerate_button.visible)
	assert_eq(pane._mode_tiles.selected, &"on")
	pane._on_regenerate_pressed()
	assert_false(pane._regenerate_button.visible)


func test_mode_tile_does_not_promote() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_mode_selected(&"off")
	var settings: SunSettings = get_signal_parameters(pane, "sun_changed")[0]
	assert_eq(settings.mode, "off")


func test_shadow_tiles_gate_softness_and_darkness() -> void:
	var pane := _pane()
	pane._on_shadow_tile_selected(&"off")
	assert_false(pane._softness_row.editable)
	assert_false(pane._darkness_row.editable)
	assert_false(pane._sun.shadows_enabled)
	pane._on_shadow_tile_selected(&"hard")
	assert_true(pane._softness_row.editable)
	assert_true(pane._darkness_row.editable)
	assert_true(pane._sun.shadows_enabled)
	assert_eq(pane._sun.softness, 0.0)


func test_gizmo_direction_updates_rows_and_emits() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane.apply_gizmo_direction(45.0, 60.0)
	assert_eq(pane._azimuth_row.value, 45.0)
	assert_eq(pane._elevation_row.value, 60.0)
	assert_signal_emitted(pane, "sun_changed")
	assert_signal_emitted(pane, "changed")


func test_aim_button_round_trip() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._aim_button.button_pressed = true
	assert_signal_emitted_with_parameters(pane, "aim_toggled", [true])
	pane.set_aim_pressed(false)
	assert_false(pane._aim_button.button_pressed)
	assert_signal_emit_count(pane, "aim_toggled", 1, "set_aim_pressed is silent")


func test_mode_and_shadow_tiles_live_in_full_width_fields() -> void:
	var pane := _pane()
	assert_true(pane._mode_field is TileField)
	assert_same(pane._mode_tiles, pane._mode_field.tiles)
	assert_true(pane._shadow_field.tiles.has_tile(&"soft"))


func test_load_maps_shadow_settings_to_a_tile() -> void:
	var pane := _pane()
	var state := LevelVisualState.new()
	state.sun.shadows_enabled = true
	state.sun.softness = 1.5
	pane.load_state(state)
	assert_eq(pane._shadow_field.tiles.selected, &"soft")
	state.sun.softness = 0.1
	pane.load_state(state)
	assert_eq(pane._shadow_field.tiles.selected, &"hard")
	state.sun.shadows_enabled = false
	pane.load_state(state)
	assert_eq(pane._shadow_field.tiles.selected, &"off")


func test_shadow_tiles_apply_values_and_gate_rows() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_shadow_tile_selected(&"hard")
	assert_true(pane._sun.shadows_enabled)
	assert_eq(pane._sun.softness, 0.0)
	pane._on_shadow_tile_selected(&"soft")
	assert_eq(pane._sun.softness, SunPane.SHADOW_SOFT_SOFTNESS)
	assert_true(pane._softness_row.editable)
	pane._on_shadow_tile_selected(&"off")
	assert_false(pane._sun.shadows_enabled)
	assert_false(pane._softness_row.editable)
	assert_signal_emit_count(pane, "sun_changed", 3)
	assert_eq(pane._sun.mode, "on", "sun edits promote auto to on")


func test_softness_slider_moves_the_shadow_tile() -> void:
	var pane := _pane()
	pane._on_shadow_tile_selected(&"hard")
	pane._on_softness_changed(2.0)
	assert_eq(pane._shadow_field.tiles.selected, &"soft")


func test_formatters() -> void:
	assert_eq(SunPane.format_time(14.5), "14:30")
	assert_eq(SunPane.format_time(0.0), "00:00")
	assert_eq(SunPane.format_time(23.999), "00:00")
	assert_eq(SunPane.format_bearing(143.0), "143° SE")
	assert_eq(SunPane.format_bearing(0.0), "0° N")
	assert_eq(SunPane.format_bearing(360.0), "0° N")
	assert_eq(SunPane.format_degrees(43.4), "43°")
	var pane := _pane()
	assert_eq(pane._time_row.hint_low, "Dawn")
	assert_eq(pane._energy_row.hint_high, "Blazing")
