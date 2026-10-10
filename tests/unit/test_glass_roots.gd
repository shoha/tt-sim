extends GutTest

## Glass is the in-play material (docs/UI_TASTE.md C8): if play continues under a UI root, the
## root wears ThemeColors.glass_theme(); if it stops play it keeps the paper project default.
## This walks every scene under scenes/ whose root is a CanvasLayer and every script under
## scenes/ or utils/ that makes a CanvasLayer in code. Each must be sorted into the in-play or
## the stops-play list below, so a new UI layer fails here until someone decides which it is,
## and every in-play one must carry glass.

const IN_PLAY_SCENES := [
	"res://scenes/states/playing/gameplay_menu.tscn",
	"res://scenes/ui/disconnect_indicator.tscn",
	"res://scenes/ui/download_queue.tscn",
	"res://scenes/ui/input_hints.tscn",
	"res://scenes/ui/toast_container.tscn",
]

const STOPS_PLAY_SCENES := [
	"res://scenes/states/authoring/new_map_dialog.tscn",
	"res://scenes/states/paused/pause_overlay.tscn",
	"res://scenes/states/playing/avatar_builder.tscn",
	"res://scenes/states/title_screen/title_screen.tscn",
	"res://scenes/ui/add_pack_dialog.tscn",
	"res://scenes/ui/app_menu.tscn",
	"res://scenes/ui/avatar_roster.tscn",
	"res://scenes/ui/confirmation_dialog.tscn",
	"res://scenes/ui/help_overlay.tscn",
	"res://scenes/ui/level_picker_dialog.tscn",
	"res://scenes/ui/loading_overlay.tscn",
	"res://scenes/ui/player_selection_dialog.tscn",
	"res://scenes/ui/settings_menu.tscn",
	"res://scenes/ui/transition_overlay.tscn",
	"res://scenes/ui/update_dialog.tscn",
]

## Scripts that make a CanvasLayer over the live table, each with the text that puts glass on
## what it adds to the layer. "" when the layer holds nothing themed of its own: the drag
## ghost is one icon, and GameMap's perf overlay layer only stacks MapOverlayUtils panels.
const IN_PLAY_SCRIPTS := {
	"res://scenes/states/authoring/authoring_controller.gd": "ThemeColors.glass_theme()",
	"res://scenes/states/playing/drag_place_controller.gd": "",
	"res://scenes/states/playing/game_map.gd": "",
	"res://scenes/states/playing/volume_overlay.gd": "MapOverlayUtils.create_label_panel",
	"res://utils/map_overlay_utils.gd": "ThemeColors.glass_theme()",
}

const STOPS_PLAY_SCRIPTS := ["res://scenes/ui/app_menu_controller.gd"]


func test_paper_is_the_project_default() -> void:
	assert_eq(ProjectSettings.get_setting("gui/theme/custom"), ThemeColors.PAPER_THEME_PATH)


func test_every_canvas_layer_scene_is_sorted() -> void:
	for path in _files("res://scenes", ".tscn"):
		if not _root_is_canvas_layer(path):
			continue
		var sorted := IN_PLAY_SCENES.has(path) or STOPS_PLAY_SCENES.has(path)
		assert_true(sorted, "%s: add it to IN_PLAY_SCENES (glass) or STOPS_PLAY_SCENES" % path)
	for path in IN_PLAY_SCENES + STOPS_PLAY_SCENES:
		assert_true(ResourceLoader.exists(path), "%s still exists" % path)


func test_in_play_scenes_wear_glass() -> void:
	for path: String in IN_PLAY_SCENES:
		var root := (load(path) as PackedScene).instantiate()
		autofree(root)
		var controls := root.get_children().filter(func(child: Node) -> bool: return child is Control)
		assert_gt(controls.size(), 0, "%s has a Control under its layer" % path)
		for control: Control in controls:
			assert_true(_is_glass(control.theme), "%s: %s wears the glass theme" % [path, control.name])


func test_every_script_canvas_layer_is_sorted_and_in_play_ones_wear_glass() -> void:
	for path in _files("res://scenes", ".gd") + _files("res://utils", ".gd"):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("CanvasLayer.new()"):
			continue
		var sorted := IN_PLAY_SCRIPTS.has(path) or STOPS_PLAY_SCRIPTS.has(path)
		assert_true(sorted, "%s makes a CanvasLayer: sort it into IN_PLAY_SCRIPTS or STOPS" % path)
		var marker: String = IN_PLAY_SCRIPTS.get(path, "")
		if not marker.is_empty():
			assert_true(text.contains(marker), "%s puts glass on its layer (%s)" % [path, marker])


func test_overlay_panels_wear_glass() -> void:
	var label := MapOverlayUtils.create_label_panel()
	var checks := MapOverlayUtils.create_checkbox_panel(PackedStringArray(["a"]))
	autofree(label.panel)
	autofree(checks.panel)
	assert_true(_is_glass((label.panel as Control).theme))
	assert_true(_is_glass((checks.panel as Control).theme))


func test_glass_reaches_controls_and_popups_under_a_root() -> void:
	var root := Control.new()
	root.theme = ThemeColors.glass_theme()
	add_child_autofree(root)
	var label := Label.new()
	var option := OptionButton.new()
	option.add_item("one")
	root.add_child(label)
	root.add_child(option)
	assert_eq(label.get_theme_color("font_color"), ThemeColors.CHALK, "glass text is chalk")
	var popup := option.get_popup()
	assert_eq(popup.get_theme_color("font_color"), ThemeColors.CHALK, "the dropdown is glass too")
	var outside := Label.new()
	add_child_autofree(outside)
	assert_eq(outside.get_theme_color("font_color"), ThemeColors.INK, "paper text is ink")


func _is_glass(theme: Theme) -> bool:
	return theme != null and theme.resource_path == ThemeColors.GLASS_THEME_PATH


func _root_is_canvas_layer(path: String) -> bool:
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("[node "):
			return line.contains('type="CanvasLayer"')
	return false


func _files(dir_path: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(suffix):
			out.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		out.append_array(_files(dir_path.path_join(sub), suffix))
	return out
