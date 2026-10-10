class_name TerrainSkirt
extends RefCounted

## The ground skirt's material, its mesh and its in-place updates after an edit on the map edge
## (AuthoredTerrain.get_skirt(), which owns the node and the state; SkirtExits adds what runs on
## under it). Split out of AuthoredTerrain to keep that class a readable size.
##
## The skirt continues one surface: the base, or a painted surface that covers the map's edge
## (edge_surface), so a new forest map whose edge band is greened
## (LandformPlacement.paint_sparse) fades out on grass rather than a brown forest-floor halo
## (2026-10-09). The choice is made when the ground's slots are bound (a build, a replan); a
## later stroke that paints the edge without changing the slots shows on the skirt at the next.

## The mean weight over the map's edge samples a painted surface must reach for the skirt to
## continue it instead of the base.
const EDGE_SURFACE_SHARE := 0.6


## The skirt's material for ground material `ground` (slots planned in `plan`,
## GroundLayerTable.plan) on map `doc`, whose skirt fades over `fade_m` stretched by `wobble`:
## the base surface's textures and seed, so the texture continues across the edge, or the
## edge's own surface (sync_ground); no layer weights (they clamp at the edge and would streak
## outward), no rules (the skirt shader compiles them out) and no accent patches.
static func material(
	ground: ShaderMaterial, plan: Dictionary, doc: MapDocument, fade_m: float, wobble: float
) -> ShaderMaterial:
	var skirt := ground.duplicate() as ShaderMaterial
	skirt.shader = AuthoredTerrain.SKIRT_SHADER
	skirt.set_shader_parameter("layer_painted_mask", 0)
	skirt.set_shader_parameter("layer_ground_mask", 0)
	GroundAccents.sync_skirt(skirt, ground)
	sync_ground(skirt, doc, plan)
	skirt.set_shader_parameter("skirt_half_extent", doc.extent_m() * 0.5)
	skirt.set_shader_parameter("skirt_fade_m", fade_m)
	skirt.set_shader_parameter("skirt_wobble", wobble)
	return skirt


## Points `skirt` at the surface it continues: the shader slot `plan` gives the edge_surface of
## `doc` (skirt_ground_mask, with every slot sampled), else the base (mask 0, no slot sampled).
static func sync_ground(skirt: ShaderMaterial, doc: MapDocument, plan: Dictionary) -> void:
	var painted: PackedInt32Array = plan.get("painted_layers", PackedInt32Array())
	var slot := edge_surface(doc)
	var shader_slot := painted[slot] if slot >= 0 and slot < painted.size() else -1
	var mask := 1 << shader_slot if shader_slot >= 0 else 0
	skirt.set_shader_parameter("skirt_ground_mask", mask)
	skirt.set_shader_parameter(
		"layer_count", (plan.get("layers", []) as Array).size() if mask != 0 else 0
	)


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
