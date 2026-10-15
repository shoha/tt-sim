class_name GroundZones
extends RefCounted

## The CPU twin of the ground shader's colour zones (shaders/ground_light_field.gdshaderinc
## zone_color, ported in ground ship card 3b), so the grass masses follow the zones the ground
## draws (ScatterMass: a mass rule's `follow`, `zone_keep`, `zone_family`, `zone_core`,
## `zone_share` and `zone_fill`).
##
## A zone record is built once per biome and map: record() takes the biome's merged ground look
## (GroundLook) and the map seed and returns a read-only Dictionary that ScatterPlan stores on
## each mass entry, so worker threads read it without sharing any mutable state. {} (no
## ground_look) turns every zone test off: a swathe keeps its rule's angle and every parent is
## kept. Two maps of one biome differ by the seed offset alone (seed_offset), and a level stores
## no zone field.
##
## The functions mirror the shader's: value noise over a fract hash (no sine, so the CPU and the
## GPU agree), zone shapes in a domain-warped, stretched and turned frame with a ragged-edge
## octave, soft masks laid over one another, and each mask resolved per brush stroke. Keep them
## in step with the shader (the comment pair on _stroke_pick and zone_stroke_pick).

## The three zone shapes' noise offsets (ground_light_field.gdshaderinc zone_color).
const ZONE_OFFSETS := [Vector2(17.3, -4.1), Vector2(-23.9, 11.7), Vector2(7.7, 29.3)]
## The step (metres) of zone_flow's central differences.
const ZONE_FLOW_STEP_M := 1.0
## The seed offset's reach either way (metres).
const SEED_REACH_M := 300.0


## The zone offset (metres) of a map seed, a few hundred metres either way, so two maps of one
## biome draw different zones; seed 0 draws the zones unshifted. The ground's zone_seed_m.
static func seed_offset(map_seed: int) -> Vector2:
	if map_seed == 0:
		return Vector2.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	return Vector2(
		rng.randf_range(-SEED_REACH_M, SEED_REACH_M), rng.randf_range(-SEED_REACH_M, SEED_REACH_M)
	)


## The read-only zone record of a merged ground look on map seed `map_seed`, or {} when `look`
## is empty (a biome without a ground_look).
static func record(look: Dictionary, map_seed: int) -> Dictionary:
	if look.is_empty():
		return {}
	var zones: Dictionary = look.zones
	var strokes: Dictionary = look.strokes
	var accent: Dictionary = look.accent_shape
	var stroked := float(strokes.on) > 0.0
	var out := {
		"scale_m": PackedFloat64Array(zones.scale_m),
		"angle": float(zones.angle),
		"angle_k": PackedFloat64Array(zones.angle_k),
		"stretch": float(zones.stretch),
		"stretch_k": PackedFloat64Array(zones.stretch_k),
		"warp": float(zones.warp),
		"cover": PackedFloat64Array(zones.cover),
		"nest": float(zones.nest),
		"seed": seed_offset(map_seed),
		"rag": float(zones.rag),
		"rag_m": float(zones.rag_m),
		"edge": PackedFloat64Array(zones.edge),
		"stroke_edge": float(strokes.edge) if stroked else 1.0,
		"edge_vary": float(zones.edge_vary),
		"edge_vary_m": float(zones.edge_vary_m),
		"stroke": float(strokes.on),
		"stroke_m": float(strokes.m),
		"stroke_len": float(strokes.len),
		"stroke_soft_lo": float(strokes.soft_lo),
		"stroke_soft_hi": float(strokes.soft_hi),
		"stroke_soft_m": float(strokes.soft_m),
		"accent_stretch": float(accent.stretch),
		"accent_stretch_angle": float(accent.stretch_angle),
		"accent_break": float(accent["break"]),
	}
	out.make_read_only()
	return out


