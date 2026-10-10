extends GutTest

## Every screen and sheet the UI tour visits (tools/render_jobs/jobs/ui_tour.json), and the
## avatar roster and help overlay, lays out on the 1280x720 virtual canvas: Interface size 150%
## gives that canvas on any 16:9 window, and no size gives a smaller one (InterfaceSize). Each
## opens in a 1280x720 SubViewport, as the root window's virtual canvas would hold it, its
## entrance tweens run to their end, and no visible control may lie outside the canvas. A
## ScrollContainer must fit, while what it holds may run past it: the player scrolls to that.
## The room (RoomScreen) and the room drawer over a table are walked from a sample summary.
##
## On the canvas is not enough where panels overlap: the input hint bar must never lie under
## an open drawer (_assert_uncovered), and the title's column must stay clear of the version
## label at the bottom of the canvas, on 1366x768 at Auto (1.35, an 800 px canvas) too.

const CANVAS := Vector2(1280.0, 720.0)
## The canvas of 720p at Auto (1.40) and of 1366x768 at Auto (1.35).
const CANVAS_720P_AUTO := Vector2i(1371, 771)
const CANVAS_768P_AUTO := Vector2i(1423, 800)
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
const HINTS_SCENE := preload("res://scenes/ui/input_hints.tscn")
## A saved level, so the title shows every caption it can (Host's "with ...", Play Solo's).
const LEVEL := {
	"path": "user://x/_fit_mossy/",
	"folder": "_fit_mossy",
	"is_folder_based": true,
	"name": "Mossy Hollow",
	"token_count": 3,
	"modified_at": 1,
	"environment_preset": "",
	"thumbnail": "",
}
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
	var title := _title()
	await _assert_fits("title screen", title.quit_button)
	_assert_clear_of_version_label("title screen", title)


## A resize while the rows lift in (a saved fullscreen applying just after the title appears
## changes the Interface size) still settles every row where the new layout puts it.
func test_title_screen_fits_after_a_resize_mid_entrance() -> void:
	_host.size = Vector2i(1920, 1080)
	var title := _title()
	await wait_process_frames(4)
	_host.size = Vector2i(CANVAS)
	await _assert_fits("title screen resized mid-entrance", title.quit_button)
	_assert_clear_of_version_label("title screen resized mid-entrance", title)


## The column is measured against its canvas, not switched at a threshold: on 1366x768 at Auto
## (exactly 800 px tall), 720p at Auto and 1080p it fits above the version label, and every
## caption sits 4 px under its own button and 12 px above the next control.
func test_title_column_fits_by_measurement() -> void:
	for canvas in [CANVAS_768P_AUTO, CANVAS_720P_AUTO, Vector2i(1920, 1080)]:
		_host.size = canvas
		var title := _title()
		var what := "title screen on a %s canvas" % str(canvas)
		await _assert_fits(what, title.quit_button, Vector2(canvas))
		_assert_clear_of_version_label(what, title)
		var caption := _next_shown(title.host_button)
		assert_almost_eq(_gap(title.host_button, caption), 4.0, SLACK_PX, "%s: caption" % what)
		var subtitle := _next_shown(caption)
		assert_eq(subtitle, title.host_subtitle, "%s: with Mossy Hollow under it" % what)
		assert_almost_eq(_gap(subtitle, title.join_button), 12.0, SLACK_PX, "%s: Join" % what)
		var play_caption := _next_shown(title.play_button)
		assert_eq(play_caption, title.play_subtitle)
		assert_almost_eq(_gap(play_caption, title.editor_button), 12.0, SLACK_PX, what)
		var stack := _gap(title.editor_button, title.build_map_button)
		assert_true(stack >= TitleScreen.STACK_GAP - SLACK_PX, "%s: stack %.1f" % [what, stack])
		title.free()


## At 1080p the column has room for its roomy stack.
func test_title_column_is_roomy_at_1080p() -> void:
	_host.size = Vector2i(1920, 1080)
	var title := _title()
	await _assert_fits("title at 1080p", title.quit_button, Vector2(1920, 1080))
	var stack := _gap(title.editor_button, title.build_map_button)
	assert_almost_eq(stack, TitleScreen.STACK_GAP_ROOMY, SLACK_PX)


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


