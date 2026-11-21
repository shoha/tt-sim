shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;
// The small stones' dabs (PainterDabs: patches of the terrain's own triangles): the painted ground's
// body with PAINTER_DAB, so a dab's pixel is the ground at that place with the stone's seam joined
// in. Its material takes every parameter of the ground's (PainterSurfaces.siblings()).

#define PAINTER_DAB
#include "res://painter/shaders/painter_ground_body.gdshaderinc"
