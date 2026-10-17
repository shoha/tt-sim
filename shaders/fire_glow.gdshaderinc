// FIRE: the burn and its fire on the ground of persistent ground fire (design:
// docs/plans/2026-10-11-fire-features/design.md section 4, option C of the F3 probe). Included
// by authored_ground.gdshaderinc for the map's ground only (the skirt never burns): fragment()
// calls fire_glow(world_xz, TIME, albedo), which turns the albedo to char where the ground burns
// and returns the fire for EMISSION. Two textures (FireLook.bind_glow; fire_present 0 skips
// everything): the document's fire_mask on the sample grid, and the flames' rasters (FireField,
// one texel every fire_heat_step metres: red the summed heat, green the feet's pools), both read
// through a cubic B-spline (texture_bspline) so every threshold is a smooth curve.
// Needs weight_uv, texture_bspline, layer_grid_origin and layer_grid_step from the including
// shader.
//
// The model (look card F4a; round 3's user verdict: a base fire unifies the flames, the burning
// ground bridges them, overlapping flames combine as stronger fire; round 4's direction: dark
// crusted char with bold glowing patches and cracks under each clump, brightest where flames
// overlap, the flames always the brightest thing in the frame):
//   - The crust: under a clump the ground is dark char, not a sheet of fire. It glows in bold,
//     soft-edged lobes round the flames' feet (the pools raster, its outline swayed by a broad
//     noise, so every foot dissolves into glow and the lobes of one clump join), wider and hotter
//     where the summed heat runs high (flames crowding or overlapping). Cracks, wandering lines of
//     the same glow, run through the crust near the flames, and dark coal lumps sit in the lobes.
//     One ramp, deep red through orange to a warm orange-gold (FIRE_GOLD) that stays below the
//     flames' outer band, so a flame always outshines the ground it stands on.
//   - Ember cores: away from the clumps a few bold glowing patches in a field of the fire's
//     noise, breathing slowly (about 0.3 Hz, the phase by place), with a few specks.
//   - The char: the albedo is replaced (a path or a light soil does not show through) by a painted
//     value field in world space, brown-black drifting to a warmer brown, a few bold near-black
//     shapes, and soft grey ash blotches at the outskirts and between the clumps. Matte, its
//     normals straight up (the including shader applies FIRE_FLATTEN), so no facet of the
//     low-poly ground draws an edge on it. The heat for the char is the mask widened over
//     FIRE_FILL_M, so a narrow cool valley between two strokes is char, not a straight seam of the
//     ground beneath.
//   - The outline: the mask is read through a bold warp (FIRE_WANDER_M), so a straight stroke's
//     edge swells into lobes, and eroded by a broad noise; outside it the grass is dried and
//     browned in a band whose width wanders (none in places, a few metres in others).
// Every pattern noise here is the fire's value noise on lattices turned off the map's axes (the
// game camera sees those axes as its diagonals) and warped by a broad noise, so no outline, band
// or cell lines up with anything. Colours are linear emission, and zero outside the lobes, cracks
// and cores: the filmic tonemap (white 1.0) lifts low emission about six times, so a dim fringe
// spread wide reads as a red or plum wash.

#include "res://shaders/fire_noise.gdshaderinc"

uniform int fire_present = 0;
uniform sampler2D fire_mask_map : hint_default_black, filter_linear, repeat_disable;
// The flames' rasters (FireField.HEAT_* and POOL_REACH): red the summed heat (0..1 of
// FireField.HEAT_FULL_M), green the feet's pools (0..1), one texel every fire_heat_step metres
// from the document's first sample.
uniform sampler2D fire_heat_map : hint_default_black, filter_linear, repeat_disable;
uniform float fire_heat_step = 0.5;
// How much of the flames' bed draws (the look probe compares the flames without it).
uniform float fire_bed = 1.0;

