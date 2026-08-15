class_name WaterGlbUtils
extends RefCounted

## Shared water-mesh material utilities extracted from GlbUtils to keep both files
## under this repo's gdlint max-file-lines gate. See utils/glb_utils.gd for GLB
## loading/processing in general.

const _WATER_SUFFIX := "-water"

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
static func process_water_meshes(node: Node) -> void:
	var water_nodes: Array[MeshInstance3D] = []
	_find_water_mesh_nodes(node, water_nodes)
	if water_nodes.is_empty():
		return
	var material := _get_water_material()
	for mesh_node in water_nodes:
		mesh_node.material_override = material
		_attach_water_zone(mesh_node)


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


## Apply a named Water Style preset (see WaterPresets) to the shared water
## ShaderMaterial. Called both from the level editor (live, on dropdown
## selection) and from the runtime level-load path, since the style choice
## lives on LevelData but the material is a single shared instance created
## lazily on first use (see _get_water_material()).
static func apply_water_style(style: String) -> void:
	var preset := WaterPresets.get_preset(style)
	var material := _get_water_material()
	for key in preset.keys():
		material.set_shader_parameter(key, preset[key])
