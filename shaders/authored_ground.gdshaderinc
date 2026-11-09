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
 * and drifts across the map edge. Both are opaque. Each has a looked twin
 * (authored_ground_looked.gdshader, authored_ground_skirt_looked.gdshader: GROUND_LOOK defined)
 * that compiles the GROUND LOOK path in; the plain pair has none of it, not even its gate, so a
 * map whose biomes carry no look pays nothing for it (see GROUND LOOK).
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
 *   The skirt receives no shadows (shadows_disabled in both skirt shaders; card groundskirt,
 * PERFORMANCE.md "Ground skirt shadows"): the directional shadow filter was about half of the
 * skirt's cost at full zoom-out (0.58 of 1.19 ms at 1080p on an RTX 3080), while the layer
 * blend was under a tenth of it, and on the measured map no shadow reached the skirt (home, full
 * zoom-out and eye views within 3 levels, mean 0).
 *   SKIRT RING (GROUND_SKIRT_RING; card skirtring): the one place a shadow does reach the skirt
 * is just past the map edge, where a tall caster near the edge with a low sun throws its shadow
 * on, so the skirt's inner rings (TerrainSkirt, the mesh's second surface, up to
 * TerrainMeshBuilder.SKIRT_SHADOW_RINGS rings out) draw with authored_ground_skirt_ring*.gdshader: the same
 * shader without shadows_disabled. The shadow term is faded out over the ring (light(): the
 * directional light's ATTENUATION mixed toward 1 by v_ring_fade, 0 at the edge to 1 at
 * skirt_shadow_m), so the shadow thins to nothing exactly where the shadowless outer skirt takes
 * over and no seam shows. The fade runs on the distance to the map rectangle, not the wobbled
 * one of the colour fade, because the surfaces split on geometry.
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
 * STEEP FACES (phase 3, P3-4; slopesmear 2026-11-08): a planar projection along an axis
 * stretches a texture by 1 / |n . axis| down the slope, so top-down alone smears a 50 degree
 * valley wall 1.6 times along its dip (and a 70 degree tier face into vertical streaks).
 * Each projection (top-down and the planes facing X and Z) is weighted by |n . axis| raised
 * to PROJECTION_SHARPNESS, so the least stretched leads and its neighbours cross-fade only
 * near the 45 degree crossovers; a share under PROJECTION_MIN_WEIGHT is dropped, so most
 * steep pixels sample one or two projections, not three. Worst case is 1.73 on a face turned
 * 45 degrees between X and Z at 55 degrees; a face turned to X or Z never passes 1.41. On
 * ground gentler than about 34 degrees the weights are exactly top-down and the side code is
 * branched over entirely: flat ground draws and costs what it did. Side planes of ground
 * surfaces (grass, soil) take the same mosaic breakup as top-down, cells laid in the plane's
 * own uv, or they would tile plainly and stand their painted strokes all down the slope;
 * side planes of cliff-role surfaces take none: cells rotate a texture, and a cliff's
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
 * result goes to light() (see LIGHTING), not to NORMAL.
 *
 * LIGHTING (card gpuprepass, 2026-11-08; docs/PERFORMANCE.md "Ground pre-pass"): with SSAO on,
 * Forward+ draws the depth pre-pass in its normal-roughness mode, and the driver keeps every
 * fragment line that feeds NORMAL, NORMAL_MAP, ROUGHNESS, ALPHA or a discard there (a probe
 * shader measured it; ALBEDO, AO, EMISSION, BENT_NORMAL_MAP and fragment-to-light varyings stay
 * out). Written to NORMAL and ROUGHNESS, the layer blend ran twice per pixel, 0.4 ms of a 3.7 ms
 * frame at home. So fragment() leaves NORMAL as the interpolated normal and writes a ROUGHNESS
 * that needs only the wet line (AMBIENT_ROUGHNESS), and hands the blended view-space normal,
 * its roughness (through the engine's roughness limiter, replicated) and the specular amount
 * to light() through varyings; light() is Godot 4.7's Burley diffuse and Schlick-GGX specular
 * (within 1 level of the engine's on every pixel, checked with the normal still written). Direct
 * light is unchanged; the ambient (sky irradiance and reflection) and SSAO now see the
 * interpolated normal and AMBIENT_ROUGHNESS, a mean change of 0.2-0.6 levels (day to sunset), at
 * most 16 at home and 24 on rock-ledge lips at zoom 8 (look-pending). Fire's omni lights go
 * through light() too, within 1 level.
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
 * The edge noise is three-dimensional (layered_noise), so a face of any slope and facing cuts
 * it into patches as round as flat ground's; at height 0 it is the plain 2D noise.
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
 * broad_tint_map is one tint map (ground layers card G4, GroundBroadTint): the tinted
 * components (the biome grounds, and the painted built surfaces at a lower weight, the
 * trodden fringe of P3-6 that seats a path in the grass instead of leaving a clean-edged
 * decal), premultiplied (rgb = the sum of weight x coverage x mean colour, a = the sum of
 * weight x coverage), box-filtered to GroundBroadTint.BROAD_FACTOR samples per texel (3.5 m
 * at the default 0.25 m step) and read with one cubic B-spline whatever their number. The
 * pixel takes away its own components (each biome corner and painted built entry: its weight
 * x a smoothstep of its fine weight, times its colour from layer_tint), and recolours toward
 * the mean colour of what is left by biome_broad_strength x smoothstep(0, biome_broad_full,
 * what is left): a biome's ground fades a gradient about 7 m wide into the base beside it, a
 * path tints the forest it crosses, and two fully painted biomes cancel each other, so their
 * border is the fine frayed edge alone. Painted weight wins here as everywhere: a painted
 * stroke (the same smoothstep of the pixel's painted total) holds its own colour, so snow
 * painted beside the taiga stays white instead of taking a cream cast. It recolours by luminance (the mean x the pixel's
 * luminance relative to the base mean), so the base texture keeps its detail and no hue is
 * amplified.
 *
 * COST: 12 fetches plus 26 small integer hashes per pixel for the base alone; measured
 * about 1.4x a StandardMaterial3D ground with the same textures. The rules add one
 * two-octave value noise wherever the slope is within reach of the cliff band (and one
 * more near steep feet). The index maps add two gathers for the ground and one for the
 * paint (four more where a sample is painted), then 12 fetches per candidate present at a
 * pixel top-down and 4 per side plane on steep pixels (docs/PERFORMANCE.md "Ground shader:
 * index layers").
 *
 * FIRE (fire card F4a, 2026-10-16): persistent ground fire (MapDocument.fire_mask) chars the
 * ground and burns on it, a soft pool of light under each fire and dark char between, from
 * fire_glow.gdshaderinc (its header holds the model). The map's ground only, plain and looked;
 * the skirt pair compiles none of it (a skirt never burns). One fetch of the sim bake per pixel
 * where the map has a fire mask (two where it burns), nothing where it has none
 * (fire_present 0).
 *
 * LIGHTING matches the StandardMaterial3D terrain of a Blender-made map: burley diffuse,
 * schlick GGX specular at the default 0.5, AO from ORM.r affecting ambient only
 * (StandardMaterial3D's ao_light_affect = 0), roughness ORM.g, metallic ORM.b. Shadows and
 * the lo-fi post pass apply as to any opaque surface.
 */

// The skirt never reads the clipmap (a measurement may define GROUND_CLIPMAP for both).
#ifdef GROUND_SKIRT
#undef GROUND_CLIPMAP
#endif

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
// Broad scale of the two-scale edge (see BROAD EDGE): the tinted components premultiplied and
// box-filtered to a few metres per texel (GroundBroadTint.broad_image, RGBA half floats), read
// with a B-spline so they are smooth; broad_present 0: the map has none. layer_tint[j]: layer
// j's mean colour (linear) when it is a tinted surface, and as w its tint weight as a painted
// surface (GroundBroadTint.TRAMPLE_WEIGHT for role built, else 0; a biome ground's is 1).
uniform int broad_present = 0;
uniform sampler2D broad_tint_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 layer_tint[64];
// Most the ground recolours toward what is left of the tint (0.5 was too faint to read at the
// game camera; 0.8 reads as woodland floor fading into lawn; GroundBroadTint.STRENGTH).
uniform float biome_broad_strength : hint_range(0.0, 1.0) = 0.8;
// Weight left at which the tint reaches full strength (GroundBroadTint.FULL).
uniform float biome_broad_full : hint_range(0.05, 1.0) = 0.4;
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
// GROUND LOOK (ground ship card 3b; docs/systems/authored_terrain.md "Ground look"). A biome
// whose palette entry carries a ground_look draws its colour zones and painted light from a
// texture GroundLookBake bakes once per map and look (ground_light_field.gdshaderinc): up to
// LOOK_SLOTS looks per map, look_tex_N for slot N, all over look_rect (map-frame XZ origin, size
// in metres). All of it is compiled in only with GROUND_LOOK defined (the looked variants, which
// AuthoredTerrain.set_looked binds while a biome on the map carries a look; the plain variants
// drew 0.22-0.44 ms faster with the path present but gated off, docs/PERFORMANCE.md "Ground look
// and grass masses"). look_present 0 (nothing bound yet) skips every line of it and draws today's
// ground. look_row_slots: per biome row (four rows per ivec4) its look slot, -1
// none; look_layer_slots: per layer (four per ivec4) the slot whose zones colour it, -1 none
// (GroundLookUniforms.ground_tables). Per slot:
//   look_light       (zones strength, light strength, light knee, light cap)
//   look_ref         (the light reference rgb, linear: ref_surface's mean albedo; sat_cap)
//   look_brush       (brush contrast, hue, key, mean): what a zoned layer keeps of its texture
//   look_shape       (accent stretch, stretch angle, break, edge scale): the accent patches
//   look_rim         (accent_rim_m, path_rim_m, strength, wobble)
//   look_rim_more    (gap, path_blend_width, accent_core_m, core_dark)
//   look_rim_color, look_accent_tint (rgb, linear)
//   look_rim_layers  the layers that draw a rim, -1 none
// look_steep, look_steep_atlas, look_steep_params: the look on steep faces
// (ground_steep_zones.gdshaderinc, read through look_texel).
// A pixel mixes today's ground and the looked one by the share of its biome components that
// carry a look; the pixel-wide values (the cap, the rims, the path band) are its dominant looked
// component's, the per-sample ones (brush, reference) the zoned layer's own.
#ifdef GROUND_LOOK
#include "res://shaders/ground_light_field.gdshaderinc"
const int LOOK_SLOTS = 4;
uniform int look_present = 0;
uniform ivec4 look_row_slots[64];
uniform ivec4 look_layer_slots[16];
uniform sampler2D look_tex_0 : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D look_tex_1 : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D look_tex_2 : hint_default_white, filter_linear, repeat_disable;
uniform sampler2D look_tex_3 : hint_default_white, filter_linear, repeat_disable;
uniform vec4 look_rect = vec4(-64.0, -64.0, 128.0, 128.0);
uniform vec4 look_light[4];
uniform vec4 look_ref[4];
uniform vec4 look_brush[4];
uniform vec4 look_shape[4];
uniform vec4 look_rim[4];
uniform vec4 look_rim_more[4];
uniform vec4 look_rim_color[4];
uniform vec4 look_accent_tint[4];
uniform ivec4 look_rim_layers[4];
// The painted rim: where a biome ground meets a rim-listed accent patch or painted path, that
// surface's own share of the pixel moves toward the rim colour by the rim strength, in a band
// accent_rim_m past the patch's ramp or path_rim_m past the stroke's half level, its width
// wobbled (a value noise RIM_WOBBLE_M across), broken into ragged lengths (RIM_WAVE_M,
// RIM_RAGGED) with no rim over about rim_gap of the edge (RIM_GAP_M). The depth into a patch is
// its noise's distance past the ramp's top over its gradient, by finite differences RIM_PROBE_M
// apart, only within RIM_REACH noise units of the ramp; a path's comes from the screen
// derivatives of its weight. From accent_core_m inside a rim-listed patch its share darkens by
// core_dark and turns glossier (a wet centre).
const float RIM_WAVE_M = 0.9;
const float RIM_RAGGED = 0.6;
const float RIM_PROBE_M = 0.06;
const float RIM_REACH = 0.3;
const float RIM_WOBBLE_M = 0.7;
const float RIM_GAP_M = 1.3;
// What accent_mask_rim_m's skip test adds to each octave it reads: far above the rounding of
// the field (about 1e-7), so the test only skips a pixel whose whole field is below the ramp.
const float RIM_EXIT_MARGIN = 1e-4;
#endif
// The accent shape of a row without a look: today's patches.
const vec4 PLAIN_SHAPE = vec4(1.0, 0.0, 0.0, 1.0);

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
#ifdef GROUND_SKIRT_RING
// The ring's outer edge: this far past the map edge shadows are no longer received (see SKIRT
// RING), and they fade in strength from SKIRT_RING_FADE_FROM of it. TerrainSkirt sets it to the
// distance of the ring surface's outer vertices.
uniform float skirt_shadow_m : hint_range(1.0, 100.0) = 16.0;
const float SKIRT_RING_FADE_FROM = 0.3;
varying float v_ring_fade;
#endif
#endif

// CLIPMAP (card clipmap1; docs/systems/ground_clipmap.md). GROUND_CLIPMAP compiles in the read
// of the baked composite: a pyramid of CLIP_LEVELS camera-following windows, level l at
// clip_d0 / 2^l texels per metre, each two textures over the same toroidal window (A: lit albedo
// as sRGB bytes + AO in alpha; B: map-frame normal x and z + roughness), written by the bake
// shaders below (GROUND_BAKE_OUT). A pixel on ground gentler than clip_steep_cos finds its level
// from the finer axis of its screen footprint and takes the baked composite where a level covers
// it; everywhere else (steep faces, the windows' gaps, the skirt) the layer blend below runs as
// ever. Fire, the wet line and the lighting stay per pixel.
#ifdef GROUND_CLIPMAP
// The windows have no mip chain: the anisotropic filter takes the taps along a foreshortened
// footprint at level 0 of the window (CLIP_NO_ANISO is a measurement define: plain bilinear).
#ifdef CLIP_NO_ANISO
#define CLIP_FILTER filter_linear
#else
#define CLIP_FILTER filter_linear_mipmap_anisotropic
#endif
uniform sampler2D clip_a0 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_a1 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_a2 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_a3 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_a4 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_b0 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_b1 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_b2 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_b3 : hint_default_black, CLIP_FILTER, repeat_enable;
uniform sampler2D clip_b4 : hint_default_black, CLIP_FILTER, repeat_enable;
// Per level: the baked rectangle in map-frame metres (min x, min z, max x, max z; empty when max
// is under min), and (1 / window extent in metres, fade width in metres, guard in metres, 0).
uniform vec4 clip_valid[5];
uniform vec4 clip_info[5];
// The map-frame rectangle (min x, min z, max x, max z, metres) an edit changed and the windows
// have not rebaked yet: inside it every pixel keeps the layer blend, which reads the live ground.
uniform vec4 clip_hole = vec4(1.0e9, 1.0e9, -1.0e9, -1.0e9);
// Texels per metre of level 0, the lod bias (negative: sharper), the lod fraction above which a
// level cross-fades into the next, and the cosine of the slope above which a pixel keeps the
// layer blend. clip_top is the coarsest level; a footprint coarser than it still reads it.
uniform float clip_d0 = 200.0;
uniform float clip_lod_bias = 0.0;
uniform float clip_blend_from = 0.7;
uniform float clip_steep_cos = 0.6;
// A footprint under this many texels of level 0 keeps the layer blend (magnifying a bake would
// show its texels where the blend shows the surface's own).
uniform float clip_near = 0.5;
uniform int clip_top = 0;
// A pixel at least this covered reads the bake (the rest of its weight renormalised).
const float CLIP_FULL = 0.5;
#endif
#ifdef GROUND_BAKE_OUT
// The bake shaders (authored_ground_bake*.gdshader): bake_pass 0 writes the lit albedo and AO,
// 1 the normal and roughness, unshaded and premultiplied so the alpha channel carries data. The
// viewport encodes colour to sRGB on output; pass 1 pre-decodes so its bytes are the values.
uniform int bake_pass = 0;
#endif

// Map-frame normal, position and the per-vertex rule fields (UV2: curvature, steepness).
varying vec3 v_normal;
varying vec3 v_position;
varying vec2 v_fields;
// GROUND_PREPASS_FULL (defined only by a probe) restores the engine's lighting from NORMAL and
// ROUGHNESS, which runs the layer blend in the depth pre-pass too (see LIGHTING).
#ifndef GROUND_PREPASS_FULL
#define GROUND_LIT_VARYINGS
#endif
#ifdef GROUND_LIT_VARYINGS
// Fragment to light (see LIGHTING): the layer-blended view-space normal, its roughness (after
// the engine's roughness limiter) and the specular amount.
varying vec3 v_lit_normal;
varying float v_lit_roughness;
varying float v_lit_specular;
#endif

const float INV_UINT_MAX = 1.0 / 4294967295.0;
// A weight at or below this is treated as absent (under half an 8-bit step).
const float WEIGHT_EPSILON = 0.002;
// The base surface's layer, and the last valid document surface index (paint_layer's size).
const int BASE_LAYER = 0;
const int LAST_PAINT_INDEX = 63;
// Fine weight over which a pixel's own component cancels its share of the broad tint
// (GroundBroadTint.OWN_START / OWN_END).
const float BROAD_OWN_START = 0.2;
const float BROAD_OWN_END = 0.8;
// Score of a surface not sampled at this pixel: far below any real score, so it never
// comes within biome_blend_width of the top.
const float ABSENT_SCORE = -1e6;

// Slopes (see STEEP FACES): each projection is weighted by |n . axis| ^ PROJECTION_SHARPNESS,
// so the least stretched one leads, and a share under PROJECTION_MIN_WEIGHT is dropped (flat
// ground: top-down alone, exactly). TerrainRules.projection_weights is the CPU twin.
// Projections meet by a height blend (PROJECTION_CONTRAST, PROJECTION_BAND: the taller detail
// wins, as between surfaces), not a cross-fade, which double-exposed two rock patterns into a
// smear.
const float PROJECTION_SHARPNESS = 8.0;
const float PROJECTION_MIN_WEIGHT = 0.04;
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
const vec2 RULE_NOISE_LAYER_OFFSET = vec2(37.13, 23.71);
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
// the X-facing plane, y: top-down, z: the Z-facing plane). A planar projection along an axis
// stretches the texture by 1 / |n . axis|, so each is weighted by that dot product sharpened;
// exactly (0, 1, 0) while both side shares are under PROJECTION_MIN_WEIGHT (gentler than
// about 34 degrees on a face turned to X or Z, about 44 on one turned 45 degrees between),
// which is what lets flat ground skip the side code.
vec3 projection_weights(vec3 n) {
	vec3 w = pow(abs(n) + 1e-4, vec3(PROJECTION_SHARPNESS));
	w /= w.x + w.y + w.z;
	if (max(w.x, w.z) <= PROJECTION_MIN_WEIGHT) {
		return vec3(0.0, 1.0, 0.0);
	}
	w = max(w - PROJECTION_MIN_WEIGHT, vec3(0.0));
	return w / (w.x + w.y + w.z);
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

// Whether `layer`'s side planes take the mosaic breakup: every surface but the cliff-role ones
// (layer_flags bit 0), whose layered beds must stay level around the map. A grass or soil side
// plane without it would tile plainly and stand its painted strokes all down the slope.
bool side_mosaic(float layer) {
	return breakup_enabled && (layer_flags[int(layer)] & 1) == 0;
}

// One layer's height on side plane `s` (through the mosaic where side_mosaic allows it).
float side_height(float layer, float tile, SidePlane s) {
	if (side_mosaic(layer)) {
		return top_height(layer, tile, tile_frame(s.uv), s.uv, s.gx, s.gy);
	}
	return textureGrad(layer_height_array, vec3(s.uv / tile, layer), s.gx / tile, s.gy / tile).r;
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
		h.x = side_height(layer, tile, side_plane(0, n, p, dpx, dpy));
		score.x = proj.x + (h.x - 0.5) * PROJECTION_CONTRAST;
	}
	if (proj.z > 0.0) {
		h.z = side_height(layer, tile, side_plane(1, n, p, dpx, dpy));
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
			if (side_mosaic(layer)) {
				TopSample side = sample_top(layer, tile, tile_frame(s.uv), s.uv, s.gx, s.gy);
				acc.albedo += side.albedo * k;
				// sample_top's normal is along (+u, +v), +v down; the plane's b is image up.
				acc.normal += perturb(vec2(side.normal_uv.x, -side.normal_uv.y), s.t, s.b, n) * k;
				acc.orm += side.orm * k;
				acc.height += side.height * k;
				continue;
			}
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

// A 3D value noise at noise-space point (p, h) (TerrainRules.layered_noise): the value noise
// of layers one unit apart in h, layer k's lattice shifted by RULE_NOISE_LAYER_OFFSET * k,
// blended by smoothstep and rescaled about 0.5 so its spread does not dip between layers. On
// a layer (flat ground at height 0) it is that layer's value noise alone, one lookup.
float layered_noise(vec2 p, float h) {
	float layer = floor(h);
	float t = h - layer;
	t = t * t * (3.0 - 2.0 * t);
	float low = value_noise(p + RULE_NOISE_LAYER_OFFSET * layer);
	if (t <= 0.0) {
		return low;
	}
	float high = value_noise(p + RULE_NOISE_LAYER_OFFSET * (layer + 1.0));
	return 0.5 + (mix(low, high, t) - 0.5) * inversesqrt(t * t + (1.0 - t) * (1.0 - t));
}

// Two-octave rule noise at map-frame point (xz, y), three-dimensional so a face of any slope
// and facing cuts it into patches as round as flat ground's (TerrainRules.rule_noise).
float rule_noise(vec2 xz, float y, vec2 offset) {
	vec2 p = xz / RULE_NOISE_SCALE_M + offset;
	float h = y / RULE_NOISE_SCALE_M;
	float n = layered_noise(p, h) * 0.65
		+ layered_noise(p * 2.3 + vec2(5.2, -1.7), h * 2.3) * 0.35;
	return clamp(n, 0.0, 1.0);
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

// The accent noise's lattice position at map-frame XZ. `shape` is the row's ground look
// accent shape (stretch, stretch angle, break, edge scale; PLAIN_SHAPE: today's): a stretch draws
// every patch that many times longer along the angle (radians), a break warps the noise's domain
// by that many lattice cells at about a third of the patch size, so an edge breaks into fingers
// and islands rather than one lobed blob. ScatterMass.bare_params is the CPU copy.
vec2 accent_domain(vec2 world_xz, vec4 params, vec4 shape) {
	vec2 q = rotate(world_xz, ACCENT_ROTATION);
	if (shape.x == 1.0 && shape.z <= 0.0) {
		return q * params.y + params.zw;
	}
	vec2 r = rotate(q, vec2(cos(shape.y), sin(shape.y)));
	r.x /= max(shape.x, 0.1);
	vec2 p = r * params.y + params.zw;
	vec2 w = vec2(value_noise(p * 2.7 + vec2(5.3, 1.7)), value_noise(p * 2.7 + vec2(-8.1, 4.4))) - 0.5;
	return p + shape.z * w;
}

// One accent's patch weight 0..1 at map-frame XZ (GroundAccents.mask): params are
// (threshold, 1 / scale_m, domain offset), `shape` as accent_domain's, its w the ramp's half
// width in units of ACCENT_EDGE. Each finer octave is only fetched where it can still change
// the result, which is exact since the ramp clamps (fetching all three with no branch between
// them measured the same or slightly slower).
float accent_mask(vec2 world_xz, vec4 params, vec4 shape) {
	vec2 p = accent_domain(world_xz, params, shape);
	float low = params.x - ACCENT_EDGE * shape.w;
	float high = params.x + ACCENT_EDGE * shape.w;
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

#ifdef GROUND_LOOK
// GROUND LOOK: one accent's three-octave noise at map-frame XZ, with no early exit.
float accent_field(vec2 world_xz, vec4 params, vec4 shape) {
	vec2 p = accent_domain(world_xz, params, shape);
	return accent_octave(p).r * (1.0 - ACCENT_DETAIL - ACCENT_FINE)
		+ accent_octave(p * ACCENT_DETAIL_SCALE + ACCENT_DETAIL_OFFSET).g * ACCENT_DETAIL
		+ accent_octave(p * ACCENT_FINE_SCALE + ACCENT_FINE_OFFSET).b * ACCENT_FINE;
}

// GROUND LOOK: the rim's width in metres at a point, wobbled along the edge by `wobble`.
float rim_width_at(vec2 world_xz, float width_m, float wobble) {
	float wob = value_noise(world_xz / RIM_WOBBLE_M + vec2(23.9, -71.3)) * 2.0 - 1.0;
	return width_m * max(1.0 + wobble * wob, 0.1);
}

// GROUND LOOK: a rim-listed accent's (weight, rim, wet core), the rim (`rim_m` wide, wobbled by
// `wobble`) and the core (from `core_m` in) measured in metres from the ramp's top. Outside the
// patch the finer octaves are skipped where the coarser ones already rule it out, as in
// accent_mask. The test runs on its own arithmetic, the octaves raised by RIM_EXIT_MARGIN (a
// bound, never a product the field shares), and the field itself is then taken whole as before:
// sharing the field's partial sums moved single pixels by one level (a GPU compiler contracts a
// product used twice differently), and the field and its two probes must round alike.
vec3 accent_mask_rim_m(
	vec2 world_xz, vec4 params, vec4 shape, float rim_m, float wobble, float core_m
) {
	float low = params.x - ACCENT_EDGE * shape.w;
	float high = params.x + ACCENT_EDGE * shape.w;
	vec2 p = accent_domain(world_xz, params, shape);
	float coarse = accent_octave(p).r + RIM_EXIT_MARGIN;
	if (coarse * (1.0 - ACCENT_DETAIL - ACCENT_FINE) + ACCENT_DETAIL + ACCENT_FINE < low) {
		return vec3(0.0);
	}
	float detail = accent_octave(p * ACCENT_DETAIL_SCALE + ACCENT_DETAIL_OFFSET).g + RIM_EXIT_MARGIN;
	if (
		coarse * (1.0 - ACCENT_DETAIL - ACCENT_FINE) + detail * ACCENT_DETAIL + ACCENT_FINE < low
	) {
		return vec3(0.0);
	}
	float n = accent_field(world_xz, params, shape);
	if (n <= low) {
		return vec3(0.0);
	}
	float w = smoothstep(low, high, n);
	if (n >= high + RIM_REACH) {
		return vec3(w, 0.0, core_m > 0.0 ? w : 0.0);
	}
	float nx = accent_field(world_xz + vec2(RIM_PROBE_M, 0.0), params, shape);
	float nz = accent_field(world_xz + vec2(0.0, RIM_PROBE_M), params, shape);
	float grad = length(vec2(nx - n, nz - n)) / RIM_PROBE_M;
	float depth = (n - high) / max(grad, 1e-4);
	float rim = 0.0;
	if (rim_m > 0.0) {
		rim = w * (1.0 - smoothstep(0.0, rim_width_at(world_xz, rim_m, wobble), depth));
	}
	float core = core_m > 0.0 ? w * smoothstep(core_m, core_m * 1.8, depth) : 0.0;
	return vec3(w, rim, core);
}

// GROUND LOOK: biome row `row`'s look slot, and the slot whose zones colour layer `layer` (-1:
// none).
int look_row_slot(int row) {
	return look_row_slots[row >> 2][row & 3];
}

int look_layer_slot(int layer) {
	return layer < 0 ? -1 : look_layer_slots[layer >> 2][layer & 3];
}

// GROUND LOOK: slot `slot`'s baked texel at map-frame XZ, decoded (outside look_rect the edge
// texel holds).
vec4 look_fetch(int slot, vec2 world_xz) {
	vec2 uv = (world_xz - look_rect.xy) / look_rect.zw;
	vec4 t;
	if (slot == 0) {
		t = textureLod(look_tex_0, uv, 0.0);
	} else if (slot == 1) {
		t = textureLod(look_tex_1, uv, 0.0);
	} else if (slot == 2) {
		t = textureLod(look_tex_2, uv, 0.0);
	} else {
		t = textureLod(look_tex_3, uv, 0.0);
	}
	return zone_decode(t);
}

// GROUND LOOK on steep faces: look_texel, look_fetch read in 3D on a face.
#include "res://shaders/ground_steep_zones.gdshaderinc"

// GROUND LOOK: one ground sample's albedo `a` under slot `s`'s look, from its texel `zone`. A
// zoned layer's sample (`zoned`) takes the zone colour and keeps its brush: its luminance over
// the light reference, raised to the brush contrast (mean-preserving around the brush key when
// the brush mean is set), and the brush hue of its own hue; any other surface takes the light's
// luminance. Not capped here.
vec3 look_albedo(vec3 a, vec4 zone, bool zoned, int s) {
	vec3 lit = a * mix(1.0, zone.a, look_light[s].y);
	if (!zoned) {
		return lit;
	}
	vec3 ref = max(look_ref[s].rgb, vec3(1e-3));
	vec4 brush_k = look_brush[s];
	float ratio = max(dot(a, ZONE_LUMA), 1e-4) / dot(ref, ZONE_LUMA);
	vec3 hue = mix(vec3(1.0), a / (ref * ratio), brush_k.y);
	float brush = pow(ratio, brush_k.x);
	if (brush_k.w > 0.0) {
		brush = pow(brush_k.w, brush_k.z) * pow(ratio / brush_k.w, brush_k.x);
	}
	vec3 z = ref * zone.rgb * brush * hue;
	return mix(lit, z, look_light[s].x);
}
#endif

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

// One of the pixel's own components for the broad edge: layer `layer` with tint weight
// `weight` shown at fine weight `fine`; (its colour x what it takes away, what it takes away).
vec4 broad_own(int layer, float weight, float fine) {
	if (layer < 0 || weight <= 0.0 || fine <= WEIGHT_EPSILON) {
		return vec4(0.0);
	}
	float shown = weight * smoothstep(BROAD_OWN_START, BROAD_OWN_END, fine);
	return vec4(layer_tint[layer].rgb * shown, shown);
}

// The broad scale of the two-scale edge (see BROAD EDGE; GroundBroadTint.tint_at is the CPU
// twin): the tint map less the pixel's own components, the ground corners (`slots`, `g`: a
// biome ground, weight 1) and the painted entries (`pl`, `pw`: weight layer_tint[layer].w),
// recolours the surface toward the mean colour of what is left.
vec3 apply_broad_edge(vec3 albedo, vec2 world_xz, ivec4 slots, vec4 g, ivec4 pl, vec4 pw) {
	vec2 st = weight_uv(world_xz, vec2(textureSize(biome_slots_map, 0)));
	vec4 broad = texture_bspline(broad_tint_map, st);
	if (broad.a <= WEIGHT_EPSILON) {
		return albedo;
	}
	vec4 own = broad_own(biome_rules[slots.x].x, 1.0, g.x)
		+ broad_own(biome_rules[slots.y].x, 1.0, g.y)
		+ broad_own(biome_rules[slots.z].x, 1.0, g.z)
		+ broad_own(biome_rules[slots.w].x, 1.0, g.w)
		+ broad_own(pl.x, layer_tint[max(pl.x, 0)].w, pw.x)
		+ broad_own(pl.y, layer_tint[max(pl.y, 0)].w, pw.y)
		+ broad_own(pl.z, layer_tint[max(pl.z, 0)].w, pw.z)
		+ broad_own(pl.w, layer_tint[max(pl.w, 0)].w, pw.w);
	float left = broad.a - own.a;
	if (left <= WEIGHT_EPSILON) {
		return albedo;
	}
	vec3 mean = clamp((broad.rgb - own.rgb) / left, vec3(0.0), vec3(1.0));
	// Recolour rather than paint over: the mean colour, carrying the ground's own luminance
	// detail relative to the base surface's mean.
	const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
	float base_luma = max(
		dot(textureLod(layer_albedo_array, vec3(0.5, 0.5, float(BASE_LAYER)), 16.0).rgb, LUMA), 0.02
	);
	float detail = dot(albedo, LUMA) / base_luma;
	// Painted weight wins: the tint recolours the automatic ground, not a painted stroke.
	float tint = biome_broad_strength * smoothstep(0.0, biome_broad_full, left)
		* (1.0 - smoothstep(BROAD_OWN_START, BROAD_OWN_END, dot(pw, vec4(1.0))));
	vec3 recoloured = clamp(mean * detail, vec3(0.0), vec3(1.0));
	return mix(albedo, recoloured, tint);
}

float blend_score(float weight, float height) {
	return weight + (height - 0.5) * biome_height_contrast;
}

#ifndef GROUND_SKIRT
// FIRE: persistent ground fire's char and ember glow (the whole model is in the include).
#include "res://shaders/fire_glow.gdshaderinc"
#endif

#ifdef GROUND_SKIRT
// Skirt fade at a point: 1 on the map edge, 0 from skirt_fade_m out (skirt_fade.gdshaderinc;
// the noise leaves the edge itself at exactly 1, so the skirt meets the map without a seam).
float skirt_alpha(vec2 world_xz) {
	return skirt_alpha_seeded(world_xz, breakup_seed);
}
#endif

#ifdef GROUND_LIT_VARYINGS
// The roughness the pre-pass and the ambient light see (see LIGHTING), pulled to WET_ROUGHNESS
// on the wet line as the full roughness is. 0.9 came closest to the full roughness's ambient in
// day, sunset, night and steep views (0.85, 0.95 and 1.0 measured; a probe may define another).
#ifndef GROUND_AMBIENT_ROUGHNESS
#define GROUND_AMBIENT_ROUGHNESS 0.9
#endif
const float AMBIENT_ROUGHNESS = GROUND_AMBIENT_ROUGHNESS;

float lit_schlick(float u) {
	float m = 1.0 - u;
	float m2 = m * m;
	return m2 * m2 * m;
}

// The engine's screen-space roughness limiter (project defaults: amount 0.25, limit 0.18), which
// it applies to the fragment's ROUGHNESS from NORMAL's derivatives.
float limited_roughness(float r, vec3 n) {
	vec3 dndu = dFdx(n);
	vec3 dndv = dFdy(n);
	float variance = 0.25 * (dot(dndu, dndu) + dot(dndv, dndv));
	float kernel = min(2.0 * variance, 0.18);
	return sqrt(min(1.0, r * r + kernel));
}
#endif

#ifdef GROUND_CLIPMAP
vec4 clip_tex_a(int l, vec2 uv, vec2 gx, vec2 gy) {
	if (l == 0) {
		return textureGrad(clip_a0, uv, gx, gy);
	} else if (l == 1) {
		return textureGrad(clip_a1, uv, gx, gy);
	} else if (l == 2) {
		return textureGrad(clip_a2, uv, gx, gy);
	} else if (l == 3) {
		return textureGrad(clip_a3, uv, gx, gy);
	}
	return textureGrad(clip_a4, uv, gx, gy);
}

vec4 clip_tex_b(int l, vec2 uv, vec2 gx, vec2 gy) {
	if (l == 0) {
		return textureGrad(clip_b0, uv, gx, gy);
	} else if (l == 1) {
		return textureGrad(clip_b1, uv, gx, gy);
	} else if (l == 2) {
		return textureGrad(clip_b2, uv, gx, gy);
	} else if (l == 3) {
		return textureGrad(clip_b3, uv, gx, gy);
	}
	return textureGrad(clip_b4, uv, gx, gy);
}

// The baked composite at a point (see CLIPMAP): a, b are the weighted sums of the levels that
// cover it; the return is the covered share (0: none, the layer blend runs). The level is the
// footprint's finer axis in texels of level 0, floored; the upper part of each octave
// cross-fades into the level above, and so does the edge of a window (its fade width), so a
// level that is missing or still filling hands over to the next without a seam.
float clip_fetch(vec2 xz, vec2 dx, vec2 dy, float slope_cos, out vec4 a, out vec4 b) {
	a = vec4(0.0);
	b = vec4(0.0);
	if (slope_cos < clip_steep_cos) {
		return 0.0;
	}
	if (all(greaterThanEqual(xz, clip_hole.xy)) && all(lessThanEqual(xz, clip_hole.zw))) {
		return 0.0;  // edited and not rebaked yet: the live ground
	}
	float fp = min(length(dx), length(dy));
	if (fp * clip_d0 < clip_near) {
		// Finer than level 0 can show (the eye view's ground at the feet): the blend draws it.
		return 0.0;
	}
	float lod = max(log2(max(fp, 1e-5) * clip_d0) + clip_lod_bias, 0.0);
	int first = min(int(floor(lod)), clip_top);
	float up = first < clip_top ? smoothstep(clip_blend_from, 1.0, lod - float(first)) : 0.0;
#ifdef CLIP_NO_BLEND
	up = 0.0;  // measurement define: one level per pixel
#endif
	// A footprint well past the coarsest level's texel (zoomed far out, the windows have no mips)
	// would alias, so the top level fades out there and the layer blend, which filters, takes over.
	float far_keep = 1.0 - smoothstep(0.35, 0.9, lod - float(clip_top));
#ifdef CLIP_NO_FAR
	far_keep = 1.0;  // measurement define
#endif
	// A level more than one octave coarser than the pixel wants would show as blur (a window that
	// is not held or not baked here, the eye view, a level cap): the layer blend draws it instead.
	int last = min(clip_top, first + 1);
#ifdef CLIP_NO_OCTAVE
	last = clip_top;  // measurement define
#endif
	float rem = 1.0;
	for (int l = first; l <= last; l++) {
		vec4 valid = clip_valid[l];
		vec4 info = clip_info[l];
		vec2 inside = min(xz - valid.xy, valid.zw - xz) - info.z;
		float c = clamp(min(inside.x, inside.y) / info.y, 0.0, 1.0);
		if (l == clip_top) {
			c *= far_keep;
		}
		if (l == first) {
			c *= 1.0 - up;
		}
		float w = rem * c;
		if (w > 0.0) {
			vec2 uv = xz * info.x;
			a += w * clip_tex_a(l, uv, dx * info.x, dy * info.x);
			b += w * clip_tex_b(l, uv, dx * info.x, dy * info.x);
			rem -= w;
		}
		if (rem < 0.01) {
			break;
		}
	}
	return 1.0 - rem;
}
#endif

#if defined(GROUND_CLIPMAP) || defined(GROUND_BAKE_OUT)
// sRGB bytes to linear: how the bake's sRGB output is undone (and, for pass 1, pre-compensated).
vec3 clip_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
#endif

void vertex() {
	v_normal = NORMAL;
	v_position = VERTEX;
	v_fields = UV2;
#ifdef GROUND_BAKE_OUT
	// The bake draws the map top-down: each vertex goes to its map-frame position.
	VERTEX = vec3(UV.x, VERTEX.y, UV.y);
#endif
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
	// What the blend (or the clipmap's bake) hands to the tail: the wet line, roughness, specular
	// amount and the map-frame normal before the fire's flattening.
	float wet_line = 0.0;
	float roughness = 1.0;
	float specular = 0.5;
	vec3 n_map = n_geom;
#ifdef GROUND_CLIPMAP
	vec4 clip_a;
	vec4 clip_b;
	float clip_w = clip_fetch(world_xz, dx, dy, n_geom.y, clip_a, clip_b);
	if (clip_w >= CLIP_FULL) {
		// The baked composite (see CLIPMAP). Only the wet line is read as the blend reads it, so
		// the depth pre-pass needs nothing else; the rest is two fetches per level.
		if (water_present != 0) {
			wet_line = texture(water_weights, weight_uv(world_xz, vec2(textureSize(water_weights, 0)))).a;
		}
		clip_a /= clip_w;
		clip_b /= clip_w;
		ALBEDO = clip_to_linear(clip_a.rgb);
		AO = clip_a.a;
		AO_LIGHT_AFFECT = 0.0;
		METALLIC = 0.0;
		roughness = clip_b.b;
		vec2 n_xz = clip_b.rg * 2.0 - 1.0;
		n_map = vec3(n_xz.x, sqrt(max(1.0 - dot(n_xz, n_xz), 0.0)), n_xz.y);
	} else
#ifdef CLIP_ONLY
	// Measurement define: the layer blend dead, to see what its registers cost the bake's read.
	if (false)
#endif
#endif
	{
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
#ifdef GROUND_LOOK
	// GROUND LOOK: the components' total weight, the part carrying a look, the dominant looked
	// component's slot and weight, and the strongest rim-listed accent rim and wet core here.
	float comp_w = 0.0;
	float look_w = 0.0;
	int dom = -1;
	float dom_w = 0.0;
	float rim_accent = 0.0;
	float core_accent = 0.0;
	int rim_accent_layer = -1;
#endif
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
#ifdef GROUND_LOOK
		int slot = look_present != 0 ? look_row_slot(row) : -1;
		vec4 shape = slot >= 0 ? look_shape[slot] : PLAIN_SHAPE;
		comp_w += weight;
		if (slot >= 0) {
			look_w += weight;
			if (weight > dom_w) {
				dom_w = weight;
				dom = slot;
			}
		}
#else
		vec4 shape = PLAIN_SHAPE;
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
				float patch_w;
#ifdef GROUND_LOOK
				if (
					slot >= 0 && (look_rim[slot].x > 0.0 || look_rim_more[slot].z > 0.0)
					&& any(equal(look_rim_layers[slot], ivec4(to)))
				) {
					// A rim-listed accent: its rim and wet core, measured in metres.
					vec3 mrc = accent_mask_rim_m(
						world_xz, params, shape, look_rim[slot].x, look_rim[slot].w,
						look_rim_more[slot].z
					);
					patch_w = mrc.x;
					float r = mrc.y * remaining;
					float c = mrc.z * remaining;
					if (r > rim_accent || c > core_accent) {
						rim_accent = max(rim_accent, r);
						core_accent = max(core_accent, c);
						rim_accent_layer = to;
					}
				} else {
					patch_w = accent_mask(world_xz, params, shape);
				}
#else
				patch_w = accent_mask(world_xz, params, shape);
#endif
				float share = remaining * patch_w;
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
	float band = biome_blend_width;
#ifdef GROUND_LOOK
	// GROUND LOOK: the share of the pixel whose biome carries a look (0: today's ground exactly,
	// 1: the looked ground exactly), its dominant look's texel, and the strongest painted stroke
	// here for its rim and its partial band (the height blend narrows to the look's
	// path_blend_width where a stroke is partial).
	bool look_any = dom >= 0;
	float look_share = look_any ? look_w / max(comp_w, 1e-5) : 0.0;
	vec4 zone_dom = look_any ? look_texel(dom, world_xz, v_position.y, n_geom.y) : vec4(1.0);
	float rim_path = 0.0;
	int rim_path_layer = -1;
	if (look_present != 0) {
		// Uniform control flow: the stroke's weight gradient in metres from its screen
		// derivatives, solving dFdx = dot(dx, g), dFdy = dot(dy, g).
		float top_w = 0.0;
		for (int k = 0; k < 4; k++) {
			if (painted_layers[k] >= 0 && holds[k] == 0.0 && painted_w[k] > top_w) {
				top_w = painted_w[k];
				rim_path_layer = painted_layers[k];
			}
		}
		top_w = clamp(top_w, 0.0, 1.0);
		float path_partial = 1.0 - abs(2.0 * top_w - 1.0);
		vec2 gs = vec2(dFdx(top_w), dFdy(top_w));
		float det = dx.x * dy.y - dx.y * dy.x;
		det = sign(det) * max(abs(det), 1e-12);
		vec2 gw = vec2(gs.x * dy.y - gs.y * dx.y, dx.x * gs.y - dy.x * gs.x) / det;
		if (look_any) {
			float path_rim_m = look_rim[dom].y;
			if (path_rim_m > 0.0 && any(equal(look_rim_layers[dom], ivec4(rim_path_layer)))) {
				float depth = (top_w - 0.5) / max(length(gw), 1e-3);
				rim_path = smoothstep(0.4, 0.5, top_w)
					* (1.0 - smoothstep(0.0, rim_width_at(world_xz, path_rim_m, look_rim[dom].w), depth));
			}
			if (look_rim_more[dom].y > 0.0) {
				band = mix(band, look_rim_more[dom].y, path_partial * look_share);
			}
		}
	}
#endif

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
#ifdef GROUND_LOOK
	// GROUND LOOK: under a look ground.albedo carries the looked samples (look_albedo) and
	// plain_albedo today's, for a pixel only partly looked; the rim surfaces' shares.
	vec3 plain_albedo = vec3(0.0);
	float rim_share_accent = 0.0;
	float rim_share_path = 0.0;
#endif
	for (int k = 0; k < 4; k++) {
		if (cw[k] > WEIGHT_EPSILON) {
			float b = count > 1 ? scores[k] - (top - band) : 1.0;
			if (b > 0.0) {
				float h;
				float layer = float(cl[k]);
				float tile = layer_tile_m[cl[k]];
				vec3 pk = surface_projections(
					layer, tile, frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy, proj,
					false, h
				);
#ifdef GROUND_LOOK
				vec3 before = ground.albedo;
#endif
				accumulate(
					layer, tile, frame, world_xz, dx, dy, n_geom, v_position, dpx, dpy, pk, b,
					ground
				);
#ifdef GROUND_LOOK
				if (look_any) {
					vec3 a = (ground.albedo - before) / b;
					plain_albedo += b * a;
					int zs = look_layer_slot(cl[k]);
					vec4 zone = zs >= 0 && zs != dom ? look_texel(zs, world_xz, v_position.y, n_geom.y) : zone_dom;
					ground.albedo = before + b * look_albedo(a, zone, zs >= 0, zs >= 0 ? zs : dom);
					rim_share_accent += (cl[k] == rim_accent_layer) ? b : 0.0;
					rim_share_path += (cl[k] == rim_path_layer) ? b : 0.0;
				}
#endif
				total += b;
			}
		}
	}
	float inv_total = 1.0 / max(total, 1e-5);
	ground.albedo *= inv_total;
	ground.orm *= inv_total;
	ground.height *= inv_total;
#ifdef GROUND_LOOK
	float core_wet = 0.0;
	if (look_any) {
		plain_albedo *= inv_total;
		vec4 rim_k = look_rim[dom];
		vec4 rim_more = look_rim_more[dom];
		if (rim_k.z > 0.0 && (rim_accent > 0.0 || rim_path > 0.0)) {
			// The painted rim: only the rim surface's own share moves, in a ragged band.
			float rim = max(rim_accent * rim_share_accent, rim_path * rim_share_path) * inv_total;
			float rag = value_noise(world_xz / RIM_WAVE_M + vec2(-57.1, 33.7));
			rim *= mix(1.0 - RIM_RAGGED, 1.0, rag);
			if (rim_more.x > 0.0) {
				// Lengths of edge with no rim at all.
				float gap = value_noise(world_xz / RIM_GAP_M + vec2(31.3, 5.9));
				rim *= smoothstep(rim_more.x - 0.08, rim_more.x + 0.08, gap);
			}
			ground.albedo = mix(
				ground.albedo, look_rim_color[dom].rgb, clamp(rim * rim_k.z, 0.0, 1.0)
			);
		}
		if (rim_more.w > 0.0 && core_accent > 0.0) {
			// The wet core of a rim-listed patch, darker and glossier.
			core_wet = clamp(core_accent * rim_share_accent * inv_total, 0.0, 1.0);
			ground.albedo *= 1.0 - rim_more.w * core_wet;
		}
		vec3 tint = look_accent_tint[dom].rgb;
		if (any(notEqual(tint, vec3(1.0))) && rim_share_accent > 0.0) {
			// The rim-listed accent's own share takes the accent tint.
			ground.albedo *= mix(vec3(1.0), tint, clamp(rim_share_accent * inv_total, 0.0, 1.0));
		}
	}
#endif
#ifndef GROUND_SKIRT
	if (broad_present != 0) {
		ground.albedo = apply_broad_edge(
			ground.albedo, world_xz, slots, g, painted_layers, painted_w
		);
#ifdef GROUND_LOOK
		if (look_any && look_share < 1.0) {
			plain_albedo = apply_broad_edge(
				plain_albedo, world_xz, slots, g, painted_layers, painted_w
			);
		}
#endif
	}
#endif

	// Cavity depth itself drifts at a few metres, so clumpy and smooth stretches alternate
	// instead of an even mottle.
	float clumpiness = mix(0.3, 1.0, value_noise(world_xz / 3.5 + vec2(-71.3, 13.9)));
	float cavity = mix(
		1.0 - cavity_strength * clumpiness, 1.0, smoothstep(0.0, 0.8, ground.height)
	);
	// GROUND LOOK: the looked ground has its colour and light already (look_albedo) and is
	// capped; its zones replace the broad variation. A pixel only partly looked mixes it with
	// today's by look_share.
	vec3 lit_albedo;
#ifdef GROUND_LOOK
	if (!look_any) {
		lit_albedo = apply_variation(ground.albedo * cavity, world_xz);
	} else {
		vec3 looked = light_field_capped_by(
			ground.albedo * cavity, look_light[dom].z, look_light[dom].w, look_ref[dom].w
		);
		lit_albedo = look_share >= 1.0
			? looked
			: mix(apply_variation(plain_albedo * cavity, world_xz), looked, look_share);
	}
	float gloss = max(wet_line, core_wet * look_share);
#else
	lit_albedo = apply_variation(ground.albedo * cavity, world_xz);
	float gloss = max(wet_line, 0.0);
#endif
	// The wet line (WET DRESSING): wet ground is darker and glossier, whatever its surface.
	ALBEDO = lit_albedo * (1.0 - WET_DARKEN * wet_line);
	AO = ground.orm.r;
	AO_LIGHT_AFFECT = 0.0;
	roughness = mix(ground.orm.g, WET_ROUGHNESS, WET_GLOSS * gloss);
	METALLIC = ground.orm.b;
	n_map = normalize(ground.normal + n_geom * 1e-4);
	}
#if !defined(GROUND_SKIRT) && !defined(GROUND_BAKE_OUT)
	// FIRE (fire_glow.gdshaderinc): the burn turns the ground to matte char and glows on it (a
	// sheen on a near-black ground read as grey and showed every facet of its normals). The
	// clipmap's bake leaves it out: fire is per pixel.
	vec3 fire_albedo = ALBEDO;
	float charred = 0.0;
	EMISSION = fire_glow(world_xz, TIME, fire_albedo, charred);
	ALBEDO = fire_albedo;
	roughness = mix(roughness, 1.0, charred);
	specular = 0.5 - 0.45 * charred;
	// Char's normals lean up, so the ground's facets do not show through its even near-black.
	n_map = normalize(mix(n_map, vec3(0.0, 1.0, 0.0), FIRE_FLATTEN * charred));
#endif
	vec3 n_view = normalize(mat3(VIEW_MATRIX) * (mat3(MODEL_MATRIX) * n_map));
#ifdef GROUND_SKIRT
	// The fade in colour (see SKIRT): lit ground * a + backdrop * (1 - a), and the fog the map's
	// ground gets, times a.
	ALBEDO *= skirt_a;
	specular = 0.5 * skirt_a;
	EMISSION = skirt_backdrop_color(INV_VIEW_MATRIX) * (1.0 - skirt_a);
	FOG = skirt_fog_at(VERTEX, INV_VIEW_MATRIX) * vec4(1.0, 1.0, 1.0, skirt_a);
#endif
	SPECULAR = specular;
#ifdef GROUND_LIT_VARYINGS
	// LIGHTING: the pre-pass sees the interpolated normal (NORMAL is not written) and a roughness
	// that needs only the wet line; light() shades with the layer-blended values.
	v_lit_normal = n_view;
	v_lit_roughness = limited_roughness(roughness, n_view);
	v_lit_specular = specular;
#ifdef GROUND_SKIRT_RING
	// SKIRT RING: how much of the sun's shadow term light() gives back (0 at the edge, 1 at the
	// ring's outer edge, where the shadowless skirt begins).
	float ring_d = length(max(abs(world_xz) - skirt_half_extent, vec2(0.0)));
	v_ring_fade = smoothstep(skirt_shadow_m * SKIRT_RING_FADE_FROM, skirt_shadow_m, ring_d);
#endif
	ROUGHNESS = mix(AMBIENT_ROUGHNESS, WET_ROUGHNESS, WET_GLOSS * wet_line);
#ifdef GROUND_LIT_KEEP_NORMAL
	// Probe only: the full normal and roughness written as before, so a diff against
	// GROUND_PREPASS_FULL measures light() alone.
	NORMAL = n_view;
	ROUGHNESS = roughness;
#endif
#else
	ROUGHNESS = roughness;
	NORMAL = n_view;
#endif
#ifdef GROUND_BAKE_OUT
	EMISSION = vec3(0.0);
	if (bake_pass == 0) {
		ALPHA = clamp(AO, 0.0, 1.0);
		ALBEDO = clamp(ALBEDO, vec3(0.0), vec3(1.0));
	} else {
		vec3 packed_nr = clamp(vec3(n_map.x * 0.5 + 0.5, n_map.z * 0.5 + 0.5, roughness), vec3(0.0), vec3(1.0));
		ALBEDO = clip_to_linear(packed_nr);
		ALPHA = 1.0;
	}
#endif
}

#ifdef GROUND_LIT_VARYINGS
// Burley diffuse and Schlick-GGX specular as Godot 4.7's light_compute does them, with the
// layer-blended normal and roughness from fragment().
void light() {
	vec3 n = v_lit_normal;
	float rough = v_lit_roughness;
	float ndl = min(dot(n, LIGHT), 1.0);
	float cndv = max(dot(n, VIEW), 1e-4);
	float cndl = max(ndl, 0.0);
	vec3 h = normalize(VIEW + LIGHT);
	float cldh = clamp(dot(LIGHT, h), 0.0, 1.0);
	float att = ATTENUATION;
#ifdef GROUND_SKIRT_RING
	// The sun's shadow fades out over the ring (see SKIRT RING); a lamp's falloff is left alone.
	if (LIGHT_IS_DIRECTIONAL) {
		att = mix(att, 1.0, v_ring_fade);
	}
#endif
	if (METALLIC < 1.0) {
		float fd90m1 = 2.0 * cldh * cldh * rough - 0.5;
		float fdv = 1.0 + fd90m1 * lit_schlick(cndv);
		float fdl = 1.0 + fd90m1 * lit_schlick(cndl);
		DIFFUSE_LIGHT += LIGHT_COLOR * ((1.0 / PI) * fdv * fdl * cndl) * att;
	}
	if (rough > 0.0) {
		float cndh = clamp(dot(n, h), 0.0, 1.0);
		float a2 = rough * rough;
		float a = cndh * a2;
		float k = a2 / (1.0 - cndh * cndh + a * a);
		float d = k * k * (1.0 / PI);
		float g = 0.5 / mix(2.0 * cndl * cndv, cndl + cndv, a2);
		vec3 f0 = mix(vec3(0.16 * v_lit_specular * v_lit_specular), ALBEDO, vec3(METALLIC));
		float f90 = clamp(dot(f0, vec3(50.0 * 0.33)), METALLIC, 1.0);
		vec3 f = f0 + (f90 - f0) * lit_schlick(cldh);
		vec4 r4 = rough * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
		float a004 = min(r4.x * r4.x, exp2(-9.28 * cndv)) * r4.x + r4.y;
		vec2 dfg = vec2(-1.04, 1.04) * a004 + r4.zw;
		vec3 ec = 1.0 + f0 * (1.0 / max(dfg.x + dfg.y, 1e-3) - 1.0);
		SPECULAR_LIGHT += ec * (cndl * d * g) * f * LIGHT_COLOR * att * SPECULAR_AMOUNT;
	}
}
#endif
