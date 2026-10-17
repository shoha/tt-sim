// FIRE: the burn and its fire on the ground of persistent ground fire (design:
// docs/plans/2026-10-11-fire-features/design.md section 4, option C of the F3 probe). Included
// by authored_ground.gdshaderinc for the map's ground only (the skirt never burns): fragment()
// calls fire_glow(world_xz, TIME, albedo), which turns the albedo to char where the ground burns
// and returns the fire for EMISSION. Two baked textures (FireNoiseBake, bound by
// FireLook.bind_glow; fire_present 0 skips everything): the static bake
// (fire_ground_bake.gdshader), three tiles of everything here that does not change with time,
// worked out from the document's fire_mask, the flames' rasters (FireField: the summed heat and
// the feet's pools, read through a cubic B-spline so every threshold is a smooth curve) and the
// broad noise; and the fine noise bake (fire_glow_bake.gdshader: the tufts, lobes, coal lumps
// and cracks). Both hold the thresholds' arguments, so the edges here keep their widths.
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
//
// Cost (cards F4b-3 and F4b-4, docs/PERFORMANCE.md "Fire (F4)"): one fetch where nothing burns
// (the static bake is 0 there), four where it does; what is left per pixel is the thresholds,
// the drifting ember bed (one warped noise, only away from the crowded clumps), the breathing
// and the specks.

#include "res://shaders/fire_noise.gdshaderinc"
#include "res://shaders/fire_glow_noise.gdshaderinc"

uniform int fire_present = 0;
// The static bake (three tiles side by side) and one tile's frame (the map-frame XZ of its
// corner, its size in metres); the fine noise bake and its frame.
uniform sampler2D fire_static_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 fire_static_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D fire_fine_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 fire_fine_rect = vec4(0.0, 0.0, 1.0, 1.0);

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
// The ground's fire ramp, from a glow's fringe to its hottest (linear emission); the gold stays
// below the flames' outer band (fire_field.gdshader's FLAME_ORANGE) in brightness.
const vec3 FIRE_RED = vec3(0.3, 0.022, 0.003);
const vec3 FIRE_HEART = vec3(0.62, 0.085, 0.005);
const vec3 FIRE_GOLD = vec3(0.82, 0.21, 0.014);
const vec3 FIRE_SPECK = vec3(1.0, 0.5, 0.1);
// The lobes round the feet: how far their noise sways their outline (pool units), and the reach
// over which they fade in (the noise's scale is GLOW_LOBE_M).
const float FIRE_LOBE_SWAY = 0.9;
const vec2 FIRE_LOBE_EDGE = vec2(0.32, 0.62);
// The cracks' half width (noise units; their scale is GLOW_CRACK_M).
const float FIRE_CRACK_W = 0.035;
// The ember cores: their noise's scale (metres), the threshold their fringe starts at in the
// ember band and from the blaze, and the noise range over which they rise to their centre.
const float FIRE_BED_M = 2.4;
const vec2 FIRE_BED_COVER = vec2(0.64, 0.62);
const float FIRE_BED_SOFT = 0.12;
// How much the coal lumps (crust plates) darken the glow (their scale is GLOW_LUMP_M).
const float FIRE_LUMP_DARK = 0.7;
// The breathing's rate (radians a second: about 0.3 Hz).
const float FIRE_BREATHE = 1.9;
// Specks: one cell this wide in FIRE_SPECK_SHARE carries one, in the hotter glow.
const float FIRE_SPECK_CELL_M = 0.4;
const float FIRE_SPECK_SHARE = 0.12;

// The ground's fire at temperature `t` (0 the crust, 1 the hottest): deep red, orange, a warm
// orange-gold, its brightness rising out of the crust over a short fringe.
vec3 fire_ramp(float t) {
	vec3 c = mix(FIRE_RED, FIRE_HEART, smoothstep(0.2, 0.55, t));
	c = mix(c, FIRE_GOLD, smoothstep(0.65, 1.0, t));
	return c * smoothstep(0.0, 0.25, t);
}

