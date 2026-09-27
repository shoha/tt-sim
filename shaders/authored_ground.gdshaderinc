/*
 * Authored Ground Shader
 * ======================
 *
 * PURPOSE:
 * The ground of a map authored in tt-sim (AuthoredTerrain, scenes/terrain/). Tiles one
 * palette surface (albedo, tangent-space normal, packed ORM) across the terrain chunks at
 * the surface's tile_m, and hides that tiling at the game camera. A Blender-made map
 * brings its terrain as a baked, non-repeating texture; this shader has to reach a
 * comparable read live from a 2-3 m texture repeated across a 61 m map.
 *
 * FILES: this include is the whole shader. authored_ground.gdshader (opaque, the map) and
 * authored_ground_skirt.gdshader (transparent, GROUND_SKIRT defined) only declare the
 * shader type and render mode and include it, so the skirt continues the ground's exact
 * texture, anti-tiling and drifts across the map edge.
 *
 * SKIRT (GROUND_SKIRT, added after T7 zoom-out renders): a ring of ground around the map
 * whose alpha falls from 1 at the map edge to 0 skirt_fade_m out, the fade distance
 * stretched by low-frequency noise so the outline is organic, not a rectangle. Alpha
 * rather than a colour fade, so it dissolves into whatever the background is (a flat
 * colour or, through the orthographic camera, a sky seen in one direction). The skirt
 * binds no biome layers: the weight map clamps at its edge, which would streak.
 *
 * ANTI-TILING (the live port of terrain-paint's Mosaic tiling breakup):
 * terrain-paint breaks a repeating texture by cutting UV space into a grid of cells, giving
 * each cell a hashed rotation and a large hashed offset (so each cell shows an unrelated
 * part of the texture), and cross-fading the 4 nearest cells so the borders do not show.
 * It does that in a bake, where 4 samples per texture are free. Live, on a surface that
 * covers the whole screen, the same idea is done on a triangle grid instead of a square
 * one (Heitz and Neyret's tiling-and-blending lattice, with Mikkelsen's per-tile
 * rotation and contrast-preserving weights): every point lies in one triangle, so it
 * blends exactly 3 cells instead of 4, which is 12 texture fetches for the four maps
 * instead of 16. The blend weights are raised to a power (breakup_sharpness) so most of
 * each cell shows a single, unblended, full-contrast sample and only a narrow band near the
 * cell edges cross-fades; within the band the taller sample (height map) wins, so clumps
 * and pebbles overlap like real material instead of averaging to mush.
 *
 * The cell hash is an integer hash (pcg2d) of the cell id plus the map seed. terrain-paint
 * had to keep its Noise Texture hash off the integer lattice because Perlin noise is
 * degenerate at integer points; an integer hash has no such lattice, so cell ids are
 * hashed directly and neighbouring cells decorrelate fully.
 *
 * Texture derivatives come from the continuous world UV (rotated per cell) and go to
 * textureGrad: the three cells in play switch at triangle edges, and implicit derivatives
 * across that switch would pick the smallest mip and draw a line of sparkle along every
 * edge. Anisotropic filtering matters here: the camera looks 22 degrees down, so the
 * ground is foreshortened about 2.7x and isotropic mips blur it.
 *
 * VARIATION (added after game-camera renders beside a Blender-made map):
 * A baked terrain carries large, soft brightness and hue drifts (painted layers, AO, a
 * noise mask); one surface tiled perfectly evenly does not, and read as flat felt at the
 * game camera even with no visible repeat. Three things, all cheap:
 *   - cavity: the height map darkens its low parts (clump gaps), with the depth itself
 *     drifting over a few metres so clumpy and smooth stretches alternate;
 *   - brightness: two octaves of world-space value noise at variation_scale_m;
 *   - dry and lush drifts: a signed noise pulls albedo toward a warm dry tint in some
 *     patches and a cooler lush one in others, with a neutral band between.
 *
 * NORMALS:
 * The palette normal maps are OpenGL tangent space (ASSET_PIPELINE.md section 6), imported
 * BC5 (only R and G survive). UVs are planar world XZ, so the tangent frame is known
 * without mesh tangents: +u is world +X, +v is world +Z, and OpenGL green (+y, "up" in the
 * image) is -v. The sampled xy is rotated back out of each cell's rotation, blended, z is
 * rebuilt, and the result is written to NORMAL directly.
 *
 * BIOME LAYERS (painted ground; weights from BiomeGroundLayers, utils/):
 * Up to 4 layer surfaces (layer_*[i]) blend over the base. biome_weights holds one RGBA8
 * texel per document sample, channel i = the painted density of the biome whose ground is
 * layer i; the base is the remainder. It is bilinear-filtered, so a 0.25 m grid gives
 * smooth ramps rather than stair steps. The tile frame is computed once per pixel and
 * shared: each layer costs only its own 12 fetches, and a layer (or the base) whose weight
 * is zero at a pixel is not sampled at all.
 * The painted edge is then made to look like ground rather than a brush circle, the way
 * terrain-paint's Edge Noise and Height Blend do it in a bake:
 *   - domain warp: the weight map is read at a noise-displaced position (up to
 *     biome_edge_warp_m), so a round dab's outline wanders; this frays even a hard edge;
 *   - edge noise: the painted total is pushed up or down by finer noise, most where it is
 *     partial (a density falloff, a sparse fill) and not at all where it is 0 or 1, so a
 *     half-painted stretch breaks into patches instead of a uniform half-blend;
 *   - height blend: each surface scores weight + (height - 0.5) * biome_height_contrast
 *     and only surfaces within biome_blend_width of the top score show, so at a boundary
 *     the taller texture detail (clumps, needles, stones) wins and the line follows the
 *     textures rather than a gradient.
 *
 * BROAD EDGE (the second scale of a two-scale edge, added after T7 renders beside the
 * river map): the frayed edge above is a few decimetres wide and on its own reads like a
 * decal laid on the lawn, where a hand-painted Blender layer fades over several metres.
 * biome_broad is the weight map box-filtered to BiomeGroundLayers.BROAD_FACTOR samples per
 * texel (3.5 m at the default 0.25 m step) and read with a cubic B-spline, so around each
 * painted area the layer's mean colour (the last mip of its albedo) recolours the ground in
 * a gradient about 7 m wide. It recolours by luminance (layer mean x the pixel's luminance
 * relative to the base mean), so the base texture keeps its detail and no hue is amplified;
 * a per-channel ratio turned green grass pink at the edge of a brown layer. The tint fades
 * out where the fine edge already shows the layer itself. Cost: 4 bilinear fetches of a
 * tiny texture plus one lowest-mip fetch per layer present.
 *
 * PHASE 3 (splatting): SurfaceSample.height is the blended height each surface needs for
 * height-blended transitions; raising MAX_LAYERS means a second weight texture.
 *
 * COST: 12 fetches plus 26 small integer hashes per pixel for the base alone; measured
 * about 1.4x a StandardMaterial3D ground with the same textures. Biome layers add 3 value
 * noises and one weight fetch when any layer is bound, plus 12 fetches per surface present
 * at a pixel (docs/ARCHITECTURE.md "Authored terrain" has the measured ratios).
 *
 * LIGHTING matches the StandardMaterial3D terrain of a Blender-made map: burley diffuse,
 * schlick GGX specular at the default 0.5, AO from ORM.r affecting ambient only
 * (StandardMaterial3D's ao_light_affect = 0), roughness ORM.g, metallic ORM.b. Shadows and
 * the lo-fi post pass apply as to any opaque surface.
 */

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Metres covered by one repeat of the surface textures (the palette's tile_m).
uniform float tile_m = 2.0;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// How much the low parts of the height map darken (clump gaps, crevices).
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.35;

// Anti-tiling. Cell size is in metres, shared by every surface.
uniform bool breakup_enabled = true;
uniform float breakup_cell_m : hint_range(0.25, 16.0) = 2.0;
// Fraction of a full turn a cell may rotate by (1 = any angle; organic surfaces).
uniform float breakup_rotation : hint_range(0.0, 1.0) = 1.0;
// Weight exponent: higher = narrower blend bands and crisper cells.
uniform float breakup_sharpness : hint_range(1.0, 16.0) = 6.0;
// How much the taller sample (height map) wins the blend band (0 = plain barycentric).
uniform float breakup_contrast : hint_range(0.0, 1.0) = 0.7;
uniform int breakup_seed = 0;

// Low-frequency variation: brightness drift, plus dry and lush drifts in opposite
// directions (multipliers, so they suit any surface's own colour).
uniform float variation_scale_m : hint_range(1.0, 100.0) = 9.0;
uniform float variation_value : hint_range(0.0, 0.5) = 0.14;
uniform float variation_tint_amount : hint_range(0.0, 1.0) = 0.6;
uniform vec3 variation_dry_tint : source_color = vec3(1.12, 1.02, 0.72);
uniform vec3 variation_lush_tint : source_color = vec3(0.86, 0.95, 0.9);

// Biome layers (see BIOME LAYERS above). Layers at index >= biome_layer_count are unbound.
uniform int biome_layer_count : hint_range(0, 4) = 0;
uniform sampler2D biome_weights : hint_default_black, filter_linear, repeat_disable;
// World XZ of document sample (0, 0) and the real sample step, in metres.
uniform vec2 biome_grid_origin = vec2(0.0);
uniform vec2 biome_grid_step = vec2(0.25);
uniform sampler2D layer_albedo[4] : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Sampler arrays take no default or normal hints, so AuthoredTerrain binds every entry.
uniform sampler2D layer_normal[4] : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_orm[4] : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_height[4] : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 layer_tile_m = vec4(2.0);
// Defaults chosen from game-camera renders (docs/ARCHITECTURE.md "Authored terrain"):
// lower contrast or a wider blend reads as a soft stain, stronger edge noise turns
// partial paint into hard-edged blobs.
// Painted density -> ground weight multiplier (clamped to 1).
uniform float biome_weight_gain : hint_range(1.0, 4.0) = 1.5;
uniform float biome_edge_warp_m : hint_range(0.0, 4.0) = 1.2;
uniform float biome_edge_scale_m : hint_range(0.5, 20.0) = 3.0;
uniform float biome_edge_noise : hint_range(0.0, 1.0) = 0.3;
uniform float biome_height_contrast : hint_range(0.0, 2.0) = 1.2;
uniform float biome_blend_width : hint_range(0.01, 0.5) = 0.2;
// Broad scale of the two-scale edge (see BROAD EDGE): the weight map box-filtered to a few
// metres per texel (BiomeGroundLayers.broad_image), read with a B-spline so it is smooth.
uniform sampler2D biome_broad : hint_default_black, filter_linear, repeat_disable;
// Most a layer's colour tints the ground around its painted area (0.5 was too faint to
// read at the game camera; 0.8 reads as woodland floor fading into lawn).
uniform float biome_broad_strength : hint_range(0.0, 1.0) = 0.8;
// Broad weight at which the tint reaches full strength.
uniform float biome_broad_full : hint_range(0.05, 1.0) = 0.4;

#ifdef GROUND_SKIRT
// Half the map's extent in UV (document) metres: the skirt fades out from this rectangle.
uniform vec2 skirt_half_extent = vec2(30.0);
// Distance past the map edge at which the skirt is fully transparent.
uniform float skirt_fade_m : hint_range(1.0, 100.0) = 24.0;
// How much low-frequency noise stretches and shrinks the fade (0 = a clean rounded rect).
uniform float skirt_wobble : hint_range(0.0, 1.0) = 0.45;
#endif

varying vec3 v_tangent_u;
varying vec3 v_tangent_v;

const float INV_UINT_MAX = 1.0 / 4294967295.0;
// A weight at or below this is treated as absent (under half an 8-bit step).
const float WEIGHT_EPSILON = 0.002;
const int MAX_LAYERS = 4;
// Score of a surface not sampled at this pixel: far below any real score, so it never
// comes within biome_blend_width of the top.
const float ABSENT_SCORE = -1e6;

// Weights and per-cell transforms of the (up to) three cells blended at one point.
struct TileFrame {
	vec3 weights;
	vec2 centers[3];
	vec2 rotations[3];  // (cos, sin) of each cell's rotation
	vec2 offsets[3];    // offset in texture repeats
};

struct SurfaceSample {
	vec3 albedo;
	vec2 normal_uv;  // tangent normal xy in world-UV axes (+u = +X, +v = +Z)
	vec3 orm;
	float height;
};

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}

