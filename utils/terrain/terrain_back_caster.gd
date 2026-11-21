class_name TerrainBackCaster
extends RefCounted

## How a terrain chunk casts its shadow under the Painted look (card painter-ground-robust): with
## its BACK faces only. The engine's way (front faces) puts the ground's own lit surface in the
## shadow map, and ground near edge-on to the sun then shadows itself in stripes and stipple (the
## map's texels stretch by 1 / N.L on it). Lowering the caster cures that but detaches every shadow
## from its foot at a low sun. With back faces the shadow map holds the far side of each hill:
## ground that faces the sun cannot be shadowed by its own surface, a hill's shadow still starts
## at its foot, and ground turned from the sun is shade by its form (painter_ground.gdshader's
## relative terminator), so it does not need the map.
## A material has one cull mode for every pass, so the chunk itself stops casting and a
## shadows-only twin (an internal child sharing the chunk's mesh, drawn with a cull_front
## material) casts in its place. AuthoredTerrain calls apply() wherever it decides a chunk's
## casting; the Classic look never asks for the twin, so its shadows are unchanged.
## Probed against the sun's shadow_reverse_cull_face, which gives the terrain the same shadows
## but flips every other caster too (a token's shadow thinned): rejected.

const NAME := "BackCaster"
## The twin's shader: front faces culled, depth only (it is never drawn in a colour pass), the
## caster moved a little toward the light so what stands right in front of a face turned from the
## sun is inside its shadow (the shader's header). Warmed by PainterWarmup.
const SHADER := "res://painter/shaders/painter_terrain_caster.gdshader"

static var _material: ShaderMaterial = null


## Makes `chunk` cast as `casting` says: by itself, or with `back` through its back-face twin.
static func apply(
	chunk: MeshInstance3D, casting: GeometryInstance3D.ShadowCastingSetting, back: bool
) -> void:
	var twin := chunk.get_node_or_null(NAME) as MeshInstance3D
	if not back:
		# The twin is hidden, not freed: it goes with its chunk, and comes back without a rebuild.
		if twin != null:
			twin.visible = false
		chunk.cast_shadow = casting
		return
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if casting == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		if twin != null:
			twin.visible = false
		return
	if twin == null:
		twin = MeshInstance3D.new()
		twin.name = NAME
		twin.material_override = _caster_material()
		twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		chunk.add_child(twin, false, Node.INTERNAL_MODE_BACK)
	twin.mesh = chunk.mesh
	twin.visible = true


## What `chunk` casts now, whichever way: ON or OFF.
static func casting(chunk: MeshInstance3D) -> GeometryInstance3D.ShadowCastingSetting:
	var twin := chunk.get_node_or_null(NAME) as MeshInstance3D
	if twin != null and twin.visible:
		return GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return chunk.cast_shadow


static func _caster_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER) as Shader
	return _material
