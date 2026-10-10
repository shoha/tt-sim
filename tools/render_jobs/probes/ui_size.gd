extends RefCounted

## Render-job probe (`call` op) for the UI tour's Interface size passes (jobs/ui_tour.json): the
## states a size pass shows that no other probe stages. The window and its size come from
## ui_primitives.gd `window`. `action`:
## - `dropdown` (`open`, default true): open the Interface Size dropdown on the open Settings
##   menu (the Graphics section must be showing), as a click on it would, or close it.
## - `measure` (`on`, default true): in play, turn the measure tool on and lay a two-segment
##   line across the middle of the board, as three clicks would (each point is a camera ray
##   onto the terrain through a fixed share of the board view), so its labels and dots draw
##   on the canvas at this Interface size; or turn it off.
## - `new_map_scroll` (`to` "end" or "start", default "end"): scroll the open new-map dialog's
##   fields, the path a short canvas takes to Landform.

## The line's three points, as shares of the board view.
const MEASURE_POINTS: Array[Vector2] = [Vector2(0.3, 0.62), Vector2(0.48, 0.4), Vector2(0.66, 0.56)]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"dropdown":
			return _dropdown(base, bool(step.get("open", true)))
		"measure":
			return _measure(base, bool(step.get("on", true)))
		"new_map_scroll":
			return _new_map_scroll(base, String(step.get("to", "end")))
	return "unknown action %s" % step.get("action", "")


static func _dropdown(base: Node, open: bool) -> String:
	var menu: SettingsMenu = null
	for child in base.get_tree().root.get_children():
		if child is SettingsMenu and not child.is_queued_for_deletion():
			menu = child
	if menu == null:
		return "settings not open"
	var option := menu.interface_size_option
	if not open:
		option.get_popup().hide()
		return "dropdown closed"
	if not option.is_visible_in_tree():
		return "the Interface Size row is not showing"
	option.show_popup()
	var items := PackedStringArray()
	for i in option.item_count:
		items.append(option.get_item_text(i))
	return "dropdown open: %s" % ", ".join(items)


static func _measure(base: Node, on: bool) -> String:
	var gm := base.get("_game_map") as GameMap
	var tool := gm.get_measure_tool() if gm else null
	if tool == null:
		return "no measure tool"
	if not on:
		tool.deactivate()
		return "measure off"
	tool.activate()
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var view := Vector2(gm.world_viewport.size)
	var points := PackedVector3Array()
	for share in MEASURE_POINTS:
		var screen := view * share
		var origin := gm.camera_node.project_ray_origin(screen)
		var end := origin + gm.camera_node.project_ray_normal(screen) * MeasureTool.RAYCAST_LENGTH
		var query := PhysicsRayQueryParameters3D.create(origin, end)
		query.collision_mask = MeasureTool.TERRAIN_COLLISION_LAYER
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return "no terrain under %s" % str(share)
		points.append(hit.position as Vector3)
	tool.set("_waypoints", points)
	tool.set("_state", MeasureTool.State.PLACING_WAYPOINT)
	tool.set("_has_preview", false)
	tool.call("_mark_dirty")
	return "measuring through %s" % str(points)


static func _new_map_scroll(base: Node, to: String) -> String:
	var dialog := base.get("_new_map_dialog") as NewMapDialog
	if dialog == null or not is_instance_valid(dialog):
		return "no new-map dialog"
	var scroll := dialog.get("_scroll") as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(bar.max_value) if to == "end" else 0
	return (
		"new-map fields scrolled to %d of %d (page %d)"
		% [scroll.scroll_vertical, int(bar.max_value), int(bar.page)]
	)
