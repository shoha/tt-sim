shader_type spatial;
render_mode specular_disabled, ambient_light_disabled;

/*
 * Painted ground (the authored terrain's chunks and skirt under the Painted look)
 * ==============================================================================
 *
 * tt-sim's terrain in the painter's ground manner (the prototype's, ported from the painter spike;
 * docs/systems/painter.md "Surfaces"). Two things are on screen:
 *   the BLOCK-IN: flat shapes, five close steps of a role's two variants from two low-frequency
 *   noises (neighbouring steps differ by a tenth of the variants' range, so a zone varies in
 *   chroma and value without spots);
 *   the MARKS: brush marks over most of the ground. Each is ONE flat colour, asked once where its
 *   middle lies: the role there (a mark that straddles the path's edge is all path or all meadow,
 *   so the edge is made of brush marks) and a neighbouring tone of that role.
 * A mark's outline is a brush alpha (PainterBrushes: layers round, dry, flat), drawn in to a
 * point at both ends and stretched about 2 to 1 along `stroke_dir`, the camera's right, so every
 * mark lies level on screen. A mark is found per pixel from a hashed cell grid in the strokes'
 * frame (two brick-offset layers of 1.3 x 0.55 m cells, and a layer of small marks only in drift
 * and litter zones), which follows the terrain and needs no nodes. A mark whose pixel footprint
 * passes `mark_px` fades out (each at its own limit), and past the upper limit the search is
 * skipped: the far ground is the flat block-in.
 * Roles (PainterGroundRoles.ROLES): meadow 0, floor 1, path 2, rock 3, shore 4. PainterSurfaces
 * makes the zone map from the terrain material's own maps (r meadow share, g path, b rock,
 * a shore) and the role ramps from the sheet. The material is lit only as a SELECTOR: light()
 * reads the sun's ATTENUATION and N.L and writes the role's lit or shade colour, with the
 * shadow's step wiggled a little by a brush streak (`cut`), never moved off its caster.
 *
 * MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd), as the chunks' and the skirt's
 * material_override.
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
// The persistent ground fire's bake and constants (fire.md "The ground"): the terrain's fire_present,
// fire_sim_map and fire_sim_rect are mirrored onto this material (FireLook.mirror_glow).
#include "res://shaders/fire_glow.gdshaderinc"

// Per role two variants (cool dark, warm light) of the lit and the shade colour, LINEAR.
uniform vec3 g_lit[18];
uniform vec3 g_shd[18];
uniform vec3 litter_col = vec3(0.5, 0.4, 0.15);
uniform vec3 drift_col = vec3(0.8, 0.8, 0.4);
uniform float drift = 0.3;
uniform float litter = 0.3;
uniform float patches = 1.0;
// The share of stroke cells that hold a mark at a zone edge, and how far they thin elsewhere.
uniform float marks = 1.0;
uniform float mark_thin = 0.25;
// The pixel footprints (metres) between which the marks fade out, each at its own limit.
uniform vec2 mark_px = vec2(0.06, 0.16);
// The cast shadow step's wiggle (attenuation units) by the brush streak.
uniform float cut_amp = 0.0;
// The path surfaces (PainterGroundPaths): per slot two variants of the lit and the shade colour
// (LINEAR) and a pattern (PainterGroundRoles.PATH_KINDS: 0 dirt, 1 cobble, 2 plates, 3 tiles,
// 4 gravel, 5 planks); the slot map (R8, the slot index, 255 none) or, with no map, the one slot
// the map paints (-1: the path role's own tone, the dirt pattern).
uniform vec3 p_lit[16];
uniform vec3 p_shd[16];
uniform int p_kind[8];
uniform int path_only = -1;
uniform sampler2D path_map : hint_default_black, filter_nearest, repeat_disable;
uniform bool path_map_present = false;
// The cliff stone: the value step of the lit lip at a cliff's top edge (and the dark at its foot),
// and the strength of the faces' strata bands.
uniform float cliff_edge = 0.0;
uniform float cliff_strata = 0.0;
// The polish (PainterGroundPaths): the lip's snow cap (the meadow's snow), the foot's share of the
// way to its shade colour, the lip's gold tint; a path under snow dusted at its edges.
uniform float cliff_snow = 0.0;
uniform float cliff_foot = 0.0;
// A cliff face's lit colour this share of the way to its shade (a middle value under the lit top).
uniform float cliff_face = 0.0;
uniform float cliff_warm = 0.0;
uniform float path_dust = 0.0;
// The meadow's gold and moss swathes (PainterMeadowSwathes): gold's two variants then moss's, lit
// and shade; the field's gold and moss thresholds, whether any is drawn and the most of its tone a
// swathe takes (swathe-mix); the map's seed (the field's offset, the gold and the moss edge's shift).
uniform vec3 sw_lit[4];
uniform vec3 sw_shd[4];
uniform vec4 sw_k = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec4 sw_seed = vec4(0.0);
// A stone's seam: how much darker the gap between cobbles, plates, tiles and boards is.
const float SEAM_DARK = 0.38;
// The strata bands' height (m) on a cliff face.
const float STRATA_H = 0.6;
// The sun height (sine of its elevation, 20 degrees) under which the turned-from-the-sun step
// shrinks with it (light()).
const float TURN_SUN_FULL = 0.34;
// The wet band: the wet line's value that the band's edge sits at, and what it does to a colour
// (darker and a little cooler, linear).
const float WET_EDGE = 0.45;
const vec3 WET_TINT = vec3(0.64, 0.70, 0.80);
uniform vec2 stroke_dir = vec2(1.0, 0.0);
uniform sampler2DArray brushes : filter_linear_mipmap, repeat_disable;
uniform bool brushes_present = false;
// The skirt ring round the map: it melts into `foot_col` (the far ground) past the map's edge.
uniform bool skirt = false;
uniform vec3 foot_col = vec3(0.4, 0.6, 0.4);
uniform vec2 half_extent = vec2(30.0);

uniform sampler2D zone_map : hint_default_black, filter_linear, repeat_disable;
uniform bool zone_present = false;
uniform float base_meadow = 1.0;
// A GLB map's own ground (card painter-glb-parity; PainterGlbMap): the map frame is the world's XZ
// (the mesh's UV is its texture's), and the zone is read from the mesh's baked albedo by its colour
// (glb_zone): uv = glb_uv * xz + glb_uv_b, the planar mapping fitted from the mesh's vertices.
uniform bool world_frame = false;
uniform bool glb_zone = false;
uniform sampler2D glb_albedo : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 glb_uv = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 glb_uv_b = vec2(0.0);
uniform vec3 glb_tint = vec3(1.0);
// The texels per metre of the baked albedo (for the colour read's mip level).
uniform float glb_texels_per_m = 8.0;
// The scorched ground's share (role 8, `char`: the scar a fire event leaves, the ash surface it
// stamps), present only when the document names one (PainterSurfaces.char_image). A different thing
// from role 6, `ash`, a burnt biome's own ground (zone2_map).
uniform sampler2D char_map : hint_default_black, filter_linear, repeat_disable;
uniform bool char_present = false;
// The biome zone map (card painter-coverage): r dry (savanna straw), g ash (burnt forest), b earth
// (badlands), roles 5, 6 and 7; absent for a map with none of those biomes.
uniform sampler2D zone2_map : hint_default_black, filter_linear, repeat_disable;
uniform bool zone2_present = false;
uniform sampler2D water_weights : hint_default_black, filter_linear, repeat_disable;
uniform bool water_present = false;
uniform vec2 layer_grid_origin = vec2(0.0);
uniform vec2 layer_grid_step = vec2(0.25);

// Contact occlusion (PainterOcclusion): the footprint field (r a pool under crowns, bushes, rocks and
// houses, g a seam at their feet), its origin and texel size, the pool's and seam's strength, the
// deeper shade's value (z) and soil share (w), its tint, and the tokens' feet discs (x, z, radius,
// foot y) with their strengths (x the seam's, y the pool's).
uniform sampler2D occ_map : hint_default_black, filter_linear, repeat_disable;
uniform bool occ_present = false;
uniform vec2 occ_origin = vec2(0.0);
uniform float occ_step = 0.5;
uniform vec4 occ_k = vec4(0.0, 0.0, 0.8, 0.3);
uniform vec4 occ_tint = vec4(0.9, 1.0, 0.96, 0.35);
uniform vec4 tok[32];
uniform int tok_n = 0;
uniform vec2 tok_k = vec2(0.0);
// The sun (tt-sim's foliage_sun global: the direction toward it and its weight): the seam at a foot
// leans to the side the shadow falls (card painter-tree-ground).
global uniform vec4 foliage_sun;
// How far below the shade colour the pool goes, and the seam's weight on sunlit ground (its full
// weight is in the shade).
const float SHADE_DEEP = 0.8;
const float SEAM_LIT = 0.6;
// Metres the seam's centre moves away from the sun.
const float SEAM_LEAN_M = 0.3;
// The N.L a steep face must reach before a cast shadow shades it (light()).
const float CLIFF_CAST_FACING = 0.3;

varying vec3 v_n;
varying float v_wy;
varying vec2 v_xz;
varying float f_glb_lod;
varying float f_pool;
varying float f_core;
varying float f_tok;
varying vec3 f_lit;
varying vec3 f_shd;
varying float f_edge;
varying vec3 f_n;
varying float f_cut;

// The village fields' soil and crop rows (PainterFields).
#include "res://painter/shaders/painter_field.gdshaderinc"

// The painted ground fire's scale on the classic char: the classic colours are linear albedo for a
// filmic tonemap, and the painted tonemap is linear at exposure 1.
const float BURN_LIFT = 4.5;
const vec3 BURN_STRAW = vec3(0.5, 0.38, 0.14);
const vec3 BURN_SHADE = vec3(0.62, 0.6, 0.68);
// The glow's three painted steps (of its brightest channel) and the colour's strength.
const vec3 BURN_STEPS = vec3(0.07, 0.3, 0.65);
const float BURN_GLOW = 1.7;

// The persistent fire at map point `xz`: the dried band, the scorch and the char laid on the role's
// lit and shade colours (the char in flat steps of its tone, its edge broken by a brush noise), and
// the glow's painted steps. One fetch where nothing burns, two where it does.
vec3 burn_ground(vec2 xz, vec3 p, float clock, inout vec3 lit, inout vec3 shd) {
	vec2 st = (xz - fire_sim_rect.xy) / fire_sim_rect.zw;
	float edge = 1.0 / float(textureSize(fire_sim_map, 0).x);
	st.x = clamp(st.x, edge, 1.0 - edge) * 0.5;
	vec4 terms = texture(fire_sim_map, st);
	if (terms.x + terms.y + terms.z <= 0.0) {
		return vec3(0.0);
	}
	float k = clamp(dot(lit, vec3(0.3, 0.59, 0.11)) / 0.25, 0.6, 1.2);
	lit = mix(lit, BURN_STRAW * k, terms.y);
	shd = mix(shd, BURN_STRAW * k * 0.45, terms.y);
	lit *= mix(vec3(1.0), vec3(0.55, 0.4, 0.28), terms.z);
	shd *= mix(vec3(1.0), vec3(0.55, 0.4, 0.28), terms.z);
	if (terms.x <= 0.0) {
		return vec3(0.0);
	}
	float burnt = smoothstep(0.4, 0.6, terms.x + (p_noise(p * 2.1 + 31.0) - 0.5) * 0.4);
	float tone = floor(terms.w * 6.0 + 0.5) / 6.0;
	vec3 char_lit = fire_char_of(tone) * BURN_LIFT;
	lit = mix(lit, char_lit, burnt);
	shd = mix(shd, char_lit * BURN_SHADE, burnt);
	vec4 glow = texture(fire_sim_map, st + vec2(0.5, 0.0));
	float breathe = 0.88 + 0.12 * sin(clock * FIRE_BREATHE + glow.w * 12.0);
	vec3 g = glow.rgb * glow.rgb * (FIRE_SIM_GLOW_MAX * breathe);
	float peak = max(g.r, max(g.g, g.b));
	float band = smoothstep(BURN_STEPS.x, BURN_STEPS.x + 0.05, peak) * 0.3
		+ smoothstep(BURN_STEPS.y, BURN_STEPS.y + 0.06, peak) * 0.35
		+ smoothstep(BURN_STEPS.z, BURN_STEPS.z + 0.08, peak) * 0.35;
	return g / max(peak, 0.001) * band * BURN_GLOW;
}

// The zone of a baked ground colour `c` (LINEAR): soft shares of the roles, so the shader's brush
// noise bites at their edges as it does on the authored zone map: r meadow (green, and snow or pale
// stone), g path (warm earth), b rock (grey), a shore (blue); a dark ground is none of them (the
// forest floor).
vec4 glb_classify(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = (mx - mn) / max(mx, 0.0001);
	float colored = smoothstep(0.08, 0.2, sat);
	float green = colored * smoothstep(0.85, 1.05, c.g / max(c.r, 0.0001)) * smoothstep(1.05, 1.3, c.g / max(c.b, 0.0001));
	float blue = colored * smoothstep(1.0, 1.25, c.b / max(c.g, 0.0001)) * step(c.r, c.b);
	float warm = colored * (1.0 - green) * (1.0 - blue) * smoothstep(0.1, 0.2, mx);
	float pale = (1.0 - colored) * smoothstep(0.5, 0.7, mx);
	float grey = (1.0 - colored) * (1.0 - smoothstep(0.5, 0.7, mx)) * smoothstep(0.03, 0.08, mx);
	return vec4(max(green, pale), warm, grey, blue);
}

// The zone map at a map-frame point (texel i's middle lies at origin + i * step).
vec4 zone(vec2 xz) {
	if (glb_zone) {
		return glb_classify(textureLod(glb_albedo, mat2(glb_uv.xy, glb_uv.zw) * xz + glb_uv_b, f_glb_lod).rgb * glb_tint);
	}
	if (!zone_present) {
		return vec4(base_meadow, 0.0, 0.0, 0.0);
	}
	vec2 size = vec2(textureSize(zone_map, 0));
	return textureLod(zone_map, ((xz - layer_grid_origin) / layer_grid_step + 0.5) / size, 0.0);
}

vec3 role_col(bool lit, int role, float variant) {
	float v = clamp(variant, 0.0, 1.0);
	return lit ? mix(g_lit[role * 2], g_lit[role * 2 + 1], v)
		: mix(g_shd[role * 2], g_shd[role * 2 + 1], v);
}

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

// Where pale drift marks (x) and fallen-leaf marks (y) lie: a few broad zones, 0 outside them.
vec2 small_zones(vec2 q) {
	return vec2(
		smoothstep(0.52, 0.78, p_noise(vec3(q.x * 0.06, 9.0, q.y * 0.1) + 50.0)),
		smoothstep(0.5, 0.72, p_noise(vec3(q.x * 0.12, 4.0, q.y * 0.16) + 60.0)));
}

// The path slot at map point `q` (PainterGroundPaths): the slot map's, or the map's one slot; -1
// for none (the path role's own tone).
int path_slot(vec2 q) {
	if (!path_map_present) {
		return path_only;
	}
	vec2 size = vec2(textureSize(path_map, 0));
	int s = int(textureLod(path_map, ((q - layer_grid_origin) / layer_grid_step + 0.5) / size, 0.0).r * 255.0 + 0.5);
	return s < 8 ? s : -1;
}

// The pattern of path kind `kind` at map point `q` for a pixel `px` metres wide: x the stone's own
// variant offset (about -0.5 to 0.5), y the seam (0 on a stone, 1 in the gap between), z the
// stone's hash (its edge against the grass). One flat colour a stone, as a mark is one: a cobble
// a rounded dab in courses, a flagstone a plate of a jittered cell grid (the nearest of nine
// centres; the seam where the second is nearly as near), a tile a square, a pebble a dot, a board
// a run along x. The courses and grids wander with a slow warp, so no line is ruled. A stone
// under three pixels fades to the flat block-in (no shimmer), its seam a little sooner.
vec3 path_pattern(int kind, vec2 q, float px) {
	vec3 p = vec3(q.x, 0.0, q.y);
	vec2 warp = (vec2(p_noise(p * 0.45 + 101.0), p_noise(p * 0.45 + 131.0)) - 0.5);
	float wob = p_noise(p * 7.0 + 17.0) - 0.5;
	float size = 0.4;
	vec3 r = vec3(0.0, 0.0, 0.5);
	if (kind == 1) {
		vec2 g = q / vec2(0.38, 0.34) + warp * 0.9;
		float row = floor(g.y);
		g.x += mod(row, 2.0) * 0.5 + p_hash(vec3(row, 5.0, 3.0)) * 0.3;
		vec2 c = floor(g);
		float h = p_hash(vec3(c.x, 21.0, c.y));
		// A round dab, a little squared (a rectangle read as brick courses).
		vec2 a = abs(fract(g) - 0.5) / (0.47 - 0.06 * fract(h * 7.1));
		float d = length(a) * 0.8 + max(a.x, a.y) * 0.2;
		r = vec3(h - 0.5, smoothstep(0.9, 1.06, d + wob * 0.22), h);
	} else if (kind == 2) {
		size = 0.95;
		vec2 g = q / size + warp * 0.6;
		vec2 c0 = floor(g);
		float f1 = 9.0;
		float f2 = 9.0;
		vec2 id = c0;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				vec2 c = c0 + vec2(float(dx), float(dy));
				vec2 o = vec2(p_hash(vec3(c.x, 41.0, c.y)), p_hash(vec3(c.x, 43.0, c.y)));
				float d = length(g - c - 0.5 - (o - 0.5) * 0.75);
				if (d < f1) {
					f2 = f1;
					f1 = d;
					id = c;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
		float h = p_hash(vec3(id.x, 47.0, id.y));
		r = vec3(h - 0.5, 1.0 - smoothstep(0.07, 0.15, f2 - f1 + wob * 0.06), h);
	} else if (kind == 3) {
		size = 0.7;
		vec2 g = q / size + warp * 0.25;
		vec2 c = floor(g);
		vec2 f = fract(g);
		float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		float h = p_hash(vec3(c.x, 51.0, c.y));
		r = vec3((h - 0.5) * 0.7, 1.0 - smoothstep(0.035, 0.075, e + wob * 0.025), h);
	} else if (kind == 4) {
		size = 0.2;
		vec2 g = q / size + warp * 0.4;
		vec2 c = floor(g);
		float h = p_hash(vec3(c.x, 61.0, c.y));
		vec2 o = vec2(fract(h * 13.1), fract(h * 29.7)) - 0.5;
		float d = length(fract(g) - 0.5 - o * 0.4);
		float dot_k = (1.0 - smoothstep(0.2, 0.3, d + wob * 0.1)) * step(0.35, h);
		r = vec3((fract(h * 7.3) > 0.45 ? 0.55 : -0.5) * dot_k, 0.0, 0.5 + (h - 0.5) * 0.3);
	} else if (kind == 5) {
		size = 0.3;
		float row = floor(q.y / size + warp.y * 0.2);
		float hr = p_hash(vec3(row, 71.0, 7.0));
		float len = 1.5 + fract(hr * 9.7) * 1.3;
		float u = (q.x + hr * 3.0) / len;
		float col = floor(u);
		float fy = fract(q.y / size + warp.y * 0.2) * size;
		float fx = fract(u) * len;
		float e = min(min(fy, size - fy), min(fx, len - fx) * 0.6);
		float h = p_hash(vec3(col, 73.0, row));
		r = vec3(h - 0.5, 1.0 - smoothstep(0.016, 0.032, e + wob * 0.008), h);
	}
	float cells = size / max(px, 0.0001);
	r.x *= smoothstep(1.5, 3.0, cells);
	r.y *= smoothstep(3.0, 6.0, cells);
	return r;
}

// The ground's lit and shade colour at `q`: for a block-in pixel (mk 0, h 0.5: flat shapes with
// firm wandering edges) or for one mark (mk 1 a stroke, 2 a small drift or litter mark; `h` its
// own hash, `vo` its offset to a neighbouring tone), asked once at the mark's middle. A path
// surface with a pattern (path_pattern) is drawn in the block-in only, each stone asked at the
// pixel; a stone's own hash moves the path's edge, so the edge is made of whole stones. On a
// cliff face (rock, steep) the tone steps in soft strata bands by the pixel's height `wy`, each
// band's top a step lighter (a ledge catching the light).
void ground_at(vec2 q, float slope, float h, float mk, float vo, float px, float wy, out vec3 lit, out vec3 shd) {
	vec3 p = vec3(q.x, 0.0, q.y);
	float j = (h - 0.5) * min(mk, 1.0);
	// A slow warp carries the meadow's edge against the forest floor; the path keeps its line.
	vec2 w = (vec2(p_noise(p * 0.35 + 21.0), p_noise(p * 0.35 + 47.0)) - 0.5) * 1.4;
	vec4 zb = zone(q + w);
	vec4 zp = zone(q + w * 0.15);
	float meadow = step(0.5, zb.r + (p_noise(p * 0.9 + 5.0) - 0.5) * 0.3 + j * 0.25);
	int pslot = -1;
	int kind = 0;
	vec3 pat = vec3(0.0, 0.0, 0.5);
	if (zp.g > 0.2) {
		pslot = path_slot(q);
		kind = pslot >= 0 ? p_kind[pslot] : 0;
		if (kind > 0 && mk < 0.5) {
			pat = path_pattern(kind, q, px);
		}
	}
	float pv = zp.g + (p_noise(p * 1.4 + 33.0) - 0.5) * 0.35 + j * 0.3 + (pat.z - 0.5) * 0.25;
	int role = meadow > 0.5 ? 0 : 1;
	if (zone2_present) {
		vec2 size2 = vec2(textureSize(zone2_map, 0));
		vec3 z2 = textureLod(zone2_map, ((q + w - layer_grid_origin) / layer_grid_step + 0.5) / size2, 0.0).rgb;
		z2 += (p_noise(p * 0.7 + 71.0) - 0.5) * 0.3 + j * 0.25;
		float top = max(z2.r, max(z2.g, z2.b));
		if (top > 0.5) {
			role = z2.r >= z2.g && z2.r >= z2.b ? 5 : (z2.g >= z2.b ? 6 : 7);
		}
	}
	if (zb.a + (p_noise(p * 0.8 + 61.0) - 0.5) * 0.3 > 0.5) {
		role = 4;
	}
	float scorch_rim = 0.0;
	if (char_present) {
		// Scorched ground over the meadow, the floor, the dry ground and the shore (a road through
		// it stays a road).
		vec2 csize = vec2(textureSize(char_map, 0));
		float cw = textureLod(char_map, ((q + w * 0.5 - layer_grid_origin) / layer_grid_step + 0.5) / csize, 0.0).r;
		// A brush edge: two scales of noise break the texel-straight border into dabs.
		float brushed = cw + (p_noise(p * 2.6 + 77.0) - 0.5) * 0.55 + (p_noise(p * 7.0 + 13.0) - 0.5) * 0.22;
		if (brushed > 0.5) {
			role = 8;
		} else {
			// The grass just outside the char is singed to a warm orange-brown (not a glow: the
			// fire is out), a few dabs wide.
			scorch_rim = smoothstep(0.28, 0.5, brushed);
		}
	}
	// The role a path lies on (its edge's snow dusting is the meadow's or the floor's).
	int under = role;
	if (pv > 0.46) {
		role = 2;
	}
	if (max(slope, zb.b - 0.2) + (p_noise(p * 0.8 + 9.0) - 0.5) * 0.12 > 0.3) {
		role = 3;
	}
	// Variation inside a zone: the role's own two variants by two slow noises. The block-in takes
	// five close steps of it; a mark takes it unstepped, a little off by its own hash.
	float n1 = p_noise(vec3(p.x * 0.05, 0.0, p.z * 0.075) + 3.0);
	float n2 = p_noise(vec3(p.x * 0.16, 1.7, p.z * 0.21) + 11.0);
	float pn = (n1 - 0.5) + (n2 - 0.5) * 0.4;
	if (mk < 0.5) {
		pn = floor(pn * 5.0 + 0.5) / 5.0;
	}
	float variant = 0.5 + pn * patches + vo;
	float vstep = 1.0;
	if (role == 2) {
		variant = mk > 0.5 ? fract(h * 5.77 + 0.3)
			: floor(p_noise(p * vec3(0.7, 1.0, 0.7) + 19.0) * 3.0) * 0.5;
		if (kind > 0) {
			// A stone takes its own step off the band's slow patches; the seam is a deeper shade.
			variant = clamp(0.5 + pn * patches * 0.5 + pat.x * 1.4, 0.0, 1.0);
			vstep = (1.0 + (fract(pat.z * 41.7) - 0.5) * 0.12 * step(0.001, abs(pat.x))) * (1.0 - pat.y * SEAM_DARK * (1.0 - path_dust * 0.5));
		}
	}
	if (role == 3 && cliff_strata > 0.0) {
		float face = smoothstep(0.3, 0.6, slope) * cliff_strata;
		float t = wy / STRATA_H + (p_noise(p * 0.5 + 15.0) - 0.5) * 0.9 + (p_noise(p * 2.2 + 25.0) - 0.5) * 0.15;
		float band = floor(t);
		float f = fract(t);
		// Each band's tone runs into the next over its upper half and the ledge's light and seam are
		// soft (painter-ground-fire-round3, owner: the seams between the face's strokes showed; they
		// were a sixth of a band wide).
		float bv = mix(p_hash(vec3(band, 81.0, 3.0)), p_hash(vec3(band + 1.0, 81.0, 3.0)), smoothstep(0.5, 1.0, f));
		variant = mix(variant, 0.5 + (bv - 0.5) * 0.75, face);
		vstep = mix(1.0, 1.0 + 0.05 * smoothstep(0.4, 0.9, f) - 0.035 * (1.0 - smoothstep(0.0, 0.35, f)), face);
	}
	if (role == 2 && pslot >= 0) {
		float v = clamp(variant, 0.0, 1.0);
		lit = mix(p_lit[pslot * 2], p_lit[pslot * 2 + 1], v);
		shd = mix(p_shd[pslot * 2], p_shd[pslot * 2 + 1], v);
	} else {
		lit = role_col(true, role, variant);
		shd = role_col(false, role, variant);
	}
	lit *= vstep;
	shd *= vstep;
	// A cliff face lit by the sun is still a middle value under its lit top (a pale sandstone face
	// at the lit colour read as a cream band on the badlands' orange, a step that did not read).
	if (role == 3) {
		lit = mix(lit, shd, smoothstep(0.3, 0.6, slope) * cliff_face);
	}
	// The meadow's broad gold and moss swathes (PainterMeadowSwathes): one slow field through the
	// meadow's warp, its highs gold and its lows moss. The block-in takes a swathe in three steps over
	// a wide rim and a mark takes it at its middle, so the edge is brushed, not a gradient; a swathe
	// takes at most sw_k.w of its tone, a gentle shift in the meadow rather than a patch on it
	// (painter-ground-fire-round4, owner twice: "too strong").
	if (role == 0 && sw_k.z > 0.0) {
		vec2 sq = (q + w * 1.5) * 0.045 + sw_seed.xy;
		float f = p_n2(sq, 7.0) * 0.72 + p_n2(sq * 2.6 + 3.1, 9.0) * 0.28 + j * 0.06;
		float gold = smoothstep(sw_k.x + sw_seed.z, sw_k.x + sw_seed.z + 0.1, f);
		float moss = 1.0 - smoothstep(sw_k.y - sw_seed.w - 0.1, sw_k.y - sw_seed.w, f);
		if (mk < 0.5) {
			gold = floor(gold * 3.0 + 0.5) / 3.0;
			moss = floor(moss * 3.0 + 0.5) / 3.0;
		}
		gold *= sw_k.w;
		moss *= sw_k.w;
		float v = clamp(variant, 0.0, 1.0);
		lit = mix(mix(lit, mix(sw_lit[0], sw_lit[1], v), gold), mix(sw_lit[2], sw_lit[3], v), moss);
		shd = mix(mix(shd, mix(sw_shd[0], sw_shd[1], v), gold), mix(sw_shd[2], sw_shd[3], v), moss);
	}
	// Under snow a path's edge beside the snowy meadow or floor is dusted white, in two steps (a
	// stone's hash moves the line, so it follows the stones).
	if (role == 2 && path_dust > 0.0 && under <= 1) {
		float e = (pv - 0.46 + (pat.z - 0.5) * 0.1) / (0.25 * path_dust);
		float dust = floor((1.0 - smoothstep(0.35, 1.0, e)) * 2.0 + 0.5) * 0.42;
		lit = mix(lit, role_col(true, under, variant), dust);
		shd = mix(shd, role_col(false, under, variant), dust);
	}
	lit = mix(lit, lit * vec3(1.45, 0.78, 0.4), scorch_rim * 0.65);
	shd = mix(shd, shd * vec3(1.35, 0.8, 0.5), scorch_rim * 0.65);
	// A village field's soil and rows over the role (not a cliff face, not a fire's scar).
	if (field_present && role != 3 && role != 8) {
		field_paint(q, px, mk, h, role_col(true, 0, 0.5), role_col(false, 0, 0.5), lit, shd);
	}
	// The wet band beside the water (card painter-water): the dressing's wet line (water_weights.a,
	// 1 under the water and falling to 0 over 0.8 m above it) darkens and cools the ground in a band
	// with a brush edge: its threshold wanders with a noise, and a mark takes it whole at its middle,
	// so the edge is made of strokes. Not a gradient: one darker step, as the shade colour is.
	if (water_present) {
		vec2 size = vec2(textureSize(water_weights, 0));
		vec2 muv = ((q - layer_grid_origin) / layer_grid_step + 0.5) / size;
		float wet = textureLod(water_weights, muv, 0.0).a;
		float band = smoothstep(WET_EDGE - 0.07, WET_EDGE + 0.07, wet + (p_noise(p * 1.7 + 83.0) - 0.5) * 0.4 + (h - 0.5) * 0.12 * min(mk, 1.0));
		lit = mix(lit, lit * WET_TINT, band);
		shd = mix(shd, shd * WET_TINT, band);
	}
	// A mark's own small step in value.
	float vk = 1.0 + (fract(h * 41.7 + 0.3) - 0.5) * 0.1 * min(mk, 1.0);
	lit *= vk;
	shd *= vk;
	// What lies on the ground takes the ground's shade: as much darker, half way to its colour.
	float lr = lum(shd) / max(lum(lit), 0.001);
	if (mk > 1.5) {
		if (role == 1) {
			vec3 c = litter_col * (0.92 + 0.16 * fract(h * 31.3));
			shd = mix(c * lr, shd, 0.5);
			lit = c;
		}
		if (role == 0) {
			vec3 c = drift_col * (0.9 + 0.2 * fract(h * 31.3));
			shd = mix(c * lr, shd, 0.5);
			lit = c;
		}
	}
}

void vertex() {
	v_n = world_frame ? normalize(mat3(MODEL_MATRIX) * NORMAL) : NORMAL;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wy = wp.y;
	v_xz = wp.xz;
}

// The contact occlusion at `xz`: x the pool, y the seam, each a flat brush-edged shape (the field's
// 0.5 contour, moved by the ground's own noise), then the tokens' feet: a wider pool joins x, and z
// is the disc right under the feet (a deeper step on top of the seam). light() shows the pool only
// inside the shade.
vec3 contact_at(vec3 p, vec2 xz) {
	vec3 occ = vec3(0.0);
	if (occ_present && (occ_k.x > 0.0 || occ_k.y > 0.0)) {
		// The field is read SEAM_LEAN_M toward the sun, so its shapes sit that far down-sun: more of
		// a seam on the side the shadow falls, a thin edge on the sunlit side (one fetch, as before).
		float sl = length(foliage_sun.xz);
		vec2 to_sun = sl > 0.01 ? foliage_sun.xz / sl : vec2(0.0);
		vec2 size = vec2(textureSize(occ_map, 0)) * occ_step;
		vec2 s = textureLod(occ_map, (xz + to_sun * SEAM_LEAN_M - occ_origin) / size, 0.0).rg;
		vec2 w = vec2(p_noise(p * 1.3 + 80.0), p_noise(p * 2.7 + 95.0)) - 0.5;
		occ.xy = vec2(
			smoothstep(0.4, 0.5, s.r + w.x * 0.3) * occ_k.x,
			smoothstep(0.4, 0.5, s.g + w.y * 0.3) * occ_k.y);
	}
	for (int i = 0; i < tok_n; i++) {
		vec4 t = tok[i];
		float on_foot = 1.0 - smoothstep(0.35, 0.9, abs(v_wy - t.w));
		float d = length(xz - t.xy) / max(t.z, 0.05);
		float wob = (p_noise(p * 3.1 + 40.0) - 0.5) * 0.25;
		occ.z = max(occ.z, (1.0 - smoothstep(0.7, 0.95, d + wob)) * on_foot * tok_k.x);
		occ.x = max(occ.x, (1.0 - smoothstep(1.0, 1.35, d + wob)) * on_foot * tok_k.y);
	}
	return occ;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec2 xz = world_frame ? v_xz : UV;
	vec3 p = vec3(xz.x, 0.0, xz.y);
	if (glb_zone) {
		// The mip level of the baked albedo that one pixel covers.
		f_glb_lod = clamp(log2(max(length(fwidth(xz)) * glb_texels_per_m, 1.0)), 0.0, 6.0);
	}
	vec3 n = normalize(v_n);
	f_n = n;
	float slope = 1.0 - n.y;
	float out_k = 0.0;
	float calm = 1.0;
	if (skirt) {
		float out_m = length(max(abs(xz) - half_extent, vec2(0.0)));
		out_k = smoothstep(2.0, 26.0, out_m + (p_noise(p * 0.2) - 0.5) * 6.0);
		// The outer ground is calmer: fewer marks the farther out.
		calm = 1.0 - 0.7 * smoothstep(0.0, 12.0, out_m);
	}
	// The top mark that covers this pixel, in the strokes' own frame (x along, y across).
	vec2 e1 = normalize(stroke_dir + vec2(0.0001, 0.0));
	vec2 e2 = vec2(-e1.y, e1.x);
	vec2 st = vec2(dot(xz, e1), dot(xz, e2));
	float px_m = length(fwidth(xz)) * 0.7;
	vec2 sz = small_zones(xz) * vec2(drift * 0.8, litter * 0.6);
	float path_here = zone(xz).g;
	float best = 0.0;
	vec2 a_k = xz;
	float h_k = 0.5;
	float l_k = 0.0;
	// No marks on a steep face: laid in the map's XZ they stretch down it as smears (the face is
	// the block-in's strata).
	// Nor inside a village field: its rows are its strokes.
	bool search = brushes_present && marks > 0.0 && px_m <= mark_px.y && slope < 0.4 && !field_inner(xz);
	for (int layer = 0; layer < 3 && search; layer++) {
		// The small marks exist only in a drift or litter zone, and not when they are a pixel or two.
		if (layer == 2 && (max(sz.x, sz.y) <= 0.0 || px_m > mark_px.x)) {
			break;
		}
		vec2 cell = layer == 2 ? vec2(1.1, 0.5) : vec2(1.3, 0.55);
		float seed = float(layer) * 40.0;
		float shift = float(layer) * 0.5;
		vec2 c0 = floor(st / cell + shift);
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				vec2 c = c0 + vec2(float(dx), float(dy));
				float h = p_hash(vec3(c.x, 3.0 + seed, c.y));
				float h2 = p_hash(vec3(c.x, 7.0 + seed, c.y));
				float h3 = p_hash(vec3(c.x, 11.0 + seed, c.y));
				// Each mark goes at its own footprint limit: the marks thin out with distance.
				if (px_m > mix(mark_px.x, mark_px.y, fract(h * 3.9 + 0.2))) {
					continue;
				}
				vec2 a_st = (c + 0.5 - shift + (vec2(h2, h3) - 0.5) * 0.7) * cell;
				vec2 a = a_st.x * e1 + a_st.y * e2;
				vec4 za = zone(a);
				bool on_path = za.g > 0.5;
				// A path mark lies over its green neighbours, and the small marks over both.
				float pr = (layer == 2 ? 2.0 : (on_path ? 1.0 : 0.0)) + 0.01 + fract(h * 3.17) * 0.98;
				if (pr < best) {
					continue;
				}
				// No green mark reaches the middle of the path: the band stays whole, its edge brushed.
				if (!on_path && path_here > 0.72) {
					continue;
				}
				// Half the mark's length and width in metres (a path mark is shorter: the band is
				// narrow); the brush fills about two thirds of its square.
				vec2 half_m = layer == 2
					? vec2(0.3, 0.13) * mix(0.5, 1.0, fract(h * 7.3))
					: mix(vec2(0.5, 0.24), vec2(0.8, 0.36), vec2(fract(h * 7.3), fract(h * 13.9)))
						* (on_path ? vec2(0.7, 0.9) : vec2(1.0));
				vec2 quad = half_m / vec2(0.66, 0.7);
				// One hand: every mark lies about one way, each a little off it.
				float ang = (h2 - 0.5) * 0.4;
				vec2 dv = st - a_st;
				dv = vec2(dv.x * cos(ang) + dv.y * sin(ang), -dv.x * sin(ang) + dv.y * cos(ang));
				vec2 uv = dv / quad;
				if (abs(uv.x) > 1.0) {
					continue;
				}
				// The brush shape drawn in to a point at both ends: a lens with the brush's own edge.
				uv.y /= max(1.0 - uv.x * uv.x * 1.5, 0.08);
				if (abs(uv.y) > 1.0) {
					continue;
				}
				uv *= vec2(h3 > 0.5 ? 1.0 : -1.0, fract(h * 5.3) > 0.5 ? 1.0 : -1.0);
				float lod = clamp(log2(px_m * 64.0 / quad.y) - 0.5, 0.0, 5.0);
				float bh = fract(h * 29.3);
				float bl = (layer == 2 || bh < 0.4) ? 0.0 : (bh < 0.8 ? 1.0 : 2.0);
				if (textureLod(brushes, vec3(uv * 0.5 + 0.5, bl), lod).r < 0.5) {
					continue;
				}
				bool keep;
				if (layer == 2) {
					keep = za.g < 0.25 && fract(h * 13.7 + 0.41) < (za.r > 0.5 ? sz.x : sz.y) * calm;
				} else {
					// A mark at a zone's edge always stays; inside a flat area some go.
					bool edge = (za.g > 0.1 && za.g < 0.9) || (za.r > 0.2 && za.r < 0.8);
					keep = fract(h * 17.77 + 0.21) < marks * (edge ? 1.0 : 1.0 - mark_thin) * calm;
				}
				if (keep) {
					best = pr;
					a_k = a;
					h_k = fract(h * 23.17 + 0.4);
					l_k = layer == 2 ? 2.0 : 1.0;
				}
			}
		}
	}
	// A path mark over a patterned path surface goes: its stones are the block-in's.
	if (best > 1.0 && best < 2.0) {
		int s = path_slot(a_k);
		if (s >= 0 && p_kind[s] > 0) {
			best = 0.0;
		}
	}
	vec3 lit;
	vec3 shd;
	if (best > 0.0) {
		ground_at(a_k, slope, h_k, l_k, (fract(h_k * 9.1) - 0.5) * 0.5, px_m, v_wy, lit, shd);
	} else {
		ground_at(xz, slope, 0.5, 0.0, 0.0, px_m, v_wy, lit, shd);
	}
	// A cliff's top edge (the ground convex, toward a steep drop) takes a lit lip, its foot
	// (concave) a darker one: the mean curvature from the screen derivatives of the normal and
	// the position, about 2 per metre at a terrace's rim, under 0.3 on rolling ground. Only where a
	// steep face is near (the slope, or the slope half a metre on by its own gradient): a shallow
	// crease on a tier's top (two strokes' caps meeting at a notch) bends the normal as fast but
	// barely tilts it, and drew a thin light line there. The lip is a little gold (`cliff_warm`)
	// and under snow takes the meadow's snow as a cap; the foot goes part way to its shade colour.
	if (cliff_edge > 0.0 && !skirt) {
		vec3 wpos = vec3(v_xz.x, v_wy, v_xz.y);
		vec3 dpx = dFdx(wpos);
		vec3 dpy = dFdy(wpos);
		float curv = (dot(dFdx(n), dpx) + dot(dFdy(n), dpy)) / max(dot(dpx, dpx) + dot(dpy, dpy), 1e-6);
		float slope_grad = (abs(dFdx(slope)) + abs(dFdy(slope))) / max(length(dpx) + length(dpy), 1e-4);
		float near = smoothstep(0.12, 0.3, slope + slope_grad * 0.5);
		float brush = (p_noise(p * 3.1 + 57.0) - 0.5) * 0.6;
		// The curvature is one value a terrain triangle (the derivative of an interpolated normal), so
		// a band cut on it alone had a hard, triangle-stepped inner edge, a seam between the lip and
		// the top (painter-ground-fire-round3). It only says which side is convex; the band's own
		// edges are feathered on the slope, which runs smoothly over the rim, wobbled by a slow brush.
		float wob = (p_noise(p * 1.3 + 91.0) - 0.5) * 0.08;
		float rim = smoothstep(0.02, 0.2, slope + wob);
		float lip = smoothstep(0.3, 0.8, curv + brush) * rim * (1.0 - smoothstep(0.42, 0.72, slope + wob)) * near;
		float foot = smoothstep(0.3, 0.8, -curv + brush) * rim * near;
		vec3 warm = vec3(1.0 + cliff_warm * 0.5, 1.0, 1.0 - cliff_warm * 0.5);
		lit *= 1.0 + cliff_edge * lip * warm;
		shd *= 1.0 + cliff_edge * 0.5 * lip * warm;
		lit = mix(lit, shd, foot * cliff_foot);
		shd *= 1.0 - foot * cliff_foot * 0.3;
		if (cliff_snow > 0.0) {
			float cap = smoothstep(0.35, 0.65, curv + brush) * (1.0 - smoothstep(0.5, 0.8, slope)) * near;
			cap = floor(cap * 2.0 + 0.5) * 0.5 * cliff_snow;
			float sv = p_noise(p * 0.6 + 41.0);
			lit = mix(lit, role_col(true, 0, sv), cap);
			shd = mix(shd, role_col(false, 0, sv), cap);
		}
	}
	if (skirt) {
		lit = mix(lit, foot_col, out_k);
		shd = mix(shd, foot_col, out_k);
	}
	vec3 glow_em = vec3(0.0);
	if (fire_present != 0 && !skirt) {
		glow_em = burn_ground(xz, p, TIME, lit, shd);
	}
	EMISSION = glow_em;
	f_lit = lit;
	f_shd = shd;
	f_cut =cut_amp > 0.0 ? be_cut(st) * cut_amp : 0.0;
	f_edge = p_noise(p * 0.55 + 71.0);
	vec3 contact = contact_at(p, xz);
	f_pool = contact.x;
	f_core = contact.y;
	f_tok = contact.z;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		// One flat shade colour behind a firm edge: the step sits in the middle of the penumbra.
		float cast = 1.0 - smoothstep(0.44 + f_cut, 0.56 + f_cut, ATTENUATION);
		// Ground turned from the sun takes its shade too (a steep bank's far side). The step and
		// its wiggle shrink with the sun's height under TURN_SUN_FULL (painter-a2a4): at a 3 degree
		// sun flat ground's N.L (0.05) sat inside them, and the wiggle alone striped a level
		// meadow lit and shade; now only a bank turned past the grazing sun goes into shade.
		float turn_k = clamp(lw.y / TURN_SUN_FULL, 0.05, 1.0);
		float nl = dot(normalize(f_n), lw);
		float turned = 1.0 - smoothstep(0.02 * turn_k, 0.1 * turn_k, nl + (f_edge - 0.5) * 0.1 * turn_k);
		// A steep face turned nearly edge-on to the sun is where the shadow map self-shadows in
		// stripes and its filter's noise stipples their edges (card painter-ground-artifacts: fine
		// horizontal hatching on the banks): such a face takes no cast shadow until it faces the sun
		// (its N.L already steps it into shade above), and flat ground keeps every cast shadow.
		cast *= 1.0 - smoothstep(0.2, 0.5, 1.0 - f_n.y) * (1.0 - smoothstep(0.0, CLIFF_CAST_FACING, nl));
		float shade = max(cast, turned);
		vec3 col = mix(f_lit, f_shd, shade);
		// Contact occlusion (card painter-tree-ground): what stands on the ground shuts out the sky,
		// not the sun, so the pool is a step below the shade colour (a little cooler) and only where
		// the ground is already in shade: each shadow is darkest at its root, and the sunlit ground
		// beside a trunk stays lit (a pool there read as a second light). The seam at a foot leans
		// toward the soil, full in the shade and lighter in the sun; a token's feet stand on a deeper
		// disc still (f_tok).
		if (f_pool > 0.0 || f_core > 0.0 || f_tok > 0.0) {
			float lr = lum(f_shd) / max(lum(f_lit), 0.001);
			vec3 deep = mix(f_lit, f_shd, occ_tint.a) * occ_k.z * occ_tint.rgb;
			vec3 deeper = f_shd * occ_k.z * SHADE_DEEP * occ_tint.rgb;
			vec3 soil = mix(deep, litter_col * lr * occ_k.z, occ_k.w);
			vec3 soil_shd = mix(deeper, litter_col * lr * occ_k.z * SHADE_DEEP, occ_k.w * 0.6);
			col = mix(col, deeper, f_pool * shade);
			col = mix(col, mix(soil, soil_shd, shade), f_core * mix(SEAM_LIT, 1.0, shade));
			col *= mix(vec3(1.0), vec3(0.74, 0.84, 0.8), f_tok);
		}
		DIFFUSE_LIGHT += col;
	}
}
