// The inner ring of the ground skirt: authored_ground_skirt.gdshader with the shadow reception back
// (card skirtring, see SKIRT RING in authored_ground.gdshaderinc). A tall caster near the map edge
// still throws its shadow onto the ground just beyond it; the reception fades out to the ring's
// outer edge, where the shadowless outer skirt takes over without a seam.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#define GROUND_SKIRT
#define GROUND_SKIRT_RING
#include "res://shaders/authored_ground.gdshaderinc"
