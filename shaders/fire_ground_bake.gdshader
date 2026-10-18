shader_type canvas_item;
// The ground fire's sim bake (FireNoiseBake; cards F4b-4 and ground-cost): everything of
// fire_glow.gdshaderinc that does not change with time, worked out at each texel's centre. One 2D
// SubViewport, two tiles side by side over the same frame; a refresh redraws only the rectangle
// its re-planned blocks reach (the viewport is never cleared). Each texel first works out the
// static fields from the fire mask, the flames' rasters and the broad noise fields
// (fire_glow_noise.gdshaderinc), and the fine noise fields (glow_fine_fields) inline:
//   a: the burn (GLOW_BURN_RANGE; 0 where the mask has no fire within the early-out's reach),
//      the dried band's argument (GLOW_DRY_RANGE, without the tufts), the dried band's width
//      noise and the fire's temperature (0..1 over the ember band and up);
//   b: the char's warm drift (its weight), the dark blotches' noise, the ash's argument
//      (GLOW_ASH_RANGE) and the room the ash has between the clumps;
//   c: the feet's pools, the flames' crowding, the cracks' strength and the breathing's phase;
// then fire_sim_bake (fire_glow.gdshaderinc) turns them into the ground's terms, the tile's
// share of which it writes:
//   tile 0, the albedo terms: the char's weight, the dried band's mix, the scorch, the char's tone;
//   tile 1, the glow terms: sqrt(glow / FIRE_SIM_GLOW_MAX) before the breathing, and the
//      breathing's phase.
// Both are 0 where nothing burns or dries. Written as is (no blending), in RGBA8.
render_mode unshaded, blend_disabled;

// fire_glow.gdshaderinc brings fire_glow_noise.gdshaderinc and fire_sim_bake (its uniforms are
// unused here).
#include "res://shaders/fire_glow.gdshaderinc"

// One tile's frame: the map-frame XZ of its corner and its size in metres, and its texels.
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform ivec2 tile_px = ivec2(16, 16);
// The fire mask on the document's sample grid (its first sample's map-frame XZ and spacing),
// and the flames' rasters (FireField: red the summed heat, green the feet's pools).
uniform sampler2D fire_mask_map : hint_default_black, filter_linear, repeat_disable;
uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_step = vec2(0.25);
uniform sampler2D fire_heat_map : hint_default_black, filter_linear, repeat_disable;
uniform float fire_heat_step = 0.5;

// The ember band's start as a mask value (FireField.EMBER_MIN over 255).
const float FIRE_EMBER_T = 0.157;
// How far (metres) the char's heat reaches across a cool valley, how far a broad noise moves the
// burn's edge (in mask units).
const float FIRE_FILL_M = 1.4;
const float FIRE_FEATHER = 0.5;
// The noise value the ash's blotches start at (its scale is FIRE_ASH_M) and over what they rise.
const float FIRE_ASH_COVER = 0.58;
const float FIRE_ASH_SOFT = 0.14;

vec2 bake_uv(vec2 at, vec2 grid) {
	return ((at - grid_origin) / grid_step + 0.5) / grid;
}

// The ground shader's texture_bspline (authored_ground.gdshaderinc): a cubic B-spline read from
// four bilinear taps.
vec4 bake_bspline(sampler2D tex, vec2 uv) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 p = uv * size - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 s0 = w0 + w1;
	vec2 s1 = w2 + w3;
	vec2 uv0 = (i - 0.5 + w1 / s0) / size;
	vec2 uv1 = (i + 1.5 + w3 / s1) / size;
	return s0.y * (s0.x * texture(tex, uv0) + s1.x * texture(tex, vec2(uv1.x, uv0.y)))
		+ s1.y * (s0.x * texture(tex, vec2(uv0.x, uv1.y)) + s1.x * texture(tex, uv1));
}

// The largest of the mask's four taps `a` and `b` either side of `uv`.
float bake_tap_max(vec2 uv, vec2 a, vec2 b) {
	return max(
		max(texture(fire_mask_map, uv + a).r, texture(fire_mask_map, uv - a).r),
		max(texture(fire_mask_map, uv + b).r, texture(fire_mask_map, uv - b).r)
	);
}

