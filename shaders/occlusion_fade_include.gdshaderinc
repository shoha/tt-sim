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

//
// Screen tiles (topic perfaudit, card occfade): looping over every token in every tree and
// map fragment cost 1.3 ms of GPU time with 10 tokens and 4-5 ms with 32, whether or not a
// token was covered. OcclusionFadeManager now bins the tokens into a grid of screen tiles
// for the camera each frame (OcclusionTiles): a tile lists every token whose fade zone
// touches it, so a fragment of the camera's passes tests only its own tile's tokens
// (usually none). The per-token test is unchanged, so the cut-out is the same. A pass from
// any other view (the sun's shadow pass, another viewport) keeps the plain loop over the
// first tokens, as before.

group_uniforms occlusion;
uniform bool enable_occlusion = false;
// One shared RGBAF texture bound once per material by OcclusionFadeManager, read by texel
// index (row-major, OCCLUSION_TEXTURE_WIDTH texels a row). Texels 0 to
// occlusion_token_count - 1: (world x, world y, world z, fade radius) of the first tokens,
// for the plain loop. From occlusion_tile_grid.z: one header per tile (row by row),
// (first list texel, token count, 0, 0). The lists follow: each entry a copy of a token's
// texel, so a tile's tokens cost one fetch each. Updating the texture once per change
// reaches every material at once.
uniform sampler2D occlusion_tokens : filter_nearest, repeat_disable;
uniform float min_alpha = 0.3;    // Target opacity at the center of the fade zone
uniform float floor_threshold = 0.5; // World-space normal Y above this = floor (never fades)
uniform float lofi_pixelation = 0.0; // Pixelation from the lo-fi shader (0 = disabled, aligns dither grid)
uniform float lofi_dither_scale = 1.0; // Dither subdivisions per lo-fi pixel (1 = 1:1 with grid)

// An avatar figure's zone (negative radius in occlusion_tokens): an upright ellipse
// FIGURE_WIDTH as wide as tall, opacity FIGURE_MIN_ALPHA inside FIGURE_CORE of it.
const float FIGURE_WIDTH = 0.6;
const float FIGURE_CORE = 0.55;
const float FIGURE_MIN_ALPHA = 0.0;

// Texels a row of occlusion_tokens (OcclusionTiles.TEXTURE_WIDTH).
const int OCCLUSION_TEXTURE_WIDTH = 256;
// How far, in metres, this pass's view translation may sit from the tile camera's and still
// count as that camera (float noise only: a light's view is metres away).
const float OCCLUSION_TILE_VIEW_EPSILON = 0.01;

// Number of tokens the plain loop reads (texels 0 to count - 1); 0 means no tokens at all.
// Global so the manager sets it once per change for every material (see project.godot
// [shader_globals]).
global uniform int occlusion_token_count;
// The camera the tile lists were built for: its VIEW_MATRIX[3].xyz, and PROJECTION_MATRIX[0][0]
// in w.
global uniform vec4 occlusion_tile_view;
// The tile grid: tiles across, tiles down, the texel index of the first tile header, unused.
// Zero tiles across: no valid lists, every pass runs the plain loop.
global uniform vec4 occlusion_tile_grid;


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


// Texel coordinates of texel `index` of occlusion_tokens (row-major).
ivec2 occlusion_texel(int index) {
	return ivec2(index % OCCLUSION_TEXTURE_WIDTH, index / OCCLUSION_TEXTURE_WIDTH);
}


