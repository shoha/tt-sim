extends GutTest

## IconButton resolves icons by Tabler name, swaps to the active variation
## (preferring the filled variant), keeps its badge in sync, and starts a hover
## tween on mouse enter. Motion end states need frames, so only tween liveness
## is asserted.


func _make(icon: String) -> IconButton:
	var button := IconButton.new()
	button.icon_name = icon
	add_child_autofree(button)
	return button


func test_known_icon_loads_texture() -> void:
	var button := _make("sun")
	assert_not_null(button.icon)


func test_missing_icon_leaves_button_without_texture() -> void:
	var button := _make("no-such-icon")
	assert_null(button.icon)
	# IconButton's push_warning for the missing icon is expected here -- mark it
	# handled so GUT doesn't fail the test on an "unexpected" engine error.
	for err in get_errors():
		err.handled = true


func test_active_switches_variation() -> void:
	var button := _make("haze")
	assert_eq(button.theme_type_variation, &"IconButton")
	button.active = true
	assert_eq(button.theme_type_variation, &"IconButtonActive")
	button.active = false
	assert_eq(button.theme_type_variation, &"IconButton")


func test_active_prefers_filled_variant_when_present() -> void:
	var button := _make("sun")
	button.active = true
	assert_eq(button.icon.resource_path, IconButton.ICON_DIR + "sun-filled.svg")
	button.active = false
	assert_eq(button.icon.resource_path, IconButton.ICON_DIR + "sun.svg")


func test_active_without_filled_variant_keeps_outline() -> void:
	var button := _make("haze")
	button.active = true
	assert_eq(button.icon.resource_path, IconButton.ICON_DIR + "haze.svg")


func test_badge_follows_property() -> void:
	var button := _make("sun")
	assert_false(button._badge.visible)
	button.badge = true
	assert_true(button._badge.visible)


func test_hover_starts_scale_tween() -> void:
	var button := _make("sun")
	button._on_mouse_entered()
	assert_true(button._tween != null and button._tween.is_valid())


func test_disabled_button_does_not_animate() -> void:
	var button := _make("sun")
	button.disabled = true
	button._on_mouse_entered()
	assert_true(button._tween == null or not button._tween.is_valid())
	assert_eq(button.offset_transform_scale, Vector2.ONE)
