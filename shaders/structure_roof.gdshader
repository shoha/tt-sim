// Roofs of built structures and street lots: tiles or shingles SUGGESTED, not drawn. The colour is
// the building's own tile colour (vertex colour, StructurePaint); COLOR.a is the height up the roof,
// 0 at the eave to 1 at the ridge. Courses run across the slope (found from the face normal, so
// the same shader serves gable, hip and flat roofs with no UVs), each course a soft shadow under
// its lip, each tile a little lighter or darker and warmer or cooler than its neighbours, the joints
// barely there; broad warm and cool patches, a deeper cooler eave and a paler ridge on top.
shader_type spatial;
render_mode specular_disabled, diffuse_burley;

#include "res://shaders/structure_painterly.gdshaderinc"

// Course height and tile width, metres along the slope (a tile is a suggestion, about twice a
// token base).
uniform float course_m = 0.42;
uniform float tile_m = 0.62;
// How strongly each tile differs from the mean (value), and the lean to warm or cool per tile.
uniform float tile_value : hint_range(0.0, 0.5) = 0.13;
uniform float tile_lean : hint_range(0.0, 1.0) = 0.55;
uniform float course_shadow : hint_range(0.0, 0.6) = 0.20;
uniform vec3 eave_tone = vec3(0.80, 0.76, 0.90);
uniform vec3 ridge_tone = vec3(1.14, 1.10, 0.96);

void fragment() {
	vec3 n = normalize(s_normal);
	float up = n.y;
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	// Downhill on the face (the normal tilts downhill), and across it.
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float s = dot(s_pos.xz, down) / max(up, 0.35);
	float t = dot(s_pos.xz, across);
	// Tiles only on faces that look up; slab edges and the ridge beam get the colour alone.
	float tiled = smoothstep(0.25, 0.5, up);
	float r = s / course_m;
	float row = floor(r);
	float c = t / tile_m + 0.5 * mod(row, 2.0);
	float col = floor(c);
	vec2 id = vec2(col, row);
	float tile_rnd = s_hash2(id);
	float tile_rnd2 = s_hash2(id + 37.0);
	// Fewer details where a course is under about two pixels, so a far roof stays calm.
	float detail = 1.0 - smoothstep(0.30, 0.80, fwidth(r));
	float lip = smoothstep(0.0, 0.40, fract(r));
	float joint = smoothstep(0.0, 0.07, fract(c)) * smoothstep(0.0, 0.07, 1.0 - fract(c));
	float shape = 1.0 - course_shadow * (1.0 - lip) - 0.05 * (1.0 - joint);
	shape += (tile_rnd - 0.5) * tile_value;
	vec3 tile_c = s_lean(tile_rnd2, tile_lean) * shape;
	tile_c = mix(vec3(1.0), tile_c, detail * tiled);

	float h = clamp(COLOR.a, 0.0, 1.0);
	vec3 grade = mix(eave_tone, ridge_tone, smoothstep(0.0, 1.0, h));
	float broad = s_noise(s_pos * 0.45 + 3.0);
	vec3 patch_c = s_lean(smoothstep(0.25, 0.75, broad), 1.0) * (1.0 + (broad - 0.5) * 0.45);
	vec3 painted = COLOR.rgb * tile_c * grade * patch_c;
	ALBEDO = painted;
	EMISSION = s_rim(painted, NORMAL, VIEW);
	ROUGHNESS = 0.9;
}
