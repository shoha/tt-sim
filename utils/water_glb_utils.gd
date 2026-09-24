class_name WaterGlbUtils
extends RefCounted

## Shared water-mesh material utilities extracted from GlbUtils to keep both files
## under this repo's gdlint max-file-lines gate. See utils/glb_utils.gd for GLB
## loading/processing in general.

const _WATER_SUFFIX := "-water"
## Shared-material sampler the level's flow map is set on (shaders/water.gdshader).
const FLOW_MAP_PARAM := "water_flow_map"
## Per-instance flag on the one plane the flow map was baked for.
const FLOW_PRESENT_PARAM := &"water_flow_present"

static var _water_material: ShaderMaterial = null


## Get the shared water ShaderMaterial, building it once on first use. Every "-water"
## suffixed mesh across every loaded map shares this single instance -- there's no
## per-map tuning yet, matching the naming-convention-only water feature (see
## terrain-paint's README "Water" section for the Blender-side naming convention).
static func _get_water_material() -> ShaderMaterial:
	if _water_material == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = load("res://shaders/water.gdshader")
	return _water_material


## Apply the shared water shader to any mesh named with a "-water" suffix (case-
## insensitive), e.g. a terrain-paint "Lake-water" plane. Mirrors
## _find_collision_mesh_nodes' suffix-matching approach so water gets the same
## zero-manual-setup treatment as collision meshes. Also attaches a WaterZone sibling
## to each mesh so token/water interaction (see WaterZone) works with the same
## zero-setup convention.
##
## Flow map: terrain-paint bakes the level's river direction into the water preview
## material's emission texture (see docs/superpowers/specs/2026-09-23-water-flow-design.md).
## That texture is lifted onto the shared material here and the plane it belongs to is
## flagged with a per-instance uniform; every other plane renders still water. A level
## with no map clears the sampler so the previous level's rivers cannot leak into it.
static func process_water_meshes(node: Node) -> void:
	var water_nodes: Array[MeshInstance3D] = []
	_find_water_mesh_nodes(node, water_nodes)
	if water_nodes.is_empty():
		return
	var material := _get_water_material()
	var flow_plane := _flow_map_plane(water_nodes)
	var flow_map: Texture2D = _extract_flow_map(flow_plane) if flow_plane else null
	material.set_shader_parameter(FLOW_MAP_PARAM, flow_map)
	for mesh_node in water_nodes:
		mesh_node.material_override = material
		mesh_node.set_instance_shader_parameter(FLOW_PRESENT_PARAM, mesh_node == flow_plane)
		_attach_water_zone(mesh_node)


## The imported material's emission texture, which terrain-paint uses to carry the
## level's flow map, or null when the plane carries none. Reads the mesh's own surface
## material: material_override is what this loader is about to set, never the imported one.
static func _extract_flow_map(mesh_node: MeshInstance3D) -> Texture2D:
	if mesh_node == null or mesh_node.mesh == null:
		return null
	if mesh_node.mesh.get_surface_count() == 0:
		return null
	var imported := mesh_node.mesh.surface_get_material(0) as BaseMaterial3D
	if imported == null:
		return null
	return imported.emission_texture


## The plane whose flow map is used: the largest XZ footprint among the planes that carry
## one. terrain-paint bakes for its largest "-water" plane but shares one preview
## material across all of them, so every plane arrives carrying the same texture.
static func _flow_map_plane(water_nodes: Array[MeshInstance3D]) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_area := 0.0
	for mesh_node in water_nodes:
		if _extract_flow_map(mesh_node) == null:
			continue
		var size := mesh_node.mesh.get_aabb().size
		var area := size.x * size.z
		if best == null or area > best_area:
			best = mesh_node
			best_area = area
	return best


## Attach a WaterZone sibling to mesh_node, mirroring
## GlbUtils._process_single_collision_node()'s StaticBody3D-sibling convention. No-op if
## the mesh's footprint is degenerate (see WaterZone.create_for_mesh()) or it has no
## parent to attach a sibling to.
static func _attach_water_zone(mesh_node: MeshInstance3D) -> void:
	var parent := mesh_node.get_parent()
	if not parent:
		return
	var zone := WaterZone.create_for_mesh(mesh_node)
	if not zone:
		return
	zone.transform = mesh_node.transform
	parent.add_child(zone)


## Push the latest submerged-token disturbance points onto the shared water material's
## water_disturbance_points uniform (see water.gdshader). Called every frame by every
## live WaterZone (see WaterZone._process()) -- redundant if multiple zones exist, but
## harmless since it's the same small fixed-size array written to the same shared
## material each time.
static func push_disturbance_points(points: Array) -> void:
	_get_water_material().set_shader_parameter("water_disturbance_points", points)


static func _find_water_mesh_nodes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.name.to_lower().ends_with(_WATER_SUFFIX):
		result.append(node)
	for child in node.get_children():
		_find_water_mesh_nodes(child, result)


## Apply a legacy Water Style name (see WaterPresets.STYLE_COMPOSITION) to the
## shared water ShaderMaterial. Kept for the loader's fallback path and for
## callers that only know a style name; the drawer and the level-load path use
## apply_water_settings() with a full WaterSettings dictionary.
static func apply_water_style(style: String) -> void:
	apply_water_settings(WaterPresets.get_preset(style))


## Apply a WaterSettings.to_dict() (or any subset of it) to the shared water
## ShaderMaterial. Called from the level editor (live, on every edit), from the
## runtime level-load path, and from the client receive path -- the material is
## a single shared instance created lazily on first use (see
## _get_water_material()), so this is the one seam every path goes through.
## Colors arrive as Color from in-process callers and as hex strings from JSON
## and the network; both are accepted. Keys the shader does not declare are
## skipped so a payload from a newer build cannot error here.
static func apply_water_settings(settings: Dictionary) -> void:
	var material := _get_water_material()
	for key: String in settings:
		if key not in WaterSettings.KEYS:
			continue
		var value: Variant = settings[key]
		if key in WaterSettings.COLOR_KEYS:
			var current: Variant = material.get_shader_parameter(key)
			var fallback: Color = current if current is Color else Color.WHITE
			material.set_shader_parameter(key, WaterSettings.color_from_value(value, fallback))
		else:
			material.set_shader_parameter(key, float(value))
