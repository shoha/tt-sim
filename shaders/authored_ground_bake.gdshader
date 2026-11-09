// The ground clipmap's bake (GroundClipmap; CLIPMAP in authored_ground.gdshaderinc): the same
// layer blend as the ground, drawn top-down and unshaded into a window strip. bake_pass 0 writes
// the lit albedo with AO in alpha, 1 the normal and roughness. Premultiplied so alpha carries
// data into a cleared target.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_always, cull_back;

#define GROUND_BAKE_OUT
#include "res://shaders/authored_ground.gdshaderinc"
