class_name StructureCollapse
extends RefCounted

## How a burnt building comes down (card painter-fire-polish; StructureBurn plays it): broken into
## rigid charred pieces that sag, fall and settle, never squashed or cut open.
##
## The pieces. A building's parts (its `<role>_<kind>` meshes, as AuthoredStructures built them) are
## cut by a few planes in its own frame (frame_of: the footprint's long axis and half sizes): one
## level at STUMP of its height, one down the ridge, and SEGMENT_M apart across it, each cut leaning
## a little off square (seeded), so the pieces are broken slabs rather than tidy tiles. Below the
## level is the stump, which stays standing. Above it, a roof triangle goes to a roof slab (its
## side of the ridge, its segment), anything else to a wall piece (the long walls by side and
## segment, the end walls by end and side of the ridge): every part on one stretch of wall
## (plaster, timber, glass) falls as one. Each piece is drawn from both faces (the cut opens the
## parts' closed solids, and a slab turns over as it falls), so nothing shows through it. The cut
## is pure data (split) and runs on a worker; install makes the nodes on the main thread.
##
## The motion (pose, pure). Over a collapse (StructureBurn.collapse_amount, 0 to 1):
## - the sag, to SAG_END: each roof slab turns about its eave so its ridge drops, the middle of the
##   ridge furthest, while the walls bow out;
## - the fall, from SAG_END (plus a small seeded delay a piece) to FALL_END: the slabs fall in,
##   turning on toward lying flat and sliding into the footprint, the walls topple (most outward),
##   each dropping with gathering speed and a little twist;
## - the settle, to the end: one small bounce and rock back, then rest.

## The share of a building's height that stands as its stump.
const STUMP := 0.24
## About how long a slab or a stretch of wall is along the building, metres; at most MAX_SEGMENTS.
const SEGMENT_M := 3.2
const MAX_SEGMENTS := 3
## The most a cut across the building leans off square, radians.
const CUT_TILT := 0.24
## Where in the collapse the sag ends, and where every piece is down.
const SAG_END := 0.3
const FALL_END := 0.8
## A roof slab's sag (radians, at the ends of the ridge and in its middle) and how far past its
## pitch it may turn as it lands (a share of the pitch).
const SAG_ROOF := Vector2(0.14, 0.32)
const LAND_TURN := Vector2(0.85, 1.3)
## How far a wall piece bows before it goes, and how far it topples (radians); the share that falls
## outward.
const BOW := Vector2(0.03, 0.07)
const TOPPLE := Vector2(1.05, 1.5)
const OUTWARD := 0.7
## The settle's bounce (a share of the building's height, held between the two metres) and rock.
const BOUNCE := 0.035
const BOUNCE_M := Vector2(0.06, 0.22)
const ROCK := Vector2(0.04, 0.09)
## A piece that comes down this close to the ground starts no lower than this share of the height.
const HEAP := Vector2(0.04, 0.12)
## A piece's name under its structure node, and where it waits (far under the ground, never in
## view) until the collapse.
const PIECE_NAME := "Collapse_%d"
const PARKED := Transform3D(Basis.IDENTITY, Vector3(0.0, -1000.0, 0.0))


## A triangle soup for one (piece, part): positions, normals, tangents (four floats each), colours
## and UVs, each present when the source has it.
class Soup:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	## Adds one vertex of `src` (index `i`), its normal turned over when `back`.
	func take(src: Soup, i: int, back: bool) -> void:
		v.append(src.v[i])
		if not src.n.is_empty():
			n.append(-src.n[i] if back else src.n[i])
		if not src.t.is_empty():
			for k in 4:
				t.append(src.t[i * 4 + k])
		if not src.c.is_empty():
			c.append(src.c[i])
		if not src.uv.is_empty():
			uv.append(src.uv[i])

	## Adds a vertex `w` of the way from `src`'s vertex `a` to `b` to this soup; returns its index.
	func mix(a: int, b: int, w: float) -> int:
		v.append(v[a].lerp(v[b], w))
		if not n.is_empty():
			n.append(n[a].lerp(n[b], w).normalized())
		if not t.is_empty():
			for k in 4:
				t.append(lerpf(t[a * 4 + k], t[b * 4 + k], w))
		if not c.is_empty():
			c.append(c[a].lerp(c[b], w))
		if not uv.is_empty():
			uv.append(uv[a].lerp(uv[b], w))
		return v.size() - 1

	## The mesh arrays (Mesh.ARRAY_MAX long, no index: a plain triangle list).
	func arrays() -> Array:
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = v
		if not n.is_empty():
			out[Mesh.ARRAY_NORMAL] = n
		if not t.is_empty():
			out[Mesh.ARRAY_TANGENT] = t
		if not c.is_empty():
			out[Mesh.ARRAY_COLOR] = c
		if not uv.is_empty():
			out[Mesh.ARRAY_TEX_UV] = uv
		return out


