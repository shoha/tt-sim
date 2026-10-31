class_name StructureCloth
extends RefCounted

## How far each vertex of a banner, pennant or awning may move in the wind (topic wind_c, 2026-10-30;
## docs/systems/structures.md "Cloth in the wind"). procgen draws the cloth as plain sheets tagged
## `ornament/banner<k>/cloth` and `ornament/awning<k>/stripe<n>`; the host writes a weight per vertex
## into the second UV set (x metres of reach from the attachment, y how far the piece leans downwind)
## and structure_ornament.gdshader moves the vertex by it under the global wind. The weight is derived
## from the piece's own shape, so procgen needs no change; the colour array is untouched, so
## StructureGeometry.digest_of (which hashes colours, not the second UV set) does not move.
##
## Pure and thread-safe (StructureGeometry.build_one calls it on a worker).

## The surface kind of cloth meshes (StructureLook.ORNAMENT_KINDS).
const KIND := "cloth"
## The y of a piece's weight: how much of the wind's push is a lean downwind.
const LEAN_FLAG := 1.0
const LEAN_HANGING := 0.6
const LEAN_AWNING := 0.0
## A piece at least this much longer than tall is a flag (pole at one end); otherwise it hangs.
const FLAG_RATIO := 1.2
## The share of a flag's length at each end that tells which end the pole holds.
const END_SHARE := 0.15
## The free end bends more than the middle: the weight along a piece is t to this power.
const CURVE := 1.5
## Shorter than this (metres) a piece has no usable direction and stays still.
const MIN_EXTENT_M := 0.05


## The group a tag path moves with, or "" when its cloth is not wind cloth: a banner's cloth is one
## group, an awning's stripes all form one (so the whole awning shares one attachment line).
static func group_of(path: String) -> String:
	var at := path.find("ornament/")
	if at < 0:
		return ""
	var parts := path.substr(at).split("/")
	if parts.size() >= 3 and parts[1].begins_with("banner") and parts[2] == "cloth":
		return path
	if parts.size() >= 3 and parts[1].begins_with("awning") and parts[2].begins_with("stripe"):
		return path.substr(0, at) + "ornament/" + parts[1]
	return ""


## Writes the weights into every `cloth` mesh of `meshes` (StructureGeometry mesh dictionaries that
## `tag_table` names the tags of), as the second UV set. Meshes and vertices of other pieces keep a
## zero weight (no motion).
static func attach(meshes: Array, tag_table: PackedStringArray) -> void:
	var group_of_tag := {}
	for id in tag_table.size():
		var group := group_of(tag_table[id])
		if group != "":
			group_of_tag[id] = group
	if group_of_tag.is_empty():
		return
	var points := {}
	for mesh: Dictionary in meshes:
		if mesh.kind != KIND:
			continue
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var tags: PackedInt32Array = mesh.tags
		for v in vertices.size():
			var group: String = group_of_tag.get(tags[v] if v < tags.size() else -1, "")
			if group == "":
				continue
			var held: PackedVector3Array = points.get(group, PackedVector3Array())
			held.append(vertices[v])
			points[group] = held
	if points.is_empty():
		return
	var weights := {}
	for group: String in points:
		weights[group] = weights_of(points[group], group.contains("/awning"))
	var cursor := {}
	for mesh: Dictionary in meshes:
		if mesh.kind != KIND:
			continue
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var tags: PackedInt32Array = mesh.tags
		var uv2 := PackedVector2Array()
		uv2.resize(vertices.size())
		for v in vertices.size():
			var group: String = group_of_tag.get(tags[v] if v < tags.size() else -1, "")
			if group == "":
				continue
			var k: int = cursor.get(group, 0)
			uv2[v] = (weights[group] as PackedVector2Array)[k]
			cursor[group] = k + 1
		mesh.arrays[Mesh.ARRAY_TEX_UV2] = uv2


## The weight of each of `points` (one piece, or one awning's stripes together): (metres of reach
## from the attachment, lean). `awning` takes the attachment as the wall edge (the outward direction
## is where the surface falls); otherwise a piece longer than tall is a flag held at the end with the
## taller edge, and any other piece hangs from its top edge.
static func weights_of(points: PackedVector3Array, awning: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	if points.size() < 3:
		return out
	var mean := Vector3.ZERO
	for p in points:
		mean += p
	mean /= float(points.size())
	var cxx := 0.0
	var czz := 0.0
	var cxz := 0.0
	var cxy := 0.0
	var czy := 0.0
	var y_min := INF
	var y_max := -INF
	for p in points:
		var d := p - mean
		cxx += d.x * d.x
		czz += d.z * d.z
		cxz += d.x * d.z
		cxy += d.x * d.y
		czy += d.z * d.y
		y_min = minf(y_min, p.y)
		y_max = maxf(y_max, p.y)
	if awning:
		var fall := Vector2(cxy, czy)
		if fall.length_squared() < 1e-12:
			return out
		var outward := -fall.normalized()
		return _from_distance(points, mean, outward, LEAN_AWNING)
	var axis_angle := 0.5 * atan2(2.0 * cxz, cxx - czz)
	var axis := Vector2(cos(axis_angle), sin(axis_angle))
	var s_min := INF
	var s_max := -INF
	for p in points:
		var s := (p.x - mean.x) * axis.x + (p.z - mean.z) * axis.y
		s_min = minf(s_min, s)
		s_max = maxf(s_max, s)
	var along := s_max - s_min
	var tall := y_max - y_min
	if along >= FLAG_RATIO * tall and along > MIN_EXTENT_M:
		var low_span := _span_at(points, mean, axis, s_min, s_min + along * END_SHARE)
		var high_span := _span_at(points, mean, axis, s_max - along * END_SHARE, s_max)
		# The pole holds the taller end; the weight grows away from it.
		var from_low := low_span >= high_span
		for k in points.size():
			var s := (points[k].x - mean.x) * axis.x + (points[k].z - mean.z) * axis.y
			var t := (s - s_min) / along if from_low else (s_max - s) / along
			out[k] = Vector2(along * pow(clampf(t, 0.0, 1.0), CURVE), LEAN_FLAG)
		return out
	if tall <= MIN_EXTENT_M:
		return out
	for k in points.size():
		var t := (y_max - points[k].y) / tall
		out[k] = Vector2(tall * pow(clampf(t, 0.0, 1.0), CURVE), LEAN_HANGING)
	return out


## Weights by distance along `direction` (xz) from the nearest point, for a piece attached at its
## near end.
static func _from_distance(
	points: PackedVector3Array, mean: Vector3, direction: Vector2, lean: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	var d_min := INF
	var d_max := -INF
	for p in points:
		var d := (p.x - mean.x) * direction.x + (p.z - mean.z) * direction.y
		d_min = minf(d_min, d)
		d_max = maxf(d_max, d)
	var extent := d_max - d_min
	if extent <= MIN_EXTENT_M:
		return out
	for k in points.size():
		var d := (points[k].x - mean.x) * direction.x + (points[k].z - mean.z) * direction.y
		out[k] = Vector2(extent * pow(clampf((d - d_min) / extent, 0.0, 1.0), CURVE), lean)
	return out


## The vertical span (metres) of the points whose position along `axis` lies in [from, to].
static func _span_at(
	points: PackedVector3Array, mean: Vector3, axis: Vector2, from: float, to: float
) -> float:
	var lo := INF
	var hi := -INF
	for p in points:
		var s := (p.x - mean.x) * axis.x + (p.z - mean.z) * axis.y
		if s >= from and s <= to:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	return hi - lo if hi >= lo else 0.0
