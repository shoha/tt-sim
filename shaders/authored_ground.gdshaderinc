/*
 * Authored Ground Shader
 * ======================
 *
 * PURPOSE:
 * The ground of a map authored in tt-sim (AuthoredTerrain, scenes/terrain/). Tiles palette
 * surfaces (albedo, tangent-space normal, packed ORM, height) across the terrain chunks at
 * each surface's tile_m, hides that tiling at the game camera, blends the few surfaces present
 * around each pixel out of every surface the map uses (painted surfaces, painted biomes' ground,
 * their accents, and the automatic cliff and scree), and dresses the terrain by itself: rock on
 * steep faces, scree at their
 * feet. A Blender-made map brings its terrain as a baked, non-repeating texture; this
 * shader has to reach a comparable read live from 2-3 m textures repeated across a 61 m map.
 *
 * FILES: this include is the whole shader. authored_ground.gdshader (the map) and
 * authored_ground_skirt.gdshader (GROUND_SKIRT defined) only declare the shader type and
 * render mode and include it, so the skirt continues the ground's exact texture, anti-tiling
 * and drifts across the map edge. Both are opaque.
 *
 * FRAME: "map frame" below is the terrain node's local space, which is the MapDocument's
 * frame (chunk vertices are written in it; UV = its XZ). The rules read the normal and
 * position in this frame, so a scaled or offset level map dresses exactly as the CPU twin
 * of the rules (TerrainRules) computes.
 *
 * SKIRT (GROUND_SKIRT, added after T7 zoom-out renders): a ring of ground around the map
 * that fades from the ground at the map edge to the backdrop skirt_fade_m out
 * (skirt_alpha(), skirt_fade.gdshaderinc), the fade distance stretched by low-frequency
 * noise so the outline is organic, not a rectangle. Its geometry rolls back down to the map
 * floor (TerrainMeshBuilder.skirt_height), so a raised edge does not run out into the fog as
 * a shelf. The skirt reads no index maps and runs no rules: the maps clamp at their edge,
 * which would streak.
 *   The skirt is opaque (phase 6, P6-1), so it is in the depth and screen textures like the
 * map's ground and the water of a river running on past the edge reads it (shallows, foam,
 * refraction of the channel bed; the P6-0 probe's verdict). The fade is done in colour
 * instead of alpha (the probe's "tint"): the lit ground times the fade a, plus the backdrop
 * as emission times 1 - a, which is what the alpha blend gave for diffuse light. The
 * backdrop is the one the camera really shows: the environment's flat colour, or under a
 * panorama sky that sky's colour in the camera's view direction (the sky is drawn at a 2
 * degree FOV, LevelEnvironmentManager.SKY_ORTHO_FOV_DEG, so it is one tone), and under fog
 * mixed toward the fog colour by fog_sky_affect, as Godot fogs the background. The skirt
 * writes its own FOG (Godot's fog_process: exponential or depth fog, plus height fog) with
 * its amount times a, so the ground near the map fogs exactly as the map does and the faded
 * tail does not take fog twice. SkirtBackdrop (scenes/terrain/) keeps these uniforms in step
 * with the environment every frame. A backdrop the shader cannot match (another sky
 * material) falls back to a per-pixel dither of the fade (skirt_backdrop_mode 2).
 *   A river's channel past the edge (RiverExitMesh) carries the wet dressing in UV2 (bed,
 * shore), routed to the base's bed and shore layers like the map's (skirt_bed_layer,
 * skirt_shore_layer); within
 * SKIRT_EDGE_DRESSING_M of the edge the map's own dressing (water_weights, clamped at its
 * edge texel) takes over, so the two meet without a seam.
 *   The skirt draws no accent patches: they shrink away inside the map's edge band (see
 * GROUND ACCENTS), so the skirt is a plain surface (on a grass map nothing hides patches past
 * the edge, and a grassland's savanna patches floated in the haze as orange blotches;
 * 2026-10-09). That surface is the base, or the painted surface that covers the map's edge
 * when one does (skirt_ground_layer, TerrainSkirt.edge_surface): a new forest map's edge band
 * is greened, and the skirt fades out on that green instead of the brown forest floor.
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
 * LAYERS (ground layers card G3, 2026-10-13; the index form replaced eight weight-map slots):
 * the map's surfaces are the layers of four Texture2DArrays (layer_*_array: albedo, normal,
 * ORM, height), one layer per palette surface the map uses, the base at layer 0 (GroundLayers
 * in utils/ plans the list, GroundLayerBinding in scenes/terrain/ binds it). Two index sources
 * say which layers are where, both one texel per document sample, uploaded as the document
 * holds them:
 *   - ground: biome_slots_map (each sample's biome slot, 0 for none) and biome_density_map
 *     (its painted density). Row r of the routing table (biome_rules, biome_extra; row 0 is
 *     the base) names the biome's ground, cliff, scree, water bed and shore layers and its
 *     accents. A biome whose ground is the base surface draws as the base (ground -1), and the
 *     base row takes the rules and accents of the most covered such biome, as the slot table
 *     did.
 *   - paint: paint_index_map and paint_weight_map, the top four painted surfaces of a sample
 *     as (index into the document's surface list, weight), weights high to low (0: unused);
 *     paint_layer maps an index to its layer.
 * Indices are never filtered: both sources are read with textureGather at the texel corner
 * below the point (corner_weights) and each corner's entries are weighted by its bilinear
 * weight, which is exactly the bilinear filter of a per-surface weight channel. Corners of the
 * same biome are merged first, so the routing and the accents run once per distinct biome.
 * A pixel gathers its contributions into four (layer, weight) candidates merged by layer
 * (add_candidate): a full list gives way to a stronger contribution, its weakest entry going,
 * so the strongest four survive.
 *   Painted weight is read through a small warp and edge noise (PAINT_*: a path keeps its
 * line), drawn first and wins over the biome ground and scree: everything else shares 1 - the
 * painted total. Exception (cliff faces, the user's 2026-09-27 decision): painted ground and
 * built surfaces cover walkable ground only and give the cliff rule's share of their weight to
 * the automatic rock (PAINT_CLIFF_YIELD), so a path stops at a ledge and resumes on top;
 * painted cliff-role surfaces (layer_flags bit 0) never yield. The ground components (the
 * distinct biomes of the four corners, their density shaped as below, then the base for what
 * they leave) share the unpainted rest. The automatic rules take their share of it:
 * rule_weights() (cliff from slope, scree at concave feet; TerrainRules is the CPU twin,
 * constants below) multiplied by 1 - painted total, handed out per ground component in
 * proportion to its weight to that component's cliff layer (-1: the share stays with its
 * ground); scree likewise. So a sample's rock is its own biome's rock.
 * The tile frame is computed once per pixel and shared: each surface costs only its own
 * fetches, and a candidate whose weight is zero at a pixel is not sampled at all.
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
 * GROUND ACCENTS (2026-09-27; GroundAccents in utils/ is the CPU twin and packs the
 * uniforms, GroundLayers gives the layers): broad, soft-edged patches of other ground
 * surfaces (moss and grass in a forest's duff) cut out of each ground component's own
 * ground, so a biome floor is not one field of one tile. Per component (a biome row or
 * the base), up to ACCENTS_PER_COMPONENT accents (their layers in biome_extra.yzw, their
 * parameters in accent_params[row * ACCENTS_PER_COMPONENT + i]); none is ever dropped for
 * want of a layer. Each is
 * three octaves of smooth value noise at its own patch size (scale_m), read from a small
 * lattice texture (accent_noise: one bilinear fetch per octave instead of value_noise's four
 * hashes), domain rotated and offset per surface and map seed, thresholded for
 * its coverage with a soft ramp (EDGE).
 * Accents are drawn in order, each taking its share of what the earlier ones left, from
 * the component's weight after the rules took theirs (keep): painted surfaces and the
 * automatic cliff and scree cover them. The patch weight then goes through the same height
 * blend as every surface, so its edge frays along texture detail. In the map's edge band
 * (accent_edge_m, the starting cover's feather depth, ragged by ACCENT_EDGE_WOBBLE) the
 * threshold rises until no patch is left at the edge itself, so no patch sits on the rim or
 * crosses into the skirt, which draws none.
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
 * WET DRESSING (phase 4, P4-3; WaterDressing in utils/ computes the field, TerrainRules
 * .compose_water is the CPU twin of the composition): water_weights holds per document
 * sample the water bed weight (R: under the water) and the wet shore weight (G: a band just
 * above it, a couple of metres wide and fading with the height over the water). After the
 * cliff, the bed takes its share of everything but painted rock, painted ground and built
 * slots included as the water deepens (PAINT_WATER_YIELD, PAINT_FORD_*: a path runs into the
 * shallows like a ford and the bed shows under it further out; B is the depth), and the
 * shore takes its share of the ground the rules kept. Both are
 * handed out per ground component to that component's biome's water bed and shore layers
 * (biome_rules.w, biome_extra.x), as cliff and scree are. The field's A is the wet
 * line (under the water and a strip just above it): the final albedo darkens and the
 * roughness drops there (WET_*), so any bank reads wet at the waterline.
 *
 * BROAD EDGE (the second scale of a two-scale edge, added after T7 renders beside the
 * river map): the frayed edge above is a few decimetres wide and on its own reads like a
 * decal laid on the lawn, where a hand-painted Blender layer fades over several metres.
 * layer_broad_a/b hold one channel per broad slot (up to BROAD_SLOTS: the non-base biome
 * grounds and the painted built surfaces, GroundLayerBinding.broad_slots; broad_layer[i] is
 * slot i's layer), the slot weights box-filtered to GroundLayerTable.BROAD_FACTOR samples per
 * texel (3.5 m at the default 0.25 m step) and read with a cubic B-spline, so around each
 * painted biome its ground's mean colour (the last mip of its albedo) recolours the ground in
 * a gradient about 7 m wide. This is the slot table's two-map form, kept as it was until the
 * one-map broad tint (ground layers card G4). Painted built slots (broad_trample_mask, P3-6)
 * get the same halo at paint_broad_strength, a faint trodden fringe that seats a path in
 * the grass instead of leaving it a clean-edged decal; other painted surfaces get none.
 * It recolours by luminance (layer mean x the pixel's luminance relative to the base
 * mean), so the base texture keeps its detail and no hue is amplified. The tint fades out
 * where the fine edge already shows the layer itself (the biome corners' weight on that
 * ground, or the painted weight of that built surface).
 *
 * COST: 12 fetches plus 26 small integer hashes per pixel for the base alone; measured
 * about 1.4x a StandardMaterial3D ground with the same textures. The rules add one
 * two-octave value noise wherever the slope is within reach of the cliff band (and one
 * more near steep feet). The index maps add two gathers for the ground and one for the
 * paint (four more where a sample is painted), then 12 fetches per candidate present at a
 * pixel top-down and 4 per side plane on steep pixels (docs/PERFORMANCE.md "Ground shader:
 * index layers").
 *
 * LIGHTING matches the StandardMaterial3D terrain of a Blender-made map: burley diffuse,
 * schlick GGX specular at the default 0.5, AO from ORM.r affecting ambient only
 * (StandardMaterial3D's ao_light_affect = 0), roughness ORM.g, metallic ORM.b. Shadows and
 * the lo-fi post pass apply as to any opaque surface.
 */

