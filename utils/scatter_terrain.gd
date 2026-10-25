class_name ScatterTerrain
extends RefCounted

## The terrain response of a rule (content library step S12a, docs/systems/scatter.md "Terrain
## response"): its slope minimum and its response curves on the slope, height and wet axes, as one
## keep ScatterGenerator._evaluate multiplies in after the slope-maximum test. Pure statics; every
## input is a pure function of the candidate's position, so region independence holds. Split out
## of ScatterGenerator (the lint cap is 1000 lines). The native port (S12b) repeats `keep`
## expression for expression.

## A rule's slope_min_deg is a band edge: full density from the minimum up, fading to none over
## this many degrees BELOW it. No allowance is added (ScatterPlan.SLOPE_ALLOWANCE_DEG is for the
## maximum only).
const SLOPE_MIN_FADE_DEG := 5.0


## Callable(Vector2 map XZ) -> float: the shore weight 0..1 (WaterDressing channel G, bilinear) the
## `wet` axis reads, from the whole-grid stored field so a window never moves it; 0 everywhere on
## a document with no wet dressing.
static func wet_sampler(doc: MapDocument) -> Callable:
	var field := doc.water_dressing
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	if field.size() != doc.sample_count() * WaterDressing.CHANNELS:
		return func(_p: Vector2) -> float: return 0.0
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	return func(p: Vector2) -> float:
		return WaterDressing.sample(field, columns, rows, (p + half) / step).y


## The product of a plan entry's terrain response at `p`, 0..1, only ever lowering the keep: the
## slope minimum band, then the slope, height (the ground's world y) and wet (the shore weight)
## curves, each a ScatterPlan.curve_value. `normal` is the ground normal when the slope maximum
## already fetched it, else Vector3.ZERO. A water_dist curve is planned but not evaluated (S12c).
static func keep(ctx: Dictionary, entry: Dictionary, p: Vector2, normal: Vector3) -> float:
	var result := 1.0
	var curve_slope: PackedFloat64Array = entry.curve_slope
	var slope_min_cos: float = entry.slope_min_cos
	if slope_min_cos > -1.5 or not curve_slope.is_empty():
		if normal == Vector3.ZERO:
			normal = ctx.normal_at.call(p)
		var flatter := slope_min_cos > -1.5 and normal.y > slope_min_cos
		if flatter or not curve_slope.is_empty():
			var angle := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
			if flatter:
				result *= clampf(1.0 - (entry.slope_min - angle) / SLOPE_MIN_FADE_DEG, 0.0, 1.0)
			if not curve_slope.is_empty():
				result *= ScatterPlan.curve_value(curve_slope, angle)
	var curve_height: PackedFloat64Array = entry.curve_height
	if not curve_height.is_empty():
		result *= ScatterPlan.curve_value(curve_height, ctx.height_at.call(p))
	var curve_wet: PackedFloat64Array = entry.curve_wet
	if not curve_wet.is_empty():
		result *= ScatterPlan.curve_value(curve_wet, ctx.wet_at.call(p))
	return result
