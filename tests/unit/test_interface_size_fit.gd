extends GutTest

## Every screen and sheet the UI tour visits (tools/render_jobs/jobs/ui_tour.json), and the
## avatar roster and help overlay, lays out on the 1280x720 virtual canvas: Interface size 150%
## gives that canvas on any 16:9 window, and no size gives a smaller one (InterfaceSize). Each
## opens in a 1280x720 SubViewport, as the root window's virtual canvas would hold it, its
## entrance tweens run to their end, and no visible control may lie outside the canvas. A
## ScrollContainer must fit, while what it holds may run past it: the player scrolls to that.
## The room screens (the session work replacing the host lobby) join this walk when they land.

const CANVAS := Vector2(1280.0, 720.0)
## Layout rounding.
const SLACK_PX := 0.5
## Longer than any entrance: the panel fade and the last staggered row.
const SETTLE_S := 3.0
const TITLE_SCENE := preload("res://scenes/states/title_screen/title_screen.tscn")
const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const NEW_MAP_SCENE := preload("res://scenes/states/authoring/new_map_dialog.tscn")
const CLIENT_SCENE := preload("res://scenes/states/lobby/lobby_client.tscn")
const PLAY_SCENE := preload("res://scenes/states/playing/gameplay_menu.tscn")
const PAUSE_SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")
const CONFIRM_SCENE := preload("res://scenes/ui/confirmation_dialog.tscn")
const TOASTS_SCENE := preload("res://scenes/ui/toast_container.tscn")
const HELP_SCENE := preload("res://scenes/ui/help_overlay.tscn")
const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}

var _host: SubViewport
var _scene: Node
var _old_scene: Node


## DragAndDrop3D and the builder's preview wait on a current scene, and a GUT run has none: a
## bare node under the root stands in for it and holds the canvas.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "InterfaceSizeFitScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_host = SubViewport.new()
	_host.size = Vector2i(CANVAS)
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_scene.add_child(_host)


func after_each() -> void:
	for node in _host.find_children("ColorRect", "ColorRect", true, false):
		UIManager.unregister_overlay(node as Control)
	get_tree().current_scene = _old_scene
	_scene.queue_free()


func test_title_screen_fits() -> void:
	var title := TITLE_SCENE.instantiate() as TitleScreen
	_host.add_child(title)
	await _assert_fits("title screen", title.quit_button)


## A resize while the rows lift in (a saved fullscreen applying just after the title appears
## changes the Interface size) still settles every row where the new layout puts it.
func test_title_screen_fits_after_a_resize_mid_entrance() -> void:
	_host.size = Vector2i(1920, 1080)
	var title := TITLE_SCENE.instantiate() as TitleScreen
	_host.add_child(title)
	await wait_process_frames(4)
	_host.size = Vector2i(CANVAS)
	await _assert_fits("title screen resized mid-entrance", title.quit_button)


func test_every_settings_section_fits() -> void:
	var menu := SETTINGS_SCENE.instantiate() as SettingsMenu
	_host.add_child(menu)
	for spec in SettingsMenu.SECTIONS:
		menu.section_rail.select(StringName(spec[0]))
		await _assert_fits("settings %s" % spec[0], menu.tab_container.get_current_tab_control())
	await _assert_fits("settings footer", menu.apply_button)


## The fields scroll between the header and the footer, and the scroll reaches all of them.
func test_new_map_dialog_fits() -> void:
	var dialog := NEW_MAP_SCENE.instantiate() as NewMapDialog
	_host.add_child(dialog)
	await _assert_fits("new map dialog", dialog.create_button)
	var scroll := dialog.landform_field.get_parent().get_parent() as ScrollContainer
	assert_not_null(scroll, "the fields sit in a scroll region")
	var fields := scroll.get_child(0) as Control
	assert_true(fields.size.y >= fields.get_combined_minimum_size().y - SLACK_PX, "all of them")


## At 1080p and 100% the dialog keeps its 600 sheet and three biome columns.
func test_new_map_dialog_keeps_its_sheet_at_1080p() -> void:
	_host.size = Vector2i(1920, 1080)
	var dialog := NEW_MAP_SCENE.instantiate() as NewMapDialog
	_host.add_child(dialog)
	await _assert_fits("new map dialog at 1080p", dialog.create_button, Vector2(1920, 1080))
	assert_almost_eq(_sheet(dialog).size.x, NewMapDialog.SHEET_WIDTH, 0.5)
	assert_eq(dialog.biome_field.tiles.columns, NewMapDialog.BIOME_COLUMNS)


## At 720p Auto (a 1371x771 canvas) the wide sheet shows every field without scrolling.
func test_new_map_dialog_needs_no_scroll_at_720p_auto() -> void:
	_host.size = Vector2i(1371, 771)
	var dialog := NEW_MAP_SCENE.instantiate() as NewMapDialog
	_host.add_child(dialog)
	await _assert_fits("new map dialog at 720p Auto", dialog.create_button, Vector2(1371, 771))
	var scroll := dialog.landform_field.get_parent().get_parent() as ScrollContainer
	var fields := scroll.get_child(0) as Control
	assert_almost_eq(_sheet(dialog).size.x, NewMapDialog.WIDE_SHEET_WIDTH, 0.5)
	assert_almost_eq(scroll.size.y, fields.get_combined_minimum_size().y, SLACK_PX)


func test_join_screen_fits() -> void:
	var lobby := CLIENT_SCENE.instantiate()
	lobby.connect_network = false
	_host.add_child(lobby)
	await _assert_fits("join screen", lobby.connect_button)


