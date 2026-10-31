extends GutTest

## WeatherPane: a kind's tile is on when its intensity is above zero and its
## row is shown; turning a tile off zeroes the intensity and remembers the
## last value for the next turn-on.


func _pane() -> WeatherPane:
	var pane := WeatherPane.new()
	add_child_autofree(pane)
	return pane


func _state() -> LevelVisualState:
	var state := LevelVisualState.new()
	state.weather.rain_intensity = 0.6
	state.weather.snow_intensity = 0.0
	state.weather.fog_intensity = 0.2
	state.weather.wind_intensity = 0.0
	return state


func test_round_trip_every_field() -> void:
	var pane := _pane()
	var state := _state()
	pane.load_state(state)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.weather.to_dict(), state.weather.to_dict())


func test_load_reflects_tiles_and_rows() -> void:
	var pane := _pane()
	pane.load_state(_state())
	assert_true(pane._tiles.is_on(&"rain"))
	assert_false(pane._tiles.is_on(&"snow"))
	assert_true(pane._rows["rain"].visible)
	assert_false(pane._rows["snow"].visible)
	assert_eq(pane._rows["rain"].value, 0.6)


func test_turning_on_uses_default_then_remembered_intensity() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_tile_toggled(&"snow", true)
	assert_eq(pane._weather.snow_intensity, WeatherPane.DEFAULT_INTENSITY)
	assert_true(pane._rows["snow"].visible)
	pane._on_intensity_changed(0.9, "snow")
	pane._on_tile_toggled(&"snow", false)
	assert_eq(pane._weather.snow_intensity, 0.0)
	assert_false(pane._rows["snow"].visible)
	pane._on_tile_toggled(&"snow", true)
	assert_eq(pane._weather.snow_intensity, 0.9)
	assert_signal_emit_count(pane, "weather_changed", 4)
	assert_signal_emit_count(pane, "changed", 4)


func test_turning_off_a_loaded_kind_remembers_its_intensity() -> void:
	var pane := _pane()
	pane.load_state(_state())
	pane._on_tile_toggled(&"rain", false)
	pane._on_tile_toggled(&"rain", true)
	assert_eq(pane._weather.rain_intensity, 0.6)


func test_dragging_intensity_to_zero_unpresses_the_tile_but_keeps_the_row() -> void:
	var pane := _pane()
	pane.load_state(_state())
	pane._on_intensity_changed(0.0, "rain")
	assert_false(pane._tiles.is_on(&"rain"), "tile follows the value")
	assert_true(pane._rows["rain"].visible, "row stays under the cursor")
	assert_eq(pane._weather.rain_intensity, 0.0)
	pane._on_intensity_changed(0.4, "rain")
	assert_true(pane._tiles.is_on(&"rain"))


func test_preset_chip_sets_the_wind_dial_tile_and_row() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_wind_preset(&"windy")
	assert_eq(pane._weather.wind_intensity, WindPresets.strength_of("windy"))
	assert_true(pane._tiles.is_on(&"wind"))
	assert_true(pane._rows["wind"].visible)
	assert_eq(pane._rows["wind"].value, WindPresets.strength_of("windy"))
	assert_eq(pane._wind_presets.selected, &"windy")
	assert_signal_emit_count(pane, "weather_changed", 1)
	var payload: Dictionary = get_signal_parameters(pane, "weather_changed")[0]
	assert_eq(payload["wind_intensity"], WindPresets.strength_of("windy"))
	pane._on_wind_preset(&"calm")
	assert_eq(pane._weather.wind_intensity, 0.0)
	assert_false(pane._tiles.is_on(&"wind"))
	assert_false(pane._rows["wind"].visible)


func test_dragging_the_wind_slider_to_a_stop_picks_its_chip() -> void:
	var pane := _pane()
	pane.load_state(_state())
	pane._on_intensity_changed(0.33, "wind")
	assert_eq(pane._wind_presets.selected, &"breezy")
	pane._on_intensity_changed(0.5, "wind")
	assert_eq(pane._wind_presets.selected, &"", "a custom strength picks no chip")


func test_compass_pick_writes_the_heading_and_the_words() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_wind_direction(&"nw")
	assert_eq(pane._weather.wind_direction_deg, 45.0)
	assert_eq(pane._wind_readout.text, "Wind from the north-west")
	assert_eq(pane._wind_compass.selected, &"nw")
	pane._on_wind_direction(WindCompass.AUTO_ID)
	assert_eq(pane._weather.wind_direction_deg, WeatherSettings.WIND_DIRECTION_AUTO)
	assert_eq(pane._wind_readout.text, "Wind from the south-west (automatic)")
	assert_signal_emit_count(pane, "weather_changed", 2)
	assert_signal_emit_count(pane, "changed", 2)


func test_reroll_changes_the_seed_and_emits() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	var before := pane._weather.wind_seed
	pane._on_wind_reroll()
	assert_ne(pane._weather.wind_seed, before)
	assert_true(pane._weather.wind_seed >= 1.0)
	var payload: Dictionary = get_signal_parameters(pane, "weather_changed")[0]
	assert_eq(payload["wind_seed"], pane._weather.wind_seed)


func test_load_shows_a_saved_wind_on_the_controls() -> void:
	var pane := _pane()
	var state := _state()
	state.weather.wind_intensity = 1.0
	state.weather.wind_direction_deg = 180.0
	state.weather.wind_seed = 31.0
	pane.load_state(state)
	assert_eq(pane._wind_presets.selected, &"storm")
	assert_eq(pane._wind_compass.selected, &"e")
	assert_eq(pane._wind_readout.text, "Wind from the east")
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.weather.wind_seed, 31.0)
	assert_eq(out.weather.wind_direction_deg, 180.0)


func test_a_direction_no_tile_stands_for_picks_nothing() -> void:
	var pane := _pane()
	var state := _state()
	state.weather.wind_direction_deg = 65.0
	pane.load_state(state)
	assert_eq(pane._wind_compass.selected, &"")
	assert_eq(pane._wind_readout.text, "Wind from roughly the north-west")


func test_wind_controls_take_keyboard_focus_and_say_what_they_do() -> void:
	var pane := _pane()
	for row: TileRow in [pane._wind_presets, pane._wind_compass]:
		for child in row.get_children():
			assert_eq((child as Button).focus_mode, Control.FOCUS_ALL)
			assert_false((child as Button).tooltip_text.is_empty(), child.name)
	assert_eq(pane._wind_reroll.text, "New gust pattern")
	assert_false(pane._wind_reroll.tooltip_text.is_empty())


func test_intensity_rows_read_light_to_heavy() -> void:
	var pane := _pane()
	assert_eq(pane._rows["rain"].hint_low, "Light")
	assert_eq(pane._rows["wind"].hint_high, "Heavy")
