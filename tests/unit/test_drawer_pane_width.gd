extends GutTest

## No drawer pane is wider than its pane, at the 1280x720 window's Auto canvas (1371x771):
## every Visuals pane and every authoring tool pane, Advanced foldouts open, ends on the edge
## the drawer's margin sets, the same edge as the rows pinned above or below the panes (the
## authoring map name). Round 1 of the 2026-10-10 UI fixes found the Sky pane 11 px past the
## edge its neighbours keep (its Look dropdown's longest preset widened everything), and the
## authoring panes 7 px short of the name field above them (a gutter kept for the scroll bar,
## which now lies over the content's margin instead).

const CANVAS := Vector2i(1371, 771)
const PLAY_SCENE := preload("res://scenes/states/playing/gameplay_menu.tscn")
## Layout rounding.
const SLACK_PX := 0.5
const SETTLE_S := 3.0

var _host: SubViewport
var _scene: Node
var _old_scene: Node


func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "DrawerPaneWidthScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_host = SubViewport.new()
	_host.size = CANVAS
	_host.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_scene.add_child(_host)


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.queue_free()


func test_every_visuals_pane_ends_on_the_drawer_edge() -> void:
	var play := PLAY_SCENE.instantiate()
	_host.add_child(play)
	var drawer := play.get_node("GameplayMenu").get("level_edit_panel") as LevelEditPanel
	drawer.initialize(LevelData.new())
	var ids: Array[StringName] = LevelEditPanel.PANE_IDS.duplicate()
	ids.append(LevelEditPanel.EVENTS_ID)
	for id in ids:
		if id != drawer._rail.selected or not drawer.is_open:
			drawer._on_rail_item_pressed(id)
		var pane := drawer._stack.get_pane(id)
		_open_foldouts(pane)
		await _settle()
		_assert_inside("visuals %s" % id, pane, drawer.content_container)


func test_every_authoring_pane_ends_on_the_name_field_edge() -> void:
	var layer := CanvasLayer.new()
	_host.add_child(layer)
	var panel := AuthoringPanel.new()
	panel.theme = ThemeColors.glass_theme()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(panel)
	for tool in ToolRegistry.tools(ToolDescriptor.AUTHORING):
		if tool.id != panel._rail.selected or not panel.is_open:
			panel._on_rail_item_pressed(tool.id)
		var pane := panel.tool_pane(tool.id)
		_open_foldouts(pane)
		await _settle()
		_assert_inside("authoring %s" % tool.id, pane, panel.content_container)
		assert_almost_eq(
			pane.get_global_rect().end.x,
			panel.name_edit.get_global_rect().end.x,
			SLACK_PX,
			"authoring %s ends where the map name does" % tool.id
		)


## The pane fills the content column, and no visible control in it ends past the column.
func _assert_inside(what: String, pane: Control, column: Control) -> void:
	var edge := column.get_global_rect().end.x
	assert_almost_eq(pane.get_global_rect().end.x, edge, SLACK_PX, "%s fills the column" % what)
	var past := PackedStringArray()
	_walk(pane, edge + SLACK_PX, past)
	assert_eq(past.size(), 0, "%s stays inside x=%.1f: %s" % [what, edge, "; ".join(past)])


func _walk(node: Node, edge: float, past: PackedStringArray) -> void:
	if node is Window:
		return
	if node is Control:
		var control := node as Control
		if not control.is_visible_in_tree():
			return
		var rect := control.get_global_rect()
		if rect.size.x > 0.0 and rect.end.x > edge:
			past.append("%s ends at %.1f" % [control.name, rect.end.x])
	for child in node.get_children():
		_walk(child, edge, past)


func _open_foldouts(pane: Control) -> void:
	for node in pane.find_children("*", "Foldout", true, false):
		(node as Foldout).expanded = true


func _settle() -> void:
	await wait_process_frames(2)
	for tween in get_tree().get_processed_tweens():
		tween.custom_step(SETTLE_S)
	await wait_process_frames(3)
