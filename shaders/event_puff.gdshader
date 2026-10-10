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
// how bold its edge is (water 1, a firmer body with a soft rim; dust 0, soft all through).
//
// A blob faces the camera, its length along the instance's Y axis as that falls on screen
// (upright for most, along a trunk for its dust, along its flight for a drop). A plume does
// too but stands on its point: a column with a rounded head whose base melts into the water.
// Both are drawn a little toward the camera (an orthographic camera, so nothing moves on
// screen), so one rising from the ground or a fallen crown sits in front of it instead of half
// inside it. A ring lies flat on the surface: a band of foam broken into soft arcs round a
// faint wash. Each melts into whatever it touches (a proximity fade on the depth buffer)
// instead of cutting a hard line across it.
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
// EventPuffs.Kind.
const float PLUME = 1.0;
const float RING = 2.0;

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
	if (puff_kind > RING - 0.5) {
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
		// A plume stands on its point.
		float lift = puff_kind > PLUME - 0.5 ? 0.5 : 0.0;
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
	if (puff_kind > RING - 0.5) {
		float r = length(p) / edge;
		float hole = puff_shape;
		float band = smoothstep(hole - 0.22, hole, r) * (1.0 - smoothstep(0.8, 0.98, r));
		float arcs = 0.65 + 0.35 * sin(4.0 * a + puff_seed * 11.0);
		shape = band * arcs + 0.2 * (1.0 - smoothstep(0.0, hole, r));
	} else if (puff_kind > PLUME - 0.5) {
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
	ALBEDO = mix(body, body * RIM_WATER, rim);
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = clamp(1.0 - smoothstep(behind.z + proximity_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALPHA = COLOR.a * clamp(shape, 0.0, 1.0) * melt;
}
