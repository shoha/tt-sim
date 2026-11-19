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
 * painter-plants-fix3); a flower's bloom cards are one dab each in the flower's own accent
 * (bloom_dab; painter-flowers), and a bloom mound's are turned to the orbit view and drawn together
 * into one carpet of a few hues (bloom_grown; painter-flower-carpet). Known fault (painter-a1c): in the eye view (4x MSAA, where the
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
// The height fraction, then a tuft card's atlas layer and the tuft's seed (painter_selector's
// tuft_card: constant over a card).
varying vec3 v_hk;
// 1 on the layer of hand-placed props (PainterSurfaces marks it): never thinned, so what an author
// places stands under Painted (painter-flowers: a placed bell cluster and a carpet were thinned
// away at the eye). Ground cover still casts nothing.
instance uniform float painter_placed = 0.0;
// A bloom card's accent and value (bloom_grown: a carpet's cards lie in a few hues, darker low on
// the mound; any other's the surface's accent at 1).
varying flat vec2 v_card;

void vertex() {
	local_vertex_y = VERTEX.y;
	vec3 hk = vec3(VERTEX.y / max(selector_height, 0.01), 0.0, 0.0);
	if (kind == 1 || kind == 3) {
		hk.yz = tuft_card(VERTEX, UV, MODEL_MATRIX[3].xyz);
	}
	v_hk = hk;
	vec2 card = vec2(float(petal_role), 1.0);
	if (kind == 3 && petal_dab && bloom_grow && !IN_SHADOW_PASS) {
		// A bloom mound's card turned to the orbit view and drawn into one carpet, in its own hue
		// (painter_selector's bloom_grown).
		VERTEX = bloom_grown(
			VERTEX, UV, VERTEX_ID, MODEL_MATRIX, INV_VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE,
			card
		);
	}
	v_card = card;
	VERTEX += wind_sway_vertex_offset(VERTEX, COLOR, MODEL_MATRIX, TIME);
	float kept = selector_keep(MODEL_MATRIX[3].xyz, IN_SHADOW_PASS);
	if (painter_placed > 0.5 && !IN_SHADOW_PASS) {
		kept = 1.0;
	}
	VERTEX *= grow_scale(MODEL_MATRIX[3].xyz) * kept;
	v_os = vec4(MODEL_MATRIX[3].xyz, length(MODEL_MATRIX[1].xyz));
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += shadow_caster_offset(MODEL_MATRIX, INV_VIEW_MATRIX, IN_SHADOW_PASS);
}

void fragment() {
	vec3 v_o = v_os.xyz;
	float v_scale = v_os.w;
	float v_h = v_hk.x;
	if (kind == 4) {
		// A bush's outline breaks between its lobes (painter_selector's bush_cut), in the sun's pass
		// too, so its shadow's edge is as round as its outline.
		vec3 eye = PROJECTION_MATRIX[3][3] == 0.0 ? normalize(INV_VIEW_MATRIX[3].xyz - v_wp)
			: normalize(INV_VIEW_MATRIX[2].xyz);
		if (bush_cut(v_wp, v_o, v_scale, eye)) {
			discard;
		}
	}
	// A tuft's dabs, snow cap and bury line (painter_selector's tuft_dab): a wide grass card's cut is
	// its dabs, read from the atlas in place of its texture (never fetched: a card is one fetch, as
	// the texture's cut was); a flower or a narrow tuft keeps its texture's.
	vec4 dab = vec4(1.0, 0.5, 0.0, 0.0);
	if (kind == 1 || kind == 3) {
		dab = tuft_dab(UV, v_hk.yz);
		if (dab.x < 0.5) {
			discard;
		}
	}
	// A bloom card is one dab (painter_selector's bloom_dab), cut in place of its texture (never
	// fetched).
	bool bloom = kind == 3 && petal_dab && petal_role >= 0;
	vec2 blot = vec2(1.0, 0.0);
	if (bloom) {
		blot = bloom_dab(UV, fract(v_hk.y * 0.37 + v_hk.z));
		if (blot.x < 0.5) {
			discard;
		}
	}
	NORMAL = two_sided_foliage_normal(NORMAL, FRONT_FACING);
	float alpha = 1.0;
	vec4 tex = vec4(0.0, 1.0, 0.0, 1.0);
	if (!tuft_wide() && !bloom) {
		vec3 pbr_albedo;
		float pbr_ao;
		float pbr_roughness;
		float pbr_metallic;
		vec3 pbr_normal_map;
		// The cutout and the fades (the ground-cover form: no canopy fade inputs, as ground cover).
		apply_wind_foliage_pbr(UV, INV_VIEW_MATRIX, NORMAL, VERTEX, VERTEX, VIEW_MATRIX,
			PROJECTION_MATRIX, FRAGCOORD.xy, VIEWPORT_SIZE, local_vertex_y, vec2(0.0), pbr_albedo,
			alpha, pbr_ao, pbr_roughness, pbr_metallic, pbr_normal_map);
		tex = texture(albedo_texture, UV);
	}
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
	vec3 n;
	float variant;
	float mul;
	float wob;
	float petal;
	float snow;
	vec3 wn = v_wn;
	if (kind == 5) {
		// A wall's leaves (baked ivy): the card's own face turned to the viewer, not its foliage
		// normals, so the leaf dabs lie on the wall (painter_selector's ivy_dab).
		vec3 face = normalize(cross(dFdx(v_wp), dFdy(v_wp)));
		vec3 to_eye = PROJECTION_MATRIX[3][3] == 0.0 ? INV_VIEW_MATRIX[3].xyz - v_wp
			: INV_VIEW_MATRIX[2].xyz;
		wn = dot(face, to_eye) < 0.0 ? -face : face;
	}
	selector_fragment(v_wp, wn, v_o, v_scale, v_h, tex, n, variant, mul, wob, petal, snow);
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
	if (bloom) {
		// A dab turns from a darker foot to a lit top, so a head of them reads as a rounded form.
		mul *= mix(0.84, 1.04, smoothstep(-0.9, 0.6, blot.y)) * v_card.y;
		petal = v_card.x;
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
