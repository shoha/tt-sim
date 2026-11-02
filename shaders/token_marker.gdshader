shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

// The top-down token marker (scenes/board_token/token_markers.gd): a ring drawn on top of the
// board around a token, in the token's own colour between two thin ink lines so it reads on
// grass, stone and roof alike. One quad per token in a MultiMesh, turned to face the camera, the
// instance colour is the ring colour and its alpha the strength (the fade-in with pitch, and the
// GM's dimmed view of a token hidden from players).

uniform vec4 ink : source_color = vec4(0.10, 0.06, 0.14, 0.92);

varying vec4 ring_colour;

void vertex() {
	ring_colour = COLOR;
}

void fragment() {
	// 0 at the quad's centre, 1 at the middle of its edges.
	float d = length(UV - vec2(0.5)) * 2.0;
	float aa = max(fwidth(d), 0.002);
	// The ring: an ink line outside and inside a band of the token's colour.
	float cover = smoothstep(0.54 - aa, 0.54 + aa, d) * (1.0 - smoothstep(0.98 - aa, 0.98 + aa, d));
	float band = smoothstep(0.62 - aa, 0.62 + aa, d) * (1.0 - smoothstep(0.87 - aa, 0.87 + aa, d));
	ALBEDO = mix(ink.rgb, ring_colour.rgb, band);
	ALPHA = cover * mix(ink.a, 1.0, band) * ring_colour.a;
}
