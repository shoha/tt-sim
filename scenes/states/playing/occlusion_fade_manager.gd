class_name OcclusionFadeManager
extends Node3D

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
## occlusion shader, then packs token positions into one shared texture and
## publishes the count as a global every few physics frames.

## Max tracked tokens, and the width of the shared token data texture (one pixel
## per token slot).
const MAX_TOKENS := 32
## Global shader parameter carrying the number of valid token slots.
const GLOBAL_TOKEN_COUNT := &"occlusion_token_count"
## Per-material sampler uniform the shared token texture is bound to.
const TOKEN_TEXTURE_UNIFORM := &"occlusion_tokens"
## Channel masks matching BaseMaterial3D.TextureChannel, dotted against the sampled
## texel in the shader the way Godot's own material shader does it.
const CHANNEL_MASKS := {
	BaseMaterial3D.TEXTURE_CHANNEL_RED: Color(1.0, 0.0, 0.0, 0.0),
	BaseMaterial3D.TEXTURE_CHANNEL_GREEN: Color(0.0, 1.0, 0.0, 0.0),
	BaseMaterial3D.TEXTURE_CHANNEL_BLUE: Color(0.0, 0.0, 1.0, 0.0),
	BaseMaterial3D.TEXTURE_CHANNEL_ALPHA: Color(0.0, 0.0, 0.0, 1.0),
	BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE: Color(0.333333, 0.333333, 0.333333, 0.0),
}

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

# References (set via setup())
var _camera: Camera3D
var _map_container: Node3D
var _tokens_container: Node3D  # DragAndDrop3D

# The occlusion fade shader resource (loaded once)
var _shader: Shader

# Tracks converted materials for restoration.
# Key: MeshInstance3D instance_id -> Array of Dictionaries per surface:
#   { "surface_index": int, "original_material": Material or null,
#     "shader_material": ShaderMaterial }
var _converted_meshes: Dictionary = {}

# Flat list of all ShaderMaterials we created (for fast uniform updates)
var _all_shader_materials: Array[ShaderMaterial] = []

# Tree-category wind_foliage.gdshader materials registered for the occlusion fade
# (grass is excluded -- see design spec). These are never created or restored by
# this class (WindFoliage builds them at map-load time); we only register them for
# token uniform pushes and flip their enable_occlusion uniform on clear()/setup().
var _tree_materials: Array[ShaderMaterial] = []

var _frame_counter: int = 0
var _is_setup: bool = false
var _lofi_pixelation: float = 0.0  # Mirror of lo-fi shader's pixelation value (0 = disabled)

# Shared token data: pixel i = (world x, y, z, fade radius). Bound once to every
# material; one update() per tick reaches all of them.
var _token_image: Image
var _token_texture: ImageTexture

# Mirrors the value last published to GLOBAL_TOKEN_COUNT. RenderingServer's global
# shader parameter getter only returns real values inside the editor process (it
# warns and returns null from a running game, GUT tests included, headless or not)
# -- this field lets tests observe the published count without that getter.
var _last_token_count: int = 0

# Source StandardMaterial3D instance id -> the ShaderMaterial that replaces it, so
# surfaces sharing one source material keep sharing one converted material.
var _shader_material_by_source: Dictionary[int, ShaderMaterial] = {}
# Shape3D RID -> local AABB. The debug-mesh AABB is constant for a given shape.
var _aabb_cache: Dictionary[RID, AABB] = {}
# Entries published on the previous tick; identical ticks skip the GPU update.
var _last_entries: Array[Vector4] = []


func _ready() -> void:
	set_physics_process(false)
	_shader = load("res://shaders/occlusion_fade.gdshader") as Shader
	if not _shader:
		push_error("OcclusionFadeManager: Failed to load occlusion_fade.gdshader")
	_token_image = build_token_image([])
	_token_texture = ImageTexture.create_from_image(_token_image)


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
	_collect_tree_materials()
	_is_setup = true
	set_physics_process(true)


## Clear all state and restore original materials. Call before loading a new map.
func clear() -> void:
	_restore_all_materials()
	_disable_tree_materials()
	_converted_meshes.clear()
	_all_shader_materials.clear()
	_tree_materials.clear()
	_shader_material_by_source.clear()
	_aabb_cache.clear()
	_last_entries = []
	RenderingServer.global_shader_parameter_set(GLOBAL_TOKEN_COUNT, 0)
	_last_token_count = 0
	_is_setup = false
	set_physics_process(false)


