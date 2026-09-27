class_name GroundLayerTable
extends RefCounted

## Pure rules for the layer table of an authored map's ground shader (phase 3, P3-4): which
## palette surfaces get one of the shader's MAX_LAYERS layer slots, what each slot's weight
## channel holds, which slot draws each biome's cliff and scree, and the two RGBA8 weight
## maps. No nodes, no textures, no side effects, so every rule is unit-testable headless.
## AuthoredTerrain binds the result; TerrainRules and the shader compute the automatic
## rules the table routes.
##
## Three kinds of surface share the eight slots, one row per slot:
##   - PAINTED: a surface painted by hand (MapDocument.surface_ids). Its channel holds the
##     painted weight. Painted weight always wins: the shader draws it first and hands the
##     automatic dressing only what is left, 1 - the painted total, in proportion.
##   - GROUND: a painted biome's palette ground_surface. Its channel holds the painted
##     density of the biomes on that surface (one channel for all of them, so a surface is
##     sampled once however many biomes use it); the base surface is the remainder of the
##     ground, as before.
##   - RULE: a biome's cliff_surface or scree_surface that is not already a slot or the
##     base. Its channel is empty: it only ever receives the rule weights the shader
##     computes from slope and curvature (TerrainRules).
## Painted and ground weights sit in separate slots even for the same surface, because
## the shader must tell "painted, overrides the rules" from "biome ground, dressed by the
## rules" per channel. A rule surface reuses any slot already drawing it (or the base).
##
## Which cliff and scree, per sample. Every ground component, each GROUND slot and the
## base, carries a rule pair (cliff_of, scree_of: a slot, BASE or NONE): the cliff and
## scree surfaces of the biome that dominates it, the painted biome with most coverage
## among those whose ground is that surface (the base: among biomes on the base surface,
## else the caller's default, the palette's first biome on the base surface). The shader
## splits the cliff weight at a pixel over the ground components in proportion to their
## weights there, so a sample's rock is its biome's rock, a border between two biomes
## blends their rocks by the same weights (height-blended), and no extra texture is needed:
## the biome weights already say which biome is where. Limitation: two biomes sharing a
## ground surface share one rule pair (the dominant one's); in the built-in palette every
## ground surface implies one cliff surface, so it never shows.
##
## Allocation. Slots already assigned keep their index (`fixed`), so painting never moves
## a surface to another channel; new surfaces take free slots in priority order: painted
## surfaces (slot order), the base's rule surfaces, biome ground surfaces by painted
## coverage (ties by first appearance), the other rule surfaces by the coverage of the
## ground they dress. Beyond MAX_LAYERS a surface falls back, deterministically, to the
## slot (or the base) nearest by mean albedo among those of the same role: a ground surface
## among GROUND slots and the base (its channel must stay a ground channel), a cliff among
## slots whose surface has role cliff (any slot if there is none), a scree among ground-role
## slots and the base. The caller warns once per surface. A painted surface never falls
## back: when one finds no free slot, the table is replanned from scratch with painted
## surfaces first (at most MAX_LAYERS are painted, MapDocument.MAX_SURFACES).

enum Source { PAINTED, GROUND, RULE }

const MAX_LAYERS := 8
const CHANNELS := 4
## Weight images: slots 0-3 in the first, 4-7 in the second.
const PLANES := 2
## Slot value of a sample with no biome.
const NO_SLOT := 0
## A rule or biome routed to the base surface.
const BASE := -1
## No surface: rule weight stays with the ground it would have replaced.
const NONE := -2
## Samples per broad texel on each axis (broad_image()): 3.5 m at the default 0.25 m step.
## Chosen from game-camera renders; 8 (2 m) left the gradient too narrow to read.
const BROAD_FACTOR := 14


## The layer plan. `inputs`:
##   base: String, the base surface;
##   biome_ground / biome_cliff / biome_scree: PackedStringArray, per document biome (in
##     biome_ids order) its surfaces, "" when missing or not drawable;
##   biome_coverage: PackedInt64Array, per document biome its painted coverage (sum of
##     density; biome_coverage());
##   painted: PackedStringArray, the document's surface_ids ("" for one not drawable);
##   base_rules: PackedStringArray [cliff, scree], the base's rule pair when no painted
##     biome is on the base surface;
##   role_of: Callable(surface) -> String ("ground" / "cliff" / "built");
##   color_of: Callable(surface) -> Color or null (mean albedo; only called on overflow).
## `fixed` is a previous plan's "layers" (kept in place). Returns:
##   "layers": Array of {"surface", "source" (Source), "role"}, at most MAX_LAYERS;
##   "biome_layers": PackedInt32Array, biome slot (0 = none) -> GROUND slot or BASE;
##   "painted_layers": PackedInt32Array, painted slot -> PAINTED slot or NONE;
##   "cliff_of", "scree_of": PackedInt32Array of MAX_LAYERS + 1, per ground component (the
##     slots, then the base at index MAX_LAYERS) -> slot, BASE or NONE; NONE for a slot
##     that is not GROUND;
##   "fallbacks": Dictionary, overflowed surface -> the surface it is drawn as ("" = base);
##   "replanned": bool, true when `fixed` had to be dropped for a painted surface.
static func plan(inputs: Dictionary, fixed: Array = []) -> Dictionary:
	var result := _plan(inputs, fixed)
	if result.get("painted_overflow", false) and not fixed.is_empty():
		result = _plan(inputs, [])
		result["replanned"] = true
	result.erase("painted_overflow")
	return result