// Three decorrelated values in [0, 1] for one cell id.
vec3 cell_hash(ivec2 cell) {
	uvec2 a = pcg2d(uvec2(cell + ivec2(breakup_seed, breakup_seed * 7919)));
	uvec2 b = pcg2d(a ^ uvec2(0x68bc21ebu, 0x02e5be93u));
	return vec3(vec2(a), float(b.x)) * INV_UINT_MAX;
}

// The triangle-grid cells around a point (metres) and their hashed transforms.
TileFrame tile_frame(vec2 world_xz) {
	TileFrame f;
	if (!breakup_enabled) {
		f.weights = vec3(1.0, 0.0, 0.0);
		for (int i = 0; i < 3; i++) {
			f.centers[i] = vec2(0.0);
			f.rotations[i] = vec2(1.0, 0.0);
			f.offsets[i] = vec2(0.0);
		}
		return f;
	}
	vec2 st = world_xz / breakup_cell_m;
	// Skew so equilateral triangles become half unit squares.
	vec2 skewed = vec2(st.x - 0.57735027 * st.y, 1.15470054 * st.y);
	ivec2 base_id = ivec2(floor(skewed));
	vec3 bary = vec3(fract(skewed), 0.0);
	bary.z = 1.0 - bary.x - bary.y;
	float s = step(0.0, -bary.z);
	float s2 = 2.0 * s - 1.0;
	f.weights = vec3(-bary.z * s2, s - bary.y * s2, s - bary.x * s2);
	ivec2 ids[3];
	ids[0] = base_id + ivec2(int(s), int(s));
	ids[1] = base_id + ivec2(int(s), 1 - int(s));
	ids[2] = base_id + ivec2(1 - int(s), int(s));
	for (int i = 0; i < 3; i++) {
		vec2 id = vec2(ids[i]);
		// Unskew the vertex back to metres; each cell rotates around its own vertex so
		// the rotation does not swing texture further the further a cell is from origin.
		f.centers[i] = vec2(id.x + 0.5 * id.y, 0.8660254 * id.y) * breakup_cell_m;
		vec3 h = cell_hash(ids[i]);
		float angle = (h.x - 0.5) * TAU * breakup_rotation;
		f.rotations[i] = vec2(cos(angle), sin(angle));
		f.offsets[i] = h.yz * 16.0;
	}
	return f;
}

