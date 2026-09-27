class_name TerrainRules
extends RefCounted

## The automatic dressing of an authored map's ground (phase 3, P3-4): which share of the
## ground is the biome's cliff rock, which is its scree, and how painted surfaces read,
## as pure functions of the terrain. The ground shader (shaders/authored_ground.gdshaderinc,
## RULE_* and PAINT_* constants) computes the same thing per pixel for the look; this class
## computes it on the CPU so scatter can respect it (ScatterGenerator.document_fields: no
## plants on rock or on a painted road, boulders gathering at cliff feet). The two are one
## formula written twice: every constant below has a shader twin of the same name and
## value, and tests/unit/test_terrain_rules.gd fails when they drift apart.
##
## The rules are terrain-paint's mask generators (TP engine/mask_generators.py), ported:
##   - a source value v becomes a mask by its tail, clamp((v - start) / (end - start));
##   - edge noise adds lerp(-s, s, noise) (TP's per-layer edge noise), with one deliberate
##     change: it is added to the tail before the clamp, not after. TP adds it to the
##     clamped mask, so a non-zero s puts noise-shaped rock patches on flat ground and holes
##     in every face; before the clamp it moves the start and end per point instead, which
##     frays the band's edges and leaves flat ground and sheer faces alone;
##   - an EASE shaping ramp (smoothstep) rounds both ends;
##   - the surfaces then meet through the shader's height blend (a surface's score is its
##     weight plus its texture height, TP's factor formula in score form), so a rule's edge
##     follows the rock and gravel detail rather than a contour line.
##
## Inputs. Everything a rule reads is available to both sides with the same interpolation:
##   - the shading normal: the vertex normals (central differences on the whole grid,
##     TerrainMeshBuilder) interpolated over the triangle, then normalised; the shader gets
##     it as a varying, the CPU as ScatterGenerator.triangle_normal;
##   - two per-vertex fields computed here on the sample grid (sample_fields) and carried by
##     the chunk meshes in UV2, interpolated the same way (field_at): curvature, TP's
##     dot(P - blur(P), N) on a heightfield, (h - mean_R(h)) * n.y with a box mean of radius
##     CURVATURE_RADIUS_M (positive convex, negative concave); and steepness nearby, the
##     same box mean of the slope tail, which tells the foot of a steep face from the floor
##     of a gentle hollow;
##   - the position (map frame XZ and height), for the edge noise.
##
## Rules:
##   - cliff: tail of n.y from cos(CLIFF_START_DEG) to cos(CLIFF_END_DEG) (TP's slope source
##     uses normal.z the same way), edge noise, then a convex lip takes some rock back so a
##     tier's top reads as a rounded grassy lip, then EASE. Defaults: fully rock from 55
##     degrees (a tier face, whose shading normal is about 70 degrees), none below 38 (a 30
##     degree hill keeps its ground except where the noise frays the band).
##   - scree: concave curvature times steepness nearby (the foot of a steep face), edge
##     noise, EASE, and never where the cliff already is: (1 - cliff) * scree.
## The shader gives the cliff share to the biome's cliff_surface and the scree share to its
## scree_surface, over the part of the ground nobody painted (GroundLayerTable).

