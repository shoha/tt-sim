// A fountain's pool and jet (StructureLook.WATER): a luminous cool aqua pulled from the vertex colour,
// unshaded so it never goes dark in the shade of a veranda, with a gentle shimmer: two slow sets of
// soft bands that drift over the surface and lift the tone a little, and a faint rim toward the
// viewer's grazing angle. Cheap: no textures, no screen reads. Seen from both sides (the jet is a
// thin cone).
shader_type spatial;
render_mode unshaded, cull_disabled;

// Linear-light aqua the painted colour is pulled toward, and how far.
uniform vec3 water_tone = vec3(0.22, 0.62, 0.70);
uniform float tone_share : hint_range(0.0, 1.0) = 0.65;
uniform float shimmer : hint_range(0.0, 0.6) = 0.22;
uniform float speed = 0.6;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	vec3 base = mix(col, water_tone, tone_share) * 1.15;
	float t = TIME * speed;
	float a = sin(w_pos.x * 7.0 + w_pos.z * 5.0 + t * 2.0);
	float b = sin(w_pos.x * 4.0 - w_pos.z * 9.0 - t * 1.4 + w_pos.y * 6.0);
	float band = smoothstep(0.55, 1.0, a * b * 0.5 + 0.5);
	float rim = pow(1.0 - clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	ALBEDO = base + vec3(0.35, 0.55, 0.6) * (band * shimmer + rim * 0.25);
}