vec2 rotate(vec2 v, vec2 cs) {
	return vec2(cs.x * v.x - cs.y * v.y, cs.y * v.x + cs.x * v.y);
}

vec2 unrotate(vec2 v, vec2 cs) {
	return vec2(cs.x * v.x + cs.y * v.y, -cs.y * v.x + cs.x * v.y);
}

// One surface through the tile frame: 3 cells x (albedo, normal, ORM, height).
SurfaceSample sample_surface(
	sampler2D albedo_map, sampler2D normal_map, sampler2D orm_map, sampler2D height_map,
	float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy
) {
	vec3 albedo[3];
	vec2 normal_xy[3];
	vec3 orm[3];
	vec3 height;
	for (int i = 0; i < 3; i++) {
		vec2 cs = f.rotations[i];
		vec2 uv = rotate(world_xz - f.centers[i], cs) / tile + f.offsets[i];
		vec2 gx = rotate(dx, cs) / tile;
		vec2 gy = rotate(dy, cs) / tile;
		albedo[i] = textureGrad(albedo_map, uv, gx, gy).rgb;
		vec2 n = textureGrad(normal_map, uv, gx, gy).rg * 2.0 - 1.0;
		// OpenGL green is image-up, which is -v; then undo the cell rotation.
		normal_xy[i] = unrotate(vec2(n.x, -n.y), cs);
		orm[i] = textureGrad(orm_map, uv, gx, gy).rgb;
		height[i] = textureGrad(height_map, uv, gx, gy).r;
	}
	vec3 w = pow(max(f.weights, vec3(0.0)), vec3(breakup_sharpness));
	w *= mix(vec3(1.0), height + 0.05, breakup_contrast);
	w /= max(w.x + w.y + w.z, 1e-5);
	SurfaceSample result;
	result.albedo = albedo[0] * w.x + albedo[1] * w.y + albedo[2] * w.z;
	result.normal_uv = normal_xy[0] * w.x + normal_xy[1] * w.y + normal_xy[2] * w.z;
	result.orm = orm[0] * w.x + orm[1] * w.y + orm[2] * w.z;
	result.height = dot(height, w);
	return result;
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	uvec2 c = uvec2(ivec2(i) + ivec2(breakup_seed, breakup_seed * 7919));
	float a = float(pcg2d(c).x);
	float b = float(pcg2d(c + uvec2(1u, 0u)).x);
	float d = float(pcg2d(c + uvec2(0u, 1u)).x);
	float e = float(pcg2d(c + uvec2(1u, 1u)).x);
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y) * INV_UINT_MAX;
}