// The bands' starts as mask values (FireField.EMBER_MIN and FLAME_MIN over 255).
const float FIRE_EMBER_T = 0.157;
const float FIRE_FLAME_T = 0.431;
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
// How far (metres) the char's heat reaches across a cool valley (and the dried band past the
// char), how far the mask's read wanders (metres: a broad lobe and a finer ripple), and how far
// a broad noise moves the burn's edge (in mask units) and over what the char fades in at it.
const float FIRE_FILL_M = 1.4;
const vec2 FIRE_WANDER_M = vec2(1.8, 0.45);
const float FIRE_FEATHER = 0.5;
const float FIRE_EDGE_SOFT = 0.1;
// The ground's fire ramp, from a glow's fringe to its hottest (linear emission); the gold stays
// below the flames' outer band (fire_field.gdshader's FLAME_ORANGE) in brightness.
const vec3 FIRE_RED = vec3(0.3, 0.022, 0.003);
const vec3 FIRE_HEART = vec3(0.62, 0.085, 0.005);
const vec3 FIRE_GOLD = vec3(0.82, 0.21, 0.014);
const vec3 FIRE_SPECK = vec3(1.0, 0.5, 0.1);
// The lobes round the feet: their noise's scale (metres), how far it sways their outline (pool
// units), and the reach over which they fade in.
const float FIRE_LOBE_M = 1.3;
const float FIRE_LOBE_SWAY = 0.9;
const vec2 FIRE_LOBE_EDGE = vec2(0.32, 0.62);
// The cracks: their noise's scale (metres) and half width (noise units).
const float FIRE_CRACK_M = 1.5;
const float FIRE_CRACK_W = 0.035;
// The ember cores: their noise's scale (metres), the threshold their fringe starts at in the
// ember band and from the blaze, and the noise range over which they rise to their centre.
const float FIRE_BED_M = 2.4;
const vec2 FIRE_BED_COVER = vec2(0.64, 0.62);
const float FIRE_BED_SOFT = 0.12;
// Coal lumps (crust plates) inside the glow: their scale (metres) and how much they darken it.
const float FIRE_LUMP_M = 0.9;
const float FIRE_LUMP_DARK = 0.7;
// The breathing's rate (radians a second: about 0.3 Hz).
const float FIRE_BREATHE = 1.9;
// Specks: one cell this wide in FIRE_SPECK_SHARE carries one, in the hotter glow.
const float FIRE_SPECK_CELL_M = 0.4;
const float FIRE_SPECK_SHARE = 0.12;
// The ash: its noise's scale (metres) and the noise value its blotches start at.
const float FIRE_ASH_M = 2.2;
const float FIRE_ASH_COVER = 0.58;

// A lattice point's value (0..1) from its integer coordinates. The ground's noise hashes here
// rather than with fire_hash (card F4b-2): fire_hash's float arithmetic amplifies rounding, so
// at map-sized coordinates the cells sharing a lattice point, which reach it through different
// expressions, hashed it to different values, and every threshold on the noise broke along the
// lattice's edges into the straight-edged grey shards and orange wedges seen on the burn.
// Integer arithmetic is exact, so the noise is continuous everywhere.
float glow_hash(ivec2 c) {
	uvec2 q = uvec2(c) * uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	return float(n >> 8u) / 16777216.0;
}

// Value noise, 0..1, one blob a unit across (fire_noise's, on glow_hash).
float glow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	ivec2 c = ivec2(i);
	float a = glow_hash(c);
	float b = glow_hash(c + ivec2(1, 0));
	float d = glow_hash(c + ivec2(0, 1));
	float e = glow_hash(c + ivec2(1, 1));
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

// The fire's two octaves on lattices turned off the map's axes (by about 32 and 74 degrees).
float fire_turned(vec2 p) {
	vec2 a = vec2(0.848 * p.x - 0.53 * p.y, 0.53 * p.x + 0.848 * p.y);
	vec2 b = vec2(0.276 * p.x - 0.961 * p.y, 0.961 * p.x + 0.276 * p.y) * 2.17;
	return 0.68 * glow_noise(a) + 0.32 * glow_noise(b + vec2(7.1, 3.3));
}

// fire_turned warped by a broad noise (about three of its units across), for the big shapes.
float fire_warped(vec2 p) {
	vec2 w = vec2(glow_noise(p * 0.37 + vec2(3.1, 8.3)), glow_noise(p * 0.37 + vec2(9.7, 1.9)));
	return fire_turned(p + (w - 0.5) * 1.2);
}

