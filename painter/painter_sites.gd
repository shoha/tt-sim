class_name PainterSites
extends RefCounted
## The small stones' dabs (card painter-terrain-dabs): which body is one, and the flat geometry its
## contact mark is drawn with. PainterDabs keeps the meshes; painter_ground draws them.
##
## A small stone is a body whose longer half is under HALF_M, no longer than ASPECT times its
## narrower one and at least MIN_M in radius. A mark its size (0.2 to 0.9 m) is one or two texels
## of the contact field (PainterOcclusion, 0.25 m): baked there it was an angular patch that joined
## three stones into one, and a second texture read per ground pixel cost 0.03 to 0.09 ms a frame.
## So a small stone leaves the field alone and its dab is GEOMETRY: a patch of flat triangles
## lying on the ground under it, drawn with the ground's own material. A pixel of a patch is
## therefore the ground at that place (the same biome paint, strata, zone maps, cast shadow and
## contact field) with one difference, a VALUE the ground's shader joins to the field's seam
## before the seam's own threshold: positive inside the dab's outline, negative round it. Inside,
## the pixel takes the seam's tone behind the seam's firm, noise-wobbled edge, as a boulder's foot
## does; outside it is the plain ground the patch covers. The seam is a tone the ground is set to,
## not a darkening, so a dab inside a boulder's seam or another dab is no darker than either.
##
## The patch is the terrain's own triangles, copied: every sample of the terrain's grid within
## the dab's reach of the stone, triangulated as the terrain's mesh is and lifted LIFT_M, so it
## lies on the ground whatever the ground's shape (a fan of its own, with vertices on the ground,
## dipped under every lip it crossed: probed, the card's first sheet). The dab's SHAPE is not in
## the triangles: the stone's LOBES.size() lobes (a lobe's middle, its radius and the turn of its
## outline's waves), placed by a hash of the stone's position, are a row of texels PainterDabs
## keeps (the patch's vertices carry the stone's slot there), and the ground's shader works the
## value out per pixel: for a lobe its
## radius over BAND_M at the middle, falling in a straight line to 0 on an outline whose distance
## varies round the lobe by two and three waves (an uneven blob, never a clean oval), and the
## greatest of the lobes'. So the outline is exact at any zoom and nothing is tessellated for it.
## The shader's too, from the same lobes:
## - The lean with the sun: the value takes a share (at most LEAN_MAX) of the offset from the
##   lobe's middle along the direction away from the sun, which stretches each outline to that
##   side (about a third of a stone shows there, a sliver elsewhere). A uniform: nothing is
##   rebuilt when the sun turns.
## - The union of touching stones' dabs: a vertex is lifted a little more by its value, so of two
##   patches that overlap the depth test keeps the one with the higher value there.
## CUSTOM3 holds BASE (the ground's own mesh has no CUSTOM3 and reads 0), what the value loses at
## this vertex (CUT per metre its ground lies past the stone's vertical reach from the ground at
## the stone: a dab at a ledge's edge ends there and does not run down the face), the lift and the
## stone's slot plus one.

const HALF_M := 0.45
const ASPECT := 1.6
const MIN_M := 0.09
## A dab's lobes: each its middle's distance from the stone's and its radius, in the stone's radii
## (a body's radius is its box's, wider than its foot). The first lies under the stone, the others
## stand off it in directions the stone's place gives.
const LOBES: Array[Vector2] = [Vector2(0.0, 0.95), Vector2(0.45, 0.8), Vector2(0.5, 0.65)]
## The outline's unevenness: the share of a lobe's radius that two and three waves round it move
## the outline by (painter_ground DAB_WAVES: keep the two equal).
const WAVES := Vector2(0.14, 0.08)
## The most the shader leans a dab by (painter_ground DAB_LEAN plus DAB_LEAN_LOW: keep under this),
## and the metres of plain ground a patch keeps round the furthest outline (the ground's brush
## noise moves the edge by 0.045 m).
const LEAN_MAX := 0.3
const MARGIN_M := 0.06
## What a patch's vertex holds in CUSTOM3.x (painter_ground takes anything over 1 for a dab).
const BASE := 8.0
## Metres a patch stands above the terrain's surface.
const LIFT_M := 0.004
## How far up and down from the ground at the stone a dab shows: UP of the stone's radius past
## half its height, and the value lost per metre past that.
const UP := 0.6
const CUT := 12.0
## Floats a site is: its middle's world x and z, its radius, the height of its foot and its
## vertical reach (metres).
const SITE_FLOATS := 5
## Floats a lobe is: its middle's x and z, its radius, its waves' turn.
const LOBE_FLOATS := 4


## The radius of the site a body of plan half extents `half` (metres) is, or 0 when it is none: too
## large or too long (a footprint in the field) or too small for any mark.
static func radius(half: Vector2) -> float:
	var narrow := minf(half.x, half.y)
	var longer := maxf(half.x, half.y)
	if longer >= HALF_M or longer > ASPECT * narrow:
		return 0.0
	var r := sqrt(half.x * half.y)
	return r if r >= MIN_M else 0.0


## Whether a body of plan half extents `half` is a site's size (it then leaves no footprint in the
## field, whether or not it is large enough for a dab).
static func holds(half: Vector2) -> bool:
	var longer := maxf(half.x, half.y)
	return longer < HALF_M and longer <= ASPECT * minf(half.x, half.y)


