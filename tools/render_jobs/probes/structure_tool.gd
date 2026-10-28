extends RefCounted

## Render-job probe (`call` op) for the Structure tool (the tool is driven with the driver's
## `gesture` and `input` ops; card S4). step.action:
##   report            every structure of the open document (authoring) with its node, vertices
##                     and body, the brush's ghost state; in play, the AuthoredStructures nodes.
##   pick {ref}        picks the structure the brush lays, as a palette tile does.
##   rotate {steps}    turns the lot, as Q (-1) and E (1) do.
##   reroll            R: re-rolls the structure under the pointer, else draws the next afresh.
##   flush             waits for the structure builds in flight.
##   save {folder}     crossing.gd's save (a _structs4_ test level only).
##   cleanup           crossing.gd's cleanup (every _structs4_ level).

const CROSSING := preload("res://tools/render_jobs/probes/crossing.gd")


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"report":
			return _report(base)
		"pick":
			return _pick(base, String(step.get("ref", "")))
		"rotate":
			return _rotate(base, int(step.get("steps", 1)))
		"reroll":
			return _reroll(base)
		"flush":
			var nodes := _nodes(base)
			return "flushed %d" % nodes.flush() if nodes != null else "no AuthoredStructures"
		"save":
			return CROSSING.run(base, {"action": "save", "folder": step.get("folder", "")})
		"cleanup":
			return CROSSING.run(base, {"action": "cleanup"})
	return "unknown action %s" % step.get("action", "")


static func _root(base: Node) -> Node:
	var gm := base.get("_game_map") as GameMap
	var played: Node = gm.get_node_or_null("LevelMap") if gm != null else null
	if is_instance_valid(played) and played.has_node(AuthoredStructures.NODE_NAME):
		return played
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl != null and is_instance_valid(ctrl.map_root):
		return ctrl.map_root
	return played


static func _nodes(base: Node) -> AuthoredStructures:
	var root := _root(base)
	return (
		root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures if root else null
	)


static func _mode(base: Node) -> StructureBrush:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.get_brush_tool() == null:
		return null
	return StructureTool.of(gm.get_brush_tool())


static func _pick(base: Node, ref: String) -> String:
	var mode := _mode(base)
	if mode == null:
		return "no brush"
	mode.pick(ref)
	return "picked %s" % ref


static func _rotate(base: Node, steps: int) -> String:
	var mode := _mode(base)
	var gm := base.get("_game_map") as GameMap
	if mode == null:
		return "no brush"
	mode.rotate(gm.get_brush_tool(), steps)
	return "yaw %.1f degrees" % rad_to_deg(mode.yaw)


static func _reroll(base: Node) -> String:
	var mode := _mode(base)
	var gm := base.get("_game_map") as GameMap
	if mode == null:
		return "no brush"
	mode.reroll(gm.get_brush_tool())
	return "rerolled (next seed %d)" % mode.seed_value


static func _report(base: Node) -> String:
	var nodes := _nodes(base)
	if nodes == null:
		return "no AuthoredStructures"
	var lines := PackedStringArray()
	for child in nodes.get_children():
		var verts := 0
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			var array_mesh := (mesh as MeshInstance3D).mesh
			verts += (
				array_mesh.surface_get_array_len(0) if array_mesh.get_surface_count() > 0 else 0
			)
		lines.append(
			(
				"%s verts %d body %s"
				% [child.name, verts, str(child.get_node_or_null("Collision") != null)]
			)
		)
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var count := ctrl.document.structures.size() if ctrl != null and ctrl.document != null else -1
	if ctrl != null and ctrl.document != null:
		for structure in ctrl.document.structures:
			lines.append("#%d at %s" % [structure.id, structure.bounds().get_center()])
	var mode := _mode(base)
	var ghost := ""
	if mode != null:
		ghost = (
			"; ghost %s size %s eased %s problem '%s' ref %s"
			% [mode.ghost_centre, mode.ghost_size, str(mode.eased), mode.problem, mode.ref]
		)
	return "structures in document %d; %s%s" % [count, "; ".join(lines), ghost]
