shader_type spatial;
// The persistent fire's smoke (FireFieldSmoke places it; design:
// docs/plans/2026-10-11-fire-features/design.md section 4 "Smoke"): a slow leaning column of a
// few soft billows over each of the fire's largest blaze clusters. Each instance is one billow,
// one camera-facing quad (the flames' approach, fire_field.gdshader), and the shader alone moves
// it, so nothing runs per billow per frame.
//
// A billow climbs its column on its own clock: born at the flame tips, it lifts and grows over a
// life of about 12 seconds while it slows and leans down the map's wind, then thins away; the
// next billow of its column is born a sixth of a life later, so a column of overlapping billows
// runs from the fire up to two or three flame heights. Each climb rolls a new size, a small
// wander across the wind and a new lobe layout, so the column never repeats.
//
// Painted, not modelled: a billow is one soft shape, three soft lobes summed (no hard
// intersection between them) and warped by the fire's broad noise (fire_noise.gdshaderinc), its
// edge a wide alpha falloff that widens as it ages, so it softens away instead of breaking up.
// It takes every light flat, with no terminator. Its colour runs by its climb: a warm underside
// lit by the fire below (emission, fading as it rises), a warm rose body, a soft blue-grey top
// as it ages; by day the body is a pale cream and the fire's glow is weaker (foliage_sun's
// weight, the gate the fire's lights use). It is translucent, so the flames and the ground
// tint it, and it draws before the flames (render priority), so the flames stay the brightest
// thing in its frame.
//
// Per instance (FireFieldSmoke.instance_buffer): the origin is where its column's billows are
// born and the basis's uniform scale is the column's unit (metres, its cluster's tallest flame
// scaled by the cluster's size); INSTANCE_CUSTOM is (phase 0..1, seed, life in seconds, unused).
// The column's shape (rise, lean, billow sizes) is set from FireFieldSmoke's constants, the
// wind's direction per map (lean_dir). Colours are linear and shown through the filmic tonemap.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/fire_noise.gdshaderinc"

global uniform vec4 foliage_sun;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// The map's wind in world XZ (unit length): the column leans down it.
uniform vec2 lean_dir = vec2(1.0, 0.0);
// A billow's climb over its life and its lean down the wind at the end (a share of the climb),
// in the column's unit.
uniform float rise = 1.5;
uniform float lean = 0.55;
// A billow's diameter when born and when grown (the column's unit).
uniform vec2 billow_size = vec2(0.8, 1.45);
// Metres over which a billow melts into the scene behind it (soft where it meets a tree).
uniform float soft_m = 0.9;

// The sun's weight over which the fire's glow and the night palette fade out (FireLook's light
// gate).
const vec2 NIGHT_GATE = vec2(0.1, 0.35);
// The body's palette (albedo, linear) at dusk and night: low and young, mid, high and old; and
// by day.
// (Round 2's first palettes, near 0.9, lit to a pink-white pillar at dusk under the day sky's
// ambient and a white one by day; these are darker so the fire's glow and the blue top read.)
const vec3 NIGHT_LOW = vec3(0.55, 0.32, 0.26);
const vec3 NIGHT_MID = vec3(0.5, 0.36, 0.42);
const vec3 NIGHT_TOP = vec3(0.3, 0.34, 0.48);
const vec3 DAY_LOW = vec3(0.78, 0.68, 0.6);
const vec3 DAY_MID = vec3(0.74, 0.7, 0.72);
const vec3 DAY_TOP = vec3(0.6, 0.66, 0.78);
// The fire's light under a billow: its colour, strength at night and by day, how far up a
// billow it reaches (the quad's -1..1), and the share of its climb over which it fades to
// GLOW_HIGH.
const vec3 FIRE_UNDER = vec3(1.0, 0.36, 0.07);
const vec2 GLOW_STRENGTH = vec2(1.3, 0.3);
const vec2 GLOW_REACH = vec2(-0.5, 0.45);
const float GLOW_FADE = 0.8;
const float GLOW_HIGH = 0.25;
// Each billow's own light: its underside in shade, its top lit by the sky (shares of its
// colour), so a column reads as a stack of billows rather than one smear.
const vec2 BILLOW_SHADE = vec2(0.6, 1.15);
// A billow's own colour as emission, so its body stays luminous where the light is low.
const float FILL = 0.1;
// How much each light reaches the billow (flat, no terminator), and a lamp's (an omni light,
// the fire's own) share and cap, so a lamp inside the column tints it rather than blowing it out.
const float FLAT = 0.8;
const float LAMP_SHARE = 0.25;
const float LAMP_CAP = 0.6;
// The shape's soft edge: the field's floor, and its falloff's width young and old.
const vec3 EDGE = vec3(0.12, 0.32, 0.7);
// Opacity at its densest (young) and when grown, the fade in and the fade out (shares of life).
const vec2 OPACITY = vec2(0.75, 0.5);
const float FADE_IN = 0.1;
const vec2 FADE_OUT = vec2(0.38, 0.98);
// The billow's quad is a little taller than wide.
const float TALL = 1.12;