vec3 apply_variation(vec3 albedo, vec2 world_xz) {
	vec2 p = world_xz / variation_scale_m;
	float broad = value_noise(p) * 0.65 + value_noise(p * 2.7 + 17.3) * 0.35;
	albedo *= 1.0 + (broad - 0.5) * 2.0 * variation_value;
	// Signed drift: > 0 drier, < 0 lusher, a wide neutral band between.
	float drift = value_noise(p * 0.8 + vec2(41.7, -9.1)) * 0.7
		+ value_noise(p * 2.1 + vec2(-3.3, 27.9)) * 0.3;
	drift = drift * 2.0 - 1.0;
	// The tints are hue shifts for coloured ground (grass, earth); on a near-grey surface
	// such as snow they would read as dirty yellow and blue stains, so they fade out with
	// saturation. Grass, soil and sand are all well above the ramp.
	float top = max(albedo.r, max(albedo.g, albedo.b));
	float saturation = (top - min(albedo.r, min(albedo.g, albedo.b))) / max(top, 1e-4);
	float tint = variation_tint_amount * smoothstep(0.08, 0.3, saturation);
	float dry = smoothstep(0.1, 0.55, drift) * tint;
	float lush = smoothstep(0.1, 0.55, -drift) * tint;
	albedo *= mix(vec3(1.0), variation_dry_tint, dry);
	return albedo * mix(vec3(1.0), variation_lush_tint, lush);
}

