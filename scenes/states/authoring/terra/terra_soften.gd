class_name TerraSoften
extends RefCounted

## The Sculpt tool's Soften tile on terrain primitives (card terraform-p2-sculpt; the erase of
## phase2_plan.md section 3): it edits what is there, never adds and never punches. Each held
## frame, the dabs of strokes, levels and terraces under the ring keep 1 - k of their strength,
## k = 1 - exp(-RATE x seconds x falloff) (the falloff HeightBrush's (1 - t^2)^2 of the dab's
## distance to the frame's capsule over the brush radius), and a hill under it keeps 1 - k of its
## height (the falloff over the hill's own radius from its centre). A dab, or a hill, whose share
## of its strength at the press falls under DROP goes; a tier or terrace dab, which has no strength
## to scale, goes once it is half softened (TIER_DROP); a primitive left with no dab is removed.
## Pure: TerraSculpt applies the result as one replace or remove per touched primitive.

## Rate of the softening (per second at the ring's centre): a one-second hold keeps 5 %.
const RATE := 3.0
## Share of its strength at the press under which a dab or a hill goes.
const DROP := 0.05
## The same for a dab without a strength (tier, terrace).
const TIER_DROP := 0.5
## The kinds Soften edits.
const KINDS: Array[int] = [TerraCore.HILL, TerraCore.STROKE, 16, 17]
const TERRACE := 16
const LEVEL := 17


## One Soften frame over a primitive of `kind` with `data`: the capsule from `from` to `to` (map
## XZ) of `radius`, `seconds` of exposure. `factors` is the share of each dab's (a hill's: its
## one) strength left since the press, empty for all 1. Returns {} when the ring changes nothing,
## else {"data" (empty: the primitive goes), "factors"}.
static func frame(
	kind: int,
	data: PackedFloat32Array,
	factors: PackedFloat32Array,
	from: Vector2,
	to: Vector2,
	radius: float,
	seconds: float
) -> Dictionary:
	if kind == TerraCore.HILL:
		return _hill(data, factors, from, to, seconds)
	var stride := 8 if kind == LEVEL else 5
	var n := data.size() / stride
	var out := PackedFloat32Array()
	var left := PackedFloat32Array()
	var touched := false
	for i in n:
		var k := i * stride
		var item := data.slice(k, k + stride)
		var f := factors[i] if i < factors.size() else 1.0
		var d := _distance(item, kind, from, to)
		var w := _falloff(d / radius)
		if w <= 0.0:
			out.append_array(item)
			left.append(f)
			continue
		touched = true
		var keep := exp(-RATE * seconds * w)
		f *= keep
		var strength := _strength_index(kind, item)
		if strength >= 0:
			if f < DROP:
				continue
			item[strength] *= keep
		elif f < TIER_DROP:
			continue
		out.append_array(item)
		left.append(f)
	if not touched:
		return {}
	return {"data": out, "factors": left}


## HeightBrush's falloff of the distance t (in radii): (1 - t^2)^2 inside, 0 outside.
static func _falloff(t: float) -> float:
	if t >= 1.0:
		return 0.0
	var a := 1.0 - t * t
	return a * a


## A hill's frame (see the header): its height scales, the hill goes under DROP.
static func _hill(
	data: PackedFloat32Array, factors: PackedFloat32Array, from: Vector2, to: Vector2, seconds: float
) -> Dictionary:
	var centre := Vector2(data[0], data[1])
	var w := _falloff(_to_segment(centre, from, to) / maxf(data[3], 1e-3))
	if w <= 0.0:
		return {}
	var keep := exp(-RATE * seconds * w)
	var f := (factors[0] if not factors.is_empty() else 1.0) * keep
	if f < DROP:
		return {"data": PackedFloat32Array(), "factors": PackedFloat32Array()}
	var out := data.duplicate()
	out[2] *= keep
	return {"data": out, "factors": PackedFloat32Array([f])}


## The index of a dab's strength within the dab, or -1: a stroke's amount, a flatten's seconds; a
## tier dab (edge 1 or 2) and a terrace dab have none.
static func _strength_index(kind: int, item: PackedFloat32Array) -> int:
	if kind == TerraCore.STROKE:
		return 3
	if kind == LEVEL and int(item[7]) == 0:
		return 6
	return -1


## The distance from a dab to the brush segment: its centre, or for a level capsule the nearest of
## its ends and middle.
static func _distance(item: PackedFloat32Array, kind: int, from: Vector2, to: Vector2) -> float:
	var a := Vector2(item[0], item[1])
	if kind != LEVEL:
		return _to_segment(a, from, to)
	var b := Vector2(item[2], item[3])
	return minf(
		minf(_to_segment(a, from, to), _to_segment(b, from, to)),
		_to_segment((a + b) * 0.5, from, to)
	)


static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
