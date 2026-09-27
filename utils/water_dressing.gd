class_name WaterDressing
extends RefCounted

## The automatic wet dressing of an authored map's ground (phase 4, P4-3), pure: per sample
## how much of the ground is the biome's water bed (under the water) and its wet shore (just
## above it, fading into the biome ground), and the water's depth, from the document's
## heights and water levels. A rule layer like the cliff and scree (TerrainRules), not paint:
## it takes no paint slot and follows the water wherever it is carved, painted or erased.
## Summary: docs/ARCHITECTURE.md "Carving water" (dressing).
##
## Field (compute()): RGBA8 on the sample grid, the layout of the ground shader's
## water_weights texture, so the shader and the CPU (ScatterGround, TerrainRules
## .compose_water) read the same bytes with the same bilinear filter and cannot drift:
##   R  bed weight: smoothstep(BED_START_M, BED_FULL_M, depth) with the thresholds moved by
##      up to BED_NOISE_M of noise, so the bed's edge wanders along the waterline;
##   G  shore weight: near the water (shore_weight(): a core band along the waterline and
##      noise-driven patches reaching SHORE_FAR_M, so the bank is a wet line with drifts of
##      mud or sand, not an outline) and low over it (the height above the nearest water's
##      level fades out between RISE_START_M and RISE_END_M, so a high cut bank keeps its
##      ground and a low bar is mud to its top);
##   B  the water's depth in centimetres (0..255), for the plants;
##   A  the wet line: 1 under the water and on a riffle, falling to 0 over WET_LINE_M above
##      the waterline (and with the height over it); the shader darkens and glosses it.
## depth is level - ground, level being the sample's own water level where a body's area
## holds it, else the level of the nearest wet sample (DistanceField). Samples farther than
## the shore band from any water are all 0; with no wet sample the field is empty.
##
## Surfaces. The ground shader draws the bed weight with the biome's water_bed_surface and
## the shore weight with its shore_surface (PaletteLibrary; defaults per biome when the
## palette has none), routed per ground component like cliff and scree (GroundLayerTable).

const BED_START_M := -0.04
const BED_FULL_M := 0.1
const BED_NOISE_M := 0.03
## The shore: a core band along the waterline (full to SHORE_NEAR_M, gone by SHORE_CORE_M,
## both moved by up to SHORE_NOISE_M), and patches reaching out to SHORE_FAR_M where a broad
## noise (PATCH_SCALE_M) passes PATCH_LOW..PATCH_HIGH, so the bank is a wet line with drifts
## of mud or sand, never a uniform outline.
const SHORE_NEAR_M := 0.15
const SHORE_CORE_M := 0.8
const SHORE_FAR_M := 2.4
const SHORE_NOISE_M := 0.3
const SHORE_NOISE_SCALE_M := 1.6
const PATCH_SCALE_M := 3.2
const PATCH_LOW := 0.45
const PATCH_HIGH := 0.62
const RISE_START_M := 0.3
const RISE_END_M := 0.8
## The wet line (A): the ground under the water and a strip WET_LINE_M wide above it, low
## over the water (fading between WET_RISE_*), which the ground shader darkens and glosses
## whatever surface it is (wet sand, wet grass roots), the cue that reads as a waterline.
const WET_LINE_M := 0.8
const WET_RISE_START_M := 0.12
const WET_RISE_END_M := 0.45
## Depth byte per metre.
const DEPTH_SCALE := 100.0
const CHANNELS := 4
const BED_NOISE_OFFSET := Vector2(41.7, -13.3)
const SHORE_NOISE_OFFSET := Vector2(-5.9, 77.1)
const PATCH_NOISE_OFFSET := Vector2(23.3, 51.9)