## On either sheet the three fields share one track: a size tile is a biome tile's width and
## starts at the same left edge, and on the 960 sheet the landforms fill one line of it.
func test_new_map_fields_share_one_track() -> void:
	for canvas in [CANVAS_720P_AUTO, Vector2i(1920, 1080)]:
		_host.size = canvas
		var dialog := NEW_MAP_SCENE.instantiate() as NewMapDialog
		_host.add_child(dialog)
		var what := "new map dialog on %s" % str(canvas)
		await _assert_fits(what, dialog.create_button, Vector2(canvas))
		var sizes := _tiles(dialog.size_field)
		var biomes := _tiles(dialog.biome_field)
		var landforms := _tiles(dialog.landform_field)
		for i in sizes.size():
			assert_almost_eq(sizes[i].size.x, biomes[i].size.x, SLACK_PX, "%s: size tile" % what)
			assert_almost_eq(
				sizes[i].global_position.x, biomes[i].global_position.x, SLACK_PX, what
			)
		if canvas == CANVAS_720P_AUTO:
			assert_almost_eq(landforms[0].size.x, biomes[0].size.x, SLACK_PX, "%s: landform" % what)
			var first_line := 0
			for tile in biomes:
				if is_equal_approx(tile.position.y, biomes[0].position.y):
					first_line += 1
			assert_eq(first_line, NewMapDialog.BIOME_COLUMNS_WIDE, "%s: biome line" % what)
		dialog.free()


func test_join_screen_fits() -> void:
	var lobby := CLIENT_SCENE.instantiate()
	lobby.connect_network = false
	_host.add_child(lobby)
	await _assert_fits("join screen", lobby.connect_button)


## The room as the GM sees it: four players, three maps (one long name), one selected.
func test_room_fits() -> void:
	var room := RoomScreen.new()
	room.connect_network = false
	_host.add_child(room)
	room.panel.set_code(LobbyCode.encode(109775244321098765))
	room.panel.show_session(_room_summary(""), "enet-1", true)
	room.panel.select("hollow")
	await _assert_fits("room", room.panel.action_button)


## The room drawer over a table, open on another map than the one out.
func test_room_drawer_fits() -> void:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var drawer := RoomDrawer.new()
	drawer.connect_network = false
	drawer.theme = ThemeColors.glass_theme()
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(drawer)
	drawer.panel.set_code(LobbyCode.encode(109775244321098765))
	drawer.panel.show_session(_room_summary("mill"), "enet-1", true)
	drawer.panel.select("hollow")
	var hints := _play_hints()
	drawer.open()
	await _assert_fits("room drawer", drawer.panel.action_button)
	_assert_uncovered("hint bar beside the room drawer", hints)


func _room_summary(table: String) -> Dictionary:
	var shelf := []
	for spec in [
		["hollow", "Mossy Hollow, the long way round past the mill"],
		["mill", "Old Mill"],
		["fen", "Fen Crossing"],
	]:
		shelf.append({"folder": spec[0], "map_path": "", "hashes": {}, "name": spec[1]})
	var players := {}
	var names := ["Marigold", "Ranger", "Starling", "Wren"]
	for i in names.size():
		players["enet-%d" % (i + 1)] = {"name": names[i], "peer_id": i + 1}
	return {
		"open": table == "",
		"table": table,
		"shelf": shelf,
		"players": players,
		"holdings": {"enet-1": ["hollow", "mill", "fen"], "enet-2": ["hollow"]},
	}


func test_authoring_drawer_fits() -> void:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var panel := AuthoringPanel.new()
	panel.theme = ThemeColors.glass_theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	var hints := _play_hints()
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
		_assert_uncovered("hint bar beside the authoring drawer on %s" % pane, hints)


