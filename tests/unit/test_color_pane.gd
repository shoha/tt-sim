extends GutTest

## ColorPane edits the shared EnvironmentEditModel: sliders write overrides
## (adjustment rows also enable adjustments), controls resync from the
## resolved config on every model change, override tints follow the keys, and
## a row reset erases through the model.

var _model: EnvironmentEditModel


func _pane() -> ColorPane:
	_model = EnvironmentEditModel.new()
	_model.load_from("outdoor_day", {}, {})
	var pane := ColorPane.new()
	pane.set_model(_model)
	add_child_autofree(pane)
	pane.load_state(LevelVisualState.new())
	return pane


func test_rows_show_resolved_config_after_load() -> void:
	var pane := _pane()
	var config := _model.resolve()
	assert_eq(pane._rows["tonemap_exposure"].value, config["tonemap_exposure"])
	assert_eq(pane._glow_row.checked, config["glow_enabled"])


func test_exposure_edit_writes_override_and_emits_changed() -> void:
	var pane := _pane()
	watch_signals(pane)
	watch_signals(_model)
	pane._on_row_changed(1.5, "tonemap_exposure", false)
	assert_eq(_model.overrides["tonemap_exposure"], 1.5)
	assert_false(_model.overrides.has("adjustment_enabled"))
	assert_signal_emitted(_model, "changed")
	assert_signal_emitted(pane, "changed")
	assert_true(pane._rows["tonemap_exposure"].overridden)


func test_adjustment_edit_enables_adjustments() -> void:
	var pane := _pane()
	pane._on_row_changed(1.2, "adjustment_brightness", true)
	assert_true(_model.overrides["adjustment_enabled"])
	assert_true(pane._rows["adjustment_brightness"].overridden)


func test_glow_check_and_value() -> void:
	var pane := _pane()
	pane._on_glow_toggled(true)
	pane._on_glow_value_changed(1.3)
	assert_true(_model.overrides["glow_enabled"])
	assert_eq(_model.overrides["glow_intensity"], 1.3)
	assert_true(pane._glow_row.overridden)


func test_reset_erases_keys_and_clears_tint() -> void:
	var pane := _pane()
	pane._on_row_changed(1.5, "tonemap_exposure", false)
	pane._on_reset_requested(["tonemap_exposure"])
	assert_false(_model.overrides.has("tonemap_exposure"))
	assert_false(pane._rows["tonemap_exposure"].overridden)
	assert_eq(pane._rows["tonemap_exposure"].value, _model.resolve()["tonemap_exposure"])


func test_tonemap_dropdown_writes_mode() -> void:
	var pane := _pane()
	var aces_index := -1
	for i in range(pane._tonemap_dropdown.item_count):
		if pane._tonemap_dropdown.get_item_metadata(i) == Environment.TONE_MAPPER_ACES:
			aces_index = i
	pane._on_tonemap_selected(aces_index)
	assert_eq(_model.overrides["tonemap_mode"], Environment.TONE_MAPPER_ACES)
	assert_true(pane._tonemap_row.overridden)


func test_model_reload_resyncs_rows() -> void:
	var pane := _pane()
	_model.load_from("outdoor_day", {"tonemap_exposure": 2.2}, {})
	assert_eq(pane._rows["tonemap_exposure"].value, 2.2)
	assert_true(pane._rows["tonemap_exposure"].overridden)
