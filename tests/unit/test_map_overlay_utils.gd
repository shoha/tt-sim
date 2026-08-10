extends GutTest

## Unit tests for MapOverlayUtils.create_checkbox_panel (utils/map_overlay_utils.gd).


func test_creates_one_checkbox_per_label_in_order() -> void:
	var result := MapOverlayUtils.create_checkbox_panel(["Foliage visible", "Tree shadows"])
	var checkboxes: Array[CheckBox] = result.checkboxes

	assert_eq(checkboxes.size(), 2)
	assert_eq(checkboxes[0].text, "Foliage visible")
	assert_eq(checkboxes[1].text, "Tree shadows")

	(result.panel as PanelContainer).free()


func test_panel_accepts_mouse_input() -> void:
	# Unlike create_label_panel (display-only, MOUSE_FILTER_IGNORE), this panel's
	# checkboxes must be clickable.
	var result := MapOverlayUtils.create_checkbox_panel(["Foliage visible"])
	var panel: PanelContainer = result.panel

	assert_ne(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	panel.free()


func test_panel_starts_hidden() -> void:
	var result := MapOverlayUtils.create_checkbox_panel(["Foliage visible"])
	var panel: PanelContainer = result.panel

	assert_false(panel.visible)

	panel.free()