static func _plan(inputs: Dictionary, fixed: Array) -> Dictionary:
	var base: String = inputs.get("base", "")
	var grounds: PackedStringArray = inputs.get("biome_ground", PackedStringArray())
	var cliffs: PackedStringArray = inputs.get("biome_cliff", PackedStringArray())
	var screes: PackedStringArray = inputs.get("biome_scree", PackedStringArray())
	var coverage: PackedInt64Array = inputs.get("biome_coverage", PackedInt64Array())
	var painted: PackedStringArray = inputs.get("painted", PackedStringArray())
	var base_rules: PackedStringArray = inputs.get("base_rules", PackedStringArray(["", ""]))
	var role_of: Callable = inputs.get("role_of", func(_s: String) -> String: return "ground")
	var color_of: Callable = inputs.get("color_of", func(_s: String) -> Variant: return null)
	var layers: Array = []
	for layer in fixed:
		layers.append((layer as Dictionary).duplicate())
	var fallbacks := {}
	var painted_overflow := false
	# 1. Painted surfaces.
	for surface in painted:
		if surface != "" and _find(layers, surface, Source.PAINTED) < 0:
			if not _claim(layers, surface, Source.PAINTED, role_of):
				painted_overflow = true
	# Ground surfaces ranked by coverage, ties by first appearance.
	var ground_coverage := {}
	var order: Array[String] = []
	for b in grounds.size():
		var surface := grounds[b]
		if surface == "" or surface == base:
			continue
		if not ground_coverage.has(surface):
			ground_coverage[surface] = 0
			order.append(surface)
		ground_coverage[surface] += coverage[b] if b < coverage.size() else 0
	var ranked := order.duplicate()
	ranked.sort_custom(
		func(a: String, b: String) -> bool:
			var ca: int = ground_coverage[a]
			var cb: int = ground_coverage[b]
			return ca > cb if ca != cb else order.find(a) < order.find(b)
	)
	# The rule biome of each ground surface and of the base: the most covered biome on it.
	var rule_biome := {}
	for b in grounds.size():
		var surface := grounds[b]
		var key := base if surface == "" or surface == base else surface
		if surface == "":
			continue
		var cov: int = coverage[b] if b < coverage.size() else 0
		if not rule_biome.has(key) or cov > int(rule_biome[key].y):
			rule_biome[key] = Vector2i(b, cov)
	var base_pair := base_rules
	if rule_biome.has(base):
		var bb: int = rule_biome[base].x
		base_pair = PackedStringArray([cliffs[bb], screes[bb]])
	# 2. The base's rule surfaces.
	for surface in base_pair:
		_want_rule(layers, surface, base, role_of, color_of, fallbacks)
	# 3. Ground surfaces.
	for surface in ranked:
		if _find(layers, surface, Source.GROUND) >= 0:
			continue
		if not _claim(layers, surface, Source.GROUND, role_of):
			var candidates: Array = []
			for layer in layers:
				if layer.source == Source.GROUND:
					candidates.append(layer.surface)
			fallbacks[surface] = _nearest(surface, candidates, base, true, color_of)
	# 4. The other rule surfaces, in the order of the ground they dress.
	for surface in ranked:
		var b: int = rule_biome[surface].x
		_want_rule(layers, cliffs[b], base, role_of, color_of, fallbacks)
		_want_rule(layers, screes[b], base, role_of, color_of, fallbacks)
	# Routing.
	var biome_layers := PackedInt32Array([BASE])
	for b in grounds.size():
		var surface := grounds[b]
		var drawn: String = fallbacks.get(surface, surface)
		var index := _find(layers, drawn, Source.GROUND) if drawn != "" and drawn != base else -1
		biome_layers.append(index if index >= 0 else BASE)
	var painted_layers := PackedInt32Array()
	for surface in painted:
		var index := _find(layers, surface, Source.PAINTED) if surface != "" else -1
		painted_layers.append(index if index >= 0 else NONE)
	# A ground slot is dressed like the most covered biome it draws, fallbacks included.
	var slot_biome := {}
	for b in grounds.size():
		var drawn: String = fallbacks.get(grounds[b], grounds[b])
		if drawn == "" or drawn == base:
			continue
		var cov: int = coverage[b] if b < coverage.size() else 0
		if not slot_biome.has(drawn) or cov > int(slot_biome[drawn].y):
			slot_biome[drawn] = Vector2i(b, cov)
	var cliff_of := PackedInt32Array()
	var scree_of := PackedInt32Array()
	cliff_of.resize(MAX_LAYERS + 1)
	scree_of.resize(MAX_LAYERS + 1)
	cliff_of.fill(NONE)
	scree_of.fill(NONE)
	for j in layers.size():
		var layer: Dictionary = layers[j]
		if layer.source != Source.GROUND or not slot_biome.has(layer.surface):
			continue
		var b: int = slot_biome[layer.surface].x
		cliff_of[j] = _route(layers, cliffs[b], base, fallbacks)
		scree_of[j] = _route(layers, screes[b], base, fallbacks)
	cliff_of[MAX_LAYERS] = _route(layers, base_pair[0], base, fallbacks)
	scree_of[MAX_LAYERS] = _route(layers, base_pair[1], base, fallbacks)
	return {
		"layers": layers,
		"biome_layers": biome_layers,
		"painted_layers": painted_layers,
		"cliff_of": cliff_of,
		"scree_of": scree_of,
		"fallbacks": fallbacks,
		"replanned": false,
		"painted_overflow": painted_overflow,
	}


