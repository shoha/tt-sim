class_name AuthoredTerrain
extends Node3D

## The ground of a map authored in tt-sim, built from a MapDocument: one MeshInstance3D per
## 10 m chunk (ScatterChunker cells, so sculpting and scatter regeneration share keys), one
## StaticBody3D with a HeightMapShape3D for every terrain raycast, and one ground
## ShaderMaterial that tiles the document's base_surface from the palette.
##
## The geometry rules (which samples a chunk owns, shared border vertices, normals across
## chunk borders, the collision transform) are pure functions in TerrainMeshBuilder; this
## node only owns the nodes and the material.
##
## Collision sits on default layer 1 / mask 1 with input_ray_pickable off, exactly like the
## StaticBody3Ds GlbUtils makes for a Blender-made map, so token drag, the drop indicator,
## DragPlaceController and MeasureTool all hit it unchanged. The shape is scaled on the
## body by the document's real sample step (see TerrainMeshBuilder.collision_transform), so
## every sample lands on its document world position.
##
## Sculpting (phase 3) edits doc.heights in place and hands the changed sample rectangle to
## queue_heights(). process_heights() then brings the chunks up to date within a
## per-frame budget: live, it rewrites only the edited vertex rows of each chunk in place
## (ArrayMesh.surface_update_vertex_region over a CPU copy of the chunk's vertex stream,
## TerrainMeshBuilder.chunk_vertex_mirror), which is several times cheaper than rebuilding
## whole chunks (docs/PERFORMANCE.md "Sculpting"); after settle_heights() (stroke end, undo)
## it rebuilds each edited chunk once more so the mesh's own AABB, which the bounds walks
## read and an in-place update cannot change, is exact again. update_collision() pushes the
## heights into the collision shape (about 0.4 ms for a 200 ft map); refresh_skirt()
## follows an edit on the map edge.
##
## Ground layers (phase 3, P3-4). One table of up to eight shader layers blends over the
## base: painted surfaces, painted biomes' ground, the automatic cliff and scree, and ground
## accents (GroundAccents) (the table, its allocation and overflow rule are
## GroundLayerTable's; the rules are TerrainRules' and the shader's). Two RGBA8 weight maps
## on the sample grid (slots 0-3 and 4-7) are DrawableTexture2Ds so a brush stroke uploads
## only the samples it changed: a brush edits the document's masks in place, then calls
## update_ground_region() with the changed sample rectangle, which recomputes those texels
## and blits them in (a texel-exact copy, shaders/texel_copy_blit.gdshader). A biome or
## surface first painted mid-session takes a free slot by setting uniforms; the material is
## never rebuilt. CPU mirrors of the textures (get_ground_weights()) are kept for tests.
##
## Wet dressing (P4-3). On a map with water the ground also draws each biome's water bed
## and wet shore where MapDocument.water_dressing says (WaterDressing: bed, shore, wet line
## per sample; build() computes it, the editor recomputes it after a water or height edit and
## calls refresh_water_dressing()), as rule surfaces like cliff and scree, and paths yield to
## the bed. The field is one RGBA8 ImageTexture (water_weights), replaced whole.
##
## Rule fields. The automatic dressing reads two per-vertex fields (curvature and
## steepness nearby, TerrainRules.sample_fields) carried in the chunks' UV2. They are kept
## for the whole grid (get_rule_fields()); settle_heights() recomputes them
## CURVATURE_RADIUS_M around everything edited since the last settle, and the settling
## rebuild carries them into the chunks (mid-stroke only the vertices move).
## River exits (P6-1): rivers leaving the map run on into the skirt (RiverExitMesh, SkirtExits;
## apply_river_exits()). The opaque skirt's fade follows the environment (SkirtBackdrop).

const CHUNK_NAME_PREFIX := "TerrainChunk"
const COLLISION_NAME := "TerrainCollision"
const SKIRT_NAME := "TerrainSkirt"
const GROUND_SHADER := preload("res://shaders/authored_ground.gdshader")
const SKIRT_SHADER := preload("res://shaders/authored_ground_skirt.gdshader")
## The skirt fades out this far past the map edge (skirt_fade_m), the distance stretched
## by up to +-SKIRT_WOBBLE with noise; the ring is wide enough for the longest stretch.
const SKIRT_FADE_M := 24.0
const SKIRT_WOBBLE := 0.45
## Half height of the skirt's culling box (in-place edge edits move it without rebuilding).
const SKIRT_AABB_HALF_HEIGHT_M := 200.0
## A chunk whose heights span no more than this is flat and casts no shadow
## (chunk_shadow_casting).
const FLAT_CHUNK_M := 0.02
const TEXEL_COPY_SHADER := preload("res://shaders/texel_copy_blit.gdshader")
## Ground shader uniforms of the layer slots; each map is a sampler array of
## GroundLayerTable.MAX_LAYERS.
const LAYER_MAPS := {
	"albedo": "layer_albedo", "normal": "layer_normal", "orm": "layer_orm", "height": "layer_height"
}
## Albedo and ORM for a map whose surface is missing from the palette: a neutral earth so
## the map still reads as ground, fully rough, never metallic.
const FALLBACK_ALBEDO := Color(0.36, 0.33, 0.26)
const FALLBACK_ORM := Color(1.0, 0.9, 0.0)
## Set on a ground material built without palette textures.
const FALLBACK_META := &"authored_ground_fallback"
## Solid stand-ins for a layer map that is missing: fallback earth, flat normal, rough,
## mid height.
const LAYER_DEFAULTS := {
	"albedo": FALLBACK_ALBEDO,
	"normal": Color(0.5, 0.5, 1.0),
	"orm": FALLBACK_ORM,
	"height": Color(0.5, 0.5, 0.5),
}
const DEFAULT_LAYER_TILE_M := 2.0

