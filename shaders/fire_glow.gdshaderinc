// FIRE: the burn and ember glow of persistent ground fire, on the ground itself (design:
// docs/plans/2026-10-11-fire-features/design.md section 4, option C of the F3 probe). Included
// by authored_ground.gdshaderinc for the map's ground only (the skirt never burns): fragment()
// calls fire_glow(world_xz, TIME, albedo), which turns the albedo to char where the ground burns
// and returns the glow for EMISSION. The document's fire_mask is bound as an R8 texture on the
// sample grid (FireLook.bind_glow; fire_present 0 skips everything) and read through a cubic
// B-spline (texture_bspline), a blur of about a metre that keeps every threshold a smooth curve.
// Needs weight_uv, texture_bspline and layer_grid_step from the including shader.
//
// The model (look card F4a, round 2): glow is the exception on a dark ground.
//   - The char: the albedo is replaced (not tinted, so a path or a light soil does not show
//     through) by a near-black with soft drifts of warm-grey ash, more ash where it burns cooler.
//     Its edge is eroded by a broad noise, so the char fingers out into the grass unevenly,
//     with a browned scorch just outside it. The heat for the char is the mask widened over
//     FIRE_FILL_M: a narrow cool valley between two strokes (the brush's falloff) is char, not a
//     straight seam of the ground beneath.
//   - Ember beds: a few bold hot cores in a field of the fire's noise, fading softly outward
//     from gold through orange to a dim deep red and then the char, with dark lumps of coal
//     inside them; more of the ground and hotter cores the hotter it burns (gold only under
//     flames), and none at the burn's edge, so the colour fades before the char does. They
//     breathe slowly (about 0.3 Hz, the phase by place).
//   - Sparks on the ground: sparse yellow-white specks, only in a bed's hot core, pulsing.
// Every noise here is the fire's value noise on lattices turned off the map's axes (the game
// camera sees those axes as its diagonals) and warped by a broad noise, so no outline, band or
// cell lines up with anything. Colours are linear emission, picked for the filmic tonemap; the
// hottest go a little past 1 so the environment's glow gives them a soft halo.

#include "res://shaders/fire_noise.gdshaderinc"

uniform int fire_present = 0;
uniform sampler2D fire_mask_map : hint_default_black, filter_linear, repeat_disable;

// The bands' starts as mask values (FireField.EMBER_MIN and FLAME_MIN over 255).
const float FIRE_EMBER_T = 0.157;
const float FIRE_FLAME_T = 0.431;
// The char's albedo: a warm near-black, and the ash drifting over it (linear).
const vec3 FIRE_CHAR = vec3(0.02, 0.017, 0.016);
const vec3 FIRE_ASH = vec3(0.13, 0.11, 0.09);
// How far char's normals lean to straight up (the including shader applies it).
const float FIRE_FLATTEN = 0.7;
// What the ground just outside the char is multiplied by (scorched, browned).
const vec3 FIRE_SCORCH = vec3(0.45, 0.34, 0.24);
// How far (metres) the char's heat reaches across a cool valley, how far the mask's read
// wanders (metres), and how far a broad noise moves the burn's edge (in mask units) and over
// what the char fades in at it.
const float FIRE_FILL_M = 1.4;
const float FIRE_WANDER_M = 1.2;
const float FIRE_FEATHER = 0.5;
const float FIRE_EDGE_SOFT = 0.05;
// The ember beds' colours, from a bed's cool edge to its hot core.
const vec3 FIRE_RED = vec3(0.42, 0.03, 0.004);
const vec3 FIRE_HEART = vec3(1.0, 0.16, 0.008);
const vec3 FIRE_GOLD = vec3(1.35, 0.62, 0.1);
const vec3 FIRE_SPECK = vec3(1.6, 1.25, 0.6);
// The beds: their noise's scale (metres), the share of the ground they cover (a threshold) in
// the ember band and from the blaze, and how wide their soft falloff is.
const float FIRE_BED_M = 2.4;
const vec2 FIRE_BED_COVER = vec2(0.62, 0.54);
const float FIRE_BED_SOFT = 0.16;
// Coal lumps inside a bed: their scale (metres) and how much of a bed they darken.
const float FIRE_LUMP_M = 0.55;
const float FIRE_LUMP_DARK = 0.72;
// The breathing's rate (radians a second: about 0.3 Hz).
const float FIRE_BREATHE = 1.9;
// Specks: one cell this wide in FIRE_SPECK_SHARE carries one, only in a bed's core.
const float FIRE_SPECK_CELL_M = 0.34;
const float FIRE_SPECK_SHARE = 0.16;

// The fire's two octaves on lattices turned off the map's axes (by about 32 and 74 degrees).
float fire_turned(vec2 p) {
	vec2 a = vec2(0.848 * p.x - 0.53 * p.y, 0.53 * p.x + 0.848 * p.y);
	vec2 b = vec2(0.276 * p.x - 0.961 * p.y, 0.961 * p.x + 0.276 * p.y) * 2.17;
	return 0.68 * fire_noise(a) + 0.32 * fire_noise(b + vec2(7.1, 3.3));
}

// fire_turned warped by a broad noise (about three of its units across), for the big shapes.
float fire_warped(vec2 p) {
	vec2 w = vec2(fire_noise(p * 0.37 + vec2(3.1, 8.3)), fire_noise(p * 0.37 + vec2(9.7, 1.9)));
	return fire_turned(p + (w - 0.5) * 1.2);
}

