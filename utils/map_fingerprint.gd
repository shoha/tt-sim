class_name MapFingerprint
extends RefCounted

## A comparable summary of a built map: what two peers compare to prove they built the same
## map from the same map.ttmap (the authored-map parity scenario over real Steam,
## tests/net/steam_authored_parity.gd). Pure: it reads the map root and its document and
## changes nothing, and works on a root outside the tree (transforms are accumulated from
## the root down, never read globally).
##
## Every float is rounded to ROUND_M (1 mm) before it is printed or hashed, so float noise
## between two builds cannot fail a comparison while any real difference (a moved vertex, a
## missing row) still does. Values are strings, ints and arrays of them, so the dictionary
## survives a JSON round trip; diff() compares through one so ints parsed back as floats
## still match.
##
## Keys:
##   heights        the document's height samples: "<count> <sha prefix>".
##   water          per body, by id: "<id> <kind> <depth> <level>".
##   falls          per fall (the falls mesh's curtain vertices grouped by the fall's height
##                  and lower level, which its UV2 carries): "<verts> <aabb>", sorted.
##   falls_count    how many falls that grouping found.
##   crossings      per AuthoredCrossings child: "<name> <kind> <verts> <aabb>".
##   edge           the skirt's river-exit parts: "<name> <verts>" for Channel and Ribbon,
##                  or [] when no water leaves the map.
##   scatter        per asset in every AuthoredScatter: "<asset> <rows>", sorted.
##   scatter_hash   every scatter row value, rounded, hashed.
##   mesh_vertices  the vertex count of every MeshInstance3D under the root.

## Floats are rounded to this before printing or hashing.
const ROUND_M := 0.001
## Hex digits kept from a SHA-256.
const HASH_CHARS := 16
const CROSSINGS_NODE := "AuthoredCrossings"
const WATER_NODE := "AuthoredWater"
const FALLS_MESH := "AuthoredWater-falls"
const EDGE_NAMES: Array[String] = ["Channel", "Ribbon"]
## A crossing node's mesh child names and the kind each means; a node with only "Wood" is a
## plank bridge.
const CROSSING_KINDS := {"Arch": "arch", "Ford": "ford", "Stones": "stones", "Wood": "plank"}
## The falls mesh's COLOR.g below this is a curtain vertex (WaterFallMesh.KIND_CURTAIN 0).
const CURTAIN_G_MAX := 0.25


## The fingerprint of map root `root` built from `doc` (either may be null).
static func of(root: Node, doc: MapDocument) -> Dictionary:
	var out := {
		"heights": "",
		"water": [],
		"falls": [],
		"falls_count": 0,
		"crossings": [],
		"edge": [],
		"scatter": [],
		"scatter_hash": "",
		"mesh_vertices": 0,
	}
	if doc != null:
		out.heights = _heights(doc)
		out.water = _water(doc)
	if root == null:
		return out
	var meshes: Array = []
	_collect_meshes(root, Transform3D.IDENTITY, meshes)
	var total := 0
	for entry: Array in meshes:
		total += _vertex_count((entry[0] as MeshInstance3D).mesh)
	out.mesh_vertices = total
	out.falls = _falls(root)
	out.falls_count = (out.falls as Array).size()
	out.crossings = _crossings(root)
	out.edge = _edge(meshes)
	var scatter := _scatter(root)
	out.scatter = scatter[0]
	out.scatter_hash = scatter[1]
	return out


