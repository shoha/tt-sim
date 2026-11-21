class_name PainterSites
extends RefCounted
## The small stones' dabs of the contact field (PainterOcclusion's SITE marks; card
## painter-terrain-marks): which body is one, and how its dab is baked.
##
## A small stone is a body whose longer half is under HALF_M, no longer than ASPECT times its
## narrower one and at least MIN_M in radius. A coverage blob its size (main's: a rounded box
## behind a band half a texel wide) is one or two texels of a 0.25 m field: an angular patch that
## joins three stones into one. So a small stone's mark is baked as a DISTANCE instead. Its dab is
## a brush's lobe about its footprint, the union of DISCS discs whose places and sizes come from
## the stone's own position (an uneven outline, the same on every bake), and each texel of the
## field's seam channel takes EDGE minus the dab's signed distance (negative inside) over BAND_M.
## A distance is smooth where a coverage is a step, so the field's bilinear read rebuilds a lobe
## 0.2 to 0.6 m across with its outline where the dab's is, and two dabs join exactly where their
## outlines do. The ground's shader does nothing for it: EDGE is the threshold it already takes
## the seam at, through the brush noise it already has, so a dab is the seam's own flat tone
## behind the seam's own firm, wobbled edge, at no cost per pixel (the two structures before it,
## a second texture of sites read per pixel, cost 0.03 to 0.09 ms a frame).
##
## Two corrections make a quarter-metre texel hold a mark its own size:
## - The distance is a paraboloid's, (d * d - R * R) / (2 R) for a disc of radius R: the disc's
##   own distance at its outline (slope 1), but without the cone's point at the middle, which a
##   bilinear read flattens by a different amount wherever the stone sits among the texels.
## - A bilinear read of a convex function is too high: by nothing at a texel's middle and by up to
##   step * step / (4 R) between four of them, for that paraboloid, whatever the stone's place. So
##   a disc is baked a little wide (its radius squared plus WIDEN of the texel's): what the ground
##   shows then lies within about a twentieth of a metre of the disc either way. (With the mean
##   error taken off whole, a third of the texel's square, a 0.1 m disc showed 0.17 m wide toward
##   the texels' middles and small stones stood in a puddle.) The first disc is at least FIRST_M
##   in radius, so it holds a texel's middle, or nearly, and every stone shows a dab.
## The ground reads the field LEAN_M toward the sun (painter_ground SEAM_LEAN_M: a boulder's seam
## leans to its shadow's side), which would set a stone's whole dab beside it, so a dab is baked
## that far toward the sun (`sun`, the unit plan direction to it): it shows at the stone, the same
## uneven lobe whatever the hour. PainterOcclusion bakes the sites again when the sun has turned.

const HALF_M := 0.45
const ASPECT := 1.6
const MIN_M := 0.09
## A dab's discs: each its middle's distance from the stone's (in the stone's radii) and its
## radius (the same). The first lies under the stone (a body's radius is its box's, wider than its
## foot); the others stand off it in directions the stone's place gives, so the dab shows as a
## lobe on two sides of the stone and reaches REACH radii at most. (With the first 1.3 radii wide
## and the others reaching 1.55, three stones side by side stood in one puddle wider than they.)
const DISCS: Array[Vector2] = [Vector2(0.0, 0.95), Vector2(0.45, 0.8), Vector2(0.5, 0.65)]
const REACH := 1.25
const FIRST_M := 0.15
const WIDEN := 0.125
## The ground's threshold on the seam channel (painter_ground contact_at(): 0.45), the metres of
## distance one unit of the channel stands for (the brush noise, 0.15 of the channel either way,
## then moves a dab's edge by 0.045 m), and the ground's lean of the field's read.
const EDGE := 0.45
const BAND_M := 0.3
const LEAN_M := 0.3
## How far up and down from its foot a stone's dab shows: UP of its radius past half its height
## (it lies on the ground the stone stands on, not down a face below it).
const UP := 0.6
## Floats a texel in the field (PainterOcclusion.CHANNELS), its seam channel and its foot's.
const CHANNELS := 4
const SEAM := 1
const FOOT := 2


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


