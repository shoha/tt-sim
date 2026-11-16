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

// Per role two variants (cool dark, warm light) of the lit and the shade colour, LINEAR.
uniform vec3 g_lit[10];
uniform vec3 g_shd[10];
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
uniform sampler2D water_weights : hint_default_black, filter_linear, repeat_disable;
uniform bool water_present = false;
uniform vec2 layer_grid_origin = vec2(0.0);
uniform vec2 layer_grid_step = vec2(0.25);

varying vec3 v_n;
varying vec3 f_lit;
varying vec3 f_shd;
varying float f_edge;
varying vec3 f_n;
varying float f_cut;

// The zone map at a map-frame point (texel i's middle lies at origin + i * step).
vec4 zone(vec2 xz) {
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

// The ground's lit and shade colour at `q`: for a block-in pixel (mk 0, h 0.5: flat shapes with
// firm wandering edges) or for one mark (mk 1 a stroke, 2 a small drift or litter mark; `h` its
// own hash, `vo` its offset to a neighbouring tone), asked once at the mark's middle.
void ground_at(vec2 q, float slope, float h, float mk, float vo, out vec3 lit, out vec3 shd) {
	vec3 p = vec3(q.x, 0.0, q.y);
	float j = (h - 0.5) * min(mk, 1.0);
	// A slow warp carries the meadow's edge against the forest floor; the path keeps its line.
	vec2 w = (vec2(p_noise(p * 0.35 + 21.0), p_noise(p * 0.35 + 47.0)) - 0.5) * 1.4;
	vec4 zb = zone(q + w);
	vec4 zp = zone(q + w * 0.15);
	float meadow = step(0.5, zb.r + (p_noise(p * 0.9 + 5.0) - 0.5) * 0.3 + j * 0.25);
	float pv = zp.g + (p_noise(p * 1.4 + 33.0) - 0.5) * 0.35 + j * 0.3;
	int role = meadow > 0.5 ? 0 : 1;
	if (zb.a + (p_noise(p * 0.8 + 61.0) - 0.5) * 0.3 > 0.5) {
		role = 4;
	}
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
	if (role == 2) {
		variant = mk > 0.5 ? fract(h * 5.77 + 0.3)
			: floor(p_noise(p * vec3(0.7, 1.0, 0.7) + 19.0) * 3.0) * 0.5;
	}
	lit = role_col(true, role, variant);
	shd = role_col(false, role, variant);
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
	v_n = NORMAL;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec2 xz = UV;
	vec3 p = vec3(xz.x, 0.0, xz.y);
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
	float px_m = length(fwidth(UV)) * 0.7;
	vec2 sz = small_zones(xz) * vec2(drift * 0.8, litter * 0.6);
	float path_here = zone(xz).g;
	float best = 0.0;
	vec2 a_k = xz;
	float h_k = 0.5;
	float l_k = 0.0;
	bool search = brushes_present && marks > 0.0 && px_m <= mark_px.y;
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
	vec3 lit;
	vec3 shd;
	if (best > 0.0) {
		ground_at(a_k, slope, h_k, l_k, (fract(h_k * 9.1) - 0.5) * 0.5, lit, shd);
	} else {
		ground_at(xz, slope, 0.5, 0.0, 0.0, lit, shd);
	}
	if (skirt) {
		lit = mix(lit, foot_col, out_k);
		shd = mix(shd, foot_col, out_k);
	}
	f_lit = lit;
	f_shd = shd;
	f_cut = cut_amp > 0.0 ? be_cut(st) * cut_amp : 0.0;
	f_edge = p_noise(p * 0.55 + 71.0);
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
		float turned = 1.0 - smoothstep(0.02 * turn_k, 0.1 * turn_k, dot(normalize(f_n), lw) + (f_edge - 0.5) * 0.1 * turn_k);
		DIFFUSE_LIGHT += mix(f_lit, f_shd, max(cast, turned));
	}
}
