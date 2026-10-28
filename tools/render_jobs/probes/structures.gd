extends RefCounted

## Render-job probe (`call` op) for structures (card S2; there is no Structure tool yet, so they
## are laid through the editor API). step.action:
##   town              lays the test town: a chimneyed cottage, a trimmed townhouse, a townhouse
##                     on an L plan and a stone house (turned), through AuthoringEditor.structures,
##                     then waits for their builds. step.set picks the layout: "basic" (default).
##   street {from, to, preset}  lays a street (Wall.Kind.ROW) through AuthoringEditor.walls.
##   flush             waits for every building in flight (AuthoredStructures.flush).
##   report            the structure nodes of the open map: triangles, meshes per role, top, notes.
##   remove_all        removes every structure (one history entry each), for a clean run.
##   tile {ref, width, depth, yaw, seed}  (card S3, tools/render_structure_thumbnails.gd) removes
##                     every structure and lays this one alone at the map's centre.

const BASIC_LOTS: Array = [
	# recipe, centre x, centre z, width, depth, yaw degrees, seed
	["core:cottage_chimneyed", -7.0, -3.0, 6.0, 4.0, 12.0, 11],
	["core:townhouse_trimmed", 3.0, -5.0, 6.0, 5.0, -8.0, 21],
	["core:townhouse", 10.0, 3.0, 5.0, 5.0, 0.0, 31],
	["core:stone_house", -4.0, 6.0, 5.0, 4.0, 35.0, 41],
]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"town":
			return _town(base)
		"street":
			return _street(base, step)
		"flush":
			return _flush(base)
		"report":
			return _report(base)
		"remove_all":
			return _remove_all(base)
		"inside":
			return _inside(base)
		"tile":
			return _tile(base, step)
	return "unknown action %s" % step.get("action", "")


## One structure alone at the centre (the thumbnail scene), the front turned `yaw` degrees.
static func _tile(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	_remove_all(base)
	var plan := _rect(
		float(step.get("width", 6.0)),
		float(step.get("depth", 4.0)),
		float(step.get("yaw", 0.0)),
		Vector2.ZERO
	)
	var structure := Structure.make(0, String(step.get("ref", "")), plan, int(step.get("seed", 5)))
	var id := editor.structures.add(structure)
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	if id < 0:
		return "refused: %s" % editor.structures.last_refusal
	return "tile %s -> %d" % [step.get("ref", ""), id]


## How many scatter rows (plants, rocks) of the map root stand inside a structure's footprint,
## and how many stand within a metre of one (scatter clearance should leave none inside).
static func _inside(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.map_root == null:
		return "no map"
	var scatter := ctrl.map_root.get_node_or_null(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	if scatter == null:
		return "no scatter node"
	var inside := 0
	var near := 0
	var total := 0
	var rows := scatter.rows_by_asset()
	for asset_id in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		for r in flat.size() / MapDocument.ROW_STRIDE:
			var at := Vector2(
				flat[r * MapDocument.ROW_STRIDE], flat[r * MapDocument.ROW_STRIDE + 2]
			)
			total += 1
			for structure in ctrl.document.structures:
				if Geometry2D.is_point_in_polygon(at, structure.footprint):
					inside += 1
					continue
				var grown := Geometry2D.offset_polygon(structure.footprint, 1.0)
				if not grown.is_empty() and Geometry2D.is_point_in_polygon(at, grown[0]):
					near += 1
	return "scatter rows %d, inside footprints %d, within 1 m outside %d" % [total, inside, near]


static func _editor(base: Node) -> AuthoringEditor:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	return ctrl.editor if ctrl != null else null


static func _nodes(base: Node) -> AuthoredStructures:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.map_root == null:
		return null
	return ctrl.map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures


static func _rect(width: float, depth: float, yaw_deg: float, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in [
		Vector2(-width, -depth),
		Vector2(width, -depth),
		Vector2(width, depth),
		Vector2(-width, depth)
	]:
		out.append((corner * 0.5).rotated(deg_to_rad(yaw_deg)) + at)
	return out


static func _l_shape(at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in [
		Vector2(-4, -3), Vector2(4, -3), Vector2(4, 0), Vector2(0, 0), Vector2(0, 3), Vector2(-4, 3)
	]:
		out.append(corner + at)
	return out


static func _town(base: Node) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var lines := PackedStringArray()
	for lot: Array in BASIC_LOTS:
		var plan := _rect(float(lot[3]), float(lot[4]), float(lot[5]), Vector2(lot[1], lot[2]))
		var structure := Structure.make(0, String(lot[0]), plan, int(lot[6]))
		if String(lot[0]) == "core:townhouse":
			structure.footprint = _l_shape(Vector2(lot[1], lot[2]))
		var id := editor.structures.add(structure)
		lines.append(
			"%s -> %d%s" % [lot[0], id, "" if id >= 0 else " " + editor.structures.last_refusal]
		)
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	return "laid: " + "; ".join(lines)


static func _street(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var a: Array = step.get("from", [-14, 12])
	var b: Array = step.get("to", [14, 12])
	var id := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(float(a[0]), 0, float(a[1])),
		Vector3(float(b[0]), 0, float(b[1])),
		-1.0,
		0.0,
		{"seed": 7, "side": 0, "preset": int(step.get("preset", 3))}
	)
	return "street %d" % id if id >= 0 else "refused: %s" % editor.walls.last_refusal


static func _flush(base: Node) -> String:
	var nodes := _nodes(base)
	return "flushed %d" % nodes.flush() if nodes != null else "no AuthoredStructures"


static func _report(base: Node) -> String:
	var nodes := _nodes(base)
	if nodes == null:
		return "no AuthoredStructures"
	var lines := PackedStringArray()
	for child in nodes.get_children():
		var tris := 0
		var meshes := PackedStringArray()
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			var array_mesh := (mesh as MeshInstance3D).mesh
			var count: int = (
				array_mesh.surface_get_array_index_len(0) / 3
				if array_mesh.get_surface_count() > 0
				else 0
			)
			tris += count
			meshes.append("%s %d" % [mesh.name, count])
		lines.append("%s tris %d [%s]" % [child.name, tris, ", ".join(meshes)])
	return "top_y %.2f notes %s; %s" % [nodes.top_y, str(nodes.notes), "; ".join(lines)]


static func _remove_all(base: Node) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var removed := 0
	for structure in editor.structures.list():
		if editor.structures.remove(structure.id):
			removed += 1
	return "removed %d" % removed