## Index of the slot drawing `surface` for `source` (a RULE want accepts any slot), or -1.
static func _find(layers: Array, surface: String, source: int) -> int:
	for j in layers.size():
		var layer: Dictionary = layers[j]
		if layer.surface == surface and (source == Source.RULE or layer.source == source):
			return j
	# A RULE slot of the same surface can become the painted or ground slot: its channel
	# is empty, and rules reuse any slot.
	if source != Source.RULE:
		for j in layers.size():
			var layer: Dictionary = layers[j]
			if layer.surface == surface and layer.source == Source.RULE:
				layer.source = source
				return j
	return -1


## Appends a slot for `surface`; false when the table is full.
static func _claim(layers: Array, surface: String, source: int, role_of: Callable) -> bool:
	if layers.size() >= MAX_LAYERS:
		return false
	layers.append({"surface": surface, "source": source, "role": String(role_of.call(surface))})
	return true


static func _want_rule(
	layers: Array,
	surface: String,
	base: String,
	role_of: Callable,
	color_of: Callable,
	fallbacks: Dictionary
) -> void:
	if surface == "" or surface == base or fallbacks.has(surface):
		return
	if _find(layers, surface, Source.RULE) >= 0:
		return
	if _claim(layers, surface, Source.RULE, role_of):
		return
	var role := String(role_of.call(surface))
	var candidates: Array = []
	for layer in layers:
		if layer.role == role:
			candidates.append(layer.surface)
	var with_base := role == "ground"
	if candidates.is_empty() and role != "ground":
		for layer in layers:
			candidates.append(layer.surface)
		with_base = true
	fallbacks[surface] = _nearest(surface, candidates, base, with_base, color_of)


## Where a rule surface is drawn: a slot, BASE, or NONE for no surface.
static func _route(layers: Array, surface: String, base: String, fallbacks: Dictionary) -> int:
	if surface == "":
		return NONE
	var drawn: String = fallbacks.get(surface, surface)
	if drawn == "" or drawn == base:
		return BASE
	var index := _find(layers, drawn, Source.RULE)
	return index if index >= 0 else NONE


## The surface among `candidates` (and the base when `with_base`) whose mean albedo is
## closest to `surface`'s; "" (the base) when a colour is unknown or the base wins. Ties go
## to the base, then to the earlier candidate.
static func _nearest(
	surface: String, candidates: Array, base: String, with_base: bool, color_of: Callable
) -> String:
	var own: Variant = color_of.call(surface)
	if not own is Color:
		return "" if with_base or candidates.is_empty() else String(candidates[0])
	var best := ""
	var best_distance := INF
	if with_base:
		var base_color: Variant = color_of.call(base)
		if base_color is Color:
			best_distance = _color_distance(own, base_color)
	for candidate in candidates:
		var color: Variant = color_of.call(candidate)
		if color is Color:
			var distance := _color_distance(own, color)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	if best == "" and not with_base and not candidates.is_empty():
		best = candidates[0]
	return best


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Painted coverage per document biome (index = slot - 1): the sum of density over its
## samples. Ranks ground surfaces and picks each surface's rule biome.
static func biome_coverage(
	slots: PackedByteArray, density: PackedByteArray, biome_count: int
) -> PackedInt64Array:
	var per_slot := PackedInt64Array()
	per_slot.resize(biome_count + 1)
	var count := mini(slots.size(), density.size())
	for i in count:
		var slot := slots[i]
		if slot != NO_SLOT and slot <= biome_count:
			per_slot[slot] += density[i]
	return per_slot.slice(1)


