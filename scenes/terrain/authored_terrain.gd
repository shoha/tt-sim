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

const CHUNK_NAME_PREFIX := "TerrainChunk"
const COLLISION_NAME := "TerrainCollision"
const GROUND_SHADER := preload("res://shaders/authored_ground.gdshader")
## Albedo and ORM for a map whose surface is missing from the palette: a neutral earth so
## the map still reads as ground, fully rough, never metallic.
const FALLBACK_ALBEDO := Color(0.36, 0.33, 0.26)
const FALLBACK_ORM := Color(1.0, 0.9, 0.0)
## Set on a ground material built without palette textures.
const FALLBACK_META := &"authored_ground_fallback"

var document: MapDocument = null
var palette_root: String = PaletteLibrary.DEFAULT_ROOT

var _material: ShaderMaterial = null
var _chunks: Dictionary[Vector2i, MeshInstance3D] = {}
var _body: StaticBody3D = null
var _shape: HeightMapShape3D = null


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
	rebuild_chunks(TerrainMeshBuilder.chunk_cells(doc))
	_build_collision()


## The shared ground material.
func get_material() -> ShaderMaterial:
	return _material


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