static var _texel_copy: ShaderMaterial = null

var document: MapDocument = null
var palette_root: String = PaletteLibrary.DEFAULT_ROOT
## Microseconds, for measurement, of the last update_ground_region() call, its broad refresh,
## the last process_heights() call (and chunks it updated), the last refresh_skirt(), and the
## rule fields the last settle_heights() recomputed.
var last_biome_update_usec: int = 0
var last_broad_update_usec: int = 0
var last_heights_usec: int = 0
var last_heights_chunks: int = 0
var last_skirt_usec: int = 0
var last_fields_usec: int = 0
var height_version: int = 0  ## Bumped per height texture refresh (GroundHeightField follows).

var _material: ShaderMaterial = null
var _chunks: Dictionary[Vector2i, MeshInstance3D] = {}
var _body: StaticBody3D = null
var _shape: HeightMapShape3D = null
## The current GroundLayerTable.plan().
var _plan: Dictionary = {}
## Biome ids and painted surface ids the current plan covers; a change means a re-plan.
var _planned_biomes: int = -1
var _planned_surfaces: PackedStringArray = PackedStringArray()
## Whether the current plan gave the water bed and shore surfaces slots.
var _planned_water: bool = false
## The wet dressing texture (MapDocument.water_dressing; WaterDressing), null without water.
var _water_texture: ImageTexture = null
## Overflowed surfaces already warned about (surface -> true).
var _warned_fallbacks: Dictionary = {}
## The weight maps' CPU mirrors (slots 0-3, 4-7), their textures and their broad scales.
var _weights: Array[Image] = []
var _weight_textures: Array[DrawableTexture2D] = []
var _broad_textures: Array[ImageTexture] = []
## Whole-grid rule fields: {"curvature", "steep"} (TerrainMeshBuilder.grid_fields).
var _fields: Dictionary = {}
## cell -> chunk mesh arrays a loader's worker built (AuthoredLoadPrep), used once each.
var _prepared_chunks: Dictionary = {}
## Samples whose rule fields height edits have made stale, recomputed by settle_heights().
var _fields_dirty: Rect2i = Rect2i()
## Ground texture paths loading on background threads (warm_biome_surface), and the loaded
## textures held so the cache keeps them.
var _warming: Dictionary = {}
var _warm_held: Array[Resource] = []
## cell -> TerrainMeshBuilder.chunk_vertex_mirror() of chunks edited in place.
var _mirrors: Dictionary = {}
## cell -> Rect2i of samples waiting for an in-place update, in queue order.
var _dirty_heights: Dictionary = {}
## Cells edited in place since the last settle_heights().
var _edited: Dictionary = {}
## Cells waiting for their settling rebuild.
var _settling: Dictionary = {}
var _skirt_dirty: bool = false
## The skirt's material, made once per build() so a sculpt refresh reuses it.
var _skirt_material: ShaderMaterial = null
## TerrainMeshBuilder.skirt_vertex_mirror() once the edge is first edited, and the samples
## waiting for refresh_skirt().
var _skirt_mirror: Dictionary = {}
var _skirt_rect: Rect2i = Rect2i()
## RiverExitMesh.build() of the skirt now ({} when no river leaves the map).
var _exits: Dictionary = {}
## cell -> Vector2(lowest, highest) height of the chunk (grown only by in-place updates,
## exact after a rebuild).
var _chunk_heights: Dictionary = {}
## get_height_texture(), and whether height edits made it stale since settle_heights().
var _height_texture: ImageTexture = null
var _height_texture_stale: bool = false


func _ready() -> void:
	set_process(false)


## A terrain for `doc`, fully built: every chunk, the collision body and the material.
## With `with_chunks` false the chunk meshes are left for the caller to build with
## rebuild_chunks() (the play-time load spreads them over frames: about 0.8 ms each, 49 on
## a 200 ft map). `prepared` is AuthoredLoadPrep's worker output (the wet dressing, rule
## fields, skirt and chunk arrays); whatever it lacks is computed here.
static func create(
	doc: MapDocument,
	root: String = PaletteLibrary.DEFAULT_ROOT,
	with_chunks: bool = true,
	prepared: Dictionary = {}
) -> AuthoredTerrain:
	var terrain := AuthoredTerrain.new()
	terrain.name = "AuthoredTerrain"
	terrain.build(doc, root, with_chunks, prepared)
	return terrain


