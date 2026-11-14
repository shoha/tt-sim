shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, specular_disabled, ambient_light_disabled;
// The painted trees' strokes in a bare season (the sheet's leaf-keep under 1, PainterTrees.retone):
// the body with TREE_BARE, so the leaf drop's code runs only here.

#define TREE_BARE
#include "res://painter/shaders/painter_tree_stroke_body.gdshaderinc"
