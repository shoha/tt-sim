extends GutTest

## The Settings menu drives its TabContainer from a labelled IconRail; the
## native tab bar is hidden and the Graphics tab keeps its advanced rows
## reachable through unique names after the Foldout reparents them.

const MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _menu: SettingsMenu


func before_each() -> void:
	_menu = MENU_SCENE.instantiate()
	add_child_autofree(_menu)


func test_rail_has_every_section_and_tab_bar_is_hidden() -> void:
	for spec in SettingsMenu.SECTIONS:
		assert_true(_menu.section_rail.has_item(StringName(spec[0])), spec[0])
	assert_false(_menu.tab_container.tabs_visible)


func test_rail_selection_switches_tab() -> void:
	_menu.section_rail.select(&"Grid")
	var grid_index: int = _menu.tab_container.get_node("Grid").get_index()
	assert_eq(_menu.tab_container.current_tab, grid_index)


## The rail selects its first section in _ready, before it has laid out its
## items; the underline must still end up under that section.
func test_rail_underline_sits_under_the_selected_section() -> void:
	await wait_process_frames(3)
	var rail := _menu.section_rail
	assert_false(rail.selected.is_empty())
	assert_gt(rail._indicator_pos, 0.0)
	assert_almost_eq(rail._indicator_pos, rail._indicator_target(), 0.5)


func test_advanced_graphics_rows_keep_unique_names() -> void:
	assert_not_null(_menu.foliage_density_slider)
	assert_not_null(_menu.renderer_method_option)
	assert_true(
		_menu.foliage_density_slider.get_parent().get_parent().get_parent().get_parent() is Foldout
	)
