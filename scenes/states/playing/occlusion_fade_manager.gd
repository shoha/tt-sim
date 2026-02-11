extends Node3D
class_name OcclusionFadeManager

## Fades map geometry that occludes tokens using a per-pixel spatial shader.
##
## APPROACH:
## Replaces map materials with a custom shader that checks, for every fragment,
## whether it sits between the camera and any token. Fragments in front of a
## token (within a configurable radius) are discarded in a dithered pattern,
## creating a screen-door transparency effect that lets the player see and
## interact with tokens behind walls, pillars, or other geometry.
##
## This works correctly regardless of whether the map is one mesh or many,
## because the fade decision is per-pixel, not per-mesh.
##
## SETUP:
## Call setup() with references to the camera, map container, and token container
## after the map has been loaded. The manager converts map materials to the
## occlusion shader and updates token positions every few physics frames.

## Multiplier applied to the token's collision extent to compute its fade radius.
## Higher = geometry fades further away from the token; lower = tighter fade zone.
@export var fade_radius_multiplier: float = 1.5
## Minimum fade radius (view-space units) for very small tokens.
@export var min_fade_radius: float = 0.3
## Minimum opacity at the center of a fade zone (0 = fully see-through).
@export_range(0.0, 1.0) var min_alpha: float = 0.3
## Height above token base to target (visual center, not feet on the floor).
@export var token_ray_height: float = 0.5
## Dither subdivisions per lo-fi pixel. Higher = finer dither pattern.
## 1 = matches lo-fi grid exactly, 2 = 2x2 cells per pixel, etc.
@export_range(1, 8) var lofi_dither_scale: float = 1.0
## Run token position updates every N physics frames.
@export_range(1, 10) var update_interval: int = 2

const MAX_TOKENS := 32

# References (set via setup())
var _camera: Camera3D
var _map_container: Node3D
var _tokens_container: Node3D # DragAndDrop3D

# The occlusion fade shader resource (loaded once)
var _shader: Shader

# Tracks converted materials for restoration.
# Key: MeshInstance3D instance_id -> Array of Dictionaries per surface:
#   { "surface_index": int, "original_material": Material or null, "shader_material": ShaderMaterial }
var _converted_meshes: Dictionary = {}

# Flat list of all ShaderMaterials we created (for fast uniform updates)
var _all_shader_materials: Array[ShaderMaterial] = []

var _frame_counter: int = 0
var _is_setup: bool = false
var _lofi_pixelation: float = 0.0 # Mirror of lo-fi shader's pixelation value (0 = disabled)


func _ready() -> void:
	_shader = load("res://shaders/occlusion_fade.gdshader") as Shader
	if not _shader:
		push_error("OcclusionFadeManager: Failed to load occlusion_fade.gdshader")


## Initialize the manager with required node references.
## Converts map materials to the occlusion shader.
func setup(camera: Camera3D, map_container: Node3D, tokens_container: Node3D) -> void:
	_camera = camera
	_map_container = map_container
	_tokens_container = tokens_container

	if not _shader:
		push_error("OcclusionFadeManager: No shader loaded, cannot set up")
		return

	_convert_map_materials()
	_is_setup = true


## Clear all state and restore original materials. Call before loading a new map.
func clear() -> void:
	_restore_all_materials()
	_converted_meshes.clear()
	_all_shader_materials.clear()
	_is_setup = false


func _physics_process(_delta: float) -> void:
	if not _is_setup or _all_shader_materials.is_empty():
		return

	_frame_counter += 1
	if _frame_counter % update_interval != 0:
		return

	_update_token_uniforms()


## Update the lo-fi pixelation value so the dither grid aligns with the
## post-process pixelation. Pass 0.0 when the lo-fi filter is disabled.
func set_lofi_pixelation(value: float) -> void:
	_lofi_pixelation = value
	for mat in _all_shader_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("lofi_pixelation", _lofi_pixelation)
			mat.set_shader_parameter("lofi_dither_scale", lofi_dither_scale)


# =============================================================================
# Material conversion
# =============================================================================

## Convert all StandardMaterial3D materials on map meshes to our occlusion shader.
func _convert_map_materials() -> void:
	if not _map_container:
		return

	var meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(_map_container, meshes)

	for mesh_inst in meshes:
		_convert_mesh_materials(mesh_inst)


## Convert all surface materials on a single MeshInstance3D.
func _convert_mesh_materials(mesh_inst: MeshInstance3D) -> void:
	if not mesh_inst.mesh:
		return

	var mesh_id := mesh_inst.get_instance_id()
	var surface_entries: Array[Dictionary] = []

	for surface_idx in range(mesh_inst.mesh.get_surface_count()):
		# Get the active material (override first, then mesh material)
		var original_mat: Material = mesh_inst.get_surface_override_material(surface_idx)
		if original_mat == null:
			original_mat = mesh_inst.mesh.surface_get_material(surface_idx)

		# Only convert StandardMaterial3D; leave ShaderMaterials as-is
		if original_mat is not StandardMaterial3D:
			continue

		var std_mat := original_mat as StandardMaterial3D
		var shader_mat := _create_shader_material_from(std_mat)

		mesh_inst.set_surface_override_material(surface_idx, shader_mat)
		_all_shader_materials.append(shader_mat)

		surface_entries.append({
			"surface_index": surface_idx,
			"original_material": original_mat,
			"shader_material": shader_mat,
		})

	if not surface_entries.is_empty():
		_converted_meshes[mesh_id] = {"mesh": mesh_inst, "surfaces": surface_entries}


