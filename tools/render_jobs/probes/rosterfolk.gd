extends RefCounted

## Render-job probe (`call` op) for a built-in token pack's roster look (jobs/rosterfolk_look.json).
## Positions are map XZ metres. `action`:
## - `row` (`pack` default "folk", `at` [x, z] of the first token, `spacing` metres along +x
##   default 1.8, `per_row` default 8, `row_gap` metres along +z default 2.4, `yaw` degrees,
##   `ids` an optional list, else every asset of the pack): spawns the pack's tokens as real
##   board tokens through the level's spawner, settled on the ground, in rows.
## - `report`: each pack token's name, position and logical height.

const PACK := "folk"


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var lpc: LevelPlayController = base.get("_level_play_controller")
	match String(step.get("action", "report")):
		"row":
			return _row(gm, lpc, step)
		"report":
			return _report(gm)
	return "unknown action"


static func _row(gm: GameMap, lpc: LevelPlayController, step: Dictionary) -> String:
	if lpc == null:
		return "not playing"
	var pack: AssetPack = AssetManager.get_pack(String(step.get("pack", PACK)))
	if pack == null:
		return "no such pack"
	var ids: Array = step.get("ids", [])
	if ids.is_empty():
		ids = pack.assets.keys()
	var origin := Vector2(float(step.at[0]), float(step.at[1]))
	var spacing := float(step.get("spacing", 1.8))
	var per_row := int(step.get("per_row", 8))
	var row_gap := float(step.get("row_gap", 2.4))
	var spawned := 0
	for i in ids.size():
		var xz := origin + Vector2((i % per_row) * spacing, (i / per_row) * row_gap)
		var token := lpc.spawn_asset(pack.pack_id, String(ids[i]), "default", _ground(gm, xz), true)
		if token == null:
			continue
		var yaw := float(step.get("yaw", 0.0))
		if yaw != 0.0:
			token.set_transform_immediate(token.rigid_body.global_position, Vector3(0, deg_to_rad(yaw), 0), Vector3.ONE)
			token.transform_changed.emit()
		spawned += 1
	return "spawned %d of %d" % [spawned, ids.size()]


static func _report(gm: GameMap) -> String:
	var out := PackedStringArray()
	for node in gm.get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		out.append("%s %s" % [token.token_name, str(token.rigid_body.global_position.snapped(Vector3.ONE * 0.01))])
	return "; ".join(out)


static func _ground(gm: GameMap, xz: Vector2) -> Vector3:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0, xz.y))
	return Vector3(xz.x, hit.y if hit != Vector3.INF else 0.0, xz.y)
