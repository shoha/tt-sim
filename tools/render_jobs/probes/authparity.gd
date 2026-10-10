extends RefCounted

## Render-job probe (`call` op) for the authoring parity card (2026-10-09): a saved token in
## authoring, the same token in play after a sculpt raised the ground under it, and the play
## camera's whole-map zoom (MapViewFit). step.action:
##   save {folder, token, y, replace}  writes the open authoring document and level as
##                                user://levels/<folder> (an _authparity_ test level), its
##                                token placements replaced by one avatar token at `token`
##                                ([x, z]) with its base at height `y` (default: the ground
##                                under it now), so a later sculpt can leave it buried.
##                                `replace` overwrites an existing folder.
##   report                       each token's base height, the ground under it (terrain
##                                layer ray) and the gap; the camera's size and zoom-out limit
##                                and the sun's shadow max distance.
##   cleanup                      deletes every _authparity_ level folder.

const PREFIX := "_authparity_"
const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"save":
			return _save(base, step)
		"report":
			return _report(base)
		"cleanup":
			return _cleanup()
	return "unknown action"


static func _save(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var folder := String(step.get("folder", ""))
	if ctrl == null or not folder.begins_with(PREFIX):
		return "no authoring controller, or not an %s folder" % PREFIX
	var path := LevelManager.folder_path(folder)
	if DirAccess.dir_exists_absolute(path) and not bool(step.get("replace", false)):
		return "folder %s exists; not touching it (replace: true overwrites)" % folder
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	ctrl.call("_sync_document")
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	var note := ""
	if step.has("token"):
		var at: Array = step.token
		var ground := _ground_at(base.get("_game_map") as GameMap, Vector2(at[0], at[1]))
		var placement := TokenPlacement.new()
		placement.avatar_recipe = RECIPE.duplicate(true)
		placement.token_name = "Parity"
		var y := float(step.get("y", ground if is_finite(ground) else 0.0))
		placement.position = Vector3(float(at[0]), y, float(at[1]))
		saved.token_placements.clear()
		saved.token_placements.append(placement)
		note = "; token at %s (ground %.3f)" % [str(placement.position), ground]
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s%s" % [folder, str(ok), note]


static func _report(base: Node) -> String:
	var gm := base.get("_game_map") as GameMap
	if gm == null:
		return "no game map"
	var out := PackedStringArray()
	for node in gm.get_tree().get_nodes_in_group("board_tokens"):
		var token := node as BoardToken
		if token == null or token.rigid_body == null:
			continue
		var at := token.rigid_body.global_position
		var ground := _ground_at(gm, Vector2(at.x, at.z))
		out.append(
			"%s base y %.3f ground %.3f gap %.3f" % [token.name, at.y, ground, at.y - ground]
		)
	var cc := gm.get_camera_controller()
	var suns := gm.world_viewport.find_children("*", "DirectionalLight3D", true, false)
	var shadow := (suns[0] as DirectionalLight3D).directional_shadow_max_distance if suns else 0.0
	return (
		"tokens [%s]; camera size %.2f max zoom %.2f; sun shadow max %.1f"
		% ["; ".join(out), gm.camera_node.size, cc.max_zoom, shadow]
	)


## The terrain-layer ground height under `xz`, or NAN when nothing is there.
static func _ground_at(gm: GameMap, xz: Vector2) -> float:
	if gm == null:
		return NAN
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var hit := DragPlaceController.raycast_terrain_down(space, Vector3(xz.x, 0.0, xz.y))
	return hit.y if hit != Vector3.INF else NAN


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
