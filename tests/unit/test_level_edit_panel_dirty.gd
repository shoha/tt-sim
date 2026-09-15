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
	assert_true(is_instance_valid(_panel._close_prompt), "The discard prompt must be on screen")
	_free_close_prompt()


func test_second_close_request_reuses_the_open_prompt() -> void:
	_panel._on_weather_override_changed(0.3, "rain_intensity")
	_panel.request_close()
	var first_prompt: Node = _panel._close_prompt
	_panel.request_close()
	assert_eq(_panel._close_prompt, first_prompt, "A second request must not stack a second dialog")
	_free_close_prompt()


func test_close_request_during_animation_keeps_the_overlay_registered() -> void:
	# close() is a no-op while animating, and Escape has already popped the panel
	# off the overlay stack by the time request_close() runs.
	UIManager.unregister_overlay(_panel)
	var before: int = UIManager.get_overlay_count()
	_panel._is_animating = true
	_panel.request_close()
	assert_eq(
		UIManager.get_overlay_count(), before + 1, "Escape mid-animation must keep the Escape route"
	)


func test_initialize_does_not_clear_dirty() -> void:
	_panel._on_weather_override_changed(0.3, "rain_intensity")
	_panel.initialize(LevelData.new())
	assert_true(_panel.is_dirty(), "Reopening a dirty drawer keeps the unsaved state")


## A prompt must not outlive the state it was asked about: e.g. the level clears,
## a new level loads and calls mark_clean(), and the stale "Discard changes"
## prompt from the OLD level must not survive to revert the NEW one.
func test_mark_clean_dismisses_open_close_prompt() -> void:
	_panel._on_weather_override_changed(0.3, "rain_intensity")
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
	# The controller answers cancel_requested with mark_clean() while the
	# dialog is still inside its own confirm handler; the dialog must be left
	# to close itself rather than being queue_freed mid-handler.
	_panel._on_weather_override_changed(0.3, "rain_intensity")
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


func test_badge_and_tooltip_follow_dirty_flag() -> void:
	_panel._mark_dirty()
	assert_true(_panel._tab_badge.visible, "Badge must be visible while dirty")
	assert_eq(_panel._tab_button.tooltip_text, LevelEditPanel.TAB_TOOLTIP_DIRTY)

	_panel.mark_clean()

	assert_false(_panel._tab_badge.visible, "Badge must hide once clean")
	assert_eq(_panel._tab_button.tooltip_text, LevelEditPanel.TAB_TOOLTIP_CLEAN)
