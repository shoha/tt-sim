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
