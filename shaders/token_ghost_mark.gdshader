shader_type spatial;
render_mode unshaded, depth_draw_always, cull_back, blend_mix, shadows_disabled;

/*
 * Token ghost, the mask pass (TokenGhost, shaders/token_ghost.gdshader is its other half)
 * ======================================================================================
 *
 * Draws nothing a player can see. It marks every pixel the token's own meshes cover by writing
 * the nearest possible depth there (DEPTH = 1.0 with the reversed depth range; the test is
 * enabled so the write happens, and the written value always passes), at render priority
 * before the line pass. The line pass then writes a depth just short of the nearest, so its
 * fragments fail the depth test on every marked pixel: the outline survives only outside the
 * union of the token's meshes, whatever part overlaps whatever, and no line is drawn inside
 * the body. One material is shared by every mesh of every token (no per-mesh parameter).
 *
 * The depth buffer under a token's pixels is left at the nearest depth for the transparent
 * passes that follow it (the ghost draws late, after the foliage and the water).
 */

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
	DEPTH = 1.0;
}