// The map's surfaces, one layer each, the base at layer 0 (see LAYERS).
uniform sampler2DArray layer_albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_orm_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray layer_height_array : filter_linear_mipmap_anisotropic, repeat_enable;
// Per layer: metres covered by one repeat of its textures (the palette's tile_m), and its
// flags (GroundLayers.FLAG_*: bit 0 role cliff, which a painted stroke holds on faces).
uniform float layer_tile_m[64];
uniform int layer_flags[64];
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

// The index maps (see LAYERS), one texel per document sample, read by textureGather only.
// biome_present / paint_present 0 skip their gathers (no biome / no paint on the map).
uniform int biome_present = 0;
uniform sampler2D biome_slots_map : filter_nearest, repeat_disable;
uniform sampler2D biome_density_map : filter_nearest, repeat_disable;
uniform int paint_present = 0;
uniform sampler2D paint_index_map : filter_nearest, repeat_disable;
uniform sampler2D paint_weight_map : filter_nearest, repeat_disable;
// Document surface index -> layer (-1: not drawn).
uniform int paint_layer[64];
// World XZ of document sample (0, 0) and the real sample step, in metres.
uniform vec2 layer_grid_origin = vec2(0.0);
uniform vec2 layer_grid_step = vec2(0.25);
// The routing table by biome slot (row 0: the base): (ground, cliff, scree, water bed) and
// (shore, accent layers 0-2). A ground of -1 draws as the base; a rule of -1 leaves its share
// with the ground; an accent of -1 ends the row's accents.
uniform ivec4 biome_rules[255];
uniform ivec4 biome_extra[255];
// The wet dressing (WaterDressing): one RGBA8 texel per document sample, R bed weight, G
// shore weight, A the wet line (B, depth, is for the CPU). water_present 0 skips the fetch.
uniform int water_present = 0;
uniform sampler2D water_weights : hint_default_black, filter_linear, repeat_disable;
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
// Broad scale of the two-scale edge (see BROAD EDGE): the broad slots' weights box-filtered to
// a few metres per texel (GroundLayerTable.broad_image), read with a B-spline so they are
// smooth; broad_count slots, slot i drawn as layer broad_layer[i], a trampled fringe when bit
// i of broad_trample_mask is set.
uniform int broad_count = 0;
uniform int broad_layer[8];
uniform int broad_trample_mask = 0;
uniform sampler2D layer_broad_a : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D layer_broad_b : hint_default_black, filter_linear, repeat_disable;
// Most a layer's colour tints the ground around its painted area (0.5 was too faint to
// read at the game camera; 0.8 reads as woodland floor fading into lawn).
uniform float biome_broad_strength : hint_range(0.0, 1.0) = 0.8;
// Broad weight at which the tint reaches full strength.
uniform float biome_broad_full : hint_range(0.05, 1.0) = 0.4;
// Most a painted built surface's colour tints the ground around it (worn, trodden grass
// beside a path; P3-6, judged at the game camera).
uniform float paint_broad_strength : hint_range(0.0, 1.0) = 0.35;
// Ground accents (see GROUND ACCENTS). accent_present 0: no row has accents. Entry
// row * ACCENTS_PER_COMPONENT + i is accent i of biome row `row` (its layer in
// biome_extra[row]): (threshold, 1 / scale_m, domain offset).
uniform int accent_present = 0;
uniform vec4 accent_params[765];
// The accent noise lattice (GroundAccents.noise_image): random values per cell, one octave
// per channel, tiling every ACCENT_NOISE_CELLS cells.
uniform sampler2D accent_noise : hint_default_black, filter_linear, repeat_enable;
// The map's edge band (see GROUND ACCENTS): the map's half extent and the band's depth in
// metres (0: no band). The patches' threshold rises by up to ACCENT_EDGE_SHRINK across it, past
// the noise's whole range, so they shrink rather than turn translucent; the depth is pushed in
// and out by ACCENT_EDGE_WOBBLE by a value noise ACCENT_EDGE_WAVE_M across.
uniform vec2 accent_edge_half = vec2(0.0);
uniform float accent_edge_m = 0.0;
const float ACCENT_EDGE_SHRINK = 1.2;
const float ACCENT_EDGE_WOBBLE = 0.5;
const float ACCENT_EDGE_WAVE_M = 9.0;