// The fire at map-frame XZ `at` at time `clock`: turns `albedo` to char where it burns, sets
// `charred` to how much (0..1, for the matte finish) and returns the fire (emission).
vec3 fire_glow(vec2 at, float clock, inout vec3 albedo, out float charred) {
	charred = 0.0;
	if (fire_present == 0) {
		return vec3(0.0);
	}
	// The static bake's first tile here (kept off the tiles' seams): 0 where nothing burns.
	vec2 st = (at - fire_static_rect.xy) / fire_static_rect.zw;
	float edge_px = 0.5 / float(textureSize(fire_static_map, 0).x);
	st.x = clamp(st.x / 3.0, edge_px, 1.0 / 3.0 - edge_px);
	vec4 bake_a = texture(fire_static_map, st);
	if (bake_a.x + bake_a.y <= 0.0) {
		return vec3(0.0);
	}
	vec4 fine = texture(fire_fine_map, (at - fire_fine_rect.xy) / fire_fine_rect.zw);
	float burn = glow_unpack(bake_a.x, GLOW_BURN_RANGE);
	float burnt = smoothstep(0.0, FIRE_EDGE_SOFT, burn);
	// How deep in the burn: the ember cores fade out before the char does.
	float deep = smoothstep(0.04, 0.2, burn);
	float fire_t = bake_a.w;
	// Outside the char: dried grass in a band whose width wanders, its edge ragged, browned
	// further next to the char. Under the full char none of it shows.
	if (burnt < 1.0) {
		float tuft = fine.x;
		float dry_w = bake_a.z;
		float dry_arg = glow_unpack(bake_a.y, GLOW_DRY_RANGE);
		float dry = smoothstep(0.01, 0.1, dry_arg + (tuft - 0.5) * 0.05);
		dry *= 1.0 - burnt;
		float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
		vec3 dried = FIRE_DRY * clamp(lum / 0.1, 0.6, 1.3);
		albedo = mix(albedo, dried, dry * FIRE_DRY_MIX * (0.75 + 0.5 * (tuft - 0.5)));
		float scorch = smoothstep(-0.1 - 0.12 * dry_w, 0.0, burn + (tuft - 0.5) * 0.06);
		albedo *= mix(vec3(1.0), FIRE_SCORCH, scorch);
	}
	// Outside the char there is no fire either.
	if (burnt <= 0.0) {
		return vec3(0.0);
	}
	vec4 bake_b = texture(fire_static_map, st + vec2(1.0 / 3.0, 0.0));
	vec4 bake_c = texture(fire_static_map, st + vec2(2.0 / 3.0, 0.0));
	// The char: brown-black drifting to a warmer brown, a few bold near-black shapes, and soft
	// grey ash at the outskirts and between the clumps (where the flames' heat is low).
	float blotch = smoothstep(0.58, 0.7, bake_b.y);
	vec3 char_colour = mix(FIRE_CHAR, FIRE_CHAR_WARM, bake_b.x);
	char_colour = mix(char_colour, FIRE_CHAR_DEEP, blotch * 0.9);
	float ash = smoothstep(0.0, 1.0, glow_unpack(bake_b.z, GLOW_ASH_RANGE)) * bake_b.w;
	char_colour = mix(char_colour, FIRE_ASH, ash * 0.85);
	albedo = mix(albedo, char_colour, burnt);
	charred = burnt;
	// The crust's glow: bold lobes round the flames' feet, wider and hotter where the summed heat
	// is high; the noise sways their outline, less right at a foot.
	float pool = bake_c.x;
	float crowd = bake_c.y;
	float lobe_n = fine.y;
	float lobe_at = pool * 1.1 + crowd * 0.5 + (lobe_n - 0.5) * FIRE_LOBE_SWAY * (1.0 - 0.6 * pool);
	float lobe = smoothstep(FIRE_LOBE_EDGE.x, FIRE_LOBE_EDGE.y, lobe_at) * burnt;
	// Hottest at the feet and where flames crowd, a red fringe at a lobe's edge (an even
	// temperature drew flat orange puddles).
	float lobe_t = lobe * (0.3 + 0.4 * smoothstep(0.35, 1.0, pool) + 0.35 * crowd);
	lobe_t *= 0.8 + 0.4 * lobe_n;
	// Crust plates: dark coal lumps over the glow, fewer where it is hottest; the cracks run
	// bright between them.
	float lump = smoothstep(0.5, 0.66, fine.z);
	lobe_t *= 1.0 - FIRE_LUMP_DARK * lump * (1.0 - 0.4 * crowd);
	// Cracks: wandering lines of the glow through the crust near the flames.
	float crack_d = abs(fine.w - 0.5) / GLOW_CRACK_GAIN;
	float crack_t = (1.0 - smoothstep(FIRE_CRACK_W * 0.4, FIRE_CRACK_W, crack_d)) * bake_c.z * burnt;
	// Ember cores: bold, few, drifting slowly, away from the clumps.
	float core = 0.0;
	if (deep > 0.0 && crowd < 1.0) {
		float bed = fire_warped(at / FIRE_BED_M + vec2(clock * 0.012, -clock * 0.008));
		float cover = mix(FIRE_BED_COVER.x, FIRE_BED_COVER.y, fire_t);
		core = smoothstep(cover, cover + FIRE_BED_SOFT, bed) * deep * 0.75 * (1.0 - crowd);
	}
	// One rate everywhere, the phase by place (a rate that varied by place wound the phase up
	// into fine ripples as the clock ran on).
	float breathe = 0.86 + 0.14 * sin(clock * FIRE_BREATHE + bake_c.w * 12.0);
	float t = max(max(lobe_t, crack_t), core) * breathe;
	vec3 glow = fire_ramp(t);
	// Specks: a few small gold dots in the hotter glow, pulsing on their own clocks (the cells
	// turned off the axes too).
	vec2 sp = vec2(0.848 * at.x - 0.53 * at.y, 0.53 * at.x + 0.848 * at.y) / FIRE_SPECK_CELL_M;
	vec2 cell = floor(sp);
	float pick = fire_hash(cell + vec2(7.3, 1.9));
	float speck_on = step(1.0 - FIRE_SPECK_SHARE, pick) * smoothstep(0.35, 0.6, t);
	if (speck_on > 0.0) {
		vec2 spot = vec2(fire_hash(cell + vec2(3.1, 9.7)), fire_hash(cell + vec2(8.5, 2.3))) * 0.5 + 0.25;
		float size = mix(0.1, 0.2, fire_hash(cell + vec2(5.5, 4.4)));
		float speck = 1.0 - smoothstep(size * 0.55, size, length(fract(sp) - spot));
		speck *= speck_on * (1.0 - lump);
		float pulse = 0.55 + 0.45 * sin(clock * (2.5 + pick * 5.0) + pick * 60.0);
		glow = mix(glow, FIRE_SPECK, speck * pulse);
	}
	return max(glow, vec3(0.0));
}
