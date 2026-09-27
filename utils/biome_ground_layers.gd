class_name BiomeGroundLayers
extends RefCounted

## Pure rules for the biome ground of an authored map (AuthoredTerrain): which palette
## surfaces get one of the ground shader's MAX_LAYERS layer slots, which layer each painted
## biome feeds, and the RGBA8 weight map the shader blends them by. No nodes, no textures
## and no side effects, so every rule is unit-testable headless.
##
## Representation. The shader never sees biome slots. The CPU turns the document's biome
## slot and density masks into one RGBA8 texel per sample, one channel per ground layer:
## channel c of a sample holds the painted density (0..255) of that sample's biome when the
## biome's ground_surface is layer c's surface, else 0. The base surface is the remainder
## (1 - the channel sum). Why weights and not slots:
##   - a slot index cannot be filtered, so the shader would have to fetch four nearest
##     samples and blend by hand to avoid 0.25 m stair steps; per-surface weights are
##     bilinear-filtered by the texture unit in one fetch;
##   - several biomes that share a ground surface (three built-in biomes use "grass") share
##     a channel, so the shader samples each surface once however many biomes paint it;
##   - a biome on the base surface, or on a surface the palette lacks, writes nothing, so it
##     costs the shader nothing either.
## One slot per sample means at most one channel is non-zero in any texel and the channel
## sum never exceeds 1; filtering between neighbours keeps that true.
##
## Layer assignment. Distinct non-base surfaces take layers in order of painted coverage
## (the sum of density over their biomes' samples), ties by first appearance in
## biome_ids; AuthoredTerrain only computes coverage when there are more surfaces than
## layers, since otherwise the order changes nothing on screen and the full-mask scan is
## wasted. A surface that already holds a layer keeps it (plan(..., fixed)), so painting
## a new biome mid-session never moves an existing surface to another channel. Beyond
## MAX_LAYERS, the least-covered surfaces fall back to their nearest match by mean albedo
## among the layered surfaces and the base, and the caller warns once per surface. Nearest
## by colour, because what the player sees at the game camera is mostly colour: a savanna
## grass that cannot get its own layer reads better as the alpine grass than as lawn or
## sand. A surface whose colour is unknown falls back to the base.

const MAX_LAYERS := 4
const CHANNELS := 4
## Slot value of a sample with no biome.
const NO_SLOT := 0
## Layer index meaning "the base surface" (contributes nothing to the weight map).
const BASE := -1
## Samples per broad texel on each axis (broad_image()): 3.5 m at the default 0.25 m step.
## Chosen from game-camera renders; 8 (2 m) left the gradient too narrow to read.
const BROAD_FACTOR := 14


## The ground surface of each biome in `biome_ids`, in order: the biome's ground_surface
## when `available` says the surface can be drawn, else "" (drawn as the base).
## `ground_of` maps a biome id to its palette ground_surface ("" for an unknown biome), and
## `available` maps a surface name to whether its textures load; both are Callables so
## tests need no palette.
static func biome_surfaces(
	biome_ids: PackedStringArray, ground_of: Callable, available: Callable
) -> PackedStringArray:
	var surfaces := PackedStringArray()
	for biome_id in biome_ids:
		var surface: String = ground_of.call(biome_id)
		surfaces.append(surface if surface != "" and available.call(surface) else "")
	return surfaces


## Distinct surfaces of `surfaces` (biome_surfaces() output) that are neither "" nor
## `base`, in first-appearance order.
static func distinct_layers(surfaces: PackedStringArray, base: String) -> PackedStringArray:
	var distinct := PackedStringArray()
	for surface in surfaces:
		if surface != "" and surface != base and not distinct.has(surface):
			distinct.append(surface)
	return distinct


## Painted coverage per surface: surface -> sum of density over the samples whose biome
## has that surface. Only needed to rank surfaces when there are more than MAX_LAYERS.
static func coverage(
	slots: PackedByteArray, density: PackedByteArray, surfaces: PackedStringArray
) -> Dictionary:
	var per_slot := PackedInt64Array()
	per_slot.resize(surfaces.size() + 1)
	var count := mini(slots.size(), density.size())
	for i in count:
		var slot := slots[i]
		if slot != NO_SLOT and slot <= surfaces.size():
			per_slot[slot] += density[i]
	var totals := {}
	for index in surfaces.size():
		var surface := surfaces[index]
		if surface != "":
			totals[surface] = int(totals.get(surface, 0)) + per_slot[index + 1]
	return totals


