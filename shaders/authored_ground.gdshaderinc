/*
 * Authored Ground Shader
 * ======================
 *
 * PURPOSE:
 * The ground of a map authored in tt-sim (AuthoredTerrain, scenes/terrain/). Tiles palette
 * surfaces (albedo, tangent-space normal, packed ORM, height) across the terrain chunks at
 * each surface's tile_m, hides that tiling at the game camera, blends up to eight layer
 * surfaces over the base (painted surfaces, painted biomes' ground, and the automatic
 * cliff and scree), and dresses the terrain by itself: rock on steep faces, scree at their
 * feet. A Blender-made map brings its terrain as a baked, non-repeating texture; this
 * shader has to reach a comparable read live from 2-3 m textures repeated across a 61 m map.
 *
 * FILES: this include is the whole shader. authored_ground.gdshader (opaque, the map) and
 * authored_ground_skirt.gdshader (transparent, GROUND_SKIRT defined) only declare the
 * shader type and render mode and include it, so the skirt continues the ground's exact
 * texture, anti-tiling and drifts across the map edge.
 *
 * FRAME: "map frame" below is the terrain node's local space, which is the MapDocument's
 * frame (chunk vertices are written in it; UV = its XZ). The rules read the normal and
 * position in this frame, so a scaled or offset level map dresses exactly as the CPU twin
 * of the rules (TerrainRules) computes.
 *
 * SKIRT (GROUND_SKIRT, added after T7 zoom-out renders): a ring of ground around the map
 * whose alpha falls from 1 at the map edge to 0 skirt_fade_m out, the fade distance
 * stretched by low-frequency noise so the outline is organic, not a rectangle. Alpha
 * rather than a colour fade, so it dissolves into whatever the background is (a flat
 * colour or, through the orthographic camera, a sky seen in one direction). Its geometry
 * rolls back down to the map floor (TerrainMeshBuilder.skirt_height), so a raised edge
 * does not run out into the fog as a shelf. The skirt binds no layers and runs no rules:
 * the weight maps clamp at their edge, which would streak.
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
 * STEEP FACES (phase 3, P3-4): a top-down projection stretches a texture by 1 / n.y, so a
 * 70 degree tier face would show its rock smeared into vertical streaks. Where n.y falls
 * below SIDE_START_NY a side projection (the plane facing X or Z, whichever the face turns
 * to) takes over, fully below SIDE_FULL_NY; near 45 degree corners both side planes blend
 * (their weights sharpened by SIDE_SHARPNESS, and a plane under SIDE_MIN_WEIGHT dropped),
 * so most steep pixels sample two projections, not three (biplanar cost, triplanar
 * seams). Above SIDE_START_NY the side code is branched over entirely: flat ground costs
 * what it did. Side planes use no mosaic breakup: cells rotate a texture, and a cliff's
 * layered beds must stay level; they run horizontally around the map at fixed heights,
 * image up = map up. Each plane has its own tangent frame (+u along the face, +v down,
 * OpenGL green = up), orthogonalised against the geometric normal, so normal maps light
 * correctly on every face.
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
 * BC5 (only R and G survive). The tangent frame of every projection is known without mesh
 * tangents: top-down, +u is map +X, +v is map +Z, and OpenGL green (+y, "up" in the
 * image) is -v; the sampled xy is rotated back out of each cell's rotation. Each surface's
 * perturbed normal is built in the map frame, surfaces and projections are blended, and the
 * result is written to NORMAL.
 *
 * LAYER TABLE (phase 3, P3-4; built by GroundLayerTable, utils/):
 * Up to 8 layer surfaces (layer_*[i]) blend over the base. layer_weights_a holds slots 0-3
 * and layer_weights_b slots 4-7, one RGBA8 texel per document sample, bilinear-filtered so
 * a 0.25 m grid gives smooth ramps. A slot is one of three kinds (layer_painted_mask and
 * layer_ground_mask say which; a slot in neither is a rule slot with an empty channel):
 *   - painted: a hand-painted surface; its channel is its painted weight, read through a
 *     small warp and edge noise (PAINT_*: a path keeps its line). Painted weight is drawn
 *     first and always wins: everything else shares 1 - the painted total.
 *   - ground: a painted biome's ground surface; its channel is the biome's painted density,
 *     shaped as below. The base surface is the ground's remainder.
 *   - rule: a biome's cliff or scree surface that nothing else draws.
 * The automatic rules then take their share of the unpainted ground: rule_weights() (cliff
 * from slope, scree at concave feet; TerrainRules is the CPU twin, constants below)
 * multiplied by 1 - painted total. The cliff share is handed out per ground component (each
 * ground slot and the base) in proportion to its weight, to that component's cliff surface
 * (rule_cliff_layer[j], index 8 = the base, -1 = none: the share stays with the ground);
 * scree likewise. So a sample's rock is its own biome's rock.
 * The tile frame is computed once per pixel and shared: each surface costs only its own
 * fetches, and a surface whose weight is zero at a pixel is not sampled at all.
 * A painted biome's edge is made to look like ground rather than a brush circle, the way
 * terrain-paint's Edge Noise and Height Blend do it in a bake:
 *   - domain warp: the weight map is read at a noise-displaced position (up to
 *     biome_edge_warp_m), so a round dab's outline wanders; this frays even a hard edge;
 *   - edge noise: the painted total is pushed up or down by finer noise, most where it is
 *     partial (a density falloff, a sparse fill) and not at all where it is 0 or 1, so a
 *     half-painted stretch breaks into patches instead of a uniform half-blend;
 *   - height blend: each surface scores weight + (height - 0.5) * biome_height_contrast
 *     and only surfaces within biome_blend_width of the top score show, so at a boundary
 *     the taller texture detail (clumps, needles, stones) wins and the line follows the
 *     textures rather than a gradient. Rule and painted weights go through the same score,
 *     which is how terrain-paint's height blend factor enters: rock juts out of the grass
 *     where the rock texture is high.
 *
 * AUTOMATIC RULES (rule_weights; formulas and defaults in utils/terrain_rules.gd, whose
 * constants are mirrored below and checked by tests/unit/test_terrain_rules.gd):
 *   - cliff: terrain-paint's slope tail on n.y (CLIFF_START_COS .. CLIFF_END_COS), edge
 *     noise added before the clamp, a convex lip taking some rock back (the per-vertex
 *     curvature in UV2.x), smoothstep;
 *   - scree: concave curvature tail with edge noise, times the steepness nearby (UV2.y),
 *     smoothstep, never under the cliff.
 * The noise domain is sheared by height so it varies up a face.
 *
 * BROAD EDGE (the second scale of a two-scale edge, added after T7 renders beside the
 * river map): the frayed edge above is a few decimetres wide and on its own reads like a
 * decal laid on the lawn, where a hand-painted Blender layer fades over several metres.
 * layer_broad_a/b are the weight maps box-filtered to GroundLayerTable.BROAD_FACTOR samples
 * per texel (3.5 m at the default 0.25 m step) and read with a cubic B-spline, so around
 * each painted biome the ground slot's mean colour (the last mip of its albedo) recolours
 * the ground in a gradient about 7 m wide. Ground slots only: a painted path gets no halo.
 * It recolours by luminance (layer mean x the pixel's luminance relative to the base
 * mean), so the base texture keeps its detail and no hue is amplified. The tint fades out
 * where the fine edge already shows the layer itself.
 *
 * COST: 12 fetches plus 26 small integer hashes per pixel for the base alone; measured
 * about 1.4x a StandardMaterial3D ground with the same textures. The rules add one
 * two-octave value noise wherever the slope is within reach of the cliff band (and one
 * more near steep feet). Layers add their weight fetches, plus 12 fetches per surface
 * present at a pixel top-down and 4 per side plane on steep pixels
 * (docs/PERFORMANCE.md "Ground shader: 8 layers, rules, steep faces").
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

// Layer table (see LAYER TABLE above). Slots at index >= layer_count are unbound.
uniform int layer_count : hint_range(0, 8) = 0;
// Bit j set: slot j is a painted surface / a biome ground surface.
uniform int layer_painted_mask = 0;
uniform int layer_ground_mask = 0;
uniform sampler2D layer_weights_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D layer_weights_b : hint_default_black, filter_linear, repeat_disable;
// World XZ of document sample (0, 0) and the real sample step, in metres.
uniform vec2 layer_grid_origin = vec2(0.0);
uniform vec2 layer_grid_step = vec2(0.25);
uniform sampler2D layer_albedo[8] : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Sampler arrays take no default or normal hints, so AuthoredTerrain binds every entry.
uniform sampler2D layer_normal[8] : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_orm[8] : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_height[8] : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layer_tile_m[8];
// Per ground component (slots 0-7, then the base at 8): the slot drawing its cliff and
// scree (8 = the base, -1 = none).
uniform int rule_cliff_layer[9];
uniform int rule_scree_layer[9];
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
// Broad scale of the two-scale edge (see BROAD EDGE): the weight maps box-filtered to a few
// metres per texel (GroundLayerTable.broad_image), read with a B-spline so they are smooth.
uniform sampler2D layer_broad_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D layer_broad_b : hint_default_black, filter_linear, repeat_disable;
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

// Map-frame normal, position and the per-vertex rule fields (UV2: curvature, steepness).
varying vec3 v_normal;
varying vec3 v_position;
varying vec2 v_fields;

const float INV_UINT_MAX = 1.0 / 4294967295.0;
// A weight at or below this is treated as absent (under half an 8-bit step).
const float WEIGHT_EPSILON = 0.002;
const int MAX_LAYERS = 8;
// Index of the base surface in the per-pixel weight arrays.
const int BASE = 8;
// Upper bound of the per-slot sampling loops: layer_count (a uniform, so they stay loops
// indexed by a dynamically uniform counter) measured equal or up to 0.1 ms faster than
// MAX_LAYERS (a constant, so they unroll eight copies of the sampling code); PERFORMANCE.md
// "Ground shader: 8 layers, rules, steep faces".
#define SLOT_LOOP_END layer_count
// Score of a surface not sampled at this pixel: far below any real score, so it never
// comes within biome_blend_width of the top.
const float ABSENT_SCORE = -1e6;

// Steep faces (see STEEP FACES): side planes start below this n.y (about 44 degrees) and
// take over fully below SIDE_FULL_NY (about 65 degrees). Projections meet by a height
// blend (PROJECTION_CONTRAST, PROJECTION_BAND: the taller detail wins, as between
// surfaces), not a cross-fade, which double-exposed two rock patterns into a smear.
const float SIDE_START_NY = 0.72;
const float SIDE_FULL_NY = 0.42;
const float SIDE_SHARPNESS = 8.0;
const float SIDE_MIN_WEIGHT = 0.04;
const float PROJECTION_CONTRAST = 0.8;
const float PROJECTION_BAND = 0.12;

// Automatic rules: the twins of TerrainRules' constants (tests/unit/test_terrain_rules.gd
// checks every value). CLIFF_*_COS are cos(CLIFF_START_DEG) and cos(CLIFF_END_DEG).
const float CLIFF_START_COS = 0.788011;
const float CLIFF_END_COS = 0.573576;
const float CLIFF_EDGE_NOISE = 0.35;
const float LIP_CURVATURE_START = 0.03;
const float LIP_CURVATURE_END = 0.12;
const float LIP_STRENGTH = 0.6;
const float LIP_SHEER_TAIL = 2.0;
const float RAMP_LOW = 0.2;
const float RAMP_HIGH = 0.8;
const float SCREE_CURVATURE_START = 0.02;
const float SCREE_CURVATURE_END = 0.12;
const float SCREE_NEAR_START = 0.03;
const float SCREE_NEAR_END = 0.1;
const float SCREE_EDGE_NOISE = 0.4;
const float SCREE_BREAKUP_SCALE_M = 2.6;
const float SCREE_FAN = 1.6;
const float SCREE_BREAKUP_LOW = 0.15;
const float SCREE_BREAKUP_HIGH = 0.45;
const float RULE_NOISE_SCALE_M = 1.6;
const float RULE_NOISE_SHEAR = 0.8;
const vec2 CLIFF_NOISE_OFFSET = vec2(13.7, -41.3);
const vec2 SCREE_NOISE_OFFSET = vec2(-27.9, 8.6);
const vec2 SCREE_BREAKUP_OFFSET = vec2(61.3, 19.4);
const float PAINT_EDGE_WARP_M = 0.3;
const float PAINT_EDGE_SCALE_M = 1.4;
const float PAINT_EDGE_NOISE = 0.35;
const vec2 PAINT_WARP_OFFSET_A = vec2(-23.1, 57.7);
const vec2 PAINT_WARP_OFFSET_B = vec2(91.3, -12.9);
const vec2 PAINT_NOISE_OFFSET = vec2(7.9, 3.1);

// Weights and per-cell transforms of the (up to) three cells blended at one point.
struct TileFrame {
	vec3 weights;
	vec2 centers[3];
	vec2 rotations[3];  // (cos, sin) of each cell's rotation
	vec2 offsets[3];    // offset in texture repeats
};

// One top-down sample (tangent normal xy in map-frame UV axes: +u = +X, +v = +Z).
struct TopSample {
	vec3 albedo;
	vec2 normal_uv;
	vec3 orm;
	float height;
};

// Weighted sums of surfaces at one pixel; normal is the perturbed map-frame normal (not
// normalised).
struct SurfaceSample {
	vec3 albedo;
	vec3 normal;
	vec3 orm;
	float height;
};

// One side plane of a pixel: UV and its screen gradients in metres, and the plane's tangent
// frame in the map frame (t: +u, b: image up, both orthogonal to the geometric normal).
struct SidePlane {
	vec2 uv;
	vec2 gx;
	vec2 gy;
	vec3 t;
	vec3 b;
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

// One surface top-down through the tile frame: 3 cells x (albedo, normal, ORM, height).
TopSample sample_top(
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
	TopSample result;
	result.albedo = albedo[0] * w.x + albedo[1] * w.y + albedo[2] * w.z;
	result.normal_uv = normal_xy[0] * w.x + normal_xy[1] * w.y + normal_xy[2] * w.z;
	result.orm = orm[0] * w.x + orm[1] * w.y + orm[2] * w.z;
	result.height = dot(height, w);
	return result;
}

// A tangent-space normal xy (scaled by normal_strength) on frame (t, b, n), map frame.
vec3 perturb(vec2 xy, vec3 t, vec3 b, vec3 n) {
	vec2 s = xy * normal_strength;
	float z = sqrt(max(1.0 - dot(s, s), 0.0));
	return n * z + t * s.x + b * s.y;
}

// Gram-Schmidt: `v` made orthogonal to unit `n`, normalised.
vec3 orthogonal(vec3 v, vec3 n) {
	return normalize(v - n * dot(n, v));
}

// Side plane `plane` (0: facing X, 1: facing Z) of a pixel with map-frame normal `n` at
// map-frame position `p` (screen derivatives dpx, dpy): +u to the viewer's right looking
// at the face, +v down the image, image up = map up, so layered beds stay level.
SidePlane side_plane(int plane, vec3 n, vec3 p, vec3 dpx, vec3 dpy) {
	SidePlane s;
	if (plane == 0) {
		float sx = n.x >= 0.0 ? 1.0 : -1.0;
		s.t = orthogonal(vec3(0.0, 0.0, -sx), n);
		s.uv = vec2(-sx * p.z, -p.y);
		s.gx = vec2(-sx * dpx.z, -dpx.y);
		s.gy = vec2(-sx * dpy.z, -dpy.y);
	} else {
		float sz = n.z >= 0.0 ? 1.0 : -1.0;
		s.t = orthogonal(vec3(sz, 0.0, 0.0), n);
		// Offset so the two planes show different parts of the texture at a corner.
		s.uv = vec2(sz * p.x + 0.37, -p.y + 0.61);
		s.gx = vec2(sz * dpx.x, -dpx.y);
		s.gy = vec2(sz * dpy.x, -dpy.y);
	}
	s.b = orthogonal(vec3(0.0, 1.0, 0.0) - s.t * s.t.y, n);
	return s;
}

// The projection weights of a pixel with map-frame normal `n` before any height blend (x:
// the X-facing plane, y: top-down, z: the Z-facing plane); exactly (0, 1, 0) above
// SIDE_START_NY, which is what lets flat ground skip the side code.
vec3 projection_weights(vec3 n) {
	float side = 1.0 - smoothstep(SIDE_FULL_NY, SIDE_START_NY, n.y);
	if (side <= 0.0) {
		return vec3(0.0, 1.0, 0.0);
	}
	vec2 planes = pow(abs(n.xz) + 1e-4, vec2(SIDE_SHARPNESS));
	planes /= planes.x + planes.y;
	planes = max(planes - SIDE_MIN_WEIGHT, vec2(0.0));
	planes /= max(planes.x + planes.y, 1e-5);
	return vec3(planes.x * side, 1.0 - side, planes.y * side);
}

// One surface's top-down height through the tile frame (sample_top's blend, height only).
float top_height(sampler2D height_map, float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy) {
	vec3 height;
	for (int i = 0; i < 3; i++) {
		vec2 cs = f.rotations[i];
		vec2 uv = rotate(world_xz - f.centers[i], cs) / tile + f.offsets[i];
		height[i] = textureGrad(height_map, uv, rotate(dx, cs) / tile, rotate(dy, cs) / tile).r;
	}
	vec3 w = pow(max(f.weights, vec3(0.0)), vec3(breakup_sharpness));
	w *= mix(vec3(1.0), height + 0.05, breakup_contrast);
	return dot(height, w / max(w.x + w.y + w.z, 1e-5));
}

// One surface's projection weights at a pixel after the projections' height blend (the
// taller detail wins, PROJECTION_CONTRAST / PROJECTION_BAND), and in `height` its blended
// height (only computed on flat ground when `need_height`). Heights only: the full
// samples are taken by accumulate(), so nothing large stays live between surfaces.
vec3 surface_projections(
	sampler2D height_map, float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy, vec3 n,
	vec3 p, vec3 dpx, vec3 dpy, vec3 proj, bool need_height, out float height
) {
	height = 0.5;
	if (proj.y >= 1.0) {
		if (need_height) {
			height = top_height(height_map, tile, f, world_xz, dx, dy);
		}
		return proj;
	}
	vec3 h = vec3(0.5);
	vec3 score = vec3(ABSENT_SCORE);
	if (proj.y > 0.0) {
		h.y = top_height(height_map, tile, f, world_xz, dx, dy);
		score.y = proj.y + (h.y - 0.5) * PROJECTION_CONTRAST;
	}
	if (proj.x > 0.0) {
		SidePlane s = side_plane(0, n, p, dpx, dpy);
		h.x = textureGrad(height_map, s.uv / tile, s.gx / tile, s.gy / tile).r;
		score.x = proj.x + (h.x - 0.5) * PROJECTION_CONTRAST;
	}
	if (proj.z > 0.0) {
		SidePlane s = side_plane(1, n, p, dpx, dpy);
		h.z = textureGrad(height_map, s.uv / tile, s.gx / tile, s.gy / tile).r;
		score.z = proj.z + (h.z - 0.5) * PROJECTION_CONTRAST;
	}
	float best = max(score.x, max(score.y, score.z));
	vec3 w = max(score - (best - PROJECTION_BAND), vec3(0.0));
	w /= max(w.x + w.y + w.z, 1e-5);
	height = dot(h, w);
	return w;
}

// Adds `weight` times one surface, through the projections weighted by `pw`, to `acc`.
void accumulate(
	sampler2D albedo_map, sampler2D normal_map, sampler2D orm_map, sampler2D height_map,
	float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy, vec3 n, vec3 p, vec3 dpx,
	vec3 dpy, vec3 pw, float weight, inout SurfaceSample acc
) {
	if (pw.y > 0.0) {
		TopSample top = sample_top(
			albedo_map, normal_map, orm_map, height_map, tile, f, world_xz, dx, dy
		);
		float k = pw.y * weight;
		vec3 top_u = orthogonal(vec3(1.0, 0.0, 0.0), n);
		vec3 top_v = orthogonal(vec3(0.0, 0.0, 1.0), n);
		acc.albedo += top.albedo * k;
		acc.normal += perturb(top.normal_uv, top_u, top_v, n) * k;
		acc.orm += top.orm * k;
		acc.height += top.height * k;
	}
	for (int plane = 0; plane < 2; plane++) {
		float k = (plane == 0 ? pw.x : pw.z) * weight;
		if (k > 0.0) {
			SidePlane s = side_plane(plane, n, p, dpx, dpy);
			vec2 uv = s.uv / tile;
			vec2 gx = s.gx / tile;
			vec2 gy = s.gy / tile;
			acc.albedo += textureGrad(albedo_map, uv, gx, gy).rgb * k;
			vec2 nm = textureGrad(normal_map, uv, gx, gy).rg * 2.0 - 1.0;
			acc.normal += perturb(nm, s.t, s.b, n) * k;
			acc.orm += textureGrad(orm_map, uv, gx, gy).rgb * k;
			acc.height += textureGrad(height_map, uv, gx, gy).r * k;
		}
	}
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

// The weight-map texture coordinate of map-frame XZ `at`.
vec2 weight_uv(vec2 at) {
	vec2 grid = vec2(textureSize(layer_weights_a, 0));
	return ((at - layer_grid_origin) / layer_grid_step + 0.5) / grid;
}

// The four bits of `mask` from bit `first` as 0/1 channels.
vec4 mask_channels(int mask, int first) {
	int m = mask >> first;
	return vec4(float(m & 1), float((m >> 1) & 1), float((m >> 2) & 1), float((m >> 3) & 1));
}

// Painted density of the ground slots at a point (a: slots 0-3, b: 4-7), with the edge
// warp, gain and edge noise applied.
void ground_weights(vec2 world_xz, out vec4 a, out vec4 b) {
	vec2 p = world_xz / biome_edge_scale_m;
	vec2 warp = vec2(value_noise(p + vec2(-23.1, 57.7)), value_noise(p + vec2(91.3, -12.9)));
	vec2 st = weight_uv(world_xz + (warp * 2.0 - 1.0) * biome_edge_warp_m);
	a = texture(layer_weights_a, st) * mask_channels(layer_ground_mask, 0);
	b = vec4(0.0);
	if ((layer_ground_mask >> 4) != 0) {
		b = texture(layer_weights_b, st) * mask_channels(layer_ground_mask, 4);
	}
	float total = dot(a, vec4(1.0)) + dot(b, vec4(1.0));
	if (total <= WEIGHT_EPSILON) {
		a = vec4(0.0);
		b = vec4(0.0);
		return;
	}
	// Gain first, so the ground leads the scatter (which thins linearly with density) out
	// to the sparse fringe instead of leaving its outer plants standing on the base.
	float gained = min(total * biome_weight_gain, 1.0);
	// Finer than the warp, and zero at 0 and 1, so it only reshapes partial paint.
	float n = value_noise(p * 2.9 + vec2(7.9, 3.1));
	float bump = 4.0 * gained * (1.0 - gained);
	float shaped = clamp(gained + (n - 0.5) * 2.0 * biome_edge_noise * bump, 0.0, 1.0);
	a *= shaped / total;
	b *= shaped / total;
}

// Painted weight of the painted slots at a point (TerrainRules.painted_lookup and
// shape_painted are the CPU twins).
void painted_weights(vec2 world_xz, out vec4 a, out vec4 b) {
	vec2 p = world_xz / PAINT_EDGE_SCALE_M;
	vec2 warp = vec2(value_noise(p + PAINT_WARP_OFFSET_A), value_noise(p + PAINT_WARP_OFFSET_B));
	vec2 st = weight_uv(world_xz + (warp * 2.0 - 1.0) * PAINT_EDGE_WARP_M);
	a = texture(layer_weights_a, st) * mask_channels(layer_painted_mask, 0);
	b = vec4(0.0);
	if ((layer_painted_mask >> 4) != 0) {
		b = texture(layer_weights_b, st) * mask_channels(layer_painted_mask, 4);
	}
	float total = dot(a, vec4(1.0)) + dot(b, vec4(1.0));
	if (total <= WEIGHT_EPSILON) {
		a = vec4(0.0);
		b = vec4(0.0);
		return;
	}
	float n = value_noise(p * 2.9 + PAINT_NOISE_OFFSET);
	float bump = 4.0 * total * (1.0 - total);
	float shaped = clamp(total + (n - 0.5) * 2.0 * PAINT_EDGE_NOISE * bump, 0.0, 1.0);
	a *= shaped / total;
	b *= shaped / total;
}

// Two-octave rule noise at map-frame point (xz, y), sheared by height
// (TerrainRules.rule_noise).
float rule_noise(vec2 xz, float y, vec2 offset) {
	vec2 p = (xz + vec2(y * RULE_NOISE_SHEAR, -y * RULE_NOISE_SHEAR)) / RULE_NOISE_SCALE_M;
	p += offset;
	return value_noise(p) * 0.65 + value_noise(p * 2.3 + vec2(5.2, -1.7)) * 0.35;
}

// The shaping ramp with EASE interpolation (TerrainRules.ease_ramp).
float ease_ramp(float m) {
	float t = clamp((m - RAMP_LOW) / (RAMP_HIGH - RAMP_LOW), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

// (cliff, scree) weights of the automatic rules (TerrainRules.weights).
vec2 rule_weights(float ny, vec2 fields, vec3 p) {
	float cliff = 0.0;
	float raw = (ny - CLIFF_START_COS) / (CLIFF_END_COS - CLIFF_START_COS);
	if (raw > -CLIFF_EDGE_NOISE) {
		float n = rule_noise(p.xz, p.y, CLIFF_NOISE_OFFSET);
		float m = clamp(raw + mix(-CLIFF_EDGE_NOISE, CLIFF_EDGE_NOISE, n), 0.0, 1.0);
		float lip = clamp(
			(fields.x - LIP_CURVATURE_START) / (LIP_CURVATURE_END - LIP_CURVATURE_START),
			0.0,
			1.0
		);
		lip *= clamp(LIP_SHEER_TAIL - raw, 0.0, 1.0);
		m *= 1.0 - LIP_STRENGTH * lip;
		cliff = ease_ramp(m);
	}
	float scree = 0.0;
	float concave = (-fields.x - SCREE_CURVATURE_START)
		/ (SCREE_CURVATURE_END - SCREE_CURVATURE_START);
	if (fields.y > SCREE_NEAR_START && concave > -SCREE_EDGE_NOISE - 0.5 * SCREE_FAN) {
		float near = clamp(
			(fields.y - SCREE_NEAR_START) / (SCREE_NEAR_END - SCREE_NEAR_START), 0.0, 1.0
		);
		float n = rule_noise(p.xz, p.y, SCREE_NOISE_OFFSET);
		float breakup = value_noise(p.xz / SCREE_BREAKUP_SCALE_M + SCREE_BREAKUP_OFFSET);
		concave += mix(-SCREE_EDGE_NOISE, SCREE_EDGE_NOISE, n) + (breakup - 0.5) * SCREE_FAN;
		float m = clamp(concave, 0.0, 1.0) * near;
		float gaps = smoothstep(SCREE_BREAKUP_LOW, SCREE_BREAKUP_HIGH, breakup);
		scree = ease_ramp(m) * gaps * (1.0 - cliff);
	}
	return vec2(cliff, scree);
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

// The broad scale of the two-scale edge: around each ground slot's painted area its mean
// colour tints the surface in a wide, soft gradient, fading out where the fine, frayed
// edge (fine_a / fine_b) already shows the layer itself.
vec3 apply_broad_edge(vec3 albedo, vec2 world_xz, vec4 fine_a, vec4 fine_b) {
	vec2 st = weight_uv(world_xz);
	vec4 broad[2];
	broad[0] = texture_bspline(layer_broad_a, st) * mask_channels(layer_ground_mask, 0);
	broad[1] = vec4(0.0);
	if ((layer_ground_mask >> 4) != 0) {
		broad[1] = texture_bspline(layer_broad_b, st) * mask_channels(layer_ground_mask, 4);
	}
	vec4 fine[2];
	fine[0] = fine_a;
	fine[1] = fine_b;
	// Recolour rather than paint over: the layer's mean colour, carrying the ground's own
	// luminance detail relative to the base surface's mean.
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	float base_luma = max(dot(textureLod(albedo_tex, vec2(0.5), 16.0).rgb, LUMA), 0.02);
	float detail = dot(albedo, LUMA) / base_luma;
	for (int i = 0; i < MAX_LAYERS; i++) {
		float w = broad[i / 4][i % 4];
		if (i >= layer_count || w <= WEIGHT_EPSILON) {
			continue;
		}
		float tint = biome_broad_strength * smoothstep(0.0, biome_broad_full, w);
		tint *= 1.0 - smoothstep(0.2, 0.8, fine[i / 4][i % 4]);
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
	v_normal = NORMAL;
	v_position = VERTEX;
	v_fields = UV2;
}

void fragment() {
	vec2 world_xz = UV;
	vec2 dx = dFdx(world_xz);
	vec2 dy = dFdy(world_xz);
	vec3 dpx = dFdx(v_position);
	vec3 dpy = dFdy(v_position);
#ifdef GROUND_SKIRT
	// More than half of the ring is past the fade. Discarding it before any texture work
	// takes a quarter off the skirt's cost at full zoom-out with bit-identical output (every
	// fetch below uses the explicit gradients taken above, so no quad helper lane is needed).
	float skirt_a = skirt_alpha(world_xz);
	if (skirt_a <= 0.0) {
		discard;
	}
#endif
	vec3 n_geom = normalize(v_normal);
	TileFrame frame = tile_frame(world_xz);
	vec3 proj = projection_weights(n_geom);

	// Weights per slot (0-7) and the base (BASE). Painted first; the rest of the ground
	// (biome ground and base) shares what the painting leaves, and the rules take their
	// share of that.
	float w[9];
	for (int i = 0; i < 9; i++) {
		w[i] = 0.0;
	}
	vec4 ground_a = vec4(0.0);
	vec4 ground_b = vec4(0.0);
	vec4 painted_a = vec4(0.0);
	vec4 painted_b = vec4(0.0);
#ifndef GROUND_SKIRT
	if (layer_count > 0) {
		if (layer_ground_mask != 0) {
			ground_weights(world_xz, ground_a, ground_b);
		}
		if (layer_painted_mask != 0) {
			painted_weights(world_xz, painted_a, painted_b);
		}
	}
#endif
	float painted_total = dot(painted_a, vec4(1.0)) + dot(painted_b, vec4(1.0));
	float unpainted = clamp(1.0 - painted_total, 0.0, 1.0);
	float g[9];
	for (int i = 0; i < 4; i++) {
		g[i] = ground_a[i];
		g[i + 4] = ground_b[i];
		w[i] = painted_a[i];
		w[i + 4] = painted_b[i];
	}
	g[BASE] = clamp(1.0 - dot(ground_a, vec4(1.0)) - dot(ground_b, vec4(1.0)), 0.0, 1.0);
	vec2 rule = vec2(0.0);
#ifndef GROUND_SKIRT
	if (unpainted > WEIGHT_EPSILON) {
		rule = rule_weights(n_geom.y, v_fields, v_position);
	}
#endif
	float keep = unpainted * (1.0 - rule.x - rule.y);
	float cliff = unpainted * rule.x;
	float scree = unpainted * rule.y;
	for (int j = 0; j < 9; j++) {
		w[j] += g[j] * keep;
	}
	if (cliff > 0.0 || scree > 0.0) {
		// Each ground component hands its share to its rule slots (-1: it keeps it). Constant
		// indices only, so w[] stays in registers.
		for (int k = 0; k < 9; k++) {
			float add = 0.0;
			for (int j = 0; j < 9; j++) {
				int to_cliff = rule_cliff_layer[j] >= 0 ? rule_cliff_layer[j] : j;
				int to_scree = rule_scree_layer[j] >= 0 ? rule_scree_layer[j] : j;
				add += g[j] * (cliff * float(to_cliff == k) + scree * float(to_scree == k));
			}
			w[k] += add;
		}
	}

	// A surface is sampled only where it has weight. One surface (most of the ground) is
	// drawn directly; several are height-blended in two passes, heights first to find the
	// top score, then full samples of the surfaces within the blend band, so no surface's
	// sample has to stay live while the others are fetched.
	int count = 0;
	for (int i = 0; i < MAX_LAYERS; i++) {
		count += (i < layer_count && w[i] > WEIGHT_EPSILON) ? 1 : 0;
	}
	bool base_in = w[BASE] > WEIGHT_EPSILON || count == 0;
	count += base_in ? 1 : 0;
	float scores[9];
	float top = ABSENT_SCORE;
	if (count > 1) {
		for (int i = 0; i < MAX_LAYERS; i++) {
			scores[i] = ABSENT_SCORE;
		}
		for (int i = 0; i < SLOT_LOOP_END; i++) {
			if (i < layer_count && w[i] > WEIGHT_EPSILON) {
				float h;
				surface_projections(
					layer_height[i], layer_tile_m[i], frame, world_xz, dx, dy, n_geom,
					v_position, dpx, dpy, proj, true, h
				);
				scores[i] = blend_score(w[i], h);
				top = max(top, scores[i]);
			}
		}
		scores[BASE] = ABSENT_SCORE;
		if (base_in) {
			float h;
			surface_projections(
				height_tex, tile_m, frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy,
				proj, true, h
			);
			scores[BASE] = blend_score(w[BASE], h);
			top = max(top, scores[BASE]);
		}
	}
	SurfaceSample ground;
	ground.albedo = vec3(0.0);
	ground.normal = vec3(0.0);
	ground.orm = vec3(0.0);
	ground.height = 0.0;
	float total = 0.0;
	for (int i = 0; i < SLOT_LOOP_END; i++) {
		if (i < layer_count && w[i] > WEIGHT_EPSILON) {
			float b = count > 1 ? scores[i] - (top - biome_blend_width) : 1.0;
			if (b > 0.0) {
				float h;
				vec3 pw = surface_projections(
					layer_height[i], layer_tile_m[i], frame, world_xz, dx, dy, n_geom,
					v_position, dpx, dpy, proj, false, h
				);
				accumulate(
					layer_albedo[i], layer_normal[i], layer_orm[i], layer_height[i],
					layer_tile_m[i], frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy, pw,
					b, ground
				);
				total += b;
			}
		}
	}
	if (base_in) {
		float b = count > 1 ? scores[BASE] - (top - biome_blend_width) : 1.0;
		if (b > 0.0) {
			float h;
			vec3 pw = surface_projections(
				height_tex, tile_m, frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy,
				proj, false, h
			);
			accumulate(
				albedo_tex, normal_tex, orm_tex, height_tex, tile_m, frame, world_xz, dx, dy,
				n_geom, v_position, dpx, dpy, pw, b, ground
			);
			total += b;
		}
	}
	float inv_total = 1.0 / max(total, 1e-5);
	ground.albedo *= inv_total;
	ground.orm *= inv_total;
	ground.height *= inv_total;
#ifndef GROUND_SKIRT
	if (layer_ground_mask != 0) {
		ground.albedo = apply_broad_edge(ground.albedo, world_xz, ground_a, ground_b);
	}
#endif

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

	vec3 n_map = normalize(ground.normal + n_geom * 1e-4);
	NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * n_map));
#ifdef GROUND_SKIRT
	ALPHA = skirt_a;
#endif
}
