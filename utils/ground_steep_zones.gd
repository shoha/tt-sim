class_name GroundSteepZones
extends RefCounted

## The ground look on steep faces (steepzones, 2026-11-08; docs/ARCHITECTURE.md "Steep faces";
## the shaders are ground_steep_zones.gdshaderinc and ground_steep_bake.gdshader).
##
## The look's bake is top-down, so a zone edge crossing a face runs down it as a stripe. A face
## instead reads the look's fields in 3D: each slot's fields before their thresholds are baked in
## LAYERS height layers (the same fields at a far XZ shift each), and a fragment blends the layers
## along its height, each field with its own layer length (its own scale, so it varies as fast up
## the face as across it), then thresholds and lights them like the bake, without strokes, edge
## variation or light streaks. weight() mixes that into the top-down texel by the normal's height,
## exactly 0 on ground gentler than about 29.5 degrees, so flat ground draws as before.
##
## The bake is one SubViewport for every slot (one sampler in the ground shader): per slot a band
## of LAYERS columns by ROWS rows (row 0: zone 1, 2, 3 shapes and the light's field; row 1: the
## zones' ragged-edge octave), each cell the bake rect at TEXELS_PER_M, RGBA8.
##
## Here: the GDScript mirrors of the shader's weight and layer blend (tests), the per-field layer
## lengths, the atlas size and bytes, and the ground's uniforms. Pure.

## The normal height (y of the unit normal) at and over which a face is flat (weight 0), and at
## and under which it is fully steep (weight 1): about 29.5 and 44.8 degrees.
const FLAT_NY := 0.87
const FULL_NY := 0.71
## Height layers and rows per slot band (ground_steep_bake.gdshader's STEEP_BAND).
const LAYERS := 3
const ROWS := 2
## The layer blend's phase in layer lengths (the shader's STEEP_PHASE).
const PHASE := 0.5
## A layer cell's density (half the look bake's: the finest field, the ragged edge, is a metre
## or more across) and its size limits.
const TEXELS_PER_M := 5.0
const MIN_PX := 8
const MAX_PX := 1024
## vec4s per slot in look_steep_params (the shader's STEEP_PARAMS).
const PARAMS := 12
## The shortest layer length (metres) a field takes.
const MIN_LENGTH_M := 0.25


## How much of the look at a ground point with normal `normal` (any length, map frame) comes from
## its 3D fields: 1 - smoothstep(FULL_NY, FLAT_NY, y), so exactly 0 on ground gentler than about
## 29.5 degrees and the same for every facing.
static func weight(normal: Vector3) -> float:
	var n := normal.normalized()
	return 1.0 - smoothstep(FULL_NY, FLAT_NY, n.y)


## The weights of the LAYERS layers at height `h` in layer lengths: with the PHASE added, layer
## k mod LAYERS fading (smoothstep) into layer k + 1 between k and k + 1. They sum to 1; at
## h = k - PHASE only layer k mod LAYERS holds and the height rate is 0, so with PHASE 0.5 no
## field is flat in height at height 0, where most walls meet the plain.
static func layer_weights(h: float) -> PackedFloat32Array:
	var k := floorf(h + PHASE)
	var t := h + PHASE - k
	t = t * t * (3.0 - 2.0 * t)
	var out := PackedFloat32Array()
	out.resize(LAYERS)
	var j := posmod(int(k), LAYERS)
	out[j] += 1.0 - t
	out[(j + 1) % LAYERS] += t
	return out


## A field's value at height `h` (in its layer length) from its value in each layer (`values`,
## LAYERS of them, centred on 0.5): the layers' weighted mix, its spread around 0.5 restored (two
## independent fields mixed half and half would read flatter than either).
static func blend(values: PackedFloat32Array, h: float) -> float:
	var w := layer_weights(h)
	var m := 0.0
	var norm := 0.0
	for i in LAYERS:
		m += w[i] * values[i]
		norm += w[i] * w[i]
	return 0.5 + (m - 0.5) / sqrt(norm)


