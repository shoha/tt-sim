shader_type spatial;
render_mode skip_vertex_transform, specular_disabled, ambient_light_disabled;
// painter_tree_blockin_fast in a bare season (TREE_BARE as well): the leaf drop's code runs only
// here, and the foliage it drops is collapsed in the vertex stage.

#define TREE_BARE
#define TREE_FAST
#include "res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
