// FIRE: the burn and its fire on the ground of persistent ground fire (design:
// docs/plans/2026-10-11-fire-features/design.md section 4; the production port: production.md).
// Included by authored_ground.gdshaderinc for the map's ground only (the skirt never burns):
// fragment() calls fire_glow(world_xz, TIME, albedo), which turns the albedo to char where the
// ground burns and returns the fire for EMISSION. Everything of it that does not change with time
// is worked out once by FireNoiseBake into the sim bake (fire_ground_bake.gdshader, calling
// fire_sim_bake below), two RGBA8 tiles side by side bound by FireLook.bind_glow (fire_present 0
// skips everything): the albedo terms (the char's weight, the dried band's mix, the scorch, the
// char's tone) and the glow terms (the glow before its breathing, and the breathing's phase).
//
// The model (look card F4a and the reference fit's round 6, card ref-fit-sim-r6: dark char
// between the fires and a soft pool of light under each, the flames always the brightest thing in
// the frame):
//   - The pools: under each fire the ground glows in a soft round pool of light from the feet's
//     pools raster (FireField: a kernel about twice a fire's width), its low tail cut so every
//     pool ends in dark ground rather than washing the gaps orange. Inside a pool a few faint
//     lobes and cracks of the crust's glow show, darkened by coal lumps; one ramp, deep red
//     through orange to a warm orange-gold (FIRE_GOLD) below the flames' outer band.
//   - No ember cores: round 5's ember cores, even faint, drew red stripes between the fires and
//     lit the gaps the user asked to keep dark (round 6 dropped them).
//   - The char: the albedo is replaced (a path or a light soil does not show through) by a painted
//     value field in world space, brown-black drifting to a warmer brown, a few bold near-black
//     shapes, and a little soft grey ash at the outskirts and between the clumps, stored as one
//     tone on the path deep, char, warm, ash (fire_char_tone). Matte, its normals straight up
//     (the including shader applies FIRE_FLATTEN), so no facet of the low-poly ground draws an
//     edge on it. The heat for the char is the mask widened over a cool valley, so a narrow gap
//     between two strokes is char, not a straight seam of the ground beneath.
//   - The outline: the mask is read through a bold warp, so a straight stroke's edge swells into
//     lobes, and eroded by a broad noise; outside it the grass is dried and browned in a band
//     whose width wanders (none in places, a few metres in others).
//   - The breathing: one slow sine (about 0.3 Hz, its phase by place) multiplies the whole glow.
// Every pattern noise is the fire's value noise on lattices turned off the map's axes (the game
// camera sees those axes as its diagonals) and warped by a broad noise, so no outline, band or
// cell lines up with anything. Colours are linear emission, and zero outside the pools: the filmic
// tonemap (white 1.0) lifts low emission about six times, so a dim fringe spread wide reads as a
// red or plum wash.
//
// Cost (card ground-cost, spike-timing.md "Run 5"; docs/PERFORMANCE.md "Fire (F4)"): one fetch
// where nothing burns or dries (the albedo terms are 0 there), two where it burns, and no noise
// or hashing per pixel.

#include "res://shaders/fire_glow_noise.gdshaderinc"

uniform int fire_present = 0;
// The sim bake (two tiles side by side: the albedo terms, then the glow terms) and one tile's
// frame (the map-frame XZ of its corner, its size in metres).
uniform sampler2D fire_sim_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 fire_sim_rect = vec4(0.0, 0.0, 1.0, 1.0);

