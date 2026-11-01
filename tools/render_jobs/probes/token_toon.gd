class_name TokenToonProbe
extends RefCounted

## Design probe (2026-11-01): an import-time toon / painterly look for pack tokens, three ways,
## behind one switch. `mode` is OFF by default and nothing in the game reads it: only the
## render job op `token_toon.gd` (and a test) call set_mode, so the shipped path is unchanged.
##
## - RAMP (approach 1): each surface material of a pack token is swapped for a ShaderMaterial
##   (token_toon_ramp.gdshader) that keeps the albedo (colour, texture, vertex colour), the
##   emission, the alpha mode and the culling, and lights it through a soft three-band ramp
##   with a violet shadow band, a warm lit band and a rim.
## - INK (approach 2): each surface material is duplicated with the engine's own toon diffuse
##   and a rim, and a shared inverted-hull ink material (token_toon_ink.gdshader) is chained
##   as its next_pass. The original material is untouched (it is the duplicate's source).
## - SCREEN (approach 3): the world SubViewportContainer's material is replaced by a posterise
##   and edge pass (token_toon_screen.gdshader) over the whole rendered image. No token work.
##
## Avatar tokens (AvatarTokenView, their own ShaderMaterial figure look) are left alone by
## RAMP and INK, so a row can show them beside the swapped pack tokens. What each token had
## is kept in a meta, so set_mode(OFF) puts back the very same material objects.

enum Mode { OFF, RAMP, INK, SCREEN }

const RAMP_SHADER_PATH := "res://tools/render_jobs/probes/token_toon_ramp.gdshader"
const INK_SHADER_PATH := "res://tools/render_jobs/probes/token_toon_ink.gdshader"
const SCREEN_SHADER_PATH := "res://tools/render_jobs/probes/token_toon_screen.gdshader"
## Meta on a MeshInstance3D: {"overrides": Array of per-surface override materials} as found.
const ORIGINAL_META := &"token_toon_original"

static var mode: int = Mode.OFF
## Source material -> its toon material, so tokens sharing a material share the swap.
static var _made: Dictionary = {}
static var _ramp_code := ""
static var _ramp_shaders: Dictionary = {}
static var _ink: ShaderMaterial = null
static var _screen: ShaderMaterial = null
static var _container_before: Material = null
static var _container_saved := false


## Sets the look for every token under `tree` and, for SCREEN, the pass on `container`.
## Everything the previous mode did is undone first, so any mode can follow any other.
static func set_mode(new_mode: int, tree: SceneTree, container: SubViewportContainer) -> void:
	for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
		strip(node as BoardToken)
	_set_screen(false, container)
	_made.clear()
	mode = new_mode
	if mode == Mode.SCREEN:
		_set_screen(true, container)
	elif mode != Mode.OFF:
		for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
			apply(node as BoardToken)


## Mode from its name ("off", "ramp", "ink", "screen"); OFF for anything else.
static func mode_named(mode_name: String) -> int:
	match mode_name.to_lower():
		"ramp":
			return Mode.RAMP
		"ink":
			return Mode.INK
		"screen":
			return Mode.SCREEN
	return Mode.OFF


## Swaps the pack token's surface materials for the current mode's (RAMP or INK).
## Does nothing in other modes, for an avatar, or on a mesh already swapped.
static func apply(token: BoardToken) -> void:
	if token == null or token.rigid_body == null or token.is_avatar():
		return
	if mode != Mode.RAMP and mode != Mode.INK:
		return
	for mi in TokenGhost.meshes_of(token.rigid_body):
		if mi.has_meta(ORIGINAL_META) or mi.mesh == null:
			continue
		var originals: Array = []
		for i in mi.mesh.get_surface_count():
			originals.append(mi.get_surface_override_material(i))
			var source: Material = originals[i]
			if source == null:
				source = mi.mesh.surface_get_material(i)
			if mi.material_override == null and source is BaseMaterial3D:
				mi.set_surface_override_material(i, _toon_of(source as BaseMaterial3D))
		mi.set_meta(ORIGINAL_META, {"overrides": originals})
		if mode == Mode.INK:
			mi.set_instance_shader_parameter("hull_center", mi.get_aabb().get_center())


