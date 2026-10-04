class_name WaterFlowBaker
extends RefCounted

## Bakes the map-wide flow map of a MapDocument's rivers: a port of terrain-paint's
## engine/flow_bake.py field (the formulas are in its module and in the phase 4 survey),
## with the wet mask read from the document's heights instead of ray casts. Pure and
## deterministic; the result ships in the document (MapDocument.water_flow), peers never
## rebake. Summary: docs/ARCHITECTURE.md "Water model and flow bake".
##
## Frame (the contract with water.gdshader's water_flow() for the merged authored water
## mesh, which sits at the map origin with an identity transform and map-normalised UVs
## u = (x + W/2) / W, v = (z + H/2) / H over the W x H metre map):
##   texel (i, j) is image column i, row j (row 0 is the first row of the Image, which
##   Godot samples at v near 0); its centre is u = (i + 0.5) / nx, v = (j + 0.5) / nz,
##   so map x = u * W - W/2, z = v * H - H/2.
##   R, G = (flow x, -flow z) * 0.5 + 0.5 as bytes (round(value * 255)): the shader reads
##   f = rg * 2 - 1 as Blender-style local (x, y) and turns it into local (f.x, 0, -f.y),
##   which with the identity transform is map (x, z). |f| is the 0..1 speed factor.
##   Every border texel is still water (128, 128), so clamp-to-edge sampling off the map
##   reads as still.
##
## Field, as terrain-paint: each river's course is its control line Chaikin-smoothed twice
## (WaterGeometry.river_course()); per texel the nearest segment's distance d and unit
## tangent t per river; weights w = 1 / (d + 1e-3)^2 within the river's reach (half-width
## at the nearest point plus WaterGeometry.RIVER_BANK_M, terrain-paint's tp_flow_radius);
## F = sum(w t speed) / sum(w), deliberately not renormalised (disagreeing rivers weaken
## toward still water at a confluence); F box-averaged over SMOOTHING_M; |F| clamped to 1;
## then F *= bank fade, the wet mask box-blurred 3x3 bank_fade_passes() times. A texel is
## wet when its bilinear ground is below the water level of its nearest sample
## (WaterGeometry.levels()), so ponds are wet but add no flow: still water. The cascade
## sheets over the steps between reaches and at run-out ends are wet too
## (WaterMeshBuilder.cascades(), P4-3), so a rapid runs downstream, and so are the faces of
## the waterfalls (WaterFalls.footprint(), P4c-3), so the bank fade does not cut the flow at
## a lip: the pool above runs into the pool below. The curtain itself never reads the map.

## Nominal texel size: about the default sample spacing (a 200 ft map bakes 244 x 244).
const TEXEL_M := 0.25
const MIN_TEXELS := 8
## Largest bake per axis; the reader accepts up to MapDocument.MAX_FLOW_TEXELS.
const MAX_BAKE_TEXELS := 512
## terrain-paint's constants.
const IDW_EPSILON := 1e-3
const SMOOTHING_M := 0.75
const BANK_FADE_PASSES_AT_512 := 3
## The byte of zero flow.
const STILL := 128


## Texels per axis for a map of `extent` metres: extent / TEXEL_M rounded up, clamped to
## MIN_TEXELS..MAX_BAKE_TEXELS.
static func resolution_for(extent: Vector2) -> Vector2i:
	return Vector2i(
		clampi(ceili(extent.x / TEXEL_M - 1e-6), MIN_TEXELS, MAX_BAKE_TEXELS),
		clampi(ceili(extent.y / TEXEL_M - 1e-6), MIN_TEXELS, MAX_BAKE_TEXELS)
	)


## terrain-paint's bank_fade_passes() for the longer axis.
static func bank_fade_passes(size: Vector2i) -> int:
	return maxi(1, roundi(BANK_FADE_PASSES_AT_512 * maxi(size.x, size.y) / 512.0))


## The flow map of `doc` at `size` texels (resolution_for() by default): RG8 pixel data,
## size.x * size.y * 2 bytes, in the frame of the header.
static func bake(doc: MapDocument, size: Vector2i = Vector2i.ZERO) -> PackedByteArray:
	var texels := size if size.x > 0 and size.y > 0 else resolution_for(doc.extent_m())
	var extent := doc.extent_m()
	var step := extent / Vector2(texels)
	var origin := -extent * 0.5 + step * 0.5
	var fade := _box_blur(_wet(doc, texels, origin, step), texels, bank_fade_passes(texels))
	var field := _river_field(doc, texels, origin, step)
	var radius := Vector2i(roundi(SMOOTHING_M / step.x), roundi(SMOOTHING_M / step.y))
	var flow_x: PackedFloat32Array = field[0]
	var flow_z: PackedFloat32Array = field[1]
	if texels.x > 1:
		flow_x = _box_mean(flow_x, texels, radius)
		flow_z = _box_mean(flow_z, texels, radius)
	return _encode(flow_x, flow_z, fade, texels)


## The baked data as an Image for the water material (FORMAT_RG8, no mipmaps).
static func to_image(rg: PackedByteArray, size: Vector2i) -> Image:
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RG8, rg)


