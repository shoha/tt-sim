class_name TokenToon
extends RefCounted

## The painted look of pack tokens: each surface material of a pack token's meshes is swapped for
## a ShaderMaterial of shaders/token_toon.gdshader (three soft bands, a per-source shade tint, a
## light rim; its header says how), so photographic PBR packs, chunky vertex-colour art and user
## imports read as one family beside the avatar kit. Settings > Graphics > "Token shading"
## (graphics/token_shading: Painted, the default, or Original).
##
## Model. Only pack tokens: an avatar (its own figure look), a placeholder (a material_override)
## and a mesh with a material_override are left alone, and a surface whose material is not a plain
## lit BaseMaterial3D (unshaded, billboard, hashed alpha, additive) keeps it. The swap is a surface
## override per surface; what the mesh had is kept in ORIGINAL_META on the MeshInstance3D
## ("overrides": the surface overrides as found, "sources": the material each surface was drawn
## with), so strip() puts back the very same objects and the token ghost and the hidden fade can
## read the source. A painted material is made once per source and kept in a meta on the source
## itself (so it lives and dies with it, and tokens sharing a material share the swap).
##
## The GM-hidden fade (BoardToken._set_mesh_transparency, 40 percent): an opaque or cutout
## ShaderMaterial has no alpha, so while a token is faded its surfaces use the BLEND variant of the
## same source and the mesh's `fade` instance uniform carries the alpha (set_fade). Unfaded, the
## opaque variant is back. A source that is blended anyway only gets the uniform.
##
## Shader variants (alpha mode x double-sided, six) are built once at load into an immutable
## dictionary by defines prepended to the one file, so the first-launch warm-up
## (warmup_samples, a GraphicsWarmup sample source) and the game draw the very same Shader
## objects. docs/systems/token_toon.md has the look, the numbers and the captures.

const DEFAULT_PAINTED := true
const SETTINGS_KEY := "token_shading"
## Item ids of the Settings option (the saved value).
const SHADING_PAINTED := 0
const SHADING_ORIGINAL := 1
const DEFAULT_ID := SHADING_PAINTED if DEFAULT_PAINTED else SHADING_ORIGINAL
const SHADER := preload("res://shaders/token_toon.gdshader")
## Meta on a MeshInstance3D that is painted: {"overrides": Array, "sources": Array}.
const ORIGINAL_META := &"token_toon_original"
## Metas on a source material: its painted material, and its blend twin.
const OPAQUE_META := &"token_toon_opaque"
const BLEND_META := &"token_toon_blend"
## The alpha of a token hidden from players, seen by its GM.
const HIDDEN_ALPHA := 0.4
const FADE_PARAM := &"fade"

## Whether pack tokens are painted (the setting). The factories read it for tokens made later.
static var painted := DEFAULT_PAINTED
## Variant key (see key_of) -> Shader; immutable after load, so safe to read from any thread.
static var _shaders: Dictionary = _build_shaders()


## Turns the painted look on or off for every pack token under `tree` and for tokens made later.
static func set_painted(on: bool, tree: SceneTree) -> void:
	painted = on
	refresh_all(tree)


## Brings every token under `tree` to the current setting (after a map load).
static func refresh_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
		refresh(node as BoardToken)


## Paints `token` or puts its materials back, as the setting says, and re-applies the GM-hidden
## fade the way the new materials need it.
static func refresh(token: BoardToken) -> void:
	if token == null or token.rigid_body == null or token.is_avatar():
		return
	var hidden := not token.is_visible_to_players
	if hidden:
		# Whatever fade the old materials carry must not be copied into the new ones.
		token.set_mesh_alpha(1.0)
	if painted:
		apply(token)
	else:
		strip(token)
	if hidden:
		token.set_mesh_alpha(HIDDEN_ALPHA)


## Swaps the pack token's surface materials for painted ones. Does nothing for an avatar, for a
## mesh that is already painted, or for a mesh with a material_override.
static func apply(token: BoardToken) -> void:
	if token == null or token.rigid_body == null or token.is_avatar():
		return
	for mi in TokenGhost.meshes_of(token.rigid_body):
		if mi.has_meta(ORIGINAL_META) or mi.material_override != null:
			continue
		var overrides: Array = []
		var sources: Array = []
		var any := false
		for i in mi.mesh.get_surface_count():
			var found := mi.get_surface_override_material(i)
			overrides.append(found)
			var source: Material = found if found != null else mi.mesh.surface_get_material(i)
			sources.append(source)
			any = any or paintable(source)
		if not any:
			continue
		mi.set_meta(ORIGINAL_META, {"overrides": overrides, "sources": sources})
		_write(mi, 1.0)


## Puts back what `token`'s meshes had before apply (the same material objects).
static func strip(token: BoardToken) -> void:
	if token == null or token.rigid_body == null:
		return
	for mi in TokenGhost.meshes_of(token.rigid_body):
		if not mi.has_meta(ORIGINAL_META):
			continue
		var overrides: Array = (mi.get_meta(ORIGINAL_META) as Dictionary).overrides
		for i in overrides.size():
			mi.set_surface_override_material(i, overrides[i] as Material)
		mi.remove_meta(ORIGINAL_META)
		mi.set_instance_shader_parameter(FADE_PARAM, 1.0)


## Whether `mi` carries painted materials.
static func is_painted(mi: MeshInstance3D) -> bool:
	return mi.has_meta(ORIGINAL_META)


