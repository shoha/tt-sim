// The painted trees' shared code (painter_tree_stroke.gdshader, painter_tree_blockin.gdshader;
// docs/systems/painter.md "Trees"): the painter spike's round 4 common and its rounds 15 to 19
// additions, ported from the spike's final composed code (branch painterspike, the dump in
// docs/plans/handoffs/painter-a2a). The rounds' own notes are kept below. What tt-sim changed:
// the wind is tt-sim's global wind (wind_dir, wind_phase, wind_gust, as every plant reads it:
// gust() is WindModel's gust field, the clock is TIME, the amplitude follows the wind's sway
// scale and the player's motion scale); the eye view's level shift, the far-glide haze shift and
// the spike's untone of tt-sim's filmic curve are gone (the Painted look's tonemap is linear at
// exposure 1, so the palette reaches the screen as written); the canopy fades are
// tt-sim's (tree_fades below).
//
// Round 4: shared by the block-in and the stroke shader (pasted in place of //#COMMON).
// Round 3's common, with the palette and the stroke manner indexed by STYLE ROW instead of
// role: the row map says which row an instance's role uses, so a sheet edit at any scope
// (this one, every oak, every broadleaf) is a texture update, never a repaint.
uniform sampler2D palette : source_color, filter_linear, repeat_disable;
// One column per style row, three rows: (size, aspect, brush, density), (align, lift, jitter,
// size variation), (patch mix, patch frequency, deposit weight, block-in shown).
uniform sampler2D role_params : filter_nearest, repeat_disable;
// One line per instance (INSTANCE_CUSTOM.z): columns 0..8 the style row of each role, columns
// 9..16 the form occluders near the instance (indices into occ_tex, -1 ends the list).
uniform sampler2D row_map : filter_nearest, repeat_disable;
// Form occluders, one column each: row 0 (centre xyz, kind: 0 leaf crown, 1 solid ellipsoid,
// 2 box), row 1 (radii or half extents xyz, box yaw).
uniform sampler2D occ_tex : filter_nearest, repeat_disable;
uniform float row_count = 64.0;
uniform float variant_count = 4.0;
uniform float dep_row = 0.0;
// The direction the sunlight travels: tt-sim's foliage_sun global (FoliageLight.publish_sun, the
// unit direction toward the level's sun, published on every sun change), negated.
global uniform vec4 foliage_sun;
#define sun_dir (-foliage_sun.xyz)
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float calm = 0.0;
uniform float crown_occ = 1.0;
uniform float deposit = 0.0;
// tt-sim's wind (autoloads/wind.gd, docs/systems/wind.md; wind_foliage_include.gdshaderinc says
// what each holds): xy of wind_dir the direction, w its sway scale; wind_phase the three front
// phases; wind_gust x the gust amplitude, y the ripple, z the seed's phase, w the motion scale.
global uniform vec4 wind_dir;
global uniform vec4 wind_phase;
global uniform vec4 wind_gust;
// The trees' sway at calm (the spike's wind_amp, 0.16), times the wind's sway scale and the
// player's motion scale (0 holds every tree still).
uniform float wind_strength = 0.16;
#define wind_amp (wind_strength * wind_gust.w * wind_dir.w)
// The tone step of the sun's cast shadow on a tree (light()): how far into the cool shade a
// shadowed fragment goes, the shade's tint, and the step's wiggle (the sheet's `cut`) inside the
// engine's filter penumbra; the shadow lookup itself never moves.
uniform float cast_amount = 0.7;
uniform vec3 cast_tint = vec3(0.6, 0.64, 0.86);
uniform float cut_amp = 0.1;
// The canopy fade (CanopyFade, wind_foliage_include.gdshaderinc's apply_canopy_fade): the same
// globals and law, keyed by a whole stroke or a whole mass so crowns open in bold pieces.
global uniform vec4 canopy_fade_centre;
global uniform vec4 canopy_fade_view;
global uniform vec4 canopy_fade_shape;
global uniform vec4 canopy_brush;
global uniform vec4 canopy_cut;
#include "res://shaders/screen_dither_include.gdshaderinc"
// 1 = flat faces get broad strokes in the neighbouring tone and edge accents (round 4);
// 0 = round 3's cut-paper faces, for the before and after.
uniform float flat_fix = 1.0;

const float ROLE_GROUND = 6.0;