// Per-layer painted weights at a point, with the edge warp and edge noise applied.
// Channels at or past biome_layer_count read 0.
vec4 biome_layer_weights(vec2 world_xz) {
	vec2 p = world_xz / biome_edge_scale_m;
	vec2 warp = vec2(value_noise(p + vec2(-23.1, 57.7)), value_noise(p + vec2(91.3, -12.9)));
	vec2 at = world_xz + (warp * 2.0 - 1.0) * biome_edge_warp_m;
	vec2 grid = vec2(textureSize(biome_weights, 0));
	vec2 st = ((at - biome_grid_origin) / biome_grid_step + 0.5) / grid;
	vec4 w = texture(biome_weights, st);
	w *= step(vec4(0.5, 1.5, 2.5, 3.5), vec4(float(biome_layer_count)));
	float total = w.x + w.y + w.z + w.w;
	if (total <= WEIGHT_EPSILON) {
		return vec4(0.0);
	}
	// Gain first, so the ground leads the scatter (which thins linearly with density) out
	// to the sparse fringe instead of leaving its outer plants standing on the base.
	float gained = min(total * biome_weight_gain, 1.0);
	// Finer than the warp, and zero at 0 and 1, so it only reshapes partial paint.
	float n = value_noise(p * 2.9 + vec2(7.9, 3.1));
	float bump = 4.0 * gained * (1.0 - gained);
	float shaped = clamp(gained + (n - 0.5) * 2.0 * biome_edge_noise * bump, 0.0, 1.0);
	return w * (shaped / total);
}

