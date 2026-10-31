// The painterly look of built structures (card S6; docs/systems/structures.md "Look"): the terms
// the roof and wall shaders share. A structure's colour comes from its mesh's vertex colours
// (StructurePaint bakes a per building tile colour into the roof and a gentle lean into the walls)
// and COLOR.a carries the height the shaders grade by, so one material per role serves every
// structure and street lot. Everything here is a broad, soft shape: world-space value noise at
// building scale, never fine grain, and a light() with a wrapped terminator whose shadow leans to a
// cool lavender instead of going grey.
//
// Cost: no extra texture reads, one 3D value noise per fragment (8 hashes), no branches on
// uniforms, specular off. light() runs for directional lights only; other lights add plain lambert.

// The plants' light model (wind_foliage_include.gdshaderinc, FOLIAGE_PAINTED_LIGHT), at a building's
// albedo: the sun published for the crowns, a sun-ward albedo ramp (lit tint toward the sun, a deeper
// saturated shade tint away from it), a wide soft N.L band with a tinted shade floor instead of a
// lifted fill, and less ambient under a full sun so the shade keeps its colour.
global uniform vec4 foliage_sun;
uniform vec3 ramp_lit_tint = vec3(1.06, 1.03, 0.98);
uniform vec3 ramp_shade_tint = vec3(0.86, 0.84, 0.96);
uniform vec3 shade_floor = vec3(0.21, 0.16, 0.25);
uniform vec3 lit_gain = vec3(1.22, 1.17, 1.08);
uniform float shadow_cast : hint_range(0.0, 1.0) = 0.7;
uniform float wrap : hint_range(0.0, 0.5) = 0.15;
// The share of ambient a surface keeps under a full sun (the crowns keep 0.25).
uniform float ambient_keep : hint_range(0.0, 2.0) = 0.5;
// Rim of warm light on edges turned away from the camera (a painter's lost-and-found edge).
uniform vec3 rim_color : source_color = vec3(1.0, 0.86, 0.62);
uniform float rim_amount : hint_range(0.0, 0.5) = 0.12;

// Silhouette and crease ink, the plants' term (foliage_view_ink, wind_foliage_include.gdshaderinc
// apply_painted_albedo) at a building's scale: the albedo is multiplied toward a deep tinted edge
// (a plum that keeps the colour, never black) where a face turns away from the camera, and along
// creases (a wall corner, an eave lip), found from how fast the shading normal changes across the
// screen (fwidth, no mesh data and no texture read).
uniform vec3 ink_tint = vec3(0.42, 0.31, 0.46);
uniform float ink_silhouette : hint_range(0.0, 1.0) = 0.8;
uniform float ink_crease : hint_range(0.0, 1.0) = 1.0;
// How strongly the larger painted patches break a wall or roof (value and hue, tree-clump size).
uniform float break_amount : hint_range(0.0, 1.0) = 0.85;

varying vec3 s_pos;
varying vec3 s_normal;