## A site: a stone whose body's middle is at world (x, z), with radius `r` (radius()), whose foot
## stands at height `at` and whose body is `half_y` tall above and below its middle.
static func site(x: float, z: float, r: float, at: float, half_y: float) -> Array:
	return [x, z, r, at, 0.5 * half_y + UP * r]


## Metres from a stone's middle within which its dab can show, whatever the sun: the furthest a
## lobe's outline reaches when leaned by LEAN_MAX, and the margin.
static func reach(r: float) -> float:
	var most := (1.0 + WAVES.x + WAVES.y)
	var stretch := most / (1.0 - LEAN_MAX * most)
	var far := 0.0
	for lobe: Vector2 in LOBES:
		far = maxf(far, lobe.x + lobe.y * stretch)
	return far * r + MARGIN_M


## The lobes of the dab of a stone at (x, z) with radius `r`: LOBE_FLOATS each. One function of
## the stone's place (to the millimetre).
static func lobes(x: float, z: float, r: float) -> PackedFloat32Array:
	var h := hash(Vector2i(roundi(x * 1000.0), roundi(z * 1000.0)))
	var turn := TAU * float(h & 0xFFFF) / 65536.0
	var apart := 2.0 + 2.3 * float((h >> 16) & 0xFFFF) / 65536.0
	var out := PackedFloat32Array()
	for k in LOBES.size():
		var off := LOBES[k].x * r
		var a := turn + apart * float(k - 1)
		out.append(x + off * cos(a))
		out.append(z + off * sin(a))
		out.append(LOBES[k].y * r)
		out.append(TAU * float(hash(Vector2i(h & 0xFFFFFF, k)) & 0x3FF) / 1024.0)
	return out


## The value of the dab whose lobes are `own` (lobes()) at (x, z), leaned by `lean` (the direction
## away from the sun times the lean's share): what painter_ground's dab_value() works out per pixel
## (the tests' and the probes' copy of it), in units of BAND_M metres, positive inside.
static func value(
	own: PackedFloat32Array, x: float, z: float, lean: Vector2, band_m: float
) -> float:
	var best := -INF
	for k in own.size() / LOBE_FLOATS:
		var d := Vector2(x - own[k * 4], z - own[k * 4 + 1])
		var radius_m := own[k * 4 + 2]
		var turn := own[k * 4 + 3]
		var th := d.angle()
		var rho := (
			radius_m
			* (1.0 + WAVES.x * cos(2.0 * th - turn) + WAVES.y * cos(3.0 * th - 2.7 * turn))
		)
		best = maxf(best, (radius_m * (1.0 - d.length() / rho) + d.dot(lean)) / band_m)
	return best


## Appends the patch of `site`'s dab: its `vertices`, their `uvs` (the map-frame x, z the ground's
## shader reads), the four floats a vertex of `custom` (CUSTOM3: BASE, what the value loses, the
## lift, and `slot` plus one, the stone's place in PainterDabs' texture of lobes) and its
## triangles' `indices`, counted from the patch's first vertex. Returns the vertices it added: none
## for a stone that does not stand on this ground (off the map, or its foot further than twice
## its reach from the ground). The site is in the terrain's own frame; `grid` is the terrain's
## heights (`columns` by `rows` samples, `step` metres apart, centred on the origin: `half` is
## half its extent).
static func append_dab(
	site_of: Array,
	grid: PackedFloat32Array,
	columns: int,
	rows: int,
	step: Vector2,
	half: Vector2,
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	custom: PackedFloat32Array,
	indices: PackedInt32Array,
	slot := 0
) -> int:
	var x: float = site_of[0]
	var z: float = site_of[1]
	var r: float = site_of[2]
	var up: float = site_of[4]
	if absf(x) > half.x or absf(z) > half.y:
		return 0
	var ground := ScatterGenerator.triangle_height(
		grid, columns, rows, Vector2((x + half.x) / step.x, (z + half.y) / step.y)
	)
	if absf(ground - float(site_of[3])) > 2.0 * up:
		return 0
	var far := reach(r)
	var i0 := clampi(floori((x - far + half.x) / step.x), 0, columns - 2)
	var i1 := clampi(ceili((x + far + half.x) / step.x), i0 + 1, columns - 1)
	var j0 := clampi(floori((z - far + half.y) / step.y), 0, rows - 2)
	var j1 := clampi(ceili((z + far + half.y) / step.y), j0 + 1, rows - 1)
	var wide := i1 - i0 + 1
	var tag := float(slot + 1)
	for j in range(j0, j1 + 1):
		var pz := j * step.y - half.y
		var row := j * columns
		for i in range(i0, i1 + 1):
			var px := i * step.x - half.x
			var h := grid[row + i]
			vertices.append(Vector3(px, h + LIFT_M, pz))
			uvs.append(Vector2(px, pz))
			custom.append(BASE)
			custom.append(maxf(absf(h - ground) - up, 0.0) * CUT)
			custom.append(LIFT_M)
			custom.append(tag)
	# The terrain's own triangles (TerrainMeshBuilder.build_chunk_arrays): front faces up.
	for j in j1 - j0:
		for i in i1 - i0:
			var a := j * wide + i
			indices.append(a)
			indices.append(a + 1)
			indices.append(a + wide)
			indices.append(a + 1)
			indices.append(a + wide + 1)
			indices.append(a + wide)
	return wide * (j1 - j0 + 1)
