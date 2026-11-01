class_name StructureDressingShapes
extends RefCounted

## The low-poly shape primitives a building's dressing is drawn with (StructureDressing): a
## jittered icosahedron blob (a bush or a boulder), a flat hexagon disc (a stepping stone), a log
## end, a flat-shaded slab (a step, a planter, a woodpile) and a bloom dot, each appended to a Soup
## of mesh arrays in the building's map frame. Heights come from the terrain's drawn triangles, and
## every jitter from an Rng, the integer-hash stream that makes a yard the same on every peer.
## Pure and safe on any thread.

const ICO_A := 0.5257311
const ICO_B := 0.8506508
const ICO_VERTS := [
	Vector3(-ICO_A, ICO_B, 0.0),
	Vector3(ICO_A, ICO_B, 0.0),
	Vector3(-ICO_A, -ICO_B, 0.0),
	Vector3(ICO_A, -ICO_B, 0.0),
	Vector3(0.0, -ICO_A, ICO_B),
	Vector3(0.0, ICO_A, ICO_B),
	Vector3(0.0, -ICO_A, -ICO_B),
	Vector3(0.0, ICO_A, -ICO_B),
	Vector3(ICO_B, 0.0, -ICO_A),
	Vector3(ICO_B, 0.0, ICO_A),
	Vector3(-ICO_B, 0.0, -ICO_A),
	Vector3(-ICO_B, 0.0, ICO_A),
]
const ICO_FACES := [
	0,
	11,
	5,
	0,
	5,
	1,
	0,
	1,
	7,
	0,
	7,
	10,
	0,
	10,
	11,
	1,
	5,
	9,
	5,
	11,
	4,
	11,
	10,
	2,
	10,
	7,
	6,
	7,
	1,
	8,
	3,
	9,
	4,
	3,
	4,
	2,
	3,
	2,
	6,
	3,
	6,
	8,
	3,
	8,
	9,
	4,
	9,
	5,
	2,
	4,
	11,
	6,
	2,
	10,
	8,
	6,
	7,
	9,
	8,
	1,
]


## The point above the ground at `at`, `lift` metres up.
static func on_ground(doc: MapDocument, at: Vector2, lift: float) -> Vector3:
	return Vector3(at.x, ground_height(doc, at) + lift, at.y)


## The ground's height at `at` on the triangles the terrain mesh is drawn with (the bilinear
## WaterGeometry.ground_at can sit a few centimetres off them on bumpy ground, which would bury a
## patch laid a hand's breadth above it).
static func ground_height(doc: MapDocument, at: Vector2) -> float:
	return ScatterGenerator.triangle_height(
		doc.heights, doc.samples_x(), doc.samples_z(), doc.world_to_sample(at)
	)


## `color` with a small random shift of tone (and of blue).
static func vary(color: Color, rng: Rng) -> Color:
	var tone := rng.between(0.9, 1.1)
	return Color(color.r * tone, color.g * tone, color.b * tone * rng.between(0.95, 1.05))


## A small tetrahedron, a bloom.
static func soup_dot(soup: Soup, centre: Vector3, radius: float, color: Color) -> void:
	var corners := [
		centre + Vector3(0.0, radius, 0.0),
		centre + Vector3(radius, -radius * 0.6, radius * 0.6),
		centre + Vector3(-radius, -radius * 0.6, radius * 0.6),
		centre + Vector3(0.0, -radius * 0.6, -radius),
	]
	var faces := [[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]]
	for face: Array in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot((a + b + c) / 3.0 - centre) < 0.0:
			normal = -normal
		var tint := Color(color.r, color.g, color.b)
		soup.tri(
			soup.vertex(a, normal, tint), soup.vertex(b, normal, tint), soup.vertex(c, normal, tint)
		)


## An up-facing vertex: the index of `position` in `soup`.
static func soup_vertex(soup: Soup, position: Vector3, color: Color) -> int:
	return soup.vertex(position, Vector3.UP, color)


## A squashed, jittered icosahedron part sunk in the ground: a painted bush or boulder. Vertex
## colour darkens toward the ground and warms toward the top; `sink` is the share of its height
## below the ground (0.3 for a bush, 0.3 for a rock).
static func blob(
	soup: Soup,
	doc: MapDocument,
	at: Vector2,
	rx: float,
	ry: float,
	color: Color,
	rng: Rng,
	sink: float = 0.3
) -> void:
	var ground := ground_height(doc, at)
	blob_at(soup, Vector3(at.x, ground + ry * (1.0 - 2.0 * sink), at.y), rx, ry, color, rng)


## The blob of `blob` centred at `centre` (a dome on a planter).
static func blob_at(
	soup: Soup, centre: Vector3, rx: float, ry: float, color: Color, rng: Rng
) -> void:
	var spin := rng.between(0.0, TAU)
	var cs := cos(spin)
	var sn := sin(spin)
	var indices := PackedInt32Array()
	for v: Vector3 in ICO_VERTS:
		var d := Vector3(v.x * cs - v.z * sn, v.y, v.x * sn + v.z * cs)
		var wobble := rng.between(0.88, 1.12)
		var position := centre + Vector3(d.x * rx, d.y * ry, d.z * rx) * wobble
		var normal := Vector3(d.x / rx, d.y / ry, d.z / rx).normalized()
		var up := d.y * 0.5 + 0.5
		var shade := lerpf(0.8, 1.2, up)
		var tint := Color(
			color.r * shade * (0.96 + 0.1 * up), color.g * shade, color.b * shade * (1.0 - 0.1 * up)
		)
		indices.append(soup.vertex(position, normal, tint))
	for f in range(0, ICO_FACES.size(), 3):
		soup.tri(indices[ICO_FACES[f]], indices[ICO_FACES[f + 1]], indices[ICO_FACES[f + 2]])


