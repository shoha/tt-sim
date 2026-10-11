class_name GroundLayers
extends RefCounted

## Pure rules for the index-based ground (docs/plans/2026-10-11-ground-layers/design.md):
## which palette surfaces a map's layer arrays hold, at which index, and the per-biome
## routing table the shader reads by biome slot. No nodes, no textures, no side effects, so
## every rule is unit-testable headless. It replaces GroundLayerTable's eight shared slots;
## nothing shipped uses it yet (the ground's binding adopts it in card G3).
##
## The layer list. A map draws its surfaces from four Texture2DArrays (albedo, normal, ORM,
## height) whose layers are this list, in order: one entry per palette surface the map uses
## (the base, painted surfaces, every biome's ground, cliff, scree, bed and shore, and the
## accents), never one entry per role, so a surface painted and also a biome's ground is one
## layer. The list is stable for a session: a surface, once given a layer, keeps its index
## (painting never rebinds or rewrites a texel), new surfaces append, and a surface no
## longer used keeps its layer until the next load compacts the list (compact(): the
## surfaces in use, in priority order, the base at layer 0). The arrays grow in capacity
## steps (CAPACITY_STEPS, recreated on growth, a layer updated in place otherwise).
##
## Overflow. At most MAX_LAYERS per map (the palette has 26 surfaces). A surface that finds
## no layer falls back, deterministically, to the layer whose surface is nearest by mean
## albedo among those of the same role (any layer when none has it; the base when a colour
## is unknown); the caller warns once per surface. An accent never falls back (a patch of
## the wrong surface is not an accent): it is dropped. Priority, which decides who overflows
## first: the base, painted surfaces in document order, each biome's ground in document
## order, the base's rule surfaces, each biome's rule surfaces, then the accents.
##
## The routing table: one row per biome slot, row 0 the base (a sample with no biome, and
## what a biome's density leaves), row b the document biome b - 1, at most MAX_BIOMES. Each
## row names its ground layer, its cliff, scree, water bed and shore layers (NONE: the
## component keeps its weight, as a missing rule surface does today) and up to
## ACCENTS_PER_BIOME accents. Per biome, not per ground surface: two biomes on the same
## ground surface keep their own cliff and scree, which GroundLayerTable could not do.
##
## Per layer: flags (FLAG_CLIFF for a surface of role cliff, which a painted stroke holds
## against the automatic rules; FLAG_BUILT for role built, the trampled fringe) and the
## tile size in metres, as arrays of the capacity's length for the shader's uniforms.

## Layers per map: the shader's layer table and the arrays' largest capacity.
const MAX_LAYERS := 64
## Rows of the routing table: the base and 254 document biomes (biome slots are bytes).
const MAX_BIOMES := 255
## Accents per biome row (the shader's ACCENTS_PER_COMPONENT).
const ACCENTS_PER_BIOME := 3
## Painted surfaces a document can list (MapDocument.MAX_SURFACES from format 2).
const MAX_PAINTED := 64
## Array capacities, smallest first; the last is MAX_LAYERS.
const CAPACITY_STEPS: PackedInt32Array = [16, 32, 64]
## No layer: a rule that leaves the weight with its ground, an unused accent entry.
const NONE := -1
const FLAG_CLIFF := 1
const FLAG_BUILT := 2
## Tile size of an unused layer or a surface without one (AuthoredTerrain's default).
const DEFAULT_TILE_M := 2.0
const RULE_KEYS: PackedStringArray = ["cliff", "scree", "bed", "shore"]


## The surfaces a map uses, in priority order (see the header). `inputs`:
##   base: String, the base surface;
##   painted: PackedStringArray, the document's surface_ids ("" for one not drawable);
##   biome_ground / biome_cliff / biome_scree / biome_bed / biome_shore: PackedStringArray,
##     per document biome its surfaces, "" when missing or not drawable;
##   water: bool, the map has water: only then are bed and shore surfaces used;
##   base_rules: PackedStringArray [cliff, scree, bed, shore], the base row's rule surfaces;
##   biome_accents: Array, per document biome its ground accents ({surface, coverage,
##     scale_m}, priority order; PaletteLibrary.ground_accents);
##   base_accents: Array, the base row's accents.
## Returns {"surfaces": PackedStringArray, the surfaces that fall back on overflow;
## "accents": PackedStringArray, the accent-only surfaces, which are dropped instead}.
static func wanted(inputs: Dictionary) -> Dictionary:
	var ordered := PackedStringArray([String(inputs.get("base", ""))])
	ordered.append_array(inputs.get("painted", PackedStringArray()))
	var biomes := _biome_count(inputs)
	var grounds: PackedStringArray = inputs.get("biome_ground", PackedStringArray())
	ordered.append_array(grounds.slice(0, biomes))
	ordered.append_array(_base_rules(inputs))
	for b in biomes:
		ordered.append_array(_biome_rules(inputs, b))
	var surfaces := PackedStringArray()
	for surface in ordered:
		if surface != "" and not surface in surfaces:
			surfaces.append(surface)
	var accents := PackedStringArray()
	for row in biomes + 1:
		for entry in _row_accents(inputs, row):
			var surface: String = entry.surface
			if not surface in surfaces and not surface in accents:
				accents.append(surface)
	return {"surfaces": surfaces, "accents": accents}


