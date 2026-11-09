// The ground of a map authored in tt-sim with the CLIPMAP read compiled in: what
// authored_ground.gdshader draws, for a map whose ground clipmap is on (AuthoredTerrain
// .set_clipmap binds it; see CLIPMAP in authored_ground.gdshaderinc). Flag off, the plain
// shaders have none of it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_CLIPMAP
#include "res://shaders/authored_ground.gdshaderinc"