func _physics_process(_delta: float) -> void:
	_frame_counter += 1
	if _frame_counter % update_interval != 0:
		return

	PerformanceMonitor.start_timer(&"perf/occlusion_fade_ms")
	_update_token_uniforms()
	PerformanceMonitor.stop_timer(&"perf/occlusion_fade_ms")


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
		var source_id := std_mat.get_instance_id()
		var shader_mat: ShaderMaterial = _shader_material_by_source.get(source_id)
		if shader_mat == null:
			shader_mat = _create_shader_material_from(std_mat)
			_shader_material_by_source[source_id] = shader_mat
			_all_shader_materials.append(shader_mat)

		mesh_inst.set_surface_override_material(surface_idx, shader_mat)

		(
			surface_entries
			. append(
				{
					"surface_index": surface_idx,
					"original_material": original_mat,
					"shader_material": shader_mat,
				}
			)
		)

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

	# roughness/metallic are multipliers over their texture channel, so the textures
	# have to come across too -- glTF ORM maps import with the scalars left at 1.0,
	# and copying those alone renders map geometry fully metallic and fully rough.
	mat.set_shader_parameter("roughness", std_mat.roughness)
	mat.set_shader_parameter("metallic", std_mat.metallic)
	_copy_channel_texture(
		mat,
		"roughness",
		std_mat.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS),
		std_mat.roughness_texture_channel
	)
	_copy_channel_texture(
		mat,
		"metallic",
		std_mat.get_texture(BaseMaterial3D.TEXTURE_METALLIC),
		std_mat.metallic_texture_channel
	)

	var ao_texture := std_mat.get_texture(BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION)
	_copy_channel_texture(
		mat, "ao", ao_texture if std_mat.ao_enabled else null, std_mat.ao_texture_channel
	)
	mat.set_shader_parameter("ao_light_affect", std_mat.ao_light_affect)
	mat.set_shader_parameter("ao_on_uv2", std_mat.ao_on_uv2)
	mat.set_shader_parameter("uv2_scale", std_mat.uv2_scale)
	mat.set_shader_parameter("uv2_offset", std_mat.uv2_offset)

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
	mat.set_shader_parameter("enable_occlusion", true)
	mat.set_shader_parameter("min_alpha", min_alpha)
	mat.set_shader_parameter(TOKEN_TEXTURE_UNIFORM, _token_texture)
	mat.set_shader_parameter("lofi_pixelation", _lofi_pixelation)
	mat.set_shader_parameter("lofi_dither_scale", lofi_dither_scale)

	return mat


## Bind one channel-packed data texture (roughness/metallic/ao) and its channel mask
## onto the shader material, or clear the has_* flag when there is no texture.
## `prefix` names the uniform family: "<prefix>_texture", "has_<prefix>_texture",
## "<prefix>_texture_channel".
func _copy_channel_texture(
	mat: ShaderMaterial, prefix: String, texture: Texture2D, channel: int
) -> void:
	if texture == null:
		mat.set_shader_parameter("has_%s_texture" % prefix, false)
		return
	mat.set_shader_parameter("has_%s_texture" % prefix, true)
	mat.set_shader_parameter("%s_texture" % prefix, texture)
	mat.set_shader_parameter(
		"%s_texture_channel" % prefix,
		CHANNEL_MASKS.get(channel, CHANNEL_MASKS[BaseMaterial3D.TEXTURE_CHANNEL_RED])
	)


## Find tree-category MultiMeshInstance3D nodes (built by GlbUtils/WindFoliage, tagged
## with wind_foliage_category meta) and register their wind_foliage.gdshader surface
## materials for the occlusion fade. Unlike _convert_map_materials, nothing is
## swapped here -- these materials already run wind_foliage.gdshader, which now
## includes the same fade logic as this class's own shader (see
## occlusion_fade_include.gdshaderinc). Idempotent: re-running skips materials
## already registered.
func _collect_tree_materials() -> void:
	if not _map_container:
		return

	var multimeshes: Array[MultiMeshInstance3D] = []
	_collect_tree_multimeshes(_map_container, multimeshes)

	for mm_inst in multimeshes:
		if not mm_inst.multimesh or not mm_inst.multimesh.mesh:
			continue
		var mesh := mm_inst.multimesh.mesh
		for surface_idx in range(mesh.get_surface_count()):
			var mat := mesh.surface_get_material(surface_idx)
			if not mat is ShaderMaterial:
				continue
			var shader_mat := mat as ShaderMaterial
			if shader_mat.shader != WindFoliage.get_shader():
				continue
			if shader_mat in _tree_materials:
				continue

			shader_mat.set_shader_parameter("enable_occlusion", true)
			shader_mat.set_shader_parameter(TOKEN_TEXTURE_UNIFORM, _token_texture)
			shader_mat.set_shader_parameter("min_alpha", min_alpha)
			shader_mat.set_shader_parameter("lofi_pixelation", _lofi_pixelation)
			shader_mat.set_shader_parameter("lofi_dither_scale", lofi_dither_scale)

			_tree_materials.append(shader_mat)
			_all_shader_materials.append(shader_mat)


