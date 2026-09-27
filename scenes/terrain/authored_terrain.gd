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
## Rule fields. The automatic dressing reads two per-vertex fields (curvature and
## steepness nearby, TerrainRules.sample_fields) carried in the chunks' UV2. They are kept
## for the whole grid (get_rule_fields()); settle_heights() recomputes them
## CURVATURE_RADIUS_M around everything edited since the last settle, and the settling
## rebuild carries them into the chunks (mid-stroke only the vertices move).

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
## Microseconds of the last update_ground_region() call, for measurement.
var last_biome_update_usec: int = 0
## Microseconds of the last broad refresh (part of update_ground_region()), for measurement.
var last_broad_update_usec: int = 0
## Microseconds of the last process_heights() call and chunks it updated, for measurement.
var last_heights_usec: int = 0
var last_heights_chunks: int = 0
## Microseconds of the last refresh_skirt(), for measurement.
var last_skirt_usec: int = 0
## Microseconds the last settle_heights() spent recomputing rule fields, for measurement.
var last_fields_usec: int = 0

var _material: ShaderMaterial = null
var _chunks: Dictionary[Vector2i, MeshInstance3D] = {}
var _body: StaticBody3D = null
var _shape: HeightMapShape3D = null
## The current GroundLayerTable.plan().
var _plan: Dictionary = {}
## Biome ids and painted surface ids the current plan covers; a change means a re-plan.
var _planned_biomes: int = -1
var _planned_surfaces: PackedStringArray = PackedStringArray()
## Overflowed surfaces already warned about (surface -> true).
var _warned_fallbacks: Dictionary = {}
## The weight maps' CPU mirrors (slots 0-3, 4-7), their textures and their broad scales.
var _weights: Array[Image] = []
var _weight_textures: Array[DrawableTexture2D] = []
var _broad_textures: Array[ImageTexture] = []
## Whole-grid rule fields: {"curvature", "steep"} (TerrainMeshBuilder.grid_fields).
var _fields: Dictionary = {}
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
## a 200 ft map).
static func create(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT, with_chunks: bool = true
) -> AuthoredTerrain:
	var terrain := AuthoredTerrain.new()
	terrain.name = "AuthoredTerrain"
	terrain.build(doc, root, with_chunks)
	return terrain