func test_play_hud_visuals_drawer_and_asset_browser_fit() -> void:
	var play := PLAY_SCENE.instantiate()
	_host.add_child(play)
	var menu: Node = play.get_node("GameplayMenu")
	var drawer := menu.get("level_edit_panel") as LevelEditPanel
	drawer.initialize(LevelData.new())
	var hints := _play_hints()
	for pane in LevelEditPanel.PANE_IDS:
		if pane != drawer._rail.selected or not drawer.is_open:
			drawer._on_rail_item_pressed(pane)
		await _assert_fits("play HUD, visuals drawer on %s" % pane, drawer)
		assert_eq(drawer._rail.selected, pane)
		_assert_uncovered("hint bar beside the visuals drawer on %s" % pane, hints)
	drawer.mark_clean()
	drawer.close()
	(menu.get("toggle_asset_browser_button") as Button).button_pressed = true
	var browser := menu.get_node("AssetBrowserContainer") as Control
	await _assert_fits("play HUD with the asset browser", browser)


## At 720p Auto the hint bar slides into the board the Visuals drawer leaves free, centred
## there and whole, and comes back to the window's centre when the drawer closes.
func test_hint_bar_centres_beside_the_visuals_drawer_at_720p_auto() -> void:
	_host.size = CANVAS_720P_AUTO
	var play := PLAY_SCENE.instantiate()
	_host.add_child(play)
	var drawer := play.get_node("GameplayMenu").get("level_edit_panel") as LevelEditPanel
	drawer.initialize(LevelData.new())
	var hints := _play_hints()
	drawer._on_rail_item_pressed(&"sun")
	await _assert_fits("hint bar beside the drawer", drawer, Vector2(CANVAS_720P_AUTO))
	_assert_uncovered("hint bar beside the drawer at 720p Auto", hints)
	var bar := _drawn_rect(_backdrop(hints))
	assert_almost_eq(_drawn_alpha(_backdrop(hints)), 1.0, 0.01, "the bar shows whole")
	var free_centre := drawer.covered_span().x / 2.0
	assert_almost_eq(bar.get_center().x, free_centre, 1.0, "centred in the free board")
	drawer.mark_clean()
	drawer.close()
	await _assert_fits("hint bar, drawer closed", _backdrop(hints), Vector2(CANVAS_720P_AUTO))
	bar = _drawn_rect(_backdrop(hints))
	assert_almost_eq(bar.get_center().x, CANVAS_720P_AUTO.x / 2.0, 1.0, "back in the centre")


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


## The measure tool's row (ten chips) is wider than the canvas at 150%: it wraps onto a second
## line inside the canvas, whole and clear of the Add Token button, rather than running past
## both edges; beside an open drawer it wraps inside the free board.
func test_a_long_hint_row_wraps_inside_the_canvas() -> void:
	var play := PLAY_SCENE.instantiate()
	_host.add_child(play)
	var drawer := play.get_node("GameplayMenu").get("level_edit_panel") as LevelEditPanel
	drawer.initialize(LevelData.new())
	var hints := _play_hints()
	# As MeasureTool._update_hints: its own keys replace Measure and Grid.
	hints.remove_hint(InputProfile.label(&"measure"))
	hints.remove_hint(InputProfile.label(&"grid"))
	for spec in [
		[&"place_point", "Place Point"],
		[&"snap_token", "Snap Token"],
		[&"undo_cancel", "Undo / Cancel"],
		[&"cycle_mode", "Sphere"],
		[&"done", "Done"],
	]:
		hints.add_hint(InputProfile.label(spec[0]), spec[1])
	await _assert_fits("the measure hint row", _backdrop(hints))
	var bar := _drawn_rect(_backdrop(hints))
	assert_true(Rect2(Vector2.ZERO, CANVAS).encloses(bar), "the row on the canvas: %s" % bar)
	assert_almost_eq(_drawn_alpha(_backdrop(hints)), 1.0, 0.01, "and shown")
	_assert_uncovered("the measure hint row beside Add Token", hints)
	drawer._on_rail_item_pressed(&"sun")
	await _assert_fits("the measure hint row beside the drawer", drawer)
	_assert_uncovered("the measure hint row beside the drawer", hints)
	var room := drawer.covered_span().x - 2.0 * InputHints.DRAWER_CLEARANCE
	assert_lte(_backdrop(hints).size.x, room + SLACK_PX, "held to the free board")


## An AnimatedCanvasLayerPanel's sheet.
func _sheet(layer: Node) -> Control:
	return layer.get_node("CenterContainer/PanelContainer") as Control


