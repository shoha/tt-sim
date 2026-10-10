class_name GroundAccents
extends RefCounted

## Ground accents (phase 3, 2026-09-27): broad patches of other ground surfaces mixed into a
## biome's ground by the ground shader, so a biome floor is not one field of one tile (a
## temperate forest read as one flat brown at the game camera; the Blender maps it came from
## carry moss, grass and bare patches). The palette lists them per biome (`ground_accents`,
## docs/ASSET_PIPELINE.md section 9: surface, coverage, scale_m, in priority order);
## GroundLayerTable gives each drawn accent a layer slot and says which ground component
## (a GROUND slot or the base) it belongs to; this class turns that into the shader's accent
## uniforms and is the CPU twin of the shader's patch mask, so the coverage calibration is
## testable headless.
##
## The mask. Per accent, three octaves of smooth value noise on a lattice of scale_m metres,
## the domain rotated (ROTATION) so the lattice's axes do not show and offset per surface and
## map (surface_offset: two biomes' patches of one surface line up across a border, two
## surfaces' patches are unrelated, and every map seed gets its own patches);
## n = (1 - DETAIL - FINE) * broad + DETAIL * detail + FINE * fine. The patch is
## smoothstep(t - EDGE, t + EDGE, n): a ramp well under a metre wide at a 6 m scale, which the
## shader's height blend then frays along the texture detail like every other surface edge.
## Judged at the game camera: two octaves and a wider ramp read as smooth, rounded
## camouflage blobs with a soft stain around them; the finest octave makes the outline ragged
## and opens small holes where an interior is only just over the threshold.
##
## The noise is a lattice texture, not the ground's hashed value noise: noise_image() holds
## NOISE_CELLS x NOISE_CELLS random lattice values per octave (one channel each, tiling), and
## the shader reads one octave with one bilinear fetch at the cell corner plus the
## smoothstepped fraction (the classic smooth-value-noise-from-bilinear trick), which is the
## same value noise TerrainRules.value_noise computes with four pcg2d hashes. Measured
## in-run on a bare temperate forest view with two accents (2026-09-27, RTX 3080, idle GPU;
## docs/PERFORMANCE.md "Ground accents"): about 0.1 ms cheaper than the hashed form.
## The pattern repeats every NOISE_CELLS * scale_m (192 m at 6 m), beyond any map at the game
## camera. The CPU twin reads the same image the same way; the GPU's 8-bit filter weights
## make it differ by far less than the ramp, which only matters for coverage statistics.
##
## The threshold t puts the covered share at `coverage`: n is not uniform (smoothed value
## noise piles up in the middle), so t comes from its measured quantiles
## (COVERAGE_THRESHOLDS; the test re-measures coverage on several seeds). The shader skips an
## octave wherever the ones before it already decide the result (exact, since the ramp
## clamps).
##
## Several accents of one component are drawn in order, each taking its share of what the
## earlier ones left (the shader's `remaining`); with independent noise an entry's visible
## share is its own coverage when its threshold is set for coverage / (1 - the earlier
## coverages) (drawn_coverages). The shares come out of the component's own ground only,
## after the automatic cliff and scree took theirs, and painted surfaces cover everything:
## painted > rules > accents > biome ground.
##
## Plants do not read accents (contract section 9: "the plant scatter does not read them"):
## a moss patch under a forest is still forest floor to the scatter. So nothing here has a
## ScatterGround twin.

## Accents per ground component the shader draws (the first entries; the rest are dropped).
const PER_COMPONENT := GroundLayerTable.ACCENTS_PER_COMPONENT
## Ground components: the eight slots, then the base.
const COMPONENTS := GroundLayerTable.MAX_LAYERS + 1
## Half width of the soft patch edge, in noise units.
const EDGE := 0.045
## Weights of the two finer octaves (the broad one has the rest), and their frequencies
## relative to the broad one.
const DETAIL := 0.3
const DETAIL_SCALE := 2.3
const DETAIL_OFFSET := Vector2(17.3, -5.9)
const FINE := 0.15
const FINE_SCALE := 5.3
const FINE_OFFSET := Vector2(-31.7, 44.1)
## (cos, sin) of the noise domain's rotation.
const ROTATION := Vector2(0.8, 0.6)
## Lattice cells per side of the noise texture (the pattern's period, in cells).
const NOISE_CELLS := 32
## pcg2d seeds of the three octave channels (r, g, b).
const CHANNEL_SEEDS: Array[int] = [0x1b873593, 0x68e31da4, 0x3c6ef372]
## The threshold t for coverage k / 20, k = 0..20: P(n > t) = coverage. Measured with the
## CPU twin (noise()) over 250,000 random points on four seeds' offsets. The ends are past
## the noise's range by more than EDGE (none, all).
const COVERAGE_THRESHOLDS: PackedFloat32Array = [
	1.05,
	0.71919,
	0.67335,
	0.64063,
	0.61424,
	0.59065,
	0.56913,
	0.54898,
	0.53006,
	0.51131,
	0.49284,
	0.47464,
	0.45623,
	0.43739,
	0.41748,
	0.39646,
	0.37359,
	0.34748,
	0.31542,
	0.27131,
	-0.05,
]