// The char's painted field (linear albedo): brown-black, a warmer brown drift, the bold dark
// shapes, and the ash.
const vec3 FIRE_CHAR = vec3(0.02, 0.013, 0.009);
const vec3 FIRE_CHAR_WARM = vec3(0.045, 0.027, 0.015);
const vec3 FIRE_CHAR_DEEP = vec3(0.005, 0.004, 0.0035);
const vec3 FIRE_ASH = vec3(0.11, 0.105, 0.1);
// How far char's normals lean to straight up (the including shader applies it): all the way,
// a facet of the ground's normals drew a hard straight edge on the char under a low sun.
const float FIRE_FLATTEN = 1.0;
// Just outside the char: browned (a multiplier) next to it, and dried grass past that (an
// albedo scaled by the ground's own brightness, mixed over it so the ground's texture shows).
const vec3 FIRE_SCORCH = vec3(0.42, 0.3, 0.2);
const vec3 FIRE_DRY = vec3(0.16, 0.105, 0.04);
const float FIRE_DRY_MIX = 0.7;
// Over what burn the char fades in at its edge.
const float FIRE_EDGE_SOFT = 0.1;
// How much of the ash shows between the clumps (round 4: the fewer, bigger fires left most of
// the char pale grey, which with the pools' tail read as a pink-grey haze by day).
const float FIRE_ASH_SHARE = 0.25;
// The ground's fire ramp, from a glow's fringe to its hottest (linear emission); the gold stays
// below the flames' outer band (fire_flames.gdshader) in brightness.
const vec3 FIRE_RED = vec3(0.3, 0.022, 0.003);
const vec3 FIRE_HEART = vec3(0.62, 0.085, 0.005);
const vec3 FIRE_GOLD = vec3(0.82, 0.21, 0.014);
// The lobes round the feet: how far their noise sways their outline (pool units), and the reach
// over which they fade in (the noise's scale is GLOW_LOBE_M).
const float FIRE_LOBE_SWAY = 0.9;
const vec2 FIRE_LOBE_EDGE = vec2(0.32, 0.62);
// The cracks' half width (noise units; their scale is GLOW_CRACK_M).
const float FIRE_CRACK_W = 0.035;
// How much the coal lumps (crust plates) darken the glow (their scale is GLOW_LUMP_M).
const float FIRE_LUMP_DARK = 0.7;
// The breathing's rate (radians a second: about 0.3 Hz).
const float FIRE_BREATHE = 1.9;
// The pool of light under a fire at full pool (linear emission).
const vec3 FIRE_POOL_LIGHT = vec3(0.75, 0.21, 0.026);
// The sim bake's glow is stored as sqrt(glow / this) (fine steps in the pools' dim tails, which
// the filmic tonemap lifts about six times).
const float FIRE_SIM_GLOW_MAX = 2.0;
const vec3 FIRE_LUMA = vec3(0.2126, 0.7152, 0.0722);

// The ground's fire at temperature `t` (0 the crust, 1 the hottest): deep red, orange, a warm
// orange-gold, its brightness rising out of the crust over a short fringe.
vec3 fire_ramp(float t) {
	vec3 c = mix(FIRE_RED, FIRE_HEART, smoothstep(0.2, 0.55, t));
	c = mix(c, FIRE_GOLD, smoothstep(0.65, 1.0, t));
	return c * smoothstep(0.0, 0.25, t);
}

// The char's colour as one tone (0..1) on the path deep, char, warm, ash, by luminance (the
// sim bake stores the tone; a dark blotch under ash comes back a little browner).
float fire_char_tone(vec3 colour) {
	float l = dot(colour, FIRE_LUMA);
	float l_deep = dot(FIRE_CHAR_DEEP, FIRE_LUMA);
	float l_char = dot(FIRE_CHAR, FIRE_LUMA);
	float l_warm = dot(FIRE_CHAR_WARM, FIRE_LUMA);
	float l_ash = dot(FIRE_ASH, FIRE_LUMA);
	if (l < l_char) {
		return clamp((l - l_deep) / (l_char - l_deep), 0.0, 1.0) / 3.0;
	}
	if (l < l_warm) {
		return (1.0 + (l - l_char) / (l_warm - l_char)) / 3.0;
	}
	return (2.0 + clamp((l - l_warm) / (l_ash - l_warm), 0.0, 1.0)) / 3.0;
}

// The char's colour at tone `tone` (fire_char_tone's inverse along the path).
vec3 fire_char_of(float tone) {
	float s = tone * 3.0;
	vec3 low = mix(FIRE_CHAR_DEEP, FIRE_CHAR, clamp(s, 0.0, 1.0));
	vec3 mid = mix(low, FIRE_CHAR_WARM, clamp(s - 1.0, 0.0, 1.0));
	return mix(mid, FIRE_ASH, clamp(s - 2.0, 0.0, 1.0));
}

