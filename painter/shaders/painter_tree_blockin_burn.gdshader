shader_type spatial;
render_mode skip_vertex_transform, specular_disabled, ambient_light_disabled;
// The painted trees' block-in for a tree an event burns, in leaf (painter-fire): the body with
// TREE_BURN, its burn an instance uniform (painter_tree_burn.gdshaderinc). PainterTrees.take.

#define TREE_BURN
#include "res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
