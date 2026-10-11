shader_type spatial;
// A terrain event's puff (EventPuffs): one soft, bold shape, a dust cloud where a tree lands or
// a splash where a bridge's plank meets the water. Painterly rather than particulate: a few
// large luminous shapes with a lobed soft edge (seeded per puff by INSTANCE_CUSTOM.x, so no two
// are the same), lighter on top as if lit from above with a cool shade underneath (pale blue
// under white spray, a soft lilac grey under dust: a painted shadow, not a grey one), unshaded
// so the colour stays bright in shade. Colour and alpha come from the per-instance colour.
//
// INSTANCE_CUSTOM: x the seed, y the shape (a blob's or plume's length over its width; a
// ring's hole as a share of its radius), z the kind (EventPuffs.Kind: blob, plume, ring), w
// how bold its edge is (water 1, a firmer body with a soft rim; dust 0, soft all through), or
// for a flame how far through its life it is (0..1).
//
// A blob faces the camera, its length along the instance's Y axis as that falls on screen
// (upright for most, along a trunk for its dust, along its flight for a drop). A plume does
// too but stands on its point: a column with a rounded head whose base melts into the water.
// Both are drawn a little toward the camera (an orthographic camera, so nothing moves on
// screen), so one rising from the ground or a fallen crown sits in front of it instead of half
// inside it. A ring lies flat on the surface: a band of foam broken into soft arcs round a
// faint wash. Each melts into whatever it touches (a proximity fade on the depth buffer)
// instead of cutting a hard line across it.
//
// Fire's flames and embers are luminous, not lit: no shade underneath, their colour running
// from the instance colour at the rim through amber to a pale gold core. A flame stands on its
// base as a plume does: three tongues in flat bands, either banded tongues (flame_banded: the
// fire's noise sways them and cuts them into crisp stepped bands, and erodes them as they age,
// the rule the fire's smoke breaks up by, fire_noise.gdshaderinc) or the painted flipbook
// (FlameAtlas), its frames cross-faded on the shader's clock. Both are seeded, so neighbours
// never lick together. An ember is a small spark with a soft halo that flickers. (A fire's
// smoke is fire_smoke.gdshader's.)
//
// Colours here and in the instance colours are linear, so they show far lighter than their
// numbers: a mid value (0.4) shows pale, which is why the first fire's amber and lilac read as
// cream and pink mist. The fire's are picked as the colour they should show through the
// scene's filmic tonemap, which shows a low value lighter still than raising it to 1/2.2 does
// (0.05 shows about 0.31, 0.15 about 0.54).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// Metres over which a puff fades into the surface behind it.
uniform float proximity_fade = 0.6;
// How far toward the camera a standing puff is drawn, as a share of its half length.
uniform float toward_camera = 1.0;
// The shade's tint under the lit top: cool, so a shaded underside reads as a painted shadow; a
// clear pale blue under water, a light lilac under dust (a deeper one read as grey smoke over
// the grass in the round 4 look).
const vec3 SHADE_DUST = vec3(0.86, 0.82, 0.9);
const vec3 SHADE_WATER = vec3(0.6, 0.75, 0.97);
// Water's soft rim: bluer and clearer than its body, so a plume glows from inside instead of
// sitting flat as a white cut-out.
const vec3 RIM_WATER = vec3(0.72, 0.86, 1.0);
// A fire's colours inward from the instance colour at its rim: amber (shows 1, 0.6, 0.15),
// then a pale gold core (shows 1, 0.9, 0.55).
const vec3 FIRE_AMBER = vec3(1.0, 0.325, 0.015);
const vec3 FIRE_CORE = vec3(1.0, 0.79, 0.27);
// EventPuffs.Kind.
const float PLUME = 1.0;
const float RING = 2.0;
const float FLAME = 3.0;
const float EMBER = 4.0;
// The painted flame flipbook (FlameAtlas, set by EventPuffs.paint_flames): FLAME_FRAMES frames
// side by side, red the heat, green the coverage, row 0 the tips. Cross-faded at FLAME_FPS.
uniform sampler2D flame_atlas : filter_linear, repeat_disable;
const float FLAME_FRAMES = 4.0;
const float FLAME_FPS = 7.0;
// The banded flame instead of the flipbook: three tongues (centre x, height, width as shares of
// the quad), swaying on the fire's noise, cut into flat stepped bands (the rim colour, amber,
// gold, a pale core) at FLAME_BANDS of their depth, eroded by the shared rule from
// FLAME_ERODE_FROM of their life (a flame's age rides in INSTANCE_CUSTOM.w).
uniform bool flame_banded = false;
const vec3 FLAME_TONGUES[3] = {
	vec3(0.0, 1.0, 0.56),
	vec3(-0.44, 0.62, 0.36),
	vec3(0.42, 0.76, 0.38)
};
const vec3 FLAME_BANDS = vec3(0.12, 0.27, 0.44);
const float FLAME_ERODE_FROM = 0.45;

