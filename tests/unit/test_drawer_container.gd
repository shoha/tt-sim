extends GutTest

## DrawerContainer rail mode: rail_items replaces the single tab with an
## IconRail; clicking an item opens the drawer on that pane, clicking the
## active item closes it (subject to the close veto), and programmatic open()
## picks the last pane or the first. Slide tweens need frames, so tests set
## is_revealed and clear _is_animating by hand.


class TabDrawer:
	extends DrawerContainer

	func _on_ready() -> void:
		tab_text = "Tab"


class EagerTabDrawer:
	extends DrawerContainer

	func _on_ready() -> void:
		tab_text = "Tab"
		set_tab_tooltip("Eager tooltip")
		set_tab_badge(true)


class RailDrawer:
	extends DrawerContainer

	func _on_ready() -> void:
		edge = DrawerEdge.RIGHT
		tab_width = 44.0
		rail_items = [
			{"id": &"a", "icon": "sun", "tooltip": "A"},
			{"id": &"b", "icon": "haze", "tooltip": "B"},
		]


class VetoRailDrawer:
	extends RailDrawer

	func _can_close_from_tab() -> bool:
		return false


func _mount(drawer: DrawerContainer) -> DrawerContainer:
	var host := Control.new()
	host.size = Vector2(1920, 1080)
	add_child_autofree(host)
	host.add_child(drawer)
	drawer.is_revealed = true
	return drawer


func test_single_tab_mode_builds_a_button_and_no_rail() -> void:
	var drawer := _mount(TabDrawer.new())
	assert_not_null(drawer._tab_button)
	assert_null(drawer._rail)
	assert_eq(drawer._tab_control, drawer._tab_button)


func test_tooltip_and_badge_set_in_on_ready_survive_tab_build() -> void:
	var drawer := _mount(EagerTabDrawer.new())
	assert_eq(drawer._tab_button.tooltip_text, "Eager tooltip")
	assert_true(drawer._tab_badge.visible)


func test_rail_mode_builds_rail_items_and_no_button() -> void:
	var drawer := _mount(RailDrawer.new())
	assert_null(drawer._tab_button)
	assert_true(drawer._rail.has_item(&"a"))
	assert_true(drawer._rail.has_item(&"b"))
	assert_eq(drawer._tab_control, drawer._rail_panel)
	assert_false(drawer._rail.auto_select)


func test_rail_press_when_closed_opens_on_that_pane() -> void:
	var drawer := _mount(RailDrawer.new())
	watch_signals(drawer)
	drawer._on_rail_item_pressed(&"b")
	assert_true(drawer.is_open)
	assert_eq(drawer._rail.selected, &"b")
	assert_signal_emitted_with_parameters(drawer, "pane_requested", [&"b"])
	assert_signal_emit_count(drawer, "pane_requested", 1)


func test_rail_press_on_active_item_closes_and_remembers() -> void:
	var drawer := _mount(RailDrawer.new())
	drawer._on_rail_item_pressed(&"b")
	drawer._is_animating = false
	drawer._on_rail_item_pressed(&"b")
	assert_false(drawer.is_open)
	assert_eq(drawer._rail.selected, &"")
	assert_eq(drawer._last_rail_id, &"b")


func test_rail_press_on_other_item_switches_pane_without_closing() -> void:
	var drawer := _mount(RailDrawer.new())
	drawer._on_rail_item_pressed(&"a")
	drawer._is_animating = false
	watch_signals(drawer)
	drawer._on_rail_item_pressed(&"b")
	assert_true(drawer.is_open)
	assert_eq(drawer._rail.selected, &"b")
	assert_signal_emitted_with_parameters(drawer, "pane_requested", [&"b"])


func test_veto_keeps_drawer_open() -> void:
	var drawer := _mount(VetoRailDrawer.new())
	drawer._on_rail_item_pressed(&"a")
	drawer._is_animating = false
	drawer._on_rail_item_pressed(&"a")
	assert_true(drawer.is_open)


func test_programmatic_open_picks_first_then_last_pane() -> void:
	var drawer := _mount(RailDrawer.new())
	watch_signals(drawer)
	drawer.open()
	assert_signal_emitted_with_parameters(drawer, "pane_requested", [&"a"])
	drawer._is_animating = false
	drawer._rail.select(&"b")
	drawer.close()
	drawer._is_animating = false
	drawer.open()
	assert_signal_emitted_with_parameters(drawer, "pane_requested", [&"b"], 1)


func test_rail_badges() -> void:
	var drawer := _mount(RailDrawer.new())
	drawer.set_rail_badge(&"a", true)
	assert_true(drawer._rail._buttons[&"a"].badge)
	drawer.set_tab_badge(false)
	assert_false(drawer._rail._buttons[&"a"].badge)
