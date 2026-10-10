extends GutTest

## Interface size (InterfaceSize): the Auto curve at common window heights, its clamp, the
## caption floor it keeps (UI_TASTE T2), fixed sizes replacing Auto, the [ui] setting's round
## trip, the Settings > Graphics row, and the board's render scale.

const TEMP_PATH := "user://test_interface_size.cfg"
const MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")


func before_each() -> void:
	UiPreferences.settings_path = TEMP_PATH
	_remove_temp()


func after_each() -> void:
	_remove_temp()
	UiPreferences.settings_path = Paths.SETTINGS_PATH


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


## A 16:9 window `height` px tall.
func _window(height: float) -> Vector2:
	return Vector2(height * 16.0 / 9.0, height)


func test_auto_curve_at_common_heights() -> void:
	assert_almost_eq(InterfaceSize.auto_factor(_window(720)), 1.40, 0.001, "720p")
	assert_almost_eq(InterfaceSize.auto_factor(_window(900)), 1.15, 0.001, "900p")
	assert_almost_eq(InterfaceSize.auto_factor(_window(1080)), 1.0, 0.001, "1080p")
	assert_almost_eq(InterfaceSize.auto_factor(_window(1440)), 1.0, 0.001, "1440p")
	assert_almost_eq(InterfaceSize.auto_factor(_window(2160)), 1.0, 0.001, "2160p")


## 720p Auto is a 1371x771 virtual canvas, as the theme probe measured.
func test_auto_canvas_at_720p() -> void:
	var window := _window(720)
	var factor := InterfaceSize.auto_factor(window)
	var canvas := window / (InterfaceSize.window_scale(window) * factor)
	assert_almost_eq(canvas.x, 1371.4, 0.1)
	assert_almost_eq(canvas.y, 771.4, 0.1)


func test_auto_clamps_to_its_range() -> void:
	assert_almost_eq(InterfaceSize.auto_factor(_window(480)), InterfaceSize.MAX_FACTOR, 0.001)
	assert_almost_eq(InterfaceSize.auto_factor(_window(240)), InterfaceSize.MAX_FACTOR, 0.001)
	assert_almost_eq(InterfaceSize.auto_factor(_window(4320)), InterfaceSize.MIN_FACTOR, 0.001)
	assert_almost_eq(InterfaceSize.auto_factor(Vector2.ZERO), InterfaceSize.MIN_FACTOR, 0.001)


## Every Auto factor is a whole 0.05 step.
func test_auto_snaps_to_steps() -> void:
	for height in range(400, 1200, 7):
		var steps := InterfaceSize.auto_factor(_window(height)) / InterfaceSize.STEP
		assert_almost_eq(steps, roundf(steps), 0.0001, "%d px" % height)


## T2: a 14 px caption draws at 13 physical px or more from the smallest window Auto can fully
## serve (669 px tall, at 1.5) up, and Auto takes the least step that does.
func test_auto_keeps_the_caption_floor() -> void:
	for height in range(670, 2200, 5):
		var window := _window(height)
		var factor := InterfaceSize.auto_factor(window)
		var caption := InterfaceSize.physical_px(InterfaceSize.CAPTION_PX, factor, window)
		assert_true(caption >= InterfaceSize.CAPTION_FLOOR_PX - 0.001, "%d px: %.2f" % [height, caption])
		if factor > InterfaceSize.MIN_FACTOR:
			var one_less := factor - InterfaceSize.STEP
			var smaller := InterfaceSize.physical_px(InterfaceSize.CAPTION_PX, one_less, window)
			assert_true(smaller < InterfaceSize.CAPTION_FLOOR_PX, "%d px is the least" % height)


## A window narrower than 16:9 is scaled by its width, so Auto reads the width there.
func test_auto_reads_the_limiting_axis() -> void:
	assert_almost_eq(InterfaceSize.auto_factor(Vector2(1280, 1024)), 1.40, 0.001, "5:4 by width")
	assert_almost_eq(InterfaceSize.auto_factor(Vector2(1720, 720)), 1.40, 0.001, "ultrawide")


## A fixed size replaces Auto, and 150% is a 1280x720 canvas on any 16:9 window.
func test_fixed_sizes_replace_auto() -> void:
	for height in [720.0, 1080.0, 2160.0]:
		var window := _window(height)
		assert_almost_eq(InterfaceSize.factor_for(90, window), 0.9, 0.001)
		var factor := InterfaceSize.factor_for(150, window)
		var canvas := window / (InterfaceSize.window_scale(window) * factor)
		assert_almost_eq(canvas.x, 1280.0, 0.5, "%d px" % height)
		assert_almost_eq(canvas.y, 720.0, 0.5, "%d px" % height)
	assert_almost_eq(
		InterfaceSize.factor_for(InterfaceSize.AUTO, _window(720)), 1.40, 0.001, "Auto"
	)


