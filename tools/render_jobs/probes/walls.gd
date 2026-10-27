extends RefCounted

## Render-job probe (`call` op) for walls and fences (the Wall tool is driven with the driver's
## `gesture` and `input` ops). step.action:
##   report            every wall of the open document (authoring) with its node, vertices,
##                     height, top and body; in play, the AuthoredWalls under the map root.
##   place {kind, from, to}  lays one wall side through the editor API (world XZ).
##   kind {kind}       picks the brush kind ("stone" or "fence") as its pane tile does.
##   save {folder}     crossing.gd's save (a _p4b1_ test level only).

const CROSSING := preload("res://tools/render_jobs/probes/crossing.gd")


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"report":
			return _report(base)
		"kind":
			return _kind(base, String(step.get("kind", "stone")))
		"place":
			return _place(base, step)
		"save":
			return CROSSING.run(base, {"action": "save", "folder": step.get("folder", "")})
	return "unknown action %s" % step.get("action", "")


static func _root(base: Node) -> Node:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl != null and ctrl.map_root != null:
		return ctrl.map_root
	var gm := base.get("_game_map") as GameMap
	return gm.get_node_or_null("LevelMap") if gm != null else null


static func _kind(base: Node, kind: String) -> String:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.get_brush_tool() == null:
		return "no brush"
	var picked := Wall.KIND_NAMES.find(kind)
	if picked < 0:
		return "unknown kind %s" % kind
	WallTool.of(gm.get_brush_tool()).kind = picked
	return "wall kind %s" % kind


static func _report(base: Node) -> String:
	var root := _root(base)
	var walls := root.get_node_or_null(AuthoredWalls.NODE_NAME) as AuthoredWalls if root else null
	if walls == null:
		return "no AuthoredWalls"
	var lines := PackedStringArray()
	for child in walls.get_children():
		var verts := 0
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			verts += (
				(mesh as MeshInstance3D).mesh.surface_get_array_len(0)
				if ((mesh as MeshInstance3D).mesh.get_surface_count() > 0)
				else 0
			)
		var body := child.get_node_or_null("Collision") != null
		lines.append("%s verts %d body %s" % [child.name, verts, str(body)])
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var count := ctrl.document.walls.size() if ctrl != null and ctrl.document != null else -1
	return "walls in document %d; top_y %.2f; %s" % [count, walls.top_y, "; ".join(lines)]


static func _place(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	var kind := Wall.KIND_NAMES.find(String(step.get("kind", "stone")))
	var a: Array = step.get("from", [0, 0])
	var b: Array = step.get("to", [0, 0])
	var id := ctrl.editor.walls.place(
		maxi(kind, 0) as Wall.Kind,
		Vector3(float(a[0]), 0, float(a[1])),
		Vector3(float(b[0]), 0, float(b[1]))
	)
	return "placed wall %d" % id if id >= 0 else "refused: %s" % ctrl.editor.walls.last_refusal
