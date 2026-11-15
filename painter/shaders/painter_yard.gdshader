shader_type spatial;
render_mode cull_disabled, specular_disabled, ambient_light_disabled;

/*
 * Painted yard planting (cards painter-buildings-fix2 and -fix3)
 * ==============================================================
 *
 * A building's yard props (StructureDressing "props": shrubs, flower beds, tufts, boulders,
 * stepping stones, planters, a woodpile; one vertex-coloured soup of low-poly pieces) in the
 * painted look, instead of Classic's saturated vertex colours. Each vertex takes one of four sheet
 * ramps by its Classic colour (yard_tone: a green the leaf, a grey the stone, a dull brown the
 * timber, any other paint the rose flowers), so winter and grimdark tone it as they tone the trees.
 *
 * The crown hand on a blob (a shrub, a planter's dome, a boulder: a 20-face icosahedron whose
 * normals are its ellipsoid's, so the interpolated normal points along the radial direction):
 *   outline  where the surface turns from the eye past `rim` it is cut away, deeper on a lobe's
 *            seam (a ridged noise), so the polygon's straight outline becomes a round, scalloped
 *            one (card painter-buildings-fix3: the props read as faceted gems). The same cut runs
 *            in the shadow pass, from the light, so the shadow is round too;
 *   light    the light's three steps on the smooth radial normal, turned a little by a slow noise
 *            and pulled darker along the seams, so the steps break into a few rounded dabs;
 *   snow     in winter (`snow`, the sheet's roof-snow) what faces up wears the roof snow's ramp:
 *            a blob's top in a cap with a scalloped edge, a stone, a lid or a step whole, a tuft's
 *            blades in patches; the snow takes the light's steps as the roofs' blanket does.
 * A lighter or darker variant lies in broad patches. Flat pieces (tufts, stepping stones, slabs,
 * blooms) keep their outline. No per-frame work: everything is the fragment's own position.
 *
 * MANAGED BY: PainterBuildings (painter/painter_buildings.gd, kind "dressing_props").
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_structure_common.gdshaderinc"

uniform vec3 ramps[24];
uniform float snow = 0.0;
uniform vec3 snow_ramp[3];
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float cast_amount = 0.94;
// How far the lobe noise turns a blob's normal, and its size (1/m).
uniform float lobe = 0.5;
uniform float lobe_freq = 3.2;
// The scalloped outline: a blob's surface facing the eye less than `rim` (0..1) is cut away, up to
// `scallop` more on a lobe's seam; seams about `scallop_freq` per metre. `seam_dark` how much
// darker the light reads along a seam.
uniform float rim = 0.3;
uniform float scallop = 0.32;
uniform float scallop_freq = 4.0;
uniform float seam_dark = 0.7;

varying vec3 v_wp;
varying vec3 v_wn;
// The ramp (0 leaf, 1 stone, 2 timber, 3 flowers), plus 4 for a flat piece (every normal upright)
// and 8 for a bloom (its paint's alpha under 0.75, StructureDressingShapes.soup_dot).
varying flat int v_kind;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

// The ramp a yard paint (linear) takes: 0 leaf, 1 stone, 2 timber, 3 flowers.
int yard_tone(vec3 c) {
	vec2 ab = paint_ab(c);
	float chroma = length(ab);
	float hue = mod(degrees(atan(ab.y, ab.x)) + 360.0, 360.0);
	if (chroma < 0.035) {
		return 1;
	}
	if (hue >= 105.0 && hue < 200.0) {
		return 0;
	}
	if (hue >= 40.0 && hue < 105.0 && chroma < 0.12) {
		return 2;
	}
	return 3;
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	// Classic stores the paint as sRGB (vertex_color_is_srgb). A tuft's blade, a stepping stone or
	// a lid carries upright normals throughout; a blob's are its ellipsoid's, never quite upright.
	v_kind = yard_tone(pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2))) + (NORMAL.y > 0.999 ? 4 : 0)
		+ (COLOR.a < 0.75 ? 8 : 0);
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	int tone = v_kind & 3;
	bool flat_piece = (v_kind & 4) != 0;
	// A bloom is a blob too, cut round with a lower rim (card painter-buildings-fix4: the blooms'
	// face normals drew small hard pyramids; their normals are radial now).
	bool bloom = (v_kind & 8) != 0;
	bool blob = !flat_piece && (tone < 2 || bloom);
	// Every piece's normals are authored outward (a blob's its ellipsoid's), but the soup's winding
	// is not one way round: flipping by FRONT_FACING turned a blob's lit top inward, so it never
	// took snow (card painter-buildings-fix3). The near side wins the depth test either way.
	vec3 n = normalize(v_wn);
	vec3 wp = v_wp;
	// 1 on the line between two lobes, 0 in a lobe's middle.
	float seam = 1.0 - abs(p_noise(wp * scallop_freq + 11.0) * 2.0 - 1.0);
	seam *= seam;
	if (blob) {
		vec3 eye = PROJECTION_MATRIX[3][3] == 0.0
			? normalize(INV_VIEW_MATRIX[3].xyz - wp)
			: normalize(INV_VIEW_MATRIX[2].xyz);
		if (dot(n, eye) < (bloom ? 0.3 + 0.2 * seam : rim + scallop * seam)) {
			discard;
		}
	}
	vec3 ln = n;
	if (!flat_piece) {
		vec3 q = wp * lobe_freq;
		vec3 turn = vec3(p_noise(q + 1.0), p_noise(q + 17.0), p_noise(q + 31.0)) - 0.5;
		ln = normalize(n + turn * lobe);
	}
	float variant = smoothstep(0.35, 0.65, p_noise(wp * 1.3 + 7.0));
	float cover = 0.0;
	if (snow > 0.0) {
		float up = n.y;
		if (flat_piece && tone == 0) {
			// A tuft's blades: whole blades under snow in patches.
			up = p_noise(wp * 2.2 + 4.0) * 1.4 - 0.1;
		}
		float cap = up - seam * 0.25 + (p_noise(wp * 4.0 + 9.0) - 0.5) * 0.3;
		// A bloom is small: snow takes most of it, leaving a red base (card painter-look-houses: bare
		// red cones in a snowed yard read as stray objects).
		cover = smoothstep(0.42, 0.48, cap + (bloom ? 0.4 : 0.0)) * clamp(snow * 2.2, 0.0, 1.0);
	}
	int base = tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	f_shd = mix(shd, snow_ramp[0], cover);
	f_mid = mix(mid, snow_ramp[1], cover);
	f_lit = mix(lit, snow_ramp[2], cover);
	if (blob && tone == 0) {
		// A shrub's lit side breaks into a few darker leaf dabs, as a crown's does (card
		// painter-buildings-fix4: a small lime shrub read as one glossy tone).
		float dab = smoothstep(0.52, 0.66, p_noise(wp * 6.5 + 3.0));
		// and its lit top sits nearer the crowns' greens than a lime highlight (card
		// painter-look-houses: a bright lime blob read as a stray object by the stone door).
		f_lit = mix(f_lit, f_mid, (dab * 0.5 + 0.3) * (1.0 - cover));
		f_mid = mix(f_mid, f_shd, dab * 0.3 * (1.0 - cover));
	}
	f_n = ln;
	f_wob = p_noise(wp * 5.0 + 5.0) - (blob ? seam * seam_dark * (1.0 - cover) : 0.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.4, 0.6, ATTENUATION + (f_wob - 0.5) * 0.3);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * 0.3;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.03, tone_lo + 0.03, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.03, tone_hi + 0.03, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