float s_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float s_hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float s_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(s_hash(i), s_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(s_hash(i + vec3(0.0, 1.0, 0.0)), s_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(s_hash(i + vec3(0.0, 0.0, 1.0)), s_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(s_hash(i + vec3(0.0, 1.0, 1.0)), s_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// A soft colour multiplier: 0 leans cool (lavender), 1 leans warm (gold), `amount` how far.
vec3 s_lean(float warmth, float amount) {
	vec3 warm = vec3(1.07, 1.0, 0.86);
	vec3 cool = vec3(0.90, 0.95, 1.08);
	return mix(vec3(1.0), mix(cool, warm, warmth), amount);
}

void vertex() {
	s_pos = VERTEX;
	s_normal = NORMAL;
#ifdef S_SWAY
	// A shader that defines S_SWAY declares `uniform float sway` before this include (the ornament
	// shader: a treehouse crown): a slow sideways drift whose phase follows the world position.
	if (sway > 0.0) {
		vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float p = w.x * 0.7 + w.z * 0.9;
		VERTEX.x += sin(TIME * 0.9 + p) * sway;
		VERTEX.z += cos(TIME * 0.7 + p * 1.3) * sway * 0.7;
	}
#endif
#ifdef S_WIND
	// A shader that defines S_WIND defines `vec3 s_cloth_wind(vec3 vertex, vec2 weight, mat4 model)`
	// before this include (the ornament shader: banner, pennant and awning cloth). The weight is the
	// second UV set, written by StructureCloth.
	VERTEX += s_cloth_wind(VERTEX, UV2, MODEL_MATRIX);
#endif
}

// The faint warm rim, from the albedo, the geometry normal and the view vector.
vec3 s_rim(vec3 painted, vec3 normal, vec3 view) {
	float rim = pow(1.0 - clamp(dot(normal, view), 0.0, 1.0), 3.0);
	return rim_color * rim * rim_amount * painted;
}

// The ink: `normal` is the view-space geometry normal, `view` VIEW, `extra` 0..1 more ink where the
// shader knows an edge (an eave). Multiplies the albedo toward `ink_tint`.
// `softness` 0..1 lightens the ink (a lavender instead of a deep plum, less on grazing faces) for
// big lit walls, where a dark ink would muddy the colour.
vec3 s_ink(vec3 painted, vec3 normal, vec3 view, float extra, float softness) {
	float graze = 1.0 - clamp(abs(dot(normal, view)), 0.0, 1.0);
	float silhouette = smoothstep(0.55, 0.95, graze) * ink_silhouette * (1.0 - 0.8 * softness);
	float crease = smoothstep(0.18, 0.6, length(fwidth(normal))) * ink_crease;
	float ink = clamp(silhouette + crease + extra, 0.0, 0.85);
	return painted * mix(vec3(1.0), mix(ink_tint, vec3(0.74, 0.66, 0.84), softness), ink);
}

// A painted patch the size of a tree clump: value and hue shift in soft-edged blotches (damp sage,
// warm ochre) from a 0..1 noise, so a large wall or roof is never one smooth gradient.
// `value` is the swing in brightness (0.58 for a roof, small for a wall so the blotches are hue
// shifts at a similar value, never darkening).
vec3 s_break(float n, float amount, float value) {
	float t = smoothstep(0.38, 0.62, n);
	vec3 hue = mix(vec3(0.90, 1.05, 0.98), vec3(1.10, 0.98, 0.86), t);
	return mix(vec3(1.0), hue * (1.0 - 0.5 * value + value * t), amount * break_amount);
}

// How mossy a wall vertex is, 0..1, from its colour alone: a ruin's moss is a multiplied green
// (procgen ProcgenRuin.MOSS_TINT) that StructurePaint keeps in the vertex colour, so green over the
// larger of red and blue says it (a cream or sage lean sits near 0 or just under the threshold).
float s_moss_of(vec3 vertex_color) {
	return smoothstep(0.015, 0.2, vertex_color.g - max(vertex_color.r, vertex_color.b));
}

// `painted` pulled toward a bright painterly moss green where `moss` is, keeping its light and dark
// (the same luminance trick as the cream of a masonry wall, which would otherwise flatten the tint
// back to stone). `amount` is how far at full moss.
vec3 s_mossy(vec3 painted, float moss, float amount) {
	float luma = dot(painted, vec3(0.299, 0.587, 0.114));
	vec3 green = vec3(0.58, 1.28, 0.34) * luma * (1.0 + 0.28 * (1.0 - luma));
	return mix(painted, green, clamp(moss * amount, 0.0, 1.0));
}

// The foliage's sun-ward albedo ramp: `normal` is the view-space normal, `inv_view` INV_VIEW_MATRIX.
vec3 s_ramp(vec3 painted, vec3 normal, mat4 inv_view) {
	vec3 ramp_dir = normalize(foliage_sun.xyz + vec3(0.0, 0.5, 0.0));
	float t = smoothstep(-0.5, 0.8, dot(normalize(mat3(inv_view) * normal), ramp_dir));
	return painted * mix(ramp_shade_tint, ramp_lit_tint, t);
}

// The ambient share (for AO): the crowns' rule, eased back to 1 as the sun fades.
float s_ambient() {
	return mix(1.0, ambient_keep, clamp(foliage_sun.w, 0.0, 1.0));
}

// A broad soft-edged value shape from a 0..1 noise: bold masses with soft edges, as in a crown.
float s_mass(float n, float amount) {
	return 1.0 + (smoothstep(0.30, 0.70, n) - 0.5) * amount;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		float lit = smoothstep(-wrap, 0.9, nl);
		float k = lit * mix(1.0 - shadow_cast, 1.0, ATTENUATION);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(shade_floor, lit_gain, k);
	} else {
		DIFFUSE_LIGHT += LIGHT_COLOR * max(nl, 0.0) * ATTENUATION / PI;
	}
}
