// The ground skirt around an authored map: authored_ground.gdshaderinc with GROUND_SKIRT.
// Opaque (phase 6, P6-1): it is in the depth and screen textures like the map's ground, so
// water running on past the edge reads its channel; it fades into the backdrop in colour,
// not alpha (see SKIRT in the include).
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_SKIRT
#include "res://shaders/authored_ground.gdshaderinc"