## A building's frame from its footprint (map XZ): {"axis": the unit direction of its longest edge,
## "half": its half sizes along that and across it, "middle": the middle of that box}. Pure.
static func frame_of(footprint: PackedVector2Array) -> Dictionary:
	var axis := Vector2.RIGHT
	var longest := 0.0
	for i in footprint.size():
		var edge := footprint[(i + 1) % footprint.size()] - footprint[i]
		if edge.length() > longest + 0.01:
			longest = edge.length()
			axis = edge.normalized()
	if axis.x < 0.0 or (is_zero_approx(axis.x) and axis.y < 0.0):
		axis = -axis
	var across := Vector2(-axis.y, axis.x)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in footprint:
		var local := Vector2(p.dot(axis), p.dot(across))
		lo = lo.min(local)
		hi = hi.max(local)
	if footprint.is_empty():
		return {"axis": axis, "half": Vector2.ONE, "middle": Vector2.ZERO}
	var mid := (lo + hi) * 0.5
	return {"axis": axis, "half": (hi - lo) * 0.5, "middle": axis * mid.x + across * mid.y}


## How many segments a building `half_long` metres half long is cut into. Pure.
static func segments(half_long: float) -> int:
	return clampi(roundi(half_long * 2.0 / SEGMENT_M), 1, MAX_SEGMENTS)


## The cutting planes of a building in `frame` ({"centre": its foot's middle, Vector3; "axis": a
## horizontal unit Vector3; "half": Vector2; "height"; "seed"}), in its node's frame: the stump's
## level, the ridge's, then the cuts across in order along the axis. Pure.
static func planes_of(frame: Dictionary) -> Array[Plane]:
	var centre: Vector3 = frame.centre
	var axis: Vector3 = frame.axis
	var half: Vector2 = frame.half
	var across := Vector3.UP.cross(axis)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(frame.seed)
	var out: Array[Plane] = []
	out.append(Plane(Vector3.UP, centre.y + STUMP * float(frame.height)))
	var ridge := across.rotated(Vector3.UP, rng.randf_range(-0.5, 0.5) * CUT_TILT * 0.5)
	out.append(Plane(ridge, ridge.dot(centre)))
	var count := segments(half.x)
	for i in range(1, count):
		var at := centre + axis * (-half.x + 2.0 * half.x * float(i) / float(count))
		var normal := axis.rotated(Vector3.UP, rng.randf_range(-1.0, 1.0) * CUT_TILT)
		out.append(Plane(normal, normal.dot(at)))
	return out


## The piece a point `c` (node frame) of a roof part (`roof`) or another part falls with, by the
## planes (planes_of) and the frame: 0 the stump, then the roof slabs, the end walls, the long
## walls. Pure.
static func piece_of(c: Vector3, roof: bool, planes: Array[Plane], frame: Dictionary) -> int:
	if not planes[0].is_point_over(c):
		return 0
	var count := planes.size() - 1
	var segment := 0
	for i in range(2, planes.size()):
		if planes[i].is_point_over(c):
			segment += 1
	var side := 1 if planes[1].is_point_over(c) else 0
	if roof:
		return 1 + side * count + segment
	var axis: Vector3 = frame.axis
	var half: Vector2 = frame.half
	var rel := c - (frame.centre as Vector3)
	var u := rel.dot(axis)
	var w := rel.dot(Vector3.UP.cross(axis))
	if absf(u) / maxf(half.x, 0.1) > absf(w) / maxf(half.y, 0.1):
		return 1 + 2 * count + (2 if u > 0.0 else 0) + side
	return 1 + 2 * count + 4 + side * count + segment


## Splits `parts` ([{"arrays": a surface's mesh arrays, "to_node": Transform3D, "roof": bool}]) of a
## building in `frame` (planes_of's) into its pieces: [{"key", "roof", "stump", "surfaces":
## [{"part": the index in `parts`, "arrays"}], and the motion: "pivot", "tip", "sag", "angle",
## "drop", "slide", "twist", "delay", "bounce", "rock"}], the stump first. Pure (runs on a worker).
static func split(parts: Array, frame: Dictionary) -> Array[Dictionary]:
	var planes := planes_of(frame)
	var soups: Dictionary = {}
	for index in parts.size():
		var part: Dictionary = parts[index]
		var src := _soup_of(part.arrays, part.to_node)
		var indices: Variant = (part.arrays as Array)[Mesh.ARRAY_INDEX]
		var order: PackedInt32Array = indices if indices is PackedInt32Array else PackedInt32Array()
		var count := order.size() if not order.is_empty() else src.v.size()
		for tri in range(0, count - 2, 3):
			var corners := PackedInt32Array()
			for k in 3:
				corners.append(order[tri + k] if not order.is_empty() else tri + k)
			_cut(src, corners, planes, frame, bool(part.roof), index, soups)
	var out: Array[Dictionary] = []
	var keys := soups.keys()
	keys.sort()
	var by_piece: Dictionary = {}
	for key: int in keys:
		var piece := key >> 8
		if not by_piece.has(piece):
			by_piece[piece] = {"key": piece, "surfaces": []}
			out.append(by_piece[piece])
		(by_piece[piece].surfaces as Array).append(
			{"part": key & 0xFF, "arrays": (soups[key] as Soup).arrays()}
		)
	for piece in out:
		_motion(piece, frame, planes.size() - 1)
	return out


