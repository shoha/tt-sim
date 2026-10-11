shader_type spatial;
// A fire's smoke (SmokePuffs): solid, lit billows made of the same stuff as the tree crowns
// rather than a translucent haze. Each is a camera-facing card that draws a heap of a few balls,
// every pixel given the normal and the depth of the ball's surface in front of it (a
// spherical-normal billboard), the normal pushed about by the fire's noise so the balls read
// as painted lumps rather than plastic. The scene's sun lights it with a soft two-tone ramp (a
// lit side and a shade side with a short soft step between) and its underside is painted a
// cooler, darker tone, the crowns' own read, so a billow sits in the light as a crown does.
// Its depth is the balls' own, so balls of one billow cut into each other and into the trees as
// solid things do.
//
// Opaque with a crisp, antialiased edge (alpha scissor with alpha to coverage, as the foliage
// cards are), it thins by erosion, never by fading: the fire's one noise eats it from the low
// parts up as it ages (fire_noise.gdshaderinc, the rule its flames break up by too), so a late
// billow is a few bold pieces shrinking away.
//
// Its palette runs on from the flames' (event_puff.gdshader): warm charcoal with an ember glow
// at its foot while young and close to the fire, then a pale lilac grey as it rises and ages.
// INSTANCE_CUSTOM: x the seed, z its age (0..1). Colours are linear and shown through the
// filmic tonemap (FireSweep's header).
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_disabled, alpha_to_coverage;

#include "res://shaders/fire_noise.gdshaderinc"

// Young smoke close to the fire and its old pale body (lit: its lit side shows a warm pale
// grey, its shade side a cool lilac), the tone its underside is painted, and the ember glow at
// a young billow's foot.
const vec3 SMOKE_DARK = vec3(0.035, 0.022, 0.02);
const vec3 SMOKE_PALE = vec3(0.34, 0.31, 0.35);
const vec3 SMOKE_UNDER = vec3(0.5, 0.45, 0.68);
const vec3 SMOKE_GLOW = vec3(0.9, 0.22, 0.03);
// The two-tone ramp: lit from where the wrapped light crosses RAMP.x to RAMP.y.
const vec2 RAMP = vec2(0.42, 0.6);
// The erosion starts this far through a billow's life.
const float ERODE_FROM = 0.2;
// How far the noise tips a ball's normal (its painted lumps).
const float NORMAL_LUMP = 1.1;
// The heap in the card's -1..1 (y up): centre, radius, and how far in front it stands.
const vec4 BALLS[4] = {
	vec4(0.0, -0.05, 0.55, 0.0),
	vec4(0.43, -0.2, 0.37, 0.06),
	vec4(-0.46, -0.24, 0.35, 0.1),
	vec4(0.1, 0.38, 0.36, -0.04)
};

varying float puff_seed;
varying float puff_age;
varying float puff_metres;

void vertex() {
	puff_seed = INSTANCE_CUSTOM.x;
	puff_age = INSTANCE_CUSTOM.z;
	float scale = length(MODEL_MATRIX[0].xyz);
	puff_metres = scale;
	vec3 centre = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	MODELVIEW_MATRIX = mat4(
		vec4(scale, 0.0, 0.0, 0.0),
		vec4(0.0, scale, 0.0, 0.0),
		vec4(0.0, 0.0, scale, 0.0),
		vec4(centre, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(1.0);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	float mirror = fract(puff_seed * 5.3) < 0.5 ? -1.0 : 1.0;
	float field = -1.0;
	float best = -10.0;
	vec3 n = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 4; i++) {
		vec4 ball = BALLS[i];
		float draw = fract(puff_seed * (3.7 + 1.9 * float(i)) + 0.37 * float(i));
		vec2 d = (p - ball.xy * vec2(mirror, 1.0)) / (ball.z * (0.9 + 0.2 * draw));
		float r = length(d);
		field = max(field, (1.0 - r) * min(1.0, ball.z / 0.4));
		if (r < 1.0) {
			float z = ball.w + ball.z * sqrt(1.0 - r * r);
			if (z > best) {
				best = z;
				n = vec3(d, sqrt(1.0 - r * r));
			}
		}
	}
	float cloud = fire_cloud(p * 1.7 + vec2(0.0, -puff_age * 0.6) + puff_seed * 13.0);
	vec2 q = p * 2.4 + puff_seed * 5.0;
	vec2 tip = vec2(fire_noise(q), fire_noise(q + vec2(5.2, 1.3))) - 0.5;
	n = normalize(vec3(n.xy + tip * NORMAL_LUMP, n.z));
	ALPHA = fire_cut(fire_erode(field, cloud, puff_age, ERODE_FROM));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	NORMAL = n;
	vec3 at = VERTEX + vec3(0.0, 0.0, max(best, 0.0) * puff_metres * 0.5);
	vec4 clip = PROJECTION_MATRIX * vec4(at, 1.0);
	DEPTH = clip.z / clip.w;
	// The palette over its life (its top a little ahead of its foot), its underside painted
	// cooler and darker by how far its surface faces down.
	float pale = smoothstep(0.08, 0.6, puff_age + 0.1 * p.y);
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float facing_up = smoothstep(-0.55, 0.35, dot(n, up));
	ALBEDO = mix(SMOKE_DARK, SMOKE_PALE, pale) * mix(SMOKE_UNDER, vec3(1.0), facing_up) * COLOR.rgb;
	float glow = (1.0 - smoothstep(0.0, 0.3, puff_age)) * smoothstep(0.0, -0.8, p.y);
	EMISSION = SMOKE_GLOW * glow * 0.8;
}

// The crowns' soft two-tone read: a lit side and a shade side with a short soft step.
void light() {
	float wrapped = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = smoothstep(RAMP.x, RAMP.y, wrapped);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
