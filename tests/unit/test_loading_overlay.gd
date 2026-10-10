extends GutTest

## The loading and transition overlays on the Painted Table (docs/UI_TASTE.md C4, C8, W4, M5,
## M6, G10): a map load is a paper sheet on the backdrop sky with a determinate bar, a wait
## over a live screen is the same sheet over the shared scrim with a gliding bar, and the
## transition overlay covers the screen with the sky rather than a dark fill.

const LOADING_SCENE := preload("res://scenes/ui/loading_overlay.tscn")
const TRANSITION_SCENE := preload("res://scenes/ui/transition_overlay.tscn")

var _overlay: LoadingOverlay


func before_each() -> void:
	_overlay = LOADING_SCENE.instantiate()
	add_child_autofree(_overlay)


func test_hidden_until_shown() -> void:
	assert_false(_overlay.visible)
	assert_false(_overlay.is_gliding(), "no loop while hidden (M6)")


func test_a_map_load_lays_the_sky_with_a_determinate_bar() -> void:
	_overlay.show_loading("Setting out Mossy Hollow")
	var sky := _overlay.get_node("%Sky") as ColorRect
	assert_true(_overlay.visible)
	assert_true(sky.visible, "nothing behind a map load is worth seeing: the sky covers it")
	assert_eq(sky.modulate.a, 1.0, "the sky is up at once, as the title's and the room's is")
	assert_false((_overlay.get_node("%Scrim") as Control).visible)
	assert_true(_overlay.progress_bar.visible)
	assert_false(_overlay.is_indeterminate(), "known progress shows as a fill")
	assert_false(_overlay.is_gliding(), "no second segment beside the real fill")
	assert_eq(_overlay.loading_label.text, "Setting out Mossy Hollow")


func test_a_wait_over_a_live_screen_scrims_it_and_glides() -> void:
	_overlay.show_indeterminate("Opening a room...")
	var scrim := _overlay.get_node("%Scrim") as ColorRect
	assert_true(scrim.visible)
	assert_true(scrim is Scrim, "the shared scrim, not a dark fill")
	assert_false((_overlay.get_node("%Sky") as Control).visible, "the title stays behind")
	assert_true(_overlay.is_indeterminate())
	assert_true(_overlay.is_gliding(), "a wait with no progress still moves")
	assert_false(_overlay.status_label.visible, "an empty caption leaves no gap")


func test_a_map_load_after_a_wait_takes_its_own_bar_back() -> void:
	_overlay.show_indeterminate("Opening a room...")
	_overlay.show_loading("Setting out Mossy Hollow")
	assert_false(_overlay.is_indeterminate())
	assert_false(_overlay.is_gliding())
	assert_eq(_overlay.progress_bar.value, 0.0)
	assert_true((_overlay.get_node("%Sky") as Control).visible)


func test_progress_reaches_its_value_and_names_the_step() -> void:
	_overlay.show_loading()
	_overlay.set_progress(0.6, "Spawning tokens...")
	assert_eq(_overlay.status_label.text, "Spawning tokens...")
	assert_true(_overlay.status_label.visible)
	await wait_seconds(LoadingOverlay.PROGRESS_S + 0.1)
	assert_almost_eq(_overlay.progress_bar.value, 0.6, 0.001)


func test_hiding_stops_the_glide_and_says_so() -> void:
	_overlay.show_indeterminate("Opening a room...")
	watch_signals(_overlay)
	await _overlay.hide_loading()
	assert_false(_overlay.visible)
	assert_false(_overlay.is_gliding(), "loops stop when hidden (M6)")
	assert_signal_emitted(_overlay, "loading_complete")


## Paper text on the paper sheet: the Title and Caption roles over the sheet, never the
## paper theme's ink over a dark fill (the regression this overlay had).
func test_the_text_is_ink_on_a_paper_sheet() -> void:
	_overlay.show_loading()
	var sheet := _overlay.get_node("CenterContainer/Sheet") as PanelContainer
	var panel := sheet.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_eq(panel.bg_color, ThemeColors.PAPER)
	assert_eq(_overlay.loading_label.get_theme_color(&"font_color"), ThemeColors.INK)
	assert_eq(_overlay.status_label.get_theme_color(&"font_color"), ThemeColors.INK_SOFT)
	var sky := _overlay.get_node("%Sky") as ColorRect
	assert_eq(sky.color, ThemeColors.PAPER_ROLES[ThemeColors.BACKDROP])


func test_a_map_load_names_its_map() -> void:
	var level := LevelData.new()
	level.level_name = "Oak's Lab"
	assert_eq(LoadingOverlay.setting_out_text(level), "Setting out Oak's Lab")
	assert_eq(LoadingOverlay.setting_out_text(null), LoadingOverlay.SETTING_OUT_ANY)
	level.level_name = "  "
	assert_eq(LoadingOverlay.setting_out_text(level), LoadingOverlay.SETTING_OUT_ANY)


func test_a_transition_covers_with_the_sky() -> void:
	var transition: TransitionOverlay = TRANSITION_SCENE.instantiate()
	add_child_autofree(transition)
	var sky: Color = ThemeColors.PAPER_ROLES[ThemeColors.BACKDROP]
	assert_eq(transition.fade_color, sky)
	assert_eq(transition.color_rect.color, sky)