## The layer list after an edit: every layer of `previous` stays at its index, the
## surfaces of `wanted` (wanted()) that have none are appended, overflow falls back or is
## dropped (header). `role_of`: Callable(surface) -> String; `color_of`: Callable(surface)
## -> Color or null (mean albedo, only called on overflow). Returns
## {"layers": PackedStringArray, "fallbacks": Dictionary surface -> the surface it is drawn
## as, "dropped": PackedStringArray, accents not drawn}.
static func extend(
	previous: PackedStringArray, wants: Dictionary, role_of: Callable, color_of: Callable
) -> Dictionary:
	var layers := previous.slice(0, MAX_LAYERS)
	var fallbacks := {}
	var dropped := PackedStringArray()
	for surface in wants.get("surfaces", PackedStringArray()):
		if surface in layers:
			continue
		if layers.size() < MAX_LAYERS:
			layers.append(surface)
		else:
			fallbacks[surface] = _nearest(surface, layers, role_of, color_of)
	for surface in wants.get("accents", PackedStringArray()):
		if surface in layers:
			continue
		if layers.size() < MAX_LAYERS:
			layers.append(surface)
		else:
			dropped.append(surface)
	return {"layers": layers, "fallbacks": fallbacks, "dropped": dropped}


## The compacted list a load starts from: only the surfaces in use, in priority order.
static func compact(wants: Dictionary, role_of: Callable, color_of: Callable) -> Dictionary:
	return extend(PackedStringArray(), wants, role_of, color_of)


## The layer drawing `surface` in `table` (extend()), its fallback's when it overflowed;
## NONE for "" or a surface the table does not hold.
static func layer_of(table: Dictionary, surface: String) -> int:
	if surface == "":
		return NONE
	var drawn: String = (table.get("fallbacks", {}) as Dictionary).get(surface, surface)
	return (table.get("layers", PackedStringArray()) as PackedStringArray).find(drawn)


## The routing table for `inputs` (wanted()) over `table` (extend()), rows by biome slot
## (header). Returns PackedInt32Arrays of rows entries, "ground", "cliff", "scree", "bed",
## "shore" (bed and shore NONE on a map without water), and "accents" of rows *
## ACCENTS_PER_BIOME (row r's entries at r * ACCENTS_PER_BIOME, NONE past its last);
## "accent_entries": Array per row of {layer, surface, coverage, scale_m}, the drawn accents
## in priority order; "base_layer": int.
static func routing(inputs: Dictionary, table: Dictionary) -> Dictionary:
	var rows := _biome_count(inputs) + 1
	var base_layer := maxi(layer_of(table, String(inputs.get("base", ""))), 0)
	var grounds: PackedStringArray = inputs.get("biome_ground", PackedStringArray())
	var ground_column := PackedInt32Array()
	var cliff := PackedInt32Array()
	var scree := PackedInt32Array()
	var bed := PackedInt32Array()
	var shore := PackedInt32Array()
	var accents := PackedInt32Array()
	accents.resize(rows * ACCENTS_PER_BIOME)
	accents.fill(NONE)
	var entries: Array = []
	for row in rows:
		var ground := NONE if row == 0 else layer_of(table, grounds[row - 1])
		ground_column.append(ground if ground != NONE else base_layer)
		var rules := _base_rules(inputs) if row == 0 else _biome_rules(inputs, row - 1, true)
		cliff.append(layer_of(table, rules[0]))
		scree.append(layer_of(table, rules[1]))
		bed.append(layer_of(table, rules[2]))
		shore.append(layer_of(table, rules[3]))
		var drawn: Array = []
		for entry in _row_accents(inputs, row):
			var layer := layer_of(table, String(entry.surface))
			if layer == NONE:
				continue
			accents[row * ACCENTS_PER_BIOME + drawn.size()] = layer
			(
				drawn
				. append(
					{
						"layer": layer,
						"surface": entry.surface,
						"coverage": entry.coverage,
						"scale_m": entry.scale_m,
					}
				)
			)
		entries.append(drawn)
	return {
		"base_layer": base_layer,
		"ground": ground_column,
		"cliff": cliff,
		"scree": scree,
		"bed": bed,
		"shore": shore,
		"accents": accents,
		"accent_entries": entries,
	}