## Resource paths of every palette texture build() binds for `doc`: the base surface's
## maps, each painted biome's ground, cliff and scree surface maps, the painted surfaces'
## and the base's rule surfaces. A caller can load them on background threads first, so
## build() finds them in the resource cache instead of loading on the main thread (about
## 35 ms cold for one surface).
static func texture_paths(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var surfaces := PaletteLibrary.surfaces(root)
	var names := [doc.base_surface]
	names.append_array(Array(base_rule_surfaces(doc.base_surface, root)))
	names.append_array(Array(doc.surface_ids))
	var accents := GroundAccents.base_accents(doc.base_surface, root)
	names.append_array(GroundAccents.surface_names(accents))
	for biome_id in doc.biome_ids:
		var biome := PaletteLibrary.biome(biome_id, root)
		for key in ["ground_surface", "cliff_surface", "scree_surface"]:
			names.append(biome.get(key, ""))
		names.append_array(GroundAccents.surface_names(biome.get("ground_accents", [])))
	var paths := PackedStringArray()
	for surface_name in names:
		var surface: Dictionary = surfaces.get(surface_name, {})
		for key in LAYER_MAPS:
			var relative: Variant = surface.get(key, "")
			if relative is String and relative != "":
				var path := root.path_join(relative)
				if not path in paths and ResourceLoader.exists(path):
					paths.append(path)
	return paths


## The cliff and scree surfaces [cliff, scree] that dress base surface `base` where no
## painted biome says otherwise: those of the palette's first biome on that ground, else
## the palette's first cliff surface and no scree ("" = none).
static func base_rule_surfaces(
	base: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	for biome in PaletteLibrary.biomes(root):
		if biome.get("ground_surface", "") == base:
			return PackedStringArray(
				[biome.get("cliff_surface", ""), biome.get("scree_surface", "")]
			)
	var cliffs := PaletteLibrary.surfaces_with_role("cliff", root)
	return PackedStringArray([cliffs[0] if not cliffs.is_empty() else "", ""])


## The ground material for palette surface `surface_name`: the authored ground shader
## with the surface's albedo, normal and ORM bound at its tile size. A surface the palette
## does not have, or whose albedo does not load, gets flat fallback textures and a
## warning, and the material carries FALLBACK_META so callers can tell.
static func build_ground_material(
	surface_name: String, map_seed: int = 0, root: String = PaletteLibrary.DEFAULT_ROOT
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("breakup_seed", map_seed & 0x7fffffff)
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var albedo := _load_texture(root, surface.get("albedo", ""))
	if albedo == null:
		push_warning(
			(
				"AuthoredTerrain: surface '%s' is not in the palette at %s; using a plain ground"
				% [surface_name, root]
			)
		)
		material.set_shader_parameter("albedo_tex", _solid_texture(FALLBACK_ALBEDO))
		material.set_shader_parameter("orm_tex", _solid_texture(FALLBACK_ORM))
		material.set_meta(FALLBACK_META, true)
		return material
	material.set_shader_parameter("albedo_tex", albedo)
	material.set_shader_parameter("tile_m", float(surface["tile_m"]))
	var normal := _load_texture(root, surface.get("normal", ""))
	if normal != null:
		material.set_shader_parameter("normal_tex", normal)
	var orm := _load_texture(root, surface.get("orm", ""))
	material.set_shader_parameter("orm_tex", orm if orm != null else _solid_texture(FALLBACK_ORM))
	var height := _load_texture(root, surface.get("height", ""))
	if height != null:
		material.set_shader_parameter("height_tex", height)
	return material


## Mean albedo of a palette surface (the last mip of its albedo, a box-filtered mean), or
## null when the surface or its albedo is missing. GroundLayerTable ranks overflow
## fallbacks by it; about 10 ms per surface (BPTC decompression), paid only on overflow.
static func surface_mean_albedo(
	surface_name: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Variant:
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var albedo := _load_texture(root, surface.get("albedo", ""))
	if albedo == null:
		return null
	var image := albedo.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed() and image.decompress() != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var offset := image.get_mipmap_offset(image.get_mipmap_count())
	var data := image.get_data()
	return Color8(data[offset], data[offset + 1], data[offset + 2])


## True when palette surface `surface_name` can be drawn (it exists and its albedo loads).
static func surface_available(
	surface_name: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> bool:
	var surface: Dictionary = PaletteLibrary.surfaces(root).get(surface_name, {})
	var path: String = surface.get("albedo", "")
	return path != "" and ResourceLoader.exists(root.path_join(path))


static func _load_texture(root: String, relative_path: String) -> Texture2D:
	if relative_path == "":
		return null
	var path := root.path_join(relative_path)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


static func _solid_texture(color: Color) -> ImageTexture:
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


## Builds (or rebuilds from scratch) everything for `doc`; the chunk meshes only with
## `with_chunks` (see create()).
func build(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT, with_chunks: bool = true
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
	_material = build_ground_material(doc.base_surface, doc.map_seed, root)
	_build_ground_layers()
	_fields = TerrainMeshBuilder.grid_fields(doc)
	if with_chunks:
		rebuild_chunks(TerrainMeshBuilder.chunk_cells(doc))
	_build_collision()
	_build_skirt()
	_refresh_height_texture()


## The shared ground material.
func get_material() -> ShaderMaterial:
	return _material


## The ground skirt: the base surface continued past the map edge, fading to transparent
## (see SKIRT in shaders/authored_ground.gdshaderinc), so a zoomed-out view shows the map
## dissolving into the background instead of a cut rectangle. Decoration only: no
## collision, no shadow casting, and Constants.BOUNDS_EXEMPT_META keeps it out of the pan
## bounds and the reflection probe. Rebuilt by build(); a height edit on the map edge
## refreshes its geometry (refresh_skirt(); its inner edge copies the boundary heights).
func get_skirt() -> MeshInstance3D:
	return get_node_or_null(SKIRT_NAME) as MeshInstance3D


## Ring width for the skirt: the longest noise-stretched fade plus a margin.
static func skirt_width_m() -> float:
	return SKIRT_FADE_M / (1.0 - SKIRT_WOBBLE) + 2.0


func _build_skirt() -> void:
	var old := get_skirt()
	if old != null:
		old.free()
	# The base surface's textures and seed, so the texture continues across the edge; no
	# layer weights (they clamp at the edge and would streak outward) and no rules (the
	# skirt shader compiles them out), only the base's accent patches (GroundAccents).
	_skirt_material = _material.duplicate() as ShaderMaterial
	_skirt_material.shader = SKIRT_SHADER
	_skirt_material.set_shader_parameter("layer_painted_mask", 0)
	_skirt_material.set_shader_parameter("layer_ground_mask", 0)
	GroundAccents.sync_skirt(_skirt_material, _material, _plan.get("layers", []).size())
	_skirt_material.set_shader_parameter("skirt_half_extent", document.extent_m() * 0.5)
	_skirt_material.set_shader_parameter("skirt_fade_m", SKIRT_FADE_M)
	_skirt_material.set_shader_parameter("skirt_wobble", SKIRT_WOBBLE)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _skirt_arrays())
	mesh.surface_set_material(0, _skirt_material)
	# In-place edge edits move vertices the build-time AABB does not know about; the skirt is
	# decoration outside every bounds walk, so a generous box costs nothing.
	var box := mesh.get_aabb()
	mesh.custom_aabb = AABB(
		Vector3(box.position.x, -SKIRT_AABB_HALF_HEIGHT_M, box.position.z),
		Vector3(box.size.x, 2.0 * SKIRT_AABB_HALF_HEIGHT_M, box.size.z)
	)
	_skirt_mirror = {}
	_skirt_rect = Rect2i()
	var skirt := MeshInstance3D.new()
	skirt.name = SKIRT_NAME
	skirt.mesh = mesh
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skirt.set_meta(Constants.BOUNDS_EXEMPT_META, true)
	add_child(skirt)


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
	var mesh := skirt.mesh as ArrayMesh
	var width := skirt_width_m()
	if _skirt_mirror.is_empty():
		_skirt_mirror = TerrainMeshBuilder.skirt_vertex_mirror(document, width, SKIRT_FADE_M)
	var count: int = _skirt_mirror.count
	var total := count * (TerrainMeshBuilder.SKIRT_RINGS + 1)
	var positions: PackedFloat32Array = _skirt_mirror.positions
	var normals: PackedInt32Array = _skirt_mirror.normals
	for indices in TerrainMeshBuilder.skirt_ranges(document, _skirt_rect):
		TerrainMeshBuilder.write_skirt_region(document, _skirt_mirror, indices, width, SKIRT_FADE_M)
		for r in TerrainMeshBuilder.SKIRT_RINGS + 1:
			var first := r * count + indices.x
			var end := r * count + indices.y
			mesh.surface_update_vertex_region(
				0, first * 12, positions.slice(first * 3, end * 3).to_byte_array()
			)
			mesh.surface_update_vertex_region(
				0, total * 12 + first * 8, normals.slice(first * 2, end * 2).to_byte_array()
			)
	_skirt_rect = Rect2i()
	last_skirt_usec = Time.get_ticks_usec() - started


## The skirt's geometry: the ring out to skirt_width_m(), falling back to the map floor
## over the fade distance, so it is at the base level wherever it is still visible.
func _skirt_arrays() -> Array:
	return TerrainMeshBuilder.build_skirt_arrays(document, skirt_width_m(), SKIRT_FADE_M)


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
	if document.biome_ids.size() != _planned_biomes or document.surface_ids != _planned_surfaces:
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


## Starts loading the surface textures of palette biome `biome_id` (ground, cliff, scree,
## accents) on background threads, so the first dab that gives one a slot binds cached
## textures instead of loading them on the main thread (21 to 25 ms for a new surface,
## measured in T3c). Harmless for surfaces already bound or the base.
func warm_biome_surface(biome_id: String) -> void:
	var biome := PaletteLibrary.biome(biome_id, palette_root)
	var bound := ground_layers()
	var names := GroundAccents.surface_names(biome.get("ground_accents", []))
	for key in ["ground_surface", "cliff_surface", "scree_surface"]:
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
		return surface != "" and surface_available(surface, root)
	var grounds := PackedStringArray()
	var cliffs := PackedStringArray()
	var screes := PackedStringArray()
	var accents: Array = []
	for biome_id in document.biome_ids:
		var biome := PaletteLibrary.biome(biome_id, root)
		var ground: String = biome.get("ground_surface", "")
		var cliff: String = biome.get("cliff_surface", "")
		var scree: String = biome.get("scree_surface", "")
		grounds.append(ground if available.call(ground) else "")
		cliffs.append(cliff if available.call(cliff) else "")
		screes.append(scree if available.call(scree) else "")
		accents.append(GroundAccents.drawable(biome.get("ground_accents", []), available))
	var painted := PackedStringArray()
	for surface in document.surface_ids:
		painted.append(surface if available.call(surface) else "")
	var base_rules := base_rule_surfaces(document.base_surface, root)
	for i in base_rules.size():
		if not available.call(base_rules[i]):
			base_rules[i] = ""
	var surfaces := PaletteLibrary.surfaces(root)
	var inputs := {
		"base": document.base_surface,
		"biome_ground": grounds,
		"biome_cliff": cliffs,
		"biome_scree": screes,
		"biome_coverage":
		GroundLayerTable.biome_coverage(
			document.biome_slots, document.biome_density, document.biome_ids.size()
		),
		"painted": painted,
		"base_rules": base_rules,
		"role_of":
		func(surface: String) -> String: return surfaces.get(surface, {}).get("role", "ground"),
		"color_of": func(surface: String) -> Variant: return surface_mean_albedo(surface, root),
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
				var texture := _load_texture(palette_root, surface.get(key, ""))
				maps[key].append(texture if texture else _solid_texture(LAYER_DEFAULTS[key]))
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
	GroundAccents.bind(_material, _plan, document.map_seed)
	if _skirt_material != null:
		GroundAccents.sync_skirt(_skirt_material, _material, layers.size())


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
	var mesh := TerrainMeshBuilder.build_chunk_mesh(document, cell, _material, _fields)
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