## Metres from the middle of a dab baked at a stone of radius `r` within which it may raise the
## field: its outline and the band outside it (the correction widens a disc by less than the band's
## curve narrows it), and a centimetre for the discs' rounding.
static func reach(r: float) -> float:
	return maxf(REACH * r, FIRST_M) + EDGE * BAND_M + 0.01


## The foot of a stone whose foot stands at height `at` and whose body is `half_y` tall above and
## below its middle, as the field holds one: the height times its weight, and the weight (one over
## the dab's vertical reach).
static func foot(at: float, r: float, half_y: float) -> Vector2:
	var up := 0.5 * half_y + UP * r
	return Vector2(at / up, 1.0 / up)


## The discs of the dab of a stone at world (x, z) with radius `r`: three floats each, the disc's
## middle (world x, z) and its radius. One function of the stone's place (to the millimetre).
static func discs(x: float, z: float, r: float) -> PackedFloat32Array:
	var h := hash(Vector2i(roundi(x * 1000.0), roundi(z * 1000.0)))
	var turn := TAU * float(h & 0xFFFF) / 65536.0
	var apart := 2.0 + 2.3 * float((h >> 16) & 0xFFFF) / 65536.0
	var out := PackedFloat32Array()
	for k in DISCS.size():
		var off := DISCS[k].x * r
		var a := turn + apart * float(k - 1)
		out.append(x + off * cos(a))
		out.append(z + off * sin(a))
		out.append(maxf(DISCS[k].y * r, FIRST_M) if k == 0 else DISCS[k].y * r)
	return out


## Bakes the dab of a small stone (`stone`: its middle's world x and z, its radius) into the seam
## channel of `field` (`width` texels a row, `step` metres a texel, the first texel's corner at
## `origin`), inside the texels of `win`, keeping the maximum; a texel the dab raises takes the
## stone's `foot` (foot()). The dab is baked LEAN_M toward `sun` (the unit plan direction to the
## sun, zero for none), where the ground's leaning read finds it at the stone.
static func bake(
	field: PackedFloat32Array,
	origin: Vector2,
	width: int,
	step: float,
	win: Rect2i,
	stone: Vector3,
	foot_of: Vector2,
	sun: Vector2
) -> void:
	var r := stone.z
	var x := stone.x + sun.x * LEAN_M
	var z := stone.y + sun.y * LEAN_M
	var own := discs(stone.x, stone.y, r)
	var count := DISCS.size()
	# Per disc: its middle, half over its radius, and its radius squared plus the correction's
	# share of the texel's.
	var cx := PackedFloat32Array()
	var cz := PackedFloat32Array()
	var inv := PackedFloat32Array()
	var edge2 := PackedFloat32Array()
	for k in count:
		cx.append(own[k * 3] + sun.x * LEAN_M)
		cz.append(own[k * 3 + 1] + sun.y * LEAN_M)
		inv.append(0.5 / own[k * 3 + 2])
		edge2.append(own[k * 3 + 2] * own[k * 3 + 2] + step * step * WIDEN)
	var far := reach(r)
	var i0 := maxi(win.position.x, floori((x - far - origin.x) / step))
	var i1 := mini(win.end.x - 1, floori((x + far - origin.x) / step))
	var j0 := maxi(win.position.y, floori((z - far - origin.y) / step))
	var j1 := mini(win.end.y - 1, floori((z + far - origin.y) / step))
	for j in range(j0, j1 + 1):
		var pz := origin.y + (j + 0.5) * step
		var row := j * width
		for i in range(i0, i1 + 1):
			var px := origin.x + (i + 0.5) * step
			var q := INF
			for k in count:
				var dx := px - cx[k]
				var dz := pz - cz[k]
				q = minf(q, (dx * dx + dz * dz - edge2[k]) * inv[k])
			var v := minf(EDGE - q / BAND_M, 1.0)
			var at := (row + i) * CHANNELS
			if v > field[at + SEAM]:
				field[at + SEAM] = v
				field[at + FOOT] = foot_of.x
				field[at + FOOT + 1] = foot_of.y
