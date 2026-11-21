class_name PainterSites
extends RefCounted
## The small stones' sites of the contact field (PainterOcclusion's SITE marks; card
## painter-terrain-marks): which body is one, and how one is recorded.
##
## A small stone is a body whose longer half is under HALF_M, no longer than ASPECT times its
## narrower one and at least MIN_M in radius. The field cannot hold a mark its size (two texels
## across, or less) nor keep three stones' marks apart, so such a body is not rasterized: every
## texel near it records the stone itself (its middle, as an offset from the texel's own, its
## radius and its foot's height), the one whose dab covers the texel most (a dab is taken as COVER
## radii wide there), and the ground draws the dab from those numbers, at the stone, at any zoom.
## A dab reaches at most GROW radii from its stone (painter_ground's SITE_FAR + SITE_LONG, its far
## end under a low sun). Two distances past that, each a part of what the ground's shader does
## with a texel:
## - TIGHT_M: the edge's wobble and the step's width (0.06 m) and half a texel's diagonal. A stone
##   within it of a texel's middle may draw in that texel (it is "tight" there). A texel one stone
##   is tight in holds that stone with its radius positive, and the ground reads that one texel;
##   where two or more are, the radius is negative and the ground reads the four texels round the
##   pixel (each for the stone it holds).
## - PAD_M: what a site is written within, and where it raises the field's seam channel to FLAG.
##   The ground reads the field anyway, SEAM_LEAN_M (0.3) toward the sun and filtered, so that
##   read being zero says no dab is near and the sites are not read at all. The flag is far under
##   the seam's threshold: it draws nothing.

const HALF_M := 0.45
const ASPECT := 1.6
const MIN_M := 0.09
const GROW := 1.95
const TIGHT_M := 0.24
const PAD_M := 0.54
const COVER := 1.95
const FLAG := 0.015625
## Floats a texel, in the sites and in the field (PainterOcclusion.CHANNELS), and the field's
## seam channel.
const CHANNELS := 4
const SEAM := 1


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


## Records a small stone (`stone`: its middle's world x and z, its radius, its foot's height) in
## every texel of `span` whose middle lies within `reach` metres of it, and raises the seam
## channel of `field` there to FLAG. `sites` and `field` are laid out alike: `width` texels a row, `step`
## metres a texel, the first texel's corner at `origin`. A texel keeps one stone: a tight one
## before any other, then the one whose dab's edge (COVER radii from its middle) lies furthest
## past the texel's middle, and the earlier mark on a tie, so the result is one function of the
## sorted marks. Its radius is written negative where two or more stones are tight. (Nearest in
## its own radii let a stone take every texel round a pebble beside it, and the pebble had no dab.)
static func record(
	sites: PackedFloat32Array,
	field: PackedFloat32Array,
	origin: Vector2,
	width: int,
	step: float,
	span: Rect2i,
	stone: Vector4,
	reach: float
) -> void:
	var x := stone.x
	var z := stone.y
	var r := stone.z
	var reach2 := reach * reach
	var tight := GROW * r + TIGHT_M
	for j in range(span.position.y, span.end.y):
		var dz := z - (origin.y + (j + 0.5) * step)
		var row := j * width
		for i in range(span.position.x, span.end.x):
			var dx := x - (origin.x + (i + 0.5) * step)
			var d2 := dx * dx + dz * dz
			if d2 >= reach2:
				continue
			var at := (row + i) * CHANNELS
			if field[at + SEAM] < FLAG:
				field[at + SEAM] = FLAG
			var d := sqrt(d2)
			var is_tight := d <= tight
			var had := absf(sites[at + 2])
			var several := false
			if had > 0.0:
				var hx := sites[at]
				var hz := sites[at + 1]
				var had_d := sqrt(hx * hx + hz * hz)
				var had_tight := had_d <= GROW * had + TIGHT_M
				several = sites[at + 2] < 0.0 or (is_tight and had_tight)
				var keep := had_d - COVER * had <= d - COVER * r
				if had_tight != is_tight:
					keep = had_tight
				if keep:
					if several:
						sites[at + 2] = -had
					continue
			sites[at] = dx
			sites[at + 1] = dz
			sites[at + 2] = -r if several else r
			sites[at + 3] = stone.w