## Document painted index -> layer, MAX_PAINTED entries (NONE for "", a surface the table
## does not hold, and past the document's list): the shader's painted-index table, so the
## document's index bytes upload verbatim.
static func painted_layers(table: Dictionary, painted: PackedStringArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(MAX_PAINTED)
	out.fill(NONE)
	for i in mini(painted.size(), MAX_PAINTED):
		out[i] = layer_of(table, painted[i])
	return out


## The smallest capacity step that holds `count` layers (MAX_LAYERS at most).
static func capacity(count: int) -> int:
	for step in CAPACITY_STEPS:
		if count <= step:
			return step
	return MAX_LAYERS


## Per-layer flags for `layers`, capacity(layers.size()) entries (0 past the last layer):
## FLAG_CLIFF for role cliff, FLAG_BUILT for role built. `role_of`: Callable(surface) ->
## String.
static func layer_flags(layers: PackedStringArray, role_of: Callable) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(capacity(layers.size()))
	for j in layers.size():
		match String(role_of.call(layers[j])):
			"cliff":
				out[j] = FLAG_CLIFF
			"built":
				out[j] = FLAG_BUILT
	return out


## Per-layer tile sizes in metres for `layers`, capacity(layers.size()) entries,
## DEFAULT_TILE_M for an unused layer or a size that is unknown or not positive.
## `tile_of`: Callable(surface) -> float or null (the palette's tile_m).
static func layer_tiles(layers: PackedStringArray, tile_of: Callable) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(capacity(layers.size()))
	out.fill(DEFAULT_TILE_M)
	for j in layers.size():
		var tile: Variant = tile_of.call(layers[j])
		if (tile is float or tile is int) and float(tile) > 0.0:
			out[j] = float(tile)
	return out


static func _biome_count(inputs: Dictionary) -> int:
	var grounds: PackedStringArray = inputs.get("biome_ground", PackedStringArray())
	return mini(grounds.size(), MAX_BIOMES - 1)


## The base row's [cliff, scree, bed, shore], bed and shore "" without water.
static func _base_rules(inputs: Dictionary) -> PackedStringArray:
	var given: PackedStringArray = inputs.get("base_rules", PackedStringArray())
	var out := PackedStringArray()
	for r in RULE_KEYS.size():
		var keep := r < 2 or bool(inputs.get("water", false))
		out.append(given[r] if keep and r < given.size() else "")
	return out


## Biome `b`'s [cliff, scree, bed, shore], bed and shore "" without water; with `padded`
## false, only the surfaces in use (for wanted()).
static func _biome_rules(inputs: Dictionary, b: int, padded: bool = false) -> PackedStringArray:
	var water := bool(inputs.get("water", false))
	var out := PackedStringArray()
	for r in RULE_KEYS.size():
		var column: PackedStringArray = inputs.get("biome_" + RULE_KEYS[r], PackedStringArray())
		var surface := column[b] if b < column.size() and (r < 2 or water) else ""
		if padded or surface != "":
			out.append(surface)
	return out


## Row `row`'s accents as drawn: the first ACCENTS_PER_BIOME usable entries (a surface,
## not the row's own ground, not repeated, coverage above 0), each {surface, coverage,
## scale_m}.
static func _row_accents(inputs: Dictionary, row: int) -> Array:
	var listed: Array
	var own: String
	if row == 0:
		listed = inputs.get("base_accents", [])
		own = String(inputs.get("base", ""))
	else:
		var per_biome: Array = inputs.get("biome_accents", [])
		listed = per_biome[row - 1] if row - 1 < per_biome.size() else []
		var grounds: PackedStringArray = inputs.get("biome_ground", PackedStringArray())
		own = grounds[row - 1]
		if own == "":
			own = String(inputs.get("base", ""))
	var out: Array = []
	var seen := {}
	for entry in listed:
		if not entry is Dictionary:
			continue
		var surface := String(entry.get("surface", ""))
		var coverage := float(entry.get("coverage", 0.0))
		if surface == "" or surface == own or seen.has(surface) or coverage <= 0.0:
			continue
		seen[surface] = true
		out.append(
			{"surface": surface, "coverage": coverage, "scale_m": float(entry.get("scale_m", 0.0))}
		)
		if out.size() == ACCENTS_PER_BIOME:
			break
	return out


## The surface among `layers` nearest to `surface` by mean albedo, among layers of the same
## role (all layers when none has it); layer 0 (the base) when `surface`'s colour is
## unknown, the first candidate when no candidate's is. Ties go to the earlier layer.
static func _nearest(
	surface: String, layers: PackedStringArray, role_of: Callable, color_of: Callable
) -> String:
	var role := String(role_of.call(surface))
	var candidates := PackedStringArray()
	for layer in layers:
		if String(role_of.call(layer)) == role:
			candidates.append(layer)
	if candidates.is_empty():
		candidates = layers
	var own: Variant = color_of.call(surface)
	if not own is Color:
		return layers[0]
	var best := candidates[0]
	var best_distance := INF
	for candidate in candidates:
		var color: Variant = color_of.call(candidate)
		if color is Color:
			var c: Color = color
			var o: Color = own
			var distance := Vector3(o.r - c.r, o.g - c.g, o.b - c.b).length()
			if distance < best_distance:
				best_distance = distance
				best = candidate
	return best
