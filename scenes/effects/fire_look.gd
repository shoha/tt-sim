class_name FireLook
extends RefCounted

## The look of persistent ground fire (design: docs/plans/2026-10-11-fire-features/design.md
## section 4): FireField owns placement, chunks and the budget; this owns the meshes and the
## materials, how a block's plan becomes MultiMesh instances, and the ground's glow binding.
##
## The flames are fire_field.gdshader: one camera-facing quad per flame in the fire events'
## banded-tongue family, its shape, motion and colour all in the shader (the header there holds
## the model), so nothing runs per flame per frame. A chunk's instance data is one packed buffer
## (instance_buffer): a scale-only basis (the flame's width and height in metres) at its foot,
## and (layout + seed, intensity, kind, keep) as custom data. The first `count` entries of the
## plan are drawn (FireField emits each plan shuffled, so any prefix is an even thinning); every
## second of them by plan order keeps showing past the LOD zoom (keep 1), and the drawn ones are
## sorted back to front along the camera's fixed forward axis once, since alpha-blended
## instances draw in buffer order and the camera only pans and zooms.
##
## The glow is a term in the authored ground shader (fire_glow.gdshaderinc): the document's
## fire_mask uploaded whole as an R8 texture on the sample grid (glow_texture) and bound to the
## terrain's material (bind_glow).
##
## One map is shown at a time, so the material's per-map uniforms (the wind, the LOD switch) are
## set on the shared material by the map's FireField.

const SHADER := preload("res://shaders/fire_field.gdshader")
## Floats per instance in a MultiMesh buffer: a 3x4 transform, then the custom data.
const INSTANCE_FLOATS := 16
## How far the wind leans a flame's tip to the side on screen (a share of its height).
const WIND_LEAN := 0.25
## Past the LOD zoom the kept half grows by this, to cover the hidden half.
const FAR_GROW := 1.25
## The camera's forward axis when there is none (tests, a field built before the camera): the
## game camera's fixed yaw and about its pitch.
const DEFAULT_FORWARD := Vector3(-0.67, -0.33, -0.67)
## Room a chunk's bounds keep around its flames: sideways (a big flame's half width and its
## lean) and down, and up (a spark rises about 1.8 m above its ember, and a breakoff above its
## tongue).
const BOUNDS_MARGIN_M := 2.0
const BOUNDS_RISE_M := 2.4

static var _mesh: QuadMesh = null
static var _material: ShaderMaterial = null


## The flame quad (shared): a unit quad the shader stands on its foot and turns to the camera.
static func mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2.ONE
	return _mesh


## The flames' material (shared).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("far_grow", FAR_GROW)
	return _material


## The map's wind for map seed `map_seed`: a direction in world XZ times WIND_LEAN. Pure.
static func wind_for(map_seed: int) -> Vector2:
	var angle := MaskBrush.sample_noise(map_seed + 11, 0x51ED) * TAU
	return Vector2.from_angle(angle) * WIND_LEAN


## Sets the map's wind on the shared material.
static func set_wind(map_seed: int) -> void:
	material().set_shader_parameter("wind", wind_for(map_seed))


## Past the LOD zoom (`far`), half the flames hide and the rest grow (one uniform).
static func set_far(far: bool) -> void:
	material().set_shader_parameter("far_view", 1.0 if far else 0.0)


## How many of `count` drawn flames still show past the LOD zoom. Pure.
static func far_count(count: int) -> int:
	@warning_ignore("integer_division")
	return (count + 1) / 2


## A chunk for one burning block, empty until fill_chunk.
static func make_chunk(chunk_name: String) -> MultiMeshInstance3D:
	var chunk := MultiMeshInstance3D.new()
	chunk.name = chunk_name
	chunk.material_override = material()
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh()
	chunk.multimesh = multimesh
	return chunk


## Draws the first `count` entries of `plan` (FireField's STRIDE layout) in `chunk`, sorted
## back to front along `forward`.
static func fill_chunk(
	chunk: MultiMeshInstance3D, plan: PackedFloat32Array, count: int, forward: Vector3
) -> void:
	var buffer := instance_buffer(plan, count, forward)
	var multimesh := chunk.multimesh
	multimesh.instance_count = count
	multimesh.buffer = buffer
	chunk.custom_aabb = bounds(plan, count)


## The MultiMesh buffer for the first `count` entries of `plan` (INSTANCE_FLOATS each), the
## far ones first along `forward`; every second entry by plan order has keep 1. Pure.
static func instance_buffer(
	plan: PackedFloat32Array, count: int, forward: Vector3
) -> PackedFloat32Array:
	var stride := FireField.STRIDE
	var order: Array = []
	for k in count:
		var o := k * stride
		order.append([Vector3(plan[o], plan[o + 1], plan[o + 2]).dot(forward), k])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := PackedFloat32Array()
	out.resize(count * INSTANCE_FLOATS)
	for slot in count:
		var k: int = order[slot][1]
		var o := k * stride
		var i := slot * INSTANCE_FLOATS
		var width := plan[o + FireField.WIDTH]
		var height := plan[o + FireField.HEIGHT]
		# Row-major 3x4: (basis x, y, z, origin) per row.
		out[i] = width
		out[i + 3] = plan[o]
		out[i + 5] = height
		out[i + 7] = plan[o + 1]
		out[i + 10] = width
		out[i + 11] = plan[o + 2]
		out[i + 12] = plan[o + FireField.SEED]
		out[i + 13] = plan[o + FireField.INTENSITY]
		out[i + 14] = plan[o + FireField.KIND]
		out[i + 15] = 1.0 if k % 2 == 0 else 0.0
	return out


## The bounds of the first `count` entries of `plan`, with room for the flames' quads, the
## far zoom's growth and a spark's rise. Pure.
static func bounds(plan: PackedFloat32Array, count: int) -> AABB:
	var box := AABB()
	var tallest := 0.0
	for k in count:
		var o := k * FireField.STRIDE
		var at := Vector3(plan[o], plan[o + 1], plan[o + 2])
		box = AABB(at, Vector3.ZERO) if k == 0 else box.expand(at)
		tallest = maxf(tallest, plan[o + FireField.HEIGHT])
	var side := Vector3(BOUNDS_MARGIN_M, BOUNDS_MARGIN_M, BOUNDS_MARGIN_M)
	var up := Vector3(0.0, tallest * FAR_GROW + BOUNDS_RISE_M, 0.0)
	return AABB(box.position - side, box.size + side * 2.0 + up)


## The fire mask of `doc` as an R8 texture on its sample grid: `texture` updated in place when
## it has the grid's size, else a new one; null without a mask.
static func glow_texture(doc: MapDocument, texture: ImageTexture) -> ImageTexture:
	var size := Vector2i(doc.samples_x(), doc.samples_z())
	if doc.fire_mask.size() != size.x * size.y:
		return null
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, doc.fire_mask)
	if texture != null and Vector2i(texture.get_size()) == size:
		texture.update(image)
		return texture
	return ImageTexture.create_from_image(image)


## Binds the glow's mask `texture` (null: no fire) to the ground material `ground`.
static func bind_glow(ground: ShaderMaterial, texture: ImageTexture) -> void:
	ground.set_shader_parameter("fire_mask_map", texture)
	ground.set_shader_parameter("fire_present", 0 if texture == null else 1)