// The fire at map-frame XZ `at` at time `clock`: turns `albedo` to char where it burns, sets
// `charred` to how much (0..1, for the matte finish) and returns the glow (emission).
vec3 fire_glow(vec2 at, float clock, inout vec3 albedo, out float charred) {
	charred = 0.0;
	if (fire_present == 0) {
		return vec3(0.0);
	}
	vec2 grid = vec2(textureSize(fire_mask_map, 0));
	vec2 uv = weight_uv(at, grid);
	// Four plain taps around the point, turned off the axes (FIRE_FILL_M away, past the wander).
	vec2 reach = FIRE_FILL_M / (layer_grid_step * grid);
	vec2 tap_a = vec2(0.848, 0.53) * reach;
	vec2 tap_b = vec2(-0.53, 0.848) * reach;
	float near = max(
		max(texture(fire_mask_map, uv + tap_a).r, texture(fire_mask_map, uv - tap_a).r),
		max(texture(fire_mask_map, uv + tap_b).r, texture(fire_mask_map, uv - tap_b).r)
	);
	// Most of a map does not burn.
	if (max(near, texture(fire_mask_map, uv).r) < 0.002) {
		return vec3(0.0);
	}
	// The burn wanders: the mask is read through a broad warp of up to FIRE_WANDER_M, so the
	// outline of a straight stroke fingers out unevenly and a straight valley bends.
	vec2 wander = vec2(fire_noise(at / 5.3 + vec2(4.1, 7.7)), fire_noise(at / 5.3 + vec2(8.9, 2.6)));
	uv = weight_uv(at + (wander - 0.5) * 2.0 * FIRE_WANDER_M, grid);
	// The mask widened across a cool valley: the taps' mean fills a dip narrower than about
	// twice FIRE_FILL_M and leaves an outer edge about where it was.
	float wide = 0.25 * (texture(fire_mask_map, uv + tap_a).r + texture(fire_mask_map, uv - tap_a).r
		+ texture(fire_mask_map, uv + tap_b).r + texture(fire_mask_map, uv - tap_b).r);
	float heat = max(texture_bspline(fire_mask_map, uv).r, wide);
	// The char's edge: eroded by a broad noise and a finer one, so it fingers out unevenly.
	float edge_noise = 0.65 * fire_warped(at / 4.2 + vec2(13.1, -4.7))
		+ 0.35 * fire_turned(at / 1.3 + vec2(2.7, 6.1));
	float burn = heat - FIRE_EMBER_T + (edge_noise - 0.5) * FIRE_FEATHER;
	float burnt = smoothstep(0.0, FIRE_EDGE_SOFT, burn);
	float scorch = smoothstep(-0.1, 0.0, burn);
	// How deep in the burn: the beds' colour fades out before the char does.
	float deep = smoothstep(0.04, 0.2, burn);
	float fire_t = clamp((heat - FIRE_EMBER_T) / (1.0 - FIRE_EMBER_T), 0.0, 1.0);
	float flaming = smoothstep(FIRE_FLAME_T - 0.06, FIRE_FLAME_T + 0.14, heat);
	// Char with drifts of ash, more of it where the fire is cooler.
	float ash = smoothstep(0.46, 0.74, fire_turned(at / 2.6 + vec2(41.3, 17.9)));
	vec3 char_colour = mix(FIRE_CHAR, FIRE_ASH, ash * mix(0.9, 0.45, fire_t));
	albedo *= mix(vec3(1.0), FIRE_SCORCH, scorch);
	albedo = mix(albedo, char_colour, burnt);
	charred = burnt;
	// Ember beds: bold cores fading softly out, drifting slowly.
	float bed = fire_warped(at / FIRE_BED_M + vec2(clock * 0.012, -clock * 0.008));
	float cover = mix(FIRE_BED_COVER.x, FIRE_BED_COVER.y, fire_t);
	float g = smoothstep(cover, cover + FIRE_BED_SOFT, bed) * deep;
	// Coal lumps: dark shapes inside the glow, most where it is brightest.
	float lump = smoothstep(0.54, 0.64, fire_turned(at / FIRE_LUMP_M + vec2(77.0, 5.3)));
	float lit = g * (1.0 - FIRE_LUMP_DARK * lump * smoothstep(0.15, 0.5, g));
	vec3 colour = mix(FIRE_RED, FIRE_HEART, smoothstep(0.2, 0.65, lit));
	colour = mix(colour, FIRE_GOLD, smoothstep(0.72, 1.0, lit) * flaming);
	// One rate everywhere, the phase by place (a rate that varied by place wound the phase up
	// into fine ripples as the clock ran on).
	float breathe = 0.78 + 0.22 * sin(clock * FIRE_BREATHE + fire_noise(at * 0.4 + 9.1) * 12.0);
	// Brightness falls faster than the colour cools, so a bed's fringe is a dim red on the char
	// rather than a haze over it.
	vec3 glow = colour * pow(lit, 1.6) * breathe;
	// Specks: a few small cells in a bed's hot core carry a yellow-white dot pulsing on its own
	// clock (the cells turned off the axes too).
	vec2 sp = vec2(0.848 * at.x - 0.53 * at.y, 0.53 * at.x + 0.848 * at.y) / FIRE_SPECK_CELL_M;
	vec2 cell = floor(sp);
	float pick = fire_hash(cell + vec2(7.3, 1.9));
	vec2 spot = vec2(fire_hash(cell + vec2(3.1, 9.7)), fire_hash(cell + vec2(8.5, 2.3))) * 0.6 + 0.2;
	float speck = 1.0 - smoothstep(0.06, 0.13, length(fract(sp) - spot));
	speck *= step(1.0 - FIRE_SPECK_SHARE, pick) * smoothstep(0.7, 0.95, g) * (1.0 - lump);
	float pulse = 0.5 + 0.5 * sin(clock * (2.5 + pick * 5.0) + pick * 60.0);
	glow = mix(glow, FIRE_SPECK, speck * pulse);
	return max(glow, vec3(0.0));
}
