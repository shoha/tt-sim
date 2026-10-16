shader_type spatial;
// The persistent fire's smoke (FireFieldSmoke places it; design:
// docs/plans/2026-10-11-fire-features/design.md section 4 "Smoke"): a leaning plume of a few bold
// billows over each of the fire's largest blaze clusters. Each instance is one billow, one
// camera-facing quad (the flames' approach, fire_field.gdshader), and the shader alone moves it,
// so nothing runs per billow per frame.
//
// A billow climbs its column on its own clock: born small among the flame tips, it lifts fast,
// slows, grows and leans down the map's wind, then thins away high up; the next billow of its
// column is born a quarter of a life later, so a plume of three or four overlapping billows, small
// at the base and biggest near the top, runs up two or three flame heights and visibly climbs.
// Each climb rolls a new size, a small wander across the wind and a new lobe layout, so the
// column never repeats. The lean is kept at least LEAN_SCREEN across the screen, so a wind that
// blows toward the camera still reads as a lean.
//
// Painted, not modelled: a billow is a cluster of three round lobes (a body and two smaller
// shoulders), each a sphere seen face on, its edge soft but drawn; where lobes overlap the nearer
// one's surface wins, so the cluster shows its lobes rather than one oval. Each lobe takes a fake
// sphere normal and two painted tones by it (emission; only a small share takes the scene's
// light through the fake NORMAL): at dusk and night (foliage_sun's weight, the gate the fire's
// lights use) the side facing down to the fire glows amber, strongest low on the column, and the
// side facing the sky is a cool, slightly luminous blue-grey, so the plume fades from a glowing
// amber base to a blue-grey crown. By day the side facing the sun (foliage_sun's direction) is
// cream and the shade side cool, the base still a little warm from the fire.
// The low billows are thinner and brighter (additive-leaning), so the flames behind them show
// through warm rather than veiled; the smoke draws before the flames (render priority), so the
// flames stay the brightest thing in its frame.
//
// Per instance (FireFieldSmoke.instance_buffer): the origin is where its column's billows are
// born and the basis's uniform scale is the column's unit (metres, its cluster's tallest flame
// scaled by the cluster's size); INSTANCE_CUSTOM is (phase 0..1, seed, life in seconds, unused).
// The column's shape (rise, lean, billow sizes) is set from FireFieldSmoke's constants, the
// wind's direction per map (lean_dir). Colours are linear and shown through the scene's tonemap.
// No fog, as the flames have none (the sunset's dense orange fog washed the painted tones out),
// and no ambient light or sky reflection: through the fake normal the bright sky's radiance laid
// a pale blue-lilac over every billow whatever its colour, even with SPECULAR 0 (round 3's
// diagnostic); round 2's pink at dusk was most likely the same.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled, ambient_light_disabled;

#include "res://shaders/fire_noise.gdshaderinc"

global uniform vec4 foliage_sun;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// The map's wind in world XZ (unit length): the column leans down it.
uniform vec2 lean_dir = vec2(1.0, 0.0);
// A billow's climb over its life and its lean down the wind at the end (a share of the climb),
// in the column's unit.
uniform float rise = 2.4;
uniform float lean = 0.5;
// A billow's diameter when born and when grown (the column's unit).
uniform vec2 billow_size = vec2(0.6, 1.6);
// Metres over which a billow melts into the scene behind it (soft where it meets a tree).
uniform float soft_m = 0.9;