## A flat hexagon `lift` above the ground, following it (a stepping stone).
static func disc(
	soup: Soup, doc: MapDocument, at: Vector2, radius: float, lift: float, color: Color, rng: Rng
) -> void:
	var spin := rng.between(0.0, TAU)
	var middle := soup.vertex(on_ground(doc, at, lift), Vector3.UP, color.lightened(0.05))
	var ring := PackedInt32Array()
	for k in 6:
		var angle := spin + TAU * float(k) / 6.0
		var p := at + Vector2(cos(angle), sin(angle)) * radius * rng.between(0.88, 1.08)
		ring.append(soup.vertex(on_ground(doc, p, lift), Vector3.UP, color.darkened(0.06)))
	for k in 6:
		soup.tri(middle, ring[k], ring[(k + 1) % 6])


## A log end on a vertical face: a hexagon at `centre` facing `normal`, spanned by `across`.
static func end_disc(
	soup: Soup,
	centre: Vector3,
	normal: Vector3,
	across: Vector2,
	radius: float,
	color: Color,
	rng: Rng
) -> void:
	var u := Vector3(across.x, 0.0, across.y)
	var middle := soup.vertex(centre, normal, color.lightened(0.08))
	var ring := PackedInt32Array()
	for k in 6:
		var angle := TAU * float(k) / 6.0
		var p := centre + (u * cos(angle) + Vector3.UP * sin(angle)) * radius
		ring.append(soup.vertex(p, normal, vary(color, rng).darkened(0.05)))
	for k in 6:
		soup.tri(middle, ring[k], ring[(k + 1) % 6])


## A box standing on the ground at `at`, `size_along` wide across `facing`'s orthogonal and
## `size_out` deep along `facing`, `height` tall, flat shaded: a step, a planter, a woodpile.
static func slab(
	soup: Soup,
	doc: MapDocument,
	at: Vector2,
	facing: Vector2,
	size_along: float,
	size_out: float,
	height: float,
	color: Color,
	rng: Rng
) -> void:
	var f := facing.normalized()
	var s := f.orthogonal()
	var hs := size_along * 0.5
	var hf := size_out * 0.5
	var corners := [
		at - s * hs - f * hf, at + s * hs - f * hf, at + s * hs + f * hf, at - s * hs + f * hf
	]
	var low := INF
	for c: Vector2 in corners:
		low = minf(low, ground_height(doc, c))
	var bottom := low - 0.06
	var top := low + height
	var tone := rng.between(0.94, 1.06)
	var base := Color(color.r * tone, color.g * tone, color.b * tone)
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var normal2 := (b - a).orthogonal().normalized()
		var normal := Vector3(normal2.x, 0.0, normal2.y)
		if normal2.dot(a - at) < 0.0:
			normal = -normal
		var shade := 0.82 + 0.12 * float(k % 2)
		var side_color := Color(base.r * shade, base.g * shade, base.b * shade)
		var i0 := soup.vertex(Vector3(a.x, bottom, a.y), normal, side_color)
		var i1 := soup.vertex(Vector3(b.x, bottom, b.y), normal, side_color)
		var i2 := soup.vertex(Vector3(b.x, top, b.y), normal, side_color)
		var i3 := soup.vertex(Vector3(a.x, top, a.y), normal, side_color)
		soup.tri(i0, i1, i2)
		soup.tri(i0, i2, i3)
	var lid := Color(base.r * 1.08, base.g * 1.08, base.b * 1.08)
	var t0 := soup.vertex(Vector3(corners[0].x, top, corners[0].y), Vector3.UP, lid)
	var t1 := soup.vertex(Vector3(corners[1].x, top, corners[1].y), Vector3.UP, lid)
	var t2 := soup.vertex(Vector3(corners[2].x, top, corners[2].y), Vector3.UP, lid)
	var t3 := soup.vertex(Vector3(corners[3].x, top, corners[3].y), Vector3.UP, lid)
	soup.tri(t0, t1, t2)
	soup.tri(t0, t2, t3)


## The mesh arrays pieces are added to (vertex, normal, colour, index).
class Soup:
	extends RefCounted
	var _vertices := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()

	func vertex(position: Vector3, normal: Vector3, color: Color) -> int:
		_vertices.append(
			Vector3(
				snappedf(position.x, 0.005),
				snappedf(position.y, 0.005),
				snappedf(position.z, 0.005)
			)
		)
		_normals.append(normal)
		_colors.append(color)
		return _vertices.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		_indices.append_array(PackedInt32Array([a, b, c]))

	func triangles() -> int:
		return _indices.size() / 3

	## {} when nothing was added.
	func arrays() -> Dictionary:
		if _indices.is_empty():
			return {}
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = _normals
		arrays[Mesh.ARRAY_COLOR] = _colors
		arrays[Mesh.ARRAY_INDEX] = _indices
		return {"arrays": arrays}


## An integer-hash random stream (StructurePaint.mix): the same on every platform.
class Rng:
	extends RefCounted
	var _seed := 0
	var _count := 0

	func _init(seed_value: int) -> void:
		_seed = seed_value

	func f() -> float:
		_count += 1
		return StructurePaint.unit(StructurePaint.mix(_seed, _count))

	func between(low: float, high: float) -> float:
		return lerpf(low, high, f())

	func chance(p: float) -> bool:
		return f() < p

	func pick(count: int) -> int:
		return mini(int(f() * count), count - 1)