void fragment() {
	int tile = int(FRAGCOORD.x) / tile_px.x;
	vec2 local = FRAGCOORD.xy - vec2(float(tile * tile_px.x), 0.0);
	vec2 at = rect.xy + local / vec2(tile_px) * rect.zw;
	vec2 grid = vec2(textureSize(fire_mask_map, 0));
	vec2 uv = bake_uv(at, grid);
	vec2 per_m = 1.0 / (grid_step * grid);
	vec2 dir_a = vec2(0.848, 0.53);
	vec2 dir_b = vec2(-0.53, 0.848);
	// Most of a map does not burn: taps on two rings reaching past the wander and the dried band.
	float near = max(
		bake_tap_max(uv, dir_a * per_m * 1.9, dir_b * per_m * 1.9),
		bake_tap_max(uv, (dir_a + dir_b) * per_m * 2.7, (dir_a - dir_b) * per_m * 2.7)
	);
	vec4 a = vec4(0.0);
	vec4 b = vec4(0.0);
	vec4 c = vec4(0.0);
	if (max(near, texture(fire_mask_map, uv).r) >= 0.002) {
		vec4 fields_a = glow_fields_a(at);
		vec4 fields_b = glow_fields_b(at);
		// The burn wanders: the mask is read through a bold warp (lobes) and a finer one.
		vec2 read = at + (fields_a.xy * 2.0 - 1.0) * FIRE_WANDER_REACH;
		uv = bake_uv(read, grid);
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
		float heat = max(bake_bspline(fire_mask_map, uv).r, wide);
		vec2 heat_grid = vec2(textureSize(fire_heat_map, 0));
		vec2 heat_uv = ((at - grid_origin) / fire_heat_step + 0.5) / heat_grid;
		vec2 rasters = bake_bspline(fire_heat_map, heat_uv).rg;
		float flame_heat = rasters.x;
		float pool = rasters.y;
		// The char's edge: eroded by a broad noise and a finer one; under flames always burnt.
		float edge_noise = fields_a.z;
		float burn = max(
			heat - FIRE_EMBER_T + (edge_noise - 0.5) * FIRE_FEATHER, max(flame_heat, pool) * 2.0 - 0.1
		);
		float fire_t = clamp((heat - FIRE_EMBER_T) / (1.0 - FIRE_EMBER_T), 0.0, 1.0);
		// The dried band's width wanders (the mask's taps 1.4 m out, or the rings further, or none).
		float dry_w = fields_a.w;
		float dry_reach = mix(reach, near, smoothstep(0.45, 0.7, dry_w)) * smoothstep(0.2, 0.42, dry_w);
		float dry_arg = dry_reach + (edge_noise - 0.5) * 0.12;
		a = vec4(glow_pack(burn, GLOW_BURN_RANGE), glow_pack(dry_arg, GLOW_DRY_RANGE), dry_w, fire_t);
		// The char: its warm drift, the dark blotches, and the ash at the outskirts and between the
		// clumps (where the flames' heat is low).
		float blotch = smoothstep(0.58, 0.7, fields_b.y);
		float ash_room = (1.0 - smoothstep(0.04, 0.22, flame_heat + pool * 0.3)) * (1.0 - 0.5 * blotch);
		float ash_cover = mix(FIRE_ASH_COVER - 0.08, FIRE_ASH_COVER + 0.06, fire_t);
		float ash_arg = (fields_b.z - ash_cover) / FIRE_ASH_SOFT;
		b = vec4(smoothstep(0.45, 0.75, fields_b.x), fields_b.y, glow_pack(ash_arg, GLOW_ASH_RANGE), ash_room);
		// The glow's inputs: the pools, the crowding, the cracks' strength near the flames, the
		// breathing's phase.
		float crowd = smoothstep(0.3, 0.85, flame_heat);
		float crack = smoothstep(0.03, 0.2, pool + flame_heat) * (0.38 + 0.3 * crowd + 0.2 * pool);
		c = vec4(clamp(pool, 0.0, 1.0), crowd, crack, fields_b.w);
	}
	// The ground's terms where anything burns or dries, nothing elsewhere.
	vec4 albedo_terms = vec4(0.0);
	vec4 glow_terms = vec4(0.0);
	if (a.x + a.y > 0.0) {
		fire_sim_bake(a, b, c, glow_fine_fields(at), albedo_terms, glow_terms);
	}
	COLOR = tile == 0 ? albedo_terms : glow_terms;
}
