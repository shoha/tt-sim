/*
 * Roof snow: one model for every painted surface that carries it (card painter-roof-snow,
 * 2026-11-18; owner: "why don't these share an implementation for snow coverage?"). Its users:
 * the hand-drawn manner's blanket mesh (code 10), the roof pieces under it and the round and Taper
 * roofs that have no record (painter_structure_manner.gdshader), the A3b roofs of the street lots,
 * wall rows and boundaries (painter_structure.gdshader) and the up faces of the village props
 * (painter_prop.gdshader).
 *
 * The model. Snow lies as one soft, thick layer, never as patches (owner: "flat splotches",
 * "much patchier"). Where it lies on a face with no record is the snow law
 * (painter_snow_law.gdshaderinc, included here: one hold by the face's up, which a roof sheds
 * sooner, and a few broad soft shapes where a face holds part; cards snow-one-law and
 * snow-steep-roofs). Upright faces
 * hold none (a street roof's tile gables keep a drift along their foot, snow_upright, snow_foot).
 * The layer is drawn in the snow's own ramp with a body:
 *   a lit top    broad soft swells (warm white) and hollows (toward the blue shade), wider along
 *                the eave than down the slope, under a few broad brush washes; the light turns
 *                over a soft step that broad dabs push about, so light and shade break into brush
 *                dabs and not airbrushed gradients (snow_paint);
 *   a round edge where the layer has no mesh of its own, its shading normal rolls over the eave
 *                in a lip whose last few centimetres are the underside, the deepest shade, crests at
 *                the ridge and rises and falls in a slow drift (snow_roll); a blanket mesh
 *                carries that shape in its own normals;
 *   the crest    a few short soft gaps along the ridge where the wind scoured it, the roof's own
 *                colour showing as a thin line (snow_gap); no bare strokes anywhere else.
 * Callers pass the snow's frame on their surface (metres along the eave and up the slope, and to
 * the eave and the ridge where known, SNOW_FAR where not; snow_frame finds them on a roof face
 * without a record). Needs painter_noise.gdshaderinc first (p_n2, p_wash). No texture reads.
 */

#include "res://painter/shaders/painter_snow_law.gdshaderinc"

// A distance to an edge the surface does not know (a prop's top, a flat roof's middle).
const float SNOW_FAR = 99.0;

// A street roof's upright faces (0 to 1): a gable end clad in the roof's own material (the guild
// and market houses' ends, h running 0 to 1 up the triangle as up a slope) and the slab's edges.
// Snow does not lie on them (card painter-roof-round5, owner on round 4's snowed gables: "would
// the gables actually have snow on them? i don't think they would"): they keep their own tile, a
// touch cooler among the snow, with a little drift caught along their foot (snow_foot). An
// underside keeps none.
float snow_upright(float up) {
	return smoothstep(-0.3, -0.15, up) * (1.0 - smoothstep(0.08, 0.16, up));
}

// The drift along an upright face's foot (0 to 1) at `above` metres over it (snow_frame's z on an
// upright face; SNOW_FAR where unknown) and `along` metres along it: 8 to 22 cm deep, its top a
// soft broken line.
float snow_foot(float above, float along) {
	float deep = 0.08 + 0.14 * p_n2(vec2(along * 0.9, 21.0), 181.0);
	return 1.0 - smoothstep(deep - 0.05, deep + 0.03, above);
}

// Where the wind scoured the crest (1 bare): a few short soft gaps along the ridge, in about a
// quarter of its run, up to 0.45 m down from it. `to_ridge` metres down from the ridge.
float snow_gap(vec2 f, float to_ridge) {
	float run = p_n2(vec2(f.x * 0.4, 3.0), 114.0);
	float reach = 0.18 + 0.27 * p_n2(vec2(f.x * 1.3, 7.0), 117.0);
	return smoothstep(0.58, 0.7, run) * (1.0 - smoothstep(reach * 0.4, reach, to_ridge));
}

// The layer's paint at frame point `f` (metres along the eave and up the slope; a caller offsets
// it per piece), `broad` 1 near to 0 where a metre is under a few pixels (the washes fade out):
// x how far it falls toward its shade (the dark washes and the hollows, blue), y how far toward
// its lit (the light washes), z the light's wobble on it (0 to 1: broad dabs, stretched along the
// eave, through a steep step), w its swells (warm white in the light).
vec4 snow_paint(vec2 f, float broad) {
	vec2 sw = p_wash(f, 1.3, 4.2, 0.5, 0.34, 0.45, 41.0);
	float mass = p_n2(vec2(f.x * 0.42, f.y * 0.62), 47.0)
		+ (p_n2(vec2(f.x * 2.2, f.y * 1.4), 48.0) - 0.5) * 0.3;
	float hollow = smoothstep(0.54, 0.7, mass);
	float swell = 1.0 - smoothstep(0.34, 0.48, mass);
	float dab_c = p_n2(f * vec2(1.5, 0.8), 61.0);
	float dab_f = p_n2(f * vec2(5.5, 2.4), 62.0);
	float dabs = smoothstep(0.3, 0.7, dab_c + (dab_f - 0.5) * 0.55);
	return vec4(
		sw.x * 0.3 * broad + hollow * 0.17,
		sw.y * 0.5 * broad,
		clamp(dabs + (sw.y - sw.x) * 0.4, 0.0, 1.0),
		swell);
}