// The opacity one token asks of a fragment at `vertex_view` (1.0: none). `token_data` is the
// token's texel: world centre, fade radius.
float occlusion_token_alpha(
	vec4 token_data, vec3 vertex_view, mat4 view_matrix, mat4 projection_matrix
) {
	// A negative radius marks an avatar figure (OcclusionFadeManager): its zone is
	// the figure's silhouette, see below.
	bool figure = token_data.w < 0.0;
	float radius = abs(token_data.w);
	if (radius <= 0.0) return 1.0;

	// Transform token world position to view space
	vec3 token_view = (view_matrix * vec4(token_data.xyz, 1.0)).xyz;

	// Skip if this fragment is behind (further from camera than) the token
	if (vertex_view.z <= token_view.z) return 1.0;

	// Orthographic views see every ray parallel, so the view-space xy offset is the
	// separation across the ray. A perspective view fans the rays out: a fragment in
	// front of the token along the same ray has a smaller xy than the token, so the hole
	// would drift off the token away from the screen centre. Scale the fragment's xy to
	// the token's depth first (EyeCanopy.token_plane_xy and OcclusionTiles mirror this).
	vec2 fragment_xy = vertex_view.xy;
	if (projection_matrix[3][3] < 0.5 && vertex_view.z < -0.0001) {
		fragment_xy *= token_view.z / vertex_view.z;
	}
	vec2 offset = fragment_xy - token_view.xy;
	if (figure) {
		// An upright ellipse round the figure (half-height `radius`, half-width
		// FIGURE_WIDTH of it), cleared almost fully over the figure's core and
		// fading back to solid over the outer ring, so the figure reads cleanly
		// and the canopy closes softly round it rather than showing a hard hole.
		float d = length(offset / vec2(radius * FIGURE_WIDTH, radius));
		if (d < 1.0) {
			float fade = 1.0 - smoothstep(FIGURE_CORE, 1.0, d);
			return mix(1.0, FIGURE_MIN_ALPHA, fade);
		}
	} else {
		// Distance in the camera's XY plane (screen-space proximity)
		float dist = length(offset);
		if (dist < radius) {
			// Smooth gradient: full fade at center, zero at edge
			float fade = 1.0 - smoothstep(0.0, radius, dist);
			return mix(1.0, min_alpha, fade);
		}
	}
	return 1.0;
}


// True when this pass draws from the camera the tile lists were built for (its view
// translation and projection scale match), so FRAGCOORD names the right tile. The sun's
// shadow pass and any other view fail it and take the plain loop.
bool occlusion_tiles_match(mat4 view_matrix, mat4 projection_matrix) {
	return occlusion_tile_grid.x > 0.0
		&& distance(view_matrix[3].xyz, occlusion_tile_view.xyz) < OCCLUSION_TILE_VIEW_EPSILON
		&& abs(projection_matrix[0][0] - occlusion_tile_view.w)
			<= 0.0001 * abs(occlusion_tile_view.w);
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
// `projection_matrix` (PROJECTION_MATRIX) tells the projection: a perspective view shrinks the
// fragment's offset to the token's depth before the radius test (see occlusion_token_alpha).
// In the camera's passes only the fragment's tile's tokens are tested (see the header).
void apply_occlusion_fade(
	vec3 world_normal, vec3 vertex_view, mat4 view_matrix, mat4 projection_matrix,
	vec2 frag_coord, vec2 viewport_size
) {
	bool is_floor = world_normal.y > floor_threshold;
	if (!enable_occlusion || occlusion_token_count <= 0 || is_floor) {
		return;
	}

	// The lowest opacity any token asks of this fragment.
	float target_alpha = 1.0;
	if (occlusion_tiles_match(view_matrix, projection_matrix)) {
		ivec2 grid = ivec2(occlusion_tile_grid.xy);
		ivec2 tile = clamp(ivec2(frag_coord / viewport_size * vec2(grid)), ivec2(0), grid - 1);
		int header_index = int(occlusion_tile_grid.z) + tile.y * grid.x + tile.x;
		vec4 header = texelFetch(occlusion_tokens, occlusion_texel(header_index), 0);
		int first = int(header.x);
		int end = first + int(header.y);
		for (int i = first; i < end; i++) {
			vec4 token_data = texelFetch(occlusion_tokens, occlusion_texel(i), 0);
			target_alpha = min(
				target_alpha,
				occlusion_token_alpha(token_data, vertex_view, view_matrix, projection_matrix));
		}
	} else {
		for (int i = 0; i < occlusion_token_count; i++) {
			vec4 token_data = texelFetch(occlusion_tokens, ivec2(i, 0), 0);
			target_alpha = min(
				target_alpha,
				occlusion_token_alpha(token_data, vertex_view, view_matrix, projection_matrix));
		}
	}

	if (target_alpha >= 0.99) {
		return;
	}

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
