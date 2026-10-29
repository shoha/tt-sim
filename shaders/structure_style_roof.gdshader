// Roofs of built structures in the materials the tile shader does not draw (architecture styles
// card 1, docs/systems/structures.md "Styles"): slate, shingle, thatch and turf. As the tile shader
// (structure_roof.gdshader): the colour is the building's own roof tone (vertex colour, StructurePaint
// draws it from the style's palette) and COLOR.a is the height up the roof, 0 at the eave to 1 at the
// ridge; the slope's own axes are found from the face normal, so gable, hip and flat roofs need no
// UVs. Each material is SUGGESTED, not drawn: slate small cool rectangles under a shadowed lip,
// shingles scalloped rows, thatch shaggy straw strands in soft bundles darkening and greening toward
// the eave, turf broad green masses with tufts and a sparse sprinkle of wildflowers over a soil edge.
shader_type spatial;
render_mode specular_disabled, diffuse_burley;

#include "res://shaders/structure_painterly.gdshaderinc"

// 0 slate, 1 shingle, 2 thatch, 3 turf.
uniform int pattern = 0;
uniform vec3 eave_tone = vec3(0.82, 0.78, 0.90);
uniform vec3 ridge_tone = vec3(1.12, 1.08, 0.96);
uniform vec3 soil_tone = vec3(0.34, 0.24, 0.15);

void fragment() {
	vec3 n = normalize(s_normal);
	float up = n.y;
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float s = dot(s_pos.xz, down) / max(up, 0.35);
	float t = dot(s_pos.xz, across);
	// Covering only on faces that look up; slab edges and the ridge beam get the colour alone.
	float tiled = smoothstep(0.25, 0.5, up);
	float h = clamp(COLOR.a, 0.0, 1.0);
	vec3 m = vec3(1.0);
	vec3 grade = mix(eave_tone, ridge_tone, smoothstep(0.0, 1.0, h));
	vec3 col = COLOR.rgb;

	if (pattern == 0) {
		float r = s / 0.30;
		float row = floor(r);
		float c = t / 0.40 + 0.5 * mod(row, 2.0);
		vec2 id = vec2(floor(c), row);
		float a = s_hash2(id);
		float b = s_hash2(id + 37.0);
		float detail = 1.0 - smoothstep(0.30, 0.80, fwidth(r));
		float lip = smoothstep(0.0, 0.30, fract(r));
		float joint = smoothstep(0.0, 0.05, fract(c)) * smoothstep(0.0, 0.05, 1.0 - fract(c));
		float shape = 1.0 - 0.34 * (1.0 - lip) - 0.10 * (1.0 - joint) + (a - 0.5) * 0.34;
		vec3 piece = s_lean(b, 0.45) * shape;
		m = mix(vec3(1.0), piece, detail * tiled);
	} else if (pattern == 1) {
		float r = s / 0.24;
		float row = floor(r);
		float c = t / 0.28 + 0.5 * mod(row, 2.0);
		vec2 id = vec2(floor(c), row);
		float a = s_hash2(id + 5.0);
		float b = s_hash2(id + 41.0);
		float detail = 1.0 - smoothstep(0.30, 0.80, fwidth(r));
		float cx = fract(c) - 0.5;
		// The shingle's rounded lower edge, lowest in the middle; the row below shows under it.
		float d = fract(r) - 0.24 * 4.0 * cx * cx;
		float lip = smoothstep(-0.05, 0.22, d);
		float shape = 1.0 - 0.32 * (1.0 - lip) + (a - 0.5) * 0.24;
		vec3 piece = s_lean(b, 0.55) * shape;
		m = mix(vec3(1.0), piece, detail * tiled);
	} else if (pattern == 2) {
		// Straw strands run down the slope; their lines wander a little, bundles overlap in bands.
		float wob = s_noise(vec3(s * 0.45, t * 0.25, 1.0)) * 0.9;
		float st = t / 0.10 + wob;
		float sid = floor(st);
		float strand = s_hash2(vec2(sid, floor(s / 0.7)));
		float detail = 1.0 - smoothstep(0.45, 1.0, fwidth(st));
		float gap = smoothstep(0.0, 0.22, fract(st)) * smoothstep(0.0, 0.22, 1.0 - fract(st));
		float r = s / 0.55;
		float band = smoothstep(0.0, 0.5, fract(r));
		float own = s_hash2(vec2(floor(r), 3.0));
		float shape = 1.0 + (strand - 0.5) * 0.40 - 0.14 * (1.0 - gap);
		shape = mix(1.0, shape, detail);
		shape *= 1.0 - 0.24 * (1.0 - band) + (own - 0.5) * 0.14;
		m = mix(vec3(1.0), s_lean(own, 0.4) * shape, tiled);
		// Old straw greens and darkens at the eave.
		grade *= mix(vec3(0.84, 0.86, 0.72), vec3(1.0), smoothstep(0.0, 0.35, h));
	} else {
		float mass = s_noise(s_pos * 0.9 + 11.0);
		float tuft_n = s_noise(s_pos * 3.2 + 5.0);
		float tuft = smoothstep(0.55, 0.82, tuft_n);
		float between = 1.0 - smoothstep(0.18, 0.45, tuft_n);
		vec3 turf = mix(vec3(0.80, 0.93, 0.84), vec3(1.14, 1.08, 0.82), smoothstep(0.3, 0.7, mass));
		turf *= 1.0 + tuft * 0.24 - between * 0.14;
		// A sprinkle of wildflowers: a dot in about one cell in nine, white, buttercup or pink.
		vec2 cell_uv = vec2(t, s) / 0.45;
		vec2 cell = floor(cell_uv);
		float roll = s_hash2(cell + 13.0);
		vec2 centre = vec2(s_hash2(cell + 2.0), s_hash2(cell + 7.0)) * 0.5 + 0.25;
		float dot_m = 1.0 - smoothstep(0.17, 0.27, length(fract(cell_uv) - centre));
		float pick = s_hash2(cell + 29.0);
		vec3 bloom = pick < 0.4 ? vec3(2.6, 2.5, 2.2) : (pick < 0.75 ? vec3(2.7, 2.3, 0.7) : vec3(2.5, 1.5, 1.7));
		float flower = step(0.84, roll) * dot_m * smoothstep(0.1, 0.35, h);
		float detail = 1.0 - smoothstep(0.45, 1.0, fwidth(cell_uv.x));
		turf = mix(turf, bloom, flower * detail * 0.85);
		m = mix(vec3(1.0), turf, tiled);
		// Slab edges and the underside are soil and roots.
		col = mix(soil_tone, col, tiled);
		grade = mix(vec3(0.92), grade, tiled);
	}

	float broad = s_noise(s_pos * 0.45 + 3.0);
	vec3 patch_c = s_lean(smoothstep(0.25, 0.75, broad), 1.0) * s_mass(broad, 0.55);
	vec3 painted = s_ramp(col * m * grade * patch_c, NORMAL, INV_VIEW_MATRIX);
	ALBEDO = painted;
	AO = s_ambient();
	AO_LIGHT_AFFECT = 1.0;
	EMISSION = s_rim(painted, NORMAL, VIEW);
	ROUGHNESS = 0.9;
}
