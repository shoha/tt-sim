shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted structure (a building's wall, roof, timber or stone under the Painted look)
 * ================================================================================
 *
 * The recipe mesh drawn in the sheet's colours (docs/systems/painter.md "Buildings"; owner D5,
 * 2026-11-12: a sheet-driven shader on the existing meshes, the hand-drawn manner waits for
 * procgen's edge and piece data). The selector light of the plants (painter_selector): ALBEDO
 * white, the ambient off, and light() picks the role's shade, middle or lit colour from N.L and
 * the sun's ATTENUATION, so a building reads tt-sim's one directional shadow map and the sheet's
 * colours reach the screen as written. It casts as any mesh does.
 *
 * What is painted is SUGGESTED in a few broad shapes, never drawn literally: soft patches of the
 * role's two variants at about the size of a tree clump, a deeper eave and a paler ridge on a
 * roof, a darker foot on a wall, a few sparse marks in each material's manner (broken course
 * dashes on tiles and slates, straw strands on thatch, blocks on stone, seams on logs and
 * boards), and a dark line where the surface folds (a corner, an eave lip). Marks fade out
 * before they are under about two pixels.
 *
 * The colour of a wall, timber or stone is its sheet role's (one ramp, `ramps[0..5]`). A tile or
 * wooden roof's tone is CHOSEN by the hue of the building's own roof paint (StructurePaint's
 * vertex colour), so one material serves every building and street lot: red and orange are clay,
 * a brown or straw paint shingle, a grey, green or blue one slate (a green roof beside the meadow
 * is what this avoids); the colour itself is always the sheet's (`ramps`, four tones of six).
 * COLOR.a is the height up a roof (0 eave, 1 ridge) or above a wall's foot in sixteenths of a metre.
 *
 * Cost: two 3D value noises for the patches, one for the dabs, one for the edge wobble, a few
 * pattern hashes a fragment;
 * no texture reads, no branches on per-fragment data beyond the pattern switch on a uniform.
 *
 * MANAGED BY: PainterBuildings (painter/painter_buildings.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_structure_common.gdshaderinc"
#include "res://painter/shaders/painter_building_burn.gdshaderinc"

// 0 plaster, 1 stone, 2 log, 3 boards, 4 timber, 5 tile, 6 slate, 7 shingle, 8 thatch, 9 turf.
uniform int pattern = 0;
// 0: the material's own ramp; 1: a tile roof's tone by its paint; 2: a wooden roof's (no clay);
// 3: a door's or shutter's (timber, or the clay, turf or slate accent by its paint).
uniform int pick = 0;
// LINEAR [shade0, mid0, lit0, shade1, mid1, lit1] per tone; a picked roof's tones are 0 clay,
// 1 slate, 2 shingle, 3 turf.
uniform vec3 ramps[24];
// The share of a roof under snow (sheet roof-snow) and the snow's LINEAR [shade, mid, lit].
uniform float snow = 0.0;
uniform vec3 snow_ramp[3];
// The N.L where the shade, middle and lit steps meet (sheet tone-lo, tone-hi).
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
// How far a cast shadow steps a face into its shade colour.
uniform float cast_amount = 0.94;
// The patches: 1/m of the noise that picks the variant, and how much of it shows.
uniform float patch_freq = 0.42;
uniform float patch_mix = 0.85;
// The dabs: 1/m, their strength on a roof, and the share a wall takes.
uniform float dab_freq = 1.1;
uniform float dabs = 0.3;
uniform float dab_wall = 0.45;
// The marks' strength (0 none), the fold line's, the wall foot's and the roof eave's.
uniform float marks = 1.0;
uniform float ink = 0.55;
uniform float contact = 0.4;
uniform float contact_m = 0.8;
uniform float eave = 0.35;

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_h;
varying flat int v_tone;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_h = COLOR.a;
	v_tone = tone_of(pick, COLOR.rgb);
}