## The transform piece `piece` (split's) takes `x` (0..1) into the collapse, in its node's frame:
## identity before it and for the stump, a rigid turn about its pivot (no scale). Pure.
static func pose(piece: Dictionary, x: float) -> Transform3D:
	if x <= 0.0 or bool(piece.stump):
		return Transform3D.IDENTITY
	var pivot: Vector3 = piece.pivot
	var start := SAG_END + float(piece.delay)
	var sagged := 1.0 - pow(1.0 - clampf(x / SAG_END, 0.0, 1.0), 2.0)
	var f := clampf((x - start) / maxf(FALL_END - start, 0.01), 0.0, 1.0)
	var fall := f * f
	var bump := sin(PI * clampf((x - FALL_END) / (1.0 - FALL_END), 0.0, 1.0))
	var sag := float(piece.sag) * sagged
	var angle := lerpf(sag, float(piece.angle), fall) - float(piece.rock) * bump
	var tip: Vector3 = piece.tip
	var turn := (
		Basis(Vector3.UP, float(piece.twist) * fall) * Basis(Vector3.UP.cross(tip).normalized(), angle)
	)
	var lift := -float(piece.drop) * fall + float(piece.bounce) * bump
	var moved := pivot + (piece.slide as Vector3) * fall + Vector3(0.0, lift, 0.0)
	return Transform3D(turn, moved - turn * pivot)


## Makes `pieces` (split's) as Node3Ds under `node` (the pose moves them), parked out of sight
## (PARKED) until the collapse, each holding a MeshInstance3D a surface, in surface order, wearing
## `materials[part]` (the part's stand-in, or its own) as its material_override, as the part it
## came from does. Shown and burning from the start, like the parts: made hidden, a piece drew
## uncharred in the render jobs although its `burn` was set (rounds 1 and 2). Returns them.
static func install(
	node: Node3D, pieces: Array[Dictionary], materials: Array[Material]
) -> Array[Node3D]:
	var made: Array[Node3D] = []
	for piece in pieces:
		var holder := Node3D.new()
		holder.name = PIECE_NAME % int(piece.key)
		holder.transform = PARKED
		for surface: Dictionary in piece.surfaces:
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays)
			var part := MeshInstance3D.new()
			part.mesh = mesh
			part.material_override = materials[int(surface.part)]
			holder.add_child(part)
		node.add_child(holder)
		made.append(holder)
	return made


static func _soup_of(arrays: Array, to_node: Transform3D) -> Soup:
	var soup := Soup.new()
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	soup.v = to_node * points
	if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var turn := to_node.basis.inverse().transposed()
		for k in normals.size():
			normals[k] = (turn * normals[k]).normalized()
		soup.n = normals
	if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
		soup.t = arrays[Mesh.ARRAY_TANGENT]
	if arrays[Mesh.ARRAY_COLOR] is PackedColorArray:
		soup.c = arrays[Mesh.ARRAY_COLOR]
	if arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array:
		soup.uv = arrays[Mesh.ARRAY_TEX_UV]
	return soup


## Cuts triangle `corners` of `src` by `planes` (Sutherland-Hodgman, keeping both sides), and adds
## each bit, both faces, to the soup of its piece (keyed piece << 8 | part).
static func _cut(
	src: Soup,
	corners: PackedInt32Array,
	planes: Array[Plane],
	frame: Dictionary,
	roof: bool,
	part: int,
	soups: Dictionary
) -> void:
	var bits: Array[PackedInt32Array] = [corners]
	for plane in planes:
		var next: Array[PackedInt32Array] = []
		for poly in bits:
			var over := 0
			var under := 0
			for i in poly:
				var d := plane.distance_to(src.v[i])
				over += 1 if d > 1e-5 else 0
				under += 1 if d < -1e-5 else 0
			if over == 0 or under == 0:
				next.append(poly)
				continue
			var front := PackedInt32Array()
			var back := PackedInt32Array()
			for k in poly.size():
				var a := poly[k]
				var b := poly[(k + 1) % poly.size()]
				var da := plane.distance_to(src.v[a])
				var db := plane.distance_to(src.v[b])
				if da >= 0.0:
					front.append(a)
				if da <= 0.0:
					back.append(a)
				if (da > 0.0 and db < 0.0) or (da < 0.0 and db > 0.0):
					var m := src.mix(a, b, da / (da - db))
					front.append(m)
					back.append(m)
			next.append(front)
			next.append(back)
		bits = next
	for poly in bits:
		if poly.size() < 3:
			continue
		var c := Vector3.ZERO
		for i in poly:
			c += src.v[i]
		c /= float(poly.size())
		var key := (piece_of(c, roof, planes, frame) << 8) | part
		if not soups.has(key):
			soups[key] = Soup.new()
		var soup: Soup = soups[key]
		for k in range(1, poly.size() - 1):
			for i in [poly[0], poly[k], poly[k + 1]]:
				soup.take(src, i, false)
			for i in [poly[k + 1], poly[k], poly[0]]:
				soup.take(src, i, true)


