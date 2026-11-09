class_name TerrainSkirt
extends RefCounted

## The ground skirt's material, its mesh and its in-place updates after an edit on the map edge
## (AuthoredTerrain.get_skirt(), which owns the node and the state; SkirtExits adds what runs on
## under it). Split out of AuthoredTerrain to keep that class a readable size.
##
## The skirt continues one surface: the base, or a painted surface that covers the map's edge
## (edge_surface), so a new forest map whose edge band is greened
## (LandformPlacement.paint_sparse) fades out on grass rather than a brown forest-floor halo
## (2026-10-09). The choice is made when the ground's tables are bound (a build, a new biome or
## surface); a later stroke that paints the edge without changing them shows on the skirt at
## the next.
##
## Two surfaces (card skirtring): the skirt receives no shadows (its shaders declare
## shadows_disabled; PERFORMANCE.md "Ground skirt shadows"), except an INNER RING, the first
## TerrainMeshBuilder.SKIRT_SHADOW_RINGS ring steps past the map edge, drawn with the ring shaders
## (the same without the render mode) as the mesh's second surface, so a tall caster at the edge
## still shadows the ground just beyond it. The ring material is a copy of the skirt's, mirrored
## uniform for uniform (sync_ring); the shader fades the shadow out over the ring's width, so the
## surfaces meet without a seam.

## The mean weight over the map's edge samples a painted surface must reach for the skirt to
## continue it instead of the base.
const EDGE_SURFACE_SHARE := 0.6
## The ring material's own uniform, which sync_ring leaves alone.
const RING_OWN_UNIFORM := "skirt_shadow_m"


## How far past the map edge the ring surface reaches on a skirt `width_m` wide, in metres (the
## distance of ring TerrainMeshBuilder.SKIRT_SHADOW_RINGS along the edges): the shaders' shadow
## reception has faded to nothing there. Pure.
static func ring_edge_m(width_m: float) -> float:
	return RiverExitMesh.skirt_distance(width_m, TerrainMeshBuilder.SKIRT_SHADOW_RINGS)


## The inner ring's material: a copy of `skirt` on the ring shader (the looked one when `looked`)
## whose shadow reception ends `edge_m` past the map edge. Keep it in step with sync_ring().
static func ring_material(skirt: ShaderMaterial, looked: bool, edge_m: float) -> ShaderMaterial:
	var ring := skirt.duplicate() as ShaderMaterial
	ring.shader = AuthoredTerrain.ring_shader(looked)
	ring.set_shader_parameter(RING_OWN_UNIFORM, edge_m)
	return ring


## Copies every uniform of `skirt` that the ring shader declares onto `ring`, so the two surfaces
## draw the same ground, fade, backdrop and fog. Cheap enough for the rare syncs (a re-table, a
## bake); SkirtBackdrop keeps both in step each frame by listing both.
static func sync_ring(skirt: ShaderMaterial, ring: ShaderMaterial) -> void:
	ring.render_priority = skirt.render_priority
	for uniform: Dictionary in ring.shader.get_shader_uniform_list():
		var uniform_name := String(uniform.name)
		if uniform_name != RING_OWN_UNIFORM:
			ring.set_shader_parameter(uniform_name, skirt.get_shader_parameter(uniform_name))


## The skirt's material for ground material `ground` (its layers bound by `layers`) on map
## `doc`, whose skirt fades over `fade_m` stretched by `wobble`: the ground's layer arrays and
## seed, so the texture continues across the edge, drawing the base or the edge's own surface
## (sync_ground); no index maps (they clamp at the edge and would streak outward; the skirt
## shader compiles them out), no rules and no accent patches.
static func material(
	ground: ShaderMaterial,
	layers: GroundLayerBinding,
	doc: MapDocument,
	fade_m: float,
	wobble: float
) -> ShaderMaterial:
	var skirt := ground.duplicate() as ShaderMaterial
	skirt.shader = AuthoredTerrain.ground_shader(
		true, ground.shader == AuthoredTerrain.GROUND_LOOKED_SHADER
	)
	skirt.set_shader_parameter("biome_present", 0)
	skirt.set_shader_parameter("paint_present", 0)
	GroundAccents.sync_skirt(skirt, ground)
	sync_ground(skirt, doc, layers)
	skirt.set_shader_parameter("skirt_half_extent", doc.extent_m() * 0.5)
	skirt.set_shader_parameter("skirt_fade_m", fade_m)
	skirt.set_shader_parameter("skirt_wobble", wobble)
	return skirt


