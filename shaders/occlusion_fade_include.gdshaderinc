// Shared occlusion-fade logic used by any spatial shader that should let tokens
// show through when geometry sits between them and the camera. Included by both
// occlusion_fade.gdshader (map geometry) and wind_foliage.gdshader (tree-category
// scattered foliage) so the dither/discard math has exactly one source of truth --
// see OcclusionFadeManager (scenes/states/playing/occlusion_fade_manager.gd) for how
// the uniforms below are populated.
//
// enable_occlusion exists because tree foliage materials are never swapped away
// from this shader when the effect is toggled off (unlike map materials, which get
// replaced back to StandardMaterial3D) -- OcclusionFadeManager flips this uniform
// instead. Map materials leave it at its default (true) and are unaffected.

group_uniforms occlusion;
uniform bool enable_occlusion = true;
uniform int token_count = 0;
uniform vec3 token_positions[32]; // World-space positions (visual center, not feet)
uniform float token_radii[32];    // Per-token fade radius (view-space), derived from collision shape
uniform float min_alpha = 0.3;    // Target opacity at the center of the fade zone
uniform float floor_threshold = 0.5; // World-space normal Y above this = floor (never fades)
uniform float lofi_pixelation = 0.0; // Pixelation from the lo-fi shader (0 = disabled, aligns dither grid)
uniform float lofi_dither_scale = 1.0; // Dither subdivisions per lo-fi pixel (1 = 1:1 with grid)


// 16x16 Bayer ordered dither via recursive construction. Builds from 2x2 -> 4x4 ->
// 8x8 -> 16x16, giving 256 threshold levels for near-smooth gradients that still
// look clean with the lo-fi pixelation grid. Returns a value in [0, 1) based on
// screen/grid pixel position.
float bayer2(float x, float y) {
	// 2x2 base matrix: 0 2 / 3 1
	float v = x + y * 2.0;
	if (v < 0.5) return 0.0;
	if (v < 1.5) return 2.0;
	if (v < 2.5) return 3.0;
	return 1.0;
}

float bayer4(float x, float y) {
	return 4.0 * bayer2(mod(x, 2.0), mod(y, 2.0))
	     + bayer2(floor(x / 2.0), floor(y / 2.0));
}

float bayer8(float x, float y) {
	return 4.0 * bayer4(mod(x, 4.0), mod(y, 4.0))
	     + bayer2(floor(x / 4.0), floor(y / 4.0));
}

float bayer16(vec2 screen_coord) {
	vec2 p = mod(floor(screen_coord), 16.0);
	return (4.0 * bayer8(mod(p.x, 8.0), mod(p.y, 8.0))
	      + bayer2(floor(p.x / 8.0), floor(p.y / 8.0))) / 256.0;
}


// Call from fragment() with the fragment's world-space normal. Discards the
// fragment (dithered, never fully) if it sits between the camera and any tracked
// token within that token's fade radius. No-op if occlusion is disabled, there are
// no tokens, or this fragment belongs to a floor-like surface (see floor_threshold).
void apply_occlusion_fade(vec3 world_normal) {
	bool is_floor = world_normal.y > floor_threshold;
	if (!enable_occlusion || token_count <= 0 || is_floor) {
		return;
	}

	float fade_intensity = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= token_count) break;

		// Transform token world position to view space
		vec3 token_view = (VIEW_MATRIX * vec4(token_positions[i], 1.0)).xyz;

		// Skip if this fragment is behind (further from camera than) the token
		if (VERTEX.z <= token_view.z) continue;

		// Distance in the camera's XY plane (screen-space proximity)
		float dist = distance(VERTEX.xy, token_view.xy);
		float radius = token_radii[i];

		if (dist < radius) {
			// Smooth gradient: full fade at center, zero at edge
			float fade = 1.0 - smoothstep(0.0, radius, dist);
			fade_intensity = max(fade_intensity, fade);
		}
	}

	if (fade_intensity <= 0.01) {
		return;
	}

	float target_alpha = mix(1.0, min_alpha, fade_intensity);

	vec2 dither_coord = FRAGCOORD.xy;
	if (lofi_pixelation > 0.0) {
		float aspect = 16.0 / 9.0;
		vec2 uv_here = FRAGCOORD.xy / VIEWPORT_SIZE;
		vec2 lofi_cell = vec2(lofi_pixelation / aspect, lofi_pixelation);
		// Subdivide each lo-fi pixel into lofi_dither_scale x lofi_dither_scale
		// dither cells. Scale=1 matches the lo-fi grid exactly; scale=2 gives
		// 2x2 finer cells per lo-fi pixel while staying grid-aligned.
		dither_coord = floor(uv_here * lofi_dither_scale / lofi_cell);
	}

	float threshold = bayer16(dither_coord);

	if (target_alpha < threshold) {
		discard;
	}
}
