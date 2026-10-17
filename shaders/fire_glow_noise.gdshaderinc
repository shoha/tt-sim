// The ground fire's value noise (fire_glow.gdshaderinc) and its fields, shared by the ground
// shader and the bakes (FireNoiseBake; cards F4b-3 and F4b-4); the noise alone (glow_noise,
// glow_cloud) also by the events' scorch and the persistent fire's smoke (card F4b-5). The
// fields are a pure function of map-frame XZ: the broad ones (glow_fields_a, glow_fields_b) feed
// the static bake
// (fire_ground_bake.gdshader), which works out everything of the ground's fire that does not
// change with time, and the fine ones (glow_fine_fields: the tufts, lobes, coal lumps, cracks)
// are baked once per map at a finer spacing (fire_glow_bake.gdshader). Only the drifting ember
// bed is evaluated per pixel (fire_warped, in fire_glow.gdshaderinc).

// How far (metres) the mask's read wanders (a broad lobe and a finer ripple), and the most it
// moves either way (the baked warp's range).
const vec2 FIRE_WANDER_M = vec2(1.8, 0.45);
const float FIRE_WANDER_REACH = 2.25;
// The ash's noise scale (metres).
const float FIRE_ASH_M = 2.2;

// A lattice point's value (0..1) from its integer coordinates. The ground's noise hashes here
// rather than with fire_hash (card F4b-2): fire_hash's float arithmetic amplifies rounding, so
// at map-sized coordinates the cells sharing a lattice point, which reach it through different
// expressions, hashed it to different values, and every threshold on the noise broke along the
// lattice's edges into the straight-edged grey shards and orange wedges seen on the burn.
// Integer arithmetic is exact, so the noise is continuous everywhere. The flaw does not need
// large coordinates: one rounding step in fire_hash's first product scrambles its result, and
// the smoke showed it at inputs of 10 to 30 (card F4b-5).
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

// Two octaves on glow_noise, mostly the broad one: fire_cloud's bold blobs without its seams.
// The events' scorch (ground_burn.gdshader) and the persistent fire's smoke use it (card
// F4b-5: fire_cloud's seams cut the smoke's plume along straight screen-aligned lines).
float glow_cloud(vec2 p) {
	return 0.68 * glow_noise(p) + 0.32 * glow_noise(p * 2.17 + vec2(7.1, 3.3));
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

// The broad fields at `at`, first half: the mask read's warp (xy, metres over
// FIRE_WANDER_REACH, 0.5 none), the char's edge noise and the dried band's width noise.
vec4 glow_fields_a(vec2 at) {
	vec2 lobe_w = vec2(glow_noise(at / 7.0 + vec2(4.1, 7.7)), glow_noise(at / 7.0 + vec2(8.9, 2.6)));
	vec2 ripple = vec2(glow_noise(at / 2.4 + vec2(1.3, 5.9)), glow_noise(at / 2.4 + vec2(6.2, 3.4)));
	vec2 wander = (lobe_w - 0.5) * 2.0 * FIRE_WANDER_M.x + (ripple - 0.5) * 2.0 * FIRE_WANDER_M.y;
	float edge = 0.65 * fire_warped(at / 4.2 + vec2(13.1, -4.7)) + 0.35 * fire_turned(at / 1.3 + vec2(2.7, 6.1));
	float dry_w = fire_warped(at / 4.5 + vec2(-17.3, 3.9));
	return vec4(wander / FIRE_WANDER_REACH * 0.5 + 0.5, edge, dry_w);
}

// The broad fields at `at`, second half: the char's drift, its dark blotches' noise, the ash's
// noise and the breathing's phase noise.
vec4 glow_fields_b(vec2 at) {
	float drift = fire_warped(at / 5.5 + vec2(31.7, 2.9));
	float blotch = fire_warped(at / 3.8 + vec2(-8.3, 15.1));
	float ash = fire_warped(at / FIRE_ASH_M + vec2(41.3, 17.9));
	return vec4(drift, blotch, ash, glow_noise(at * 0.4 + 9.1));
}

// The scales (metres) of the fine fields: the dried band's tufts, the glow's lobes, the coal
// lumps (crust plates) and the cracks. (GLOW_ names: F4b-3's fire_glow, which A/B probes
// compile against this file, defines the FIRE_ ones.)
const float GLOW_TUFT_M = 0.6;
const float GLOW_LOBE_M = 1.3;
const float GLOW_LUMP_M = 0.9;
const float GLOW_CRACK_M = 1.5;
// How much the crack noise's distance from its middle is magnified in the bake (only within
// 0.5 / GLOW_CRACK_GAIN of it is a crack drawn), for precision in eight bits.
const float GLOW_CRACK_GAIN = 4.0;

// The static bake's (fire_ground_bake.gdshader) ranges in eight bits: the burn (below its
// start nothing burns, scorches or dries), the dried band's argument and the ash's.
const vec2 GLOW_BURN_RANGE = vec2(-0.3, 0.7);
const vec2 GLOW_DRY_RANGE = vec2(-0.05, 0.2);
const vec2 GLOW_ASH_RANGE = vec2(-0.5, 1.5);

// `v` stored in `range` (0..1), and back.
float glow_pack(float v, vec2 range) {
	return clamp((v - range.x) / (range.y - range.x), 0.0, 1.0);
}

float glow_unpack(float e, vec2 range) {
	return range.x + e * (range.y - range.x);
}

// The fine fields at `at`: the tufts' noise, the lobes' noise, the coal lumps' noise and the
// crack noise's offset from its middle (times GLOW_CRACK_GAIN, about 0.5, clamped to 0..1).
vec4 glow_fine_fields(vec2 at) {
	float tuft = fire_turned(at / GLOW_TUFT_M + vec2(5.3, -2.1));
	float lobe = fire_warped(at / GLOW_LOBE_M + vec2(23.3, 9.1));
	float lump = fire_warped(at / GLOW_LUMP_M + vec2(77.0, 5.3));
	float crack = fire_warped(at / GLOW_CRACK_M + vec2(-3.7, 29.3));
	return vec4(tuft, lobe, lump, clamp((crack - 0.5) * GLOW_CRACK_GAIN + 0.5, 0.0, 1.0));
}
