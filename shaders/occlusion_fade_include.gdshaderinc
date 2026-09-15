// Shared occlusion-fade logic used by any spatial shader that should let tokens
// show through when geometry sits between them and the camera. Included by both
// occlusion_fade.gdshader (map geometry) and wind_foliage.gdshader (tree-category
// scattered foliage) so the dither/discard math has exactly one source of truth --
// see OcclusionFadeManager (scenes/states/playing/occlusion_fade_manager.gd), which
// populates occlusion_tokens (a shared token data texture) and the
// occlusion_token_count global below.
//
// enable_occlusion is opt-in (defaults to false): OcclusionFadeManager sets it to
// true on every material it converts or registers (map surfaces and tree-category
// foliage) and back to false on tree materials in clear(). Materials it never
// touches (grass, anything else that includes this file) therefore skip the loop
// entirely by default -- this matters because occlusion_token_count below is a
// process-global and cannot gate per material on its own; the per-material
// enable_occlusion flag is the only thing keeping an unregistered material out of
// the fade loop.

group_uniforms occlusion;
uniform bool enable_occlusion = false;
// One shared 32x1 RGBAF texture bound once per material by OcclusionFadeManager:
// pixel i = (world x, world y, world z, fade radius) for token i. Updating the
// texture once per tick reaches every material at once, instead of pushing three
// uniform arrays to each of them.
uniform sampler2D occlusion_tokens : filter_nearest, repeat_disable;
uniform float min_alpha = 0.3;    // Target opacity at the center of the fade zone
uniform float floor_threshold = 0.5; // World-space normal Y above this = floor (never fades)
uniform float lofi_pixelation = 0.0; // Pixelation from the lo-fi shader (0 = disabled, aligns dither grid)
uniform float lofi_dither_scale = 1.0; // Dither subdivisions per lo-fi pixel (1 = 1:1 with grid)

// Number of valid entries in occlusion_tokens. Global so the manager sets it once per
// tick for every material (see project.godot [shader_globals]).
global uniform int occlusion_token_count;


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


// Call from fragment() with the fragment's world-space normal, view-space vertex
// position, the view matrix, and the fragment coordinate/viewport size. Discards
// the fragment (dithered, never fully) if it sits between the camera and any
// tracked token within that token's fade radius. No-op if occlusion is disabled,
// there are no tokens, or this fragment belongs to a floor-like surface (see
// floor_threshold). Takes VERTEX/VIEW_MATRIX/FRAGCOORD/VIEWPORT_SIZE as explicit
// parameters rather than reading the built-ins directly -- confirmed via a real
// headless probe that Godot's shader compiler does not resolve stage built-ins
// referenced inside a plain (non-vertex/fragment) function, even one called from
// fragment(); the caller must read them itself and pass the values in.
void apply_occlusion_fade(
	vec3 world_normal, vec3 vertex_view, mat4 view_matrix, vec2 frag_coord, vec2 viewport_size
) {
	bool is_floor = world_normal.y > floor_threshold;
	if (!enable_occlusion || occlusion_token_count <= 0 || is_floor) {
		return;
	}

	float fade_intensity = 0.0;
	for (int i = 0; i < 32; i++) {
		if (i >= occlusion_token_count) break;

		vec4 token_data = texelFetch(occlusion_tokens, ivec2(i, 0), 0);
		float radius = token_data.w;
		if (radius <= 0.0) continue;

		// Transform token world position to view space
		vec3 token_view = (view_matrix * vec4(token_data.xyz, 1.0)).xyz;

		// Skip if this fragment is behind (further from camera than) the token
		if (vertex_view.z <= token_view.z) continue;

		// Distance in the camera's XY plane (screen-space proximity)
		float dist = distance(vertex_view.xy, token_view.xy);

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

	vec2 dither_coord = frag_coord;
	if (lofi_pixelation > 0.0) {
		float aspect = 16.0 / 9.0;
		vec2 uv_here = frag_coord / viewport_size;
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