## Stop tree materials from dithering with stale token data once physics_process
## stops pushing updates (called from clear()). Map materials don't need this: they
## get swapped back to StandardMaterial3D by _restore_all_materials() instead, so
## the shader (and its stale uniforms) simply stops being used.
func _disable_tree_materials() -> void:
	for mat in _tree_materials:
		if is_instance_valid(mat):
			mat.set_shader_parameter("enable_occlusion", false)


# =============================================================================
# Token position uniform updates
# =============================================================================


## Collect token world centres and per-token fade radii, pack them into the shared
## token texture, and publish the count as a global. One texture update plus one
## global set per tick, regardless of how many materials are converted. Returns
## false (and touches nothing) when no token moved since the previous tick.
func _update_token_uniforms() -> bool:
	var entries := _collect_token_entries()
	if entries == _last_entries:
		return false
	_last_entries = entries
	_token_image = build_token_image(entries)
	_token_texture.update(_token_image)
	RenderingServer.global_shader_parameter_set(GLOBAL_TOKEN_COUNT, entries.size())
	_last_token_count = entries.size()
	return true


## Per-token (world centre, fade radius) as Vector4(x, y, z, radius). Uses the
## collision shape AABB centre as the token position and derives the fade radius
## from the AABB extent so small tokens get a tight zone and large tokens get a
## proportionally larger one. Capped at MAX_TOKENS.
func _collect_token_entries() -> Array[Vector4]:
	var entries: Array[Vector4] = []
	for child in _tokens_container.get_children():
		if child is not BoardToken:
			continue
		var token := child as BoardToken
		if not token.rigid_body or not token.rigid_body.visible:
			continue

		# Find the token model's center and extent from its collision shape AABB.
		# This excludes the SelectionGlow disc (which is a separate mesh).
		var center_pos := token.rigid_body.global_position
		var token_radius := min_fade_radius
		var col_shape := _find_collision_shape(token.rigid_body)
		if col_shape and col_shape.shape:
			var aabb := _get_shape_aabb(col_shape.shape)
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

		entries.append(Vector4(center_pos.x, center_pos.y, center_pos.z, token_radius))
		if entries.size() >= MAX_TOKENS:
			break
	return entries


## Pack (x, y, z, radius) entries into a MAX_TOKENS x 1 RGBAF image.
## Unused slots are zero, which the shader treats as "no token" (radius 0).
static func build_token_image(entries: Array[Vector4]) -> Image:
	var image := Image.create_empty(MAX_TOKENS, 1, false, Image.FORMAT_RGBAF)
	var count := mini(entries.size(), MAX_TOKENS)
	for i in range(count):
		var e := entries[i]
		image.set_pixel(i, 0, Color(e.x, e.y, e.z, e.w))
	return image


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


## Local AABB of a collision shape, cached by shape RID. The debug mesh AABB is
## constant for a shape resource, so it is computed once per shape rather than
## per token per tick.
func _get_shape_aabb(shape: Shape3D) -> AABB:
	var key := shape.get_rid()
	if _aabb_cache.has(key):
		return _aabb_cache[key]
	var aabb := shape.get_debug_mesh().get_aabb()
	_aabb_cache[key] = aabb
	return aabb


## Recursively collect all visible MeshInstance3D nodes with geometry.
static func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.visible:
			var mesh_inst := child as MeshInstance3D
			if mesh_inst.mesh:
				result.append(mesh_inst)
		_collect_mesh_instances(child, result)


## Recursively collect visible MultiMeshInstance3D nodes tagged as tree-category
## foliage (wind_foliage_category meta, set by
## ScatterGlbUtils._build_multimesh_from_transforms from WindFoliage.classify_category).
## Grass and untagged nodes are skipped -- see design spec for why grass doesn't
## participate in the occlusion fade.
static func _collect_tree_multimeshes(node: Node, result: Array[MultiMeshInstance3D]) -> void:
	for child in node.get_children():
		if (
			child is MultiMeshInstance3D
			and child.visible
			and child.get_meta("wind_foliage_category", "") == "tree"
		):
			result.append(child as MultiMeshInstance3D)
		_collect_tree_multimeshes(child, result)
