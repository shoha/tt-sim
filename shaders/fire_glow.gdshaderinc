// FIRE: the burn and its fire on the ground of persistent ground fire (design:
// docs/plans/2026-10-11-fire-features/design.md section 4, option C of the F3 probe). Included
// by authored_ground.gdshaderinc for the map's ground only (the skirt never burns): fragment()
// calls fire_glow(world_xz, TIME, albedo), which turns the albedo to char where the ground burns
// and returns the fire for EMISSION. Two textures (FireLook.bind_glow; fire_present 0 skips
// everything): the document's fire_mask on the sample grid, and the flames' summed heat
// (FireField's heat raster, one texel every fire_heat_step metres), both read through a cubic
// B-spline (texture_bspline) so every threshold is a smooth curve.
// Needs weight_uv, texture_bspline, layer_grid_origin and layer_grid_step from the including
// shader.
//
// The model (look card F4a, round 3; the user's verdict: a base fire unifies the flames, the
// burning ground bridges them, and overlapping flames combine as stronger fire):
//   - The bed: under every clump of flames the ground itself is fire. Its temperature is the
//     flames' summed heat, so a lone flame stands in a dim red pool, a clump in one continuous
//     orange bed, and where flames crowd (a blaze, a dense clump) the bed runs gold to flame
//     yellow. One colour ramp (deep red, orange, gold, flame yellow) with soft edges between its
//     bands, broken by a broad cloud so its outline is a painted lump, not an iso-line.
//   - Ember cores: away from the flames (the ember band) a few bold hot cores in a field of the
//     fire's noise, flame yellow at the centre fading out through red over a wide fringe, with
//     dark coal lumps and a cluster of bright specks around each core; they breathe slowly
//     (about 0.3 Hz, the phase by place). Hot enough to read by day.
//   - The char, at the burn's outskirts and in the gaps between clumps: the albedo is replaced
//     (a path or a light soil does not show through) by a painted value field in world space,
//     deep umber drifting to plum, a few bold near-black blotches, and a few long pale strokes of
//     ash. Matte, its normals straight up (the including shader applies FIRE_FLATTEN), so no
//     facet of the low-poly ground draws an edge on it. The heat for the char is the mask
//     widened over FIRE_FILL_M, so a narrow cool valley between two strokes is char, not a
//     straight seam of the ground beneath.
//   - The outline: the mask is read through a bold warp (FIRE_WANDER_M), so a straight stroke's
//     edge swells into lobes, and eroded by a broad noise; outside it a ragged band of dying
//     straw-yellow grass, browned where it meets the char.
// Every pattern noise here is the fire's value noise on lattices turned off the map's axes (the
// game camera sees those axes as its diagonals) and warped by a broad noise, so no outline, band
// or cell lines up with anything. Colours are linear emission, picked for the filmic tonemap
// (white 1.0 lifts low emission about six times, so the fringes stay dim and nothing glows
// everywhere); the hottest go past 1 so the environment's glow gives them a soft halo.

#include "res://shaders/fire_noise.gdshaderinc"

uniform int fire_present = 0;
uniform sampler2D fire_mask_map : hint_default_black, filter_linear, repeat_disable;
// The flames' summed heat (FireField.HEAT_*): 0..1 of FireField.HEAT_FULL_M, one texel every
// fire_heat_step metres from the document's first sample.
uniform sampler2D fire_heat_map : hint_default_black, filter_linear, repeat_disable;
uniform float fire_heat_step = 0.5;
// How much of the flames' bed draws (the look probe compares the flames without it).
uniform float fire_bed = 1.0;

