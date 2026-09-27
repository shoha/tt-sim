// The ground skirt around an authored map: authored_ground.gdshaderinc with GROUND_SKIRT,
// transparent so it fades into the background (see SKIRT in the include). No depth write:
// it is flat, lies outside the map, and nothing is drawn on it.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_SKIRT
#include "res://shaders/authored_ground.gdshaderinc"
