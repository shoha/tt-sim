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
## Phase 3 sculpting edits doc.heights in place, then calls rebuild_chunks() with the
## touched cells and update_collision() once per stroke (both measured cheap: about 1 ms
## per chunk and 0.5 ms for the whole 200 ft heightfield).
##
## Biome ground. Painted biomes also paint the ground: each biome's palette ground_surface
## is one of up to four shader layers blended over the base surface by an RGBA8 weight map
## on the sample grid (the representation, layer assignment and overflow rule are
## BiomeGroundLayers'). The weight map is a DrawableTexture2D so a brush stroke uploads only
## the samples it changed: the biome brush edits doc.biome_slots / biome_density in place,
## then calls update_biome_region() with the changed sample rectangle, which recomputes
## those texels and blits them in (a texel-exact copy, shaders/texel_copy_blit.gdshader). A
## biome first painted mid-session takes a free layer by setting that layer's uniforms; the
## material itself is never rebuilt. A CPU mirror of the texture (get_biome_weights()) is
## kept for tests and for anything that must read the weights back.

const CHUNK_NAME_PREFIX := "TerrainChunk"
const COLLISION_NAME := "TerrainCollision"
const GROUND_SHADER := preload("res://shaders/authored_ground.gdshader")
const TEXEL_COPY_SHADER := preload("res://shaders/texel_copy_blit.gdshader")
## Ground shader uniforms of the biome layers; each map is a sampler array of
## BiomeGroundLayers.MAX_LAYERS.
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
## Microseconds of the last update_biome_region() call, for measurement.
var last_biome_update_usec: int = 0

var _material: ShaderMaterial = null
var _chunks: Dictionary[Vector2i, MeshInstance3D] = {}
var _body: StaticBody3D = null
var _shape: HeightMapShape3D = null
## Layer index -> palette surface (BiomeGroundLayers.plan()["layers"]).
var _layers: PackedStringArray = PackedStringArray()
## Biome slot -> layer index or BiomeGroundLayers.BASE.
var _slot_layers: PackedInt32Array = PackedInt32Array([BiomeGroundLayers.BASE])
## Biome ids the current plan covers; more in the document means a biome was added.
var _planned_biomes: int = 0
## Overflowed surfaces already warned about (surface -> true).
var _warned_fallbacks: Dictionary = {}
var _weights: Image = null
var _weight_texture: DrawableTexture2D = null


## A terrain for `doc`, fully built: every chunk, the collision body and the material.
static func create(doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT) -> AuthoredTerrain:
	var terrain := AuthoredTerrain.new()
	terrain.name = "AuthoredTerrain"
	terrain.build(doc, root)
	return terrain


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
## null when the surface or its albedo is missing. BiomeGroundLayers ranks overflow
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


## Builds (or rebuilds from scratch) everything for `doc`.
func build(doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT) -> void:
	document = doc
	palette_root = root
	for chunk in _chunks.values():
		chunk.free()
	_chunks.clear()
	_material = build_ground_material(doc.base_surface, doc.map_seed, root)
	_build_biome_ground()
	rebuild_chunks(TerrainMeshBuilder.chunk_cells(doc))
	_build_collision()


## The shared ground material.
func get_material() -> ShaderMaterial:
	return _material


## The palette surface of each biome ground layer, in layer (weight channel) order.
func ground_layers() -> PackedStringArray:
	return _layers.duplicate()


## The CPU mirror of the biome weight texture (RGBA8, one texel per sample). Do not modify.
func get_biome_weights() -> Image:
	return _weights


## Recomputes the biome ground weights of the samples in `sample_rect` (sample
## coordinates, position = first sample, size in samples; clipped to the grid) from the
## document's biome masks and uploads just those texels. Call it after every mask edit
## with a rectangle covering every sample changed since the last call. A biome id appended
## to the document since the last call is given a layer first (a free one, the one its
## surface already has, or its overflow fallback), which only sets uniforms.
func update_biome_region(sample_rect: Rect2i) -> void:
	var start := Time.get_ticks_usec()
	if document.biome_ids.size() != _planned_biomes:
		_plan_layers()
	var grid := Rect2i(0, 0, document.samples_x(), document.samples_z())
	var rect := sample_rect.intersection(grid)
	if rect.has_area():
		var region := Image.create_from_data(
			rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8, _weight_bytes(rect)
		)
		_weights.blit_rect(region, Rect2i(Vector2i.ZERO, rect.size), rect.position)
		_upload(region, rect.position)
	last_biome_update_usec = Time.get_ticks_usec() - start


