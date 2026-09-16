extends GutTest

## FilmPane round-trips every LofiSettings field through load_state /
## write_state, emits lofi_changed with the full dict plus changed on edits,
## and stays silent on load.


func _pane() -> FilmPane:
	var pane := FilmPane.new()
	add_child_autofree(pane)
	return pane


func _state() -> LevelVisualState:
	var state := LevelVisualState.new()
	state.lofi.pixelation = 0.005
	state.lofi.saturation = 0.7
	state.lofi.color_levels = 16.0
	state.lofi.dither_strength = 0.4
	state.lofi.vignette_strength = 0.6
	state.lofi.vignette_radius = 0.9
	state.lofi.grain_intensity = 0.05
	return state


func test_round_trip_every_field() -> void:
	var pane := _pane()
	var state := _state()
	pane.load_state(state)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.lofi.to_dict(), state.lofi.to_dict())
	assert_ne(out.lofi, state.lofi, "write_state hands out an independent copy")


func test_load_sets_rows_silently() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane.load_state(_state())
	assert_eq(pane._rows["pixelation"].value, 0.005)
	assert_eq(pane._rows["color_levels"].value, 16.0)
	assert_signal_not_emitted(pane, "changed")
	assert_signal_not_emitted(pane, "lofi_changed")


func test_edit_emits_payload_and_changed() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_row_changed(0.25, "dither_strength")
	assert_signal_emitted(pane, "changed")
	var params: Array = get_signal_parameters(pane, "lofi_changed")
	assert_eq(params[0]["dither_strength"], 0.25)
	assert_eq(params[0]["pixelation"], 0.005, "other fields ride along")


func test_every_row_is_wired() -> void:
	var pane := _pane()
	for spec in FilmPane.ROWS:
		assert_true(pane._rows.has(spec[1]), spec[1])
