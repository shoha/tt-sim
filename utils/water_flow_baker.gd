class_name WaterFlowBaker
extends RefCounted

## Bakes the map-wide flow map of a MapDocument's rivers: a port of terrain-paint's
## engine/flow_bake.py field (the formulas are in its module and in the phase 4 survey),
## with the wet mask read from the document's heights instead of ray casts. Pure and
## deterministic; the result ships in the document (MapDocument.water_flow), so a peer bakes
## only a flow that arrives missing or stale (below). Summary: docs/systems/water.md (Water
## model and flow bake).
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
##   Every border texel repeats the flow of the texel just inside it (EDGE_INSET_TEXELS), so a
##   river that leaves the map keeps its flow to the edge and clamp-to-edge sampling off the map
##   reads as the edge's flow (still where the edge is dry).
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

##
## The flow map is derived data, cached in the document with a stamp of its inputs
## (MapDocument.water_flow_stamp, stamp()): the grid, the tier height, the seed, the heights, the
## pond mask, the bodies in their saved form and BAKE_VERSION. Every bake records its stamp, and
## the load bakes again on a worker (refreshed(), AuthoredLoadPrep.FLOW) when the stored one is
## missing or no longer matches: a level written without a flow, one saved from an older build or
## edited outside the editor never draws its rivers as still water. A fresh flow costs only the
## stamp (about 1 ms on a 200 ft map, 3 to 4 ms on a 320 ft one); a rebake about 0.45 s on a
## 200 ft map and 1 s on a 320 ft one with 27 bodies (2026-11-21).

## Bump whenever bake() gives a different flow for the same document: every stored flow then goes
## stale and is rebaked at its next load.
const BAKE_VERSION := 1
## Hex digits of a stamp.
const STAMP_LENGTH := 16
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
## The border texels copy the flow of the texel this many in from the edge (_encode).
const EDGE_INSET_TEXELS := 1


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


## The stamp of everything bake() reads from `doc` (see the header): STAMP_LENGTH hex digits of a
## SHA-256. Pure, reads only the document, so it runs on any thread.
static func stamp(doc: MapDocument) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var head := PackedFloat64Array(
		[
			BAKE_VERSION,
			doc.size_cells.x,
			doc.size_cells.y,
			doc.cell_size_m,
			doc.sample_spacing_m,
			doc.tier_height_m,
			doc.map_seed,
		]
	)
	ctx.update(head.to_byte_array())
	if not doc.heights.is_empty():
		ctx.update(doc.heights.to_byte_array())
	if not doc.pond_mask.is_empty():
		ctx.update(doc.pond_mask)
	# The bodies in their saved form, so a saved and reloaded document stamps the same.
	var bodies: Array = []
	for body in doc.water_bodies:
		bodies.append(MapWaterIO.body_json(body))
	ctx.update(JSON.stringify(bodies, "", false, true).to_utf8_buffer())
	return ctx.finish().hex_encode().left(STAMP_LENGTH)


## True when `doc` has a river (a flow map to bake).
static func has_river(doc: MapDocument) -> bool:
	for body in doc.water_bodies:
		if body.is_river():
			return true
	return false


## The flow `doc` should carry: {"flow", "size", "stamp"}, the bake at resolution_for() or, with
## no river, no flow at all.
static func baked(doc: MapDocument) -> Dictionary:
	var now := stamp(doc)
	if not has_river(doc):
		return {"flow": PackedByteArray(), "size": Vector2i.ZERO, "stamp": now}
	var size := resolution_for(doc.extent_m())
	return {"flow": bake(doc, size), "size": size, "stamp": now}


## True when the flow `doc` carries is the one baked() would give: its stamp matches and it is
## present exactly when a river runs. `now` is stamp(doc) when the caller has it.
static func is_fresh(doc: MapDocument, now: String = "") -> bool:
	var current := now if now != "" else stamp(doc)
	return doc.water_flow_stamp == current and doc.water_flow.is_empty() != has_river(doc)


## {} when the flow of `doc` is fresh (the stamp's cost only), else baked(doc). Reads the
## document only, so it runs on a worker (AuthoredLoadPrep.FLOW); store() applies the result.
static func refreshed(doc: MapDocument) -> Dictionary:
	if is_fresh(doc, stamp(doc)):
		return {}
	return baked(doc)


## Writes a baked() or refreshed() result into `doc` (nothing for {}).
static func store(doc: MapDocument, result: Dictionary) -> void:
	if result.is_empty():
		return
	doc.water_flow = result["flow"]
	doc.water_flow_size = result["size"]
	doc.water_flow_stamp = result["stamp"]


## refreshed() and store() on the calling thread. True when it baked.
static func ensure(doc: MapDocument) -> bool:
	var result := refreshed(doc)
	store(doc, result)
	return not result.is_empty()


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


## Clamp |F| to 1, apply the bank fade, pack (x, -z). A border texel takes the flow of the texel
## just inside it (EDGE_INSET_TEXELS), so a river that leaves the map keeps its flow out to the
## edge: with the border forced still, the last quarter metre of the in-map water read as still
## water (ice in winter, a pale hairline across the river at the mouth, card painter-water-edge3).
static func _encode(
	flow_x: PackedFloat32Array,
	flow_z: PackedFloat32Array,
	fade: PackedFloat32Array,
	texels: Vector2i
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(texels.x * texels.y * 2)
	out.fill(STILL)
	var inset := mini(EDGE_INSET_TEXELS, (mini(texels.x, texels.y) - 1) >> 1)
	for j in texels.y:
		for i in texels.x:
			var k := j * texels.x + i
			var src := clampi(j, inset, texels.y - 1 - inset) * texels.x
			src += clampi(i, inset, texels.x - 1 - inset)
			if fade[src] <= 0.0:
				continue
			var f := Vector2(flow_x[src], -flow_z[src])
			var length := f.length()
			if length > 1.0:
				f /= length
			f *= fade[src]
			out[k * 2] = clampi(roundi((f.x * 0.5 + 0.5) * 255.0), 0, 255)
			out[k * 2 + 1] = clampi(roundi((f.y * 0.5 + 0.5) * 255.0), 0, 255)
	return out
