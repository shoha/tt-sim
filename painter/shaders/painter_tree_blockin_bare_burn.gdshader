shader_type spatial;
render_mode skip_vertex_transform, specular_disabled, ambient_light_disabled;
// The painted trees' block-in for a tree an event burns in a bare season (painter-fire): the bare
// body with TREE_BURN.

#define TREE_BARE
#define TREE_BURN
#include "res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
