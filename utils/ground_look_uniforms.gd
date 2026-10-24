class_name GroundLookUniforms
extends RefCounted

## A merged ground look (GroundLook) as shader uniforms (ground ship card 3b). Three materials
## read a look:
##   - the bake (shaders/ground_light_field_bake.gdshader), one per look and map: the zones, the
##     strokes, the painted light and the light reference under their round 20 names
##     (bake_params);
##   - the grass (wind_foliage_main, LIGHT_FIELD_TUFT): the tuft and mass shading, the light's
##     cap, the reference and the bake (tuft_params);
##   - the ground and its skirt (authored_ground, GROUND LOOK): per look slot a few packed vec4s
##     (brush, light, cap, rims, accent shape) and the tables that say which biome row and which
##     layer each slot owns (plan, ground_tables), so a map of several biomes draws each biome's
##     own look.
## NAMES is the contract table's "r20 name" column (docs/ASSET_PIPELINE.md section 9), so
## uniforms() gives a look back in round 20's terms; the run-time values (the bake texture and
## rect, the seed offset, the light reference, the tuft reference, the sun) are passed in.
## Everything here is pure but ref_linear and opaque_mean_linear, which read textures once and
## cache the result.

## Looks a map binds at once (the ground shader's look_tex_0..3); a further biome with a look
## draws today's ground (GroundLookBake warns once).
const SLOTS := 4
## Biome rows (the ground shader's look_row_slots, four per ivec4) and layers (look_layer_slots).
const ROW_SLOTS := 256
const LAYER_SLOTS := GroundLayers.MAX_LAYERS
## The ground's tables with no look on the map: today's ground.
const OFF := {"look_present": 0}
## The contract key -> round 20 uniform name (zones.colors_linear is zone_color_0 .. 3).
const NAMES := {
	"ref_surface": "ref_surface",
	"zones.colors_linear": "zone_color_",
	"zones.strength": "zone_strength",
	"zones.cover": "zone_cover",
	"zones.scale_m": "zone_scale_m",
	"zones.edge": "zone_edge",
	"zones.stretch": "zone_stretch",
	"zones.stretch_k": "zone_stretch_k",
	"zones.angle": "zone_angle",
	"zones.angle_k": "zone_angle_k",
	"zones.warp": "zone_warp",
	"zones.rag": "zone_rag",
	"zones.rag_m": "zone_rag_m",
	"zones.nest": "zone_nest",
	"zones.edge_vary": "zone_edge_vary",
	"zones.edge_vary_m": "zone_edge_vary_m",
	"zones.shade_warm": "zone_shade_warm",
	"zones.oklab": "zone_oklab",
	"zones.layers": "zone_layers",
	"strokes.on": "zone_stroke",
	"strokes.m": "zone_stroke_m",
	"strokes.len": "zone_stroke_len",
	"strokes.edge": "zone_stroke_edge",
	"strokes.soft_lo": "zone_stroke_soft_lo",
	"strokes.soft_hi": "zone_stroke_soft_hi",
	"strokes.soft_m": "zone_stroke_soft_m",
	"brush.contrast": "zone_brush_contrast",
	"brush.hue": "zone_brush_hue",
	"brush.key": "zone_brush_key",
	"brush.mean": "zone_brush_mean",
	"light.strength": "light_field_strength",
	"light.key": "light_field_key",
	"light.scale_m": "light_field_scale_m",
	"light.cover": "light_field_cover",
	"light.lift": "light_field_lift",
	"light.lit_tint": "light_field_lit_tint",
	"light.shade": "light_field_shade",
	"light.shade_tint": "light_field_shade_tint",
	"light.streak": "light_field_streak",
	"light.streak_m": "light_field_streak_m",
	"light.streak_stretch": "light_field_streak_stretch",
	"light.streak_angle": "light_field_streak_angle",
	"light.streak_ripple": "light_field_streak_ripple",
	"light.streak_cover": "light_field_streak_cover",
	"light.knee": "light_field_knee",
	"light.cap": "light_field_cap",
	"light.sat_cap": "light_field_sat_cap",
	"light.broad": "light_field_broad",
	"light.stretch": "light_field_stretch",
	"light.crisp": "light_field_crisp",
	"light.ripple_curve": "light_field_ripple_curve",
	"tuft.strength": "zone_tuft_strength",
	"tuft.step": "zone_tuft_step",
	"tuft.contrast": "zone_tuft_contrast",
	"tuft.hue": "zone_tuft_hue",
	"tuft.knee": "zone_tuft_knee",
	"tuft.cap": "zone_tuft_cap",
	"tuft.capped": "zone_tuft_capped",
	"mass.step": "zone_mass_step",
	"mass.sat": "zone_mass_sat",
	"mass.lit": "zone_mass_lit",
	"mass.lit_m": "zone_mass_lit_m",
	"mass.contrast": "zone_mass_contrast",
	"mass.base": "zone_mass_base",
	"mass.tip": "zone_mass_tip",
	"mass.h_m": "zone_mass_h_m",
	"mass.own": "zone_mass_own",
	"mass.up_pow": "zone_mass_up_pow",
	"mass.shade": "mass_shade",
	"mass.shade_size": "mass_shade_size",
	"mass.shade_push": "mass_shade_push",
	"mass.lift": "mass_lift",
	"mass.lift_size": "mass_lift_size",
	"mass.lift_push": "mass_lift_push",
	"rim.surfaces": "rim_surfaces",
	"rim.accent_rim_m": "accent_rim_m",
	"rim.path_rim_m": "path_rim_m",
	"rim.strength": "rim_strength",
	"rim.wobble": "rim_wobble",
	"rim.gap": "rim_gap",
	"rim.path_blend_width": "path_blend_width",
	"rim.color_linear": "rim_color",
	"rim.accent_core_m": "accent_core_m",
	"rim.core_dark": "core_dark",
	"rim.accent_tint": "accent_tint",
	"accent_shape.stretch": "accent_stretch",
	"accent_shape.stretch_angle": "accent_stretch_angle",
	"accent_shape.break": "accent_break",
	"accent_shape.edge_scale": "accent_edge_scale",
}
## The bake shader's uniforms (besides zone_color_0..3, the reference, the seed and the rect).
const BAKE_GROUPS := ["zones", "strokes", "light"]
const BAKE_SKIP := ["zone_strength", "zone_layers", "light_field_strength"]
const BAKE_SKIP_LIGHT := ["light_field_knee", "light_field_cap", "light_field_sat_cap"]
## The grass's uniforms (besides the reference, the tuft reference, the sun, the bake and rect).
const TUFT_GROUPS := ["tuft", "mass"]
const TUFT_LIGHT := ["light_field_knee", "light_field_cap", "light_field_sat_cap"]
const STAMP_NAMES := [
	"mass_shade", "mass_shade_size", "mass_shade_push", "mass_lift", "mass_lift_size", "mass_lift_push"
]
## Grey, the reference of a texture with no opaque texel (as the probe's).
const NO_REF := Color(0.18, 0.18, 0.18)
## Texels sampled per row when a mean is measured (the texture's width over this, at least 1).
const MEAN_SAMPLES := 128

