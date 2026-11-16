shader_type spatial;
render_mode skip_vertex_transform, specular_disabled, ambient_light_disabled;
// The painted trees' crown masses as the camera draws them in leaf (painter-perf-blockin): the body
// with TREE_FAST, which has no discard anywhere, so the depth pre-pass and the opaque pass keep
// early-z (a shader with any discard runs every fragment of its prepass, about 0.3 ms at the taiga
// home view, and the discards' own work about 0.3 more). The node casts no shadow; its twin node of
// the full block-in shader, SHADOWS_ONLY over the same MultiMesh, casts the whole crown's shadow with
// its eroded edge and gaps. While an authoring canopy fade (brush window, cut) is live PainterTrees draws the full shader here.
// A burning tree and the limb ribbons keep the full shaders.

#define TREE_FAST
#include "res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
