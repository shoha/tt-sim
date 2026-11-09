// The skirt's inner ring with the GROUND LOOK path compiled in: authored_ground_skirt_ring.gdshader
// for a map on which a biome carries a ground look (AuthoredTerrain.set_looked binds it).
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_SKIRT
#define GROUND_SKIRT_RING
#define GROUND_LOOK
#include "res://shaders/authored_ground.gdshaderinc"