## Resource paths of every palette texture build() binds for `doc` (GroundPalette, where
## the palette helpers live).
static func texture_paths(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	return GroundPalette.texture_paths(doc, root)


## Builds (or rebuilds from scratch) everything for `doc`; the chunk meshes only with
## `with_chunks` (see create(), and `prepared` there).
func build(
	doc: MapDocument,
	root: String = PaletteLibrary.DEFAULT_ROOT,
	with_chunks: bool = true,
	prepared: Dictionary = {}
) -> void:
	document = doc
	palette_root = root
	for chunk in _chunks.values():
		chunk.free()
	_chunks.clear()
	_mirrors.clear()
	_dirty_heights.clear()
	_edited.clear()
	_settling.clear()
	_chunk_heights.clear()
	_skirt_dirty = false
	_fields_dirty = Rect2i()
	_skirt_material = null
	_material = GroundPalette.build_ground_material(doc.base_surface, doc.map_seed, root)
	# The wet dressing first: whether the map has water decides the layer plan.
	if prepared.has(AuthoredLoadPrep.DRESSING):
		doc.water_dressing = prepared[AuthoredLoadPrep.DRESSING]
	else:
		WaterDressing.refresh(doc)
	_build_ground_layers()
	_bind_water_dressing()
	_fields = prepared.get(AuthoredLoadPrep.FIELDS, {})
	if _fields.is_empty():
		_fields = TerrainMeshBuilder.grid_fields(doc)
	_prepared_chunks = prepared.get(AuthoredLoadPrep.CHUNKS, {}).duplicate()
	if with_chunks:
		rebuild_chunks(TerrainMeshBuilder.chunk_cells(doc))
	_build_collision()
	_build_skirt(prepared.get(AuthoredLoadPrep.SKIRT, {}))
	_refresh_height_texture()


## The shared ground material.
func get_material() -> ShaderMaterial:
	return _material


## The ground skirt: the base surface continued past the map edge, fading into the backdrop
## (see SKIRT in shaders/authored_ground.gdshaderinc), so a zoomed-out view shows the map
## dissolving into the background instead of a cut rectangle; the rivers that leave the map
## run on in it (SkirtExits children; see the header). Decoration only: no
## collision, no shadow casting, and Constants.BOUNDS_EXEMPT_META keeps it out of the pan
## bounds and the reflection probe. Rebuilt by build(); a height edit on the map edge
## refreshes its geometry (refresh_skirt(); its inner edge copies the boundary heights).
func get_skirt() -> MeshInstance3D:
	return get_node_or_null(SKIRT_NAME) as MeshInstance3D


## Ring width for the skirt: the longest noise-stretched fade plus a margin.
static func skirt_width_m() -> float:
	return SKIRT_FADE_M / (1.0 - SKIRT_WOBBLE) + 2.0


## Builds the skirt node from `parts` (RiverExitMesh.skirt_parts(): the skirt's arrays and
## the river exits; computed here when empty), its material made once per build().
func _build_skirt(parts: Dictionary = {}) -> void:
	var old := get_skirt()
	if old != null:
		old.free()
	if _skirt_material == null:
		var layers: int = _plan.get("layers", []).size()
		_skirt_material = TerrainSkirt.material(
			_material, layers, document, SKIRT_FADE_M, SKIRT_WOBBLE
		)
	if parts.is_empty():
		parts = RiverExitMesh.skirt_parts(document, skirt_width_m(), SKIRT_FADE_M, SKIRT_WOBBLE)
	_exits = parts.get("exits", {})
	var mesh := TerrainSkirt.mesh(parts.skirt, _skirt_material)
	_skirt_mirror = parts.get("mirror", {})  # Built with the parts; refresh_skirt() needs it.
	_skirt_rect = Rect2i()
	var skirt := SkirtExits.decoration(SKIRT_NAME, mesh)
	SkirtExits.decorate(skirt, _exits, _skirt_material, document, SKIRT_FADE_M, SKIRT_WOBBLE)
	_sync_skirt_water()
	add_child(skirt)


## Rebuilds the skirt, keeping its material, with `parts` (RiverExitMesh.skirt_parts() from
## AuthoredWater's refresh worker; {} when no river leaves the map) when either has an exit.
func apply_river_exits(parts: Dictionary) -> void:
	if _exits.is_empty() and (parts.get("exits", {}) as Dictionary).is_empty():
		return
	_build_skirt(parts)


## The current river exits' geometry (RiverExitMesh.build(); {} when none). Do not modify.
func river_exits() -> Dictionary:
	return _exits


func _sync_skirt_water() -> void:
	if _skirt_material != null:
		var channel := not _exits.is_empty() and _has_water()
		var layers: int = _plan.get("layers", []).size()
		SkirtExits.sync_water(_skirt_material, _material, layers, channel)


## Brings the skirt's geometry up to the current boundary heights (a sculpt edit on the map
## edge), keeping its node and its material: no material is duplicated, so the ground's
## uniforms and the shader's compiled pipelines stay as they are. Only the boundary samples
## queue_heights() marked are rewritten, in place (surface_update_vertex_region over a
## CPU copy of the vertex stream, TerrainMeshBuilder.skirt_vertex_mirror): with its rings
## the whole skirt took about 11 ms to rebuild, every frame of a stroke on the edge. The
## triangles and UVs never change (they depend on XZ only).
func refresh_skirt() -> void:
	var started := Time.get_ticks_usec()
	_skirt_dirty = false
	var skirt := get_skirt()
	if skirt == null or _skirt_material == null:
		_build_skirt()
		return
	var width := skirt_width_m()
	if _skirt_mirror.is_empty():
		_skirt_mirror = TerrainMeshBuilder.skirt_vertex_mirror(document, width, SKIRT_FADE_M)
	TerrainSkirt.update_in_place(
		skirt.mesh as ArrayMesh, _skirt_mirror, document, _skirt_rect, width, SKIRT_FADE_M
	)
	_skirt_rect = Rect2i()
	last_skirt_usec = Time.get_ticks_usec() - started


## The palette surface of each layer slot, in slot (weight channel) order.
func ground_layers() -> PackedStringArray:
	var surfaces := PackedStringArray()
	for layer in _plan.get("layers", []):
		surfaces.append(layer.surface)
	return surfaces


## The current layer plan (GroundLayerTable.plan()). Do not modify.
func layer_plan() -> Dictionary:
	return _plan


## The CPU mirror of weight image `plane` (0: slots 0-3, 1: slots 4-7; RGBA8, one texel per
## sample). Do not modify.
func get_ground_weights(plane: int = 0) -> Image:
	return _weights[plane]


## The whole-grid rule fields {"curvature", "steep"} the chunks carry in UV2
## (TerrainRules.sample_fields). Do not modify.
func get_rule_fields() -> Dictionary:
	return _fields


## Recomputes the layer weights of the samples in `sample_rect` (sample coordinates,
## position = first sample, size in samples; clipped to the grid) from the document's
## biome masks and painted surfaces and uploads just those texels. Call it after every
## mask or paint edit with a rectangle covering every sample changed since the last call.
## A biome or painted surface added to the document since the last call is given a slot
## first (a free one, one already drawing it, or its overflow fallback), which only sets
## uniforms; in the rare case a painted surface forces a re-plan (GroundLayerTable), every
## texel is rewritten.
func update_ground_region(sample_rect: Rect2i) -> void:
	var start := Time.get_ticks_usec()
	var grid := Rect2i(0, 0, document.samples_x(), document.samples_z())
	var rect := sample_rect.intersection(grid)
	if (
		document.biome_ids.size() != _planned_biomes
		or document.surface_ids != _planned_surfaces
		or _has_water() != _planned_water
	):
		if _plan_layers():
			rect = grid
	if rect.has_area():
		var planes := _weight_planes(rect)
		for plane in GroundLayerTable.PLANES:
			var region := Image.create_from_data(
				rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8, planes[plane]
			)
			_weights[plane].blit_rect(region, Rect2i(Vector2i.ZERO, rect.size), rect.position)
			_upload(plane, region, rect.position)
		_refresh_broad()
	last_biome_update_usec = Time.get_ticks_usec() - start


## Brings the ground's wet dressing up to the document's water_dressing (WaterDressing
## .refresh(), which the caller runs after a water or height edit): re-plans the layers when
## the map gains or loses water (the bed and shore surfaces take slots only with water) and
## uploads the field (the whole texture: about 0.25 MB on a 200 ft map).
func refresh_water_dressing() -> void:
	if _has_water() != _planned_water:
		if _plan_layers():
			update_ground_region(Rect2i(0, 0, document.samples_x(), document.samples_z()))
	_bind_water_dressing()
	_sync_skirt_water()


## The wet dressing texture (WaterDressing layout), or null with no water. Do not modify.
func get_water_texture() -> ImageTexture:
	return _water_texture


func _has_water() -> bool:
	return document != null and not document.water_dressing.is_empty()


func _bind_water_dressing() -> void:
	var field := document.water_dressing
	var size := Vector2i(document.samples_x(), document.samples_z())
	if field.size() != size.x * size.y * WaterDressing.CHANNELS:
		_water_texture = null
		_material.set_shader_parameter("water_present", 0)
		_material.set_shader_parameter("water_weights", null)
		return
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, field)
	if _water_texture != null and Vector2i(_water_texture.get_size()) == size:
		_water_texture.update(image)
	else:
		_water_texture = ImageTexture.create_from_image(image)
	_material.set_shader_parameter("water_weights", _water_texture)
	_material.set_shader_parameter("water_present", 1)