#include "res://shaders/fire_noise.gdshaderinc"

// The banded flame's depth at `uv` (0 its edge, above 0 inside), seeded by `seed`, `age` 0..1.
float banded_flame(vec2 uv, float seed, float age) {
	float v = 1.0 - uv.y;
	float x = uv.x * 2.0 - 1.0;
	float mirror = fract(seed * 5.3) < 0.5 ? -1.0 : 1.0;
	float field = -1.0;
	for (int i = 0; i < 3; i++) {
		vec3 tongue = FLAME_TONGUES[i];
		float sway = (fire_noise(vec2(seed * 9.0 + float(i) * 3.1, v * 2.2 - TIME * 2.4)) - 0.5) * 0.55 * v;
		float vv = v / tongue.y;
		float xx = (x - tongue.x * mirror - sway) / tongue.z;
		float profile = vv < 0.3 ? sqrt(max(0.0, 1.0 - pow((0.3 - vv) / 0.3, 2.0))) : pow(max(0.0, (1.0 - vv) / 0.7), 1.1);
		field = max(field, profile - abs(xx));
	}
	float cloud = fire_cloud(vec2(x * 2.2, v * 2.6 - TIME * 3.0) + seed * 7.0);
	return fire_erode(field, cloud, age, FLAME_ERODE_FROM);
}

bool is_kind(float kind, float which) {
	return abs(kind - which) < 0.5;
}

varying float puff_seed;
varying float puff_shape;
varying float puff_kind;
varying float puff_bold;
// The fragment's height in the puff on screen, -1 at its bottom to 1 at its top.
varying float lit_y;