// The sun's weight over which the fire's glow and the night palette fade out (FireLook's light
// gate).
const vec2 NIGHT_GATE = vec2(0.1, 0.35);
// The climb: how fast a billow lifts off and slows (the ease's power), and how its lean grows.
const float RISE_EASE = 1.4;
const float LEAN_EASE = 1.4;
// The least share of the lean that shows across the screen (a wind along the view still leans).
const float LEAN_SCREEN = 0.6;
// A billow's growth over its life (a power of its age: fast at first).
const float GROW_EASE = 0.6;
// The three lobes in the quad's -1..1: (x, y, radius) of the body and the two shoulders, and
// how far each sits in front of the body (so a shoulder overlaps it as a nearer lobe).
// (Round 3's first layout, lobes 0.36-0.6 set further apart, read as small three-eared puffs.)
const vec3 BODY = vec3(0.0, -0.12, 0.66);
const vec3 SHOULDER = vec3(0.32, 0.12, 0.47);
const vec3 CAP = vec3(-0.13, 0.35, 0.43);
const vec2 LOBE_FRONT = vec2(0.14, 0.08);
// How softly the nearer lobe's surface takes over where lobes overlap (the crease between them).
const float CREASE = 0.07;
// The broad noise's warp of the lobes (painted, uneven edges), and its slow churn.
const float WARP = 0.16;
const float CHURN = 0.06;
// A lobe's edge: soft but drawn, this wide inside its circle (the quad's units).
const float EDGE = 0.16;
// The painted tones are emission (linear), so the scene's light cannot wash them out; only
// AMBIENT_SHARE of the colour takes the scene's direct light. At dusk and night: the cool side
// low on the column and at the crown, its sky-facing lift, and the fire's amber on the side
// facing down. (Under the sunset preset's tonemap a cool of (0.1, 0.13, 0.21) already showed a
// pale blue-white, brighter than the amber; these are about 2.5 times darker.)
const float AMBIENT_SHARE = 0.06;
const vec3 NIGHT_COOL_LOW = vec3(0.05, 0.032, 0.03);
const vec3 NIGHT_COOL_TOP = vec3(0.04, 0.055, 0.09);
const float SKY_LIFT = 1.3;
const vec3 FIRE_AMBER = vec3(1.0, 0.34, 0.06);
// By day: the side the sun lights (foliage_sun's direction) cream, the shade side cool, a little
// warmer low on the column.
const vec3 DAY_LIT = vec3(0.5, 0.47, 0.41);
const vec3 DAY_SHADE_LOW = vec3(0.2, 0.18, 0.17);
const vec3 DAY_SHADE_TOP = vec3(0.2, 0.23, 0.29);
// The fire's glow at night and by day, how far up the climb it reaches (it falls to GLOW_HIGH
// of itself by GLOW_REACH of the climb), and how much of a young billow glows all over (it is in
// the flames) rather than only on its down-facing side.
const vec2 GLOW_STRENGTH = vec2(1.5, 0.35);
const float GLOW_REACH = 0.85;
const float GLOW_HIGH = 0.25;
const float GLOW_WRAP = 0.85;
// Opacity: young (low, thin so the flames show through), grown, the fade in and the fade out
// (shares of life); a lobe is a little thinner toward its edge.
const vec2 OPACITY = vec2(0.45, 0.85);
const float FADE_IN = 0.08;
const vec2 FADE_OUT = vec2(0.55, 1.0);
const float EDGE_THIN = 0.25;
// A lamp's (an omni light, the fire's own) share and cap, so a lamp inside the column tints it
// rather than blowing it out; every light wraps a little past the terminator.
const float LAMP_SHARE = 0.35;
const float LAMP_CAP = 0.6;
const float WRAP = 0.35;

// The billow's age (0..1), the climb's draws, and its screen axes (up in view space).
varying flat vec4 v_billow;
varying flat vec2 v_up;
varying float v_age;