// The body of a layer with no mesh of its own: x how far its shading normal rolls along the fall
// line (toward the eave positive), y the shade of its rounded front and underside (0 to 1), z the
// light on its rounded tops. From metres `to_eave` and `to_ridge` (SNOW_FAR when unknown) and
// frame point `f`: the layer rounds over the eave in a lip (its last 0.4 m turn down, steepest at
// the edge), whose front, the last 0.2 m, falls softly into the blue shade below a lit roll; it
// crests at the ridge in a lit heap (its last 0.45 m turn up toward the other half) and rises and
// falls along the eave in a slow drift, so a slope reads as a thick soft cushion lit on its top.
vec3 snow_roll(float to_eave, float to_ridge, vec2 f) {
	float lip = 1.0 - smoothstep(0.0, 0.4, to_eave);
	float crest = 1.0 - smoothstep(0.0, 0.45, to_ridge);
	float drift = p_n2(vec2(f.x * 0.35, f.y * 0.5), 151.0) - 0.5;
	float roll = lip * lip * 1.9 - crest * crest * 0.9 + drift * 0.8;
	// The lip's front wanders a little along the eave, so its edge is soft and not ruled.
	float front = 0.2 + 0.06 * (p_n2(vec2(f.x * 1.7, 2.0), 152.0) - 0.5);
	float under = 1.0 - smoothstep(front * 0.3, front, to_eave);
	float top = smoothstep(front * 0.7, front * 1.2, to_eave) * (1.0 - smoothstep(front * 1.6, front * 2.6, to_eave));
	float heap = 1.0 - smoothstep(0.04, 0.35, to_ridge);
	return vec3(roll, under, top * 0.35 + heap * 0.3);
}

// The snow's frame on a roof face that has no record, from world point `wp`, the face normal `n`
// and `h` (0 at the eave to 1 at the ridge, linear up the face): x metres along the eave, y metres
// up the slope, z metres down the slope to the eave, w metres up it to the ridge. The metres come
// from the rate h climbs with height on the face (its screen derivatives, exact on a plane), so a
// lip is as wide on a small roof as on a large one; a face where h does not climb (a flat roof)
// has neither edge (SNOW_FAR). Call it outside a branch on per-fragment data (derivatives).
vec4 snow_frame(vec3 wp, vec3 n, float h) {
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float up = max(n.y, 0.3);
	float rise = sqrt(max(1.0 - n.y * n.y, 0.0));
	float k = (abs(dFdx(h)) + abs(dFdy(h))) / max(abs(dFdx(wp.y)) + abs(dFdy(wp.y)), 1e-5);
	bool climbs = k > 0.02 && rise > 0.1;
	float to_eave = climbs ? h / k / rise : SNOW_FAR;
	float to_ridge = climbs ? (1.0 - h) / k / rise : SNOW_FAR;
	// On an upright face (a gable end, snow_foot) the metres up it are its height: the slope's
	// measure is one value over the whole face, and its washes ran as upright stripes.
	float upright = 1.0 - smoothstep(0.04, 0.08, n.y);
	return vec4(dot(wp.xz, across), mix(-dot(wp.xz, down) / up, wp.y, upright), to_eave, to_ridge);
}

// The dark and light (shares of a surface's composed tones) the layer lays where it lies
// (`cover`): its paint (snow_paint `sp`), its rounded front and underside (`under`, a lip's) and
// the light on its rounded tops (`lift`, snow_roll's z; 0 on a blanket mesh, whose shape is lit).
vec2 snow_marks(float cover, vec4 sp, float under, float lift) {
	return vec2(
		(sp.x * (1.0 - under) + under * 0.6) * cover,
		(sp.y * (1.0 - under) + lift) * cover);
}

// The layer's lit tone leans warm on its swells (`swell`, snow_paint's w, times the cover).
vec3 snow_warm(vec3 lit, float swell) {
	return mix(lit, lit * vec3(1.0, 0.975, 0.9), swell * 0.6);
}

// Snow facing the sky is never the deep shade blue: where `sky` (the face's up, 0 under a lip)
// is high its shade takes some of the mid tone, so a shaded slope reads as soft snow and not one
// blue slab (card painter-buildings-fix4).
vec3 snow_sky_shade(vec3 shd, vec3 mid, float sky) {
	return mix(shd, mid, 0.4 * sky * sky);
}
