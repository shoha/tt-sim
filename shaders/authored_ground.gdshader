// The ground of a map authored in tt-sim. The whole shader, and its documentation, is
// authored_ground.gdshaderinc; this file only makes it opaque. See also
// authored_ground_skirt.gdshader.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/authored_ground.gdshaderinc"