## Each zone's share of the ground colour at (x, z) as the ground draws it: zone k's soft mask
## (its edge widened by the strokes' edge and varied along the boundary) resolved per brush
## stroke (_stroke_pick) and laid over the zones before it, so [w0, w1, w2, w3] sum to 1.
static func zone_weights(zones: Dictionary, x: float, z: float) -> PackedFloat64Array:
	var w := PackedFloat64Array([1.0, 0.0, 0.0, 0.0])
	if zones.is_empty():
		return w
	var p := Vector2(x, z) + Vector2(zones.seed)
	var cover: PackedFloat64Array = zones.cover
	var edges: PackedFloat64Array = zones.edge
	var widen := float(zones.stroke_edge)
	for k in 3:
		var share := cover[k]
		if share <= 0.0:
			continue
		var t := lerpf(0.7, 0.3, clampf(share, 0.0, 1.0))
		var e := _edge_at(zones, p, edges[k] * widen, k + 1.0)
		var m := smoothstep(t - e, t + e, _zone_shape(zones, p, _shape_of(zones, k), true))
		m = _stroke_pick(zones, p, m, k + 1)
		for j in k + 1:
			w[j] *= 1.0 - m
		w[k + 1] = m
	return w


## The direction (radians from +X toward +Z) of the contour of the zone shape whose edge lies
## nearest (x, z): each covering zone's field (without its ragged octave) and gradient by central
## differences, its distance to the zone's edge |f - threshold| / |gradient|, and the contour
## (across the gradient) of the nearest, so a swathe turned to it runs with the zone's outline.
static func zone_flow(zones: Dictionary, x: float, z: float) -> float:
	var p := Vector2(x, z) + Vector2(zones.seed)
	var cover: PackedFloat64Array = zones.cover
	var best := INF
	var flow := float(zones.angle)
	for k in 3:
		var share := cover[k]
		if share <= 0.0:
			continue
		var shape := _shape_of(zones, k)
		var f := _zone_shape(zones, p, shape)
		var g := _zone_slope(zones, p, shape)
		var edge := absf(f - lerpf(0.7, 0.3, clampf(share, 0.0, 1.0))) / maxf(g.length(), 1e-4)
		if edge < best:
			best = edge
			flow = atan2(g.x, -g.y)
	return flow


## Mirrors zone_stroke_pick in shaders/ground_light_field.gdshaderinc (keep the two in step):
## zone `k`'s (1..3) weight `m` at `p` (the zone frame, seed added) resolved per brush stroke, so a
## zone edge reads as interleaved strokes rather than a crossfade; `m` without strokes.
static func _stroke_pick(zones: Dictionary, p: Vector2, m: float, k: int) -> float:
	var stroke := float(zones.stroke)
	if stroke <= 0.0 or m <= 0.0 or m >= 1.0:
		return m
	var angle_k: PackedFloat64Array = zones.angle_k
	var angle := float(zones.angle) + angle_k[k - 1]
	var cs := Vector2(cos(angle), sin(angle))
	var r := Vector2(p.dot(cs), p.dot(Vector2(-cs.y, cs.x)))
	var width := float(zones.stroke_m)
	var q := Vector2(r.x / (width * maxf(float(zones.stroke_len), 1.0)), r.y / width)
	var o := Vector2(k * 13.7, -k * 7.9)
	q.y += (_noise(Vector2(q.x * 0.6, q.y * 0.25) + o + Vector2(3.3, 1.1)) - 0.5) * 2.4
	var s := (
		_noise(q + o) * 0.62 + _noise(q * Vector2(1.7, 2.1) + o * 1.3 + Vector2(-4.1, 9.2)) * 0.38
	)
	s = clampf((s - 0.5) * 2.6 + 0.5, 0.0, 1.0)
	var soft_m := maxf(float(zones.stroke_soft_m), 0.5)
	var soft_n := _noise(p / soft_m + o * 0.5 + Vector2(-6.6, 2.4))
	var soft := lerpf(
		float(zones.stroke_soft_lo), float(zones.stroke_soft_hi), smoothstep(0.3, 0.7, soft_n)
	)
	s = lerpf(soft, 1.0 - soft, s)
	return lerpf(m, smoothstep(s - soft, s + soft, m), stroke)


