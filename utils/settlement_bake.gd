class_name SettlementBake
extends RefCounted

## Pure: the furnishings of one cell (a list of placements) merged into a few surfaces, one per
## material, so a whole stretch of street is one mesh with a handful of draws. The same idea as
## StructureDecor.bake (arrays in, arrays out, a worker may run it) but for the prop meshes of
## StructureGeometry.build_one, which also carry the cloth wind weights in the second UV set.
## A source is {"surfaces": [{"key": "<role>:<kind>", "role", "kind", "arrays": Mesh arrays}]}.


## Props are drawn this much larger than the plan's metres (tabletop exaggeration, as decor plants
## are): at the home camera a barrel at true size is a speck. The plan (and its digests) keep true
## size; only the drawn mesh grows, about the prop's origin.
const PROP_VISUAL_SCALE := 1.35
## A prop beside a door or an entrance (slot ids with "/d" or "/e", as the plan's own clearance
## rule reads them) grows only this much, so the door's path stays as wide as the plan made it.
const DOOR_VISUAL_SCALE := 1.12
## The most a drawn prop may be scaled, whatever the placement asks for.
const MAX_VISUAL_SCALE := 1.7
## A prop leans toward the ground's normal by at most this many degrees.
const TILT_MAX_DEG := 12.0
## The material kinds a prop's surfaces keep apart: StructureMaterials.prop gives every other kind
## (wood, accent, thatch, boards ...) the same shader and parameters (the colour is in the
## vertices), so they share one surface and one draw.
const DISTINCT_KINDS: Array[String] = ["leaf", "leaf_b", "metal", "cloth", "stone", "glass"]


## The drawn scale of placement `item`: its own scale times PROP_VISUAL_SCALE (DOOR_VISUAL_SCALE
## beside a door), clamped to MAX_VISUAL_SCALE and never below the placement's own scale.
static func visual_scale(item: Dictionary) -> float:
	var own := float(item["scale"])
	var slot := String(item.get("slot", ""))
	var factor := (
		DOOR_VISUAL_SCALE if slot.contains("/d") or slot.contains("/e") else PROP_VISUAL_SCALE
	)
	return maxf(minf(own * factor, MAX_VISUAL_SCALE), own)


## The rotation that leans +y toward `normal` by at most `max_deg` degrees: the identity on flat
## ground, never a flip (a normal that points down, or zero, is the identity).
static func tilt_of(normal: Vector3, max_deg: float = TILT_MAX_DEG) -> Basis:
	if normal.length() < 0.0001 or normal.y <= 0.0:
		return Basis.IDENTITY
	var n := normal.normalized()
	var axis := Vector3.UP.cross(n)
	if axis.length() < 0.0001:
		return Basis.IDENTITY
	var angle := minf(acos(clampf(n.y, -1.0, 1.0)), deg_to_rad(max_deg))
	return Basis(axis.normalized(), angle)


## The kind whose material draws a surface of `kind` in `role`: itself, or "wood" for the prop kinds
## that look the same.
static func look_kind(role: String, kind: String) -> String:
	if role != StructureLook.PROP or DISTINCT_KINDS.has(kind):
		return kind
	return "wood"


## The world transform of placement `item` standing at height `y` on ground of `normal`: yaw about
## +y (the prop's front +z turns to (sin yaw, cos yaw)), the drawn scale (visual_scale), leaned
## toward the ground (tilt_of), at map XZ.
static func transform_of(
	item: Dictionary, y: float, normal: Vector3 = Vector3.UP
) -> Transform3D:
	var at: Vector2 = item["position"]
	var basis := (
		tilt_of(normal)
		* Basis(Vector3.UP, float(item["yaw"])).scaled(Vector3.ONE * visual_scale(item))
	)
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
			var kind := look_kind(String(surface["role"]), String(surface["kind"]))
			var key := "%s:%s" % [surface["role"], kind]
			if not by_key.has(key):
				by_key[key] = {
					"key": key,
					"role": surface["role"],
					"kind": kind,
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
