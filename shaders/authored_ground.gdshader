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
 * PHASE 3 (splatting): sample_surface() takes its textures as arguments and the tile frame
 * (cell weights and transforms) is computed once per pixel in metres, independent of any
 * surface, so up to 8 splat-weighted surfaces can share one frame and each cost only its
 * own fetches (in practice the top 2-3 weights per pixel). SurfaceSample.height is the
 * blended height each surface needs for height-blended transitions between surfaces.
 *
 * COST: 12 fetches plus 26 small integer hashes per pixel; measured about 1.4x a
 * StandardMaterial3D ground with the same textures (docs/ARCHITECTURE.md "Authored
 * terrain").
 *
 * LIGHTING matches the StandardMaterial3D terrain of a Blender-made map: burley diffuse,
 * schlick GGX specular at the default 0.5, AO from ORM.r affecting ambient only
 * (StandardMaterial3D's ao_light_affect = 0), roughness ORM.g, metallic ORM.b. Shadows and
 * the lo-fi post pass apply as to any opaque surface.
 */

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

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

varying vec3 v_tangent_u;
varying vec3 v_tangent_v;

const float INV_UINT_MAX = 1.0 / 4294967295.0;

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
	float dry = smoothstep(0.1, 0.55, drift) * variation_tint_amount;
	float lush = smoothstep(0.1, 0.55, -drift) * variation_tint_amount;
	albedo *= mix(vec3(1.0), variation_dry_tint, dry);
	return albedo * mix(vec3(1.0), variation_lush_tint, lush);
}

void vertex() {
	// Tangent frame of the planar world UV, in view space, for NORMAL in fragment().
	v_tangent_u = (MODELVIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	v_tangent_v = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
}

void fragment() {
	vec2 world_xz = UV;
	vec2 dx = dFdx(world_xz);
	vec2 dy = dFdy(world_xz);
	TileFrame frame = tile_frame(world_xz);
	SurfaceSample ground = sample_surface(
		albedo_tex, normal_tex, orm_tex, height_tex, tile_m, frame, world_xz, dx, dy
	);

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
}
