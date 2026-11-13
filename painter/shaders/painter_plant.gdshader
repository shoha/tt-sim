shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted plant (a stand-in for a wind foliage material under the Painted look)
 * ===========================================================================
 *
 * The selector light (painter_selector.gdshaderinc) on a scatter plant that sways: bushes,
 * ferns, grass, flowers. Everything that moves or fades the plant is the wind foliage's own
 * code, included, never copied: the sway (wind_dir, wind_phase, wind_gust globals), the
 * arrival grow-in and shrink (wind_foliage_grow.gdshaderinc's instance uniforms), the canopy
 * and occlusion fades and the leaf shadow push (wind_foliage_include.gdshaderinc). PainterSurfaces
 * makes it as a duplicate of the plant's own wind material, so every wind, fade and cutout
 * uniform keeps its value. A plain alpha-scissor cutout: the strokes are opaque, so MSAA needs
 * no alpha-to-coverage twin, and the foliage AA swap leaves it alone (WindFoliage.META_STAND_IN).
 *
 * MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd).
 */

#define FOLIAGE_GROUND_LEAN
#include "res://shaders/wind_foliage_include.gdshaderinc"
#include "res://shaders/wind_foliage_grow.gdshaderinc"
#include "res://painter/shaders/painter_selector.gdshaderinc"

varying vec3 v_wp;
varying vec3 v_wn;
varying flat vec3 v_o;
varying float v_h;
varying flat float v_scale;

void vertex() {
	local_vertex_y = VERTEX.y;
	v_h = VERTEX.y / max(selector_height, 0.01);
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	VERTEX *= grow_scale(MODEL_MATRIX[3].xyz) * selector_keep(MODEL_MATRIX[3].xyz, IN_SHADOW_PASS);
	v_o = MODEL_MATRIX[3].xyz;
	v_scale = length(MODEL_MATRIX[1].xyz);
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += shadow_caster_offset(MODEL_MATRIX, INV_VIEW_MATRIX, IN_SHADOW_PASS);
}

void fragment() {
	NORMAL = two_sided_foliage_normal(NORMAL, FRONT_FACING);
	vec3 pbr_albedo;
	float pbr_alpha;
	float pbr_ao;
	float pbr_roughness;
	float pbr_metallic;
	vec3 pbr_normal_map;
	// The cutout and the fades (the ground-cover form: no canopy fade inputs, as ground cover).
	apply_wind_foliage_pbr(UV, INV_VIEW_MATRIX, NORMAL, VERTEX, VERTEX, VIEW_MATRIX,
		PROJECTION_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE, local_vertex_y, vec2(0.0), pbr_albedo,
		pbr_alpha, pbr_ao, pbr_roughness, pbr_metallic, pbr_normal_map);
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ALPHA = pbr_alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	vec3 n;
	float variant;
	float mul;
	float wob;
	float petal;
	selector_fragment(v_wp, v_wn, v_o, v_scale, v_h, texture(albedo_texture, UV), n, variant, mul,
		wob, petal);
	f_n = n;
	f_variant = variant;
	f_mul = mul;
	f_wob = wob;
	f_accent = petal;
}
