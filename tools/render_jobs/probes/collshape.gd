extends RefCounted

## Render-job probe (`call` op) for pack tokens' collision shapes (jobs/collshape_look.json,
## scenes/board_token/token_shape.gd). Positions are map XZ metres. `action`:
## - `debug` (`on` default true): a red wire of every token's collision shape, drawn over the
##   model (named PlaceholderModel so the token's own mesh readers skip it).
## - `report`: per token, its shape box, mesh box and the ratio of the two, the gap between the
##   shape's base and the terrain, and two pick rays (down through the shape's centre, which
##   must hit the token, and 0.3 m beside the shape, which must miss it).
## - `table` (`at` [x, z], `size` default 1.6, `height` default 0.75): a slab standing on the
##   terrain. `put` (`at`, `token` a name), a step later: the token set on the ray's hit the way
##   a drop settles one (its shape's base on it), reporting the gap between the model's lowest
##   point and the slab's top.
## - `onto` (`token`, `target`): the token moved over the target's centre, set on its top, to
##   show their boxes (tokens do not collide with each other, so this is a placement check).
## - `wait_report`: the same as `report`, for a step after a move.

const DEBUG_NAME := "PlaceholderModel"
const TOKEN_LAYER := 2


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	match String(step.get("action", "report")):
		"debug":
			return _debug(gm, bool(step.get("on", true)))
		"report", "wait_report":
			return _report(gm)
		"table":
			return _table(gm, step)
		"put":
			return _put(gm, step)
		"onto":
			return _onto(gm, step)
	return "unknown action"


static func _tokens(gm: GameMap) -> Array[BoardToken]:
	var out: Array[BoardToken] = []
	for node in gm.get_tree().get_nodes_in_group(BoardToken.GROUP_NAME):
		out.append(node as BoardToken)
	return out


static func _find(gm: GameMap, token_name: String) -> BoardToken:
	for token in _tokens(gm):
		if token.token_name == token_name:
			return token
	return null


static func _mesh_box(token: BoardToken) -> AABB:
	var box := AABB()
	var first := true
	for mi in TokenGhost.meshes_of(token.rigid_body):
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin != null else null
		var world := mi.global_transform * mi.get_aabb()
		if skeleton != null:
			world = TokenShape.bounds_of(
				skeleton.global_transform * TokenShape.posed_points(mi, skeleton)
			)
		box = world if first else box.merge(world)
		first = false
	return box


static func _debug(gm: GameMap, on: bool) -> String:
	var count := 0
	for token in _tokens(gm):
		var node := token.rigid_body.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if node == null or node.shape == null:
			continue
		for child in node.get_children():
			if child.name == DEBUG_NAME:
				child.queue_free()
		if not on:
			continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.1, 0.1, 0.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.no_depth_test = true
		material.render_priority = 100
		var wire := MeshInstance3D.new()
		wire.name = DEBUG_NAME
		wire.mesh = node.shape.get_debug_mesh()
		wire.material_override = material
		wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(wire)
		count += 1
	return "debug wires %d" % count


static func _ray_down(gm: GameMap, xz: Vector2, mask: int) -> Dictionary:
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, 20.0, xz.y), Vector3(xz.x, -20.0, xz.y), mask
	)
	return space.intersect_ray(query)


static func _report(gm: GameMap) -> String:
	var out := PackedStringArray()
	for token in _tokens(gm):
		var shape := TokenMarkers.shape_box(token.rigid_body)
		var mesh := _mesh_box(token)
		var line := "%s: shape %s mesh %s" % [token.token_name, _size(shape), _size(mesh)]
		if shape.has_volume() and mesh.has_volume():
			var ground := _ray_down(gm, Vector2(shape.get_center().x, shape.get_center().z), 1)
			var gy: float = ground.position.y if not ground.is_empty() else NAN
			var centre := _ray_down(gm, Vector2(shape.get_center().x, shape.get_center().z), TOKEN_LAYER)
			var beside := _ray_down(gm, Vector2(shape.end.x + 0.3, shape.get_center().z), TOKEN_LAYER)
			line += " | ratio %.2f/%.2f | base-ground %.3f | pick centre %s beside %s" % [
				shape.size.x / mesh.size.x,
				shape.size.z / mesh.size.z,
				shape.position.y - gy,
				str(not centre.is_empty() and centre.collider == token.rigid_body),
				str(not beside.is_empty() and beside.collider == token.rigid_body),
			]
		out.append(line)
	return "\n" + "\n".join(out)


static func _size(box: AABB) -> String:
	return "%.2fx%.2fx%.2f@(%.2f,%.2f,%.2f)" % [
		box.size.x, box.size.y, box.size.z, box.position.x, box.position.y, box.position.z
	]


static func _table(gm: GameMap, step: Dictionary) -> String:
	var at := Vector2(float(step.at[0]), float(step.at[1]))
	var size := float(step.get("size", 1.6))
	var height := float(step.get("height", 0.75))
	var ground := _ray_down(gm, at, 1)
	var gy: float = ground.position.y if not ground.is_empty() else 0.0
	var slab := StaticBody3D.new()
	slab.name = "CollshapeTable"
	slab.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, height, size)
	shape.shape = box
	slab.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.22)
	mesh.material_override = wood
	slab.add_child(mesh)
	gm.world_viewport.add_child(slab)
	slab.global_position = Vector3(at.x, gy + height * 0.5, at.y)
	return "table at %s, top %.3f" % [str(at), gy + height]


## `put`: the named token set on whatever the terrain ray finds at `at` (the table, once the
## physics frame has taken it), reporting the gap between the model's lowest point and that top.
static func _put(gm: GameMap, step: Dictionary) -> String:
	var at := Vector2(float(step.at[0]), float(step.at[1]))
	var token := _find(gm, String(step.get("token", "")))
	if token == null:
		return "no token"
	var top := _ray_down(gm, at, 1)
	var hit_y: float = top.position.y
	var rb := token.rigid_body
	var local := TokenMarkers.shape_box(rb)
	var base_offset := local.position.y - rb.global_position.y
	token.set_transform_immediate(
		Vector3(at.x, hit_y - base_offset, at.y), rb.global_rotation, rb.scale
	)
	token.transform_changed.emit()
	var mesh_low := _mesh_box(token).position.y
	return "table top %.3f, model lowest %.3f, gap %.3f" % [hit_y, mesh_low, mesh_low - hit_y]


static func _onto(gm: GameMap, step: Dictionary) -> String:
	var token := _find(gm, String(step.get("token", "")))
	var target := _find(gm, String(step.get("target", "")))
	if token == null or target == null:
		return "missing token"
	var target_box := TokenMarkers.shape_box(target.rigid_body)
	var rb := token.rigid_body
	var own := TokenMarkers.shape_box(rb)
	var base_offset := own.position.y - rb.global_position.y
	var centre := target_box.get_center()
	token.set_transform_immediate(
		Vector3(centre.x, target_box.end.y - base_offset, centre.z), rb.global_rotation, rb.scale
	)
	token.transform_changed.emit()
	return "%s on %s: target top %.3f, token base %.3f" % [
		token.token_name, target.token_name, target_box.end.y, TokenMarkers.shape_box(rb).position.y
	]