## Starts loading the surface textures of palette biome `biome_id` (ground, cliff, scree,
## accents) on background threads, so the first dab that gives one a slot binds cached
## textures instead of loading them on the main thread (21 to 25 ms for a new surface,
## measured in T3c). Harmless for surfaces already bound or the base.
func warm_biome_surface(biome_id: String) -> void:
	var biome := PaletteLibrary.biome(biome_id, palette_root)
	var bound := ground_layers()
	var names := GroundAccents.surface_names(biome.get("ground_accents", []))
	var keys := ["ground_surface", "cliff_surface", "scree_surface"]
	if _has_water():
		keys.append_array(["water_bed_surface", "shore_surface"])
	for key in keys:
		names.append(biome.get(key, ""))
	for surface_name: String in names:
		if surface_name == "" or surface_name == document.base_surface or bound.has(surface_name):
			continue
		warm_surface(surface_name)


## Starts loading the textures of palette surface `surface_name` on background threads
## (see warm_biome_surface; the Paint tool warms a surface when its tile is picked).
func warm_surface(surface_name: String) -> void:
	var surface: Dictionary = PaletteLibrary.surfaces(palette_root).get(surface_name, {})
	# None under the headless dummy renderer (GlbUtils.threaded_loads_safe): loaded when bound.
	for key in LAYER_MAPS if GlbUtils.threaded_loads_safe() else {}:
		var relative: Variant = surface.get(key, "")
		if not relative is String or relative == "":
			continue
		var path := palette_root.path_join(relative)
		if ResourceLoader.has_cached(path) or _warming.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_warming[path] = true
	if not _warming.is_empty():
		set_process(true)