## Sets the alpha of a painted mesh (1.0 opaque): below 1.0 its surfaces use the blend variant and
## the `fade` instance uniform. A mesh that is not painted is left alone (returns false).
static func set_fade(mi: MeshInstance3D, alpha: float) -> bool:
	if not is_painted(mi):
		return false
	_write(mi, alpha)
	return true


## The material surface `surface` of a painted mesh was drawn with before the swap, or null.
static func source_of(mi: MeshInstance3D, surface: int) -> Material:
	if not is_painted(mi):
		return null
	var sources: Array = (mi.get_meta(ORIGINAL_META) as Dictionary).sources
	return sources[surface] as Material if surface < sources.size() else null


## How many meshes under `tree`'s tokens are painted.
static func painted_meshes(tree: SceneTree) -> int:
	var n := 0
	for node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if token.rigid_body == null:
			continue
		for mi in TokenGhost.meshes_of(token.rigid_body):
			n += 1 if is_painted(mi) else 0
	return n


## Whether the painted look can stand in for `source`: a lit BaseMaterial3D drawn as a plain
## surface, a cutout or a blend.
static func paintable(source: Material) -> bool:
	if not source is BaseMaterial3D:
		return false
	var base := source as BaseMaterial3D
	return (
		base.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
		and base.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED
		and base.blend_mode == BaseMaterial3D.BLEND_MODE_MIX
		and base.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	)


## Writes each paintable surface of the painted mesh `mi` with the painted material of its source
## (the blend variant when `alpha` < 1). The `fade` instance uniform follows `alpha`.
static func _write(mi: MeshInstance3D, alpha: float) -> void:
	var sources: Array = (mi.get_meta(ORIGINAL_META) as Dictionary).sources
	var faded := alpha < 1.0
	for i in sources.size():
		var source := sources[i] as Material
		# A surface that cannot be painted keeps whatever it has (BoardToken's own fade works on it).
		if paintable(source):
			mi.set_surface_override_material(i, painted_of(source as BaseMaterial3D, faded))
	mi.set_instance_shader_parameter(FADE_PARAM, alpha)


## The painted material of `source` (made once, kept on the source). `faded` asks for the blend
## variant, which the hidden fade needs; a source that is blended anyway has one variant.
static func painted_of(source: BaseMaterial3D, faded: bool) -> ShaderMaterial:
	var blend := faded or _is_blend(source)
	var meta := BLEND_META if blend else OPAQUE_META
	if not source.has_meta(meta):
		source.set_meta(meta, make_material(source, blend))
	return source.get_meta(meta) as ShaderMaterial


static func _is_blend(source: BaseMaterial3D) -> bool:
	return (
		source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		and source.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	)


## A ShaderMaterial of the source's albedo, emission, alpha mode and culling.
static func make_material(source: BaseMaterial3D, blend: bool) -> ShaderMaterial:
	var scissor := source.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and not blend
	var double_sided := source.cull_mode == BaseMaterial3D.CULL_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = shader_for(scissor, blend, double_sided)
	mat.set_shader_parameter("albedo_color", source.albedo_color)
	if source.albedo_texture != null:
		mat.set_shader_parameter("use_tex", true)
		mat.set_shader_parameter("albedo_tex", source.albedo_texture)
	mat.set_shader_parameter("uv1_scale", source.uv1_scale)
	mat.set_shader_parameter("uv1_offset", source.uv1_offset)
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


## The shader for an alpha mode and a culling.
static func shader_for(scissor: bool, blend: bool, double_sided: bool) -> Shader:
	return _shaders[key_of(scissor, blend, double_sided)]


static func key_of(scissor: bool, blend: bool, double_sided: bool) -> String:
	return "%s%s%s" % ["s" if scissor else "-", "b" if blend else "-", "d" if double_sided else "-"]


## All six variants, by prepending the defines their #ifdef blocks read to the one shader file.
static func _build_shaders() -> Dictionary:
	var out := {}
	for alpha_mode in 3:
		for double_sided in [false, true]:
			var scissor: bool = alpha_mode == 1
			var blend: bool = alpha_mode == 2
			var defines := ""
			defines += "#define MODE_SCISSOR\n" if scissor else ""
			defines += "#define MODE_BLEND\n" if blend else ""
			defines += "#define CULL_OFF\n" if double_sided else ""
			var shader := Shader.new()
			shader.code = defines + SHADER.code
			out[key_of(scissor, blend, double_sided)] = shader
	return out


## GraphicsWarmup samples (the first-launch warm-up draws them): one triangle in each of the six
## variants on the two vertex layouts pack meshes come in (normal and UV; and with a vertex
## colour), so a first pack token does not compile its shader and pipelines in the frame it
## lands. Safe on a worker thread: it only makes resources, and the shaders are the immutable
## ones the game draws.
static func warmup_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for with_color in [false, true]:
		var arrays := _triangle_arrays(with_color)
		for key: String in _shaders:
			samples.append(
				{
					"name": "token_toon_%s%s" % [key, "_color" if with_color else ""],
					"primitive": Mesh.PRIMITIVE_TRIANGLES,
					"arrays": arrays,
					"material": GraphicsWarmup.material_for(_shaders[key] as Shader),
					"multimesh": false,
				}
			)
	return samples


static func _triangle_arrays(with_color: bool) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.FORWARD])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	if with_color:
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	return arrays