static var _noise_data: PackedByteArray = PackedByteArray()
static var _noise_texture: ImageTexture = null


## The lattice values: NOISE_CELLS square, RGBA8, one octave per channel (r broad, g detail,
## b fine), alpha 255. Pure; a new Image each call.
static func noise_image() -> Image:
	return Image.create_from_data(
		NOISE_CELLS, NOISE_CELLS, false, Image.FORMAT_RGBA8, _lattice().duplicate()
	)


## noise_image()'s bytes, made once.
static func _lattice() -> PackedByteArray:
	if _noise_data.is_empty():
		var data := PackedByteArray()
		data.resize(NOISE_CELLS * NOISE_CELLS * 4)
		for y in NOISE_CELLS:
			for x in NOISE_CELLS:
				var at := (y * NOISE_CELLS + x) * 4
				for channel in 3:
					data[at + channel] = TerrainRules.pcg2d_x(x + CHANNEL_SEEDS[channel], y) >> 24
				data[at + 3] = 255
		_noise_data = data
	return _noise_data


## noise_image() as the texture the ground shader binds (accent_noise), made once.
static func noise_texture() -> ImageTexture:
	if _noise_texture == null:
		_noise_texture = ImageTexture.create_from_image(noise_image())
	return _noise_texture


## One octave in [0, 1] at lattice point `p`: the lattice values of `channel` around it
## (wrapping every NOISE_CELLS), interpolated with smoothstep weights, as the shader's
## single bilinear fetch at the smoothed position computes it.
static func octave(p: Vector2, channel: int) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var f := Vector2(p.x - ix, p.y - iy)
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var data := _lattice()
	var x0 := posmod(ix, NOISE_CELLS)
	var y0 := posmod(iy, NOISE_CELLS)
	var x1 := (x0 + 1) % NOISE_CELLS
	var y1 := (y0 + 1) % NOISE_CELLS
	var a := data[(y0 * NOISE_CELLS + x0) * 4 + channel]
	var b := data[(y0 * NOISE_CELLS + x1) * 4 + channel]
	var c := data[(y1 * NOISE_CELLS + x0) * 4 + channel]
	var d := data[(y1 * NOISE_CELLS + x1) * 4 + channel]
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y) / 255.0


## The accent noise n in [0, 1] at map-frame `xz` for an accent of patch size `scale_m`
## whose domain is offset by `offset` (surface_offset).
static func noise(xz: Vector2, scale_m: float, offset: Vector2) -> float:
	var p := _domain(xz, scale_m, offset)
	var broad := octave(p, 0) * (1.0 - DETAIL - FINE)
	var detail := octave(p * DETAIL_SCALE + DETAIL_OFFSET, 1)
	var fine := octave(p * FINE_SCALE + FINE_OFFSET, 2)
	return broad + detail * DETAIL + fine * FINE


## The patch mask 0..1 (the shader's accent_mask) at `xz` for threshold `threshold`.
static func mask(xz: Vector2, threshold: float, scale_m: float, offset: Vector2) -> float:
	return smoothstep(threshold - EDGE, threshold + EDGE, noise(xz, scale_m, offset))


## The threshold that makes a share `coverage` (0..1) of the ground a patch: linear between
## the measured quantiles; above 1 for no coverage, below 0 for full.
static func threshold(coverage: float) -> float:
	if coverage <= 0.0:
		return COVERAGE_THRESHOLDS[0]
	if coverage >= 1.0:
		return COVERAGE_THRESHOLDS[COVERAGE_THRESHOLDS.size() - 1]
	var steps := COVERAGE_THRESHOLDS.size() - 1
	var at := coverage * steps
	var k := mini(floori(at), steps - 1)
	return lerpf(COVERAGE_THRESHOLDS[k], COVERAGE_THRESHOLDS[k + 1], at - k)


## The coverage each of one component's accents is drawn at, so each ends up with its own
## share of the ground when every entry takes its share of what the earlier ones left:
## coverage_i / (1 - sum of the earlier coverages), clamped to 0..1.
static func drawn_coverages(coverages: PackedFloat32Array) -> PackedFloat32Array:
	var drawn := PackedFloat32Array()
	var taken := 0.0
	for coverage in coverages:
		var left := 1.0 - taken
		drawn.append(clampf(coverage / left, 0.0, 1.0) if left > 1e-4 else 0.0)
		taken += coverage
	return drawn


## The noise domain offset of accent surface `surface` on map seed `map_seed`, in lattice
## cells within one period: a hash of both, stable across runs.
static func surface_offset(surface: String, map_seed: int) -> Vector2:
	var h := surface.hash() & 0x7fffffff
	var s := map_seed & 0x7fffffff
	var a := TerrainRules.pcg2d_x(h, s)
	var b := TerrainRules.pcg2d_x(h ^ 0x68bc21eb, s ^ 0x02e5be93)
	return Vector2(a, b) * TerrainRules.INV_UINT_MAX * NOISE_CELLS