// The billow's age (0..1), the climb's draw, the column's unit, the instance's seed.
varying flat vec4 v_billow;
varying float v_age;

// A soft lobe: 1 at its centre, falling as a gaussian to about 0.05 at 1.7 radii.
float lobe(vec2 p, vec2 centre, float radius) {
	vec2 d = (p - centre) / radius;
	return exp(-dot(d, d));
}

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
	v_billow = vec4(age, roll, unit, seed);
	// Lifts fast off the fire and slows; leans more the higher it is.
	float up = rise * (1.0 - pow(1.0 - age, 1.6));
	float down_wind = lean * rise * pow(age, 1.25);
	float wander = (roll2 - 0.5) * 0.4 * (0.25 + age);
	vec2 side = lean_dir * down_wind + vec2(-lean_dir.y, lean_dir.x) * wander;
	vec3 centre = born + unit * vec3(side.x, up, side.y);
	float across = unit * mix(billow_size.x, billow_size.y, sqrt(age)) * (0.85 + 0.3 * roll);
	vec3 view_centre = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
	vec2 up_view = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	up_view = length(up_view) > 1e-4 ? normalize(up_view) : vec2(0.0, 1.0);
	vec2 right = vec2(up_view.y, -up_view.x);
	MODELVIEW_MATRIX = mat4(
		vec4(right * across, 0.0, 0.0),
		vec4(up_view * across * TALL, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(view_centre, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float age = v_age;
	float roll = v_billow.y;
	float seed = v_billow.w;
	vec2 q = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	// A slow churn: the broad noise warps the billow and drifts through it as it climbs.
	vec2 churn = vec2(seed * 13.0 + roll * 5.0, seed * 7.0 - TIME * 0.05);
	vec2 warp = vec2(fire_cloud(q * 1.2 + churn), fire_cloud(q * 1.2 + churn.yx + 4.1)) - 0.5;
	vec2 p = q + warp * 0.36;
	// Three lobes: a body low in the quad, two shoulders turned by the climb's draw; a round
	// window keeps the warped shape off the quad's edges.
	float turn = roll * 6.2832 + age * 0.9;
	vec2 shoulder = vec2(cos(turn), abs(sin(turn)) * 0.6 + 0.1) * 0.3;
	float field = lobe(p, vec2(0.0, -0.08), 0.62)
		+ 0.8 * lobe(p, shoulder, 0.5)
		+ 0.7 * lobe(p, vec2(-shoulder.x * 0.9, 0.2 - shoulder.y * 0.4), 0.44);
	field *= 1.0 - smoothstep(0.7, 1.0, length(q));
	float density = smoothstep(EDGE.x, EDGE.x + mix(EDGE.y, EDGE.z, age), field);
	float opacity = mix(OPACITY.x, OPACITY.y, age) * smoothstep(0.0, FADE_IN, age)
		* (1.0 - smoothstep(FADE_OUT.x, FADE_OUT.y, age));
	// The palette by the climb, paler toward the billow's top (the sky above it), with a few
	// broad painted patches.
	float night = 1.0 - smoothstep(NIGHT_GATE.x, NIGHT_GATE.y, foliage_sun.w);
	vec3 low = mix(DAY_LOW, NIGHT_LOW, night);
	vec3 mid = mix(DAY_MID, NIGHT_MID, night);
	vec3 top = mix(DAY_TOP, NIGHT_TOP, night);
	vec3 body = mix(mix(low, mid, smoothstep(0.0, 0.4, age)), top, smoothstep(0.35, 0.85, age));
	float patches = fire_noise(p * 1.7 + vec2(seed * 3.0, roll * 9.0));
	float lit = smoothstep(-0.5, 0.6, q.y + warp.y * 0.8);
	body *= mix(BILLOW_SHADE.x, BILLOW_SHADE.y, lit) * mix(0.93, 1.05, patches);
	// The fire's light on the underside, strongest low on the column.
	float under = 1.0 - smoothstep(GLOW_REACH.x, GLOW_REACH.y, q.y + (patches - 0.5) * 0.6);
	float near = mix(GLOW_HIGH, 1.0, 1.0 - smoothstep(0.0, GLOW_FADE, age));
	float glow = under * near * mix(GLOW_STRENGTH.y, GLOW_STRENGTH.x, night);
	ALBEDO = mix(body, NIGHT_LOW, 0.5 * glow);
	EMISSION = FIRE_UNDER * glow + ALBEDO * FILL;
	// Melts into the scene just behind it.
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = smoothstep(0.0, soft_m, VERTEX.z - behind.z);
	ALPHA = clamp(density * opacity * melt, 0.0, 1.0);
}

// Every light reaches the billow flat (no terminator); a lamp only a share, capped.
void light() {
	float reach = LIGHT_IS_DIRECTIONAL ? ATTENUATION : min(ATTENUATION, LAMP_CAP) * LAMP_SHARE;
	DIFFUSE_LIGHT += LIGHT_COLOR * reach * FLAT / PI;
}
