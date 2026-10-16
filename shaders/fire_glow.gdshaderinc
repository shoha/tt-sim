// FIRE: the burn and ember glow of persistent ground fire, on the ground itself (design:
// docs/plans/2026-10-11-fire-features/design.md section 4, option C of the F3 probe). Included
// by authored_ground.gdshaderinc for the map's ground only (the skirt never burns): fragment()
// takes fire_glow(world_xz, TIME), darkens ALBEDO toward FIRE_CHAR by its alpha and sets
// EMISSION to its colour. The document's fire_mask is bound as an R8 texture on the sample grid
// (FireLook.bind_glow; fire_present 0 skips everything) and read through a cubic B-spline
// (texture_bspline), a blur of about a metre that keeps the cut tones' edges smooth curves
// instead of the bilinear facets the probe showed. Needs weight_uv and texture_bspline from the
// including shader.
//
// Two layers, both cut crisp (fire_cut) out of the fire's shared noise:
//   - Embers, over the whole burn and alone in the ember band (40-110, where FireField draws no
//     flames): the ground charred dark, lumpy patches about 1.5 m across glowing in two stepped
//     tones (a deep red rim, an orange heart) that cover more of the ground the hotter it burns
//     and breathe slowly (about 0.2-0.4 Hz, the phase by place), and small specks that pulse on
//     their own clocks. They fill what the flames leave open, so a gap between clumps reads as
//     a bed of coals rather than dead ash.
//   - Hot patches under the flames and the blaze: bold shapes about 3 m across in a deep,
//     luminous orange, a gold core in the blaze's hottest that flickers, drifting slowly.
// Colours are linear emission, picked for the filmic tonemap: saturated, so they read as glow
// over the char instead of the peach wash a pale colour over light ash gave in the probe.

#include "res://shaders/fire_noise.gdshaderinc"

uniform int fire_present = 0;
uniform sampler2D fire_mask_map : hint_default_black, filter_linear, repeat_disable;

// The bands' starts as mask values (FireField.EMBER_MIN and FLAME_MIN over 255).
const float FIRE_EMBER_T = 0.157;
const float FIRE_FLAME_T = 0.431;
// What a fully charred ground's albedo is multiplied by: a warm near-black, not grey.
const vec3 FIRE_CHAR = vec3(0.32, 0.2, 0.14);
// The smoulder between the ember patches, a share of FIRE_RED.
const float FIRE_SMOULDER = 0.14;
const vec3 FIRE_RED = vec3(0.5, 0.035, 0.004);
const vec3 FIRE_HEART = vec3(0.95, 0.15, 0.007);
const vec3 FIRE_HOT = vec3(1.0, 0.22, 0.01);
const vec3 FIRE_GOLD = vec3(1.0, 0.5, 0.08);
const vec3 FIRE_SPECK = vec3(1.0, 0.4, 0.05);
// Ember patch sizes (metres), and the share of the ground they cover at the ember band's start
// and from the flames band on (as noise thresholds).
const float FIRE_LUMP_M = 1.5;
const vec2 FIRE_COVER = vec2(0.68, 0.56);
// The orange heart's step inside a patch.
const float FIRE_HEART_STEP = 0.08;
// The breathing's rate (radians a second: about 0.3 Hz).
const float FIRE_BREATHE = 1.9;
// Specks: one cell this wide in FIRE_SPECK_SHARE carries one.
const float FIRE_SPECK_CELL_M = 0.32;
const float FIRE_SPECK_SHARE = 0.09;
// Hot patches: their noise's reach on the heat, the thresholds of the hot tone and the core, and
// how far past its edge a patch takes to brighten from red to orange.
const float FIRE_PATCH_REACH = 0.7;
const float FIRE_HOT_FROM = 0.8;
const float FIRE_HOT_RAMP = 0.12;
const float FIRE_CORE_FROM = 0.95;

