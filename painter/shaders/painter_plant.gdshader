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
 * uniform keeps its value. A plain alpha-scissor cutout, and the foliage AA swap leaves it alone
 * (WindFoliage.META_STAND_IN); a wide grass tuft's card is cut into round dabs instead of its
 * texture's teeth, with winter snow on the dabs and over its foot (painter_selector's tuft_dab,
 * painter-plants-fix3). Known fault (painter-a1c): in the eye view (4x MSAA, where the
 * Classic foliage swaps to its alpha-to-coverage twin) thin grass blades alias into fine broken
 * light lines where they cross a dark bush; an alpha-to-coverage twin swapped like the Classic's
 * is the planned fix.
 *
 * MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd).
 */

#define FOLIAGE_GROUND_LEAN
#include "res://shaders/wind_foliage_include.gdshaderinc"
#include "res://shaders/wind_foliage_grow.gdshaderinc"
#include "res://painter/shaders/painter_selector.gdshaderinc"

varying vec3 v_wp;
varying vec3 v_wn;
// The instance's origin and scale (xyz, w).
varying flat vec4 v_os;
// A tuft card's point (painter_selector's tuft_layout: xy, z the tuft's seed) and w the height
// fraction; then the card's dabs, constant over it, so read flat. Packed (painter-plants-fix4): the
// shader is near Godot's 32 varying slots, and each slot is set up per triangle on a field of
// small tuft cards.
varying vec4 v_tp;
varying flat vec4 v_dx;
varying flat vec4 v_dy;
varying flat vec4 v_di;

void vertex() {
	local_vertex_y = VERTEX.y;
	float h = VERTEX.y / max(selector_height, 0.01);
	vec3 tp = vec3(0.0);
	vec4 dx = vec4(0.0);
	vec4 dy = vec4(0.0);
	vec4 di = vec4(1.0);
	if (kind == 1 || kind == 3) {
		tuft_layout(VERTEX, UV, MODEL_MATRIX[3].xyz, tp, dx, dy, di);
	}
	v_tp = vec4(tp, h);
	v_dx = dx;
	v_dy = dy;
	v_di = di;
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	VERTEX *= grow_scale(MODEL_MATRIX[3].xyz) * selector_keep(MODEL_MATRIX[3].xyz, IN_SHADOW_PASS);
	v_os = vec4(MODEL_MATRIX[3].xyz, length(MODEL_MATRIX[1].xyz));
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += shadow_caster_offset(MODEL_MATRIX, INV_VIEW_MATRIX, IN_SHADOW_PASS);
}

void fragment() {
	vec3 v_o = v_os.xyz;
	float v_scale = v_os.w;
	float v_h = v_tp.w;
	if (kind == 4) {
		// A bush's outline breaks between its lobes (painter_selector's bush_cut), in the sun's pass
		// too, so its shadow's edge is as round as its outline.
		vec3 eye = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - v_wp)
			: normalize(INV_VIEW_MATRIX[2].xyz);
		if (bush_cut(v_wp, v_o, v_scale, eye)) {
			discard;
		}
	}
	// A tuft's dabs, snow cap and bury line (painter_selector's tuft_dab): a grass card's cut is its
	// dabs, a flower keeps its texture's.
	vec4 dab = vec4(1.0, 0.5, 0.0, 0.0);
	if (kind == 1 || kind == 3) {
		dab = tuft_dab(v_tp.xyz, v_dx, v_dy, v_di);
		if (dab.x < 0.5) {
			discard;
		}
	}
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
	ALPHA = dab.x > 1.5 ? 1.0 : pbr_alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	vec3 n;
	float variant;
	float mul;
	float wob;
	float petal;
	float snow;
	selector_fragment(v_wp, v_wn, v_o, v_scale, v_h, texture(albedo_texture, UV), n, variant, mul,
		wob, petal, snow);
	if (kind == 1 || kind == 3) {
		if (dab.x > 1.5) {
			// Each dab its own value and variant (russet or straw in winter), darker at its foot
			// where it overlaps the dab below, so the mound reads as laid dabs.
			variant = mix(variant, dab.y, 0.6);
			mul *= mix(1.0 - 0.7 * TUFT_STEP, 1.0 + 0.7 * TUFT_STEP, dab.y)
				* mix(0.84, 1.04, smoothstep(-0.9, 0.6, dab.z));
		}
		snow = dab.w;
	}
	f_n = n;
	f_variant = variant;
	f_mul = mul;
	f_wob = wob;
	f_accent = petal;
	f_frost = snow;
	if (kind == 1 || kind == 3) {
		// Ground cover takes the cast shade of the ground at its foot: light and shadow are read
		// straight below the fragment, a little over the tuft's root, with the ground's up normal,
		// so a bush's or a tree's shadow covers the grass in it with the same shape it lays on the
		// ground (read at the blade, a tuft whose foot was in the shadow stood lit in it; painter-
		// a1c eye view). Grass casts no shadow, so no shadow moves off its caster.
		LIGHT_VERTEX = (VIEW_MATRIX * vec4(v_wp.x, v_o.y + 0.1, v_wp.z, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
}