float p_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float p_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(p_hash(i), p_hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(p_hash(i + vec3(0.0, 1.0, 0.0)), p_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(p_hash(i + vec3(0.0, 0.0, 1.0)), p_hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(p_hash(i + vec3(0.0, 1.0, 1.0)), p_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float row_of(float role, int inst) {
	return texelFetch(row_map, ivec2(int(role + 0.5), inst), 0).r;
}

// tt-sim (painter-winter-trees): a bare season. The leaf row's row 6 w is the share of a tree's
// leaf clumps it drops (PainterTreeTones: (1 - the sheet's leaf-keep) times the species' fall; 0 in
// leaf). A clump falls whole, by its own mass seed, so its block-in mass, its strokes and its
// ground shadow go together and the limbs and twigs show between the clumps that stay.
// The share of a kept clump's strokes a bare tree draws (its block-in mass is not drawn).
const float TREE_DRY_STROKES = 0.45;
// How far a bare tree's kept clump is drawn in toward its middle (1 = its whole surface: a hollow
// ring; 0.55: a round knot, a seed ball).
const float TREE_DRY_SHRINK = 0.75;

// Only the bare variants (TREE_BARE: painter_tree_stroke_bare.gdshader, painter_tree_blockin_bare)
// read the drop; a tree in leaf draws with the plain ones, which have none of this code (card
// painter-winter-trees2: in every season it cost the eye view 0.23 ms in summer).
#ifdef TREE_BARE
// 1 while the sheet's leaf-keep is under 1 (PainterTrees.retone): only then is the leaf row's drop
// read (two texel reads a vertex in leaf cost the eye view about 0.2 ms, measured).
uniform float leaf_fall = 0.0;

float tree_leaf_drop(int inst) {
	if (leaf_fall < 0.5) {
		return 0.0;
	}
	return texelFetch(role_params, ivec2(int(row_of(0.0, inst) + 0.5), 6), 0).w;
}

bool tree_leaf_fallen(float mass_seed, float drop) {
	if (drop <= 0.0) {
		return false;
	}
	uint h = uint(mass_seed + 0.5) * 2654435769u + 40503u;
	h ^= h >> 15u;
	h *= 2246822519u;
	h ^= h >> 13u;
	return float(h >> 8u) / 16777216.0 < drop;
}
#endif

float tone3(float ndl, float jit, float soft) {
	float x = ndl + jit;
	float a = smoothstep(tone_lo - soft, tone_lo + soft, x);
	float b = smoothstep(tone_hi - soft, tone_hi + soft, x);
	return 0.1 + 0.4 * a + 0.4 * b;
}

vec3 palette_at(float tone, float row, float variant) {
	float rows = row_count * variant_count;
	float y = (floor(row + 0.5) * variant_count + 0.5 + clamp(variant, 0.0, 1.0) * (variant_count - 1.0)) / rows;
	return textureLod(palette, vec2(clamp(tone, 0.02, 0.98), y), 0.0).rgb;
}

float dep_threshold(vec3 p, float rnd) {
	return 0.2 + 0.75 * mix(p_noise(p * 1.3 + 3.0), rnd, 0.2);
}

vec3 oct_decode(vec2 e) {
	vec3 v = vec3(e, 1.0 - abs(e.x) - abs(e.y));
	float t = max(-v.z, 0.0);
	v.x += v.x >= 0.0 ? -t : t;
	v.y += v.y >= 0.0 ? -t : t;
	return normalize(v);
}

vec2 unpack2(float q) {
	float y = floor(q / 1024.0);
	float x = q - y * 1024.0;
	return vec2(x, y) / 1023.0 * 2.0 - 1.0;
}

// 1 when the ray from `o` toward the sun (`d`, unit) meets one of the FORMS listed for this
// instance (its eight nearest: whole crowns, rock piles, buildings). Constant cost per pixel
// whatever the world holds. A point inside or on a form is not shaded by it.
float form_occ(vec3 o, vec3 d, int inst) {
	for (int k = 0; k < 8; k++) {
		float fi = texelFetch(row_map, ivec2(9 + k, inst), 0).r;
		if (fi < -0.5) {
			break;
		}
		int i = int(fi + 0.5);
		vec4 a = texelFetch(occ_tex, ivec2(i, 0), 0);
		vec4 b = texelFetch(occ_tex, ivec2(i, 1), 0);
		vec3 v = o - a.xyz;
		if (a.w < 1.5) {
			if (a.w < 0.5 && crown_occ < 0.5) {
				continue;
			}
			vec3 lo = v / b.xyz;
			float c = dot(lo, lo) - 1.0;
			if (c < 0.3) {
				continue;
			}
			vec3 ld = d / b.xyz;
			float aa = dot(ld, ld);
			float bb = dot(lo, ld);
			if (bb < 0.0 && bb * bb - aa * c > 0.0) {
				return 1.0;
			}
		} else {
			float cs = cos(b.w);
			float sn = sin(b.w);
			vec3 lo = vec3(cs * v.x - sn * v.z, v.y, sn * v.x + cs * v.z);
			vec3 q = abs(lo) - b.xyz;
			if (max(q.x, max(q.y, q.z)) < 0.3) {
				continue;
			}
			vec3 ld = vec3(cs * d.x - sn * d.z, d.y, sn * d.x + cs * d.z);
			vec3 inv = 1.0 / (ld + vec3(0.00001));
			vec3 t1 = (-b.xyz - lo) * inv;
			vec3 t2 = (b.xyz - lo) * inv;
			vec3 tmn = min(t1, t2);
			vec3 tmx = max(t1, t2);
			float tn = max(tmn.x, max(tmn.y, tmn.z));
			float tf = min(tmx.x, min(tmx.y, tmx.z));
			if (tf > max(tn, 0.0)) {
				return 1.0;
			}
		}
	}
	return 0.0;
}

// painter-look-eyebush: a bush another form shades is not one flat dark tone. Its shade keeps a
// value structure in broad lobes (BUSH_CAST_F per metre, the block-in's wobble and each stroke's
// own draw): the tops of the mound turn sky-lit mid teal, the sides break between deep and mid
// teal, the underside stays the deepest. `q` is a 0..1 noise (lobe), `n_y` the surface's up.
const float BUSH_CAST_F = 1.8;

float bush_cast_tone(float q, float n_y) {
	float w = q + 0.45 * (n_y - 0.15);
	return 0.1 + 0.2 * step(0.5, w) + 0.2 * step(0.68, w);
}

// ---- wind (round 3's sway; the gust is tt-sim's).
// The gust at xz in 0.15 .. 1: WindModel.gust_at's field (wind_foliage_include's
// wind_gust_field, term for term), so a front moves through the trees and the plants together.
float gust(vec2 xz) {
	vec2 dir = wind_dir.xy;
	float along = dot(xz, dir);
	float across = dot(xz, vec2(-dir.y, dir.x));
	float sp = wind_gust.z;
	float wave = 0.55 * sin(along * 6.2831853 / 12.0 - wind_phase.x + sp)
		+ 0.45 * sin(along * 6.2831853 / 19.0 + across * 0.25 - wind_phase.y + 1.7 + sp * 1.618);
	wave += wind_gust.y * 0.3 * sin(along * 6.2831853 / 7.0 + across * 0.35 - wind_phase.z + 0.6 + sp * 2.414);
	return 0.15 + 0.85 * smoothstep(-0.2, 0.9, wave);
}

vec3 tree_flex(vec3 wp, vec3 base, float flex) {
	float h = max(wp.y - base.y, 0.0) / 7.0;
	float g = gust(base.xz);
	float s = sin(TIME * 1.9 + base.x * 0.7 + base.z * 0.4);
	vec3 wd3 = vec3(wind_dir.x, 0.0, wind_dir.y);
	vec3 side = vec3(-wind_dir.y, 0.0, wind_dir.x);
	return (wd3 * (g * 1.1 + 0.15 * s) + side * 0.12 * s) * h * h * wind_amp * 1.6 * flex;
}

vec3 mass_sway(float phase, float weight) {
	float a = TIME * 1.7 + phase * 6.2832;
	return vec3(sin(a) + 0.35 * sin(a * 2.3 + 1.0), 0.18 * sin(a * 1.3 + 2.0), 0.6 * cos(a * 0.8)) * wind_amp * weight * 0.22;
}

vec3 edge_push(vec3 anchor, float wgt) {
	return vec3(wind_dir.x, -0.15, wind_dir.y) * gust(anchor.xz) * wind_amp * 0.8 * wgt;
}

// ---- Round 15 (pasted after common4.txt): what a mood needs that the palette cannot say.
// Every part is driven by a world property of the sheet and costs nothing when it is 0.
// 1 = round 15's rules that have no property of their own (willow hem marks).
uniform float fix15 = 0.0;
// contact: a painted contact shadow on the ground round a building's foot, and a darker foot on
// its walls. One footprint per building: (centre x, centre z, half width, half depth), yaw.
uniform vec4 foot15[4];
uniform float foot_yaw15[4];
uniform float foot_n15 = 0.0;
uniform float contact15 = 0.0;
// window-light: the panes of a few windows glow and their light spills on the ground in front.
// One entry per lit window: its centre on the wall, and the wall's outward normal.
uniform vec4 glow15[6];
uniform vec4 glown15[6];
uniform float glow_n15 = 0.0;
uniform float glow_amt15 = 0.0;
uniform vec3 glow_col15 : source_color = vec3(1.0, 0.75, 0.35);
// sun-patch: a break in the cloud. (x, z, radius, amount): inside it everything is a tone lighter.
uniform vec4 patch15 = vec4(0.0);
// dapple: a crown's shadow on a built face is broken, lighter shade (0 = round 8's solid shape).
uniform float dapple15 = 0.0;
// litter: the share of a broadleaf's shadow strokes that are fallen leaves under its crown.
uniform float litter15 = 0.0;

float contact_at(vec3 p) {
	float c = 0.0;
	float wob = (p_noise(p * 1.7 + 3.0) - 0.5) * 0.22;
	int n = int(foot_n15 + 0.5);
	for (int i = 0; i < n; i++) {
		vec4 a = foot15[i];
		float cs = cos(foot_yaw15[i]);
		float sn = sin(foot_yaw15[i]);
		vec2 v = p.xz - a.xy;
		vec2 q = abs(vec2(cs * v.x - sn * v.y, sn * v.x + cs * v.y)) - a.zw;
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		c = max(c, 1.0 - smoothstep(0.02, 0.62, d + wob));
	}
	return c * contact15;
}

// How much window light falls on a ground point (0..1).
float spill_at(vec3 p) {
	float s = 0.0;
	int n = int(glow_n15 + 0.5);
	for (int i = 0; i < n; i++) {
		vec3 g = glow15[i].xyz;
		vec2 nn = normalize(glown15[i].xz + vec2(0.0001, 0.0));
		vec2 v = p.xz - g.xz;
		float along = dot(v, nn);
		float across = dot(v, vec2(-nn.y, nn.x));
		float reach = 1.5 + g.y * 0.55;
		float e = length(vec2((along - reach * 0.55) / reach, across / (0.75 + reach * 0.3)));
		s = max(s, (1.0 - smoothstep(0.25, 1.0, e + (p_noise(p * 1.3 + 8.0) - 0.5) * 0.25)) * step(0.0, along) / (1.0 + g.y * 0.25));
	}
	return s * glow_amt15;
}

// 1 on the pane of a lit window.
float pane_at(vec3 p) {
	int n = int(glow_n15 + 0.5);
	for (int i = 0; i < n; i++) {
		vec3 d = p - glow15[i].xyz;
		if (dot(d, d) < 0.36) {
			return glow_amt15;
		}
	}
	return 0.0;
}

float patch_at(vec3 p) {
	if (patch15.w <= 0.0) {
		return 0.0;
	}
	float e = length((p.xz - patch15.xy) * vec2(1.0, 1.5)) / patch15.z + (p_noise(p * 0.21 + 5.0) - 0.5) * 0.5;
	return patch15.w * (1.0 - smoothstep(0.45, 1.0, e));
}

// Round 8's soft form shadow, with `dapple`: a crown's shade is lighter, has a wide soft edge and
// a few bold gaps where the sun comes through; a building's shadow is as it was.
float occ15(vec3 o, vec3 d, int inst) {
	float sh = 0.0;
	float wob = (p_noise(o * 1.1 + 13.0) - 0.5) * 0.24 + (p_noise(o * 3.7 + 5.0) - 0.5) * 0.08;
	// (First version: gaps 1.3 m apart with a firm edge, at 0.62 of the shade. At dusk, where shade
	// and lit tones are far apart, that drew blots on a tiled roof; broader, softer and lighter now.)
	// (Second version, gaps 0.7 deep: still a camouflage of blots on the townhouse's tiles at dusk.)
	float gaps = 1.0 - 0.35 * dapple15 * smoothstep(0.35, 0.75, p_noise(o * vec3(0.45, 0.3, 0.45) + 41.0));
	for (int k = 0; k < 8; k++) {
		float fi = texelFetch(row_map, ivec2(9 + k, inst), 0).r;
		if (fi < -0.5) {
			break;
		}
		int i = int(fi + 0.5);
		vec4 a = texelFetch(occ_tex, ivec2(i, 0), 0);
		vec4 b = texelFetch(occ_tex, ivec2(i, 1), 0);
		vec3 v = o - a.xyz;
		if (a.w < 1.5) {
			if (a.w < 0.5 && crown_occ < 0.5) {
				continue;
			}
			vec3 lo = v / b.xyz;
			float c = dot(lo, lo) - 1.0;
			if (c < 0.3) {
				continue;
			}
			vec3 ld = d / b.xyz;
			float aa = dot(ld, ld);
			float bb = dot(lo, ld);
			if (bb < 0.0) {
				float miss = sqrt(max(dot(lo, lo) - bb * bb / aa, 0.0)) + wob;
				float crown = a.w < 0.5 ? 1.0 : 0.0;
				float one = 1.0 - smoothstep(mix(0.84, 0.5, dapple15 * crown), mix(1.02, 1.08, dapple15 * crown), miss);
				sh = max(sh, one * mix(1.0, (1.0 - 0.5 * dapple15) * gaps, crown));
			}
		} else {
			float cs = cos(b.w);
			float sn = sin(b.w);
			vec3 lo = vec3(cs * v.x - sn * v.z, v.y, sn * v.x + cs * v.z);
			vec3 q = abs(lo) - b.xyz;
			if (max(q.x, max(q.y, q.z)) < 0.3) {
				continue;
			}
			vec3 ld = vec3(cs * d.x - sn * d.z, d.y, sn * d.x + cs * d.z);
			vec3 inv = 1.0 / (ld + vec3(0.00001));
			vec3 t1 = (-b.xyz - lo) * inv;
			vec3 t2 = (b.xyz - lo) * inv;
			vec3 tmn = min(t1, t2);
			vec3 tmx = max(t1, t2);
			float tn = max(tmn.x, max(tmn.y, tmn.z));
			float tf = min(tmx.x, min(tmx.y, tmx.z));
			if (tf > max(tn, 0.0)) {
				sh = 1.0;
			}
		}
	}
	return sh;
}

// ---- Round 16 (pasted after common15.txt): the ground as a painting.
// r16 = 0 gives round 15's shaders exactly.
uniform float r16 = 0.0;
// The field map, laid over the world's xz (field_rect16 = x0, z0, width, depth), built on the CPU
// when the sun or the world changes: R a crown's cast shade, G a solid's cast shade (buildings,
// rocks, trunks), B the footprint under broadleaf crowns (litter), A the trodden path.
uniform sampler2D field16 : filter_linear, repeat_disable;
uniform vec4 field_rect16 = vec4(-58.0, -62.0, 116.0, 116.0);
// ground-shade: cast shadows are painted INTO the ground, per pixel, as the ground's own shade
// tone (its palette row at the shade end), with a soft edge that wanders in broad scallops
// (shade-scallop, metres) and a few soft holes of light inside a crown's shade (shade-holes).
uniform float shade16 = 0.0;
uniform float shade_scallop16 = 0.5;
uniform float shade_holes16 = 0.4;
// ground-patches: broad soft patches of the ground's own variants; cloud: a cloud's soft shadow;
// drift + drift-color: drifts of flowers or pale grass in the open; litter + litter-color: soft
// drifts of fallen leaves under broadleaf crowns; path + path-color: the path painted as one
// soft-edged trodden band.
uniform float patches16 = 0.0;
uniform float cloud16 = 0.0;
uniform float drift16 = 0.0;
uniform vec3 drift_col16 : source_color = vec3(1.0, 0.95, 0.7);
uniform float litter16 = 0.0;
uniform vec3 litter_col16 : source_color = vec3(0.9, 0.7, 0.2);
uniform float path16 = 0.0;
uniform vec3 path_col16 : source_color = vec3(0.8, 0.75, 0.6);
// mottle: 1 = round 15's fine broken colour on built faces, lower = fewer, broader patches.
uniform float mottle16 = 1.0;
// Bare crowns (twig rows): how far the soft twig mass is set back in depth so the limbs show
// through it (metres); twig-veil: the crown's own outline drawn as one veil, at this share of its
// radii (0 = clumps only). The share of sky in the mass is the leaf role's `sky`.
uniform float twig_back16 = 2.2;
uniform float twig_veil16 = 0.95;
// twig-swell: how far a bare crown's clumps swell so they join into one mass.
uniform float twig_swell16 = 1.35;

// thatch-streaks: the share of a thatch roof's streaks that are drawn; the kept ones are broader.
uniform float thatch16 = 1.0;

// The sun patch with a wide soft edge (round 15's had a firm, noisy one).
float patch16(vec3 p) {
	if (r16 < 0.5) {
		return patch_at(p);
	}
	if (patch15.w <= 0.0) {
		return 0.0;
	}
	float e = length((p.xz - patch15.xy) * vec2(1.0, 1.35)) / patch15.z + (p_noise(p * 0.12 + 5.0) - 0.5) * 0.3;
	return patch15.w * (1.0 - smoothstep(0.1, 1.0, e));
}

// Window light on the ground: round 15's shape with a soft falloff (it had a firm edge).
float spill16(vec3 p) {
	float s = spill_at(p);
	return s * s * (3.0 - 2.0 * s) * 0.6;
}

vec4 field_at(vec2 xz) {
	return textureLod(field16, (xz - field_rect16.xy) / field_rect16.zw, 0.0);
}

// How deep a ground point lies in cast shade (0..1): soft, scalloped, with holes in crown shade.
float shade_at16(vec3 p) {
	vec2 w = (vec2(p_noise(p * 0.5 + 21.0), p_noise(p * 0.5 + 47.0)) - 0.5) * 2.2 * shade_scallop16;
	vec4 f = field_at(p.xz + w);
	float holes = shade_holes16 * smoothstep(0.52, 0.74, p_noise(vec3(p.x * 0.4, 2.0, p.z * 0.4) + 31.0));
	float crown = smoothstep(0.12, 0.62, f.r) * (1.0 - holes) * 0.9;
	float solid = smoothstep(0.1, 0.7, f.g);
	return max(crown, solid) * shade16;
}

// The ground's colour at a point: `t` its lit tone, `vo` and `value_o` a mark's own offsets.
vec3 ground16(vec3 p, float row, float t, float vo, float value_o, float contact) {
	float n1 = p_noise(vec3(p.x * 0.05, 0.0, p.z * 0.075) + 3.0);
	float n2 = p_noise(vec3(p.x * 0.16, 1.7, p.z * 0.21) + 11.0);
	// (First version: 1.7 and 0.55, and the tone moved too: the meadow went from teal to yellow in
	// bands. The patches now stay inside the ground's own variants and its lit tone.)
	float variant = 0.5 + ((n1 - 0.5) * 1.0 + (n2 - 0.5) * 0.4) * patches16 + vo;
	float tv = t + (n2 - 0.5) * 0.03 * patches16;
	vec3 lit = palette_at(tv + value_o, row, variant);
	vec3 shd = palette_at(0.1 + value_o, row, variant);
	vec4 f = field_at(p.xz + (vec2(p_noise(p * 0.9 + 61.0), p_noise(p * 0.9 + 77.0)) - 0.5) * 0.9);
	// Drifts in the open: a slow noise picks where, a faster one breaks each drift into soft dabs.
	// (First version: firm thresholds on two noises; the drifts were a camouflage of hard blots.)
	float d = drift16 * smoothstep(0.52, 0.82, p_noise(vec3(p.x * 0.06, 9.0, p.z * 0.1) + 50.0)) * (0.55 + 0.45 * smoothstep(0.3, 0.7, p_noise(p * vec3(0.5, 1.0, 0.8) + 15.0)));
	d *= 0.6 / 0.85;
	vec3 base = mix(lit, drift_col16, d * 0.85);
	// Litter: a few soft drifts under and beside the crowns that shed it.
	float l = litter16 * smoothstep(0.2, 0.6, f.b) * smoothstep(0.4, 0.56, p_noise(vec3(p.x * 0.45, 4.0, p.z * 0.6) + 90.0));
	base = mix(base, litter_col16 * (0.9 + 0.2 * p_noise(p * 1.3 + 7.0)), l * 0.9);
	// The path: one trodden band, soft at its edges, a little uneven in colour.
	float pa = path16 * smoothstep(0.3, 0.62, f.a + (p_noise(p * 1.4 + 33.0) - 0.5) * 0.35);
	base = mix(base, path_col16 * (0.93 + 0.14 * p_noise(p * vec3(0.7, 1.0, 0.7) + 19.0)), pa);
	float sh = shade_at16(p);
	sh = max(sh, cloud16 * 0.4 * smoothstep(0.45, 0.8, p_noise(vec3(p.x * 0.018, 5.0, p.z * 0.03) + 70.0)));
	sh = max(sh, contact * 0.9);
	// What lies on the ground takes the ground's shade: its own colour as much darker and as far
	// toward the shade hue as the ground itself goes.
	vec3 shaded = mix(shd, base * (shd / max(lit, vec3(0.001))), min(1.0, d * 0.85 + l * 0.9 + pa));
	return mix(base, shaded, sh);
}

// ---- Round 17 (pasted after common16.txt): one hand. Everything on screen is a block-in shape or
// a stroke. Nothing here is sampled as a gradient: the field map of round 16 survives only as a
// mask that is cut hard (a block-in shape) or asked once per stroke (one flat colour a stroke).
// limb-snow: snow lies as one ridge along the upper side of a limb, by how level the limb is.
uniform float limb_snow17 = 0.0;
// bare-limb (metres): in a bare tree, a branch whose base is thinner than this is not drawn.
uniform float bare_limb17 = 0.0;
// whips: the share of a bare willow's hanging strands that stay, as thin whips.
uniform float whips17 = 0.4;
// ground-ink: the share of ground strokes in shade that are thin ink hatching marks (and its colour).
uniform float ground_ink17 = 0.0;
uniform vec3 ink17 : source_color = vec3(0.05, 0.05, 0.08);
// window-marks: the share of ground strokes in a lit window's reach that are warm marks.
uniform float glow_marks17 = 0.0;
// shade-keep: the share of a shadow's inner strokes that are drawn (its edge strokes all are).
uniform float shade_keep17 = 0.3;
// Aerial haze, laid into the colour of each stroke (once a stroke) and of the block-in.
uniform vec3 haze_col17 : source_color = vec3(0.8, 0.85, 0.9);
uniform float haze_amt17 = 0.0;
uniform float haze_start17 = 50.0;
uniform float haze_end17 = 90.0;
// The ground's own palette row (a tree's shadow stroke asked its own instance for the ground role
// and got row 0, the snow: round 15's shadows were the snow's blue shade in every mood).
uniform float ground_row17 = 0.0;
// turn-break: how far the edge between a crown's tones is broken (a noise in the block-in, a
// spread from stroke to stroke), so a crown turns from light to shade in steps, not as two halves.
uniform float turn17 = 0.0;
// turn-wide: 0..1 a crown's middle tone takes more of it: the lit tone is a rim on the sun side,
// the shade a smaller far side (0 = the world's thresholds as they are).
uniform float turn_wide17 = 0.0;

float turn_ndl17(float ndl) {
	return mix(ndl, ndl * 0.6 + 0.12, turn_wide17);
}

vec3 haze17(vec3 col, float depth) {
	return mix(col, haze_col17, haze_amt17 * smoothstep(haze_start17, haze_end17, depth));
}

// The sun patch as a shape with a firm, wandering edge (round 16's was a soft pool).
float patch17(vec3 p) {
	if (patch15.w <= 0.0) {
		return 0.0;
	}
	float e = length((p.xz - patch15.xy) * vec2(1.0, 1.35)) / patch15.z + (p_noise(p * 0.16 + 5.0) - 0.5) * 0.5;
	return patch15.w * (1.0 - smoothstep(0.6, 0.64, e));
}

// A form shadow on a built face as a flat shape with a firm edge (round 15's edge was a soft ramp):
// a crown's is the lighter one.
float cast17(float c) {
	return smoothstep(0.2, 0.26, c) * max(c, 0.55);
}

// How much snow a limb carries at a point of its axis (0..1.2): `tg` its direction (world), `r`
// its radius there, `wc` the point. Level limbs carry a ridge, steep ones little, upright none.
float snow_amt17(vec3 tg, float r, vec3 wc) {
	float lie = 1.0 - abs(tg.y);
	float a = smoothstep(0.2, 0.7, lie) * smoothstep(0.012, 0.035, r);
	return limb_snow17 * deposit * a * (0.65 + 0.7 * p_noise(wc * 0.8 + 3.0));
}

// The up side of a limb: the direction across it that points most upward.
vec3 snow_up17(vec3 tg) {
	return normalize(vec3(0.0, 1.0, 0.0) - tg * tg.y + vec3(0.0001, 0.0, 0.0002));
}

// Where the snow begins across a limb (in the cosine to the up side), for an amount.
float snow_bnd17(float a) {
	return mix(1.0, 0.45, clamp(a, 0.0, 1.0));
}

// The field map at a ground point, read where the shade's scalloped edge has wandered to.
vec4 gfield17(vec3 p) {
	vec2 w = (vec2(p_noise(p * 0.5 + 21.0), p_noise(p * 0.5 + 47.0)) - 0.5) * 2.2 * shade_scallop16;
	return field_at(p.xz + w);
}

// What a ground mark is: x 1 in cast shade, y 1 = keep it whatever the thinning says (it draws an
// edge, a hole of light, a drift, the path's edge), z 1 = a hole of light inside a crown's shade,
// w 1 = on the path. `h` is the mark's own hash; a block-in pixel passes 0.5 and is_stroke 0.
vec4 gflags17(vec3 p, float h, float is_stroke) {
	vec4 f = gfield17(p);
	float sv = max(f.r * 0.9, f.g);
	// (0.34 at first: single dabs of shade stood off the edge as islands.)
	float j = (h - 0.5) * 0.2 * is_stroke;
	float shade = step(0.42, sv + j);
	float edge = (sv > 0.1 && sv < 0.8) ? 1.0 : 0.0;
	float hole = 0.0;
	if (is_stroke > 0.5 && f.g < 0.3 && f.r > 0.55) {
		float zone = smoothstep(0.5, 0.68, p_noise(vec3(p.x * 0.4, 2.0, p.z * 0.4) + 31.0));
		hole = step(fract(h * 7.31 + 0.17), shade_holes16 * zone);
	}
	float pv = f.a + (p_noise(p * 1.4 + 33.0) - 0.5) * 0.35 + (h - 0.5) * 0.3 * is_stroke;
	float path = path16 * step(0.46, pv);
	if (path16 > 0.0 && f.a > 0.15 && f.a < 0.85) {
		edge = 1.0;
	}
	return vec4(shade * (1.0 - hole), max(edge, hole), hole, path);
}

// The ground's colour for a block-in pixel (h 0.5, is_stroke 0: flat shapes with firm edges) or for
// one stroke (its own hash: one flat colour). `t` its lit tone, `vo` and `value_o` the mark's own
// offsets, `force` 1 = a shadow stroke (always the shade tone of what lies there).
// Shade is the ground role's own shade tone, so the mood sets how far it is pushed to its shade hue.
// `mark`: what gmark17 said this stroke is (0 for the block-in and for shadow strokes).
float gmark17(vec3 p, float h) {
	if (glow_n15 > 0.5 && glow_marks17 > 0.0 && fract(h * 17.9 + 0.63) < glow_marks17 && spill_at(p) > 0.42) {
		return 2.0;
	}
	if (drift16 > 0.0) {
		float zone = smoothstep(0.5, 0.8, p_noise(vec3(p.x * 0.06, 9.0, p.z * 0.1) + 50.0));
		if (fract(h * 13.7 + 0.41) < drift16 * zone * 0.8) {
			return 1.0;
		}
	}
	return 0.0;
}

vec3 ground17(vec3 p, float row, float t, float vo, float value_o, float h, float is_stroke, float force, float mark) {
	vec4 g = gflags17(p, h, is_stroke);
	float n1 = p_noise(vec3(p.x * 0.05, 0.0, p.z * 0.075) + 3.0);
	float n2 = p_noise(vec3(p.x * 0.16, 1.7, p.z * 0.21) + 11.0);
	float pv = (n1 - 0.5) * 1.0 + (n2 - 0.5) * 0.4;
	if (is_stroke < 0.5) {
		// The block-in's patches are flat: three steps of the ground's own variants.
		pv = (floor(pv * 5.0 + 0.5)) / 5.0;
	}
	float variant = 0.5 + pv * patches16 + vo;
	vec3 lit = palette_at(t + value_o, row, variant);
	vec3 shd = palette_at(0.1 + value_o, row, variant);
	vec3 base = lit;
	float own = 0.0;
	float h2 = fract(h * 13.7 + 0.41);
	if (mark > 0.5 && mark < 1.5) {
		// Drifts of flowers or pale grass in the open: clusters of small dabs, never a wash.
		base = drift_col16 * (0.9 + 0.2 * fract(h * 31.3));
		own = 1.0;
	}
	if (g.w > 0.5) {
		base = path_col16 * (0.9 + 0.2 * (is_stroke > 0.5 ? fract(h * 5.77 + 0.3) : floor(p_noise(p * vec3(0.7, 1.0, 0.7) + 19.0) * 3.0) * 0.5));
		own = 1.0;
	}
	float sh = max(g.x, force);
	// A cloud's shadow: one broad flat shape, lighter than cast shade.
	float cz = cloud16 * step(0.6, p_noise(vec3(p.x * 0.018, 5.0, p.z * 0.03) + 70.0) + (h - 0.5) * 0.06 * is_stroke);
	sh = max(sh, cz * 0.42);
	if (contact15 > 0.0) {
		sh = max(sh, step(0.5, contact_at(p) + (h - 0.5) * 0.3 * is_stroke) * 0.9);
	}
	// What lies on the ground takes the ground's shade: as much darker, and half way to its colour.
	// (First version: its colour times shade over lit, channel by channel; at dusk, where the lit
	// ground is olive and its shade violet, the path in shade came out electric blue.)
	float lr = dot(shd, vec3(0.3, 0.59, 0.11)) / max(dot(lit, vec3(0.3, 0.59, 0.11)), 0.001);
	vec3 shaded = own > 0.5 ? mix(base * lr, shd, 0.5) : shd;
	vec3 col = mix(base, shaded, sh);
	if (mark > 1.5) {
		// Window light: a few small warm marks under the window that casts them.
		// (0.85 of the window's colour at first: flat pale discs on a dark ground, like stepping stones.)
		col = mix(col, glow_col15 * (0.75 + 0.2 * h2), 0.5);
	}
	return col;
}

// ---- Round 18 (pasted after common17.txt). NOTES.md "Round 18".
// crown-lo, crown-hi: the light (cosine to the sun, of the crown's form) at which a crown's shade
// ends and its lit tone begins. Set, they replace the world's thresholds for foliage, so a crown can
// keep a narrow lit side and a small shade side under a low sun (-9 = unset: round 17's rule).
uniform float crown_lo18 = -9.0;
uniform float crown_hi18 = 9.0;
// turn-half: a half tone either side of each of a crown's two tone edges, this share of the span
// between them wide (0 = three tones). The palette has it: it is the tone between two neighbours.
uniform float turn_half18 = 0.0;
// turn-big: the share of a crown's strokes that are a size larger and one half tone off their place
// (the turn is broken by a few large marks of the neighbouring tone).
uniform float turn_big18 = 0.0;
// crown-cast: the tone (0.1 shade .. 0.5 middle) foliage takes where another form shades it.
uniform float crown_cast18 = 0.1;
// Bare limbs in a painter's hand. limb-wide: a bare tree's limbs are this many times their grown
// width. limb-px: the least width of a main limb on screen (pixels; half as much again at 38 m;
// a limb at the bare-limb threshold gets under half of it). limb-taper: how far a limb narrows
// over its outer two thirds (1 = to a point). limb-far: bare-limb is this many times higher at 38 m.
uniform float limb_wide18 = 0.0;
uniform float limb_px18 = 0.0;
uniform float limb_taper18 = 0.0;
uniform float limb_far18 = 1.0;
// snow-lump: the depth of the snow on a limb, as a share of the limb's (widened) radius; it lies in
// lumps with gaps (a slow noise along the limb). snow-foot: metres of snow heaped against a stem's foot.
uniform float snow_lump18 = 1.2;
uniform float snow_foot18 = 0.0;
// snow-shelf: on evergreens the snow lies only on what faces up more than this (the cosine), as one
// shelf a bough, so needles show below and at the sides (0 = round 17's patches).
uniform float snow_shelf18 = 0.0;
// whip-wide: a bare willow's kept strands at this share of their summer width (they come in bunches).
uniform float whip_wide18 = 0.2;
// limb-shadow: a bare tree's shadow is painted limb by limb as long soft marks, for limbs this many
// times bare-limb and thicker (0 = round 17's dabs).
uniform float limb_shadow18 = 0.0;

float far18(float px) {
	return smoothstep(0.0128, 0.0352, px);
}

// The thinnest limb a bare tree draws (the radius at the limb's base, metres).
float limb_cut18(float px) {
	return bare_limb17 * mix(1.0, limb_far18, far18(px));
}

// A bare limb's painted radius: `r` grown, `base_r` at the limb's base, `along` 0 base .. 1 tip.
float limb_r18(float r, float base_r, float along, float px) {
	float tp = 1.0 - limb_taper18 * smoothstep(0.3, 1.0, along);
	float least = 0.5 * limb_px18 * px * mix(1.0, 1.5, far18(px)) * clamp(base_r / max(bare_limb17 * 2.5, 0.001), 0.4, 1.0) * (1.0 - 0.8 * smoothstep(0.3, 1.0, along));
	return max(r * limb_wide18 * tp, least);
}

float crown_ndl18(float ndl) {
	if (crown_lo18 < -5.0) {
		return turn_ndl17(ndl);
	}
	return tone_lo + (ndl - crown_lo18) * (tone_hi - tone_lo) / max(crown_hi18 - crown_lo18, 0.01);
}

// A crown's tone: three tones, or five with turn-half.
float crown_tone18(float x, float soft) {
	if (turn_half18 <= 0.0) {
		return tone3(x, 0.0, soft);
	}
	float w = turn_half18 * (tone_hi - tone_lo);
	return 0.1 + 0.2 * (smoothstep(-soft, soft, x - tone_lo + w) + smoothstep(-soft, soft, x - tone_lo - w) + smoothstep(-soft, soft, x - tone_hi + w) + smoothstep(-soft, soft, x - tone_hi - w));
}

// How near a crown's light is to one of its tone edges (1 on it .. 0 a quarter away).
float crown_edge18(float x) {
	float w = turn_half18 * (tone_hi - tone_lo);
	float d = min(min(abs(x - tone_lo + w), abs(x - tone_lo - w)), min(abs(x - tone_hi + w), abs(x - tone_hi - w)));
	return 1.0 - min(1.0, d * 4.0);
}

// Snow on a limb: lumps and ridges along level limbs, none on upright ones.
// `h`: the height above the tree's foot (none on the root flare: the foot has its own heap).
float snow_amt18(vec3 tg, vec3 wc, float h) {
	float lie = 1.0 - abs(tg.y);
	float lump = 0.3 + 1.1 * smoothstep(0.25, 0.7, p_noise(wc * 1.7 + 3.0));
	return limb_snow17 * deposit * smoothstep(0.15, 0.6, lie) * lump * smoothstep(0.4, 0.9, h);
}

float snow_deep18(float r, float sa, float px) {
	return max(r * snow_lump18, px * 2.0) * min(sa, 1.4);
}

// Where the snow begins across a limb (the cosine to its up side): lower than round 17's, it overhangs.
float snow_bnd18(float a) {
	return mix(1.0, 0.2, clamp(a, 0.0, 1.0));
}

// The deposit on an evergreen's or a rock's up side: a shelf (snow-shelf) or round 17's patches.
bool shelf18(float ny, float weight, vec3 p, float rnd) {
	if (snow_shelf18 > 0.0) {
		// The role's `settle` is the share of the up-facing surface that carries a shelf (a pine's flat
		// boughs face up nearly all over: first version, by the normal alone, left them all white).
		return deposit > 0.0 && ny + (p_noise(p * 2.1 + 3.0) - 0.5) * 0.2 > snow_shelf18 && p_noise(p * vec3(0.55, 1.6, 0.55) + 41.0) < weight * 0.9;
	}
	return deposit * weight * smoothstep(0.1, 0.55, ny) > dep_threshold(p, rnd);
}

// ---- The ground of round 18.
// window-spill: metres. A lit window near the ground casts a short warm spill that starts at the wall
// under it, widens a little and is gone within this distance (0 = round 17's marks in a pool).
uniform float spill18 = 0.0;
// litter-shapes: 1 = fallen leaves lie as a few broad flat shapes in two tones under the broadleaf
// crowns (round 17: single leaf dabs, confetti).
uniform float litter_shape18 = 0.0;
// drift-shade: snow drifts in the open: long low shapes, each with a crescent of shade on its lee side.
uniform float drift_shade18 = 0.0;
// mist: pale long shapes lying across the near ground, in the haze colour.
uniform float mist18 = 0.0;
// tufts, tuft-size, tuft-color: the share of open-ground marks, in a few clusters, that are upright
// tufts (dry grass through snow, reeds), their height in metres and their colour.
uniform float tufts18 = 0.0;
uniform float tuft_size18 = 0.4;
uniform vec3 fore_col18 : source_color = vec3(0.6, 0.5, 0.3);
// foot-grass: the share of ground marks at a building's foot that stand up against it.
uniform float foot_grass18 = 0.0;
// ink-open: the share of open-ground marks, in long zones, that are ink contour marks (see ground-ink).
uniform float ink_open18 = 0.0;
// rock-ink: a rock's outline is drawn in ink where its surface turns from the eye (0 = none).
uniform float rock_ink18 = 0.0;
// roof-dapple: 0 = a crown casts no shade on a roof (round 17: a soft stain); solid forms still do.
uniform float roof_dapple18 = 1.0;

float spill18_at(vec3 p) {
	float s = 0.0;
	int n = int(glow_n15 + 0.5);
	for (int i = 0; i < n; i++) {
		vec3 g = glow15[i].xyz;
		if (g.y > 2.4) {
			continue;
		}
		vec2 nn = normalize(glown15[i].xz + vec2(0.0001, 0.0));
		vec2 v = p.xz - g.xz;
		float along = dot(v, nn);
		float across = abs(dot(v, vec2(-nn.y, nn.x)));
		float w = 0.45 + along * 0.4 + (p_noise(p * 2.3 + 8.0) - 0.5) * 0.25;
		if (along > 0.05 && along < spill18 && across < w) {
			s = max(s, 1.0 - along / spill18);
		}
	}
	return s * glow_amt15;
}

float gmark18(vec3 p, float h) {
	if (spill18 <= 0.0) {
		return gmark17(p, h);
	}
	if (glow_n15 > 0.5) {
		float s = spill18_at(p);
		if (s > 0.0 && fract(h * 17.9 + 0.63) < 0.35 + 0.65 * s) {
			return 2.0;
		}
	}
	if (drift16 > 0.0) {
		float zone = smoothstep(0.5, 0.8, p_noise(vec3(p.x * 0.06, 9.0, p.z * 0.1) + 50.0));
		if (fract(h * 13.7 + 0.41) < drift16 * zone * 0.8) {
			return 1.0;
		}
	}
	return 0.0;
}

// Round 17's ground with round 18's flat shapes laid in: litter, snow drifts, mist, the window's spill.
vec3 ground18(vec3 p, float row, float t, float vo, float value_o, float h, float is_stroke, float force, float mark) {
	vec3 col = ground17(p, row, t, vo, value_o, h, is_stroke, force, mark);
	if (force > 0.5 || mark > 0.5) {
		return col;
	}
	float j = (h - 0.5) * is_stroke;
	vec3 shd = palette_at(0.1 + value_o, row, 0.5 + vo);
	if (drift_shade18 > 0.0) {
		vec2 away = normalize(sun_dir.xz + vec2(0.0001, 0.0));
		float d1 = p_noise(vec3(p.x * 0.06, 3.0, p.z * 0.15) + 90.0) + j * 0.04;
		vec2 q = p.xz + away * 1.6;
		float d2 = p_noise(vec3(q.x * 0.06, 3.0, q.y * 0.15) + 90.0);
		if (d1 > 0.6 && d2 < 0.6) {
			col = mix(col, shd, drift_shade18);
		}
	}
	if (mist18 > 0.0) {
		// Shorter and fewer than the first version, whose full-width bands read as pale roads.
		float m = p_noise(vec3(p.x * 0.05, 11.0, p.z * 0.17) + 30.0) + j * 0.03;
		if (m > 0.67 &&p.z + (p_noise(vec3(p.x * 0.05, 2.0, 7.0)) - 0.5) * 6.0 > 7.0) {
			col = mix(col, haze_col17, mist18);
		}
	}
	if (litter_shape18 > 0.0 && litter16 > 0.0) {
		vec4 f = gfield17(p);
		float ln = f.b * 1.1 + (p_noise(p * 0.5 + 61.0) - 0.5) * 0.9 + j * 0.12;
		if (ln > 0.64 && f.a < 0.3) {
			vec3 lc = litter_col16 * mix(0.74, 1.0, step(0.5, p_noise(p * 1.1 + 77.0) + j * 0.1));
			float sh = step(0.42, max(f.r * 0.9, f.g));
			col = mix(lc, mix(lc * 0.55, shd, 0.45), sh);
		}
	}
	if (is_stroke < 0.5 && spill18 > 0.0 && glow_n15 > 0.5 && spill18_at(p) > 0.3) {
		col = mix(col, glow_col15 * 0.8, 0.6);
	}
	return col;
}

// ---- Round 19 (pasted after common18.txt). NOTES.md "Round 19": a manner for bare wood.
// wood-stroke: 1 = a limb is drawn as a brush stroke: a ribbon that follows the limb's curve (a spline
// through the skeleton's nodes), turned to the eye, with a hand-drawn edge, tapering to a point, a
// light and a shade side with a broken turn, and its bark marks in limb coordinates (0 = round 18's tube).
uniform float wood19 = 0.0;
// limb-bend: metres. The whole skeleton is carried by one slow warp (so joints stay joined): limbs
// sweep and crook instead of running straight between forks.
uniform float limb_bend19 = 0.0;
// limb-edge: how far a limb's painted edge wanders, as a share of its radius.
uniform float limb_edge19 = 0.2;
// limb-dry: how much a limb stroke breaks into dry-brush streaks at its edges and toward its tip.
uniform float limb_dry19 = 0.5;
// limb-turn: how far the edge between a limb's light and shade side wanders (in the cosine to the sun).
uniform float limb_turn19 = 0.4;
// limb-point: how far every limb narrows to a point at its end (1 = a point; a stem that ends in a
// fork keeps its width there).
uniform float limb_point19 = 1.0;
// twig-limb: metres. A branch whose base is thinner than this is drawn in the twig manner: one thin
// dry stroke (twig-px wide on screen), broken along its length (twig-break), in the twig colour
// (the bare leaf role's colour) by twig-tone.
uniform float twig_r19 = 0.03;
uniform float twig_px19 = 1.3;
uniform float twig_break19 = 0.3;
uniform float twig_tone19 = 0.8;
// twig-mass: 1 = a bare crown's outermost twigs are drawn as clusters of thin strokes at the twig
// ends (near: sprays in the species' habit; far: a few broad dry-brush shapes). twig-back: metres the
// twig mass is set behind its limbs, so the limb strokes show through it.
uniform float twig_mass19 = 0.0;
uniform float twig_back19 = 0.4;
// twig-far: how large a far twig-mass shape is, against its clump.
uniform float twig_far19 = 1.5;
// twig-haze: how far a far twig-mass shape's colour goes toward the snow (the haze where there is none).
uniform float twig_haze19 = 0.35;
// snow-cap: the share of twig-mass strokes on the crown's upper side that are snow caps.
uniform float snow_cap19 = 0.0;
// snow-drift: metres. The height of the soft snow mound painted against the foot of a bare stem.
uniform float snow_drift19 = 0.0;
// snow-over: how far a snow lump stands out past the limb's upper edge, as a share of its radius.
uniform float snow_over19 = 0.8;

// The warp that carries a tree's skeleton (tree-local position; `seed` the tree's place).
vec3 warp19(vec3 p, vec3 seed) {
	if (limb_bend19 <= 0.0) {
		return vec3(0.0);
	}
	// (Two octaves on three axes at first: 12 noise lookups a vertex, twice, was a third of a millisecond
	// in every mood. One slow octave sideways and a cheap crook.)
	vec3 q = p * 0.42 + seed * 0.37;
	vec2 a = vec2(p_noise(q + 3.0), p_noise(q + 47.0)) - 0.5;
	vec2 b = vec2(sin(p.y * 2.9 + seed.x * 1.7 + p.x * 1.3), sin(p.y * 2.3 + seed.z * 2.1 + p.z * 1.1));
	return vec3(a.x * 2.0 + b.x * 0.14, 0.0, a.y * 2.0 + b.y * 0.14) * limb_bend19 * smoothstep(0.35, 2.6, p.y);
}

// How much a branch is a twig (1) or a limb (0), by the radius at its base.
float twig19(float base_r) {
	return 1.0 - smoothstep(twig_r19 * 0.8, twig_r19 * 1.3, base_r);
}

// A limb stroke's half width: `r` grown, `base_r` at the limb's base, `along` 0 base .. 1 tip.
float limb_r19(float r, float base_r, float along, float px, float twig, bool bare_tree) {
	if (!bare_tree) {
		return r;
	}
	float tp = 1.0 - limb_taper18 * smoothstep(0.3, 1.0, along);
	float least_main = 0.5 * limb_px18 * px * mix(1.0, 1.5, far18(px)) * clamp(base_r / 0.05, 0.45, 1.0) * (1.0 - 0.7 * smoothstep(0.3, 1.0, along));
	return max(r * max(limb_wide18, 1.0) * tp, mix(least_main, 0.5 * twig_px19 * px, twig));
}

// ---- tt-sim: the eye view's pin, the fades and the cast shadow's step.
// The eye view's stroke levels and lifts (the spike's eye_patch, e_* in both passes) are a later
// card's: pinned off, so every projection draws by the orbit view's rules (lod_level).
const float e_far = 1.0;

// The canopy fade's numbers (wind_foliage_include.gdshaderinc's CANOPY_*, the same law).
const float TREE_FADE_START = 0.5;
const float TREE_BRUSH_INNER = 0.55;
const float TREE_BRUSH_START = 0.3;
const float TREE_BRUSH_BAND = 1.2;
const float TREE_CUT_INNER = 0.6;
const float TREE_CUT_BARK = 1.5;
const float TREE_CUT_BEHIND = 0.5;
// (The per-token fade of painter-look-fade, painter-look-fade2 and the token window before it was
// removed on 2026-11-15: a covered token is found through the token ghost, not a hole in the crown.
// docs/PERFORMANCE.md "Occlusion fade removed".)

// The canopy fades (the view-centre window, a map brush's window, the Village tool's cut) of one
// tree fragment; fragment() passes its built-ins in (a plain function does not see them). `key`
// (0..1) is constant over a whole stroke or a whole mass, so a crown opens in bold pieces rather
// than a stipple; a `trunk` stays through every fade but the cut. Only the camera's pass fades:
// the sun's pass keeps the whole crown's shadow.
// (TREE_FAST, painter-perf-blockin: the discard-free masses leave it out; PainterTrees swaps them for
// the full shader while a fade is live.)
#ifndef TREE_FAST
void tree_fades(vec3 vertex_view, mat4 inv_view_matrix, float key, bool trunk) {
	vec3 back = canopy_fade_view.xyz;
	if (dot(inv_view_matrix[2].xyz, back) < 0.999) {
		return;
	}
	vec3 world = (inv_view_matrix * vec4(vertex_view, 1.0)).xyz;
	float fade = 0.0;
	if (canopy_cut.w > 0.0) {
		vec3 offset = world - canopy_cut.xyz;
		float ahead = dot(offset, back);
		float across = length(offset - back * ahead);
		float inner = canopy_cut.w * (trunk ? 1.0 : TREE_CUT_INNER);
		float outer = canopy_cut.w * (trunk ? TREE_CUT_BARK : 1.0);
		fade = max(smoothstep(-TREE_CUT_BEHIND, 0.0, ahead) * (1.0 - smoothstep(inner, outer, across)),
			1.0 - smoothstep(inner, outer, length(offset.xz)));
	}
	if (!trunk && canopy_fade_centre.w > 0.0) {
		vec3 offset = world - canopy_fade_centre.xyz;
		float ahead = dot(offset, back);
		float across = length(offset - back * ahead);
		fade = max(fade, canopy_fade_centre.w
			* smoothstep(TREE_FADE_START, TREE_FADE_START + canopy_fade_shape.z, ahead)
			* (1.0 - smoothstep(canopy_fade_shape.x, canopy_fade_shape.y, across)));
	}
	if (!trunk && canopy_brush.w > 0.0) {
		vec3 offset = world - canopy_brush.xyz;
		float ahead = dot(offset, back);
		float across = length(offset - back * ahead);
		fade = max(fade, smoothstep(TREE_BRUSH_START, TREE_BRUSH_START + TREE_BRUSH_BAND, ahead)
			* (1.0 - smoothstep(canopy_brush.w * TREE_BRUSH_INNER, canopy_brush.w, across)));
	}
	if (fade > 0.0 && key < fade) {
		discard;
	}
}
#endif

// The sun's cast shadow on a tree as a tone step (light() of both passes): 0 lit .. 1 shaded,
// cut at the engine's attenuation 0.5 with a threshold wiggle of `cut_amp` by a world noise at
// `wp` (painter-a1's rule: the lookup never moves, so a thin shadow never detaches).
float tree_cast(float attenuation, vec3 wp) {
	float kv = (p_noise(wp * 1.7 + 5.0) - 0.5) * 2.0 * cut_amp;
	return (1.0 - smoothstep(0.44 + kv, 0.56 + kv, attenuation)) * cast_amount;
}

// painter-perf-forest, painter-perf-cull: a tree's box in view space (`c` its centre, `h` its half
// extents along the view's axes plus TREE_BOX_PAD; from its tree_tex texels 5
// and 6: the centre in the tree's frame, w 1, and the half extents of its masses; w 0 = no box, `h`
// then unbounded), and whether it lies inside the four side planes of this pass's view (the camera's,
// or one sun cascade's) with `margin` metres to spare. The engine culls a cell's MultiMesh whole, so
// before this every tree of a cell that touched the view built every stroke even off the screen
// (forest tokens view: 21 of 58 cells drawn for 14 trees in view). Near and far are not tested.
// `view_cull` 1 culls; 2 draws only the trees it would cull (a diagnostic); 0 is off.
//
// The margin is how far a stroke reaches past the masses' box: its quad (a size of the order of a
// quarter metre to a metre, more far away: e_px metres a pixel) and the wind's sway. Measured
// 2026-11-14 (painter-perf-cull): with tree wind off, a frame with the cull on at a 0.5 m margin is
// pixel-identical to the frame with it off at tokens_45, tokens_winter_45, far_winter_45 and the
// forest home, everywhere but where the tokens animate. (The "sliver" painter-perf-forest saw at
// tokens_20 was the trees' own sway: the painted trees read TIME and the global wind, which the job's
// `wind` freeze does not stop, so two frames of one state differ along every crown edge.) The margin
// shipped is `view_margin` (1 m) plus TREE_VIEW_MARGIN_PX pixels' worth.
uniform float view_cull = 1.0;
uniform float view_margin = 1.0;
const float TREE_VIEW_MARGIN_PX = 8.0;
// The metres past a tree's box that a stroke or a clump reaches (PainterTreePack.BOUND_PAD, which a
// test pins to this).
const float TREE_BOX_PAD = 2.5;

vec3 tree_view_extent(mat3 vm, vec3 half_ext) {
	// A box turned into view space, boxed again: its extent along each view axis.
	return vec3(dot(abs(vec3(vm[0][0], vm[1][0], vm[2][0])), half_ext),
		dot(abs(vec3(vm[0][1], vm[1][1], vm[2][1])), half_ext),
		dot(abs(vec3(vm[0][2], vm[1][2], vm[2][2])), half_ext));
}

bool tree_view_box(vec4 centre, vec4 half_ext, mat4 model, mat4 view, mat4 proj, float px,
		out vec3 c, out vec3 h) {
	c = vec3(0.0);
	h = vec3(1e6);
	if (centre.w <= 0.0) {
		return true;
	}
	c = (view * (model * vec4(centre.xyz, 1.0))).xyz;
	mat3 vm = mat3(view) * mat3(model);
	h = tree_view_extent(vm, half_ext.xyz + vec3(TREE_BOX_PAD));
	if (view_cull < 0.5) {
		return true;
	}
	vec4 rx = vec4(proj[0][0], proj[1][0], proj[2][0], proj[3][0]);
	vec4 ry = vec4(proj[0][1], proj[1][1], proj[2][1], proj[3][1]);
	vec4 rw = vec4(proj[0][3], proj[1][3], proj[2][3], proj[3][3]);
	vec4 side[4] = vec4[4](rw + rx, rw - rx, rw + ry, rw - ry);
	bool inside = true;
	vec3 hp = tree_view_extent(vm, half_ext.xyz) + vec3(view_margin + TREE_VIEW_MARGIN_PX * px);
	for (int i = 0; i < 4; i++) {
		if (dot(side[i].xyz, c) + side[i].w < -dot(abs(side[i].xyz), hp)) {
			inside = false;
		}
	}
	return inside != (view_cull > 1.5);
}

