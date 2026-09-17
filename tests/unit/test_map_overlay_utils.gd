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


## The panel itself accepting mouse input (above) is not enough -- the checkbox that
## actually gets clicked has to consume the event too. Asserted separately because the
## F3 debug panel was recorded for weeks as unclickable through the validation bridge,
## and this is the property that claim would have needed in order to be true. It never
## was: the real cause was a caller-side canvas/window coordinate mismatch.
func test_checkboxes_stop_mouse_input() -> void:
	var result := MapOverlayUtils.create_checkbox_panel(["Foliage visible", "Tree shadows"])
	var checkboxes: Array[CheckBox] = result.checkboxes

	for checkbox in checkboxes:
		assert_eq(checkbox.mouse_filter, Control.MOUSE_FILTER_STOP)

	(result.panel as PanelContainer).free()


## Godot skips only the MOUSE_FILTER_IGNORE node itself and still hit-tests its
## children, so an IGNORE row container would not actually break the checkboxes -- but
## nothing in this panel wants to be click-through, and letting one turn up would make
## the next "the panel is unclickable" diagnosis plausible all over again.
func test_row_container_is_not_click_through() -> void:
	var result := MapOverlayUtils.create_checkbox_panel(["Foliage visible"])
	var panel: PanelContainer = result.panel
	var vbox: Control = panel.get_child(0)

	assert_ne(vbox.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	panel.free()


## The contrast case the checkbox panel must not drift into: label panels are
## display-only and deliberately let clicks through to the 3D map underneath.
func test_label_panel_stays_click_through() -> void:
	var result := MapOverlayUtils.create_label_panel()
	var panel: PanelContainer = result.panel

	assert_eq(panel.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq((result.label as Label).mouse_filter, Control.MOUSE_FILTER_IGNORE)

	panel.free()