## The layer plan for one document:
##   "layers": PackedStringArray, layer index -> surface (at most MAX_LAYERS);
##   "slot_layers": PackedInt32Array, biome slot (0 = none) -> layer index or BASE;
##   "fallbacks": Dictionary, overflowed surface -> the surface it is drawn as ("" = base).
## `surfaces` is biome_surfaces() output, `coverage_by_surface` ranks surfaces (missing =
## 0; pass {} to rank by first appearance), `color_of` maps a surface to its mean albedo
## Color or null (only called on overflow), and `fixed` is a previous plan's "layers",
## kept in place.
static func plan(
	surfaces: PackedStringArray,
	base: String,
	coverage_by_surface: Dictionary,
	color_of: Callable,
	fixed: PackedStringArray = PackedStringArray()
) -> Dictionary:
	var layers := fixed.duplicate()
	var candidates: Array[String] = []
	for surface in distinct_layers(surfaces, base):
		if not layers.has(surface):
			candidates.append(surface)
	# Stable by first appearance: sort_custom is not stable, so ties compare the index.
	var order := {}
	for index in candidates.size():
		order[candidates[index]] = index
	candidates.sort_custom(
		func(a: String, b: String) -> bool:
			var ca := int(coverage_by_surface.get(a, 0))
			var cb := int(coverage_by_surface.get(b, 0))
			return ca > cb if ca != cb else order[a] < order[b]
	)
	var overflow: Array[String] = []
	for surface in candidates:
		if layers.size() < MAX_LAYERS:
			layers.append(surface)
		else:
			overflow.append(surface)
	var fallbacks := {}
	for surface in overflow:
		fallbacks[surface] = nearest_surface(surface, layers, base, color_of)
	var slot_layers := PackedInt32Array([BASE])
	for surface in surfaces:
		var drawn: String = fallbacks.get(surface, surface)
		slot_layers.append(layers.find(drawn) if drawn != "" and drawn != base else BASE)
	return {"layers": layers, "slot_layers": slot_layers, "fallbacks": fallbacks}


## The surface among `layers` and `base` whose mean albedo is closest to `surface`'s, or ""
## (the base) when a colour is unknown. Ties go to the base, then to the lower layer.
static func nearest_surface(
	surface: String, layers: PackedStringArray, base: String, color_of: Callable
) -> String:
	var own: Variant = color_of.call(surface)
	if not own is Color:
		return ""
	var best := ""
	var best_distance := INF
	var base_color: Variant = color_of.call(base)
	if base_color is Color:
		best_distance = _color_distance(own, base_color)
	for layer in layers:
		var candidate: Variant = color_of.call(layer)
		if candidate is Color:
			var distance := _color_distance(own, candidate)
			if distance < best_distance:
				best_distance = distance
				best = layer
	return best


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## The broad scale of the ground shader's two-scale edge: the RGBA8 weight map (one texel
## per sample) box-filtered down by BROAD_FACTOR, so one texel spans 3.5 m at the
## default 0.25 m sample step. The shader reads it with a B-spline filter, which spreads a
## painted area's colour a few metres past its frayed edge in a soft gradient, the way a
## Blender map's hand-painted layers fade. Downsampled from the whole map in native code
## (Image.resize with trilinear filtering averages the mip chain), so a stroke can refresh
## it every frame. Never empty: at least 1 x 1.
static func broad_image(weights: Image) -> Image:
	var broad := weights.duplicate() as Image
	var size := broad_size(weights.get_size())
	broad.resize(size.x, size.y, Image.INTERPOLATE_TRILINEAR)
	return broad


## Size of broad_image() for a weight map of `samples` texels.
static func broad_size(samples: Vector2i) -> Vector2i:
	return Vector2i(
		maxi(1, ceili(float(samples.x) / BROAD_FACTOR)),
		maxi(1, ceili(float(samples.y) / BROAD_FACTOR))
	)


## RGBA8 weight bytes for the samples in `rect` (sample coordinates, clipped to the grid
## by the caller), row-major, 4 bytes per sample: the painted density of each sample's
## biome in the channel of its layer (see the class comment). Masks shorter than the grid
## (malformed, or not painted yet) read as unpainted.
static func weight_bytes(
	slots: PackedByteArray,
	density: PackedByteArray,
	samples_x: int,
	slot_layers: PackedInt32Array,
	rect: Rect2i
) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(rect.size.x * rect.size.y * CHANNELS)
	var count := mini(slots.size(), density.size())
	var out := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * samples_x
		for x in range(rect.position.x, rect.end.x):
			var i := row + x
			if i < count:
				var slot := slots[i]
				if slot != NO_SLOT and slot < slot_layers.size():
					var layer := slot_layers[slot]
					if layer != BASE:
						bytes[out + layer] = density[i]
			out += CHANNELS
	return bytes
