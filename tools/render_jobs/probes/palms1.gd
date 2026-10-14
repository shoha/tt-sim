extends RefCounted

## Render-job probe (`call` op) for the palms and ferns looks pass (treecube
## docs/looks/palms_ferns.md), on the open authoring map:
## - `action: "hide_scatter"` (default): hide every scatter MultiMeshInstance3D under the
##   authoring scatter (`AuthoredScatter`), keeping placed props, so a type sheet shows only the
##   props a job placed on the biome's own ground; `visible: true` shows them again.
## - `action: "only"`, `prefixes` ([String]): show only the scatter nodes whose name starts with
##   one of the prefixes (the asset node stems, e.g. "Palm_", "Fern_").


static func run(root: Node, step: Dictionary) -> String:
	var action := String(step.get("action", "hide_scatter"))
	if action == "look_up":
		return _look_up(root, step.get("at", [0.0, 0.0]), float(step.get("height", 0.0)))
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.scatter == null:
		return "no authoring map"
	var prefixes: Array = step.get("prefixes", [])
	var shown := 0
	var hidden := 0
	for node in ctrl.scatter.find_children("*", "MultiMeshInstance3D", true, false):
		var keep := false
		if action == "hide_scatter":
			keep = bool(step.get("visible", false))
		else:
			for prefix in prefixes:
				if String(node.name).begins_with(String(prefix)):
					keep = true
		(node as Node3D).visible = keep
		if keep:
			shown += 1
		else:
			hidden += 1
	return "%s: %d scatter nodes shown, %d hidden" % [action, shown, hidden]


## `action: "look_up"`, `at` ([x, z]), `height`: pan (as the driver's `look_at` does) so the
## screen centre shows the point `height` metres above the ground point `at` (a palm's crown):
## the view ray through that point meets the ground further along the camera's view direction.
static func _look_up(root: Node, at: Array, height: float) -> String:
	var gm := root.get("_game_map") as GameMap
	if gm == null:
		return "no map"
	var camera := gm.world_viewport.get_camera_3d()
	var forward := -camera.global_basis.z
	if forward.y > -0.01:
		return "camera does not look down"
	var reach := height / -forward.y
	var ground := Vector2(float(at[0]) + forward.x * reach, float(at[1]) + forward.z * reach)
	var cc := gm.get_camera_controller()
	var off: Vector2 = cc.call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(
		ground.x - off.x, holder.global_position.y, ground.y - off.y
	)
	return "look_up: centre on %s (%.1f m above %s)" % [ground, height, at]
