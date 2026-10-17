class_name GroundLayerBinding
extends RefCounted

## The index ground's binding (ground layers card G3, docs/systems/authored_terrain.md): what
## AuthoredTerrain's ground material reads, kept in step with its MapDocument. Split out of
## AuthoredTerrain so that class keeps its nodes; the rules are GroundLayers' (the layer list
## and the routing table), the textures GroundLayerArrays', the shader's LAYERS section says
## how they are read.
##
## Per map it binds:
##   - the layer arrays: every surface the map uses, the base at layer 0, in a stable order
##     for the session (a surface first used mid-session appends; painting never rebinds),
##     compacted at the next build(); build() also binds the `reserve` surfaces after the map's
##     own, ahead of their first use, as many as the arrays' capacity step already holds;
##   - the routing table by biome slot (biome_rules, biome_extra, accent_params): each biome's
##     ground, cliff, scree, water bed, shore and accent layers. Row 0 is the base, which takes
##     the rules and accents of the most covered painted biome on the base surface (else the
##     palette's first biome on it), and a biome on the base surface draws as the base: the
##     slot table's rules, kept so the look is unchanged;
##   - the four index maps, the document's own bytes (biome slots and density, R8; the paint
##     entries' index and weight planes, RGBA8), replaced whole on every update: a native copy
##     of each, no per-sample GDScript;
##   - per layer its tile size and flags, and the paint index -> layer table.
## No surface or accent is dropped for want of a layer below GroundLayers.MAX_LAYERS (64); past
## it a surface falls back to the nearest by mean albedo and an accent is dropped, each with
## one warning.
##
## The broad edge (the two-scale edge's wide tint, BROAD EDGE in the shader; card G4) is one
## tint map, GroundBroadTint's: per biome slot and per painted surface a tint (mean colour and
## weight; no slot limit), the premultiplied tint per sample in a CPU mirror (tint_mirror),
## box-filtered into broad_texture, and per layer its colour and painted tint weight
## (layer_tint) for the shader to take away the pixel's own components. An edit recomputes the
## mirror over its rectangle and refilters it whole (native); a table change that recolours a
## component already drawn (a layer list compacted, a biome's ground replaced) recomputes it
## whole.

## Rows of the shader's routing table and its accent entries.
const ROWS := GroundLayers.MAX_BIOMES
const ACCENT_ENTRIES := GroundLayers.MAX_BIOMES * GroundLayers.ACCENTS_PER_BIOME
## biome_rules' ground for a row that draws as the base (row 0, a biome on the base surface).
const AS_BASE := -1
const INDEX_MAPS: PackedStringArray = [
	"biome_slots_map", "biome_density_map", "paint_index_map", "paint_weight_map"
]

var document: MapDocument = null
var material: ShaderMaterial = null
var palette_root: String = PaletteLibrary.DEFAULT_ROOT
var arrays := GroundLayerArrays.new()
## Surfaces build() binds ahead of their first use (AuthoredTerrain.fire_surfaces: a fire's op
## brings them to a map at once, on every peer, and binding them there read their textures back
## in one frame). Only those the map's own capacity step holds are bound (with_reserve), so a
## reserve never grows the arrays; GroundLayers.extend keeps them for the session.
var reserve := PackedStringArray()
## GroundLayers.extend() of the current list, GroundLayers.routing() over it, and the inputs
## both were computed from (gather_inputs()).
var table: Dictionary = {}
var routing: Dictionary = {}
var inputs: Dictionary = {}
## The broad tint (see the header): per biome slot (0: none) and per document surface its
## GroundBroadTint.component(), the CPU mirror (RGBAF, one texel per sample) and the map.
var biome_tints := PackedColorArray()
var paint_tints := PackedColorArray()
var tint_mirror: Image = null
var broad_texture: ImageTexture = null
## Microseconds the last broad refresh took.
var last_broad_usec: int = 0

var _tint_stale: bool = true
var _index: Dictionary = {}
var _index_images: Dictionary = {}
var _planned_biomes := PackedStringArray()
var _planned_surfaces := PackedStringArray()
var _planned_water: bool = false
var _warned: Dictionary = {}


