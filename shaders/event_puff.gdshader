shader_type spatial;
// A terrain event's puff (EventPuffs): one soft, bold shape facing the camera, a dust cloud
// where a tree lands or a splash where a bridge's plank meets the water. Painterly rather than
// particulate: a few large luminous blobs with a lobed soft edge (seeded per puff by
// INSTANCE_CUSTOM.x, so no two are the same), lighter on top as if lit from above, unshaded so
// the colour stays bright in shade. It melts into the ground it touches (a proximity fade on
// the depth buffer) instead of cutting a hard line across it. Colour and alpha come from the
// MultiMesh's per-instance colour.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// Metres over which a puff fades into the surface behind it.
uniform float proximity_fade = 0.6;

varying float puff_seed;

void vertex() {
	// Billboard keeping the instance's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	float scale = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(scale, 0.0, 0.0, 0.0),
		vec4(0.0, scale, 0.0, 0.0),
		vec4(0.0, 0.0, scale, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	puff_seed = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	// Three and five soft lobes: a cloud's outline, not a disc.
	float edge = 1.0 + 0.09 * sin(3.0 * a + puff_seed * 6.283) + 0.05 * sin(5.0 * a + puff_seed * 17.0);
	float shape = 1.0 - smoothstep(0.36 * edge, 0.98 * edge, r);
	// Lit from above: the top of the shape brighter, its underside in a cooler shade, so it
	// reads as a body in the light rather than a flat cut-out.
	float light = mix(0.78, 1.1, clamp(0.5 - p.y * 0.7, 0.0, 1.0));
	ALBEDO = COLOR.rgb * light;
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = clamp(1.0 - smoothstep(behind.z + proximity_fade, behind.z, VERTEX.z), 0.0, 1.0);
	ALPHA = COLOR.a * shape * melt;
}