func test_authoring_drawer_fits() -> void:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var panel := AuthoringPanel.new()
	panel.theme = ThemeColors.glass_theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	for pane in [
		AuthoringPanel.TOOL_BIOME,
		AuthoringPanel.TOOL_THIN,
		AuthoringPanel.TOOL_PLACE,
		AuthoringPanel.TOOL_SCULPT,
		AuthoringPanel.TOOL_PAINT,
		AuthoringPanel.TOOL_WATER,
		AuthoringPanel.TOOL_BRIDGE,
	]:
		if pane != panel._rail.selected or not panel.is_open:
			panel._on_rail_item_pressed(pane)
		await _assert_fits("authoring drawer on %s" % pane, panel.tool_pane(pane))


func test_play_hud_visuals_drawer_and_asset_browser_fit() -> void:
	var play := PLAY_SCENE.instantiate()
	_host.add_child(play)
	var menu: Node = play.get_node("GameplayMenu")
	var drawer := menu.get("level_edit_panel") as LevelEditPanel
	drawer.initialize(LevelData.new())
	for pane in LevelEditPanel.PANE_IDS:
		if pane != drawer._rail.selected or not drawer.is_open:
			drawer._on_rail_item_pressed(pane)
		await _assert_fits("play HUD, visuals drawer on %s" % pane, drawer)
		assert_eq(drawer._rail.selected, pane)
	drawer.mark_clean()
	drawer.close()
	(menu.get("toggle_asset_browser_button") as Button).button_pressed = true
	var browser := menu.get_node("AssetBrowserContainer") as Control
	await _assert_fits("play HUD with the asset browser", browser)


func test_pause_menu_fits() -> void:
	var pause := PAUSE_SCENE.instantiate()
	_host.add_child(pause)
	await _assert_fits("pause menu", _sheet(pause))


func test_danger_confirmation_fits() -> void:
	var dialog := CONFIRM_SCENE.instantiate()
	_host.add_child(dialog)
	dialog.setup(
		"Remove token",
		'Remove "Marigold" from the board? Ctrl+Z undoes it.',
		"Remove",
		"Cancel",
		Callable(),
		Callable(),
		"Danger"
	)
	await _assert_fits("danger confirmation", dialog.confirm_button)


func test_toasts_fit() -> void:
	var toasts := TOASTS_SCENE.instantiate()
	_host.add_child(toasts)
	toasts.show_toast("Level saved", ToastContainer.ToastType.SUCCESS, 30.0)
	toasts.show_toast("Undone: Move token", ToastContainer.ToastType.INFO, 30.0)
	toasts.show_toast(
		"Maps are built offline. Leave the game to build or edit a map.",
		ToastContainer.ToastType.WARNING,
		30.0
	)
	toasts.show_toast("Could not load that level", ToastContainer.ToastType.ERROR, 30.0)
	await _assert_fits("four toasts", toasts.toast_vbox)
	assert_eq(toasts.toast_vbox.get_child_count(), 4)


## The builder's panel asks for PANEL_SHARE of the canvas (1101x619); its panes may need more
## height, never past WINDOW_MARGIN from the canvas edges.
func test_every_avatar_builder_pane_fits() -> void:
	var builder := AvatarBuilder.open_for_new(_host, RECIPE, "Plum")
	for spec in AvatarBuilder.PANES:
		builder._rail.select(spec[0])
		await _assert_fits("avatar builder on %s" % spec[2], builder.panel)
		assert_almost_eq(builder.panel.size.x, 1101.0, 1.0)
		assert_lte(builder.panel.size.y, CANVAS.y - 2.0 * AvatarBuilder.WINDOW_MARGIN, spec[2])


func test_avatar_roster_fits() -> void:
	var roster := AvatarRoster.open(_host)
	await _assert_fits("avatar roster", roster.panel)


func test_help_overlay_fits() -> void:
	var help := HELP_SCENE.instantiate()
	_host.add_child(help)
	await _assert_fits("help overlay", _sheet(help))


## An AnimatedCanvasLayerPanel's sheet.
func _sheet(layer: Node) -> Control:
	return layer.get_node("CenterContainer/PanelContainer") as Control


## Run the entrance tweens to their end, let the containers sort, and assert that every visible
## control under the host lies on the canvas, `subject` among them (so the walk saw the screen).
func _assert_fits(what: String, subject: Control, canvas: Vector2 = CANVAS) -> void:
	await wait_process_frames(2)
	for tween in get_tree().get_processed_tweens():
		tween.custom_step(SETTLE_S)
	await wait_process_frames(3)
	assert_true(is_instance_valid(subject) and subject.is_visible_in_tree(), "%s shows" % what)
	if is_instance_valid(subject):
		assert_gt(subject.size.x * subject.size.y, 0.0, "%s has a size" % what)
	var outside := PackedStringArray()
	_walk(_host, Rect2(Vector2.ZERO, canvas).grow(SLACK_PX), outside)
	assert_eq(outside.size(), 0, "%s lies on the %s canvas: %s" % [what, canvas, "; ".join(outside)])


func _walk(node: Node, canvas: Rect2, outside: PackedStringArray) -> void:
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return
	if node is Window:
		return
	# A closed drawer parks its panel past the edge on purpose; its rail is checked open.
	if node is DrawerContainer and not (node as DrawerContainer).is_open:
		return
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return
		var rect := control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
		if rect.size.x > 0.0 and rect.size.y > 0.0 and not canvas.encloses(rect):
			outside.append("%s at %s" % [_host.get_path_to(control), str(rect)])
		if control is ScrollContainer:
			return
	for child in node.get_children():
		_walk(child, canvas, outside)