## Bitmask of the slots of `plan` with source `source` (bit j = slot j), for the shader.
static func source_mask(the_plan: Dictionary, source: int) -> int:
	var mask := 0
	var layers: Array = the_plan.layers
	for j in layers.size():
		if (layers[j] as Dictionary).source == source:
			mask |= 1 << j
	return mask


## The ground shader's slot mask uniforms for `plan`: which slots are painted, biome ground,
## painted rock (layer_cliff_paint_mask: never yields to the automatic rules) and painted
## built surfaces (layer_trample_mask: a faint trampled fringe around them, P3-6).
static func shader_masks(the_plan: Dictionary) -> Dictionary:
	return {
		"layer_painted_mask": source_mask(the_plan, Source.PAINTED),
		"layer_ground_mask": source_mask(the_plan, Source.GROUND),
		"layer_cliff_paint_mask": painted_role_mask(the_plan, "cliff"),
		"layer_trample_mask": painted_role_mask(the_plan, "built"),
	}


## Bitmask of the PAINTED slots of `plan` whose surface has role `role` (bit j = slot j).
static func painted_role_mask(the_plan: Dictionary, role: String) -> int:
	var mask := 0
	var layers: Array = the_plan.get("layers", [])
	for j in layers.size():
		var layer: Dictionary = layers[j]
		if layer.source == Source.PAINTED and String(layer.get("role", "")) == role:
			mask |= 1 << j
	return mask


## The two RGBA8 weight images' bytes for the samples of `rect` (sample coordinates,
## clipped to the grid by the caller): [plane A (slots 0-3), plane B (slots 4-7)], each
## row-major, 4 bytes per sample. A GROUND slot's channel holds the density of the sample's
## biome when that biome is routed to it; a PAINTED slot's channel the painted weight of
## the document slots routed to it (MapDocument.surface_weights layout); a RULE slot's
## channel is 0. Masks shorter than the grid read as unpainted.
static func weight_planes(
	doc: MapDocument, biome_layers: PackedInt32Array, painted_layers: PackedInt32Array, rect: Rect2i
) -> Array[PackedByteArray]:
	var samples_x := doc.samples_x()
	var count := doc.sample_count()
	var area := rect.size.x * rect.size.y * CHANNELS
	var a := PackedByteArray()
	var b := PackedByteArray()
	a.resize(area)
	b.resize(area)
	var slots := doc.biome_slots
	var density := doc.biome_density
	var biome_count := mini(slots.size(), density.size())
	var weights := doc.surface_weights
	var painted := PackedInt32Array()
	for s in mini(painted_layers.size(), doc.surface_ids.size()):
		painted.append(painted_layers[s])
	var paints := not weights.is_empty() and weights.size() == count * CHANNELS * PLANES
	var plane := count * CHANNELS
	var out := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * samples_x
		for x in range(rect.position.x, rect.end.x):
			var i := row + x
			if i < biome_count:
				var slot := slots[i]
				if slot != NO_SLOT and slot < biome_layers.size():
					var layer := biome_layers[slot]
					if layer >= 0:
						if layer < CHANNELS:
							a[out + layer] = density[i]
						else:
							b[out + layer - CHANNELS] = density[i]
			if paints:
				for s in painted.size():
					var layer := painted[s]
					if layer < 0:
						continue
					var value := weights[(s >> 2) * plane + i * CHANNELS + (s & 3)]
					if value == 0:
						continue
					if layer < CHANNELS:
						a[out + layer] = mini(a[out + layer] + value, 255)
					else:
						b[out + layer - CHANNELS] = mini(b[out + layer - CHANNELS] + value, 255)
			out += CHANNELS
	return [a, b]


## The broad scale of the ground shader's two-scale edge: one RGBA8 weight image (one
## texel per sample) box-filtered down by BROAD_FACTOR, so one texel spans 3.5 m at the
## default 0.25 m sample step. The shader reads it with a B-spline filter for its GROUND
## slots, which spreads a painted biome's colour a few metres past its frayed edge in a
## soft gradient, the way a Blender map's hand-painted layers fade. Downsampled from the
## whole map in native code (Image.resize with trilinear filtering averages the mip chain),
## so a stroke can refresh it every frame. Never empty: at least 1 x 1.
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
