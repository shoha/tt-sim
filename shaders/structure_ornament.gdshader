// The soft and small parts a player adds to a building (StructureOrnaments): ivy and flower-box
// foliage, awning and banner cloth, a vane's metal, the small wooden parts of a sign. Each keeps the
// colour procgen painted into its vertices (a stripe, a jewel tone, a leaf green) and takes the
// suite's painterly light (structure_painterly.gdshaderinc): a warm lit side, a soft cool shade, a
// faint rim. Seen from both sides, since a leaf, a pennant and an awning are single sheets. COLOR.a
// is the height above the building's foot in sixteenths of a metre (StructurePaint), which cools
// and darkens the first half metre the way a wall's foot is, so ivy sits in the ground.
shader_type spatial;
render_mode specular_disabled, diffuse_burley, cull_disabled;

#include "res://shaders/structure_painterly.gdshaderinc"

// A multiplier on the painted colour: metal is lifted a little warm so it reads as gold and iron,
// not as a dark lump; cloth and foliage keep their colour.
uniform vec3 tone = vec3(1.0);
// Procgen paints these parts in lit colours (a leaf green near 0.5, a cream stripe near 0.9) and the
// painterly light adds its own gain on top, which blew a first render out to pale cream: the paint is
// brought down to the albedo the crowns' foliage has before the light is applied.
uniform float exposure : hint_range(0.2, 1.0) = 0.66;
// A broad hue/value shift in soft blotches, so a clump of leaves is never one flat green.
uniform float blotch : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	vec3 col = COLOR.rgb * tone * exposure;
	float metres = COLOR.a * 16.0;
	col *= s_break(s_noise(s_pos * 1.7 + 3.0), blotch, 0.3);
	float foot = 1.0 - smoothstep(0.0, 0.5, metres);
	col *= mix(vec3(1.0), vec3(0.78, 0.86, 0.80), foot * 0.6);
	vec3 painted = s_ramp(col, NORMAL, INV_VIEW_MATRIX);
	ALBEDO = painted;
	AO = s_ambient();
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = roughness_amount;
	EMISSION = s_rim(painted, NORMAL, VIEW);
}