// The ground's fire worked out once in the sim bake (fire_ground_bake.gdshader) from its static
// fields `a`, `b`, `c` (the burn, the dried band, the char's colour weights, the ash, the pools,
// the crowding, the cracks' strength, the breathing's phase) and the fine fields `fine`
// (glow_fine_fields: the tufts, lobes, coal lumps and cracks), so the ground reads it with two
// fetches and no noise.
// `albedo_terms`: the char's weight (burnt), the dried band's mix, the scorch, the char's tone.
// `glow_terms`: sqrt(glow / FIRE_SIM_GLOW_MAX) before the breathing, and the breathing's phase.
void fire_sim_bake(vec4 a, vec4 b, vec4 c, vec4 fine, out vec4 albedo_terms, out vec4 glow_terms) {
	float burn = glow_unpack(a.x, GLOW_BURN_RANGE);
	float burnt = smoothstep(0.0, FIRE_EDGE_SOFT, burn);
	// Outside the char: dried grass in a band whose width wanders, its edge ragged, browned
	// further next to the char.
	float tuft = fine.x;
	float dry_arg = glow_unpack(a.y, GLOW_DRY_RANGE);
	float dry = smoothstep(0.01, 0.1, dry_arg + (tuft - 0.5) * 0.05) * (1.0 - burnt);
	float dry_mix = dry * FIRE_DRY_MIX * (0.75 + 0.5 * (tuft - 0.5));
	float scorch = smoothstep(-0.1 - 0.12 * a.z, 0.0, burn + (tuft - 0.5) * 0.06);
	// The char: brown-black drifting to a warmer brown, a few bold near-black shapes, a little
	// soft grey ash where the flames' heat is low.
	float blotch = smoothstep(0.58, 0.7, b.y);
	vec3 char_colour = mix(FIRE_CHAR, FIRE_CHAR_WARM, b.x);
	char_colour = mix(char_colour, FIRE_CHAR_DEEP, blotch * 0.9);
	float ash = smoothstep(0.0, 1.0, glow_unpack(b.z, GLOW_ASH_RANGE)) * b.w * FIRE_ASH_SHARE;
	char_colour = mix(char_colour, FIRE_ASH, ash * 0.85);
	albedo_terms = vec4(burnt, dry_mix, scorch, fire_char_tone(char_colour));
	glow_terms = vec4(0.0);
	if (burnt <= 0.0) {
		return;
	}
	// The crust's glow: lobes round the flames' feet, wider and hotter where the summed heat is
	// high, their outline swayed by the noise, less right at a foot; coal lumps darken them and
	// cracks run between. Both keep to the inner pools and stay faint.
	float pool = c.x;
	float crowd = c.y;
	float lobe_n = fine.y;
	float lobe_at = pool * 1.1 + crowd * 0.5 + (lobe_n - 0.5) * FIRE_LOBE_SWAY * (1.0 - 0.6 * pool);
	float lobe = smoothstep(FIRE_LOBE_EDGE.x, FIRE_LOBE_EDGE.y, lobe_at) * burnt;
	float lobe_t = lobe * (0.3 + 0.4 * smoothstep(0.35, 1.0, pool) + 0.35 * crowd);
	lobe_t *= 0.8 + 0.4 * lobe_n;
	float lump = smoothstep(0.5, 0.66, fine.z);
	lobe_t *= 1.0 - FIRE_LUMP_DARK * lump * (1.0 - 0.4 * crowd);
	float crack_d = abs(fine.w - 0.5) / GLOW_CRACK_GAIN;
	float crack_t = (1.0 - smoothstep(FIRE_CRACK_W * 0.4, FIRE_CRACK_W, crack_d)) * c.z * burnt;
	lobe_t *= smoothstep(0.3, 0.65, pool) * 0.15;
	crack_t *= smoothstep(0.08, 0.35, pool) * 0.5;
	vec3 glow = fire_ramp(max(lobe_t, crack_t));
	// The pool of light, its low tail cut so each pool ends in dark ground.
	glow += FIRE_POOL_LIGHT * pow(smoothstep(0.15, 1.0, pool), 1.3) * 1.3;
	glow_terms = vec4(sqrt(clamp(glow / FIRE_SIM_GLOW_MAX, 0.0, 1.0)), c.w);
}

// The fire at map-frame XZ `at` at time `clock`, read from the sim bake: turns `albedo` to char
// where it burns, sets `charred` to how much (0..1, for the matte finish) and returns the fire
// (emission). One fetch where nothing burns or dries, two where it burns; the dried band and the
// scorch go on the ground's own albedo, then the char's tone, then the glow times the breathing.
vec3 fire_glow(vec2 at, float clock, inout vec3 albedo, out float charred) {
	charred = 0.0;
	if (fire_present == 0) {
		return vec3(0.0);
	}
	// The albedo tile here, kept half a texel inside it (off the tiles' seam).
	vec2 st = (at - fire_sim_rect.xy) / fire_sim_rect.zw;
	float edge = 1.0 / float(textureSize(fire_sim_map, 0).x);
	st.x = clamp(st.x, edge, 1.0 - edge) * 0.5;
	vec4 terms = texture(fire_sim_map, st);
	if (terms.x + terms.y + terms.z <= 0.0) {
		return vec3(0.0);
	}
	vec3 dried = FIRE_DRY * clamp(dot(albedo, FIRE_LUMA) / 0.1, 0.6, 1.3);
	albedo = mix(albedo, dried, terms.y);
	albedo *= mix(vec3(1.0), FIRE_SCORCH, terms.z);
	if (terms.x <= 0.0) {
		return vec3(0.0);
	}
	albedo = mix(albedo, fire_char_of(terms.w), terms.x);
	charred = terms.x;
	vec4 glow = texture(fire_sim_map, st + vec2(0.5, 0.0));
	// One rate everywhere, the phase by place (a rate that varied by place wound the phase up
	// into fine ripples as the clock ran on).
	float breathe = 0.86 + 0.14 * sin(clock * FIRE_BREATHE + glow.w * 12.0);
	return glow.rgb * glow.rgb * (FIRE_SIM_GLOW_MAX * breathe);
}