## The dressing field of `doc` for per-sample water `levels` (WaterGeometry.levels(); see the
## header) and `channel` (1 per sample under a cascade sheet, WaterMeshBuilder.cascades():
## the riffles between reaches are bed too, and the shore follows them). Empty when no
## sample is wet or in a channel.
@warning_ignore("integer_division")
static func compute(
	doc: MapDocument, levels: PackedFloat32Array, channel: PackedByteArray = PackedByteArray()
) -> PackedByteArray:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var count := columns * rows
	var heights := doc.heights
	if levels.size() != count or heights.size() != count:
		return PackedByteArray()
	var channels := channel.size() == count
	var wet_rect := Rect2i()
	for z in rows:
		var row := z * columns
		var first := -1
		var last := -1
		for x in columns:
			if heights[row + x] < levels[row + x] or (channels and channel[row + x] != 0):
				if first < 0:
					first = x
				last = x
		if first >= 0:
			wet_rect = MaskBrush.merge_rect(wet_rect, Rect2i(first, z, last - first + 1, 1))
	if not wet_rect.has_area():
		return PackedByteArray()
	var step := doc.sample_step()
	var reach := SHORE_FAR_M + SHORE_NOISE_M + 0.5
	var pad := ceili(reach / minf(step.x, step.y))
	var rect := wet_rect.grow(pad).intersection(Rect2i(0, 0, columns, rows))
	var feature := PackedByteArray()
	feature.resize(rect.size.x * rect.size.y)
	for j in rect.size.y:
		var row := (rect.position.y + j) * columns + rect.position.x
		for i in rect.size.x:
			var at := row + i
			if heights[at] < levels[at] or (channels and channel[at] != 0):
				feature[j * rect.size.x + i] = 1
	var field := DistanceField.transform(feature, rect.size.x, rect.size.y, step)
	var distance_sq: PackedFloat32Array = field.distance_sq
	var nearest: PackedInt32Array = field.nearest
	var out := PackedByteArray()
	out.resize(count * CHANNELS)
	var seed_value := doc.map_seed & 0x7FFFFFFF
	var origin := -doc.extent_m() * 0.5
	var reach_sq := reach * reach
	for j in rect.size.y:
		for i in rect.size.x:
			var k := j * rect.size.x + i
			var d_sq := distance_sq[k]
			if d_sq > reach_sq:
				continue
			var x := rect.position.x + i
			var z := rect.position.y + j
			var at := z * columns + x
			var level := levels[at]
			if level == WaterGeometry.DRY or d_sq > 0.0:
				var from := nearest[k]
				if from < 0:
					continue
				var fz: int = from / rect.size.x
				var fx: int = from - fz * rect.size.x
				var own := level
				level = levels[(rect.position.y + fz) * columns + rect.position.x + fx]
				if own != WaterGeometry.DRY:
					level = maxf(level, own)
			var h := heights[at]
			var depth := level - h
			var p := origin + Vector2(x, z) * step
			var bed := 0.0
			if channels and channel[at] != 0:
				bed = 1.0
			elif depth > BED_START_M - BED_NOISE_M:
				var n := TerrainRules.value_noise(p / 0.9 + BED_NOISE_OFFSET, seed_value) - 0.5
				var shift := n * 2.0 * BED_NOISE_M
				bed = smoothstep(BED_START_M + shift, BED_FULL_M + shift, depth)
			var shore := 0.0
			# Wet under the water and on a riffle (the distance field's own samples); a dry
			# channel left below a level (an erase) keeps its bed but is not wet.
			var wet := 1.0 if d_sq <= 0.0 else 0.0
			var rise := h - level
			if rise < RISE_END_M:
				var d := sqrt(d_sq)
				shore = shore_weight(d, p, seed_value)
				shore *= 1.0 - smoothstep(RISE_START_M, RISE_END_M, rise)
				if wet == 0.0 and d < WET_LINE_M:
					wet = 1.0 - smoothstep(0.0, WET_LINE_M, d)
					wet *= 1.0 - smoothstep(WET_RISE_START_M, WET_RISE_END_M, rise)
			var b := at * CHANNELS
			out[b] = clampi(roundi(bed * 255.0), 0, 255)
			out[b + 1] = clampi(roundi(shore * 255.0), 0, 255)
			out[b + 2] = clampi(roundi(maxf(depth, 0.0) * DEPTH_SCALE), 0, 255)
			out[b + 3] = clampi(roundi(wet * 255.0), 0, 255)
	return out


## The shore weight `d` metres from the nearest water at map point `p` (see the header),
## before the height fade.
static func shore_weight(d: float, p: Vector2, seed_value: int) -> float:
	if d >= SHORE_FAR_M:
		return 0.0
	var n := TerrainRules.value_noise(p / SHORE_NOISE_SCALE_M + SHORE_NOISE_OFFSET, seed_value)
	var shift := (n - 0.5) * 2.0 * SHORE_NOISE_M
	var core := 1.0 - smoothstep(SHORE_NEAR_M + shift, SHORE_CORE_M + shift, d)
	if d <= SHORE_NEAR_M:
		return core
	var patch := TerrainRules.value_noise(p / PATCH_SCALE_M + PATCH_NOISE_OFFSET, seed_value)
	var patches := smoothstep(PATCH_LOW, PATCH_HIGH, patch)
	patches *= 1.0 - smoothstep(SHORE_CORE_M, SHORE_FAR_M, d)
	return maxf(core, patches)


## compute() for `doc`'s own water (WaterGeometry.levels, and the riffles under the cascade
## sheets, WaterMeshBuilder.cascades, as channel), stored in doc.water_dressing (a derived
## cache the document never saves). Returns the new field.
static func refresh(doc: MapDocument) -> PackedByteArray:
	var field := PackedByteArray()
	if not doc.water_bodies.is_empty():
		var channel := PackedByteArray()
		channel.resize(doc.sample_count())
		for i: int in WaterMeshBuilder.cascades(doc):
			channel[i] = 1
		field = compute(doc, WaterGeometry.levels(doc), channel)
	doc.water_dressing = field
	return field


## The field bilinearly at continuous sample coordinates `s` (the ground shader's filter):
## Vector3(bed, shore, depth metres). Zero with no field.
static func sample(field: PackedByteArray, columns: int, rows: int, s: Vector2) -> Vector3:
	if field.size() != columns * rows * CHANNELS:
		return Vector3.ZERO
	var fx := clampf(s.x, 0.0, columns - 1)
	var fz := clampf(s.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var a := (z0 * columns + x0) * CHANNELS
	var b := a + CHANNELS
	var c := a + columns * CHANNELS
	var d := c + CHANNELS
	var out := Vector3.ZERO
	for ch in 3:
		var top := lerpf(field[a + ch], field[b + ch], tx)
		var bottom := lerpf(field[c + ch], field[d + ch], tx)
		out[ch] = lerpf(top, bottom, tz)
	return Vector3(out.x / 255.0, out.y / 255.0, out.z / DEPTH_SCALE)