## Collects finished warm-up loads, holding each texture until the node goes, so the
## resource cache keeps it for the layer bind.
func _process(_delta: float) -> void:
	for path in _warming.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_warming.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_warm_held.append(ResourceLoader.load_threaded_get(path))
	if _warming.is_empty():
		set_process(false)


func _exit_tree() -> void:
	for path in _warming.keys():
		ResourceLoader.load_threaded_get(path)
	_warming.clear()
	_warm_held.clear()


func _build_ground_layers() -> void:
	_plan = {}
	_planned_biomes = -1
	_planned_surfaces = PackedStringArray()
	_warned_fallbacks.clear()
	_plan_layers()
	var size := Vector2i(document.samples_x(), document.samples_z())
	var planes := _weight_planes(Rect2i(Vector2i.ZERO, size))
	_weights.clear()
	_weight_textures.clear()
	_broad_textures.clear()
	for plane in GroundLayerTable.PLANES:
		var image := Image.create_from_data(
			size.x, size.y, false, Image.FORMAT_RGBA8, planes[plane]
		)
		_weights.append(image)
		var texture := DrawableTexture2D.new()
		texture.setup(
			size.x, size.y, DrawableTexture2D.DRAWABLE_FORMAT_RGBA8, Color(0, 0, 0, 0), false
		)
		_weight_textures.append(texture)
		if planes[plane].count(0) != planes[plane].size():
			_upload(plane, image, Vector2i.ZERO)
		_broad_textures.append(ImageTexture.create_from_image(GroundLayerTable.broad_image(image)))
	_material.set_shader_parameter("layer_weights_a", _weight_textures[0])
	_material.set_shader_parameter("layer_weights_b", _weight_textures[1])
	_material.set_shader_parameter("layer_broad_a", _broad_textures[0])
	_material.set_shader_parameter("layer_broad_b", _broad_textures[1])
	_material.set_shader_parameter("layer_grid_origin", -document.extent_m() * 0.5)
	_material.set_shader_parameter("layer_grid_step", document.sample_step())


## (Re)plans the layer table for the document's current biomes and painted surfaces,
## keeping every slot already assigned (unless a painted surface forces a re-plan), and
## binds the textures of the slots. Returns true when slots moved, so every weight texel
## must be rewritten.
func _plan_layers() -> bool:
	var root := palette_root
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
	for biome_id in document.biome_ids:
		var biome := PaletteLibrary.biome(biome_id, root)
		grounds.append(pick.call(biome, "ground_surface"))
		cliffs.append(pick.call(biome, "cliff_surface"))
		screes.append(pick.call(biome, "scree_surface"))
		beds.append(pick.call(biome, "water_bed_surface"))
		shores.append(pick.call(biome, "shore_surface"))
		accents.append(GroundAccents.drawable(biome.get("ground_accents", []), available))
	var painted := PackedStringArray()
	for surface in document.surface_ids:
		painted.append(surface if available.call(surface) else "")
	var base_rules := GroundPalette.base_rule_surfaces(document.base_surface, root)
	base_rules.append_array(GroundPalette.base_water_surfaces(document.base_surface, root))
	for i in base_rules.size():
		if not available.call(base_rules[i]):
			base_rules[i] = ""
	var water := _has_water()
	var surfaces := PaletteLibrary.surfaces(root)
	var inputs := {
		"base": document.base_surface,
		"biome_ground": grounds,
		"biome_cliff": cliffs,
		"biome_scree": screes,
		"biome_bed": beds,
		"biome_shore": shores,
		"water": water,
		"biome_coverage":
		GroundLayerTable.biome_coverage(
			document.biome_slots, document.biome_density, document.biome_ids.size()
		),
		"painted": painted,
		"base_rules": base_rules,
		"role_of":
		func(surface: String) -> String: return surfaces.get(surface, {}).get("role", "ground"),
		"color_of":
		func(surface: String) -> Variant: return GroundPalette.surface_mean_albedo(surface, root),
		"biome_accents": accents,
		"base_accents":
		GroundAccents.drawable(GroundAccents.base_accents(document.base_surface, root), available),
	}
	var previous: Array = _plan.get("layers", [])
	var result := GroundLayerTable.plan(inputs, previous)
	for surface in result.dropped_accents:
		if not _warned_fallbacks.has("accent:" + surface):
			_warned_fallbacks["accent:" + surface] = true
			push_warning("AuthoredTerrain: ground accent '%s' did not fit the layers" % surface)
	var fallbacks: Dictionary = result.fallbacks
	for surface in fallbacks:
		if not _warned_fallbacks.has(surface):
			_warned_fallbacks[surface] = true
			var drawn: String = fallbacks[surface]
			push_warning(
				(
					"AuthoredTerrain: more than %d ground layer surfaces; '%s' is drawn as '%s'"
					% [
						GroundLayerTable.MAX_LAYERS,
						surface,
						drawn if drawn != "" else document.base_surface
					]
				)
			)
	var moved: bool = result.replanned
	_plan = result
	_planned_biomes = document.biome_ids.size()
	_planned_surfaces = document.surface_ids.duplicate()
	_planned_water = water
	_bind_layers(previous)
	return moved