## Puts back what `token`'s meshes had before apply (the same material objects).
static func strip(token: BoardToken) -> void:
	if token == null or token.rigid_body == null:
		return
	for mi in TokenGhost.meshes_of(token.rigid_body):
		if not mi.has_meta(ORIGINAL_META):
			continue
		var originals: Array = (mi.get_meta(ORIGINAL_META) as Dictionary).overrides
		for i in originals.size():
			mi.set_surface_override_material(i, originals[i] as Material)
		mi.remove_meta(ORIGINAL_META)


## How many mesh instances under `tree`'s tokens carry a swap (0 in OFF).
static func swapped_meshes(tree: SceneTree) -> int:
	var n := 0
	for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if token.rigid_body == null:
			continue
		for mi in TokenGhost.meshes_of(token.rigid_body):
			if mi.has_meta(ORIGINAL_META):
				n += 1
	return n


static func _toon_of(source: BaseMaterial3D) -> Material:
	if not _made.has(source):
		_made[source] = _ramp_of(source) if mode == Mode.RAMP else _ink_of(source)
	return _made[source]


## INK: the source duplicated with the engine's toon diffuse, a rim, and the shared hull.
static func _ink_of(source: BaseMaterial3D) -> Material:
	var mat := source.duplicate() as BaseMaterial3D
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 0.35
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.rim_tint = 0.6
	if source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and source.next_pass == null:
		mat.next_pass = _ink_material()
	return mat


static func _ink_material() -> ShaderMaterial:
	if _ink == null:
		_ink = ShaderMaterial.new()
		_ink.shader = load(INK_SHADER_PATH)
	return _ink


## RAMP: a ShaderMaterial of the source's albedo, emission, alpha mode and culling.
static func _ramp_of(source: BaseMaterial3D) -> ShaderMaterial:
	var blend := (
		source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		and source.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	)
	var scissor := source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var mat := ShaderMaterial.new()
	mat.shader = _shader_for(scissor, blend, source.cull_mode == BaseMaterial3D.CULL_DISABLED)
	mat.set_shader_parameter("albedo_color", source.albedo_color)
	if source.albedo_texture != null:
		mat.set_shader_parameter("use_tex", true)
		mat.set_shader_parameter("albedo_tex", source.albedo_texture)
	mat.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
	mat.set_shader_parameter("vertex_color_srgb", source.vertex_color_is_srgb)
	if source.emission_enabled:
		mat.set_shader_parameter("emission_color", source.emission)
		mat.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
		if source.emission_texture != null:
			mat.set_shader_parameter("use_emission_tex", true)
			mat.set_shader_parameter("emission_tex", source.emission_texture)
	mat.set_shader_parameter("alpha_cutoff", source.alpha_scissor_threshold)
	return mat


## The ramp shader for an alpha mode and a culling, built once from the file by prepending
## the defines its #ifdef blocks read.
static func _shader_for(scissor: bool, blend: bool, double_sided: bool) -> Shader:
	var key := "%s%s%s" % [scissor, blend, double_sided]
	if not _ramp_shaders.has(key):
		if _ramp_code.is_empty():
			_ramp_code = (load(RAMP_SHADER_PATH) as Shader).code
		var defines := ""
		defines += "#define MODE_SCISSOR\n" if scissor else ""
		defines += "#define MODE_BLEND\n" if blend else ""
		defines += "#define CULL_OFF\n" if double_sided else ""
		var shader := Shader.new()
		shader.code = defines + _ramp_code
		_ramp_shaders[key] = shader
	return _ramp_shaders[key]


## SCREEN: puts the screen pass on the container (remembering the lo-fi material), or back.
static func _set_screen(on: bool, container: SubViewportContainer) -> void:
	if container == null:
		return
	if on:
		if not _container_saved:
			_container_before = container.material
			_container_saved = true
		if _screen == null:
			_screen = ShaderMaterial.new()
			_screen.shader = load(SCREEN_SHADER_PATH)
		container.material = _screen
	elif _container_saved:
		container.material = _container_before
		_container_before = null
		_container_saved = false
