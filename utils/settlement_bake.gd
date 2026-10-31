class_name SettlementBake
extends RefCounted

## Pure: the furnishings of one cell (a list of placements) merged into a few surfaces, one per
## material, so a whole stretch of street is one mesh with a handful of draws. The same idea as
## StructureDecor.bake (arrays in, arrays out, a worker may run it) but for the prop meshes of
## StructureGeometry.build_one, which also carry the cloth wind weights in the second UV set.
## A source is {"surfaces": [{"key": "<role>:<kind>", "role", "kind", "arrays": Mesh arrays}]}.


## The world transform of placement `item` standing at height `y`: yaw about +y (the prop's front
## +z turns to (sin yaw, cos yaw)), uniform scale, at map XZ.
static func transform_of(item: Dictionary, y: float) -> Transform3D:
	var at: Vector2 = item["position"]
	var basis := Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * float(item["scale"]))
	return Transform3D(basis, Vector3(at.x, y, at.y))


## `placed` ([{"variant": source key, "transform": Transform3D}]) baked against `sources`
## ({source key: {"surfaces": [...]}}): [{"key", "role", "kind", "arrays"}] sorted by key. A
## placement whose source is missing is left out.
static func bake(placed: Array[Dictionary], sources: Dictionary) -> Array[Dictionary]:
	var by_key := {}
	for item in placed:
		var source: Variant = sources.get(item["variant"])
		if not source is Dictionary:
			continue
		var transform: Transform3D = item["transform"]
		var turn := Transform3D(transform.basis.orthonormalized(), Vector3.ZERO)
		for surface: Dictionary in source["surfaces"]:
			var key := String(surface["key"])
			if not by_key.has(key):
				by_key[key] = {
					"key": key,
					"role": surface["role"],
					"kind": surface["kind"],
					"vertices": PackedVector3Array(),
					"normals": PackedVector3Array(),
					"colors": PackedColorArray(),
					"uvs": PackedVector2Array(),
					"uv2s": PackedVector2Array(),
					"indices": PackedInt32Array(),
					"has_uv2": false,
				}
			_append(by_key[key], surface["arrays"], transform, turn)
	var keys: Array = by_key.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for key: String in keys:
		var into: Dictionary = by_key[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = into["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = into["normals"]
		arrays[Mesh.ARRAY_COLOR] = into["colors"]
		arrays[Mesh.ARRAY_TEX_UV] = into["uvs"]
		if bool(into["has_uv2"]):
			arrays[Mesh.ARRAY_TEX_UV2] = into["uv2s"]
		arrays[Mesh.ARRAY_INDEX] = into["indices"]
		out.append({"key": key, "role": into["role"], "kind": into["kind"], "arrays": arrays})
	return out


## The triangles of baked `surfaces`.
static func triangle_count(surfaces: Array[Dictionary]) -> int:
	var total := 0
	for surface in surfaces:
		total += (surface["arrays"][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


static func _append(
	into: Dictionary, arrays: Array, transform: Transform3D, turn: Transform3D
) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var count := vertices.size()
	var all_vertices: PackedVector3Array = into["vertices"]
	var base := all_vertices.size()
	all_vertices.append_array(transform * vertices)
	into["vertices"] = all_vertices
	var all_normals: PackedVector3Array = into["normals"]
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	if normals is PackedVector3Array and (normals as PackedVector3Array).size() == count:
		all_normals.append_array(turn * (normals as PackedVector3Array))
	else:
		var up := PackedVector3Array()
		up.resize(count)
		up.fill(Vector3.UP)
		all_normals.append_array(up)
	into["normals"] = all_normals
	var all_colors: PackedColorArray = into["colors"]
	var colors: Variant = arrays[Mesh.ARRAY_COLOR]
	if colors is PackedColorArray and (colors as PackedColorArray).size() == count:
		all_colors.append_array(colors)
	else:
		var white := PackedColorArray()
		white.resize(count)
		white.fill(Color.WHITE)
		all_colors.append_array(white)
	into["colors"] = all_colors
	var all_uvs: PackedVector2Array = into["uvs"]
	var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if uvs is PackedVector2Array and (uvs as PackedVector2Array).size() == count:
		all_uvs.append_array(uvs)
	else:
		var blank_uv := PackedVector2Array()
		blank_uv.resize(count)
		all_uvs.append_array(blank_uv)
	into["uvs"] = all_uvs
	var all_uv2: PackedVector2Array = into["uv2s"]
	var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
	if uv2 is PackedVector2Array and (uv2 as PackedVector2Array).size() == count:
		if not bool(into["has_uv2"]):
			# Earlier surfaces had none: their vertices get zero weights.
			all_uv2.resize(base)
			into["has_uv2"] = true
		all_uv2.append_array(uv2)
	elif bool(into["has_uv2"]):
		var blank := PackedVector2Array()
		blank.resize(count)
		all_uv2.append_array(blank)
	into["uv2s"] = all_uv2
	var all_indices: PackedInt32Array = into["indices"]
	var shifted: PackedInt32Array = arrays[Mesh.ARRAY_INDEX].duplicate()
	for i in shifted.size():
		shifted[i] += base
	all_indices.append_array(shifted)
	into["indices"] = all_indices
