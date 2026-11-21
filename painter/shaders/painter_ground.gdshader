shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
// The painted ground: the authored terrain's chunks and skirt, and a GLB map's terrain (the body's
// header has the model). The small stones' dabs are painter_ground_dab.gdshader, the same body with
// PAINTER_DAB: none of their code is in this one.

#include "res://painter/shaders/painter_ground_body.gdshaderinc"
