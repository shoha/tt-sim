// Walls, trim and chimneys of built structures and street lots: the baked masonry set or the
// planks, repainted warm. The colour is the texture times a tint times the vertex colour
// (StructurePaint gives each building its own gentle lean), lifted toward cream (saturation and a
// warm bias), cooler and damper at the foot, paler toward the eaves, with broad warm and cool
// washes. COLOR.a is the height above the foot, in sixteenths of a metre.
shader_type spatial;
render_mode specular_disabled, diffuse_burley;

#include "res://shaders/structure_painterly.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 albedo_tint = vec3(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;
// 1 keeps the texture's saturation; more lifts it (a grey rock turned to cream stone).
uniform float saturation = 1.0;
uniform vec3 warm_bias = vec3(1.0);
// How far the hue is replaced by `cream` (times the texture's luminance), 0 keeps the rock's own.
uniform vec3 cream = vec3(1.25, 1.02, 0.78);
uniform float cream_amount : hint_range(0.0, 1.0) = 0.0;
// How strongly the foot cools and darkens, and how far up it reaches (metres).
uniform float damp_amount : hint_range(0.0, 1.0) = 0.6;
uniform float damp_height = 1.1;
uniform float wash_amount : hint_range(0.0, 1.0) = 0.7;
uniform float contact_amount : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 col = texture(albedo_tex, uv).rgb * albedo_tint * COLOR.rgb;
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	// A grey rock turned to warm cream stone: the texture's light and dark kept, the hue replaced.
	col = mix(col, vec3(luma) * cream, cream_amount) * warm_bias;

	float metres = COLOR.a * 16.0;
	float foot = (1.0 - smoothstep(0.0, damp_height, metres)) * damp_amount;
	col *= mix(vec3(1.0), vec3(0.74, 0.82, 1.02), foot);
	// Ground contact: the grass's green bounce and a close dark, hugging the first metre.
	float contact = 1.0 - smoothstep(0.0, 0.9, metres);
	col *= mix(vec3(1.0), vec3(0.66, 0.78, 0.64), contact * contact_amount);
	col *= mix(vec3(1.0), vec3(1.05, 1.03, 0.95), smoothstep(2.0, 6.0, metres));

	float wash = s_noise(s_pos * 0.32 + 41.0);
	// The clump-sized octave: blotches about as wide as a crown, a little taller on a wall.
	float clump = s_noise(s_pos * vec3(0.24, 0.30, 0.24) + 19.0);
	col *= s_lean(smoothstep(0.25, 0.75, wash), wash_amount);
	col *= s_mass(wash, 0.5 * wash_amount) * s_break(clump, 1.0);
	col = s_ramp(col, NORMAL, INV_VIEW_MATRIX);
	col = s_ink(col, NORMAL, VIEW, 0.0);

	vec3 orm = texture(orm_tex, uv).rgb;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_scale;
	AO = orm.r * s_ambient();
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = max(orm.g, 0.7);
	ALBEDO = col;
	EMISSION = s_rim(col, NORMAL, VIEW);
}