// The fire at map-frame XZ `at` at time `clock`: rgb its glow (emission), a how charred the
// ground is (0..1).
vec4 fire_glow(vec2 at, float clock) {
	if (fire_present == 0) {
		return vec4(0.0);
	}
	vec2 uv = weight_uv(at, vec2(textureSize(fire_mask_map, 0)));
	// One plain fetch first: most of a map does not burn.
	if (texture(fire_mask_map, uv).r < 0.03) {
		return vec4(0.0);
	}
	float heat = texture_bspline(fire_mask_map, uv).r;
	// The burn's outline wanders with a lumpy noise and is cut crisp.
	float outline = fire_cloud(at / FIRE_LUMP_M + vec2(31.7, -12.3));
	float burnt = fire_cut(heat + (outline - 0.5) * 0.18 - FIRE_EMBER_T);
	// Embers: lumpy patches, more of the ground the hotter, in two stepped tones, breathing.
	float ember_heat = clamp((heat - FIRE_EMBER_T) / (FIRE_FLAME_T - FIRE_EMBER_T), 0.0, 1.0);
	float lumps = fire_cloud(at / FIRE_LUMP_M + vec2(clock * 0.03, -clock * 0.02));
	float cover = lumps - mix(FIRE_COVER.x, FIRE_COVER.y, ember_heat);
	float glowing = fire_cut(cover) * burnt;
	float heart = fire_cut(cover - FIRE_HEART_STEP) * burnt;
	// One rate everywhere, the phase by place (a rate that varied by place wound the phase up
	// into fine ripples as the clock ran on).
	float breathe = 0.72 + 0.28 * sin(clock * FIRE_BREATHE + fire_noise(at * 0.4 + 9.1) * 12.0);
	vec3 glow = (FIRE_RED * glowing + (FIRE_HEART - FIRE_RED) * heart) * breathe;
	// A dim smoulder under all of it, so the char between patches is warm, never dead grey.
	glow += FIRE_RED * FIRE_SMOULDER * burnt * (1.0 - glowing);
	// Specks: a few small cells carry a glowing dot that pulses on its own clock.
	vec2 sp = at / FIRE_SPECK_CELL_M;
	vec2 cell = floor(sp);
	float pick = fire_hash(cell + vec2(7.3, 1.9));
	vec2 spot = vec2(fire_hash(cell + vec2(3.1, 9.7)), fire_hash(cell + vec2(8.5, 2.3))) * 0.6 + 0.2;
	float speck = 1.0 - smoothstep(0.07, 0.15, length(fract(sp) - spot));
	// Gathered where a broad noise is high, so they read as embers, not confetti.
	speck *= step(1.0 - FIRE_SPECK_SHARE, pick) * step(0.45, fire_noise(at * 0.5 + 3.7)) * burnt;
	glow += FIRE_SPECK * speck * (0.6 + 0.8 * sin(clock * (2.5 + pick * 5.0) + pick * 60.0));
	// Under the flames and the blaze: bold hot patches, a flickering gold core in the hottest.
	float flaming = smoothstep(FIRE_FLAME_T - 0.06, FIRE_FLAME_T + 0.14, heat);
	float patches = fire_cloud(at * 0.33 + vec2(clock * 0.04, -clock * 0.03));
	float e = heat + (patches - 0.5) * FIRE_PATCH_REACH;
	float flick = fire_cloud(at * 0.8 + vec2(-clock * 0.15, clock * 0.11));
	float hot = fire_cut(e - FIRE_HOT_FROM) * flaming * burnt;
	float core = fire_cut(e - FIRE_CORE_FROM) * smoothstep(0.35, 0.55, flick) * hot;
	// A patch glows deep red at its crisp edge and brightens to orange inside: a luminous shape,
	// not a flat pool.
	float inner = smoothstep(FIRE_HOT_FROM, FIRE_HOT_FROM + FIRE_HOT_RAMP, e);
	vec3 hot_colour = mix(FIRE_RED * 1.4, FIRE_HOT * (0.85 + 0.15 * flick), inner);
	glow = mix(glow, hot_colour, hot);
	glow = mix(glow, FIRE_GOLD, core);
	return vec4(max(glow, vec3(0.0)), burnt * mix(0.8, 0.95, max(hot, glowing)));
}
