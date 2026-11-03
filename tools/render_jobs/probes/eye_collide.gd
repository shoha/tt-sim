extends RefCounted

## Render-job probe for the eye view's collision (docs/plans/2026-11-02-camera, card eyecollide).
## Steps (`op: call`, script this file):
##   {action: "bodies", out}      the collision bodies under the map container: path, layer, mask,
##                                shape class, world AABB; written to <out> (a file path)
##   {action: "occupancy", at: [x, z], half, cell, out, mark: [[x, z, "A"], ...]}
##                                an ASCII map of where the eye's sphere (EyeCollider radius at the
##                                eye's height, the terrain body excluded) is blocked: '#' blocked,
##                                '.' free, row 0 at z = at.z - half; x runs right. `mark` puts a
##                                letter at the cells of the listed world points
##   {action: "rays", at: [x, z], count, reach, out}
##                                horizontal rays at eye height from a point: distance and the hit
##                                body per direction (to find a wall's facing)
##   {action: "aa", on}           GameMap.eye_view_antialiasing: MSAA 4x (on) or the saved setting (off)
##   {action: "sweep", at, motions, out}   EyeCollider moves from a point, with cast and rest info
##   {action: "bounds"}           the eye's walking area, the document's and the fallback
## Walks and their foot logs are eye_view.gd's `walk` action (events face / place / walk).


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var cc := gm.get_camera_controller()
	match String(step.get("action", "")):
		"bodies":
			return _bodies(gm, String(step.out))
		"occupancy":
			return _occupancy(gm, cc, step)
		"rays":
			return _rays(gm, cc, step)
		"aa":
			gm.eye_view_antialiasing = bool(step.get("on", true))
			return "eye aa %s, msaa_3d %d" % [str(gm.eye_view_antialiasing), gm.world_viewport.msaa_3d]
		"sweep":
			return _sweep(gm, cc, step)
		"bounds":
			return "bounds walk %s document %s fallback %s" % [str(cc.eye._bounds), str(cc.eye._document_bounds), str(cc.eye._fallback_bounds)]
	return "unknown action"


static func _eye_height(gm: GameMap) -> float:
	var map := gm.map_container.get_node_or_null("LevelMap") as Node3D
	var scale := 1.0 if map == null else map.global_transform.basis.get_scale().x
	return EyeRig.eye_height(scale)


static func _bodies(gm: GameMap, out: String) -> String:
	var lines: Array[String] = []
	var stack: Array[Node] = [gm.map_container]
	var layer_one := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var body := node as CollisionObject3D
		if body == null:
			continue
		var shapes: Array[String] = []
		for child in body.get_children():
			var cs := child as CollisionShape3D
			if cs != null and cs.shape != null:
				shapes.append(cs.shape.get_class())
		if body.collision_layer & 1:
			layer_one += 1
		lines.append(
			"%s layer %d mask %d shapes %s meta %s"
			% [str(gm.map_container.get_path_to(body)), body.collision_layer, body.collision_mask, str(shapes), str(body.get_meta_list())]
		)
	_write(out, lines)
	return "bodies %d (layer 1: %d) -> %s" % [lines.size(), layer_one, out]


static func _occupancy(gm: GameMap, cc: CameraController, step: Dictionary) -> String:
	var at: Array = step.at
	var half := float(step.get("half", 20.0))
	var cell := float(step.get("cell", 0.25))
	var space := gm.map_container.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = EyeCollider.RADIUS_M
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WaterSurface.TERRAIN_LAYER
	query.exclude = cc.eye._excluded_bodies()
	var y := _eye_height(gm)
	if step.has("y"):
		y = float(step.y)
	var marks := {}
	for m: Array in step.get("mark", []):
		marks[Vector2i(roundi((float(m[0]) - float(at[0])) / cell), roundi((float(m[1]) - float(at[1])) / cell))] = String(m[2])
	var n := int(half / cell)
	var lines: Array[String] = []
	var blocked := 0
	for j in range(-n, n + 1):
		var row := ""
		for i in range(-n, n + 1):
			if marks.has(Vector2i(i, j)):
				row += marks[Vector2i(i, j)]
				continue
			query.transform = Transform3D(Basis.IDENTITY, Vector3(float(at[0]) + i * cell, y, float(at[1]) + j * cell))
			if space.intersect_shape(query, 1).is_empty():
				row += "."
			else:
				row += "#"
				blocked += 1
		lines.append(row)
	lines.push_front(
		"occupancy centre %s half %.1f cell %.2f eye y %.2f; first row z %.2f, first col x %.2f"
		% [str(at), half, cell, y, float(at[1]) - n * cell, float(at[0]) - n * cell]
	)
	_write(String(step.out), lines)
	return "occupancy %d blocked cells -> %s" % [blocked, step.out]


static func _rays(gm: GameMap, cc: CameraController, step: Dictionary) -> String:
	var at: Array = step.at
	var count := int(step.get("count", 72))
	var reach := float(step.get("reach", 20.0))
	var space := gm.map_container.get_world_3d().direct_space_state
	var y := _eye_height(gm)
	var lines: Array[String] = []
	for i in count:
		var a := TAU * float(i) / float(count)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var from := Vector3(float(at[0]), y, float(at[1]))
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
		query.collision_mask = WaterSurface.TERRAIN_LAYER
		query.exclude = cc.eye._excluded_bodies()
		query.hit_back_faces = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			lines.append("dir (%.2f, %.2f) none" % [dir.x, dir.z])
		else:
			var collider: Node = hit.collider
			lines.append(
				"dir (%.2f, %.2f) dist %.2f at (%.2f, %.2f) normal (%.2f, %.2f) %s"
				% [dir.x, dir.z, from.distance_to(hit.position), hit.position.x, hit.position.z, hit.normal.x, hit.normal.z, collider.get_parent().name]
			)
	_write(String(step.out), lines)
	return "rays %d -> %s" % [count, step.out]


## {action: "sweep", at: [x, z], motions: [[dx, dz], ...], out}: EyeCollider moves from a point, with
## the cast fractions and the rest info of the sphere at the start (a stuck foot, debugging).
static func _sweep(gm: GameMap, cc: CameraController, step: Dictionary) -> String:
	var at: Array = step.at
	var space := gm.map_container.get_world_3d().direct_space_state
	var y := _eye_height(gm)
	var collider := EyeCollider.new(space, cc.eye._excluded_bodies(), EyeCollider.RADIUS_M)
	var shape := SphereShape3D.new()
	shape.radius = EyeCollider.RADIUS_M
	var lines: Array[String] = []
	for m: Array in step.motions:
		var from := Vector2(float(at[0]), float(at[1]))
		var motion := Vector2(float(m[0]), float(m[1]))
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.collision_mask = 1
		params.exclude = cc.eye._excluded_bodies()
		params.transform = Transform3D(Basis.IDENTITY, Vector3(from.x, y, from.y))
		params.motion = Vector3(motion.x, 0.0, motion.y)
		var cast := space.cast_motion(params)
		params.motion = Vector3.ZERO
		params.margin = 0.03
		var rest := space.get_rest_info(params)
		var end := collider.move(from, motion, y)
		lines.append(
			"motion %s -> end %s hits %d cast %s rest point %s normal %s"
			% [str(motion), str(end.snapped(Vector2.ONE * 0.001)), collider.last_hits, str(cast), str(rest.get("point", "-")), str(rest.get("normal", "-"))]
		)
	_write(String(step.out), lines)
	return "sweep %d motions -> %s" % [lines.size(), step.out]


static func _write(path: String, lines: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	for l in lines:
		f.store_line(l)
