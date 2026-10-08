shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_disabled;

/*
 * Avatar figure shader, double-sided variant: for parts whose open cards render both faces
 * (kit.json `double_sided`, glTF `extras.figurine_double_sided`, hair locks built as planes).
 * Identical to avatar_figure.gdshader in every other way; see its header.
 */

#include "res://shaders/avatar_figure.gdshaderinc"
