// Walls of built structures in the materials the textured-masonry and plank shaders do not draw
// (architecture styles card 1, docs/systems/structures.md "Styles"): plaster, adobe, brick and log,
// all from the wall's vertex colour (StructurePaint bakes the style's wall tone into it; COLOR.a is
// the height above the building's foot in sixteenths of a metre) and the position alone, so a wall
// needs no textures and no UVs and a rotated building keeps its pattern. Everything is a broad soft
// shape: a lime wash that thins toward the foot, rain streaks, trowel and slump marks, bricks and
// logs SUGGESTED (a stylised, chunkier size than the real thing, faded out where a course is under
// about two pixels so a far wall stays calm).
shader_type spatial;
render_mode specular_disabled, diffuse_burley;

#include "res://shaders/structure_painterly.gdshaderinc"

// 0 plaster, 1 adobe, 2 brick, 3 log.
uniform int pattern = 0;
// How strongly the foot cools and darkens, and how far up it reaches (metres).
uniform float damp_amount : hint_range(0.0, 1.0) = 0.5;
uniform float damp_height = 1.0;
uniform float wash_amount : hint_range(0.0, 1.0) = 0.7;
uniform float contact_amount : hint_range(0.0, 1.0) = 0.6;
// Brick: course height, brick length (metres, stylised). Log: `course_m` is the log's diameter.
uniform float course_m = 0.16;
uniform float brick_m = 0.40;
uniform vec3 mortar_tone = vec3(0.92, 0.86, 0.74);
// How far a mossy vertex (a ruin's green foot, StructurePaint) is pulled to a painterly moss green.
uniform float moss_amount : hint_range(0.0, 1.0) = 0.6;
// Brick only: how far the baked tone is pulled from a saturated orange red toward a rosy brown.
uniform float brick_weather : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec3 n = normalize(s_normal);
	// Patterns only on faces that stand up; a sloped slab (a flat adobe roof) gets the colour alone.
	float vertical = 1.0 - smoothstep(0.55, 0.85, abs(n.y));
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 along = flat_len > 0.02 ? vec2(-flat_n.y, flat_n.x) / flat_len : vec2(1.0, 0.0);
	float u = dot(s_pos.xz, along);
	float v = s_pos.y;
	float metres = COLOR.a * 16.0;

	vec3 col = s_mossy(COLOR.rgb, s_moss_of(COLOR.rgb), moss_amount);
	vec3 m = vec3(1.0);
	float wash = s_noise(s_pos * 0.32 + 41.0);
	float mottle = s_noise(s_pos * 1.1 + 7.0);

	if (pattern == 0 || pattern == 1) {
		bool adobe = pattern == 1;
		// Trowel and slump: soft broad strokes, longer across than up.
		float trowel = s_noise(vec3(u * 1.3, v * 0.45, 2.0));
		m *= 1.0 + (trowel - 0.5) * (adobe ? 0.16 : 0.10);
		// Rain streaks running down from the eaves.
		float streak = s_noise(vec3(u * 2.1, v * 0.14, 9.0));
		m *= 1.0 - (adobe ? 0.15 : 0.09) * smoothstep(0.58, 0.88, streak);
		if (adobe) {
			// Sun-baked layers, paler toward the top.
			float layer = s_noise(vec3(u * 0.45, v * 2.6, 4.0));
			m *= 1.0 + (layer - 0.5) * 0.14;
			m *= mix(1.0, 1.07, smoothstep(2.0, 5.0, metres));
			m *= 1.0 + (mottle - 0.5) * 0.28;
			// A mud roof: darker packed earth in broad patches, dry and dusty.
			float top = smoothstep(0.6, 0.9, n.y);
			float packed = s_noise(s_pos * 1.3 + 31.0);
			col *= mix(vec3(1.0), vec3(0.84, 0.76, 0.66), top);
			m *= 1.0 + (packed - 0.5) * 0.45 * top;
		}
		// Lime wash lost at the foot, showing the warmer coat under it in a few soft patches.
		float lost = s_noise(s_pos * 1.7 + 23.0);
		float patch_m = smoothstep(0.70, 0.78, lost) * (1.0 - smoothstep(0.0, 3.2, metres));
		col = mix(col, col * vec3(0.80, 0.64, 0.52), patch_m * (adobe ? 0.35 : 0.7));
	} else if (pattern == 2) {
		// The styles' brick tones are saturated orange reds; weather them toward a rosy brown.
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(1.08, 0.94, 0.84) * luma, brick_weather * (1.0 - s_moss_of(COLOR.rgb)));
		float r = v / course_m;
		float row = floor(r);
		float c = u / brick_m + 0.5 * mod(row, 2.0);
		vec2 id = vec2(floor(c), row);
		float b1 = s_hash2(id + 3.0);
		float b2 = s_hash2(id + 19.0);
		float detail = 1.0 - smoothstep(0.35, 0.90, max(fwidth(r), fwidth(c)));
		float fr = fract(r);
		float fc = fract(c);
		// Mortar: a light joint round every brick, a little thicker in the beds than the heads.
		float edge = min(min(fr, 1.0 - fr) / 0.13, min(fc, 1.0 - fc) / 0.07);
		float mortar = 1.0 - smoothstep(0.0, 1.0, edge);
		// Each brick its own value and a touch of warm or cool; a shadow under every course's lip.
		float shape = 1.0 + (b1 - 0.5) * 0.34 - 0.16 * (1.0 - smoothstep(0.0, 0.35, fr));
		vec3 brick = s_lean(b2, 0.75) * shape;
		vec3 joint = mortar_tone / max(col, vec3(0.05));
		joint = clamp(joint, vec3(0.6), vec3(3.0));
		brick = mix(brick, mix(vec3(1.0), joint, 0.5), mortar * 0.6);
		m *= mix(vec3(1.0), brick, detail * vertical);
		// A few bricks burnt dark, and soft sooty and pale stains over the wall.
		m *= 1.0 + (mottle - 0.5) * 0.18;
	} else {
		float r = v / course_m;
		float row = floor(r);
		float f = fract(r);
		float detail = 1.0 - smoothstep(0.35, 0.90, fwidth(r));
		// A round log: dark in the seam, light on the belly, lighter on its upper half.
		float belly = sin(f * 3.14159265);
		float shade = mix(0.52, 1.10, smoothstep(0.0, 0.75, belly)) * (1.0 + 0.10 * (f - 0.5));
		float own = s_hash2(vec2(row, 5.0));
		float grain = s_noise(vec3(u * 0.8, v * 13.0, row * 1.7));
		vec3 log_c = s_lean(own, 0.55) * shade * (1.0 + (own - 0.5) * 0.22);
		log_c *= 1.0 + (grain - 0.5) * 0.20;
		m *= mix(vec3(1.0), log_c, detail * vertical);
		m *= 1.0 + (mottle - 0.5) * 0.12;
	}

	float foot = (1.0 - smoothstep(0.0, damp_height, metres)) * damp_amount;
	col *= mix(vec3(1.0), vec3(0.76, 0.84, 1.0), foot);
	// Ground contact: the grass's green bounce and a close dark, hugging the first metre.
	float contact = 1.0 - smoothstep(0.0, 0.9, metres);
	col *= mix(vec3(1.0), vec3(0.68, 0.80, 0.66), contact * contact * contact_amount);
	col *= mix(vec3(1.0), vec3(1.05, 1.03, 0.95), smoothstep(2.0, 6.0, metres));
	col *= s_lean(smoothstep(0.25, 0.75, wash), wash_amount);
	col *= s_mass(wash, 0.5 * wash_amount);

	vec3 painted = s_ramp(col * m, NORMAL, INV_VIEW_MATRIX);
	ALBEDO = painted;
	AO = s_ambient();
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = 0.92;
	EMISSION = s_rim(painted, NORMAL, VIEW);
}