// A thin line at the start of each unit of `x` (width `w` of a unit), faded out before the
// units are under about two pixels.
float p_line(float x, float w) {
	float f = fract(x);
	float d = min(f, 1.0 - f);
	float detail = 1.0 - smoothstep(0.25, 0.6, fwidth(x));
	return (1.0 - smoothstep(w * 0.5, w, d)) * detail;
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	vec3 n = normalize(v_wn);
	vec3 wp = v_wp;
	// The variant: broad soft patches, their edges broken by a finer octave.
	float pn = mix(p_noise(wp * patch_freq + 7.0), p_noise(wp * patch_freq * 3.3 + 21.0), 0.3);
	float variant = mix(0.5, smoothstep(0.36, 0.64, pn), patch_mix);
	// `dark` pulls toward the variant's shade, `light` toward its lit colour.
	float dark = 0.0;
	float light = 0.0;
	// Dabs: a few soft spots a step darker or lighter, about a metre across, so a slope or a wall
	// is never one smooth field (the prototype's roofs: blotches over the base colour).
	float bn = p_noise(wp * dab_freq + 33.0);
	float dab = (pattern >= 5 ? 1.0 : dab_wall) * dabs;
	// A slate's dark dabs read as blotches up close: a lighter share of them.
	dark += smoothstep(0.62, 0.72, bn) * dab * (pattern == 6 ? 0.35 : 1.0);
	light += (1.0 - smoothstep(0.28, 0.38, bn)) * dab * 0.8;
	// A slope's own axes (roofs) and a wall's horizontal axis, from the face normal.
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float up = n.y;
	float s = dot(wp.xz, down) / max(up, 0.35);
	// Across the slope on a roof, along the wall on a wall.
	float t = dot(wp.xz, across);
	float u = t;
	float h = clamp(v_h, 0.0, 1.0);
	if (pattern >= 5) {
		float tiled = smoothstep(0.25, 0.5, up);
		// A deeper eave band and a paler ridge.
		dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
		light += 0.35 * smoothstep(0.82, 1.0, h) * tiled;
		if (pattern == 8) {
			// Straw: a few long strands down the slope, darker or lighter, in loose bundles.
			float st = t / 0.11 + p_noise(vec3(s * 0.5, t * 0.3, 3.0)) * 1.4;
			float seg = floor(s / 0.9 + p_hash(vec3(floor(st), 1.0, 2.0)) * 3.0);
			float pickm = p_hash(vec3(floor(st), seg, 5.0));
			float strand = p_line(st + 0.5, 0.35) * step(0.82, pickm) * tiled;
			dark += strand * 0.45 * step(0.91, pickm);
			light += strand * 0.5 * (1.0 - step(0.91, pickm));
		} else if (pattern == 9) {
			// Turf: lighter tufts in the patches.
			float tuft = step(0.86, p_hash(floor(wp * 2.2))) * tiled;
			light += tuft * 0.4;
		} else {
			// Tiles, slates, shingles: broken dashes under each course's lip.
			float course = pattern == 5 ? 0.42 : (pattern == 6 ? 0.32 : 0.26);
			float r = s / course;
			float row = floor(r);
			float dash = step(0.72, p_hash(vec3(row, floor(t / 1.1 + row * 0.37), 9.0)));
			dark += p_line(r, 0.16) * dash * 0.5 * tiled;
			float piece = p_hash(vec3(row, floor(t / (course * 1.6) + 0.5 * row), 4.0));
			variant = clamp(variant + (piece - 0.5) * 0.5 * tiled, 0.0, 1.0);
		}
	} else {
		float hm = h * 16.0;
		// A darker foot.
		dark += contact * (1.0 - smoothstep(0.0, contact_m, hm)) * (1.0 - smoothstep(0.6, 0.9, abs(up)));
		if (pattern == 1) {
			// Stone: blocks in courses, each its own variant, a thin joint.
			float r = wp.y / 0.34;
			float row = floor(r);
			float c = u / 0.62 + 0.5 * mod(row, 2.0) + p_hash(vec3(row, 3.0, 1.0)) * 0.3;
			float blk = p_hash(vec3(row, floor(c), 7.0));
			variant = clamp(variant + (blk - 0.5) * 0.8, 0.0, 1.0);
			dark += max(p_line(r, 0.1), p_line(c, 0.06)) * 0.4;
		} else if (pattern == 2) {
			// Logs: a round of 0.3 m with a dark seam and a lit belly.
			float r = wp.y / 0.3;
			dark += p_line(r, 0.14) * 0.6;
			light += (1.0 - abs(fract(r) - 0.5) * 2.0) * 0.18;
		} else if (pattern == 3) {
			// Boards: vertical, 0.24 m, a dark seam, each board its own variant.
			float c = u / 0.24;
			dark += p_line(c, 0.1) * 0.5;
			variant = clamp(variant + (p_hash(vec3(floor(c), 2.0, 8.0)) - 0.5) * 0.5, 0.0, 1.0);
		} else if (pattern == 0) {
			// Plaster: soft vertical brush streaks in the wash.
			float streak = be_cut(vec2(wp.y * 0.6, u * 0.9 + wp.y * 0.1));
			light += max(streak, 0.0) * 0.12;
			dark += max(-streak, 0.0) * 0.08;
		}
	}
	// The fold line: where the shading normal turns within a pixel (a corner, an eave lip).
	dark += smoothstep(0.2, 0.6, length(fwidth(NORMAL))) * ink;
	// Snow on a roof (winter): the snow's own tones, the marks under it mostly hidden.
	float cover = pattern >= 5 ? snow_cover(snow, wp, up, h) : 0.0;
	dark = clamp(dark * marks * (1.0 - cover * 0.85), 0.0, 0.85);
	light = clamp(light * marks * (1.0 - cover * 0.85), 0.0, 0.8);
	int base = v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	shd = mix(shd, snow_ramp[0], cover);
	mid = mix(mid, snow_ramp[1], cover);
	lit = mix(lit, snow_ramp[2], cover);
	vec3 deep = shd * 0.82;
	f_shd = mix(mix(shd, deep, dark), mid, light * 0.5);
	f_mid = mix(mix(mid, shd, dark), lit, light * 0.6);
	f_lit = mix(mix(lit, mid, dark), lit * 1.06, light);
	// A varying cannot be an inout argument: the burn works on copies.
	vec3 burn_shd = f_shd;
	vec3 burn_mid = f_mid;
	vec3 burn_lit = f_lit;
	EMISSION = building_burn(wp, h, burn_shd, burn_mid, burn_lit);
	f_shd = burn_shd;
	f_mid = burn_mid;
	f_lit = burn_lit;
	f_n = n;
	f_wob = p_noise(wp * 1.7 + 5.0);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(0.45, 0.55, ATTENUATION + (f_wob - 0.5) * 0.2);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * 0.12;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - 0.01, tone_lo + 0.01, x));
		col = mix(col, f_lit, smoothstep(tone_hi - 0.01, tone_hi + 0.01, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