func test_unknown_choices_fall_back_to_auto() -> void:
	assert_eq(InterfaceSize.sanitize(125), InterfaceSize.AUTO)
	assert_eq(InterfaceSize.sanitize(400), InterfaceSize.AUTO)
	assert_eq(InterfaceSize.sanitize(140), 140)
	assert_almost_eq(InterfaceSize.factor_for(400, _window(1080)), 1.0, 0.001)


func test_labels() -> void:
	assert_eq(InterfaceSize.label_for(InterfaceSize.AUTO, _window(720)), "Auto (recommended)")
	assert_eq(InterfaceSize.label_for(InterfaceSize.AUTO, _window(1080)), "Auto (recommended)")
	# A fixed size is named against Auto on this window, so 100% at 720p is not "normal".
	assert_eq(InterfaceSize.label_for(100, _window(720)), "100% (smaller than Auto)")
	assert_eq(InterfaceSize.label_for(140, _window(720)), "140% (same as Auto)")
	assert_eq(InterfaceSize.label_for(150, _window(720)), "150% (larger than Auto)")
	assert_eq(InterfaceSize.label_for(100, _window(1080)), "100% (same as Auto)")
	assert_eq(InterfaceSize.label_for(90, _window(1080)), "90% (smaller than Auto)")


func test_setting_defaults_to_auto_and_round_trips() -> void:
	assert_eq(UiPreferences.load_interface_size(), InterfaceSize.AUTO)
	var config := ConfigFile.new()
	config.set_value("audio", "master", 0.5)
	config.save(TEMP_PATH)
	UiPreferences.save_interface_size(130)
	assert_eq(UiPreferences.load_interface_size(), 130)
	var reread := ConfigFile.new()
	reread.load(TEMP_PATH)
	assert_eq(reread.get_value("audio", "master", -1.0), 0.5, "other sections kept")
	reread.set_value(UiPreferences.SECTION, UiPreferences.KEY_INTERFACE_SIZE, 77)
	reread.save(TEMP_PATH)
	assert_eq(UiPreferences.load_interface_size(), InterfaceSize.AUTO, "a stale value is Auto")


## Graphics holds the row, in the shared label column, with every choice and the saved one.
func test_settings_row_lists_every_choice() -> void:
	var menu := MENU_SCENE.instantiate() as SettingsMenu
	add_child_autofree(menu)
	var option := menu.interface_size_option
	assert_eq(option.item_count, InterfaceSize.CHOICES.size())
	for i in range(option.item_count):
		assert_eq(option.get_item_id(i), InterfaceSize.CHOICES[i])
	assert_true(option.get_item_text(0).begins_with("Auto ("))
	assert_eq(option.get_selected_id(), UIManager.get_interface_size())
	var row := option.get_parent() as HBoxContainer
	assert_eq(row.theme_type_variation, &"PropertyRow")
	assert_eq((row.get_child(0) as Label).custom_minimum_size.x, PropertyRow.SHEET_LABEL_WIDTH)
	assert_true(row.get_parent().get_path().get_concatenated_names().contains("Graphics"))
	UIManager.unregister_overlay(menu.get_node("ColorRect") as Control)


## Picking a size saves it at once (no Apply), and Reset puts Auto back.
func test_picking_a_size_saves_it_and_reset_restores_auto() -> void:
	var before := UIManager.get_interface_size()
	var menu := MENU_SCENE.instantiate() as SettingsMenu
	add_child_autofree(menu)
	var option := menu.interface_size_option
	var index := option.get_item_index(120)
	option.select(index)
	option.item_selected.emit(index)
	assert_eq(UIManager.get_interface_size(), 120)
	assert_eq(UiPreferences.load_interface_size(), 120)
	menu._on_reset_pressed()
	assert_eq(UIManager.get_interface_size(), InterfaceSize.AUTO)
	assert_eq(UiPreferences.load_interface_size(), InterfaceSize.AUTO)
	assert_eq(option.get_selected_id(), InterfaceSize.AUTO)
	UIManager.set("_interface_size", before)
	UIManager.unregister_overlay(menu.get_node("ColorRect") as Control)


## The board renders at its 100% size: the 3D scale undoes the window's content scale.
func test_world_render_scale_follows_the_content_scale() -> void:
	var window := Window.new()
	window.visible = false
	add_child_autofree(window)
	window.content_scale_factor = 1.4
	assert_almost_eq(InterfaceSize.world_render_scale(window), 1.4, 0.001)
	assert_almost_eq(InterfaceSize.world_render_scale(null), 1.0, 0.001)


## apply() sets a fixed size on a window and leaves an equal factor alone.
func test_apply_sets_the_content_scale() -> void:
	var window := Window.new()
	window.visible = false
	add_child_autofree(window)
	window.content_scale_size = Vector2i(1920, 1080)
	assert_almost_eq(InterfaceSize.apply(window, 150), 1.5, 0.001)
	assert_almost_eq(window.content_scale_factor, 1.5, 0.001)
	assert_almost_eq(InterfaceSize.apply(window, 90), 0.9, 0.001)
	assert_almost_eq(window.content_scale_factor, 0.9, 0.001)