static var _refs: Dictionary = {}
static var _tuft_refs: Dictionary = {}


## Every contract key of `look` under its round 20 name (zone_color_0 .. 3 for the colours; a
## look of three colours repeats the third), values as in the look (floats, arrays, names). {}
## for no look.
static func uniforms(look: Dictionary) -> Dictionary:
	if look.is_empty():
		return {}
	var out := {"ref_surface": look.ref_surface}
	var colors: Array = look.zones.colors_linear
	for i in 4:
		out["zone_color_%d" % i] = colors[mini(i, colors.size() - 1)]
	for key: String in NAMES:
		var group := key.get_slice(".", 0)
		if key == "ref_surface" or key == "zones.colors_linear":
			continue
		out[NAMES[key]] = look[group][key.get_slice(".", 1)]
	return out


## The bake material's uniforms for `look` with light reference `ref` (linear), the seed offset
## `seed_m` (GroundZones.seed_offset) and the bake rect (map-frame XZ origin, size in metres).
static func bake_params(look: Dictionary, ref: Color, seed_m: Vector2, rect: Vector4) -> Dictionary:
	var named := uniforms(look)
	var out := {
		"light_field_ref": Vector3(ref.r, ref.g, ref.b), "zone_seed_m": seed_m, "bake_rect": rect
	}
	for i in 4:
		out["zone_color_%d" % i] = _typed(named["zone_color_%d" % i])
	for key: String in NAMES:
		var name: String = NAMES[key]
		if key == "zones.colors_linear" or name in BAKE_SKIP + BAKE_SKIP_LIGHT:
			continue
		if key.get_slice(".", 0) in BAKE_GROUPS:
			out[name] = _typed(named[name])
	return out


