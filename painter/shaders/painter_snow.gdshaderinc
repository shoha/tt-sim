/*
 * Roof snow: one model for every painted surface that carries it (card painter-roof-snow,
 * 2026-11-18; owner: "why don't these share an implementation for snow coverage?"). Its users:
 * the hand-drawn manner's blanket mesh (code 10), the roof pieces under it and the round and Taper
 * roofs that have no record (painter_structure_manner.gdshader), the A3b roofs of the street lots,
 * wall rows and boundaries (painter_structure.gdshader) and the up faces of the village props
 * (painter_prop.gdshader).
 *
 * The model. Snow lies as one soft, thick layer, never as patches (owner: "flat splotches",
 * "much patchier"). A face holds it by its slope (snow_hold); where it holds only part, on a steep
 * run, the layer thins into long soft streaks down the fall line, never a half-mixed veil
 * (snow_cover_of); on a roof the layer instead ends at a soft lower edge that rises up a steeper
 * face, so a spire wears a cap of a few uneven drifts over its upper part, heavier on some facets
 * and nearly bare toward the sun (snow_cover_roof, snow_edge). Upright faces hold none (a street
 * roof's tile gables keep a drift along their foot, snow_upright, snow_foot). The layer is drawn in
 * the snow's own ramp with a body:
 *   a lit top    broad soft swells (warm white) and hollows (toward the blue shade), wider along
 *                the eave than down the slope, under a few broad brush washes; the light turns
 *                over a soft step that broad dabs push about, so light and shade break into brush
 *                dabs and not airbrushed gradients (snow_paint);
 *   a round edge where the layer has no mesh of its own, its shading normal rolls over the eave (or
 *                a cap's lower edge, snow_edge_m) in a lip whose last few centimetres are the
 *                underside, the deepest shade, crests at
 *                the ridge and rises and falls in a slow drift (snow_roll); a blanket mesh
 *                carries that shape in its own normals;
 *   the crest    a few short soft gaps along the ridge where the wind scoured it, the roof's own
 *                colour showing as a thin line (snow_gap); no bare strokes anywhere else.
 * Callers pass the snow's frame on their surface (metres along the eave and up the slope, and to
 * the eave and the ridge where known, SNOW_FAR where not; snow_frame finds them on a roof face
 * without a record). Needs painter_noise.gdshaderinc first (p_n2, p_wash). No texture reads.
 */

// A distance to an edge the surface does not know (a prop's top, a flat roof's middle).
const float SNOW_FAR = 99.0;

// The direction toward the sun (xyz) and its weight (FoliageLight): a steep cap thins on the side
// facing it (snow_edge).
global uniform vec4 foliage_sun;

// How much snow a face holds (0 to 1): `snow` the structure snow's switch (1 on, 0 off: no amount
// since card snow-tops-builder; PainterBuildings.snow_switch), `up` the face's normal Y. All of it
// from a moderate pitch, none on a spire's steep run: the law for faces with no snow body.
float snow_hold(float snow, float up) {
	return clamp(snow, 0.0, 1.0) * smoothstep(0.24, 0.42, up);
}

// The layer's cover (0 to 1) where a face holds `hold`, at frame point `f` (metres along the eave,
// up the slope): whole where it holds it all, none where it holds none, and in between long soft
// streaks down the fall line, a dusting caught on a steep run.
float snow_cover_of(float hold, vec2 f) {
	float streak = p_n2(vec2(f.x * 1.6, f.y * 0.3), 141.0);
	return smoothstep(0.4, 0.62, hold + (streak - 0.5) * 0.6);
}

// Where a roof's cover ends down its face (`h` 0 at the eave to 1 at the tip or ridge, as h runs),
// by how much of the layer the face holds (`up` its normal's Y), at frame point `f`, on a face
// whose normal is `n`, of a building whose seed is `seed`: past the eave on a face that holds it
// all, wandering in a few broad soft tongues along the eave; on a steep face (a spire, a Taper
// roof) a cap of a few uneven drifts (card painter-roof-round5, owner on round 3's one regular cap:
// "Rework"; chosen over a high cap with long tongues and a cap with a drift band, probe/
// sheet_caps2): each facet holds its own share (a slow noise of its facing, continuous round a
// cone and one value per face of a Taper roof), the side facing the sun nearly bare, so the roof's
// own colour shows below a painted edge broken round the roof and along each facet.
float snow_edge(float up, vec2 f, vec3 n, float seed) {
	float hold = smoothstep(0.2, 0.44, up);
	float tongue = p_n2(vec2(f.x * 1.3, 5.0), 173.0);
	float sway = p_n2(vec2(f.x * 0.4, 9.0), 174.0);
	float edge = mix(0.55, -0.3, hold) + ((tongue - 0.5) * 0.12 + (sway - 0.5) * 0.1) * hold;
	vec2 face = n.xz / max(length(n.xz), 1e-4);
	float facet = p_n2(face * 1.2 + vec2(seed, seed * 0.7), 191.0);
	vec2 sun = foliage_sun.xz;
	float sunward = length(sun) > 0.01 ? dot(face, normalize(sun)) : 0.0;
	float e1 = p_n2(face * 3.0 + vec2(f.x * 0.9, seed), 193.0);
	float e2 = p_n2(face * 7.0 + vec2(f.x * 1.7, seed + 3.0), 194.0);
	float drifts = (facet - 0.5) * 0.45 + 0.3 * smoothstep(0.0, 0.85, sunward)
		+ (e1 - 0.5) * 0.28 + (e2 - 0.5) * 0.12;
	return edge + (1.0 - hold) * drifts;
}

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

// A roof face's cover (the roof shaders'; the props keep snow_cover_of): one soft layer down to its
// lower edge (snow_edge), whole below a moderate pitch and over the upper part of a steep face, so
// a spire, a Taper roof's cone, a bell or mansard roof's lower run carries a bodied cap of snow
// (card painter-roof-round3, owner on the round towers in winter: "streaky and weird"; the long
// streaks of a half hold and the steep cap's thin ledges are gone). A face near vertical (a slab's
// edge, a finial) or facing down holds none (a street roof's upright faces, snow_upright).
float snow_cover_roof(float snow, float up, float h, vec2 f, vec3 n, float seed) {
	float amount = clamp(snow, 0.0, 1.0) * smoothstep(0.08, 0.16, up);
	float edge = snow_edge(up, f, n, seed);
	return amount * smoothstep(edge - 0.025, edge + 0.025, h);
}

// Metres up the face from a roof cover's lower edge (snow_cover_roof), for its lip: snow_roll's
// `to_eave` where the cover ends above the eave, so a cap rounds over its own edge into the blue
// shade as a blanket does over an eave. `to_eave` snow_frame's z (SNOW_FAR kept).
float snow_edge_m(float up, float h, vec2 f, float to_eave, vec3 n, float seed) {
	float edge = max(snow_edge(up, f, n, seed), 0.0);
	return to_eave >= SNOW_FAR ? SNOW_FAR : max(h - edge, 0.0) * to_eave / max(h, 0.001);
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
