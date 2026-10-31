// The halo round a lantern (StructureGlow): a camera-facing quad drawn from four vertices that all sit
// at the pane's centre. UV is the corner (-1 or 1 each way), UV2.x the quad's half-size in metres. It
// is painted in two soft-edged shapes, a small bright core and a wide amber halo, and blended OVER the
// scene (not added), so it stays a warm gold disc in bright daylight where an additive glow would wash
// to nothing against a lit meadow; the colour runs a little past 1 so the environment's glow lifts the
// core too. Steady: tt-sim has no day and night. Drawn a little toward the camera so the post and the
// roof behind the lantern do not cut the disc in half, and never into the depth buffer.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 halo_colour : source_color = vec3(1.0, 0.56, 0.16);
uniform vec3 core_colour : source_color = vec3(1.0, 0.82, 0.4);
// How opaque the wide halo is at its brightest, and how opaque the core is.
uniform float halo_alpha : hint_range(0.0, 1.0) = 0.75;
uniform float core_alpha : hint_range(0.0, 1.0) = 0.9;
// Where the core ends (as a share of the quad's half-size) and how hard the halo falls away.
uniform float core_radius : hint_range(0.05, 0.6) = 0.24;
uniform float halo_falloff : hint_range(0.5, 4.0) = 1.5;
// The disc's push toward the camera as a share of its half-size.
uniform float lift : hint_range(0.0, 1.0) = 0.5;
uniform float energy : hint_range(0.5, 3.0) = 1.3;

varying vec2 corner;

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
	// The camera's own back axis, so the push never moves the disc on the screen (an orthographic
	// camera has no single point the rays leave from).
	vec3 toward = normalize(INV_VIEW_MATRIX[2].xyz);
	float half_size = UV2.x;
	vec3 world = centre + toward * half_size * lift + (right * UV.x + up * UV.y) * half_size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	corner = UV;
}

void fragment() {
	float d = length(corner);
	float halo = pow(1.0 - smoothstep(0.0, 1.0, d), halo_falloff) * halo_alpha;
	float core = (1.0 - smoothstep(core_radius * 0.55, core_radius, d)) * core_alpha;
	float a = clamp(halo + core * (1.0 - halo) , 0.0, 1.0);
	vec3 col = mix(halo_colour, core_colour, clamp(core / max(a, 0.001), 0.0, 1.0));
	ALBEDO = col * energy;
	ALPHA = a;
}
