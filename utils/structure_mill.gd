class_name StructureMill
extends RefCounted

## The moving parts of a windmill (procgen docs/style_range.md "Host contract"; topic range_look,
## 2026-10-30). procgen builds the sails and the cap as ordinary geometry in a fixed pose; the host
## cuts them out of the structure's meshes so a node can turn them, with no mesh rebuilt per frame:
##
##  - the WHEEL is every triangle whose first vertex is tagged `sails/...`; it turns about the axis
##    through the centroid of the `sails/hub` vertices, along the horizontal direction from the
##    tower's centre to the hub (the outward normal of the plan's first side turned by the style's
##    `yaw`, which is how procgen puts the hub there);
##  - the CAP is every triangle of the ROOF role (its own roofing material, not a gable end or an
##    accent) lying wholly at or above the top of the `windmill/curb` ring; it turns with the wheel
##    about the vertical axis through the tower's centre (the middle of the curb ring).
##
## Pure and thread-safe: it reads mesh dictionaries (StructureGeometry's) and returns new ones.

## The tag path ends (a path is "<node id>/<slot path>") the contract names.
const HUB_SLOT := "sails/hub"
const WHEEL_SLOT := "sails/"
const CURB_SLOT := "windmill/curb"
## A roof triangle counts as above the curb when its lowest vertex is within this of the curb's top.
const CURB_EPSILON_M := 0.02
## Shortest horizontal hub offset (metres) from the centre that still gives an axis.
const MIN_REACH_M := 0.05


## True when the provenance path `path` ends with the slot `slot` (a whole segment run).
static func is_slot(path: String, slot: String) -> bool:
	return ("/" + path).ends_with("/" + slot)


## True when the provenance path `path` lies under the slot group `group` (e.g. "sails/").
static func in_group(path: String, group: String) -> bool:
	return ("/" + path).contains("/" + group)


## The tag ids of `tag_table` whose path satisfies `test` (a Callable taking the path).
static func ids_where(tag_table: PackedStringArray, test: Callable) -> Dictionary:
	var out := {}
	for id in tag_table.size():
		if test.call(tag_table[id]):
			out[id] = true
	return out


## Cuts the moving parts out of `meshes` (StructureGeometry mesh dictionaries; `tag_table` names
## their tags). Returns {} when the structure has no sails hub (not a windmill) or no usable axis.
## Otherwise:
##   {"rest": meshes that stay, "wheel": meshes that turn about the axis, "cap": meshes that turn
##    with the cap, "hub": Vector3 (the wheel's pivot), "axis": Vector3 (horizontal, unit, from the
##    tower's centre toward the hub), "centre": Vector3 (the cap's pivot, y 0), "curb_top": float}
## `plan_centre` is the fallback tower centre when the style has no curb ring (then the cap stays
## fixed, as its height cannot be told; the wheel still turns).
static func split(
	meshes: Array, tag_table: PackedStringArray, plan_centre: Vector2 = Vector2.ZERO
) -> Dictionary:
	var hub_ids := ids_where(tag_table, func(p: String) -> bool: return is_slot(p, HUB_SLOT))
	if hub_ids.is_empty():
		return {}
	var wheel_ids := ids_where(tag_table, func(p: String) -> bool: return in_group(p, WHEEL_SLOT))
	var curb_ids := ids_where(tag_table, func(p: String) -> bool: return is_slot(p, CURB_SLOT))
	var hub_sum := Vector3.ZERO
	var hub_count := 0
	var curb_sum := Vector2.ZERO
	var curb_count := 0
	var curb_top := -INF
	for mesh: Dictionary in meshes:
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var tags: PackedInt32Array = mesh.tags
		for v in vertices.size():
			var tag := tags[v] if v < tags.size() else -1
			if hub_ids.has(tag):
				hub_sum += vertices[v]
				hub_count += 1
			elif curb_ids.has(tag):
				curb_sum += Vector2(vertices[v].x, vertices[v].z)
				curb_count += 1
				curb_top = maxf(curb_top, vertices[v].y)
	if hub_count == 0:
		return {}
	var hub := hub_sum / float(hub_count)
	var centre_xz := curb_sum / float(curb_count) if curb_count > 0 else plan_centre
	var reach := Vector2(hub.x - centre_xz.x, hub.z - centre_xz.y)
	if reach.length() < MIN_REACH_M:
		return {}
	var axis := Vector3(reach.x, 0.0, reach.y).normalized()
	var rest: Array = []
	var wheel: Array = []
	var cap: Array = []
	for mesh: Dictionary in meshes:
		var groups := _groups_of(mesh, wheel_ids, curb_top if curb_count > 0 else INF)
		for part: Array in [[groups.rest, rest], [groups.wheel, wheel], [groups.cap, cap]]:
			var picked: PackedInt32Array = part[0]
			if not picked.is_empty():
				(part[1] as Array).append(_subset(mesh, picked))
	return {
		"rest": rest,
		"wheel": wheel,
		"cap": cap,
		"hub": hub,
		"axis": axis,
		"centre": Vector3(centre_xz.x, 0.0, centre_xz.y),
		"curb_top": curb_top if curb_count > 0 else INF,
	}