## zone_edge_at: zone k's edge width varying along its boundary.
static func _edge_at(zones: Dictionary, xz: Vector2, edge: float, k: float) -> float:
	var vary := float(zones.edge_vary)
	if vary <= 0.0:
		return edge
	var q := xz / maxf(float(zones.edge_vary_m), 0.5) + Vector2(k * 7.31, -k * 3.17)
	var n := smoothstep(0.3, 0.7, _noise(q) * 0.75 + _noise(q * 2.3) * 0.25)
	return edge * lerpf(1.0 - vary, 1.0 + 1.5 * vary, n)


## Zone k's shape as [scale_m, offset, angle, stretch] (nest lays the third zone in the second's
## shape).
static func _shape_of(zones: Dictionary, k: int) -> Array:
	var scale: PackedFloat64Array = zones.scale_m
	var angle_k: PackedFloat64Array = zones.angle_k
	var stretch_k: PackedFloat64Array = zones.stretch_k
	var n := 1 if k == 2 and float(zones.nest) > 0.5 else k
	return [
		scale[n],
		ZONE_OFFSETS[n],
		float(zones.angle) + angle_k[n],
		float(zones.stretch) * stretch_k[n],
	]


## The gradient of a zone's field (without the ragged octave) by central differences.
static func _zone_slope(zones: Dictionary, p: Vector2, shape: Array) -> Vector2:
	var dx := Vector2(ZONE_FLOW_STEP_M, 0.0)
	var dz := Vector2(0.0, ZONE_FLOW_STEP_M)
	return (
		Vector2(
			_zone_shape(zones, p + dx, shape) - _zone_shape(zones, p - dx, shape),
			_zone_shape(zones, p + dz, shape) - _zone_shape(zones, p - dz, shape)
		)
		/ (2.0 * ZONE_FLOW_STEP_M)
	)


## zone_shape, its ragged-edge octave only with `rag`; `shape` is [scale_m, offset, angle,
## stretch].
static func _zone_shape(zones: Dictionary, xz: Vector2, shape: Array, rag := false) -> float:
	var angle: float = shape[2]
	var offset: Vector2 = shape[1]
	var cs := Vector2(cos(angle), sin(angle))
	var r := Vector2(xz.dot(cs) / maxf(float(shape[3]), 0.1), xz.dot(Vector2(-cs.y, cs.x)))
	var p: Vector2 = r / float(shape[0])
	var w := Vector2(
		_noise(p * 0.55 + offset + Vector2(3.7, -1.9)),
		_noise(p * 0.55 + offset + Vector2(-8.3, 6.1))
	)
	p += (w - Vector2(0.5, 0.5)) * 2.0 * float(zones.warp)
	var f := _noise(p + offset) * 0.7 + _noise(p * 2.07 + offset * 1.3 + Vector2(5.1, 2.2)) * 0.3
	if not rag:
		return f
	var q := r / maxf(float(zones.rag_m), 0.1) + (w - Vector2(0.5, 0.5)) * 3.0
	var ragged := _noise(q + offset * 0.7 + Vector2(-2.9, 13.3)) - 0.5
	return f + ragged * float(zones.rag)


## light_field_noise: value noise over light_field_hash, smoothstep-eased.
static func _noise(p: Vector2) -> float:
	var i := p.floor()
	var u := p - i
	u = u * u * (Vector2(3.0, 3.0) - 2.0 * u)
	var a := _hash(i)
	var b := _hash(i + Vector2(1.0, 0.0))
	var c := _hash(i + Vector2(0.0, 1.0))
	var d := _hash(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


## light_field_hash (a fract hash, no sine, so the CPU copy agrees with the GPU's).
static func _hash(p: Vector2) -> float:
	var q := Vector3(
		fposmod(p.x * 0.1031, 1.0), fposmod(p.y * 0.1030, 1.0), fposmod(p.x * 0.0973, 1.0)
	)
	var s := q.dot(Vector3(q.y + 33.33, q.z + 33.33, q.x + 33.33))
	q += Vector3(s, s, s)
	return fposmod((q.x + q.y) * q.z, 1.0)