## Binds every slot's textures and tile size, the slot masks and the rule routing. Only
## slots whose surface changed are reloaded. Unused array entries (and a slot surface
## missing a map) get small solid textures: they are never sampled (an unused slot's
## weight is 0), but every sampler stays valid.
func _bind_layers(previous: Array) -> void:
	var layers: Array = _plan.layers
	var same := previous.size() == layers.size()
	for j in mini(previous.size(), layers.size()):
		same = same and previous[j].surface == layers[j].surface
	if not same or _material.get_shader_parameter("layer_albedo") == null:
		var maps := {}
		for key in LAYER_MAPS:
			maps[key] = []
		var tiles := PackedFloat32Array()
		var surfaces := PaletteLibrary.surfaces(palette_root)
		for index in GroundLayerTable.MAX_LAYERS:
			var surface: Dictionary = (
				surfaces.get(layers[index].surface, {}) if index < layers.size() else {}
			)
			for key in LAYER_MAPS:
				var texture := GroundPalette.load_texture(palette_root, surface.get(key, ""))
				maps[key].append(
					texture if texture else GroundPalette.solid_texture(LAYER_DEFAULTS[key])
				)
			tiles.append(float(surface.get("tile_m", DEFAULT_LAYER_TILE_M)))
		for key in LAYER_MAPS:
			_material.set_shader_parameter(LAYER_MAPS[key], maps[key])
		_material.set_shader_parameter("layer_tile_m", tiles)
	_material.set_shader_parameter("layer_count", layers.size())
	var masks := GroundLayerTable.shader_masks(_plan)
	for uniform in masks:
		_material.set_shader_parameter(uniform, masks[uniform])
	var cliff_of := GroundLayerTable.shader_routing(_plan.cliff_of)
	_material.set_shader_parameter("rule_cliff_layer", cliff_of)
	_material.set_shader_parameter(
		"rule_scree_layer", GroundLayerTable.shader_routing(_plan.scree_of)
	)
	_material.set_shader_parameter("rule_bed_layer", GroundLayerTable.shader_routing(_plan.bed_of))
	_material.set_shader_parameter(
		"rule_shore_layer", GroundLayerTable.shader_routing(_plan.shore_of)
	)
	GroundAccents.bind(_material, _plan, document.map_seed)
	if _skirt_material != null:
		GroundAccents.sync_skirt(_skirt_material, _material, layers.size())
		_sync_skirt_water()


func _weight_planes(rect: Rect2i) -> Array[PackedByteArray]:
	return GroundLayerTable.weight_planes(document, _plan.biome_layers, _plan.painted_layers, rect)


## Rebuilds the broad weight textures from the CPU mirrors (whole map; native resize, a
## fraction of a millisecond each on a 200 ft map) and uploads them in place.
func _refresh_broad() -> void:
	var start := Time.get_ticks_usec()
	for plane in GroundLayerTable.PLANES:
		_broad_textures[plane].update(GroundLayerTable.broad_image(_weights[plane]))
	last_broad_update_usec = Time.get_ticks_usec() - start


## The broad weight texture of `plane` (see GroundLayerTable.broad_image). Do not modify.
func get_broad_texture(plane: int = 0) -> ImageTexture:
	return _broad_textures[plane]


## Copies `region` into weight texture `plane` at `at`, texel for texel.
func _upload(plane: int, region: Image, at: Vector2i) -> void:
	if _texel_copy == null:
		_texel_copy = ShaderMaterial.new()
		_texel_copy.shader = TEXEL_COPY_SHADER
	_weight_textures[plane].blit_rect(
		Rect2i(at, region.get_size()),
		ImageTexture.create_from_image(region),
		Color.WHITE,
		0,
		_texel_copy
	)


## Every chunk cell that currently has a mesh.
func chunk_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_chunks.keys())
	return cells


## The chunk node for `cell`, or null.
func get_chunk(cell: Vector2i) -> MeshInstance3D:
	return _chunks.get(cell, null)


func get_collision_body() -> StaticBody3D:
	return _body


## Rebuilds the meshes of the given chunk cells from the document's current heights,
## leaving every other chunk untouched. Cells outside the map are ignored. Normals read
## neighbouring samples across chunk borders, so after a height edit pass every cell whose
## samples are within one sample of the edit (a sculpt brush's dab rect grown by one step).
## The rule fields (UV2) are the ones kept since build() or the last queue_heights(): a
## height edit goes through queue_heights(), which refreshes them.
func rebuild_chunks(cells: Array[Vector2i]) -> void:
	for cell in cells:
		# The chunk now matches the document; a vertex copy kept for in-place edits may not.
		_mirrors.erase(cell)
		_dirty_heights.erase(cell)
		_settling.erase(cell)
		_rebuild_chunk(cell)


func _rebuild_chunk(cell: Vector2i) -> void:
	var mesh: ArrayMesh = null
	if _prepared_chunks.has(cell):
		mesh = TerrainMeshBuilder.mesh_of(_prepared_chunks[cell], _material)
		_prepared_chunks.erase(cell)
	else:
		mesh = TerrainMeshBuilder.build_chunk_mesh(document, cell, _material, _fields)
	if mesh == null:
		return
	var chunk: MeshInstance3D = _chunks.get(cell, null)
	if chunk == null:
		chunk = MeshInstance3D.new()
		chunk.name = CHUNK_NAME_PREFIX + ScatterChunker.cell_suffix(cell)
		add_child(chunk)
		_chunks[cell] = chunk
	chunk.mesh = mesh
	chunk.cast_shadow = chunk_shadow_casting(mesh)
	var aabb := mesh.get_aabb()
	_chunk_heights[cell] = Vector2(aabb.position.y, aabb.end.y)