## Binds everything for `doc` on `ground` from palette `root` from scratch (a compacted list).
func build(doc: MapDocument, ground: ShaderMaterial, root: String, water: bool) -> void:
	document = doc
	material = ground
	palette_root = root
	table = {}
	arrays = GroundLayerArrays.new()
	biome_tints = PackedColorArray()
	paint_tints = PackedColorArray()
	_index.clear()
	_warned.clear()
	retable(water)
	upload_index()
	_build_broad()
	material.set_shader_parameter("layer_grid_origin", -doc.extent_m() * 0.5)
	material.set_shader_parameter("layer_grid_step", doc.sample_step())


## True when the document's biomes, painted surfaces or water changed since the last table.
func needs_retable(water: bool) -> bool:
	return (
		document.biome_ids != _planned_biomes
		or document.surface_ids != _planned_surfaces
		or water != _planned_water
	)


## Brings the bindings up to the document after an edit of the samples in `rect` (clipped to
## the grid): the tables first when needs_retable(), then the index maps (whole) and the
## broad tint of `rect` (whole when the tables recoloured a component already drawn).
func update_region(rect: Rect2i, water: bool) -> void:
	if needs_retable(water):
		retable(water)
	upload_index()
	var size := Vector2i(document.samples_x(), document.samples_z())
	if _tint_stale or tint_mirror == null or tint_mirror.get_size() != size:
		_build_broad()
	elif rect.has_area():
		_update_broad(rect)


## Recomputes the layer list (appending to the bound one), the routing table and the broad
## tints, and binds them. Returns true when the arrays were created anew.
func retable(water: bool) -> bool:
	inputs = gather_inputs(document, palette_root, water)
	var surfaces := PaletteLibrary.surfaces(palette_root)
	var root := palette_root
	var role_of := func(surface: String) -> String:
		return String(surfaces.get(surface, {}).get("role", "ground"))
	var color_of := func(surface: String) -> Variant:
		return GroundPalette.surface_mean_albedo(surface, root)
	var previous: PackedStringArray = table.get("layers", PackedStringArray())
	table = GroundLayers.extend(previous, GroundLayers.wanted(inputs), role_of, color_of)
	if previous.is_empty():
		table = with_reserve(table, reserve)
	_warn_overflow()
	routing = GroundLayers.routing(inputs, table)
	var layers: PackedStringArray = table.layers
	var recreated := arrays.sync(layers, palette_root)
	if recreated:
		arrays.bind(material)
	var flags := GroundLayers.layer_flags(layers, role_of)
	flags.resize(GroundLayers.MAX_LAYERS)
	material.set_shader_parameter("layer_flags", flags)
	var tile_of := func(surface: String) -> Variant: return surfaces.get(surface, {}).get("tile_m")
	material.set_shader_parameter("layer_tile_m", padded_tiles(layers, tile_of))
	material.set_shader_parameter(
		"paint_layer",
		GroundLayers.painted_layers(table, inputs.get("painted", PackedStringArray()))
	)
	var tables := shader_tables(
		routing, inputs.get("as_base", PackedByteArray()), document.map_seed
	)
	for uniform in tables:
		material.set_shader_parameter(uniform, tables[uniform])
	material.set_shader_parameter("accent_noise", GroundAccents.noise_texture())
	GroundAccents.bind_edge(material, document.extent_m() * 0.5)
	_plan_tints(role_of)
	_planned_biomes = document.biome_ids.duplicate()
	_planned_surfaces = document.surface_ids.duplicate()
	_planned_water = water
	return recreated


## The palette surface of each layer, in layer order (the base first).
func layers() -> PackedStringArray:
	return table.get("layers", PackedStringArray())


## `table` (GroundLayers.extend) with the surfaces of `reserved` it lacks appended, as many as
## its capacity step (GroundLayers.capacity) still holds, so the arrays keep their size. Pure.
static func with_reserve(table: Dictionary, reserved: PackedStringArray) -> Dictionary:
	var layers: PackedStringArray = table.get("layers", PackedStringArray()).duplicate()
	var fallbacks: Dictionary = table.get("fallbacks", {})
	var room := GroundLayers.capacity(maxi(layers.size(), 1)) - layers.size()
	for surface in reserved:
		if room <= 0:
			break
		if surface == "" or surface in layers or fallbacks.has(surface):
			continue
		layers.append(surface)
		room -= 1
	var out := table.duplicate()
	out["layers"] = layers
	return out


## The layer drawing `surface` (its fallback's past MAX_LAYERS), or -1.
func layer_of(surface: String) -> int:
	return GroundLayers.layer_of(table, surface)