## The ground shader's accent uniforms for a plan's "accents" (GroundLayerTable.plan: per
## component, the drawn accents {slot, coverage, scale_m, surface} in order) on map seed
## `map_seed`:
##   accent_components: int, bit j set when component j (8 = the base) has accents;
##   accent_layer: PackedInt32Array of COMPONENTS * PER_COMPONENT, entry j * PER_COMPONENT + i
##     the slot accent i of component j adds to (8 = the base), -1 past the last;
##   accent_params: PackedVector4Array, the same entries' (threshold, 1 / scale_m, offset).
static func shader_uniforms(accents: Array, map_seed: int) -> Dictionary:
	var components := 0
	var layers := PackedInt32Array()
	var params := PackedVector4Array()
	layers.resize(COMPONENTS * PER_COMPONENT)
	layers.fill(-1)
	params.resize(COMPONENTS * PER_COMPONENT)
	for j in mini(accents.size(), COMPONENTS):
		var entries: Array = accents[j]
		var count := mini(entries.size(), PER_COMPONENT)
		if count == 0:
			continue
		components |= 1 << j
		var coverages := PackedFloat32Array()
		for i in count:
			coverages.append(float(entries[i].coverage))
		var drawn := drawn_coverages(coverages)
		for i in count:
			var entry: Dictionary = entries[i]
			var index := j * PER_COMPONENT + i
			var slot := int(entry.slot)
			layers[index] = GroundLayerTable.MAX_LAYERS if slot == GroundLayerTable.BASE else slot
			var offset := surface_offset(String(entry.surface), map_seed)
			params[index] = Vector4(
				threshold(drawn[i]), 1.0 / maxf(float(entry.scale_m), 0.01), offset.x, offset.y
			)
	return {"accent_components": components, "accent_layer": layers, "accent_params": params}


## Binds a plan's accents (shader_uniforms) and the noise lattice on ground `material`.
static func bind(material: ShaderMaterial, plan: Dictionary, map_seed: int) -> void:
	var uniforms := shader_uniforms(plan.get("accents", []), map_seed)
	for uniform in uniforms:
		material.set_shader_parameter(uniform, uniforms[uniform])
	material.set_shader_parameter("accent_noise", noise_texture())


## Brings the ground skirt's material up to the ground's: the skirt continues the base
## surface, and with it the base's accent patches for a few metres, so they do not stop in a
## straight line at the map edge (the skirt shader shrinks them away as its fade begins; see
## SKIRT in authored_ground.gdshaderinc). It gets the slot textures (`layer_count` of them)
## and the accent uniforms, but only the base's accents, and never any weights (its painted
## and ground masks stay 0; the skirt shader reads no weight maps and runs no rules). Without
## base accents it samples no slot at all (layer_count 0).
static func sync_skirt(skirt: ShaderMaterial, ground: ShaderMaterial, layer_count: int) -> void:
	for uniform in ["layer_albedo", "layer_normal", "layer_orm", "layer_height", "layer_tile_m"]:
		skirt.set_shader_parameter(uniform, ground.get_shader_parameter(uniform))
	for uniform in ["accent_layer", "accent_params", "accent_noise"]:
		skirt.set_shader_parameter(uniform, ground.get_shader_parameter(uniform))
	var bound: Variant = ground.get_shader_parameter("accent_components")
	var base_bit := 1 << GroundLayerTable.MAX_LAYERS
	var base_accented := bound is int and (int(bound) & base_bit) != 0
	skirt.set_shader_parameter("accent_components", base_bit if base_accented else 0)
	skirt.set_shader_parameter("layer_count", layer_count if base_accented else 0)


## The ground accents of base surface `base` where no painted biome says otherwise: those of
## the palette's first biome on that ground (the biome GroundPalette.base_rule_surfaces
## reads), else none.
static func base_accents(base: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Array:
	for biome in PaletteLibrary.biomes(root):
		if biome.get("ground_surface", "") == base:
			return biome.get("ground_accents", [])
	return []


## The surface names of palette accents `accents` ({surface, ...}), in order.
static func surface_names(accents: Array) -> Array:
	return accents.map(func(accent: Dictionary) -> String: return String(accent.surface))


## The accents of `listed` whose surface `available` (Callable(surface) -> bool) accepts.
static func drawable(listed: Array, available: Callable) -> Array:
	return listed.filter(func(accent: Dictionary) -> bool: return available.call(accent.surface))


## The rotated, scaled and offset noise domain of an accent (the shader's, in accent_mask).
static func _domain(xz: Vector2, scale_m: float, offset: Vector2) -> Vector2:
	var rotated := Vector2(
		ROTATION.x * xz.x - ROTATION.y * xz.y, ROTATION.y * xz.x + ROTATION.x * xz.y
	)
	return rotated / maxf(scale_m, 0.01) + offset
