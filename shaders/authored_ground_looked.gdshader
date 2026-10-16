// The ground of a map authored in tt-sim with the GROUND LOOK path compiled in: what
// authored_ground.gdshader draws, for a map on which a biome carries a ground look
// (AuthoredTerrain.set_looked binds it; see GROUND LOOK in authored_ground.gdshaderinc).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_LOOK
#include "res://shaders/authored_ground.gdshaderinc"
