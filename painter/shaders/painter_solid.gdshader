shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted solid (a stand-in for a still scatter asset's own material under the Painted look)
 * ========================================================================================
 *
 * The selector light (painter_selector.gdshaderinc) on scatter that does not sway: rocks,
 * logs, stumps, litter. Such an asset keeps its imported material in Classic, so it has no wind
 * uniforms; its arrival drops it in through its instance transforms (ScatterArrival), which
 * any material follows. `cutout` keeps a cut-out asset's silhouette from its texture's alpha.
 *
 * MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd).
 */

// The selector's solid light: the form's shade, its planes (solid_form()) and its shade's two values.
#define SELECTOR_SOLID
#include "res://painter/shaders/painter_selector.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, hint_default_white;
uniform bool cutout = false;
uniform float alpha_scissor = 0.5;

varying vec3 v_wp;
varying vec3 v_wn;
varying flat vec3 v_o;
varying float v_h;
varying flat float v_scale;
// The rock's own turn of its plane lattice (cosine, sine): solid_form().
varying flat vec2 v_turn;

void vertex() {
	v_h = VERTEX.y / max(selector_height, 0.01);
	VERTEX *= selector_keep(MODEL_MATRIX[3].xyz, IN_SHADOW_PASS);
	v_o = MODEL_MATRIX[3].xyz;
	v_scale = length(MODEL_MATRIX[1].xyz);
	float turn = p_hash(floor(v_o * 10.0) + vec3(5.0, 9.0, 2.0)) * 6.2832;
	v_turn = vec2(cos(turn), sin(turn));
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	if (cutout) {
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	}
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n;
	float variant;
	float mul;
	float wob;
	float petal;
	float snow;
	selector_fragment(v_wp, v_wn, v_o, v_scale, v_h, tex, n, variant, mul, wob, petal, snow);
	vec3 plane;
	n = solid_form(v_wp, v_wn, v_o, v_scale, v_turn, plane, variant);
	// The snow law on the form's normal (painter_selector's snow_on), as a bush's and a roof's.
	snow = frost > 0.0 ? snow_on(n, v_wp) : 0.0;
	f_n = n;
	f_plane = plane;
	f_variant = variant;
	f_mul = mul;
	f_wob = wob;
	f_accent = petal;
	f_centre = 0.0;
	f_frost = snow;
	// A solid does not take its own shadow from the map. A rock's faces turned near edge-on to the
	// sun are where a shadow map stripes and stipples, and a low-poly rock's own shadow on itself
	// is polygons that fight the shade its form already has (cards painter-ground-artifacts,
	// painter-ground-rocks). So it asks the map from a shell around itself: each point moved out
	// from the rock's middle (never downward, so the shell stays over level ground) by a share of
	// its size. Out there the sun's ray clears the rock on every side but its far back, which is
	// in the form's shade already; what a tree, a wall or the terrain throws lands on the shell as
	// it would on the rock, in one smooth edge across its faces. The caster is untouched, so the
	// rock's shadow on the ground starts at its foot.
	vec3 half_m = max(selector_extent * v_scale, vec3(0.02));
	vec3 out_dir = v_wp - (v_o + vec3(0.0, SOLID_MID * selector_height * v_scale, 0.0));
	out_dir.y = max(out_dir.y, 0.4 * length(out_dir.xz));
	float shell = min(SOLID_SHELL * max(half_m.x, max(half_m.y, half_m.z)), SOLID_SHELL_MAX);
	LIGHT_VERTEX = (VIEW_MATRIX * vec4(v_wp + normalize(out_dir + vec3(0.0, 1e-4, 0.0)) * shell, 1.0)).xyz;
}
