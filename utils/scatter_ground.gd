class_name ScatterGround
extends RefCounted

## What the ground of an authored map lets grow, for ScatterGenerator.document_fields (phase
## 3, P3-4): plants respect the automatic dressing and the painted surfaces the ground
## shader draws, through the same formulas (TerrainRules, the shader's CPU twin).
##   - On automatic rock nothing grows: density times (1 - cliff share).
##   - Under a painted built surface (role "built": a road, a courtyard) nothing grows:
##     times (1 - built weight), the painted weight shaped as the shader shapes it.
##   - On scree, rock species gather (density times 1 + SCREE_ROCK_BOOST * scree share,
##     capped at full) and everything else thins (times 1 - SCREE_THIN * scree share), so
##     boulders collect at a cliff's foot, per the user's cliff decision.
## The cliff and scree shares are those of the unpainted ground, as the shader hands them
## out: a surface painted by hand overrides the rules, and plants grow on painted grass
## however steep. Pure statics.

## Species rule kind that gathers at cliff feet.
const ROCK_KIND := "rock"
## Judged by eye at the game camera (P3-4 renders): a stronger boost lines every tier foot
## with a row of boulders.
const SCREE_ROCK_BOOST := 0.8
const SCREE_THIN := 0.5


## A sampler for `doc`: Callable(Vector2 map XZ) -> Vector3(open, cliff share, scree share),
## open = (1 - cliff share) * (1 - built weight). The rule fields (curvature, steepness
## nearby) and the painted weights are decoded for the samples of `samples` (grid rect,
## plus one sample around it) only; `built_surfaces` names the palette surfaces with role
## "built". `heights` is the document's heights (or a flat field of the grid's size).
static func sampler(
	doc: MapDocument,
	heights: PackedFloat32Array,
	samples: Rect2i,
	built_surfaces: PackedStringArray
) -> Callable:
	var count := doc.sample_count()
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var seed_value := doc.map_seed & 0x7FFFFFFF
	var curvature := PackedFloat32Array()
	var steep := PackedFloat32Array()
	curvature.resize(count)
	steep.resize(count)
	# One more sample around the rect: a point near its edge interpolates across it.
	var rect := samples.grow(1).intersection(Rect2i(0, 0, columns, rows))
	TerrainRules.store_fields(
		TerrainRules.sample_fields(heights, columns, rows, step, rect), columns, curvature, steep
	)
	var painted := _painted_fields(doc, rect, built_surfaces)
	var painted_total: PackedFloat32Array = painted.total
	var built: PackedFloat32Array = painted.built
	var paints := not painted_total.is_empty()
	return func(p: Vector2) -> Vector3:
		var s := (p + half) / step
		var n := ScatterGenerator.triangle_normal(heights, columns, rows, s, step)
		var fields := TerrainRules.field_at(curvature, steep, columns, rows, s)
		var y := ScatterGenerator.triangle_height(heights, columns, rows, s)
		var rule := TerrainRules.weights(n.y, fields, p, y, seed_value)
		var unpainted := 1.0
		var built_weight := 0.0
		if paints:
			var lookup := (TerrainRules.painted_lookup(p, seed_value) + half) / step
			var total := ScatterGenerator.bilinear(painted_total, columns, rows, lookup)
			if total > 0.0:
				var shaped := TerrainRules.shape_painted(total, p, seed_value)
				unpainted = 1.0 - shaped
				built_weight = (
					ScatterGenerator.bilinear(built, columns, rows, lookup) * shaped / total
				)
		var cliff := rule.x * unpainted
		var scree := rule.y * unpainted
		return Vector3((1.0 - cliff) * (1.0 - built_weight), cliff, scree)


## The painted total and the built weight (0..1) per sample of `rect` (whole-grid arrays,
## empty when the document has no painted surfaces).
static func _painted_fields(
	doc: MapDocument, rect: Rect2i, built_surfaces: PackedStringArray
) -> Dictionary:
	var count := doc.sample_count()
	var total_field := PackedFloat32Array()
	var built := PackedFloat32Array()
	if doc.surface_ids.is_empty() or doc.surface_weights.size() != count * MapDocument.MAX_SURFACES:
		return {"total": total_field, "built": built}
	total_field.resize(count)
	built.resize(count)
	var built_slots := PackedInt32Array()
	for s in doc.surface_ids.size():
		if built_surfaces.has(doc.surface_ids[s]):
			built_slots.append(s)
	var weights := doc.surface_weights
	var columns := doc.samples_x()
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * columns + x
			var total := 0
			for s in doc.surface_ids.size():
				total += weights[MapDocument.surface_offset(i, s, count)]
			if total == 0:
				continue
			total_field[i] = total / 255.0
			var b := 0
			for s in built_slots:
				b += weights[MapDocument.surface_offset(i, s, count)]
			built[i] = b / 255.0
	return {"total": total_field, "built": built}


## Painted density `density` as every species but rock reads it, given a sampler value `g`.
static func density(value: float, g: Vector3) -> float:
	return value * g.x * (1.0 - SCREE_THIN * g.z)


## Painted density as rock species read it, given a sampler value `g`.
static func rock_density(value: float, g: Vector3) -> float:
	return minf(value * (1.0 + SCREE_ROCK_BOOST * g.z), 1.0) * g.x