// Cubic B-spline sample from four bilinear taps (Sigg and Hadwiger), so a coarse texture
// reads as a smooth field instead of bilinear diamonds.
vec4 texture_bspline(sampler2D tex, vec2 uv) {
	vec2 size = vec2(textureSize(tex, 0));
	vec2 p = uv * size - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 s0 = w0 + w1;
	vec2 s1 = w2 + w3;
	vec2 uv0 = (i - 0.5 + w1 / s0) / size;
	vec2 uv1 = (i + 1.5 + w3 / s1) / size;
	return s0.y * (s0.x * texture(tex, uv0) + s1.x * texture(tex, vec2(uv1.x, uv0.y)))
		+ s1.y * (s0.x * texture(tex, vec2(uv0.x, uv1.y)) + s1.x * texture(tex, uv1));
}

// The broad scale of the two-scale edge: around each painted layer its ground colour (the
// last mip of its albedo, i.e. its mean) tints the surface in a wide, soft gradient, fading
// out where the fine, frayed edge (fine_w) already shows the layer itself.
vec3 apply_broad_edge(vec3 albedo, vec2 world_xz, vec4 fine_w) {
	vec2 grid = vec2(textureSize(biome_weights, 0));
	vec2 st = ((world_xz - biome_grid_origin) / biome_grid_step + 0.5) / grid;
	vec4 broad = texture_bspline(biome_broad, st);
	// Recolour rather than paint over: the layer's mean colour, carrying the ground's own
	// luminance detail relative to the base surface's mean.
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	float base_luma = max(dot(textureLod(albedo_tex, vec2(0.5), 16.0).rgb, LUMA), 0.02);
	float detail = dot(albedo, LUMA) / base_luma;
	for (int i = 0; i < MAX_LAYERS; i++) {
		if (i >= biome_layer_count || broad[i] <= WEIGHT_EPSILON) {
			continue;
		}
		float tint = biome_broad_strength * smoothstep(0.0, biome_broad_full, broad[i]);
		tint *= 1.0 - smoothstep(0.2, 0.8, fine_w[i]);
		if (tint > 0.001) {
			vec3 mean = textureLod(layer_albedo[i], vec2(0.5), 16.0).rgb;
			vec3 recoloured = clamp(mean * detail, vec3(0.0), vec3(1.0));
			albedo = mix(albedo, recoloured, tint);
		}
	}
	return albedo;
}

float blend_score(float weight, float height) {
	return weight + (height - 0.5) * biome_height_contrast;
}

#ifdef GROUND_SKIRT
// Skirt opacity at a point: 1 on the map edge, 0 from skirt_fade_m out. The distance is to
// the map rectangle (rounded at the corners) and is scaled by noise, which leaves the edge
// itself at exactly 1 so the skirt meets the map without a seam.
float skirt_alpha(vec2 world_xz) {
	float d = length(max(abs(world_xz) - skirt_half_extent, vec2(0.0)));
	vec2 p = world_xz / 11.0;
	float n = value_noise(p + vec2(3.7, -8.2)) * 0.7 + value_noise(p * 2.3 + vec2(-5.1, 2.9)) * 0.3;
	d *= 1.0 + (n - 0.5) * 2.0 * skirt_wobble;
	float t = clamp(d / skirt_fade_m, 0.0, 1.0);
	// Holds near the map, then falls off softly, like haze rather than a linear ramp.
	return 1.0 - t * t * (3.0 - 2.0 * t);
}
#endif