## The triangle indices of `mesh` by group: {"rest", "wheel", "cap"} (each a PackedInt32Array of
## index triples). `cap_from` is the curb's top; INF turns no cap.
static func _groups_of(mesh: Dictionary, wheel_ids: Dictionary, cap_from: float) -> Dictionary:
	var indices: PackedInt32Array = mesh.arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
	var tags: PackedInt32Array = mesh.tags
	var roofing: bool = mesh.role == StructureLook.ROOF and mesh.kind != StructureLook.ACCENT_KIND
	var rest := PackedInt32Array()
	var wheel := PackedInt32Array()
	var cap := PackedInt32Array()
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var b := indices[t * 3 + 1]
		var c := indices[t * 3 + 2]
		var tag := tags[a] if a < tags.size() else -1
		var corners := PackedInt32Array([a, b, c])
		if wheel_ids.has(tag):
			wheel.append_array(corners)
		elif roofing and minf(vertices[a].y, minf(vertices[b].y, vertices[c].y)) >= (
			cap_from - CURB_EPSILON_M
		):
			cap.append_array(corners)
		else:
			rest.append_array(corners)
	return {"rest": rest, "wheel": wheel, "cap": cap}


## A new mesh dictionary holding the triangles `picked` (index triples into `mesh`'s vertices),
## vertices renumbered in their old order. Carries every array the source has.
static func _subset(mesh: Dictionary, picked: PackedInt32Array) -> Dictionary:
	var source: Array = mesh.arrays
	var vertices: PackedVector3Array = source[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = source[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = source[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = source[Mesh.ARRAY_COLOR]
	var tangents: PackedFloat32Array = source[Mesh.ARRAY_TANGENT]
	var tags: PackedInt32Array = mesh.tags
	var used := PackedByteArray()
	used.resize(vertices.size())
	for v in picked:
		used[v] = 1
	var remap := PackedInt32Array()
	remap.resize(vertices.size())
	var out_vertices := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var out_colors := PackedColorArray()
	var out_tangents := PackedFloat32Array()
	var out_tags := PackedInt32Array()
	for v in vertices.size():
		if used[v] == 0:
			continue
		remap[v] = out_vertices.size()
		out_vertices.append(vertices[v])
		out_normals.append(normals[v])
		out_uvs.append(uvs[v])
		out_colors.append(colors[v])
		if tangents.size() >= (v + 1) * 4:
			out_tangents.append_array(tangents.slice(v * 4, v * 4 + 4))
		out_tags.append(tags[v] if v < tags.size() else -1)
	var out_indices := PackedInt32Array()
	out_indices.resize(picked.size())
	for k in picked.size():
		out_indices[k] = remap[picked[k]]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_vertices
	arrays[Mesh.ARRAY_NORMAL] = out_normals
	arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	arrays[Mesh.ARRAY_COLOR] = out_colors
	arrays[Mesh.ARRAY_INDEX] = out_indices
	if not out_tangents.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = out_tangents
	return {"kind": mesh.kind, "role": mesh.role, "arrays": arrays, "tags": out_tags}