## The grass material's uniforms for `look`: the tuft and mass shading, the light's cap, the
## reference `ref`, the sun's XZ direction `lit_dir` and the bake `tex` over `rect`. The tuft
## reference is the material's own (opaque_mean_linear).
static func tuft_params(
	look: Dictionary, ref: Color, lit_dir: Vector2, tex: Texture2D, rect: Vector4
) -> Dictionary:
	var named := uniforms(look)
	var out := {
		"light_field_tex": tex,
		"light_field_rect": rect,
		"light_field_ref": as_r20_spatial(ref),
		"zone_mass_lit_dir": lit_dir,
	}
	for name: String in TUFT_LIGHT:
		out[name] = float(named[name])
	for key: String in NAMES:
		var name: String = NAMES[key]
		if key.get_slice(".", 0) in TUFT_GROUPS and not name in STAMP_NAMES:
			out[name] = _typed(named[name])
	return out


## The look slots of a map. `rows` holds per biome row (row 0 the base) {"biome": its palette
## biome id ("" none), "ground": the layer its ground draws on}; `looks` maps a biome id to its
## merged look ({} or absent: none); `layer_of` maps a surface name to its layer (-1 none). Each
## looked biome takes the next free slot, up to SLOTS ("dropped" lists the rest). Returns
## {"biomes": slot -> biome id, "row_slots": ROW_SLOTS ints, "layer_slots": LAYER_SLOTS ints
## (the slot whose zones colour the layer: zones.layers when set, else the row's ground, first
## slot wins), "rim_layers": SLOTS * 4 ints, "dropped"}. Pure.
static func plan(rows: Array, looks: Dictionary, layer_of: Callable) -> Dictionary:
	var biomes := PackedStringArray()
	var dropped := PackedStringArray()
	var row_slots := _filled(ROW_SLOTS)
	var layer_slots := _filled(LAYER_SLOTS)
	var rim_layers := _filled(SLOTS * 4)
	for r in mini(rows.size(), ROW_SLOTS):
		var biome_id := String(rows[r].get("biome", ""))
		var look: Dictionary = looks.get(biome_id, {})
		if look.is_empty():
			continue
		var s := biomes.find(biome_id)
		if s < 0 and biomes.size() >= SLOTS:
			if not biome_id in dropped:
				dropped.append(biome_id)
			continue
		if s < 0:
			s = biomes.size()
			biomes.append(biome_id)
			var rims: Array = look.rim.surfaces
			for i in mini(rims.size(), 4):
				rim_layers[s * 4 + i] = int(layer_of.call(String(rims[i])))
		row_slots[r] = s
		var zoned: Array = look.zones.layers
		var layers := [int(rows[r].get("ground", -1))]
		if not zoned.is_empty():
			layers = zoned.map(func(surface: Variant) -> int: return int(layer_of.call(surface)))
		for layer: int in layers:
			if layer >= 0 and layer < LAYER_SLOTS and layer_slots[layer] < 0:
				layer_slots[layer] = s
	return {
		"biomes": biomes,
		"row_slots": row_slots,
		"layer_slots": layer_slots,
		"rim_layers": rim_layers,
		"dropped": dropped,
	}


## The ground (and skirt) material's GROUND LOOK uniforms for `the_plan` (plan()), the merged
## looks of its slots (`looks`, in slot order), each slot's light reference (`refs`, linear) and
## bake texture (`textures`, null before the first bake), over `rect`. OFF when no slot is
## bound. Pure.
static func ground_tables(
	the_plan: Dictionary, looks: Array, refs: Array, textures: Array, rect: Vector4
) -> Dictionary:
	if (the_plan.get("biomes", PackedStringArray()) as PackedStringArray).is_empty():
		return OFF.duplicate()
	var light := PackedVector4Array()
	var refs_out := PackedVector4Array()
	var brush := PackedVector4Array()
	var shape := PackedVector4Array()
	var rim := PackedVector4Array()
	var rim_more := PackedVector4Array()
	var rim_color := PackedVector4Array()
	var tint := PackedVector4Array()
	for s in SLOTS:
		var look: Dictionary = looks[s] if s < looks.size() else {}
		if look.is_empty():
			# An unused slot: no row points at it.
			light.append(Vector4.ZERO)
			refs_out.append(Vector4.ZERO)
			brush.append(Vector4.ZERO)
			shape.append(Vector4(1.0, 0.0, 0.0, 1.0))
			rim.append(Vector4.ZERO)
			rim_more.append(Vector4.ZERO)
			rim_color.append(Vector4.ZERO)
			tint.append(Vector4(1.0, 1.0, 1.0, 0.0))
			continue
		var ref := as_r20_spatial(refs[s] if s < refs.size() else NO_REF)
		var z: Dictionary = look.zones
		var lt: Dictionary = look.light
		var b: Dictionary = look.brush
		var a: Dictionary = look.accent_shape
		var r: Dictionary = look.rim
		light.append(Vector4(z.strength, lt.strength, lt.knee, lt.cap))
		refs_out.append(Vector4(ref.x, ref.y, ref.z, lt.sat_cap))
		brush.append(Vector4(b.contrast, b.hue, b.key, b.mean))
		shape.append(Vector4(a.stretch, a.stretch_angle, a["break"], a.edge_scale))
		rim.append(Vector4(r.accent_rim_m, r.path_rim_m, r.strength, r.wobble))
		rim_more.append(Vector4(r.gap, r.path_blend_width, r.accent_core_m, r.core_dark))
		rim_color.append(_vec4(r.color_linear))
		var t: Array = r.accent_tint
		var tint_gpu := as_r20_spatial(Color(float(t[0]), float(t[1]), float(t[2])))
		tint.append(Vector4(tint_gpu.x, tint_gpu.y, tint_gpu.z, 0.0))
	var out := {
		"look_present": 1,
		"look_row_slots": the_plan.row_slots,
		"look_layer_slots": the_plan.layer_slots,
		"look_rim_layers": the_plan.rim_layers,
		"look_rect": rect,
		"look_light": light,
		"look_ref": refs_out,
		"look_brush": brush,
		"look_shape": shape,
		"look_rim": rim,
		"look_rim_more": rim_more,
		"look_rim_color": rim_color,
		"look_accent_tint": tint,
	}
	for s in SLOTS:
		out["look_tex_%d" % s] = textures[s] if s < textures.size() else null
	return out