## The layer document surface index `index` draws as, or -1.
func painted_layer(index: int) -> int:
	var painted: PackedStringArray = inputs.get("painted", PackedStringArray())
	return layer_of(painted[index]) if index >= 0 and index < painted.size() else -1


## True when a surface fell back or an accent was dropped (past MAX_LAYERS).
func overflowed() -> bool:
	return (
		not (table.get("fallbacks", {}) as Dictionary).is_empty()
		or not ((table.get("dropped", PackedStringArray()) as PackedStringArray).is_empty())
	)


## Replaces the four index maps with the document's current bytes (see the header).
func upload_index() -> void:
	var size := Vector2i(document.samples_x(), document.samples_z())
	var count := size.x * size.y
	var slots := document.biome_slots
	var density := document.biome_density
	var biomes := slots.size() == count and density.size() == count
	if not biomes:
		slots = _zeros(count)
		density = slots
	_set_map("biome_slots_map", size, Image.FORMAT_R8, slots)
	_set_map("biome_density_map", size, Image.FORMAT_R8, density)
	var painted := document.has_surface_entries()
	var index_plane := document.surface_plane(MapDocument.SURFACE_INDEX_PLANE)
	var weight_plane := document.surface_plane(MapDocument.SURFACE_WEIGHT_PLANE)
	if not painted:
		index_plane = _zeros(count * MapDocument.SURFACE_CHANNELS)
		weight_plane = index_plane
	_set_map("paint_index_map", size, Image.FORMAT_RGBA8, index_plane)
	_set_map("paint_weight_map", size, Image.FORMAT_RGBA8, weight_plane)
	var any_biome := biomes and not document.biome_ids.is_empty() and slots.count(0) != count
	material.set_shader_parameter("biome_present", 1 if any_biome else 0)
	material.set_shader_parameter("paint_present", 1 if painted else 0)


## The index map behind `uniform` (one of INDEX_MAPS), or null. Do not modify.
func index_texture(uniform: String) -> ImageTexture:
	return _index.get(uniform)


## The image last uploaded to index map `uniform` (headless runs cannot read a texture's
## updates back), or null. Do not modify.
func index_image(uniform: String) -> Image:
	return _index_images.get(uniform)


## The routing table as the shader's uniforms: "biome_rules" and "biome_extra" (ROWS ivec4s
## each, flattened: (ground, cliff, scree, bed) and (shore, accent layers 0-2), -1 for none,
## AS_BASE as the ground of row 0 and of a biome flagged in `as_base`), "accent_params"
## (ACCENT_ENTRIES Vector4s, GroundAccents.row_params per row) and "accent_present". Pure.
static func shader_tables(
	the_routing: Dictionary, as_base: PackedByteArray, map_seed: int
) -> Dictionary:
	var rules := PackedInt32Array()
	rules.resize(ROWS * 4)
	rules.fill(-1)
	var extra := rules.duplicate()
	var params := PackedVector4Array()
	params.resize(ACCENT_ENTRIES)
	var present := 0
	var ground: PackedInt32Array = the_routing.get("ground", PackedInt32Array())
	var entries: Array = the_routing.get("accent_entries", [])
	for row in mini(ground.size(), ROWS):
		var drawn_as_base := row == 0 or (row - 1 < as_base.size() and as_base[row - 1] != 0)
		rules[row * 4] = AS_BASE if drawn_as_base else ground[row]
		rules[row * 4 + 1] = (the_routing.cliff as PackedInt32Array)[row]
		rules[row * 4 + 2] = (the_routing.scree as PackedInt32Array)[row]
		rules[row * 4 + 3] = (the_routing.bed as PackedInt32Array)[row]
		extra[row * 4] = (the_routing.shore as PackedInt32Array)[row]
		var row_entries: Array = entries[row] if row < entries.size() else []
		var row_params := GroundAccents.row_params(row_entries, map_seed)
		for i in row_params.size():
			extra[row * 4 + 1 + i] = int(row_entries[i].layer)
			params[row * GroundLayers.ACCENTS_PER_BIOME + i] = row_params[i]
			present = 1
	return {
		"biome_rules": rules,
		"biome_extra": extra,
		"accent_params": params,
		"accent_present": present,
	}