## Cliff slope tail, degrees from horizontal (terrain-paint slope start / end).
const CLIFF_START_DEG := 38.0
const CLIFF_END_DEG := 55.0
## Edge noise amplitude of the cliff tail (TP edge noise s).
const CLIFF_EDGE_NOISE := 0.35
## Convex curvature (m) over which the lip rule takes rock back, and how much at most. The
## lip rule fades out between a slope tail of 1 (fully rock) and LIP_SHEER_TAIL: the
## rounded shoulder above a face turns to ground, the sheer face below it stays rock.
const LIP_CURVATURE_START := 0.03
const LIP_CURVATURE_END := 0.12
const LIP_STRENGTH := 0.6
const LIP_SHEER_TAIL := 2.0
## terrain-paint's shaping ramp (black and white points) before the EASE: a steeper ramp
## narrows the band where rock and ground mix, which on a smooth hill otherwise spans
## metres of double-exposed texture.
const RAMP_LOW := 0.2
const RAMP_HIGH := 0.8
## Concave curvature (m, magnitude) over which scree comes in.
const SCREE_CURVATURE_START := 0.02
const SCREE_CURVATURE_END := 0.12
## Steepness nearby (box mean of the cliff tail) over which scree comes in.
const SCREE_NEAR_START := 0.03
const SCREE_NEAR_END := 0.1
const SCREE_EDGE_NOISE := 0.4
## A coarser noise breaks the scree apron into fans and gaps, so a foot does not read as a
## gravel path around the face: it moves the concave tail by (noise - 0.5) * SCREE_FAN (the
## band reaches further out in some places than others) and multiplies the band by
## smoothstep(LOW, HIGH, noise) (a few clean gaps).
const SCREE_BREAKUP_SCALE_M := 2.6
const SCREE_FAN := 1.6
const SCREE_BREAKUP_LOW := 0.15
const SCREE_BREAKUP_HIGH := 0.45
## Feature size of the rule noise, metres. The noise domain is sheared by height
## (RULE_NOISE_SHEAR) so it also varies up a vertical face.
const RULE_NOISE_SCALE_M := 1.6
const RULE_NOISE_SHEAR := 0.8
## Radius of the curvature and steepness box means, metres.
const CURVATURE_RADIUS_M := 1.5
## Painted surfaces: the weight map is read through a small noise domain warp (a painted
## path keeps its line, unlike a biome's 1.2 m warp) and partial paint gets edge noise.
const PAINT_EDGE_WARP_M := 0.3
const PAINT_EDGE_SCALE_M := 1.4
const PAINT_EDGE_NOISE := 0.35

const INV_UINT_MAX := 1.0 / 4294967295.0
const _MASK32 := 0xFFFFFFFF
## Noise offsets (match the shader's).
const CLIFF_NOISE_OFFSET := Vector2(13.7, -41.3)
const SCREE_NOISE_OFFSET := Vector2(-27.9, 8.6)
const SCREE_BREAKUP_OFFSET := Vector2(61.3, 19.4)
const PAINT_WARP_OFFSET_A := Vector2(-23.1, 57.7)
const PAINT_WARP_OFFSET_B := Vector2(91.3, -12.9)
const PAINT_NOISE_OFFSET := Vector2(7.9, 3.1)


## cos() of the cliff tail's start and end, the n.y values the tail runs between.
static func cliff_start_cos() -> float:
	return cos(deg_to_rad(CLIFF_START_DEG))


static func cliff_end_cos() -> float:
	return cos(deg_to_rad(CLIFF_END_DEG))


## Radius of the box means in samples for a sample step of `step_m` (at least 1).
static func radius_samples(step_m: float) -> int:
	return maxi(1, roundi(CURVATURE_RADIUS_M / maxf(step_m, 1e-4)))


## terrain-paint's tail: clamp((v - start) / (end - start), 0, 1).
static func tail(v: float, start: float, end: float) -> float:
	return clampf(raw_tail(v, start, end), 0.0, 1.0)


## The tail before its clamp, where edge noise is added.
static func raw_tail(v: float, start: float, end: float) -> float:
	if is_equal_approx(start, end):
		return 1.0 if v >= end else 0.0
	return (v - start) / (end - start)


