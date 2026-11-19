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
 * roof, a darker foot on a wall, a few sparse marks in each material's manner (soft course
 * bands on tiles, slates and shingles, straw strands on thatch, blocks on stone, seams on logs and
 * boards), and a dark line where the surface folds (a corner, an eave lip). Marks fade out
 * before they are under about two pixels.
 *
 * The colour of a wall, timber or stone is its sheet role's (one ramp, `ramps[0..5]`). A tile or
 * wooden roof follows the building's own roof paint (StructurePaint's vertex colour), as Classic
 * does, so one material serves every building and street lot: the paint chooses the nearest of
 * the four roof roles (red and orange clay, ochre and brown shingle, green turf, blue and grey
 * slate) and that role's ramp is turned from its summer tone (`paint_ref`) to the paint, as the
 * hand-drawn manner's round roofs are (card painter-roof-clay: a street's red tile roofs read
 * mud-brown, its green ones slate, when a lot's wooden roof never took the clay and a green paint
 * took the slate). The turn is relative, so each mood's own moves of the role carry over. A slate
 * or shingle roof keeps its kind's ramp and turns it to its paint the same way (card
 * painter-roof-polish: an alpine lot's blue-grey shingle drew brown, a modern row's peach and teal
 * slates blue-grey).
 * COLOR.a is the height up a roof (0 eave, 1 ridge) or above a wall's foot in sixteenths of a metre.
 *
 * Cost: two 3D value noises for the patches, one for the dabs, one for the edge wobble, a few
 * pattern hashes a fragment; on a picked roof three OKLab round trips (the turn, per vertex);
 * no texture reads, no branches on per-fragment data beyond the pattern switch on a uniform.
 *
 * MANAGED BY: PainterBuildings (painter/painter_buildings.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_structure_common.gdshaderinc"
#include "res://painter/shaders/painter_snow.gdshaderinc"
#include "res://painter/shaders/painter_building_burn.gdshaderinc"

// 0 plaster, 1 stone, 2 log, 3 boards, 4 timber, 5 tile, 6 slate, 7 shingle, 8 thatch, 9 turf.
uniform int pattern = 0;
// 0: the material's own ramp; 1: a tile roof's tone by its paint; 2: a wooden roof's (both turned
// to the paint); 3: a door's or shutter's (timber, or the clay, turf or slate accent by its paint).
uniform int pick = 0;
// LINEAR [shade0, mid0, lit0, shade1, mid1, lit1] per tone; a picked roof's tones are 0 clay,
// 1 slate, 2 shingle, 3 turf.
uniform vec3 ramps[24];
// A picked roof's reference tones (OKLab, the four roles' middles in the mood a paint is read in:
// PainterBuildings.paint_refs) that its ramp turns from to its paint.
uniform vec3 paint_ref[4];
// The street lots' planks (the wall layers' `Wood`): a vertex whose UV2.x is 1 is a house's (its
// walls, frames and trim; WallGeometry.house_flags) and takes the second ramp, the plank houses'
// calmer wood; a yard fence, a drawn fence and a bridge deck (0) keep the props' honey (owner
// 2026-11-19: "Plank houses less honey"; the fences keep their warmth).
uniform bool house_planks = false;
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
// A picked roof's turn of its ramp to its paint (painter_structure_common's paint_turn); z 0: none.
varying flat vec4 v_turn;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;
// x: half the width of the light's steps, y: how far the wobble moves them (soft on snow), z: the
// light's share under which a point is in cast shadow, w: how far the wobble moves that share.
varying vec4 f_soft;

// A wall's share of the variant patches and of the dabs (card painter-walls-round3, owner on the
// grimdark streets: "the walls are still splotchy"): a wall is a few broad soft tones, its
// weathering at the foot, never camouflage.
const float WALL_PATCHES = 0.55;
const float WALL_DABS = 0.45;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_h = COLOR.a;
	v_tone = tone_of(pick, COLOR.rgb);
	if (house_planks && UV2.x > 0.5) {
		v_tone = 1;
	}
	v_turn = vec4(1.0, 0.0, 0.0, 1.0);
	if (paint_turns(pattern, pick)) {
		// A tile or wooden roof (a street lot's, a wall row's): the role nearest its paint, its ramp
		// turned to the paint; a grey paint keeps the slate's hue and takes only its lightness and
		// greyness. A shingle roof (an alpine lot's `Roof_shingle`) keeps its kind's ramp, turned to
		// its paint the same way; a slate roof (a modern row's `Roof_slate`) the nearest of its own
		// three (paint_slate_tone).
		vec3 lab = paint_lab(COLOR.rgb);
		bool grey = paint_grey(lab, pick);
		if (pick > 0 && !grey) {
			v_tone = paint_roof_tone(lab);
		} else if (pattern == 6 && !grey) {
			v_tone = paint_slate_tone(lab);
		}
		v_turn = paint_turn(lab, paint_ref[v_tone], grey);
	}
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
	if (building_break(wp, clamp(v_h, 0.0, 1.0))) {
		discard;
	}
	// The variant: broad soft patches, their edges broken by a finer octave. A roof is one broad
	// mass and takes half the patches and half the dabs (card painter-roof-clay: on a street's big
	// roofs the full patches and dark dabs read as camouflage blotches; the hand-drawn manner's
	// slopes are as calm). A wall takes WALL_PATCHES of them and WALL_DABS of its dabs.
	float calm = pattern >= 5 ? 0.5 : WALL_PATCHES;
	float pn = mix(p_noise(wp * patch_freq + 7.0), p_noise(wp * patch_freq * 3.3 + 21.0), 0.3);
	float variant = mix(0.5, smoothstep(0.36, 0.64, pn), patch_mix * calm);
	// `dark` pulls toward the variant's shade, `light` toward its lit colour.
	float dark = 0.0;
	float light = 0.0;
	// Dabs: a few soft spots a step darker or lighter, about a metre across, so a slope or a wall
	// is never one smooth field (the prototype's roofs: blotches over the base colour).
	float bn = p_noise(wp * dab_freq + 33.0);
	float dab = (pattern >= 5 ? calm : dab_wall * WALL_DABS) * dabs;
	// A slate's dark dabs read as blotches up close: a lighter share of them. Every roof's dark dabs
	// are halved again (a quarter of their old share, as the hand-drawn slopes' 0.5 of 0.5), since
	// they pull the tile toward its violet shade and read as damp stains on a big street roof.
	dark += smoothstep(0.62, 0.72, bn) * dab * (pattern == 6 ? 0.35 : calm);
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
			// Tiles, slates, shingles: soft course banding, a shadow under each course's lip run
			// across the whole slope, each course a touch apart, and the slope a little lighter toward
			// its ridge (card painter-roof-polish: a tile's own variant read as a patchwork of lighter
			// and rosier tiles at zoom 16 where Classic is one smooth red, and the broken dashes as busy
			// ticks on a hip face). The bands fade before a course is under about three pixels. Only a
			// hint of them (card painter-roof-round3, owner: "Banding too strong" at 0.2 of shadow and
			// 0.14 of variant): a slope reads as one calm mass with its courses suggested.
			float course = pattern == 5 ? 0.42 : (pattern == 6 ? 0.32 : 0.26);
			float r = s / course;
			float banding = (1.0 - smoothstep(0.2, 0.45, fwidth(r))) * tiled;
			dark += (1.0 - smoothstep(0.0, 0.5, fract(r))) * 0.08 * banding;
			float band = p_hash(vec3(floor(r), 4.0, 9.0));
			variant = clamp(variant + (band - 0.5) * 0.05 * banding, 0.0, 1.0);
			light += 0.16 * smoothstep(0.1, 1.0, h) * tiled;
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
			variant = clamp(variant + (blk - 0.5) * 0.6, 0.0, 1.0);
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
	// Snow on a roof (winter): the shared layer of painter_snow.gdshaderinc, as the hand-drawn
	// houses' and the props' (one soft thick cushion: a lit top, a lip rolling over the eave with a
	// blue underside, a crest at the ridge, a few soft gaps along it). No record here: its frame
	// comes from the face and h.
	float cover = 0.0;
	vec4 sp = vec4(0.0, 0.0, 0.5, 0.0);
	vec3 roll = vec3(0.0);
	if (pattern >= 5 && snow > 0.0) {
		vec4 fr = snow_frame(wp, n, h);
		float broad = 1.0 - smoothstep(0.08, 0.16, length(fwidth(fr.xy)));
		cover = snow_cover_roof(snow, up, h, fr.xy) * (1.0 - snow_gap(fr.xy, fr.w));
		// A gable end clad in the roof's material, and the slab's edges (snow_gable).
		cover = max(cover, clamp(snow * 2.2, 0.0, 1.0) * snow_gable(up));
		sp = snow_paint(fr.xy, broad);
		roll = snow_roll(snow_edge_m(up, h, fr.xy, fr.z), fr.w, fr.xy);
	}
	// No roof mark shows through the layer (the course dashes read as a grid of ticks on it).
	dark = clamp(dark * marks * (1.0 - cover), 0.0, 0.85);
	light = clamp(light * marks * (1.0 - cover), 0.0, 0.8);
	vec2 sm = snow_marks(cover, sp, roll.y, roll.z);
	dark = clamp(dark + sm.x, 0.0, 0.85);
	light = clamp(light + sm.y, 0.0, 0.8);
	// The layer's shape: its shading normal rolls along the fall line (the face's own `up` and the
	// marks keep the plain normal).
	vec3 shade_n = n;
	if (cover > 0.0) {
		shade_n = normalize(n + vec3(down.x, 0.0, down.y) * roll.x * cover);
	}
	int base = v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	if (v_turn.z > 0.0) {
		// A picked roof in its recipe's own colour (v_turn, from its paint).
		shd = paint_turned(shd, v_turn);
		mid = paint_turned(mid, v_turn);
		lit = paint_turned(lit, v_turn);
	}
	shd = mix(shd, snow_ramp[0], cover);
	mid = mix(mid, snow_ramp[1], cover);
	lit = mix(lit, snow_ramp[2], cover);
	vec3 deep = shd * 0.82;
	vec3 o_shd = mix(mix(shd, deep, dark), mid, light * 0.5);
	vec3 o_mid = mix(mix(mid, shd, dark), lit, light * 0.6);
	vec3 o_lit = mix(mix(lit, mid, dark), lit * 1.06, light);
	f_lit = snow_warm(o_lit, sp.w * cover);
	f_shd = mix(o_shd, snow_sky_shade(o_shd, o_mid, up * (1.0 - roll.y)), cover);
	f_mid = o_mid;
	// A varying cannot be an inout argument: the burn works on copies.
	vec3 burn_shd = f_shd;
	vec3 burn_mid = f_mid;
	vec3 burn_lit = f_lit;
	EMISSION = building_burn(wp, h, burn_shd, burn_mid, burn_lit);
	f_shd = burn_shd;
	f_mid = burn_mid;
	f_lit = burn_lit;
	f_n = shade_n;
	// On snow the light turns over a soft step that the layer's dabs push about (its light and
	// shade break into brush dabs); elsewhere a crisp step with a small wobble.
	f_wob = mix(p_noise(wp * 1.7 + 5.0), sp.z, cover);
	// A point on snow is in cast shadow only under a fuller shadow (the hand-drawn roofs' 0.3), so a
	// grazing sun's partial self-shadow on the roof draws no hatch of ticks across the layer. A bare
	// roof too, and its light step barely wobbles: a slope is one plane, so it is lit or not as a
	// whole (card painter-roofs-ivy: at grimdark's tone-hi 0.66 and a low sun a street roof's slope
	// sat at the step and the wobble and the partial self-shadow broke it into camouflage patches).
	// A wall face is one plane as well (card painter-walls-round3: at grimdark's tone-hi a street's
	// sunward plank walls broke into tan patches over brown): its step barely wobbles and turns over
	// a little more softly, so a face that sits at the step is one even blend; a cast shadow's edge
	// on it wobbles half as far.
	float roof = pattern >= 5 ? 1.0 : 0.0;
	f_soft = vec4(
		mix(mix(0.03, 0.02, roof), 0.06, cover),
		mix(0.03, 0.32, cover),
		mix(mix(0.5, 0.3, roof), 0.3, cover),
		mix(0.1, 0.2, roof));
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(f_soft.z - 0.05, f_soft.z + 0.05, ATTENUATION + (f_wob - 0.5) * f_soft.w);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * f_soft.y;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - f_soft.x, tone_lo + f_soft.x, x));
		col = mix(col, f_lit, smoothstep(tone_hi - f_soft.x, tone_hi + f_soft.x, x));
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount);
	}
}