// The bands' starts as mask values (FireField.EMBER_MIN and FLAME_MIN over 255).
const float FIRE_EMBER_T = 0.157;
const float FIRE_FLAME_T = 0.431;
// The char's painted field (linear albedo): deep umber, a plum drift, the bold dark blotches,
// and the ash.
const vec3 FIRE_CHAR = vec3(0.032, 0.015, 0.009);
const vec3 FIRE_PLUM = vec3(0.024, 0.01, 0.015);
const vec3 FIRE_CHAR_DEEP = vec3(0.006, 0.004, 0.0035);
const vec3 FIRE_ASH = vec3(0.2, 0.17, 0.14);
// How far char's normals lean to straight up (the including shader applies it): all the way,
// a facet of the ground's normals drew a hard straight edge on the char under a low sun.
const float FIRE_FLATTEN = 1.0;
// Just outside the char: browned (a multiplier) next to it, and dying straw-yellow grass (an
// albedo, scaled by the ground's own brightness) in a ragged band past that.
const vec3 FIRE_SCORCH = vec3(0.4, 0.28, 0.18);
const vec3 FIRE_STRAW = vec3(0.4, 0.3, 0.09);
const float FIRE_STRAW_MIX = 0.75;
// How far (metres) the char's heat reaches across a cool valley (and the straw band past the
// char), how far the mask's read wanders (metres: a broad lobe and a finer ripple), and how far
// a broad noise moves the burn's edge (in mask units) and over what the char fades in at it.
const float FIRE_FILL_M = 1.4;
const vec2 FIRE_WANDER_M = vec2(1.8, 0.45);
const float FIRE_FEATHER = 0.5;
const float FIRE_EDGE_SOFT = 0.05;
// The fire's colour ramp, from a bed's cool fringe to its hottest centre (linear emission).
const vec3 FIRE_RED = vec3(0.42, 0.03, 0.004);
const vec3 FIRE_HEART = vec3(1.0, 0.16, 0.008);
const vec3 FIRE_GOLD = vec3(1.35, 0.62, 0.1);
const vec3 FIRE_YELLOW = vec3(1.6, 1.05, 0.3);
const vec3 FIRE_SPECK = vec3(1.8, 1.4, 0.7);
// The ember cores: their noise's scale (metres), the threshold their fringe starts at in the
// ember band and from the blaze, and the noise range over which they rise to their centre.
const float FIRE_BED_M = 2.4;
const vec2 FIRE_BED_COVER = vec2(0.62, 0.58);
const float FIRE_BED_SOFT = 0.15;
// Coal lumps inside a bed: their scale (metres) and how much of a bed they darken.
const float FIRE_LUMP_M = 0.7;
const float FIRE_LUMP_DARK = 0.45;
// The breathing's rate (radians a second: about 0.3 Hz).
const float FIRE_BREATHE = 1.9;
// Specks: one cell this wide in FIRE_SPECK_SHARE carries one, around a bed's hot core.
const float FIRE_SPECK_CELL_M = 0.4;
const float FIRE_SPECK_SHARE = 0.22;

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

// The fire's colour at temperature `t` (0 the char, 1 the hottest centre): deep red, orange,
// gold, flame yellow, its brightness rising out of the char over a wide fringe.
vec3 fire_ramp(float t) {
	vec3 c = mix(FIRE_RED, FIRE_HEART, smoothstep(0.3, 0.5, t));
	c = mix(c, FIRE_GOLD, smoothstep(0.55, 0.75, t));
	c = mix(c, FIRE_YELLOW, smoothstep(0.8, 0.98, t));
	return c * pow(smoothstep(0.06, 0.45, t), 1.4);
}

// The largest of the mask's four taps `a` and `b` either side of `uv`.
float fire_tap_max(vec2 uv, vec2 a, vec2 b) {
	return max(
		max(texture(fire_mask_map, uv + a).r, texture(fire_mask_map, uv - a).r),
		max(texture(fire_mask_map, uv + b).r, texture(fire_mask_map, uv - b).r)
	);
}