## Queues the chunks whose vertices the height samples of `sample_rect` (grid coordinates)
## change: every sample in it, and the samples one step around it, whose normals read
## them. process_heights() does the work. The rule fields (curvature, steepness nearby)
## that read these samples, up to TerrainRules.CURVATURE_RADIUS_M plus a step out, are only
## marked: settle_heights() recomputes them once for the whole edit (per dab they cost 5 to
## 10 ms of a stroke frame). Mid-stroke the cliff follows the live normals; scree and lip
## catch up when the stroke settles, with the plants.
func queue_heights(sample_rect: Rect2i) -> void:
	var grid := Rect2i(0, 0, document.samples_x(), document.samples_z())
	_height_texture_stale = true
	_prepared_chunks.clear()  # Built from the heights before this edit.
	var step := document.sample_step()
	var reach := TerrainRules.radius_samples(minf(step.x, step.y)) + 1
	var fields_rect := sample_rect.grow(reach).intersection(grid)
	if fields_rect.has_area():
		_fields_dirty = MaskBrush.merge_rect(_fields_dirty, fields_rect)
	var grown := sample_rect.grow(1).intersection(grid)
	if not grown.has_area():
		return
	var world := MaskBrush.sample_rect_to_world(document, grown).grow(maxf(step.x, step.y))
	for cell in ScatterGenerator.cells_in_bounds(world):
		var rect := TerrainMeshBuilder.chunk_sample_rect(document, cell)
		if rect.size == Vector2i.ZERO:
			continue
		var part := grown.intersection(Rect2i(rect.position, rect.size + Vector2i.ONE))
		if not part.has_area():
			continue
		var queued: Rect2i = _dirty_heights.get(cell, Rect2i())
		_dirty_heights.erase(cell)
		_dirty_heights[cell] = MaskBrush.merge_rect(queued, part)
	if (
		grown.position.x == 0
		or grown.position.y == 0
		or grown.end.x == grid.end.x
		or grown.end.y == grid.end.y
	):
		_skirt_dirty = true
		_skirt_rect = MaskBrush.merge_rect(_skirt_rect, grown)


## Updates queued chunks until `budget_usec` of main-thread time is spent (at least one
## chunk per call, so progress is guaranteed; a negative budget does everything): first the
## in-place vertex updates, then the skirt, then settling rebuilds. Returns true when no
## height work is left.
func process_heights(budget_usec: int = -1) -> bool:
	var started := Time.get_ticks_usec()
	var chunks := 0
	for cell in _dirty_heights.keys():
		if chunks > 0 and budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
		var part: Rect2i = _dirty_heights[cell]
		_dirty_heights.erase(cell)
		_update_chunk_in_place(cell, part)
		chunks += 1
	var spent := func() -> bool:
		return budget_usec >= 0 and Time.get_ticks_usec() - started >= budget_usec
	if _dirty_heights.is_empty() and _skirt_dirty and not (chunks > 0 and spent.call()):
		refresh_skirt()
	if _dirty_heights.is_empty():
		for cell in _settling.keys():
			if spent.call() and chunks > 0:
				break
			_settling.erase(cell)
			_rebuild_chunk(cell)
			chunks += 1
	last_heights_usec = Time.get_ticks_usec() - started
	last_heights_chunks = chunks
	return not has_height_work()


## True while height updates, a skirt refresh or settling rebuilds are waiting.
func has_height_work() -> bool:
	return not _dirty_heights.is_empty() or _skirt_dirty or not _settling.is_empty()


## True while chunks edited in place still differ from a rebuild (their meshes report the
## AABB they had before the edit); settle_heights() queues their rebuild.
func has_unsettled_chunks() -> bool:
	return not _edited.is_empty() or not _settling.is_empty() or _fields_dirty.has_area()


## Queues a rebuild of every chunk edited in place since the last call (the end of a sculpt
## stroke, an undo), which process_heights() runs after the in-place work. The rebuilt
## chunk is the same geometry; what changes is the mesh's AABB, exact again for the bounds
## walks, and the chunk's shadow casting, which a flattened chunk turns off.
##
## It also brings the rule fields up to date for everything queued since the last call (one
## TerrainRules.sample_fields pass over the edit grown by CURVATURE_RADIUS_M) and queues the
## rebuild of every chunk they changed, which carries them in UV2; vertex copies kept for
## in-place edits get the new fields too, and the height texture (get_height_texture()).
func settle_heights() -> void:
	if _height_texture_stale:
		_refresh_height_texture()
	if _fields_dirty.has_area():
		var started := Time.get_ticks_usec()
		var columns := document.samples_x()
		TerrainRules.store_fields(
			TerrainRules.sample_fields(
				TerrainMeshBuilder.collision_heights(document),
				columns,
				document.samples_z(),
				document.sample_step(),
				_fields_dirty
			),
			columns,
			_fields.curvature,
			_fields.steep
		)
		for cell in _mirrors:
			TerrainMeshBuilder.write_attribute_region(
				_mirrors[cell], _fields_dirty, _fields, columns
			)
		var world := MaskBrush.sample_rect_to_world(document, _fields_dirty)
		for cell in ScatterGenerator.cells_in_bounds(
			world.grow(maxf(document.sample_step().x, 0.01))
		):
			if _chunks.has(cell):
				_settling[cell] = true
		_fields_dirty = Rect2i()
		last_fields_usec = Time.get_ticks_usec() - started
	for cell in _edited:
		_settling[cell] = true
	_edited.clear()


