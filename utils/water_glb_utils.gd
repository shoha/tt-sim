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
## zero-manual-setup treatment as collision meshes.
static func process_water_meshes(node: Node) -> void:
	var water_nodes: Array[MeshInstance3D] = []
	_find_water_mesh_nodes(node, water_nodes)
	if water_nodes.is_empty():
		return
	var material := _get_water_material()
	for mesh_node in water_nodes:
		mesh_node.material_override = material


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