void vertex() {
	// Tangent frame of the planar world UV, in view space, for NORMAL in fragment().
	v_tangent_u = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	v_tangent_v = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

void fragment() {
	vec2 world_xz = UV;
	vec2 dx = dFdx(world_xz);
	vec2 dy = dFdy(world_xz);
#ifdef GROUND_SKIRT
	// More than half of the ring is past the fade. Discarding it before any texture work
	// takes a quarter off the skirt's cost at full zoom-out with bit-identical output (every
	// fetch below uses the explicit gradients taken above, so no quad helper lane is needed).
	float skirt_a = skirt_alpha(world_xz);
	if (skirt_a <= 0.0) {
		discard;
	}
#endif
	TileFrame frame = tile_frame(world_xz);

	// Index 0 is the base, 1..4 the biome layers. A surface is sampled only where it has
	// weight; the rest keep score ABSENT_SCORE and are never read. Some surface always has
	// weight: the base does whenever the layers sum to (almost) nothing.
	vec4 layer_w = vec4(0.0);
	if (biome_layer_count > 0) {
		layer_w = biome_layer_weights(world_xz);
	}
	float base_w = clamp(1.0 - (layer_w.x + layer_w.y + layer_w.z + layer_w.w), 0.0, 1.0);
	SurfaceSample samples[5];
	float scores[5];
	float top = ABSENT_SCORE;
	scores[0] = ABSENT_SCORE;
	if (base_w > WEIGHT_EPSILON) {
		samples[0] = sample_surface(
			albedo_tex, normal_tex, orm_tex, height_tex, tile_m, frame, world_xz, dx, dy
		);
		scores[0] = blend_score(base_w, samples[0].height);
		top = scores[0];
	}
	for (int i = 0; i < MAX_LAYERS; i++) {
		scores[i + 1] = ABSENT_SCORE;
		if (layer_w[i] > WEIGHT_EPSILON) {
			samples[i + 1] = sample_surface(
				layer_albedo[i], layer_normal[i], layer_orm[i], layer_height[i],
				layer_tile_m[i], frame, world_xz, dx, dy
			);
			scores[i + 1] = blend_score(layer_w[i], samples[i + 1].height);
			top = max(top, scores[i + 1]);
		}
	}
	SurfaceSample ground;
	ground.albedo = vec3(0.0);
	ground.normal_uv = vec2(0.0);
	ground.orm = vec3(0.0);
	ground.height = 0.0;
	float total = 0.0;
	for (int i = 0; i < MAX_LAYERS + 1; i++) {
		float b = scores[i] - (top - biome_blend_width);
		if (b > 0.0) {
			ground.albedo += samples[i].albedo * b;
			ground.normal_uv += samples[i].normal_uv * b;
			ground.orm += samples[i].orm * b;
			ground.height += samples[i].height * b;
			total += b;
		}
	}
	float inv_total = 1.0 / max(total, 1e-5);
	ground.albedo *= inv_total;
	ground.normal_uv *= inv_total;
	ground.orm *= inv_total;
	ground.height *= inv_total;
	if (biome_layer_count > 0) {
		ground.albedo = apply_broad_edge(ground.albedo, world_xz, layer_w);
	}

	// Cavity depth itself drifts at a few metres, so clumpy and smooth stretches alternate
	// instead of an even mottle.
	float clumpiness = mix(0.3, 1.0, value_noise(world_xz / 3.5 + vec2(-71.3, 13.9)));
	float cavity = mix(
		1.0 - cavity_strength * clumpiness, 1.0, smoothstep(0.0, 0.8, ground.height)
	);
	ALBEDO = apply_variation(ground.albedo * cavity, world_xz);
	AO = ground.orm.r;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = ground.orm.g;
	METALLIC = ground.orm.b;

	vec2 n_uv = ground.normal_uv * normal_strength;
	float n_z = sqrt(max(1.0 - dot(n_uv, n_uv), 0.0));
	vec3 n = normalize(NORMAL);
	vec3 t_u = normalize(v_tangent_u - n * dot(n, v_tangent_u));
	vec3 t_v = normalize(v_tangent_v - n * dot(n, v_tangent_v));
	NORMAL = normalize(n * n_z + t_u * n_uv.x + t_v * n_uv.y);
#ifdef GROUND_SKIRT
	ALPHA = skirt_a;
#endif
}