func _build_biome_ground() -> void:
	_layers = PackedStringArray()
	_slot_layers = PackedInt32Array([BiomeGroundLayers.BASE])
	_planned_biomes = 0
	_warned_fallbacks.clear()
	_plan_layers()
	var size := Vector2i(document.samples_x(), document.samples_z())
	_weights = Image.create_from_data(
		size.x, size.y, false, Image.FORMAT_RGBA8, _weight_bytes(Rect2i(Vector2i.ZERO, size))
	)
	_weight_texture = DrawableTexture2D.new()
	_weight_texture.setup(
		size.x, size.y, DrawableTexture2D.DRAWABLE_FORMAT_RGBA8, Color(0, 0, 0, 0), false
	)
	if not document.biome_slots.is_empty():
		_upload(_weights, Vector2i.ZERO)
	_material.set_shader_parameter("biome_weights", _weight_texture)
	_material.set_shader_parameter("biome_grid_origin", -document.extent_m() * 0.5)
	_material.set_shader_parameter("biome_grid_step", document.sample_step())
	_material.set_shader_parameter("biome_layer_count", _layers.size())


## (Re)plans the ground layers for the document's current biome list, keeping every layer
## already assigned, and binds the textures of any new layer.
func _plan_layers() -> void:
	var root := palette_root
	var surfaces := BiomeGroundLayers.biome_surfaces(
		document.biome_ids,
		func(biome_id: String) -> String:
			return PaletteLibrary.biome(biome_id, root).get("ground_surface", ""),
		func(surface: String) -> bool: return surface_available(surface, root)
	)
	var base := document.base_surface
	var coverage := {}
	var fresh := 0
	for surface in BiomeGroundLayers.distinct_layers(surfaces, base):
		if not _layers.has(surface):
			fresh += 1
	if _layers.size() + fresh > BiomeGroundLayers.MAX_LAYERS:
		coverage = BiomeGroundLayers.coverage(
			document.biome_slots, document.biome_density, surfaces
		)
	var result := BiomeGroundLayers.plan(
		surfaces,
		base,
		coverage,
		func(surface: String) -> Variant: return surface_mean_albedo(surface, root),
		_layers
	)
	var fallbacks: Dictionary = result["fallbacks"]
	for surface in fallbacks:
		if not _warned_fallbacks.has(surface):
			_warned_fallbacks[surface] = true
			var drawn: String = fallbacks[surface]
			push_warning(
				(
					"AuthoredTerrain: more than %d biome ground surfaces; '%s' is drawn as '%s'"
					% [BiomeGroundLayers.MAX_LAYERS, surface, drawn if drawn != "" else base]
				)
			)
	var changed := (result["layers"] as PackedStringArray) != _layers
	_layers = result["layers"]
	_slot_layers = result["slot_layers"]
	_planned_biomes = document.biome_ids.size()
	if changed:
		_bind_layers()


## Binds every layer's textures and tile size. Unused array entries (and a layer surface
## missing a map) get small solid textures: they are never sampled where it matters (an
## unused layer's weight is masked to 0), but every sampler stays valid.
func _bind_layers() -> void:
	var maps := {}
	for key in LAYER_MAPS:
		maps[key] = []
	var tiles := Vector4.ONE * DEFAULT_LAYER_TILE_M
	var surfaces := PaletteLibrary.surfaces(palette_root)
	for index in BiomeGroundLayers.MAX_LAYERS:
		var surface: Dictionary = surfaces.get(_layers[index], {}) if index < _layers.size() else {}
		for key in LAYER_MAPS:
			var texture := _load_texture(palette_root, surface.get(key, ""))
			maps[key].append(texture if texture != null else _solid_texture(LAYER_DEFAULTS[key]))
		tiles[index] = float(surface.get("tile_m", DEFAULT_LAYER_TILE_M))
	for key in LAYER_MAPS:
		_material.set_shader_parameter(LAYER_MAPS[key], maps[key])
	_material.set_shader_parameter("layer_tile_m", tiles)
	_material.set_shader_parameter("biome_layer_count", _layers.size())


func _weight_bytes(rect: Rect2i) -> PackedByteArray:
	return BiomeGroundLayers.weight_bytes(
		document.biome_slots, document.biome_density, document.samples_x(), _slot_layers, rect
	)


## Copies `region` into the weight texture at `at`, texel for texel.
func _upload(region: Image, at: Vector2i) -> void:
	if _texel_copy == null:
		_texel_copy = ShaderMaterial.new()
		_texel_copy.shader = TEXEL_COPY_SHADER
	_weight_texture.blit_rect(
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
func rebuild_chunks(cells: Array[Vector2i]) -> void:
	for cell in cells:
		var mesh := TerrainMeshBuilder.build_chunk_mesh(document, cell, _material)
		if mesh == null:
			continue
		var chunk: MeshInstance3D = _chunks.get(cell, null)
		if chunk == null:
			chunk = MeshInstance3D.new()
			chunk.name = CHUNK_NAME_PREFIX + ScatterChunker.cell_suffix(cell)
			add_child(chunk)
			_chunks[cell] = chunk
		chunk.mesh = mesh


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
