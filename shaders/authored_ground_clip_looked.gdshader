// authored_ground_clip.gdshader with the GROUND LOOK path compiled in, for a clipmap map on which
// a biome carries a ground look (AuthoredTerrain.set_looked and set_clipmap pick the variant).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_LOOK
#define GROUND_CLIPMAP
#include "res://shaders/authored_ground.gdshaderinc"