## Each field's layer length in metres for the merged look `look` (GroundLook): {"fields":
## Vector4(zone 1, zone 2, zone 3, light), "rag": the ragged edge}, each its own scale
## (zones.scale_m, light.scale_m, zones.rag_m); a nested third zone takes the second's.
static func layer_lengths(look: Dictionary) -> Dictionary:
	var z: Dictionary = look.zones
	var scale: Array = z.scale_m
	var third := float(scale[1]) if float(z.nest) > 0.5 else float(scale[2])
	return {
		"fields":
		Vector4(
			maxf(float(scale[0]), MIN_LENGTH_M),
			maxf(float(scale[1]), MIN_LENGTH_M),
			maxf(third, MIN_LENGTH_M),
			maxf(float(look.light.scale_m), MIN_LENGTH_M)
		),
		"rag": maxf(float(z.rag_m), MIN_LENGTH_M),
	}


## One layer cell's texels for the bake rect `rect` (map-frame origin, size in metres).
static func cell_px(rect: Vector4) -> Vector2i:
	return Vector2i(
		clampi(ceili(rect.z * TEXELS_PER_M), MIN_PX, MAX_PX),
		clampi(ceili(rect.w * TEXELS_PER_M), MIN_PX, MAX_PX)
	)


## The steep bake's size for `slots` slots of cells `cell` texels.
static func atlas_px(cell: Vector2i, slots: int) -> Vector2i:
	return Vector2i(cell.x * LAYERS, cell.y * ROWS * maxi(slots, 1))


## The steep bake's bytes (RGBA8) over `rect` for `slots` slots.
static func atlas_bytes(rect: Vector4, slots: int) -> int:
	var px := atlas_px(cell_px(rect), slots)
	return px.x * px.y * 4


## The ground's steep uniforms: look_steep (`texture`, the bake), look_steep_atlas and
## look_steep_params for the merged looks of the slots (`looks`, slot order) with their light
## references (`refs`, linear), over `rect`.
static func tables(looks: Array, refs: Array, rect: Vector4, texture: Texture2D) -> Dictionary:
	var cell := cell_px(rect)
	return {
		"look_steep": texture,
		"look_steep_atlas": Vector4(maxi(looks.size(), 1), cell.x, cell.y, 0.0),
		"look_steep_params": params(looks, refs),
	}


## look_steep_params (GroundLookUniforms.SLOTS * PARAMS vec4s; the layout is in
## ground_steep_zones.gdshaderinc): per slot the zone colours, cover, edges and OKLab mode, the
## light's key, pools and tints as the bake computes them, the layer lengths and the reference.
static func params(looks: Array, refs: Array) -> PackedVector4Array:
	var out := PackedVector4Array()
	out.resize(GroundLookUniforms.SLOTS * PARAMS)
	for s in mini(looks.size(), GroundLookUniforms.SLOTS):
		var look: Dictionary = looks[s]
		if look.is_empty():
			continue
		var u := GroundLookUniforms.uniforms(look)
		var ref: Color = refs[s] if s < refs.size() else GroundLookUniforms.NO_REF
		var lengths := layer_lengths(look)
		var light_cover := float(u.light_field_cover)
		var lit := _v3(u.light_field_lit_tint) * (1.0 + float(u.light_field_lift))
		var shade := _v3(u.light_field_shade_tint) * (1.0 - float(u.light_field_shade))
		var o := s * PARAMS
		var tail := [float(u.zone_oklab), float(u.zone_rag), float(lengths.rag), 0.0]
		for i in 4:
			out[o + i] = _with_w(_v3(u["zone_color_%d" % i]), tail[i])
		out[o + 4] = _with_w(_v3(u.zone_cover), float(u.light_field_key))
		out[o + 5] = _with_w(
			_v3(u.zone_edge), lerpf(0.2, 0.02, clampf(light_cover / 0.5, 0.0, 1.0))
		)
		out[o + 6] = lengths.fields
		out[o + 7] = _with_w(lit, lerpf(1.0, 0.35, clampf(float(u.light_field_crisp), 0.0, 1.0)))
		out[o + 8] = _with_w(shade, float(u.light_field_shade))
		out[o + 9] = _with_w(_v3(u.zone_shade_warm), 0.0)
		out[o + 10] = Vector4(ref.r, ref.g, ref.b, 0.0)
	return out


static func _v3(value: Variant) -> Vector3:
	if value is Array:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	var f := float(value)
	return Vector3(f, f, f)


static func _with_w(v: Vector3, w: float) -> Vector4:
	return Vector4(v.x, v.y, v.z, w)