#ifdef GROUND_SKIRT
// The fade, the backdrop and the fog (skirt_alpha_seeded, skirt_backdrop_color, skirt_fog_at).
#include "res://shaders/skirt_fade.gdshaderinc"
// 1 when a river's channel runs into the skirt: its wet dressing (UV2) is drawn.
uniform int skirt_channel = 0;
// Within this of the map edge the map's own wet dressing takes over the channel's.
const float SKIRT_EDGE_DRESSING_M = 2.0;
// The layer the skirt draws as its ground (the base, or the surface covering the map's edge;
// see SKIRT), and the layers its channel's bed and shore go to (-1: the ground keeps them).
uniform int skirt_ground_layer = 0;
uniform int skirt_bed_layer = -1;
uniform int skirt_shore_layer = -1;
#endif

// Map-frame normal, position and the per-vertex rule fields (UV2: curvature, steepness).
varying vec3 v_normal;
varying vec3 v_position;
varying vec2 v_fields;

const float INV_UINT_MAX = 1.0 / 4294967295.0;
// A weight at or below this is treated as absent (under half an 8-bit step).
const float WEIGHT_EPSILON = 0.002;
// The base surface's layer, and the last valid document surface index (paint_layer's size).
const int BASE_LAYER = 0;
const int LAST_PAINT_INDEX = 63;
// Broad slots (broad_layer's size).
const int BROAD_SLOTS = 8;
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
const float CLIFF_START_COS = 0.719340;
const float CLIFF_END_COS = 0.529919;
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
// Painted ground and built slots yield this fraction of the cliff rule to the automatic rock
// (TerrainRules.PAINT_CLIFF_YIELD and compose_paint): paths cover walkable ground only.
const float PAINT_CLIFF_YIELD = 1.0;
// And of the water bed (TerrainRules.PAINT_WATER_YIELD and compose_water), fading in with the
// water's depth (PAINT_FORD_*): a path runs into the shallows like a ford, and the bed shows
// through further out.
const float PAINT_WATER_YIELD = 1.0;
const float PAINT_FORD_START_M = 0.05;
const float PAINT_FORD_END_M = 0.35;
// water_weights.b is the depth in centimetres as a byte (WaterDressing.DEPTH_SCALE).
const float WATER_DEPTH_SCALE = 100.0;
// The wet line (water_weights.a): albedo darkened by up to WET_DARKEN, roughness pulled
// toward WET_ROUGHNESS by up to WET_GLOSS. Judged at the game camera (P4-3 look pass).
const float WET_DARKEN = 0.35;
const float WET_ROUGHNESS = 0.3;
const float WET_GLOSS = 0.6;
// Ground accents: the twins of GroundAccents' constants (tests/unit/test_ground_accents.gd).
const int ACCENTS_PER_COMPONENT = 3;
const float ACCENT_EDGE = 0.045;
const float ACCENT_DETAIL = 0.3;
const float ACCENT_DETAIL_SCALE = 2.3;
const vec2 ACCENT_DETAIL_OFFSET = vec2(17.3, -5.9);
const float ACCENT_FINE = 0.15;
const float ACCENT_FINE_SCALE = 5.3;
const vec2 ACCENT_FINE_OFFSET = vec2(-31.7, 44.1);
const vec2 ACCENT_ROTATION = vec2(0.8, 0.6);
const float ACCENT_NOISE_CELLS = 32.0;

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