## Points `skirt` at the surface it continues: the layer of `doc`'s edge_surface, whose
## channel dressing stays with it (as a painted surface's always did), else the base, whose
## channel takes the base row's water bed and shore (skirt_ground_layer, skirt_bed_layer,
## skirt_shore_layer).
static func sync_ground(
	skirt: ShaderMaterial, doc: MapDocument, layers: GroundLayerBinding
) -> void:
	var edge_layer := layers.painted_layer(edge_surface(doc))
	var bed := -1
	var shore := -1
	if edge_layer < 0:
		edge_layer = 0
		var routing := layers.routing
		bed = (routing.get("bed", PackedInt32Array([-1])) as PackedInt32Array)[0]
		shore = (routing.get("shore", PackedInt32Array([-1])) as PackedInt32Array)[0]
	skirt.set_shader_parameter("skirt_ground_layer", edge_layer)
	skirt.set_shader_parameter("skirt_bed_layer", bed)
	skirt.set_shader_parameter("skirt_shore_layer", shore)


## The painted surface (an index into `doc`'s surface_ids) whose weight averages at least
## EDGE_SURFACE_SHARE over the map's edge samples, the heaviest when several do; -1 when none
## does. Pure.
static func edge_surface(doc: MapDocument) -> int:
	var slots := doc.surface_ids.size()
	if slots == 0 or doc.surface_weights.is_empty():
		return -1
	var edge := PackedInt32Array()
	var last_x := doc.samples_x() - 1
	var last_z := doc.samples_z() - 1
	for x in last_x + 1:
		edge.append(doc.sample_index(x, 0))
		edge.append(doc.sample_index(x, last_z))
	for z in range(1, last_z):
		edge.append(doc.sample_index(0, z))
		edge.append(doc.sample_index(last_x, z))
	var best := -1
	var best_mean := EDGE_SURFACE_SHARE * 255.0
	for slot in slots:
		var total := 0
		for i in edge:
			total += doc.surface_weight(i, slot)
		var mean := float(total) / maxf(edge.size(), 1.0)
		if mean >= best_mean:
			best_mean = mean
			best = slot
	return best


## The skirt's mesh from `arrays` (RiverExitMesh.skirt_parts() "skirt") drawn with `skirt_material`.
## With a `ring_material` and a `ring_split` (the parts' "ring_split": how many of the indices,
## from the front, are the inner rings'), the inner rings are the second surface drawn with
## `ring_material` and surface 0 holds the rest; both share the one vertex layout, so an in-place
## edge update writes both.
static func mesh(
	arrays: Array,
	skirt_material: ShaderMaterial,
	ring_material: ShaderMaterial = null,
	ring_split: int = 0
) -> ArrayMesh:
	var built := ArrayMesh.new()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if ring_material == null or ring_split <= 0 or ring_split >= indices.size():
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		built.surface_set_material(0, skirt_material)
	else:
		var outer := arrays.duplicate()
		outer[Mesh.ARRAY_INDEX] = indices.slice(ring_split)
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, outer)
		built.surface_set_material(0, skirt_material)
		var inner := arrays.duplicate()
		inner[Mesh.ARRAY_INDEX] = indices.slice(0, ring_split)
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, inner)
		built.surface_set_material(1, ring_material)
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
			var position_bytes := positions.slice(first * 3, end * 3).to_byte_array()
			var normal_bytes := normals.slice(first * 2, end * 2).to_byte_array()
			for surface in skirt_mesh.get_surface_count():
				skirt_mesh.surface_update_vertex_region(surface, first * 12, position_bytes)
				skirt_mesh.surface_update_vertex_region(
					surface, total * 12 + first * 8, normal_bytes
				)