## Create a ShaderMaterial that replicates a StandardMaterial3D's appearance
## and includes the occlusion fade logic.
func _create_shader_material_from(std_mat: StandardMaterial3D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader

	# --- Copy PBR properties ---
	mat.set_shader_parameter("albedo_color", std_mat.albedo_color)

	if std_mat.albedo_texture:
		mat.set_shader_parameter("has_albedo_texture", true)
		mat.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
	else:
		mat.set_shader_parameter("has_albedo_texture", false)

	mat.set_shader_parameter("roughness", std_mat.roughness)
	mat.set_shader_parameter("metallic", std_mat.metallic)

	if std_mat.normal_enabled and std_mat.normal_texture:
		mat.set_shader_parameter("has_normal_texture", true)
		mat.set_shader_parameter("normal_texture", std_mat.normal_texture)
		mat.set_shader_parameter("normal_scale", std_mat.normal_scale)
	else:
		mat.set_shader_parameter("has_normal_texture", false)

	if std_mat.emission_enabled:
		mat.set_shader_parameter("emission", std_mat.emission)
		mat.set_shader_parameter("emission_energy", std_mat.emission_energy_multiplier)

	mat.set_shader_parameter("uv1_scale", std_mat.uv1_scale)
	mat.set_shader_parameter("uv1_offset", std_mat.uv1_offset)

	# --- Occlusion parameters ---
	mat.set_shader_parameter("min_alpha", min_alpha)
	mat.set_shader_parameter("token_count", 0)
	mat.set_shader_parameter("lofi_pixelation", _lofi_pixelation)
	mat.set_shader_parameter("lofi_dither_scale", lofi_dither_scale)

	return mat


# =============================================================================
# Token position uniform updates
# =============================================================================

## Collect token world positions and per-token fade radii, then push to shaders.
## Uses the collision shape AABB center as the token position and derives the
## fade radius from the AABB extent so small tokens get a tight zone and large
## tokens get a proportionally larger one.
func _update_token_uniforms() -> void:
	var positions: Array = []
	var radii: Array = []
	var count := 0

	for child in _tokens_container.get_children():
		if child is BoardToken:
			var token := child as BoardToken
			if not token.rigid_body or not token.rigid_body.visible:
				continue

			# Find the token model's center and extent from its collision shape AABB.
			# This excludes the SelectionGlow disc (which is a separate mesh).
			var center_pos := token.rigid_body.global_position
			var token_radius := min_fade_radius
			var col_shape := _find_collision_shape(token.rigid_body)
			if col_shape and col_shape.shape:
				var aabb := col_shape.shape.get_debug_mesh().get_aabb()
				var local_center_y: float = aabb.position.y + aabb.size.y * 0.5
				var token_scale: Vector3 = token.rigid_body.scale
				center_pos += Vector3.UP * local_center_y * token_scale.y

				# Compute the fade radius from the token's horizontal footprint.
				# Use the larger of X/Z (ground-plane extent) rather than the
				# full 3D diagonal, which over-estimates for tall models.
				var scaled_size := aabb.size * token_scale
				var half_extent := maxf(scaled_size.x, scaled_size.z) * 0.5
				token_radius = maxf(half_extent * fade_radius_multiplier, min_fade_radius)
			else:
				# Fallback: use a flat height offset and default radius
				center_pos += Vector3.UP * token_ray_height

			positions.append(center_pos)
			radii.append(token_radius)
			count += 1
			if count >= MAX_TOKENS:
				break

	# Pad to 32 entries (shader arrays are fixed size)
	while positions.size() < MAX_TOKENS:
		positions.append(Vector3.ZERO)
		radii.append(0.0)

	# Update all shader materials with the new token data
	for mat in _all_shader_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("token_count", count)
			mat.set_shader_parameter("token_positions", positions)
			mat.set_shader_parameter("token_radii", radii)


# =============================================================================
# Restoration
# =============================================================================

## Restore all original materials on converted meshes.
func _restore_all_materials() -> void:
	for mesh_id in _converted_meshes:
		var data: Dictionary = _converted_meshes[mesh_id]
		var mesh_inst: MeshInstance3D = data.get("mesh")

		if not is_instance_valid(mesh_inst):
			continue

		var surfaces: Array = data.get("surfaces", [])
		for entry in surfaces:
			var surface_idx: int = entry["surface_index"]
			var original_mat: Material = entry["original_material"]

			if original_mat and mesh_inst.mesh:
				var mesh_mat = mesh_inst.mesh.surface_get_material(surface_idx)
				if original_mat == mesh_mat:
					# Original was the mesh's own material - clear override
					mesh_inst.set_surface_override_material(surface_idx, null)
				else:
					mesh_inst.set_surface_override_material(surface_idx, original_mat)
			else:
				mesh_inst.set_surface_override_material(surface_idx, null)


# =============================================================================
# Helpers
# =============================================================================

## Find the first CollisionShape3D child of a node (non-recursive, direct children only).
static func _find_collision_shape(node: Node) -> CollisionShape3D:
	for child in node.get_children():
		if child is CollisionShape3D:
			return child
	return null


## Recursively collect all visible MeshInstance3D nodes with geometry.
static func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.visible:
			var mesh_inst := child as MeshInstance3D
			if mesh_inst.mesh:
				result.append(mesh_inst)
		_collect_mesh_instances(child, result)