void vertex() {
	float unit = length(MODEL_MATRIX[0].xyz);
	vec3 born = MODEL_MATRIX[3].xyz;
	float seed = INSTANCE_CUSTOM.y;
	float clock = TIME / max(INSTANCE_CUSTOM.z, 1.0) + INSTANCE_CUSTOM.x;
	float age = fract(clock);
	float climb = mod(floor(clock), 251.0);
	float roll = fire_hash(vec2(seed * 31.7 + 0.3, climb * 0.137 + 0.5));
	float roll2 = fire_hash(vec2(climb * 0.71 + 3.1, seed * 17.3 + 0.9));
	v_age = age;
	v_billow = vec4(age, roll, roll2, seed);
	// Lifts fast off the fire and slows; leans more the higher it is.
	float up = rise * (1.0 - pow(1.0 - age, RISE_EASE));
	float down_wind = lean * rise * pow(age, LEAN_EASE);
	float wander = (roll2 - 0.5) * 0.35 * (0.2 + age);
	vec2 across_wind = vec2(-lean_dir.y, lean_dir.x) * wander;
	vec3 centre = born + unit * vec3(across_wind.x, up, across_wind.y);
	vec3 view_centre = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
	// The lean in view space, at least LEAN_SCREEN of it across the screen.
	vec3 lean_view = (VIEW_MATRIX * vec4(lean_dir.x, 0.0, lean_dir.y, 0.0)).xyz;
	float side = lean_view.x < 0.0 ? -1.0 : 1.0;
	lean_view.x = side * max(abs(lean_view.x), LEAN_SCREEN);
	view_centre += lean_view * unit * down_wind;
	float across = unit * mix(billow_size.x, billow_size.y, pow(age, GROW_EASE)) * (0.85 + 0.3 * roll);
	vec2 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	up_view = length(up_view) > 1e-4 ? normalize(up_view) : vec2(0.0, 1.0);
	v_up = up_view;
	vec2 right = vec2(up_view.y, -up_view.x);
	MODELVIEW_MATRIX = mat4(
		vec4(right * across, 0.0, 0.0),
		vec4(up_view * across, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(view_centre, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
}

void fragment() {
	float age = v_age;
	float roll = v_billow.y;
	float roll2 = v_billow.z;
	float seed = v_billow.w;
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	// A slow churn: the broad noise warps the lobes and drifts through them as they climb.
	vec2 churn = vec2(seed * 13.0 + roll * 5.0, seed * 7.0 - TIME * CHURN);
	vec2 warp = vec2(fire_cloud(q * 1.4 + churn), fire_cloud(q * 1.4 + churn.yx + 4.1)) - 0.5;
	vec2 p = q + warp * WARP;
	// The lobes, laid out by the climb's draws: the shoulder on one side, the cap leaning the
	// other way, each a little larger or smaller.
	float flip = roll < 0.5 ? -1.0 : 1.0;
	vec3 lobes[3] = vec3[3](
		vec3(BODY.x + (roll2 - 0.5) * 0.08, BODY.y, BODY.z * (0.92 + 0.16 * roll2)),
		vec3(SHOULDER.x * flip, SHOULDER.y + 0.1 * (roll2 - 0.5), SHOULDER.z * (0.85 + 0.3 * fract(roll * 7.3))),
		vec3(CAP.x * flip + 0.1 * (roll - 0.5), CAP.y, CAP.z * (0.85 + 0.3 * fract(roll2 * 5.1)))
	);
	float fronts[3] = float[3](0.0, LOBE_FRONT.x, LOBE_FRONT.y);
	// Each lobe's sphere surface (its height toward the camera) and coverage; the nearest
	// surface wins, softly, and its sphere normal is the billow's.
	float cover = 0.0;
	float nearest = -1.0;
	float heights[3];
	for (int i = 0; i < 3; i++) {
		vec2 d = p - lobes[i].xy;
		float r = lobes[i].z;
		float inside = r * r - dot(d, d);
		heights[i] = inside > 0.0 ? sqrt(inside) + fronts[i] : -1.0;
		nearest = max(nearest, heights[i]);
		cover = max(cover, smoothstep(0.0, EDGE, r - length(d)));
	}
	vec3 n = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		if (heights[i] < 0.0) {
			continue;
		}
		float w = exp((heights[i] - nearest) / CREASE);
		vec2 d = (p - lobes[i].xy) / lobes[i].z;
		n += w * vec3(d, sqrt(max(1.0 - dot(d, d), 0.0)));
	}
	n = length(n) > 1e-4 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	// The fake normal in view space (the quad's right, up and toward the camera), then the world.
	vec2 right = vec2(v_up.y, -v_up.x);
	NORMAL = normalize(vec3(right * n.x + v_up * n.y, n.z));
	vec3 world_n = mat3(INV_VIEW_MATRIX) * NORMAL;
	float below = smoothstep(-0.6, 0.5, -world_n.y);
	float above = smoothstep(-0.25, 0.85, world_n.y);
	// Night and day, the climb's height, and a few broad painted patches.
	float night = 1.0 - smoothstep(NIGHT_GATE.x, NIGHT_GATE.y, foliage_sun.w);
	float high = smoothstep(0.0, 0.8, age);
	float patches = mix(0.9, 1.08, fire_noise(p * 1.6 + vec2(seed * 3.0, roll * 9.0)));
	// The fire's glow: low on the column, on the side facing down (all over while it is young).
	float near_fire = mix(GLOW_HIGH, 1.0, 1.0 - smoothstep(0.05, GLOW_REACH, age));
	float wrap = GLOW_WRAP * (1.0 - smoothstep(0.0, 0.4, age));
	float glow = near_fire * mix(wrap, 1.0, below) * mix(GLOW_STRENGTH.y, GLOW_STRENGTH.x, night);
	// At night the cool side, lifted where it faces the sky (the luminous crown); by day the sun
	// lights one side cream and the sky leaves the other cool.
	vec3 cool = mix(NIGHT_COOL_LOW, NIGHT_COOL_TOP, high) * mix(1.0, SKY_LIFT, above);
	float sun_side = smoothstep(-0.3, 0.9, dot(world_n, foliage_sun.xyz));
	vec3 day = mix(mix(DAY_SHADE_LOW, DAY_SHADE_TOP, high), DAY_LIT, sun_side);
	vec3 colour = (mix(day, cool, night) + FIRE_AMBER * glow) * patches;
	ALBEDO = colour * AMBIENT_SHARE;
	EMISSION = colour;
	// Thin and young low on the column, fading high up.
	float opacity = mix(OPACITY.x, OPACITY.y, smoothstep(0.0, 0.35, age))
		* smoothstep(0.0, FADE_IN, age) * (1.0 - smoothstep(FADE_OUT.x, FADE_OUT.y, age));
	float density = cover * mix(1.0 - EDGE_THIN, 1.0, n.z);
	// Melts into the scene just behind it.
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = smoothstep(0.0, soft_m, VERTEX.z - behind.z);
	ALPHA = clamp(density * opacity * melt, 0.0, 1.0);
}

// Every light wraps a little past the fake normal's terminator; a lamp only a share, capped.
void light() {
	float reach = LIGHT_IS_DIRECTIONAL ? ATTENUATION : min(ATTENUATION, LAMP_CAP) * LAMP_SHARE;
	float lit = clamp((dot(NORMAL, LIGHT) + WRAP) / (1.0 + WRAP), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * reach * lit / PI;
}
