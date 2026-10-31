class_name StructureVane
extends RefCounted

## The turning parts of a weathervane (topic wind_c, 2026-10-30; procgen docs/architecture_styles.md
## section 8). procgen draws the vane in one fixed pose, tagged `ornament/vane/{base, pole, cross0,
## cross1, shaft, arrow, tail, ball_top, ball_bottom}`; the host cuts the shaft, arrow and tail
## out of the structure's meshes so a node (VaneMotion) can yaw them about the pole in the wind.
## The base, pole, crossbars and balls stay put (a crossbar is the compass and does not turn). The
## cut runs when the node is made, on the mesh dictionaries StructureGeometry built, which it does
## not change: the digest and the triangle count still cover the whole vane.
##
## Pure and thread-safe.

const TURNING_SLOTS: Array[String] = [
	"ornament/vane/shaft", "ornament/vane/arrow", "ornament/vane/tail"
]
const POLE_SLOT := "ornament/vane/pole"
const ARROW_SLOT := "ornament/vane/arrow"
const TAIL_SLOT := "ornament/vane/tail"
## The pole's vertices must lie within this of their centre (horizontally), else the structure holds
## more than one vane and none turns.
const MAX_POLE_SPREAD_M := 0.1


## The tag ids of `tag_table` whose path ends with the vane slot `slot`.
static func _ids_of(tag_table: PackedStringArray, slots: Array[String]) -> Dictionary:
	var out := {}
	for id in tag_table.size():
		for slot in slots:
			if ("/" + tag_table[id]).ends_with("/" + slot):
				out[id] = true
	return out


## Cuts the vane's turning parts out of `meshes`. {} when the structure has no vane with an arrow
## (or more than one). Otherwise:
##   {"rest": meshes without the turning triangles, "turning": the turning meshes,
##    "pivot": Vector3 (the pole's centre in x and z, y at the pole's middle),
##    "tip": Vector3 (horizontal, unit: where the arrow points, as built)}
static func split(meshes: Array, tag_table: PackedStringArray) -> Dictionary:
	var arrow_ids := _ids_of(tag_table, [ARROW_SLOT])
	if arrow_ids.is_empty():
		return {}
	var turning_ids := _ids_of(tag_table, TURNING_SLOTS)
	var pole_ids := _ids_of(tag_table, [POLE_SLOT])
	var tail_ids := _ids_of(tag_table, [TAIL_SLOT])
	var pole := PackedVector3Array()
	var arrow_sum := Vector3.ZERO
	var arrow_count := 0
	var tail_sum := Vector3.ZERO
	var tail_count := 0
	for mesh: Dictionary in meshes:
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var tags: PackedInt32Array = mesh.tags
		for v in vertices.size():
			var tag := tags[v] if v < tags.size() else -1
			if pole_ids.has(tag):
				pole.append(vertices[v])
			elif arrow_ids.has(tag):
				arrow_sum += vertices[v]
				arrow_count += 1
			elif tail_ids.has(tag):
				tail_sum += vertices[v]
				tail_count += 1
	if pole.is_empty() or arrow_count == 0 or tail_count == 0:
		return {}
	var centre := Vector3.ZERO
	for p in pole:
		centre += p
	centre /= float(pole.size())
	for p in pole:
		if Vector2(p.x - centre.x, p.z - centre.z).length() > MAX_POLE_SPREAD_M:
			return {}
	var along := arrow_sum / float(arrow_count) - tail_sum / float(tail_count)
	along.y = 0.0
	if along.length_squared() < 0.000001:
		return {}
	var rest: Array = []
	var turning: Array = []
	for mesh: Dictionary in meshes:
		var indices: PackedInt32Array = mesh.arrays[Mesh.ARRAY_INDEX]
		var tags: PackedInt32Array = mesh.tags
		var kept := PackedInt32Array()
		var cut := PackedInt32Array()
		for t in indices.size() / 3:
			var a := indices[t * 3]
			var tag := tags[a] if a < tags.size() else -1
			var corners := PackedInt32Array([a, indices[t * 3 + 1], indices[t * 3 + 2]])
			if turning_ids.has(tag):
				cut.append_array(corners)
			else:
				kept.append_array(corners)
		if cut.is_empty():
			rest.append(mesh)
			continue
		turning.append(StructureMill.subset(mesh, cut))
		if not kept.is_empty():
			rest.append(StructureMill.subset(mesh, kept))
	return {
		"rest": rest,
		"turning": turning,
		"pivot": centre,
		"tip": along.normalized(),
	}
