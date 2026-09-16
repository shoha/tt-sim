extends GutTest

## UiActions builds the two menu action shapes: one tall accent primary with an
## optional caption underneath, and quiet Secondary rows. Both park a hidden
## subtitle label after the button for screens that name their selection.

var _box: VBoxContainer


func before_each() -> void:
	_box = VBoxContainer.new()
	add_child_autofree(_box)


func test_primary_is_an_accent_animated_button_with_caption_and_subtitle() -> void:
	var button := UiActions.primary("Host Game", "network", "Start a table", _box)
	assert_true(button is AnimatedButton, "primary actions animate their press")
	assert_eq(button.theme_type_variation, &"", "the primary keeps the default accent variant")
	assert_eq(button.custom_minimum_size.y, float(UiActions.PRIMARY_HEIGHT))
	assert_eq(button.alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_not_null(button.icon)
	var caption := _box.get_child(1) as Label
	assert_eq(caption.text, "Start a table")
	assert_eq(caption.theme_type_variation, &"Caption")
	var subtitle := UiActions.subtitle_of(button)
	assert_false(subtitle.visible, "the subtitle stays hidden until a screen fills it in")


func test_primary_without_a_caption_adds_only_the_subtitle() -> void:
	var button := UiActions.primary("Resume", "map", "", _box)
	assert_eq(_box.get_child_count(), 2)
	assert_same(_box.get_child(1), UiActions.subtitle_of(button))


func test_secondary_is_quiet_and_shorter() -> void:
	var button := UiActions.secondary("Settings", "settings", _box)
	assert_eq(button.theme_type_variation, &"Secondary")
	assert_eq(button.custom_minimum_size.y, float(UiActions.SECONDARY_HEIGHT))
	assert_eq(button.alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_not_null(button.icon)
	assert_false(UiActions.subtitle_of(button).visible)


func test_spacer_reserves_height_and_takes_no_input() -> void:
	var spacer := UiActions.spacer(12, _box)
	assert_eq(spacer.custom_minimum_size.y, 12.0)
	assert_eq(spacer.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_same(_box.get_child(0), spacer)