## The keys whose values differ between fingerprints `a` and `b` (compared after a JSON round
## trip), sorted; [] when they match.
static func diff(a: Dictionary, b: Dictionary) -> Array[String]:
	var keys := {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	var out: Array[String] = []
	for k in keys:
		if _normal(a.get(k)) != _normal(b.get(k)):
			out.append(String(k))
	out.sort()
	return out


## `value` as JSON text after a JSON round trip (ints and floats print alike).
static func _normal(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


## `v` rounded to ROUND_M and printed (a rounded -0 prints as 0).
static func mm(v: float) -> String:
	var rounded := snappedf(v, ROUND_M)
	return "%.3f" % (0.0 if rounded == 0.0 else rounded)


## `box` printed at mm precision: "(x y z)+(w h d)".
static func aabb_text(box: AABB) -> String:
	return (
		"(%s %s %s)+(%s %s %s)"
		% [
			mm(box.position.x),
			mm(box.position.y),
			mm(box.position.z),
			mm(box.size.x),
			mm(box.size.y),
			mm(box.size.z),
		]
	)


## The first HASH_CHARS hex digits of the SHA-256 of `values` rounded to ROUND_M.
static func hash_floats(values: PackedFloat32Array) -> String:
	var ints := PackedInt32Array()
	ints.resize(values.size())
	for i in values.size():
		ints[i] = roundi(values[i] / ROUND_M)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not ints.is_empty():
		ctx.update(ints.to_byte_array())
	return ctx.finish().hex_encode().substr(0, HASH_CHARS)


static func _heights(doc: MapDocument) -> String:
	return "%d %s" % [doc.heights.size(), hash_floats(doc.heights)]


static func _water(doc: MapDocument) -> Array:
	var out: Array = []
	for body in doc.water_bodies:
		out.append(
			(
				"%d %s %d %s"
				% [body.id, WaterBody.KIND_NAMES[body.kind], int(body.depth), mm(body.level_m)]
			)
		)
	out.sort()
	return out


## [MeshInstance3D, its transform relative to the root] for every mesh instance under `node`.
static func _collect_meshes(node: Node, xform: Transform3D, out: Array) -> void:
	for child in node.get_children():
		var child_xform := xform
		if child is Node3D:
			child_xform = xform * (child as Node3D).transform
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append([child, child_xform])
		_collect_meshes(child, child_xform, out)


static func _vertex_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh:
			total += (mesh as ArrayMesh).surface_get_array_len(s)
		else:
			var arrays := mesh.surface_get_arrays(s)
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


## The transform of `node` relative to `root` (identity when it is not under it).
static func _relative(root: Node, node: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var at := node
	while at != null and at != root:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


## Per fall: "<curtain verts> <curtain aabb>", grouping the curtain vertices by UV2 (the
## fall's height and lower level, one pair per fall).
static func _falls(root: Node) -> Array:
	var water := root.get_node_or_null(NodePath(WATER_NODE))
	var node := water.get_node_or_null(NodePath(FALLS_MESH)) if water else null
	if not node is MeshInstance3D or (node as MeshInstance3D).mesh == null:
		return []
	var mesh := (node as MeshInstance3D).mesh
	var xform := _relative(root, node)
	var groups := {}
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = (
			arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		)
		var uv2s: PackedVector2Array = (
			arrays[Mesh.ARRAY_TEX_UV2]
			if arrays[Mesh.ARRAY_TEX_UV2] != null
			else PackedVector2Array()
		)
		if colors.size() != vertices.size() or uv2s.size() != vertices.size():
			continue
		for i in vertices.size():
			if colors[i].g >= CURTAIN_G_MAX:
				continue
			var key := "%s %s" % [mm(uv2s[i].x), mm(uv2s[i].y)]
			var at := xform * vertices[i]
			if groups.has(key):
				groups[key][0] += 1
				groups[key][1] = (groups[key][1] as AABB).expand(at)
			else:
				groups[key] = [1, AABB(at, Vector3.ZERO)]
	var out: Array = []
	for key in groups:
		out.append("%d %s" % [groups[key][0], aabb_text(groups[key][1])])
	out.sort()
	return out


## Per crossing node: "<name> <kind> <verts> <aabb of its meshes>".
static func _crossings(root: Node) -> Array:
	var holder := root.get_node_or_null(NodePath(CROSSINGS_NODE))
	if holder == null:
		return []
	var out: Array = []
	for crossing in holder.get_children():
		var meshes: Array = []
		_collect_meshes(crossing, _relative(root, crossing), meshes)
		var kind := ""
		var verts := 0
		var box := AABB()
		var first := true
		for entry: Array in meshes:
			var instance := entry[0] as MeshInstance3D
			var name := String(instance.name)
			if CROSSING_KINDS.has(name) and (kind == "" or kind == "plank"):
				kind = CROSSING_KINDS[name]
			verts += _vertex_count(instance.mesh)
			var part := (entry[1] as Transform3D) * instance.mesh.get_aabb()
			box = part if first else box.merge(part)
			first = false
		out.append("%s %s %d %s" % [crossing.name, kind, verts, aabb_text(box)])
	out.sort()
	return out


## "<name> <verts>" for each river-exit part (EDGE_NAMES) among `meshes`.
static func _edge(meshes: Array) -> Array:
	var out: Array = []
	for entry: Array in meshes:
		var instance := entry[0] as MeshInstance3D
		if String(instance.name) in EDGE_NAMES:
			out.append("%s %d" % [instance.name, _vertex_count(instance.mesh)])
	out.sort()
	return out


## [["<asset> <rows>", ...] sorted, the hash of every row value] over every node under
## `root` that answers rows_by_asset() (AuthoredScatter).
static func _scatter(root: Node) -> Array:
	var rows := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != root and node.has_method("rows_by_asset"):
			var by_asset: Dictionary = node.call("rows_by_asset")
			for asset_id in by_asset:
				# Packed arrays are values: append to a copy and store it back.
				var joined: PackedFloat32Array = rows.get(asset_id, PackedFloat32Array())
				joined.append_array(by_asset[asset_id])
				rows[asset_id] = joined
			continue
		stack.append_array(node.get_children())
	var ids := rows.keys()
	ids.sort()
	var counts: Array = []
	var all := PackedFloat32Array()
	for asset_id in ids:
		var flat: PackedFloat32Array = rows[asset_id]
		counts.append("%s %d" % [asset_id, flat.size() / MapDocument.ROW_STRIDE])
		all.append_array(flat)
	return [counts, hash_floats(all)]
