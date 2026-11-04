extends RefCounted

## Render-job probe for card verify1 (item 4): stand the eye inside the map edge in front of a real
## EyeRim cluster and face it, and report the rim's census.
##   {action: "face", nth: 0, dist: 12, pitch: 0, fov: 60}
##       Enters the eye view, finds the `nth` densest cluster of rim instances (clusters at least 15 m
##       apart), stands `dist` m inside the edge in front of it and looks at it. Logs the rim's
##       instance count per asset, the cluster's centre and the eye's forward vector (to check the yaw).


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	cc.set_view_mode(cc.eye)
	var rim := base.get_tree().root.find_child("EyeRim", true, false) as Node3D
	if rim == null:
		return "no EyeRim node"
	var points: Array[Vector3] = []
	var census: Array[String] = []
	for node in rim.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm == null:
			continue
		census.append("%s x%d" % [mmi.name, mm.instance_count])
		for i in mm.instance_count:
			points.append((mmi.global_transform * mm.get_instance_transform(i)).origin)
	if points.is_empty():
		return "EyeRim has no instances (visible %s)" % str(rim.visible)
	var picked: Array[Vector3] = []
	var nth := int(step.get("nth", 0))
	var best := Vector3.INF
	for round_index in nth + 1:
		var best_n := -1
		best = Vector3.INF
		for p in points:
			var far := true
			for q in picked:
				if Vector2(p.x, p.z).distance_to(Vector2(q.x, q.z)) < 15.0:
					far = false
			if not far:
				continue
			var n := 0
			for o in points:
				if Vector2(p.x, p.z).distance_to(Vector2(o.x, o.z)) < 6.0:
					n += 1
			if n > best_n:
				best_n = n
				best = p
		picked.append(best)
	var out := Vector2(best.x, best.z)
	var normal := Vector2.ZERO
	if absf(out.x) > absf(out.y):
		normal = Vector2(signf(out.x), 0.0)
	else:
		normal = Vector2(0.0, signf(out.y))
	var stand := out - normal * (float(step.get("dist", 12.0)) + 6.0)
	cc.eye.frame_ground(stand, 0.0)
	var yaw := rad_to_deg(atan2(-normal.x, -normal.y))
	cc.set_yaw_now(yaw)
	cc.set_pitch_now(float(step.get("pitch", 0.0)))
	cc.view_mode().zoom_by(float(step.get("fov", 60.0)) - cc.view_mode().fov_deg())
	cc.finish_zoom()
	var fwd := -gm.camera_node.global_transform.basis.z
	return (
		"rim %d instances (%s); cluster at %s y %.2f, stand %s yaw %.0f, camera forward xz (%.2f, %.2f) wanted (%.2f, %.2f)"
		% [
			points.size(), ", ".join(census), str(out), best.y, str(stand), yaw, fwd.x, fwd.z,
			normal.x, normal.y
		]
	)