## The title with one saved level selected, so Host and Play Solo show their captions.
func _title() -> TitleScreen:
	var title := TITLE_SCENE.instantiate() as TitleScreen
	title.level_provider = func() -> Array[Dictionary]: return [LEVEL.duplicate()]
	_host.add_child(title)
	return title


## The bottom-left version label stays SPACE_3 or more below the left column's last button.
func _assert_clear_of_version_label(what: String, title: TitleScreen) -> void:
	var version := (title.get("_version_label") as Control).get_global_rect()
	var quit := _drawn_rect(title.quit_button)
	assert_lte(quit.end.y + 12.0, version.position.y, "%s: Quit clears the version" % what)


## The next shown sibling after `control` that is not a spacer (a bare Control).
func _next_shown(control: Control) -> Control:
	var parent := control.get_parent()
	for i in range(control.get_index() + 1, parent.get_child_count()):
		var next := parent.get_child(i) as Control
		if next.visible and next.get_class() != "Control":
			return next
	return null


## The vertical space between `upper`'s bottom and `lower`'s top.
func _gap(upper: Control, lower: Control) -> float:
	return lower.get_global_rect().position.y - upper.get_global_rect().end.y


func _tiles(field: TileField) -> Array[Control]:
	var out: Array[Control] = []
	for child in field.tiles.get_children():
		if child is Button:
			out.append(child as Control)
	return out


## A hint bar in the host with the play HUD's hints (GameplayMenuController's defaults).
func _play_hints() -> InputHints:
	var hints := HINTS_SCENE.instantiate() as InputHints
	_host.add_child(hints)
	hints.set_hints(
		[
			{"key": InputProfile.label(&"pause"), "action": "Pause"},
			{"key": InputProfile.label(&"wasd"), "action": "Pan"},
			{"key": InputProfile.label(&"zoom"), "action": "Zoom"},
			{"key": InputProfile.label(&"reset_camera"), "action": "Reset Camera"},
			{"key": InputProfile.label(&"measure"), "action": "Measure"},
			{"key": InputProfile.label(&"grid"), "action": "Grid"},
			{"key": "F1", "action": "Help"},
		]
	)
	return hints


func _backdrop(hints: InputHints) -> Control:
	return hints.get_node("%BackdropPanel") as Control


## No open drawer's panel or handle, and no bottom-corner button (InputHints.OBSTACLES), lies
## over the hint bar where it draws (offset transforms included); a bar that is not showing
## is out of the way.
func _assert_uncovered(what: String, hints: InputHints) -> void:
	var backdrop := _backdrop(hints)
	assert_true(backdrop.is_visible_in_tree(), "%s is in the tree" % what)
	if _drawn_alpha(backdrop) < 0.01:
		return
	var rect := _drawn_rect(backdrop)
	var covers: Array[Control] = []
	for node in get_tree().get_nodes_in_group(DrawerContainer.GROUP):
		var drawer := node as DrawerContainer
		if _host.is_ancestor_of(drawer) and drawer.is_open:
			covers.append_array([drawer._panel, drawer._tab_control])
	for node in get_tree().get_nodes_in_group(InputHints.OBSTACLES):
		if _host.is_ancestor_of(node):
			covers.append(node as Control)
	var under := PackedStringArray()
	for part in covers:
		if part.is_visible_in_tree() and _drawn_rect(part).intersects(rect):
			under.append("%s under %s" % [str(rect), _host.get_path_to(part)])
	assert_eq(under.size(), 0, "%s is clear of drawers and buttons: %s" % [what, "; ".join(under)])


## Where `control` draws: its rect moved by every offset transform on it and its ancestors.
func _drawn_rect(control: Control) -> Rect2:
	var rect := control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
	var node: Node = control
	while node is Control:
		var each := node as Control
		if each.offset_transform_enabled:
			rect.position += each.offset_transform_position
		node = node.get_parent()
	return rect


## The alpha `control` draws with: its modulate times its ancestors' up to the canvas layer.
func _drawn_alpha(control: Control) -> float:
	var alpha := control.self_modulate.a
	var node: Node = control
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a
		node = node.get_parent()
	return alpha


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