// The fire at map-frame XZ `at` at time `clock`: turns `albedo` to char where it burns, sets
// `charred` to how much (0..1, for the matte finish) and returns the fire (emission).
vec3 fire_glow(vec2 at, float clock, inout vec3 albedo, out float charred) {
	charred = 0.0;
	if (fire_present == 0) {
		return vec3(0.0);
	}
	vec2 grid = vec2(textureSize(fire_mask_map, 0));
	vec2 uv = weight_uv(at, grid);
	vec2 per_m = 1.0 / (layer_grid_step * grid);
	vec2 dir_a = vec2(0.848, 0.53);
	vec2 dir_b = vec2(-0.53, 0.848);
	// Most of a map does not burn: taps on two rings reaching past the wander and the straw band.
	float near = max(
		fire_tap_max(uv, dir_a * per_m * 1.9, dir_b * per_m * 1.9),
		fire_tap_max(uv, (dir_a + dir_b) * per_m * 2.7, (dir_a - dir_b) * per_m * 2.7)
	);
	if (max(near, texture(fire_mask_map, uv).r) < 0.002) {
		return vec3(0.0);
	}
	// The burn wanders: the mask is read through a bold warp (lobes) and a finer one, so the
	// outline of a straight stroke swells and bites unevenly and a straight valley bends.
	vec2 lobe = vec2(fire_noise(at / 7.0 + vec2(4.1, 7.7)), fire_noise(at / 7.0 + vec2(8.9, 2.6)));
	vec2 ripple = vec2(fire_noise(at / 2.4 + vec2(1.3, 5.9)), fire_noise(at / 2.4 + vec2(6.2, 3.4)));
	vec2 read = at + (lobe - 0.5) * 2.0 * FIRE_WANDER_M.x + (ripple - 0.5) * 2.0 * FIRE_WANDER_M.y;
	uv = weight_uv(read, grid);
	// The mask widened across a cool valley (the mean of four turned taps FIRE_FILL_M out), and
	// their largest for the straw band past the char.
	vec2 tap_a = dir_a * per_m * FIRE_FILL_M;
	vec2 tap_b = dir_b * per_m * FIRE_FILL_M;
	vec4 taps = vec4(
		texture(fire_mask_map, uv + tap_a).r, texture(fire_mask_map, uv - tap_a).r,
		texture(fire_mask_map, uv + tap_b).r, texture(fire_mask_map, uv - tap_b).r
	);
	float wide = dot(taps, vec4(0.25));
	float reach = max(max(taps.x, taps.y), max(taps.z, taps.w));
	float heat = max(texture_bspline(fire_mask_map, uv).r, wide);
	// The flames' bed: their summed heat at this point.
	vec2 heat_grid = vec2(textureSize(fire_heat_map, 0));
	vec2 heat_uv = ((at - layer_grid_origin) / fire_heat_step + 0.5) / heat_grid;
	float flame_heat = texture_bspline(fire_heat_map, heat_uv).r * fire_bed;
	// The char's edge: eroded by a broad noise and a finer one; under flames always burnt.
	float edge_noise = 0.65 * fire_warped(at / 4.2 + vec2(13.1, -4.7))
		+ 0.35 * fire_turned(at / 1.3 + vec2(2.7, 6.1));
	float burn = max(
		heat - FIRE_EMBER_T + (edge_noise - 0.5) * FIRE_FEATHER, flame_heat * 2.0 - 0.1
	);
	float burnt = smoothstep(0.0, FIRE_EDGE_SOFT, burn);
	// How deep in the burn: the ember cores fade out before the char does.
	float deep = smoothstep(0.04, 0.2, burn);
	float fire_t = clamp((heat - FIRE_EMBER_T) / (1.0 - FIRE_EMBER_T), 0.0, 1.0);
	// Outside the char: dying straw-yellow grass in a ragged band, browned next to the char.
	float straw = smoothstep(0.01, 0.09, reach + (edge_noise - 0.5) * 0.12) * (1.0 - burnt);
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(albedo, FIRE_STRAW * clamp(lum / 0.1, 0.6, 1.4), straw * FIRE_STRAW_MIX);
	albedo *= mix(vec3(1.0), FIRE_SCORCH, smoothstep(-0.08, 0.0, burn));
	// The char: umber drifting to plum, a few bold dark blotches, a few long strokes of ash.
	float drift = fire_warped(at / 5.5 + vec2(31.7, 2.9));
	float blotch = smoothstep(0.6, 0.72, fire_warped(at / 3.8 + vec2(-8.3, 15.1)));
	vec3 char_colour = mix(FIRE_CHAR, FIRE_PLUM, smoothstep(0.35, 0.65, drift));
	char_colour = mix(char_colour, FIRE_CHAR_DEEP, blotch * 0.85);
	// (Warped, and only twice as long as wide: a plain lattice stretched further drew them as
	// angular grey shards.)
	vec2 stroke = vec2(dot(at, vec2(0.6, 0.8)) / 2.6, dot(at, vec2(-0.8, 0.6)) / 1.2);
	float ash = smoothstep(0.6, 0.8, fire_warped(stroke + vec2(41.3, 17.9)));
	char_colour = mix(char_colour, FIRE_ASH, ash * mix(0.75, 0.4, fire_t));
	albedo = mix(albedo, char_colour, burnt);
	charred = burnt;
	// The bed's temperature: the flames' heat, its iso-lines broken by a broad cloud.
	float lumpy = fire_warped(at / 1.7 + vec2(23.3, 9.1));
	float bed_t = flame_heat * (0.65 + 0.7 * lumpy) * burnt;
	// Ember cores: bold, few, drifting slowly; flame yellow at the centre, a wide red fringe.
	float bed = fire_warped(at / FIRE_BED_M + vec2(clock * 0.012, -clock * 0.008));
	float cover = mix(FIRE_BED_COVER.x, FIRE_BED_COVER.y, fire_t);
	float core = smoothstep(cover, cover + FIRE_BED_SOFT, bed) * deep;
	// One rate everywhere, the phase by place (a rate that varied by place wound the phase up
	// into fine ripples as the clock ran on).
	float breathe = 0.86 + 0.14 * sin(clock * FIRE_BREATHE + fire_noise(at * 0.4 + 9.1) * 12.0);
	float t = max(bed_t, core) * breathe;
	// Coal lumps: dark shapes inside the glow, most where it is hottest.
	float lump = smoothstep(0.52, 0.7, fire_warped(at / FIRE_LUMP_M + vec2(77.0, 5.3)));
	t *= 1.0 - FIRE_LUMP_DARK * lump * smoothstep(0.3, 0.6, t);
	vec3 glow = fire_ramp(t);
	// Specks: a cluster of small yellow-white dots around each hot core, pulsing on their own
	// clocks (the cells turned off the axes too).
	vec2 sp = vec2(0.848 * at.x - 0.53 * at.y, 0.53 * at.x + 0.848 * at.y) / FIRE_SPECK_CELL_M;
	vec2 cell = floor(sp);
	float pick = fire_hash(cell + vec2(7.3, 1.9));
	vec2 spot = vec2(fire_hash(cell + vec2(3.1, 9.7)), fire_hash(cell + vec2(8.5, 2.3))) * 0.5 + 0.25;
	float size = mix(0.1, 0.2, fire_hash(cell + vec2(5.5, 4.4)));
	float speck = 1.0 - smoothstep(size * 0.55, size, length(fract(sp) - spot));
	speck *= step(1.0 - FIRE_SPECK_SHARE, pick) * smoothstep(0.25, 0.5, t) * (1.0 - lump);
	float pulse = 0.55 + 0.45 * sin(clock * (2.5 + pick * 5.0) + pick * 60.0);
	glow = mix(glow, FIRE_SPECK, speck * pulse);
	return max(glow, vec3(0.0));
}