## Sets piece `piece`'s motion (see the header) from its geometry, the frame and a seeded draw.
static func _motion(piece: Dictionary, frame: Dictionary, count: int) -> void:
	var key := int(piece.key)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(frame.seed) * 131 + key
	var centre: Vector3 = frame.centre
	var axis: Vector3 = frame.axis
	var across := Vector3.UP.cross(axis)
	var half: Vector2 = frame.half
	var height := float(frame.height)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var sum := Vector3.ZERO
	var points := 0
	for surface: Dictionary in piece.surfaces:
		for p: Vector3 in (surface.arrays as Array)[Mesh.ARRAY_VERTEX]:
			var rel := p - centre
			var local := Vector3(rel.dot(axis), p.y, rel.dot(across))
			lo = lo.min(local)
			hi = hi.max(local)
			sum += local
			points += 1
	var mean := sum / maxf(float(points), 1.0)
	piece.roof = key >= 1 and key <= 2 * count
	piece.stump = key == 0
	piece.bounce = clampf(BOUNCE * height, BOUNCE_M.x, BOUNCE_M.y)
	piece.rock = rng.randf_range(ROCK.x, ROCK.y)
	piece.twist = rng.randf_range(-0.22, 0.22)
	var heap := centre.y + rng.randf_range(HEAP.x, HEAP.y) * height
	if piece.stump:
		_still(piece, centre)
		return
	if piece.roof:
		# The eave is the slab's outer, lowest edge; the ridge drops about it, into the footprint.
		var side := signf(mean.z) if mean.z != 0.0 else 1.0
		var outer := hi.z if side > 0.0 else lo.z
		var reach := maxf(absf(hi.z - lo.z), 0.1)
		var pitch := atan2(hi.y - lo.y, reach)
		var middle := 1.0 - clampf(absf(mean.x) / maxf(half.x, 0.1), 0.0, 1.0)
		var hinge := centre + axis * mean.x + across * outer
		piece.pivot = Vector3(hinge.x, lo.y, hinge.z)
		piece.tip = -across * side
		piece.sag = lerpf(SAG_ROOF.x, SAG_ROOF.y, middle) + rng.randf_range(0.0, 0.06)
		piece.angle = clampf(pitch * rng.randf_range(LAND_TURN.x, LAND_TURN.y), 0.35, 1.45)
		piece.drop = maxf(lo.y - heap, 0.0)
		piece.slide = -across * side * rng.randf_range(0.3, 0.8)
		piece.delay = (1.0 - middle) * 0.1 + rng.randf_range(0.0, 0.05)
		return
	# A wall piece topples about its foot, most of them outward.
	var end_wall := key >= 1 + 2 * count and key < 1 + 2 * count + 4
	var out := axis * signf(mean.x) if end_wall else across * signf(mean.z)
	if out == Vector3.ZERO:
		out = across
	var tip := out if rng.randf() < OUTWARD else -out
	var foot := centre + axis * mean.x + across * mean.z
	piece.pivot = Vector3(foot.x, lo.y, foot.z)
	piece.tip = tip
	piece.sag = rng.randf_range(BOW.x, BOW.y)
	piece.angle = rng.randf_range(TOPPLE.x, TOPPLE.y)
	piece.drop = maxf(minf((hi.y - lo.y) * rng.randf_range(0.3, 0.6), lo.y - heap), 0.0)
	piece.slide = tip * rng.randf_range(0.0, 0.4)
	piece.delay = rng.randf_range(0.04, 0.2)


static func _still(piece: Dictionary, centre: Vector3) -> void:
	piece.pivot = centre
	piece.tip = Vector3.RIGHT
	piece.sag = 0.0
	piece.angle = 0.0
	piece.drop = 0.0
	piece.slide = Vector3.ZERO
	piece.delay = 0.0
	piece.bounce = 0.0
	piece.rock = 0.0
	piece.twist = 0.0
