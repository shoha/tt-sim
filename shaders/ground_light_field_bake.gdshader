// Bakes one biome's ground look (shaders/ground_light_field.gdshaderinc) into a texture once per
// map, so the ground and the grass read the zones and the painted light with one fetch instead of
// evaluating them per fragment. Runs on a ColorRect filling a SubViewport (GroundLookBake); each
// texel is the zone colour times the light over light_field_ref (rgb) and the light's luminance
// (a) at its map-frame XZ over bake_rect (origin, size in metres) shifted by zone_seed_m,
// square-root encoded over ZONE_RANGE. The alpha is written as is (blend_disabled; the
// SubViewport keeps a transparent background). The mass shade and lift stamps draw over it.
shader_type canvas_item;
render_mode blend_disabled;

#define LIGHT_FIELD_BAKE
#include "res://shaders/ground_light_field.gdshaderinc"

uniform vec4 bake_rect = vec4(-64.0, -64.0, 128.0, 128.0);

void fragment() {
	vec2 xs = bake_rect.xy + UV * bake_rect.zw + zone_seed_m;
	vec3 light = light_field_procedural(xs);
	vec3 m = zone_lit(zone_color(xs), light) / max(light_field_ref, vec3(1e-3));
	float a = dot(light, ZONE_LUMA);
	COLOR = sqrt(clamp(vec4(m, a) / ZONE_RANGE, vec4(0.0), vec4(1.0)));
}
