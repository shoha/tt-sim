extends RefCounted

## Render-job probe (`call` op) for the decor plants of structures (topic polish3, the decor draw
## bake). step.action:
##   village {count}   lays `count` dressable buildings on a grid, asks each for ivy and flower
##                     boxes, and waits for the builds.
##   report            the decor nodes (MultiMeshInstance3D and baked MeshInstance3D), their
##                     instances, vertices, triangles and bytes, and the main-thread milliseconds one
##                     decorated building's _add_decor takes (best of three, summed over all).
## A new unsaved map only.

const REFS: Array[String] = [
	"core:cottage_chimneyed",
	"core:townhouse_timber",
	"core:stone_house",
	"core:townhouse_trimmed",
	"core:house_hip",
	"core:cottage_hip",
]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"village":
			return _village(base, step)
		"report":
			return _report(base)
		"assets":
			return _assets(base)
	return "unknown action %s" % step.get("action", "")


static func _ctrl(base: Node) -> AuthoringController:
	return base.get("_authoring_controller") as AuthoringController


static func _nodes(base: Node) -> AuthoredStructures:
	var ctrl := _ctrl(base)
	if ctrl == null or ctrl.map_root == null:
		return null
	return ctrl.map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures


static func _rect(width: float, depth: float, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner: Vector2 in [
		Vector2(-width, -depth),
		Vector2(width, -depth),
		Vector2(width, depth),
		Vector2(-width, depth)
	]:
		out.append(corner * 0.5 + at)
	return out


static func _village(base: Node, step: Dictionary) -> String:
	var ctrl := _ctrl(base)
	if ctrl == null:
		return "no authoring"
	var count := int(step.get("count", 30))
	var columns := int(ceil(sqrt(float(count))))
	var spacing := 80.0 / columns
	var laid := 0
	for k in count:
		var ref := REFS[k % REFS.size()]
		var row := LibraryStructureStore.structure(ref)
		var size: Array = row["default_size_m"]
		var fit := minf(1.0, (spacing - 2.0) / maxf(float(size[0]), float(size[1])))
		var at := Vector2(
			(float(k % columns) - (columns - 1) * 0.5) * spacing,
			(float(k / columns) - (columns - 1) * 0.5) * spacing
		)
		var id := ctrl.editor.structures.add(
			Structure.make(0, ref, _rect(float(size[0]) * fit, float(size[1]) * fit, at), 200 + k)
		)
		if id >= 0:
			ctrl.editor.structures.set_ornaments(id, ["ivy", "flower_boxes"], "decor probe")
			laid += 1
	var nodes := _nodes(base)
	if nodes == null:
		return "no structures node"
	nodes.flush()
	return "decor village laid %d of %d" % [laid, count]


static func _report(base: Node) -> String:
	var nodes := _nodes(base)
	if nodes == null:
		return "no structures node"
	var multis := 0
	var baked := 0
	var instances := 0
	var triangles := 0
	var vertices := 0
	var bytes := 0
	var decorated := 0
	for structure in nodes.get_children():
		var had := false
		for part in structure.get_children():
			if part is MultiMeshInstance3D:
				had = true
				multis += 1
				var multi := (part as MultiMeshInstance3D).multimesh
				instances += multi.instance_count
				triangles += _triangles(multi.mesh) * multi.instance_count
				vertices += _vertices(multi.mesh) * multi.instance_count
			elif part is MeshInstance3D and String(part.name).begins_with("decor"):
				had = true
				baked += 1
				var mesh := (part as MeshInstance3D).mesh
				triangles += _triangles(mesh)
				vertices += _vertices(mesh)
				bytes += _bytes(mesh)
		if had:
			decorated += 1
	# One building's _add_decor, on the main thread: best of three per cached build.
	var total_ms := 0.0
	var measured := 0
	for parts: Dictionary in nodes._cache.values():
		if not bool(parts.get("decor", false)) or (parts.get("anchors", []) as Array).is_empty():
			continue
		var best := INF
		for _try in 3:
			var holder := Node3D.new()
			var t0 := Time.get_ticks_usec()
			nodes._add_decor(holder, parts)
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
			holder.free()
		total_ms += best
		measured += 1
	return (
		"decor: %d decorated structures, %d multimesh nodes, %d baked nodes, %d plants, %d verts, %d tris, baked bytes %.2f MB; _add_decor %.2f ms per building over %d"
		% [
			decorated,
			multis,
			baked,
			instances,
			vertices,
			triangles,
			bytes / 1048576.0,
			total_ms / maxf(measured, 1),
			measured
		]
	)


static func _assets(base: Node) -> String:
	var nodes := _nodes(base)
	if nodes == null:
		return "no structures node"
	var lines: Array[String] = []
	for row: Dictionary in AssetStore.decor_rows(nodes._palette_root):
		var mesh: Mesh = nodes._decor_mesh(row)
		if mesh == null:
			lines.append("%s: no mesh" % row.local)
			continue
		var text := "%s (%s, wind %s):" % [row.local, row.kind, row.wind_category]
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var arrays := mesh.surface_get_arrays(surface)
			var cols := []
			for slot in arrays.size():
				if arrays[slot] != null:
					cols.append(slot)
			var shader := ""
			var tex := ""
			if material is ShaderMaterial:
				shader = (material as ShaderMaterial).shader.resource_path.get_file()
				var albedo: Variant = (material as ShaderMaterial).get_shader_parameter("albedo_texture")
				tex = "none"
				if albedo is Texture2D:
					var image := (albedo as Texture2D).get_image()
					tex = "%dx%d %s" % [
						image.get_width(), image.get_height(), image.get_data().hex_encode().sha256_text().substr(0, 8)
					]
			text += " [s%d %s %s tex %s cols %s verts %d mh %s uvw %s]" % [
				surface, material.get_class(), shader, tex, cols,
				(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				(material as ShaderMaterial).get_shader_parameter("mesh_height") if material is ShaderMaterial else "",
				(material as ShaderMaterial).get_shader_parameter("use_vertex_wind") if material is ShaderMaterial else "",
			]
		lines.append(text)
	return "
".join(lines)


static func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


static func _vertices(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		total += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


static func _bytes(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		for column: Variant in mesh.surface_get_arrays(surface):
			if column != null and not column is Object:
				total += var_to_bytes(column).size()
	return total