## 1.0 where a texel is wet (see the header), else 0.0.
static func _wet(
	doc: MapDocument, texels: Vector2i, origin: Vector2, step: Vector2
) -> PackedFloat32Array:
	var at_level := WaterGeometry.levels(doc)
	var wet := PackedFloat32Array()
	wet.resize(texels.x * texels.y)
	var any := false
	for level in at_level:
		if level != WaterGeometry.DRY:
			any = true
			break
	if not any:
		return wet
	var width := doc.samples_x()
	# The sheets over reach steps flow too (WaterMeshBuilder.cascades), and the faces of the
	# falls (WaterFalls.footprint).
	var sheets := WaterMeshBuilder.cascades(doc)
	for at in WaterFalls.footprint(doc):
		sheets[at] = true
	for j in texels.y:
		for i in texels.x:
			var xz := origin + Vector2(i, j) * step
			var sample := doc.world_to_sample(xz).round()
			var at := int(sample.y) * width + int(sample.x)
			var level := at_level[at]
			if level != WaterGeometry.DRY and WaterGeometry.ground_at(doc, xz) < level:
				wet[j * texels.x + i] = 1.0
			elif sheets.has(at):
				wet[j * texels.x + i] = 1.0
	return wet


## The blended river field before smoothing: [flow_x, flow_z] per texel.
static func _river_field(
	doc: MapDocument, texels: Vector2i, origin: Vector2, step: Vector2
) -> Array:
	var count := texels.x * texels.y
	var weight_sum := PackedFloat32Array()
	var sum_x := PackedFloat32Array()
	var sum_z := PackedFloat32Array()
	weight_sum.resize(count)
	sum_x.resize(count)
	sum_z.resize(count)
	var bank := WaterGeometry.RIVER_BANK_M
	for body in doc.water_bodies:
		if not body.is_river():
			continue
		var course := WaterGeometry.river_course(body)
		var field := WaterGeometry.nearest_field(course[0], course[1], origin, step, texels, bank)
		var rect: Rect2i = field["rect"]
		var distance: PackedFloat32Array = field["distance"]
		var half_width: PackedFloat32Array = field["half_width"]
		var tangent_x: PackedFloat32Array = field["tangent_x"]
		var tangent_z: PackedFloat32Array = field["tangent_z"]
		for j in rect.size.y:
			var row := (rect.position.y + j) * texels.x + rect.position.x
			for i in rect.size.x:
				var k := j * rect.size.x + i
				var d := distance[k]
				if d > half_width[k] + bank:
					continue
				var w := 1.0 / ((d + IDW_EPSILON) * (d + IDW_EPSILON))
				weight_sum[row + i] += w
				sum_x[row + i] += w * tangent_x[k] * body.speed
				sum_z[row + i] += w * tangent_z[k] * body.speed
	for k in count:
		if weight_sum[k] > 0.0:
			sum_x[k] /= weight_sum[k]
			sum_z[k] /= weight_sum[k]
	return [sum_x, sum_z]


## `passes` rounds of a 3x3 box blur with replicated edges (terrain-paint's box_blur()),
## run as a horizontal then a vertical 3-tap pass, which is the same filter.
static func _box_blur(
	values: PackedFloat32Array, texels: Vector2i, passes: int
) -> PackedFloat32Array:
	var out := values
	for _pass in passes:
		out = _box_mean(out, texels, Vector2i.ONE)
	return out


## The mean over a (2 radius.x + 1) x (2 radius.y + 1) window with replicated edges
## (terrain-paint's smooth_vector_field() per channel), as two running-sum passes.
static func _box_mean(
	values: PackedFloat32Array, texels: Vector2i, radius: Vector2i
) -> PackedFloat32Array:
	var width := texels.x
	var depth := texels.y
	var rows := values
	if radius.x > 0:
		rows = PackedFloat32Array()
		rows.resize(values.size())
		var window := 2 * radius.x + 1
		for j in depth:
			var base := j * width
			var sum := 0.0
			for d in range(-radius.x, radius.x + 1):
				sum += values[base + clampi(d, 0, width - 1)]
			for i in width:
				rows[base + i] = sum / window
				sum += values[base + mini(i + radius.x + 1, width - 1)]
				sum -= values[base + maxi(i - radius.x, 0)]
	if radius.y <= 0:
		return rows
	var out := PackedFloat32Array()
	out.resize(values.size())
	var tall := 2 * radius.y + 1
	for i in width:
		var sum := 0.0
		for d in range(-radius.y, radius.y + 1):
			sum += rows[clampi(d, 0, depth - 1) * width + i]
		for j in depth:
			out[j * width + i] = sum / tall
			sum += rows[mini(j + radius.y + 1, depth - 1) * width + i]
			sum -= rows[maxi(j - radius.y, 0) * width + i]
	return out


## Clamp |F| to 1, apply the bank fade, pack (x, -z) and force the border still.
static func _encode(
	flow_x: PackedFloat32Array,
	flow_z: PackedFloat32Array,
	fade: PackedFloat32Array,
	texels: Vector2i
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(texels.x * texels.y * 2)
	out.fill(STILL)
	for j in range(1, texels.y - 1):
		for i in range(1, texels.x - 1):
			var k := j * texels.x + i
			if fade[k] <= 0.0:
				continue
			var f := Vector2(flow_x[k], -flow_z[k])
			var length := f.length()
			if length > 1.0:
				f /= length
			f *= fade[k]
			out[k * 2] = clampi(roundi((f.x * 0.5 + 0.5) * 255.0), 0, 255)
			out[k * 2 + 1] = clampi(roundi((f.y * 0.5 + 0.5) * 255.0), 0, 255)
	return out
