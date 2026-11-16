// Shared screen-space dither helpers: a 16x16 Bayer threshold and the size of one dither cell in
// render pixels. Included by wind_foliage_include.gdshaderinc (the stipple of an asset without
// authored weights) and painter_tree.gdshaderinc (the canopy fades' keys).
//
// (This file held the per-token occlusion fade as occlusion_fade_include.gdshaderinc until
// 2026-11-15, when the fade was removed: a covered token is found through the token ghost,
// shaders/token_ghost.gdshader, docs/PERFORMANCE.md "Occlusion fade removed".)

// The world viewport's pixel height over 1080 (WorldView, project.godot [shader_globals]): 1 at
// 1080p, 2 at 4K. Dither cells are whole numbers of render pixels that keep their share of the
// screen: world_px_cell() pixels across (1 at 1080p and 1440p, 2 at 4K).
global uniform float world_px_scale;

float world_px_cell() {
	return max(1.0, floor(world_px_scale + 0.5));
}


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