void vertex() {
	puff_seed = INSTANCE_CUSTOM.x;
	puff_shape = INSTANCE_CUSTOM.y;
	puff_kind = INSTANCE_CUSTOM.z;
	puff_bold = INSTANCE_CUSTOM.w;
	float scale = length(MODEL_MATRIX[0].xyz);
	if (is_kind(puff_kind, RING)) {
		// Lying flat on the surface it spreads over.
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(scale, 0.0, 0.0, 0.0),
			vec4(0.0, 0.0, scale, 0.0),
			vec4(0.0, scale, 0.0, 0.0),
			MODEL_MATRIX[3]
		);
		lit_y = 0.6;
	} else {
		float length_m = scale * max(puff_shape, 0.05);
		vec2 up = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xy;
		up = length(up) > 1e-4 ? normalize(up) : vec2(0.0, 1.0);
		vec2 right = vec2(up.y, -up.x);
		vec3 centre = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
		// A plume stands on its point, a flame on its base.
		float lift = is_kind(puff_kind, PLUME) || is_kind(puff_kind, FLAME) ? 0.5 : 0.0;
		centre.xy += up * length_m * lift;
		centre.z += toward_camera * 0.5 * max(scale, length_m);
		MODELVIEW_MATRIX = mat4(
			vec4(right * scale, 0.0, 0.0),
			vec4(up * length_m, 0.0, 0.0),
			vec4(0.0, 0.0, scale, 0.0),
			vec4(centre, 1.0)
		);
		float half_y = 0.5 * (abs(right.y) * scale + abs(up.y) * length_m);
		lit_y = (VERTEX.x * right.y * scale + VERTEX.y * up.y * length_m) / max(half_y, 1e-4);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// p runs -1..1 across the quad, y from its head (-1) to its foot (1).
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	// Three and five soft lobes: a cloud's outline, not a disc.
	float edge = 1.0 + 0.09 * sin(3.0 * a + puff_seed * 6.283) + 0.05 * sin(5.0 * a + puff_seed * 17.0);
	float inner = mix(0.44, 0.58, puff_bold) * edge;
	float shape;
	// Fire's kinds: how hot this fragment is (0 its rim colour, 1 FIRE_CORE).
	float heat = -1.0;
	if (is_kind(puff_kind, FLAME) && flame_banded) {
		float inside = banded_flame(UV, puff_seed, puff_bold);
		shape = fire_cut(inside);
		heat = 0.45 * fire_cut(inside - FLAME_BANDS.x) + 0.35 * fire_cut(inside - FLAME_BANDS.y) + 0.2 * fire_cut(inside - FLAME_BANDS.z);
	} else if (is_kind(puff_kind, FLAME)) {
		// The painted flame: the flipbook's frames cross-faded on the clock (a quick blend
		// between held frames, so a band's edge licks rather than smears).
		float clock = TIME * FLAME_FPS + puff_seed * FLAME_FRAMES;
		float f0 = mod(floor(clock), FLAME_FRAMES);
		float f1 = mod(f0 + 1.0, FLAME_FRAMES);
		vec2 a0 = texture(flame_atlas, vec2((UV.x + f0) / FLAME_FRAMES, UV.y)).rg;
		vec2 a1 = texture(flame_atlas, vec2((UV.x + f1) / FLAME_FRAMES, UV.y)).rg;
		vec2 paint = mix(a0, a1, smoothstep(0.2, 0.8, fract(clock)));
		shape = paint.g;
		heat = paint.r;
	} else if (is_kind(puff_kind, EMBER)) {
		float r = length(p) / edge;
		shape = (1.0 - smoothstep(0.15, 1.0, r)) * (0.75 + 0.25 * sin(TIME * 14.0 + puff_seed * 30.0));
		heat = 1.0 - smoothstep(0.0, 0.6, r);
	} else if (is_kind(puff_kind, RING)) {
		float r = length(p) / edge;
		float hole = puff_shape;
		float band = smoothstep(hole - 0.22, hole, r) * (1.0 - smoothstep(0.8, 0.98, r));
		float arcs = 0.65 + 0.35 * sin(4.0 * a + puff_seed * 11.0);
		shape = band * arcs + 0.2 * (1.0 - smoothstep(0.0, hole, r));
	} else if (is_kind(puff_kind, PLUME)) {
		// A column: a round head (a circle in metres, whatever the column's height), sides
		// narrowing to the foot like a sheet of water flung up, and a foot that melts into the
		// water. Straight sides read as fingers in the round 4 look.
		float head = min(1.0, 1.0 / max(puff_shape, 0.05));
		float head_y = -1.0 + head;
		float waist = mix(1.0, 0.5, smoothstep(head_y, 1.0, p.y));
		float r = p.y < head_y ? length(vec2(p.x, (p.y - head_y) / head)) : abs(p.x) / waist;
		float foot = 1.0 - smoothstep(1.0 - 0.5 * head, 1.0, p.y);
		shape = (1.0 - smoothstep(inner, 0.98 * edge, r)) * foot;
	} else {
		shape = 1.0 - smoothstep(inner, 0.98 * edge, length(p));
	}
	// Lit from above: the top of the shape brighter, its underside in a cool shade, so it
	// reads as a body in the light rather than a flat cut-out.
	float lit = clamp(0.5 + lit_y * 0.7, 0.0, 1.0);
	vec3 body = COLOR.rgb * mix(mix(SHADE_DUST, SHADE_WATER, puff_bold), vec3(1.12), lit);
	float rim = (1.0 - clamp(shape, 0.0, 1.0)) * puff_bold;
	vec3 fire = mix(COLOR.rgb, FIRE_AMBER, smoothstep(0.0, 0.6, heat));
	fire = mix(fire, FIRE_CORE, smoothstep(0.6, 1.0, heat));
	ALBEDO = heat >= 0.0 ? fire : mix(body, body * RIM_WATER, rim);
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = clamp(1.0 - smoothstep(behind.z + proximity_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALPHA = COLOR.a * clamp(shape, 0.0, 1.0) * melt;
}
