// authored_ground_bake.gdshader with the GROUND LOOK path compiled in, for a map on which a biome
// carries a ground look: the look's zones and painted light are baked into the composite.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_always, cull_back;

#define GROUND_LOOK
#define GROUND_BAKE_OUT
#include "res://shaders/authored_ground.gdshaderinc"
