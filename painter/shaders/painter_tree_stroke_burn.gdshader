shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, specular_disabled, ambient_light_disabled;
// The painted trees' strokes for a tree an event burns, in leaf (painter-fire): the body with
// TREE_BURN, its burn an instance uniform (painter_tree_burn.gdshaderinc). PainterTrees.take.

#define TREE_BURN
#include "res://painter/shaders/painter_tree_stroke_body.gdshaderinc"