## Per-layer tile sizes for `layers` padded to MAX_LAYERS (GroundLayers.layer_tiles).
static func padded_tiles(layers: PackedStringArray, tile_of: Callable) -> PackedFloat32Array:
	var tiles := GroundLayers.layer_tiles(layers, tile_of)
	var size := tiles.size()
	tiles.resize(GroundLayers.MAX_LAYERS)
	for j in range(size, tiles.size()):
		tiles[j] = GroundLayers.DEFAULT_TILE_M
	return tiles


## The broad tints for `grounds` (per document biome its ground, "" for none or one drawn as
## the base) and `painted` (per document surface, "" for one not drawable): {"biome" (by biome
## slot, slot 0 untinted), "paint" (by document surface; only role built tints, at
## GroundBroadTint.TRAMPLE_WEIGHT)} as GroundBroadTint.component() Colors, and "layer"
## (MAX_LAYERS Vector4s: per layer drawing a tinted surface its colour, and as w its painted
## tint weight). `layer_of` maps a surface to its layer, `color_of` to its mean colour. Pure.
static func tint_tables(
	grounds: PackedStringArray,
	painted: PackedStringArray,
	role_of: Callable,
	layer_of_surface: Callable,
	color_of: Callable
) -> Dictionary:
	var biomes := PackedColorArray([Color(0, 0, 0, 0)])
	var paints := PackedColorArray()
	var per_layer := PackedVector4Array()
	per_layer.resize(GroundLayers.MAX_LAYERS)
	for surface in grounds:
		var tint := GroundBroadTint.component(surface, 1.0, color_of)
		biomes.append(tint)
		var layer: int = layer_of_surface.call(surface) if surface != "" else -1
		if layer >= 0 and layer < per_layer.size():
			per_layer[layer] = Vector4(tint.r, tint.g, tint.b, per_layer[layer].w)
	for surface in painted:
		var built := surface != "" and String(role_of.call(surface)) == "built"
		var weight := GroundBroadTint.TRAMPLE_WEIGHT if built else 0.0
		var tint := GroundBroadTint.component(surface, weight, color_of)
		paints.append(tint)
		var layer: int = layer_of_surface.call(surface) if built else -1
		if layer >= 0 and layer < per_layer.size():
			per_layer[layer] = Vector4(tint.r, tint.g, tint.b, weight)
	return {"biome": biomes, "paint": paints, "layer": per_layer}


## The GroundLayers inputs for `doc` (see GroundLayers.wanted), surfaces the palette at `root`
## cannot draw left out, plus "as_base": per document biome 1 when it draws as the base (its
## ground is the base surface or missing; its own rules and accents are then blanked, the base
## row carries them as the slot table did).
static func gather_inputs(doc: MapDocument, root: String, water: bool) -> Dictionary:
	var available := func(surface: String) -> bool:
		return surface != "" and GroundPalette.surface_available(surface, root)
	var pick := func(biome: Dictionary, key: String) -> String:
		var surface: String = biome.get(key, "")
		return surface if available.call(surface) else ""
	var grounds := PackedStringArray()
	var cliffs := PackedStringArray()
	var screes := PackedStringArray()
	var beds := PackedStringArray()
	var shores := PackedStringArray()
	var accents: Array = []
	for biome_id in doc.biome_ids.slice(0, GroundLayers.MAX_BIOMES - 1):
		var biome := PaletteLibrary.biome(biome_id, root)
		grounds.append(pick.call(biome, "ground_surface"))
		cliffs.append(pick.call(biome, "cliff_surface"))
		screes.append(pick.call(biome, "scree_surface"))
		beds.append(pick.call(biome, "water_bed_surface"))
		shores.append(pick.call(biome, "shore_surface"))
		accents.append(GroundAccents.drawable(biome.get("ground_accents", []), available))
	var base := doc.base_surface
	var coverage := GroundLayerTable.biome_coverage(
		doc.biome_slots, doc.biome_density, grounds.size()
	)
	var base_biome := -1
	for b in grounds.size():
		if grounds[b] == base and (base_biome < 0 or coverage[b] > coverage[base_biome]):
			base_biome = b
	var base_rules := PackedStringArray()
	var base_accents: Array = []
	if base_biome >= 0:
		var b := base_biome
		base_rules = PackedStringArray([cliffs[b], screes[b], beds[b], shores[b]])
		base_accents = accents[b]
	else:
		base_rules = GroundPalette.base_rule_surfaces(base, root)
		base_rules.append_array(GroundPalette.base_water_surfaces(base, root))
		for i in base_rules.size():
			if not available.call(base_rules[i]):
				base_rules[i] = ""
		base_accents = GroundAccents.drawable(GroundAccents.base_accents(base, root), available)
	var as_base := PackedByteArray()
	for b in grounds.size():
		var on_base := grounds[b] == "" or grounds[b] == base
		as_base.append(1 if on_base else 0)
		if on_base:
			grounds[b] = ""
			cliffs[b] = ""
			screes[b] = ""
			beds[b] = ""
			shores[b] = ""
			accents[b] = []
	var painted := PackedStringArray()
	for surface in doc.surface_ids:
		painted.append(surface if available.call(surface) else "")
	return {
		"base": base,
		"painted": painted,
		"biome_ground": grounds,
		"biome_cliff": cliffs,
		"biome_scree": screes,
		"biome_bed": beds,
		"biome_shore": shores,
		"water": water,
		"base_rules": base_rules,
		"biome_accents": accents,
		"base_accents": base_accents,
		"as_base": as_base,
	}


