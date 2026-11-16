shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, specular_disabled, ambient_light_disabled;
// The painted trees' strokes for a tree an event burns in a bare season (painter-fire): the bare
// body with TREE_BURN.

#define TREE_BARE
#define TREE_BURN
#include "res://painter/shaders/painter_tree_stroke_body.gdshaderinc"