## The shaping ramp (RAMP_LOW .. RAMP_HIGH) with EASE interpolation: smoothstep.
static func ease_ramp(m: float) -> float:
	var t := clampf((m - RAMP_LOW) / (RAMP_HIGH - RAMP_LOW), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The cliff tail of a normal's y alone (no noise, no lip): the slope mask the steepness
## field blurs.
static func slope_tail(normal_y: float) -> float:
	return tail(normal_y, cliff_start_cos(), cliff_end_cos())


# ---------------------------------------------------------------------------------------
# Noise: the shader's pcg2d value noise, bit for bit on the integer side.
# ---------------------------------------------------------------------------------------


## pcg2d (Jarzynski and Olano), 32-bit unsigned, as the shader computes it.
static func pcg2d(x: int, y: int) -> Vector2i:
	var vx := (x * 1664525 + 1013904223) & _MASK32
	var vy := (y * 1664525 + 1013904223) & _MASK32
	vx = (vx + vy * 1664525) & _MASK32
	vy = (vy + vx * 1664525) & _MASK32
	vx = vx ^ (vx >> 16)
	vy = vy ^ (vy >> 16)
	vx = (vx + vy * 1664525) & _MASK32
	vy = (vy + vx * 1664525) & _MASK32
	vx = vx ^ (vx >> 16)
	vy = vy ^ (vy >> 16)
	return Vector2i(vx, vy)


## The shader's value_noise(p): smooth value noise in [0, 1] on the unit lattice, the
## lattice hashed with the map seed (the shader's breakup_seed).
static func value_noise(p: Vector2, seed_value: int) -> float:
	var ix := floori(p.x)
	var iz := floori(p.y)
	var u := Vector2(p.x - ix, p.y - iz)
	u = u * u * (Vector2(3.0, 3.0) - 2.0 * u)
	var cx := (ix + seed_value) & _MASK32
	var cz := (iz + ((seed_value * 7919) & _MASK32)) & _MASK32
	var a := float(pcg2d(cx, cz).x)
	var b := float(pcg2d((cx + 1) & _MASK32, cz).x)
	var d := float(pcg2d(cx, (cz + 1) & _MASK32).x)
	var e := float(pcg2d((cx + 1) & _MASK32, (cz + 1) & _MASK32).x)
	return lerpf(lerpf(a, b, u.x), lerpf(d, e, u.x), u.y) * INV_UINT_MAX


## Two-octave rule noise in [0, 1] at map-frame point (xz, y), the domain sheared by height
## so it varies up a face too.
static func rule_noise(xz: Vector2, y: float, offset: Vector2, seed_value: int) -> float:
	var p := (xz + Vector2(y * RULE_NOISE_SHEAR, -y * RULE_NOISE_SHEAR)) / RULE_NOISE_SCALE_M
	p += offset
	return (
		value_noise(p, seed_value) * 0.65
		+ value_noise(p * 2.3 + Vector2(5.2, -1.7), seed_value) * 0.35
	)


# ---------------------------------------------------------------------------------------
# Rules
# ---------------------------------------------------------------------------------------


## Cliff weight 0..1 at a point with shading normal y `normal_y`, curvature `curvature`
## (m, sample_fields) and edge noise value `noise` (rule_noise with CLIFF_NOISE_OFFSET).
static func cliff_from(normal_y: float, curvature: float, noise: float) -> float:
	var raw := raw_tail(normal_y, cliff_start_cos(), cliff_end_cos())
	var m := clampf(raw + lerpf(-CLIFF_EDGE_NOISE, CLIFF_EDGE_NOISE, noise), 0.0, 1.0)
	var lip := tail(curvature, LIP_CURVATURE_START, LIP_CURVATURE_END)
	lip *= clampf(LIP_SHEER_TAIL - raw, 0.0, 1.0)
	m *= 1.0 - LIP_STRENGTH * lip
	return ease_ramp(m)


## Scree weight 0..1 given curvature, steepness nearby, the cliff weight at the point, the
## edge noise value `noise` (rule_noise with SCREE_NOISE_OFFSET) and the breakup noise
## `breakup` (scree_breakup): the concave tail with its edge noise, times the steepness
## tail, shaped, broken up, and never under the cliff.
static func scree_from(
	curvature: float, steep: float, cliff: float, noise: float, breakup: float
) -> float:
	var near := tail(steep, SCREE_NEAR_START, SCREE_NEAR_END)
	if near <= 0.0:
		return 0.0
	var concave := raw_tail(-curvature, SCREE_CURVATURE_START, SCREE_CURVATURE_END)
	concave += lerpf(-SCREE_EDGE_NOISE, SCREE_EDGE_NOISE, noise) + (breakup - 0.5) * SCREE_FAN
	concave = clampf(concave, 0.0, 1.0)
	var gaps := smoothstep(SCREE_BREAKUP_LOW, SCREE_BREAKUP_HIGH, breakup)
	return ease_ramp(concave * near) * gaps * (1.0 - cliff)


## The scree breakup noise in [0, 1] at map-frame XZ (one octave, SCREE_BREAKUP_SCALE_M).
static func scree_breakup(xz: Vector2, seed_value: int) -> float:
	return value_noise(xz / SCREE_BREAKUP_SCALE_M + SCREE_BREAKUP_OFFSET, seed_value)


## Vector2(cliff, scree) at a map-frame point: shading normal y, the interpolated fields
## (Vector2(curvature, steep), field_at) and the map seed.
static func weights(
	normal_y: float, fields: Vector2, xz: Vector2, y: float, seed_value: int
) -> Vector2:
	var cliff := 0.0
	# Below this n.y the tail cannot reach 0 whatever the noise: flat ground skips the noise.
	if raw_tail(normal_y, cliff_start_cos(), cliff_end_cos()) > -CLIFF_EDGE_NOISE:
		cliff = cliff_from(normal_y, fields.x, rule_noise(xz, y, CLIFF_NOISE_OFFSET, seed_value))
	var scree := 0.0
	# Likewise: no scree away from steep ground, or where even the noise leaves none.
	var concave := raw_tail(-fields.x, SCREE_CURVATURE_START, SCREE_CURVATURE_END)
	if fields.y > SCREE_NEAR_START and concave > -SCREE_EDGE_NOISE - 0.5 * SCREE_FAN:
		scree = scree_from(
			fields.x,
			fields.y,
			cliff,
			rule_noise(xz, y, SCREE_NOISE_OFFSET, seed_value),
			scree_breakup(xz, seed_value)
		)
	return Vector2(cliff, scree)


## The painted-surface shaping the shader applies to a painted total `total` (0..1) at
## map-frame `xz`: edge noise on partial paint only (0 and 1 stay put). Returns the shaped
## total; each painted channel scales by shaped / total.
static func shape_painted(total: float, xz: Vector2, seed_value: int) -> float:
	if total <= 0.0:
		return 0.0
	var p := xz / PAINT_EDGE_SCALE_M
	var n := value_noise(p * 2.9 + PAINT_NOISE_OFFSET, seed_value)
	var bump := 4.0 * total * (1.0 - total)
	return clampf(total + (n - 0.5) * 2.0 * PAINT_EDGE_NOISE * bump, 0.0, 1.0)


## Where the shader reads the painted weight map for point `xz`: the point displaced by the
## painted edge warp.
static func painted_lookup(xz: Vector2, seed_value: int) -> Vector2:
	var p := xz / PAINT_EDGE_SCALE_M
	var warp := Vector2(
		value_noise(p + PAINT_WARP_OFFSET_A, seed_value),
		value_noise(p + PAINT_WARP_OFFSET_B, seed_value)
	)
	return xz + (warp * 2.0 - Vector2.ONE) * PAINT_EDGE_WARP_M


# ---------------------------------------------------------------------------------------
# Per-vertex fields
# ---------------------------------------------------------------------------------------


## Curvature and steepness nearby for the samples of `rect` (grid coordinates, clipped to
## the grid) of the row-major `heights` grid: {"rect": Rect2i (clipped), "curvature":
## PackedFloat32Array, "steep": PackedFloat32Array}, row-major over the rect. Curvature is
## (h - box mean of h) * n.y, steepness the box mean of slope_tail(n.y), both means over
## (2 r + 1)^2 samples (r = radius_samples) with the grid edge clamped (replicated), so the
## map edge is neither convex nor concave. Normals are the mesh's (central differences on
## the whole grid). Sums run on separable sliding windows: each output sample costs a few
## operations whatever the radius.
static func sample_fields(
	heights: PackedFloat32Array, columns: int, rows: int, step: Vector2, rect: Rect2i
) -> Dictionary:
	var grid := Rect2i(0, 0, columns, rows)
	var out := rect.intersection(grid)
	var curvature := PackedFloat32Array()
	var steep := PackedFloat32Array()
	if not out.has_area() or heights.size() < columns * rows:
		return {"rect": out, "curvature": curvature, "steep": steep}
	var r := radius_samples(minf(step.x, step.y))
	# Input window: the rect grown by r (clamped reads beyond the grid replicate the edge).
	var x_lo := out.position.x - r
	var x_hi := out.end.x - 1 + r
	var z_lo := out.position.y - r
	var z_hi := out.end.y - 1 + r
	var in_rows := z_hi - z_lo + 1
	var width := out.size.x
	# Normal y and slope tail over the rows of the window, columns of the window.
	var in_cols := x_hi - x_lo + 1
	var ny_window := PackedFloat32Array()
	ny_window.resize(in_rows * in_cols)
	var start_cos := cliff_start_cos()
	var end_cos := cliff_end_cos()
	var inv_span := 1.0 / (end_cos - start_cos)
	for wz in in_rows:
		var sz := clampi(z_lo + wz, 0, rows - 1)
		var z0 := maxi(sz - 1, 0)
		var z1 := mini(sz + 1, rows - 1)
		var inv_dz := 1.0 / ((z1 - z0) * step.y)
		var here := sz * columns
		for wx in in_cols:
			var sx := clampi(x_lo + wx, 0, columns - 1)
			var x0 := maxi(sx - 1, 0)
			var x1 := mini(sx + 1, columns - 1)
			var slope_x := (heights[here + x1] - heights[here + x0]) / ((x1 - x0) * step.x)
			var slope_z := (heights[z1 * columns + sx] - heights[z0 * columns + sx]) * inv_dz
			ny_window[wz * in_cols + wx] = 1.0 / sqrt(1.0 + slope_x * slope_x + slope_z * slope_z)
	# Horizontal pass: per window row, box sums of h and of the slope tail for each output
	# column.
	var h_rows := PackedFloat32Array()
	var t_rows := PackedFloat32Array()
	h_rows.resize(in_rows * width)
	t_rows.resize(in_rows * width)
	for wz in in_rows:
		var sz := clampi(z_lo + wz, 0, rows - 1)
		var here := sz * columns
		var base := wz * in_cols
		var sum_h := 0.0
		var sum_t := 0.0
		for k in range(0, 2 * r + 1):
			sum_h += heights[here + clampi(x_lo + k, 0, columns - 1)]
			sum_t += clampf((ny_window[base + k] - start_cos) * inv_span, 0.0, 1.0)
		for ox in width:
			h_rows[wz * width + ox] = sum_h
			t_rows[wz * width + ox] = sum_t
			if ox + 1 < width:
				var drop := ox
				var add := ox + 2 * r + 1
				sum_h += (
					heights[here + clampi(x_lo + add, 0, columns - 1)]
					- heights[here + clampi(x_lo + drop, 0, columns - 1)]
				)
				sum_t += (
					clampf((ny_window[base + add] - start_cos) * inv_span, 0.0, 1.0)
					- clampf((ny_window[base + drop] - start_cos) * inv_span, 0.0, 1.0)
				)
	# Vertical pass.
	var count := out.size.x * out.size.y
	curvature.resize(count)
	steep.resize(count)
	var inv_area := 1.0 / float((2 * r + 1) * (2 * r + 1))
	for ox in width:
		var sum_h := 0.0
		var sum_t := 0.0
		for k in range(0, 2 * r + 1):
			sum_h += h_rows[k * width + ox]
			sum_t += t_rows[k * width + ox]
		for oz in out.size.y:
			var wz := oz + r
			var sx := out.position.x + ox
			var sz := out.position.y + oz
			var ny := ny_window[wz * in_cols + (sx - x_lo)]
			var i := oz * width + ox
			curvature[i] = (heights[sz * columns + sx] - sum_h * inv_area) * ny
			steep[i] = sum_t * inv_area
			if oz + 1 < out.size.y:
				sum_h += h_rows[(oz + 2 * r + 1) * width + ox] - h_rows[oz * width + ox]
				sum_t += t_rows[(oz + 2 * r + 1) * width + ox] - t_rows[oz * width + ox]
	return {"rect": out, "curvature": curvature, "steep": steep}


## Writes sample_fields() output into whole-grid arrays `curvature` / `steep` (each
## columns * rows long).
static func store_fields(
	fields: Dictionary, columns: int, curvature: PackedFloat32Array, steep: PackedFloat32Array
) -> void:
	var rect: Rect2i = fields.rect
	var c: PackedFloat32Array = fields.curvature
	var s: PackedFloat32Array = fields.steep
	for oz in rect.size.y:
		var row := (rect.position.y + oz) * columns + rect.position.x
		var at := oz * rect.size.x
		for ox in rect.size.x:
			curvature[row + ox] = c[at + ox]
			steep[row + ox] = s[at + ox]


## The fields interpolated at continuous sample coordinates `at` over the terrain's own
## triangle (the same split and barycentric weights as ScatterGenerator.triangle_height),
## which is how the shader receives them from the vertices: Vector2(curvature, steep).
## `curvature` / `steep` are whole-grid arrays (store_fields).
static func field_at(
	curvature: PackedFloat32Array, steep: PackedFloat32Array, columns: int, rows: int, at: Vector2
) -> Vector2:
	var fx := clampf(at.x, 0.0, columns - 1)
	var fz := clampf(at.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * columns + x0
	if tx + tz <= 1.0:
		var w0 := 1.0 - tx - tz
		return Vector2(
			curvature[i] * w0 + curvature[i + 1] * tx + curvature[i + columns] * tz,
			steep[i] * w0 + steep[i + 1] * tx + steep[i + columns] * tz
		)
	var w11 := tx + tz - 1.0
	var j := i + columns + 1
	return Vector2(
		curvature[j] * w11 + curvature[i + columns] * (1.0 - tx) + curvature[i + 1] * (1.0 - tz),
		steep[j] * w11 + steep[i + columns] * (1.0 - tx) + steep[i + 1] * (1.0 - tz)
	)