func _warn_overflow() -> void:
	var fallbacks: Dictionary = table.get("fallbacks", {})
	for surface in fallbacks:
		if not _warned.has(surface):
			_warned[surface] = true
			push_warning(
				(
					"AuthoredTerrain: more than %d ground layer surfaces; '%s' is drawn as '%s'"
					% [GroundLayers.MAX_LAYERS, surface, fallbacks[surface]]
				)
			)
	for surface in table.get("dropped", PackedStringArray()):
		if not _warned.has("accent:" + surface):
			_warned["accent:" + surface] = true
			push_warning("AuthoredTerrain: ground accent '%s' did not fit the layers" % surface)


func _set_map(uniform: String, size: Vector2i, format: Image.Format, data: PackedByteArray) -> void:
	var image := Image.create_from_data(size.x, size.y, false, format, data)
	_index_images[uniform] = image
	var texture: ImageTexture = _index.get(uniform)
	if texture != null and Vector2i(texture.get_size()) == size and texture.get_format() == format:
		texture.update(image)
		return
	texture = ImageTexture.create_from_image(image)
	_index[uniform] = texture
	material.set_shader_parameter(uniform, texture)


static func _zeros(count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count)
	return out


## Recomputes the broad tints and binds them; marks the mirror stale when a component already
## drawn changed colour or weight (see the header).
func _plan_tints(role_of: Callable) -> void:
	var drawn := layers()
	var root := palette_root
	var layer_of_surface := func(surface: String) -> int: return layer_of(surface)
	var color_of := func(surface: String) -> Color:
		var layer := layer_of(surface)
		return GroundBroadTint.mean_color(drawn[layer] if layer >= 0 else surface, root)
	var tables := tint_tables(
		inputs.get("biome_ground", PackedStringArray()),
		inputs.get("painted", PackedStringArray()),
		role_of,
		layer_of_surface,
		color_of
	)
	var biomes: PackedColorArray = tables.biome
	var paints: PackedColorArray = tables.paint
	if (
		biomes.slice(0, biome_tints.size()) != biome_tints
		or paints.slice(0, paint_tints.size()) != paint_tints
	):
		_tint_stale = true
	biome_tints = biomes
	paint_tints = paints
	var present := 0
	for tint in biomes + paints:
		if tint.a > 0.0:
			present = 1
	material.set_shader_parameter("layer_tint", tables.layer)
	material.set_shader_parameter("broad_present", present)


func _build_broad() -> void:
	var start := Time.get_ticks_usec()
	var size := Vector2i(document.samples_x(), document.samples_z())
	var plane := GroundBroadTint.tint_plane(
		document, biome_tints, paint_tints, Rect2i(Vector2i.ZERO, size)
	)
	tint_mirror = GroundBroadTint.plane_image(size, plane)
	broad_texture = ImageTexture.create_from_image(GroundBroadTint.broad_image(tint_mirror))
	material.set_shader_parameter("broad_tint_map", broad_texture)
	_tint_stale = false
	last_broad_usec = Time.get_ticks_usec() - start


func _update_broad(rect: Rect2i) -> void:
	var start := Time.get_ticks_usec()
	var plane := GroundBroadTint.tint_plane(document, biome_tints, paint_tints, rect)
	var region := GroundBroadTint.plane_image(rect.size, plane)
	tint_mirror.blit_rect(region, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	broad_texture.update(GroundBroadTint.broad_image(tint_mirror))
	last_broad_usec = Time.get_ticks_usec() - start