## The lowest and highest ground height (Vector2(min, max), map frame) over every chunk:
## exact after a rebuild, and never below the truth during a stroke (in-place edits only
## widen it). Vector2.ZERO for a terrain without chunks.
func height_range() -> Vector2:
	if _chunk_heights.is_empty():
		return Vector2.ZERO
	var span := Vector2(INF, -INF)
	for heights: Vector2 in _chunk_heights.values():
		span.x = minf(span.x, heights.x)
		span.y = maxf(span.y, heights.y)
	return span


## height_range() in world space (the terrain's global transform applied: the level's map
## scale and offset).
func world_height_range() -> Vector2:
	var span := height_range()
	if not is_inside_tree():
		return span
	var low := global_transform * Vector3(0.0, span.x, 0.0)
	var high := global_transform * Vector3(0.0, span.y, 0.0)
	return Vector2(minf(low.y, high.y), maxf(low.y, high.y))


## The heights for the grid overlay (TerrainMeshBuilder.height_image, GridOverlay.set_ground),
## updated in place by build() and settle_heights() (stroke end, cancel, undo, redo).
func get_height_texture() -> ImageTexture:
	if _height_texture == null:
		_refresh_height_texture()
	return _height_texture


func _refresh_height_texture() -> void:
	_height_texture_stale = false
	height_version += 1
	if document == null:
		return
	var image := TerrainMeshBuilder.height_image(document)
	if _height_texture == null or Vector2i(_height_texture.get_size()) != image.get_size():
		_height_texture = ImageTexture.create_from_image(image)
	else:
		_height_texture.update(image)


func _update_chunk_in_place(cell: Vector2i, part: Rect2i) -> void:
	var chunk: MeshInstance3D = _chunks.get(cell, null)
	if chunk == null or not chunk.mesh is ArrayMesh:
		return
	var mesh := chunk.mesh as ArrayMesh
	var mirror: Dictionary = _mirrors.get(cell, {})
	var rect: Rect2i
	var first_row := 0
	var last_row := 0
	var span := Vector2(INF, -INF)
	if mirror.is_empty():
		# First edit of this chunk: the whole stream from the current heights and fields.
		mirror = TerrainMeshBuilder.chunk_vertex_mirror(document, cell, _fields)
		if mirror.is_empty():
			return
		_mirrors[cell] = mirror
		rect = mirror.rect
		last_row = int(mirror.rows) - 1
		span = _mirror_span(mirror)
	else:
		rect = mirror.rect
		span = TerrainMeshBuilder.write_vertex_region(document, mirror, part)
		first_row = maxi(part.position.y - rect.position.y, 0)
		last_row = mini(part.end.y - 1 - rect.position.y, int(mirror.rows) - 1)
	var bytes := TerrainMeshBuilder.vertex_rows_bytes(mirror, first_row, last_row)
	mesh.surface_update_vertex_region(0, bytes.position_offset, bytes.positions)
	mesh.surface_update_vertex_region(0, bytes.normal_offset, bytes.normals)
	_edited[cell] = true
	# The mesh keeps its build-time AABB; culling reads the custom one, widened to the new
	# heights (exact again after the settling rebuild).
	var known: Vector2 = _chunk_heights.get(cell, span)
	var widened := Vector2(minf(known.x, span.x), maxf(known.y, span.y))
	_chunk_heights[cell] = widened
	var base := mesh.get_aabb()
	mesh.custom_aabb = AABB(
		Vector3(base.position.x, widened.x, base.position.z),
		Vector3(base.size.x, maxf(widened.y - widened.x, 0.0), base.size.z)
	)
	if widened.y - widened.x > FLAT_CHUNK_M:
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


static func _mirror_span(mirror: Dictionary) -> Vector2:
	var positions: PackedFloat32Array = mirror.positions
	var span := Vector2(INF, -INF)
	for i in range(1, positions.size(), 3):
		span.x = minf(span.x, positions[i])
		span.y = maxf(span.y, positions[i])
	return span


## Shadow casting for a chunk mesh: off when the chunk is flat. A flat chunk can only
## shadow itself, and the directional shadow's self-shadowing darkened flat ground about
## 10 % in steps that follow the cascade splits (a horizontal line across a zoomed-out map,
## and a seam against the ground skirt, which casts nothing; T7 renders). A sculpted chunk
## (phase 3) casts as before.
static func chunk_shadow_casting(mesh: Mesh) -> GeometryInstance3D.ShadowCastingSetting:
	if mesh.get_aabb().size.y <= FLAT_CHUNK_M:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Pushes the document's current heights into the collision shape.
func update_collision() -> void:
	if _shape == null:
		_build_collision()
		return
	_shape.map_width = document.samples_x()
	_shape.map_depth = document.samples_z()
	_shape.map_data = TerrainMeshBuilder.collision_heights(document)
	_body.transform = TerrainMeshBuilder.collision_transform(document)


func _build_collision() -> void:
	if _body == null:
		_body = StaticBody3D.new()
		_body.name = COLLISION_NAME
		_body.input_ray_pickable = false
		var collision := CollisionShape3D.new()
		_shape = HeightMapShape3D.new()
		collision.shape = _shape
		_body.add_child(collision)
		add_child(_body)
	update_collision()