## The light reference of ground surface `surface` (linear): its palette albedo_mean_linear, else
## the mean of its albedo map's texels decoded from sRGB (sampled, as opaque_mean_linear). Cached.
static func ref_linear(surface: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var key := root.path_join(surface)
	if _refs.has(key):
		return _refs[key]
	var entry: Dictionary = PaletteLibrary.surfaces(root).get(surface, {})
	var mean: Variant = entry.get("albedo_mean_linear")
	var ref := NO_REF
	if mean is Array and (mean as Array).size() == 3:
		ref = Color(float(mean[0]), float(mean[1]), float(mean[2]))
	else:
		ref = _mean_linear(GroundPalette.load_texture(root, entry.get("albedo", "")), false)
	_refs[key] = ref
	return ref


## The mean linear colour of a grass texture's opaque texels (alpha over 0.5), the reference a
## tuft's luminance is measured against (zone_tuft_ref). NO_REF when there is none. Cached.
static func opaque_mean_linear(tex: Texture2D) -> Color:
	if tex == null:
		return NO_REF
	var key: Variant = tex.get_rid()
	if tex.resource_path != "":
		key = tex.resource_path
	if not _tuft_refs.has(key):
		_tuft_refs[key] = _mean_linear(tex, true)
	return _tuft_refs[key]


## The mean of `tex`'s texels decoded from sRGB, sampled every width / MEAN_SAMPLES texels; with
## `opaque` only those with alpha over 0.5.
static func _mean_linear(tex: Texture2D, opaque: bool) -> Color:
	if tex == null:
		return NO_REF
	var img := tex.get_image()
	if img == null or img.is_empty():
		return NO_REF
	if img.is_compressed():
		img.decompress()
	var step := maxi(1, img.get_width() / MEAN_SAMPLES)
	var sum := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if not opaque or c.a > 0.5:
				var lin := c.srgb_to_linear()
				sum += Vector3(lin.r, lin.g, lin.b)
				n += 1
	if n == 0:
		return NO_REF
	sum /= float(n)
	return Color(sum.x, sum.y, sum.z)


## Colour `c` as round 20's GPU got it on a spatial material. The probe set the ground's and the
## grass's light reference, the grass's tuft reference and the accent tint as a Color, and Godot
## converts a Color set on a spatial shader's plain vec3 from sRGB to linear (a canvas shader,
## the bake, takes it as is; measured 2026-10-15, ground ship card 3c: a Color of 0.2711, 0.3928,
## 0.0485 drew 88, 129, 14 on an unshaded quad, the same Vector3 178, 202, 78). The approved look
## was tuned on those converted values (grassland's brush mean, 3.2, is about its ground's
## luminance over the converted reference, 3.3; over the raw one it is about 1), so those four
## take the same conversion here; the bake's values and the rim colour (set as a plain vector)
## reach the GPU raw.
static func as_r20_spatial(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	return Vector3(lin.r, lin.g, lin.b)


## A look value as the shader takes it: a three-number array as a Vector3 (raw, linear).
static func _typed(value: Variant) -> Variant:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return float(value) if value is int else value


static func _vec4(rgb: Array) -> Vector4:
	return Vector4(float(rgb[0]), float(rgb[1]), float(rgb[2]), 0.0)


static func _filled(count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	out.fill(-1)
	return out
