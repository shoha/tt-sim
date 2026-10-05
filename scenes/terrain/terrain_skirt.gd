class_name TerrainSkirt
extends RefCounted

## The ground skirt's material, its mesh and its in-place updates after an edit on the map edge
## (AuthoredTerrain.get_skirt(), which owns the node and the state; SkirtExits adds what runs on
## under it). Split out of AuthoredTerrain to keep that class a readable size.


## The skirt's material for ground material `ground` (`layer_count` slots) on map `doc`, whose
## skirt fades over `fade_m` stretched by `wobble`: the base surface's textures and seed, so the
## texture continues across the edge; no layer weights (they clamp at the edge and would streak
## outward) and no rules (the skirt shader compiles them out), only the base's accent patches
## (GroundAccents).
static func material(
	ground: ShaderMaterial, layer_count: int, doc: MapDocument, fade_m: float, wobble: float
) -> ShaderMaterial:
	var skirt := ground.duplicate() as ShaderMaterial
	skirt.shader = AuthoredTerrain.SKIRT_SHADER
	skirt.set_shader_parameter("layer_painted_mask", 0)
	skirt.set_shader_parameter("layer_ground_mask", 0)
	GroundAccents.sync_skirt(skirt, ground, layer_count)
	skirt.set_shader_parameter("skirt_half_extent", doc.extent_m() * 0.5)
	skirt.set_shader_parameter("skirt_fade_m", fade_m)
	skirt.set_shader_parameter("skirt_wobble", wobble)
	return skirt


## The skirt's mesh from `arrays` (RiverExitMesh.skirt_parts() "skirt") drawn with `skirt_material`.
static func mesh(arrays: Array, skirt_material: ShaderMaterial) -> ArrayMesh:
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	built.surface_set_material(0, skirt_material)
	# In-place edge edits move vertices the build-time AABB does not know about; the skirt is
	# decoration outside every bounds walk, so a generous box costs nothing.
	var box := built.get_aabb()
	var half := AuthoredTerrain.SKIRT_AABB_HALF_HEIGHT_M
	built.custom_aabb = AABB(
		Vector3(box.position.x, -half, box.position.z), Vector3(box.size.x, 2.0 * half, box.size.z)
	)
	return built


## Rewrites in `skirt_mesh` the vertices of the boundary samples in `rect` from map `doc`'s heights,
## through `mirror` (TerrainMeshBuilder.skirt_vertex_mirror(), updated too) of a skirt `width`
## wide fading over `fade_m`: positions and normals only (surface_update_vertex_region), since
## the triangles and UVs depend on XZ alone.
static func update_in_place(
	skirt_mesh: ArrayMesh,
	mirror: Dictionary,
	doc: MapDocument,
	rect: Rect2i,
	width: float,
	fade_m: float
) -> void:
	var count: int = mirror.count
	var total := count * (TerrainMeshBuilder.SKIRT_RINGS + 1)
	var positions: PackedFloat32Array = mirror.positions
	var normals: PackedInt32Array = mirror.normals
	for indices in TerrainMeshBuilder.skirt_ranges(doc, rect):
		TerrainMeshBuilder.write_skirt_region(doc, mirror, indices, width, fade_m)
		for r in TerrainMeshBuilder.SKIRT_RINGS + 1:
			var first := r * count + indices.x
			var end := r * count + indices.y
			skirt_mesh.surface_update_vertex_region(
				0, first * 12, positions.slice(first * 3, end * 3).to_byte_array()
			)
			skirt_mesh.surface_update_vertex_region(
				0, total * 12 + first * 8, normals.slice(first * 2, end * 2).to_byte_array()
			)