// The ground's fire at temperature `t` (0 the crust, 1 the hottest): deep red, orange, a warm
// orange-gold, its brightness rising out of the crust over a short fringe.
vec3 fire_ramp(float t) {
	vec3 c = mix(FIRE_RED, FIRE_HEART, smoothstep(0.2, 0.55, t));
	c = mix(c, FIRE_GOLD, smoothstep(0.65, 1.0, t));
	return c * smoothstep(0.0, 0.25, t);
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
	// Most of a map does not burn: taps on two rings reaching past the wander and the dried band.
	float near = max(
		fire_tap_max(uv, dir_a * per_m * 1.9, dir_b * per_m * 1.9),
		fire_tap_max(uv, (dir_a + dir_b) * per_m * 2.7, (dir_a - dir_b) * per_m * 2.7)
	);
	if (max(near, texture(fire_mask_map, uv).r) < 0.002) {
		return vec3(0.0);
	}
	// The burn wanders: the mask is read through a bold warp (lobes) and a finer one, so the
	// outline of a straight stroke swells and bites unevenly and a straight valley bends.
	vec2 lobe_w = vec2(glow_noise(at / 7.0 + vec2(4.1, 7.7)), glow_noise(at / 7.0 + vec2(8.9, 2.6)));
	vec2 ripple = vec2(glow_noise(at / 2.4 + vec2(1.3, 5.9)), glow_noise(at / 2.4 + vec2(6.2, 3.4)));
	vec2 read = at + (lobe_w - 0.5) * 2.0 * FIRE_WANDER_M.x + (ripple - 0.5) * 2.0 * FIRE_WANDER_M.y;
	uv = weight_uv(read, grid);
	// The mask widened across a cool valley (the mean of four turned taps FIRE_FILL_M out), and
	// their largest for the dried band past the char.
	vec2 tap_a = dir_a * per_m * FIRE_FILL_M;
	vec2 tap_b = dir_b * per_m * FIRE_FILL_M;
	vec4 taps = vec4(
		texture(fire_mask_map, uv + tap_a).r, texture(fire_mask_map, uv - tap_a).r,
		texture(fire_mask_map, uv + tap_b).r, texture(fire_mask_map, uv - tap_b).r
	);
	float wide = dot(taps, vec4(0.25));
	float reach = max(max(taps.x, taps.y), max(taps.z, taps.w));
	float heat = max(texture_bspline(fire_mask_map, uv).r, wide);
	// The flames' rasters here: their summed heat and the feet's pools.
	vec2 heat_grid = vec2(textureSize(fire_heat_map, 0));
	vec2 heat_uv = ((at - layer_grid_origin) / fire_heat_step + 0.5) / heat_grid;
	vec2 rasters = texture_bspline(fire_heat_map, heat_uv).rg * fire_bed;
	float flame_heat = rasters.x;
	float pool = rasters.y;
	// The char's edge: eroded by a broad noise and a finer one; under flames always burnt.
	float edge_noise = 0.65 * fire_warped(at / 4.2 + vec2(13.1, -4.7))
		+ 0.35 * fire_turned(at / 1.3 + vec2(2.7, 6.1));
	float burn = max(
		heat - FIRE_EMBER_T + (edge_noise - 0.5) * FIRE_FEATHER, max(flame_heat, pool) * 2.0 - 0.1
	);
	float burnt = smoothstep(0.0, FIRE_EDGE_SOFT, burn);
	// How deep in the burn: the ember cores fade out before the char does.
	float deep = smoothstep(0.04, 0.2, burn);
	float fire_t = clamp((heat - FIRE_EMBER_T) / (1.0 - FIRE_EMBER_T), 0.0, 1.0);
	// Outside the char: dried grass in a band whose width wanders (the mask's taps 1.4 m out, or
	// the early-out's rings further, or none), its edge ragged, browned further next to the char.
	float dry_w = fire_warped(at / 4.5 + vec2(-17.3, 3.9));
	float dry_reach = mix(reach, near, smoothstep(0.45, 0.7, dry_w)) * smoothstep(0.2, 0.42, dry_w);
	float tuft = fire_turned(at / 0.6 + vec2(5.3, -2.1));
	float dry = smoothstep(0.01, 0.1, dry_reach + (edge_noise - 0.5) * 0.12 + (tuft - 0.5) * 0.05);
	dry *= 1.0 - burnt;
	float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	vec3 dried = FIRE_DRY * clamp(lum / 0.1, 0.6, 1.3);
	albedo = mix(albedo, dried, dry * FIRE_DRY_MIX * (0.75 + 0.5 * (tuft - 0.5)));
	float scorch = smoothstep(-0.1 - 0.12 * dry_w, 0.0, burn + (tuft - 0.5) * 0.06);
	albedo *= mix(vec3(1.0), FIRE_SCORCH, scorch);
	// The char: brown-black drifting to a warmer brown, a few bold near-black shapes, and soft
	// grey ash at the outskirts and between the clumps (where the flames' heat is low).
	float drift = fire_warped(at / 5.5 + vec2(31.7, 2.9));
	float blotch = smoothstep(0.58, 0.7, fire_warped(at / 3.8 + vec2(-8.3, 15.1)));
	vec3 char_colour = mix(FIRE_CHAR, FIRE_CHAR_WARM, smoothstep(0.45, 0.75, drift));
	char_colour = mix(char_colour, FIRE_CHAR_DEEP, blotch * 0.9);
	float ash_room = (1.0 - smoothstep(0.04, 0.22, flame_heat + pool * 0.3)) * (1.0 - 0.5 * blotch);
	float ash_cover = mix(FIRE_ASH_COVER - 0.08, FIRE_ASH_COVER + 0.06, fire_t);
	float ash_n = fire_warped(at / FIRE_ASH_M + vec2(41.3, 17.9));
	float ash = smoothstep(ash_cover, ash_cover + 0.14, ash_n) * ash_room;
	char_colour = mix(char_colour, FIRE_ASH, ash * 0.85);
	albedo = mix(albedo, char_colour, burnt);
	charred = burnt;
	// The crust's glow: bold lobes round the flames' feet, wider and hotter where the summed heat
	// is high; the noise sways their outline, less right at a foot.
	float lobe_n = fire_warped(at / FIRE_LOBE_M + vec2(23.3, 9.1));
	float crowd = smoothstep(0.3, 0.85, flame_heat);
	float lobe_at = pool * 1.1 + crowd * 0.5 + (lobe_n - 0.5) * FIRE_LOBE_SWAY * (1.0 - 0.6 * pool);
	float lobe = smoothstep(FIRE_LOBE_EDGE.x, FIRE_LOBE_EDGE.y, lobe_at) * burnt;
	// Hottest at the feet and where flames crowd, a red fringe at a lobe's edge (an even
	// temperature drew flat orange puddles).
	float lobe_t = lobe * (0.3 + 0.4 * smoothstep(0.35, 1.0, pool) + 0.35 * crowd);
	lobe_t *= 0.8 + 0.4 * lobe_n;
	// Crust plates: dark coal lumps over the glow, fewer where it is hottest; the cracks run
	// bright between them.
	float lump = smoothstep(0.5, 0.66, fire_warped(at / FIRE_LUMP_M + vec2(77.0, 5.3)));
	lobe_t *= 1.0 - FIRE_LUMP_DARK * lump * (1.0 - 0.4 * crowd);
	// Cracks: wandering lines of the glow through the crust near the flames.
	float crack_n = fire_warped(at / FIRE_CRACK_M + vec2(-3.7, 29.3));
	float crack = 1.0 - smoothstep(FIRE_CRACK_W * 0.4, FIRE_CRACK_W, abs(crack_n - 0.5));
	crack *= smoothstep(0.03, 0.2, pool + flame_heat) * burnt;
	float crack_t = crack * (0.38 + 0.3 * crowd + 0.2 * pool);
	// Ember cores: bold, few, drifting slowly, away from the clumps.
	float bed = fire_warped(at / FIRE_BED_M + vec2(clock * 0.012, -clock * 0.008));
	float cover = mix(FIRE_BED_COVER.x, FIRE_BED_COVER.y, fire_t);
	float core = smoothstep(cover, cover + FIRE_BED_SOFT, bed) * deep * 0.75 * (1.0 - crowd);
	// One rate everywhere, the phase by place (a rate that varied by place wound the phase up
	// into fine ripples as the clock ran on).
	float breathe = 0.86 + 0.14 * sin(clock * FIRE_BREATHE + glow_noise(at * 0.4 + 9.1) * 12.0);
	float t = max(max(lobe_t, crack_t), core) * breathe;
	vec3 glow = fire_ramp(t);
	// Specks: a few small gold dots in the hotter glow, pulsing on their own clocks (the cells
	// turned off the axes too).
	vec2 sp = vec2(0.848 * at.x - 0.53 * at.y, 0.53 * at.x + 0.848 * at.y) / FIRE_SPECK_CELL_M;
	vec2 cell = floor(sp);
	float pick = fire_hash(cell + vec2(7.3, 1.9));
	vec2 spot = vec2(fire_hash(cell + vec2(3.1, 9.7)), fire_hash(cell + vec2(8.5, 2.3))) * 0.5 + 0.25;
	float size = mix(0.1, 0.2, fire_hash(cell + vec2(5.5, 4.4)));
	float speck = 1.0 - smoothstep(size * 0.55, size, length(fract(sp) - spot));
	speck *= step(1.0 - FIRE_SPECK_SHARE, pick) * smoothstep(0.35, 0.6, t) * (1.0 - lump);
	float pulse = 0.55 + 0.45 * sin(clock * (2.5 + pick * 5.0) + pick * 60.0);
	glow = mix(glow, FIRE_SPECK, speck * pulse);
	return max(glow, vec3(0.0));
}