// One layer top-down through the tile frame: 3 cells x (albedo, normal, ORM, height).
TopSample sample_top(float layer, float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy) {
	vec3 albedo[3];
	vec2 normal_xy[3];
	vec3 orm[3];
	vec3 height;
	for (int i = 0; i < 3; i++) {
		vec2 cs = f.rotations[i];
		vec3 uv = vec3(rotate(world_xz - f.centers[i], cs) / tile + f.offsets[i], layer);
		vec2 gx = rotate(dx, cs) / tile;
		vec2 gy = rotate(dy, cs) / tile;
		albedo[i] = textureGrad(layer_albedo_array, uv, gx, gy).rgb;
		vec2 n = textureGrad(layer_normal_array, uv, gx, gy).rg * 2.0 - 1.0;
		// OpenGL green is image-up, which is -v; then undo the cell rotation.
		normal_xy[i] = unrotate(vec2(n.x, -n.y), cs);
		orm[i] = textureGrad(layer_orm_array, uv, gx, gy).rgb;
		height[i] = textureGrad(layer_height_array, uv, gx, gy).r;
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

// One layer's top-down height through the tile frame (sample_top's blend, height only).
float top_height(float layer, float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy) {
	vec3 height;
	for (int i = 0; i < 3; i++) {
		vec2 cs = f.rotations[i];
		vec3 uv = vec3(rotate(world_xz - f.centers[i], cs) / tile + f.offsets[i], layer);
		height[i] = textureGrad(
			layer_height_array, uv, rotate(dx, cs) / tile, rotate(dy, cs) / tile
		).r;
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
	float layer, float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy, vec3 n, vec3 p,
	vec3 dpx, vec3 dpy, vec3 proj, bool need_height, out float height
) {
	height = 0.5;
	if (proj.y >= 1.0) {
		if (need_height) {
			height = top_height(layer, tile, f, world_xz, dx, dy);
		}
		return proj;
	}
	vec3 h = vec3(0.5);
	vec3 score = vec3(ABSENT_SCORE);
	if (proj.y > 0.0) {
		h.y = top_height(layer, tile, f, world_xz, dx, dy);
		score.y = proj.y + (h.y - 0.5) * PROJECTION_CONTRAST;
	}
	if (proj.x > 0.0) {
		SidePlane s = side_plane(0, n, p, dpx, dpy);
		h.x = textureGrad(layer_height_array, vec3(s.uv / tile, layer), s.gx / tile, s.gy / tile).r;
		score.x = proj.x + (h.x - 0.5) * PROJECTION_CONTRAST;
	}
	if (proj.z > 0.0) {
		SidePlane s = side_plane(1, n, p, dpx, dpy);
		h.z = textureGrad(layer_height_array, vec3(s.uv / tile, layer), s.gx / tile, s.gy / tile).r;
		score.z = proj.z + (h.z - 0.5) * PROJECTION_CONTRAST;
	}
	float best = max(score.x, max(score.y, score.z));
	vec3 w = max(score - (best - PROJECTION_BAND), vec3(0.0));
	w /= max(w.x + w.y + w.z, 1e-5);
	height = dot(h, w);
	return w;
}

// Adds `weight` times one layer, through the projections weighted by `pw`, to `acc`.
void accumulate(
	float layer, float tile, TileFrame f, vec2 world_xz, vec2 dx, vec2 dy, vec3 n, vec3 p,
	vec3 dpx, vec3 dpy, vec3 pw, float weight, inout SurfaceSample acc
) {
	if (pw.y > 0.0) {
		TopSample top = sample_top(layer, tile, f, world_xz, dx, dy);
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
			vec3 uv = vec3(s.uv / tile, layer);
			vec2 gx = s.gx / tile;
			vec2 gy = s.gy / tile;
			acc.albedo += textureGrad(layer_albedo_array, uv, gx, gy).rgb * k;
			vec2 nm = textureGrad(layer_normal_array, uv, gx, gy).rg * 2.0 - 1.0;
			acc.normal += perturb(nm, s.t, s.b, n) * k;
			acc.orm += textureGrad(layer_orm_array, uv, gx, gy).rgb * k;
			acc.height += textureGrad(layer_height_array, uv, gx, gy).r * k;
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

// The texture coordinate of map-frame XZ `at` in a map of `grid` texels on the sample grid.
vec2 weight_uv(vec2 at, vec2 grid) {
	return ((at - layer_grid_origin) / layer_grid_step + 0.5) / grid;
}

// The texel-corner coordinate of the 2x2 samples around `at` in a map of `grid` texels (so
// textureGather picks exactly them) and their bilinear weights in gather order (x: (i, j+1),
// y: (i+1, j+1), z: (i+1, j), w: (i, j)): weighting each corner's entries by these equals
// bilinear filtering of a per-surface weight channel, with no filtering of the indices.
vec4 corner_weights(vec2 at, vec2 grid, out vec2 uv) {
	vec2 t = (at - layer_grid_origin) / layer_grid_step;
	vec2 i0 = floor(t);
	vec2 f = t - i0;
	uv = (i0 + 1.0) / grid;
	return vec4((1.0 - f.x) * f.y, f.x * f.y, f.x * (1.0 - f.y), (1.0 - f.x) * (1.0 - f.y));
}

// Adds `w` of layer `layer` to the candidates (cl: layers, -1 free; cw: weights): into the
// entry already drawing it, else a free entry, else in place of the weakest entry when `w`
// outweighs it (which then drops out). Compare-and-select only, so the four stay in
// registers.
void add_candidate(int layer, float w, inout ivec4 cl, inout vec4 cw) {
	if (w <= 0.0 || layer < 0) {
		return;
	}
	bvec4 same = equal(cl, ivec4(layer));
	if (any(same)) {
		cw += mix(vec4(0.0), vec4(w), same);
		return;
	}
	int k = cl.x < 0 ? 0 : (cl.y < 0 ? 1 : (cl.z < 0 ? 2 : (cl.w < 0 ? 3 : -1)));
	if (k < 0) {
		float least = min(min(cw.x, cw.y), min(cw.z, cw.w));
		if (w <= least) {
			return;
		}
		k = cw.x == least ? 0 : (cw.y == least ? 1 : (cw.z == least ? 2 : 3));
	}
	cl = ivec4(k == 0 ? layer : cl.x, k == 1 ? layer : cl.y, k == 2 ? layer : cl.z, k == 3 ? layer : cl.w);
	cw = vec4(k == 0 ? w : cw.x, k == 1 ? w : cw.y, k == 2 ? w : cw.z, k == 3 ? w : cw.w);
}

// The ground components at a point: the biome slots of the four samples around the warped
// point (`slots`) and their density (`g`), with the edge warp, gain and edge noise applied;
// a corner without a biome, or of a biome drawn as the base, has weight 0, and corners of one
// biome are merged into the first of them. Returns the base's weight, 1 - their total.
float ground_components(vec2 world_xz, out ivec4 slots, out vec4 g) {
	slots = ivec4(0);
	g = vec4(0.0);
	if (biome_present == 0) {
		return 1.0;
	}
	vec2 p = world_xz / biome_edge_scale_m;
	vec2 warp = vec2(value_noise(p + vec2(-23.1, 57.7)), value_noise(p + vec2(91.3, -12.9)));
	vec2 uv;
	vec4 corners = corner_weights(
		world_xz + (warp * 2.0 - 1.0) * biome_edge_warp_m, vec2(textureSize(biome_slots_map, 0)), uv
	);
	slots = ivec4(textureGather(biome_slots_map, uv, 0) * 255.0 + 0.5);
	vec4 drawn = vec4(
		float(biome_rules[slots.x].x >= 0),
		float(biome_rules[slots.y].x >= 0),
		float(biome_rules[slots.z].x >= 0),
		float(biome_rules[slots.w].x >= 0)
	);
	g = corners * textureGather(biome_density_map, uv, 0) * drawn;
	if (slots.y == slots.x) {
		g.x += g.y;
		g.y = 0.0;
	}
	if (slots.z == slots.x) {
		g.x += g.z;
		g.z = 0.0;
	} else if (slots.z == slots.y) {
		g.y += g.z;
		g.z = 0.0;
	}
	if (slots.w == slots.x) {
		g.x += g.w;
		g.w = 0.0;
	} else if (slots.w == slots.y) {
		g.y += g.w;
		g.w = 0.0;
	} else if (slots.w == slots.z) {
		g.z += g.w;
		g.w = 0.0;
	}
	float total = dot(g, vec4(1.0));
	if (total <= WEIGHT_EPSILON) {
		g = vec4(0.0);
		return 1.0;
	}
	// Gain first, so the ground leads the scatter (which thins linearly with density) out
	// to the sparse fringe instead of leaving its outer plants standing on the base.
	float gained = min(total * biome_weight_gain, 1.0);
	// Finer than the warp, and zero at 0 and 1, so it only reshapes partial paint.
	float n = value_noise(p * 2.9 + vec2(7.9, 3.1));
	float bump = 4.0 * gained * (1.0 - gained);
	float shaped = clamp(gained + (n - 0.5) * 2.0 * biome_edge_noise * bump, 0.0, 1.0);
	g *= shaped / total;
	return clamp(1.0 - shaped, 0.0, 1.0);
}

// One entry plane of the paint maps (weights `w`, already times the corner weights, and
// their document indices `index` * 1/255) added to the candidates.
void add_painted(vec4 w, vec4 index, inout ivec4 cl, inout vec4 pw) {
	ivec4 s = min(ivec4(index * 255.0 + 0.5), ivec4(LAST_PAINT_INDEX));
	add_candidate(paint_layer[s.x], w.x, cl, pw);
	add_candidate(paint_layer[s.y], w.y, cl, pw);
	add_candidate(paint_layer[s.z], w.z, cl, pw);
	add_candidate(paint_layer[s.w], w.w, cl, pw);
}

// The painted candidates at a point (TerrainRules.painted_lookup and shape_painted are the
// CPU twins): the four nearest samples' entries weighted by their corners, merged by layer
// into (cl, pw), their total shaped by the edge noise. Returns the painted total. The
// entries are sorted high to low, so an entry plane is only read where the one before it
// had weight.
float painted_candidates(vec2 world_xz, out ivec4 cl, out vec4 pw) {
	cl = ivec4(-1);
	pw = vec4(0.0);
	if (paint_present == 0) {
		return 0.0;
	}
	vec2 p = world_xz / PAINT_EDGE_SCALE_M;
	vec2 warp = vec2(value_noise(p + PAINT_WARP_OFFSET_A), value_noise(p + PAINT_WARP_OFFSET_B));
	vec2 uv;
	vec4 corners = corner_weights(
		world_xz + (warp * 2.0 - 1.0) * PAINT_EDGE_WARP_M, vec2(textureSize(paint_weight_map, 0)), uv
	);
	vec4 w = textureGather(paint_weight_map, uv, 0) * corners;
	if (dot(w, vec4(1.0)) <= 0.0) {
		return 0.0;
	}
	add_painted(w, textureGather(paint_index_map, uv, 0), cl, pw);
	w = textureGather(paint_weight_map, uv, 1) * corners;
	if (dot(w, vec4(1.0)) > 0.0) {
		add_painted(w, textureGather(paint_index_map, uv, 1), cl, pw);
		w = textureGather(paint_weight_map, uv, 2) * corners;
		if (dot(w, vec4(1.0)) > 0.0) {
			add_painted(w, textureGather(paint_index_map, uv, 2), cl, pw);
			w = textureGather(paint_weight_map, uv, 3) * corners;
			if (dot(w, vec4(1.0)) > 0.0) {
				add_painted(w, textureGather(paint_index_map, uv, 3), cl, pw);
			}
		}
	}
	float total = dot(pw, vec4(1.0));
	if (total <= WEIGHT_EPSILON) {
		cl = ivec4(-1);
		pw = vec4(0.0);
		return 0.0;
	}
	float n = value_noise(p * 2.9 + PAINT_NOISE_OFFSET);
	float bump = 4.0 * total * (1.0 - total);
	float shaped = clamp(total + (n - 0.5) * 2.0 * PAINT_EDGE_NOISE * bump, 0.0, 1.0);
	pw *= shaped / total;
	return shaped;
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

// Smooth value noise at lattice point p from the accent lattice (GroundAccents.octave): one
// bilinear fetch at the cell corner plus the smoothstepped fraction interpolates the four
// lattice values with smoothstep weights. All four channels come back; the caller picks one.
vec4 accent_octave(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	return textureLod(accent_noise, (i + f + 0.5) / ACCENT_NOISE_CELLS, 0.0);
}

// How much of the accent patches the map keeps at map-frame XZ (see GROUND ACCENTS): none on
// the map edge, all from accent_edge_m in, that depth ragged by ACCENT_EDGE_WOBBLE.
float accent_edge_keep(vec2 world_xz) {
	vec2 inside = accent_edge_half - abs(world_xz);
	float wobble = value_noise(world_xz / ACCENT_EDGE_WAVE_M + vec2(13.7, -41.3)) * 2.0 - 1.0;
	float depth = accent_edge_m * (1.0 + ACCENT_EDGE_WOBBLE * wobble);
	return smoothstep(0.0, depth, min(inside.x, inside.y));
}

// One accent's patch weight 0..1 at map-frame XZ (GroundAccents.mask): params are
// (threshold, 1 / scale_m, domain offset). Each finer octave is only fetched where it can
// still change the result, which is exact since the ramp clamps (fetching all three with
// no branch between them measured the same or slightly slower).
float accent_mask(vec2 world_xz, vec4 params) {
	vec2 p = rotate(world_xz, ACCENT_ROTATION) * params.y + params.zw;
	float low = params.x - ACCENT_EDGE;
	float high = params.x + ACCENT_EDGE;
	float n = accent_octave(p).r * (1.0 - ACCENT_DETAIL - ACCENT_FINE);
	if (n + ACCENT_DETAIL + ACCENT_FINE <= low) {
		return 0.0;
	}
	if (n >= high) {
		return 1.0;
	}
	n += accent_octave(p * ACCENT_DETAIL_SCALE + ACCENT_DETAIL_OFFSET).g * ACCENT_DETAIL;
	if (n + ACCENT_FINE <= low) {
		return 0.0;
	}
	if (n >= high) {
		return 1.0;
	}
	n += accent_octave(p * ACCENT_FINE_SCALE + ACCENT_FINE_OFFSET).b * ACCENT_FINE;
	return smoothstep(low, high, n);
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

// The broad scale of the two-scale edge: around each broad slot's painted area its layer's
// mean colour tints the surface in a wide, soft gradient, fading out where the fine, frayed
// edge already shows the layer itself: the weight of the ground corners (`slots`, `g`) on
// that layer, or for a trampled slot the painted weight of that layer (`pl`, `pw`).
vec3 apply_broad_edge(vec3 albedo, vec2 world_xz, ivec4 slots, vec4 g, ivec4 pl, vec4 pw) {
	vec2 st = weight_uv(world_xz, vec2(textureSize(biome_slots_map, 0)));
	vec4 broad[2];
	broad[0] = texture_bspline(layer_broad_a, st);
	broad[1] = vec4(0.0);
	if (broad_count > 4) {
		broad[1] = texture_bspline(layer_broad_b, st);
	}
	ivec4 grounds = ivec4(
		biome_rules[slots.x].x, biome_rules[slots.y].x, biome_rules[slots.z].x, biome_rules[slots.w].x
	);
	// Recolour rather than paint over: the layer's mean colour, carrying the ground's own
	// luminance detail relative to the base surface's mean.
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	float base_luma = max(
		dot(textureLod(layer_albedo_array, vec3(0.5, 0.5, float(BASE_LAYER)), 16.0).rgb, LUMA), 0.02
	);
	float detail = dot(albedo, LUMA) / base_luma;
	for (int i = 0; i < BROAD_SLOTS; i++) {
		float w = broad[i / 4][i % 4];
		int layer = broad_layer[i];
		if (i >= broad_count || w <= WEIGHT_EPSILON || layer < 0) {
			continue;
		}
		bool trample = ((broad_trample_mask >> i) & 1) != 0;
		float strength = trample ? paint_broad_strength : biome_broad_strength;
		float fine = trample ? dot(mix(vec4(0.0), pw, equal(pl, ivec4(layer))), vec4(1.0))
			: dot(mix(vec4(0.0), g, equal(grounds, ivec4(layer))), vec4(1.0));
		float tint = strength * smoothstep(0.0, biome_broad_full, w);
		tint *= 1.0 - smoothstep(0.2, 0.8, fine);
		if (tint > 0.001) {
			vec3 mean = textureLod(layer_albedo_array, vec3(0.5, 0.5, float(layer)), 16.0).rgb;
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
// Skirt fade at a point: 1 on the map edge, 0 from skirt_fade_m out (skirt_fade.gdshaderinc;
// the noise leaves the edge itself at exactly 1, so the skirt meets the map without a seam).
float skirt_alpha(vec2 world_xz) {
	return skirt_alpha_seeded(world_xz, breakup_seed);
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
	if (skirt_backdrop_mode == 2) {
		// No colour to fade to: the fade as an interleaved-gradient dither (see SKIRT).
		if (skirt_a < fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))))) {
			discard;
		}
		skirt_a = 1.0;
	}
#endif
	vec3 n_geom = normalize(v_normal);
	TileFrame frame = tile_frame(world_xz);
	vec3 proj = projection_weights(n_geom);

	// Painted candidates first (ground and built paint minus what it yields to the cliff
	// rule); the ground components (the corners' biomes and the base) share what the painting
	// leaves, and the rules take their share of that.
	ivec4 slots = ivec4(0);
	vec4 g = vec4(0.0);
	float g_base = 1.0;
	ivec4 cl = ivec4(-1);
	vec4 pw = vec4(0.0);
	float painted_total = 0.0;
#ifndef GROUND_SKIRT
	g_base = ground_components(world_xz, slots, g);
	painted_total = painted_candidates(world_xz, cl, pw);
#endif
	// The painted entries as read, for the broad edge's fine weights.
	ivec4 painted_layers = cl;
	vec4 painted_w = pw;
	// Painted cliff-role surfaces hold their weight; painted ground and built surfaces yield
	// to the automatic rock on faces (TerrainRules.compose_paint is the CPU twin).
	vec4 holds = vec4(
		float(cl.x >= 0 && (layer_flags[max(cl.x, 0)] & 1) != 0),
		float(cl.y >= 0 && (layer_flags[max(cl.y, 0)] & 1) != 0),
		float(cl.z >= 0 && (layer_flags[max(cl.z, 0)] & 1) != 0),
		float(cl.w >= 0 && (layer_flags[max(cl.w, 0)] & 1) != 0)
	);
	vec4 held_w = pw * holds;
	float held = dot(held_w, vec4(1.0));
	float yielding = painted_total - held;
	float unpainted = clamp(1.0 - painted_total, 0.0, 1.0);
	vec2 rule = vec2(0.0);
	vec2 water = vec2(0.0);
	float water_depth = 0.0;
	float wet_line = 0.0;
#ifndef GROUND_SKIRT
	if (unpainted + yielding > WEIGHT_EPSILON) {
		rule = rule_weights(n_geom.y, v_fields, v_position);
	}
	if (water_present != 0) {
		vec4 wet_field = texture(water_weights, weight_uv(world_xz, vec2(textureSize(water_weights, 0))));
		water = wet_field.rg;
		water_depth = wet_field.b * (255.0 / WATER_DEPTH_SCALE);
		wet_line = wet_field.a;
	}
#else
	if (skirt_channel != 0) {
		// A river's channel past the edge (see SKIRT): its dressing from UV2, the map's own
		// near the edge.
		water = v_fields;
		wet_line = clamp(water.x + water.y * 0.7, 0.0, 1.0);
		float edge = length(max(abs(world_xz) - skirt_half_extent, vec2(0.0)));
		if (water_present != 0 && edge < SKIRT_EDGE_DRESSING_M) {
			vec4 wet_field = texture(water_weights, weight_uv(world_xz, vec2(textureSize(water_weights, 0))));
			float k = smoothstep(0.0, SKIRT_EDGE_DRESSING_M, edge);
			water = mix(wet_field.rg, water, k);
			wet_line = mix(wet_field.a, wet_line, k);
		}
	}
#endif
	// TerrainRules.compose_water is the CPU twin of these lines.
	float cliff_scale = 1.0 - PAINT_CLIFF_YIELD * rule.x;
	float fording = smoothstep(PAINT_FORD_START_M, PAINT_FORD_END_M, water_depth);
	float ford = PAINT_WATER_YIELD * water.x * fording;
	float paint_scale = cliff_scale * (1.0 - ford);
	vec4 cw = held_w + (pw - held_w) * paint_scale;
	float cliff = unpainted * rule.x + yielding * (1.0 - cliff_scale);
	float dry = 1.0 - water.x;
	float bed = water.x * unpainted * (1.0 - rule.x) + yielding * cliff_scale * ford;
	float scree = unpainted * rule.y * dry;
	float shore = unpainted * (1.0 - rule.x - rule.y) * dry * water.y;
	float keep = unpainted * (1.0 - rule.x - rule.y) * dry * (1.0 - water.y);
	bool accents_on = accent_present != 0 && keep > WEIGHT_EPSILON;
	float accent_rise = 0.0;
	if (accents_on && accent_edge_m > 0.0) {
		// The patches shrink away in the map's edge band (see GROUND ACCENTS).
		float edge_keep = accent_edge_keep(world_xz);
		accents_on = edge_keep > 0.0;
		accent_rise = (1.0 - edge_keep) * ACCENT_EDGE_SHRINK;
	}
	// Each ground component (the corners' distinct biomes, then the base at j = 4) hands its
	// weight to its layers: its kept ground less the accent patches cut out of it, in order
	// (see GROUND ACCENTS), then its cliff, scree, water bed and shore (-1: its ground keeps
	// that share).
	for (int j = 0; j < 5; j++) {
		float weight = j < 4 ? g[j] : g_base;
		if (weight <= WEIGHT_EPSILON) {
			continue;
		}
		int row = j < 4 ? slots[j] : 0;
		ivec4 rules = biome_rules[row];
		ivec4 extra = biome_extra[row];
		int ground_layer = j < 4 ? rules.x : BASE_LAYER;
		bool row_accents = accents_on;
#ifdef GROUND_SKIRT
		// The skirt's one surface and its channel's dressing (see SKIRT); no patches.
		ground_layer = skirt_ground_layer;
		rules.w = skirt_bed_layer;
		extra.x = skirt_shore_layer;
		row_accents = false;
#endif
		float kept = weight * keep;
		float remaining = 1.0;
		if (row_accents && kept > WEIGHT_EPSILON) {
			for (int e = 0; e < ACCENTS_PER_COMPONENT; e++) {
				int to = extra[e + 1];
				if (to < 0) {
					break;
				}
				vec4 params = accent_params[row * ACCENTS_PER_COMPONENT + e];
				params.x += accent_rise;
				float share = remaining * accent_mask(world_xz, params);
				remaining -= share;
				add_candidate(to, kept * share, cl, cw);
			}
		}
		add_candidate(ground_layer, kept * remaining, cl, cw);
		add_candidate(rules.y >= 0 ? rules.y : ground_layer, weight * cliff, cl, cw);
		add_candidate(rules.z >= 0 ? rules.z : ground_layer, weight * scree, cl, cw);
		add_candidate(rules.w >= 0 ? rules.w : ground_layer, weight * bed, cl, cw);
		add_candidate(extra.x >= 0 ? extra.x : ground_layer, weight * shore, cl, cw);
	}

	// A candidate is sampled only where it has weight. One (most of the ground) is drawn
	// directly; several are height-blended in two passes, heights first to find the top
	// score, then full samples of the candidates within the blend band, so no sample has to
	// stay live while the others are fetched.
	int count = 0;
	for (int k = 0; k < 4; k++) {
		count += cw[k] > WEIGHT_EPSILON ? 1 : 0;
	}
	if (count == 0) {
		cl = ivec4(BASE_LAYER, -1, -1, -1);
		cw = vec4(1.0, 0.0, 0.0, 0.0);
		count = 1;
	}
	vec4 scores = vec4(ABSENT_SCORE);
	float top = ABSENT_SCORE;
	if (count > 1) {
		for (int k = 0; k < 4; k++) {
			if (cw[k] > WEIGHT_EPSILON) {
				float h;
				surface_projections(
					float(cl[k]), layer_tile_m[cl[k]], frame, world_xz, dx, dy, n_geom,
					v_position, dpx, dpy, proj, true, h
				);
				scores[k] = blend_score(cw[k], h);
				top = max(top, scores[k]);
			}
		}
	}
	SurfaceSample ground;
	ground.albedo = vec3(0.0);
	ground.normal = vec3(0.0);
	ground.orm = vec3(0.0);
	ground.height = 0.0;
	float total = 0.0;
	for (int k = 0; k < 4; k++) {
		if (cw[k] > WEIGHT_EPSILON) {
			float b = count > 1 ? scores[k] - (top - biome_blend_width) : 1.0;
			if (b > 0.0) {
				float h;
				float layer = float(cl[k]);
				float tile = layer_tile_m[cl[k]];
				vec3 pk = surface_projections(
					layer, tile, frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy, proj,
					false, h
				);
				accumulate(
					layer, tile, frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy, pk, b,
					ground
				);
				total += b;
			}
		}
	}
	float inv_total = 1.0 / max(total, 1e-5);
	ground.albedo *= inv_total;
	ground.orm *= inv_total;
	ground.height *= inv_total;
#ifndef GROUND_SKIRT
	if (broad_count > 0) {
		ground.albedo = apply_broad_edge(
			ground.albedo, world_xz, slots, g, painted_layers, painted_w
		);
	}
#endif

	// Cavity depth itself drifts at a few metres, so clumpy and smooth stretches alternate
	// instead of an even mottle.
	float clumpiness = mix(0.3, 1.0, value_noise(world_xz / 3.5 + vec2(-71.3, 13.9)));
	float cavity = mix(
		1.0 - cavity_strength * clumpiness, 1.0, smoothstep(0.0, 0.8, ground.height)
	);
	// The wet line (WET DRESSING): wet ground is darker and glossier, whatever its surface.
	ALBEDO = apply_variation(ground.albedo * cavity, world_xz) * (1.0 - WET_DARKEN * wet_line);
	AO = ground.orm.r;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = mix(ground.orm.g, WET_ROUGHNESS, WET_GLOSS * wet_line);
	METALLIC = ground.orm.b;

	vec3 n_map = normalize(ground.normal + n_geom * 1e-4);
	NORMAL = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * n_map));
#ifdef GROUND_SKIRT
	// The fade in colour (see SKIRT): lit ground * a + backdrop * (1 - a), and the fog the map's
	// ground gets, times a.
	ALBEDO *= skirt_a;
	SPECULAR = 0.5 * skirt_a;
	EMISSION = skirt_backdrop_color(INV_VIEW_MATRIX) * (1.0 - skirt_a);
	FOG = skirt_fog_at(VERTEX, INV_VIEW_MATRIX) * vec4(1.0, 1.0, 1.0, skirt_a);
#endif
}
