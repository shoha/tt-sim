// A painted building a fire burns (card painter-fire; PainterBuildings.take and set_burn; docs/
// systems/painter.md "Fire and events"). Included by painter_structure.gdshader and
// painter_structure_manner.gdshader after painter_noise.gdshaderinc.
//
// The burn is one number a building, an instance uniform on each of its painted parts, on
// FireSweep.burn_progress's scale (0 untouched, about 1.4 charred). Char climbs from the foot: a part
// catches where `burn` passes its height up the part (0 foot .. 1 top) plus a brush noise, then is drawn
// in flat steps, never a ramp: a red ember edge, an orange ember band, then charcoal. Where the burn is
// 0 the branch is not taken, so an untouched building costs a compare.

instance uniform float burn : hint_range(0.0, 3.0) = 0.0;

// How far past catching a point is when the burn has reached it (the ember bands' depth, then char).
const float BURN_EMBER_BAND = 0.34;

// A burnt building's collapse (StructureBurn, StructureCollapse): the burn value runs on past
// BURN_CHARRED (FireSweep.BURN_RATE, where it is fully charred) toward BURN_CHARRED + 1.0 while the
// building comes down in rigid charred pieces (each piece carries the burn as its part does, so it
// starts at the building's char), and the charcoal deepens. Embers glow in seams through it as it breaks
// (two flat bands, a hot orange core in a deep red, along a brush noise), brightest as the slabs fall
// and dying to a low smoulder once they rest (EMBER_SMOULDER of it). EMBER_SEAM is a crack's half
// width in metres at its widest (the red rim; the core under half of it).
const float BURN_CHARRED = 1.7;
const float EMBER_SEAM = 0.09;
const float EMBER_SMOULDER = 0.3;
const float BURN_DEEPEN = 0.3;

// Whether the collapse cuts the point at world `wp`, part height `h` away: never (card
// painter-fire-polish). A cut chunk showed the sky through the roof; the building breaks into pieces
// instead (StructureCollapse). Kept for the structure shaders' call.
bool building_break(vec3 wp, float h) {
	return false;
}

// The ember seams' emission at world `wp` of a collapsing building (burn past BURN_CHARRED). A seam is
// a crack, not a ring (painter-ground-fire-round3: the contour of one smooth noise closed into rings
// on a big slab, like leopard spots): the contour of a two-octave field, its point pushed along by a
// finer noise so the line goes jagged, and its width tapered to nothing by a slow gate, so each line
// opens into a few crack runs that thin out and stop. The width is in metres (the field's distance to
// its contour, by its screen derivatives): cut in field units, a flat stretch of the field swelled a
// line into a broad flame-shaped band (round 2). Called in uniform control flow (burn is the draw's),
// so the derivatives hold.
vec3 building_embers(vec3 wp) {
	float k = clamp(burn - BURN_CHARRED, 0.0, 1.0);
	float glow = smoothstep(0.0, 0.12, k) * (1.0 - (1.0 - EMBER_SMOULDER) * smoothstep(0.5, 1.0, k));
	vec3 q = wp * 0.55 + 23.0;
	// (Round 1 of the card pushed harder and wider, 0.5 at 2.4 per metre with a 0.35 second octave:
	// the lines curled into a tangle of flame-like swirls.)
	q.xz += (p_noise(wp * 3.4 + 7.0) - 0.5) * vec2(0.3, -0.25);
	float field = p_noise(q) * 0.75 + p_noise(q * 2.3 + 11.0) * 0.25;
	float open = smoothstep(0.42, 0.62, p_noise(wp * 0.33 + 61.0));
	float metres = abs(field - 0.5) / max(fwidth(field), 1.0e-5) * length(fwidth(wp));
	float width = EMBER_SEAM * open;
	if (metres < width * 0.45) {
		return vec3(1.0, 0.36, 0.05) * glow;
	}
	return metres < width ? vec3(0.42, 0.06, 0.018) * glow : vec3(0.0);
}

// Lays the burn on the three tones (shade, mid, lit: linear) of the surface at world point `wp`,
// part height `h`; returns the emission of the ember bands.
vec3 building_burn(vec3 wp, float h, inout vec3 shd, inout vec3 mid, inout vec3 lit) {
	if (burn <= 0.0) {
		return vec3(0.0);
	}
	// The seams before any per-pixel branch: they take screen derivatives.
	vec3 embers = burn > BURN_CHARRED ? building_embers(wp) : vec3(0.0);
	float n = p_noise(wp * 0.9 + 41.0);
	float since = burn * 1.1 - (0.75 * h + 0.35 * n);
	if (since <= 0.0) {
		return vec3(0.0);
	}
	if (since >= BURN_EMBER_BAND) {
		// A collapsing building's charcoal darkens on as it comes down (to BURN_DEEPEN less).
		float tone = mix(0.8, 1.2, p_noise(wp * 3.1 + 5.0))
			* (1.0 - BURN_DEEPEN * clamp(burn - BURN_CHARRED, 0.0, 1.0));
		shd = vec3(0.022, 0.017, 0.016) * tone;
		mid = vec3(0.042, 0.032, 0.028) * tone;
		lit = vec3(0.075, 0.056, 0.046) * tone;
		return embers;
	}
	shd = vec3(0.05, 0.02, 0.014);
	mid = vec3(0.11, 0.036, 0.016);
	lit = vec3(0.2, 0.07, 0.025);
	return since < BURN_EMBER_BAND * 0.4 ? vec3(0.9, 0.34, 0.05) : vec3(0.55, 0.1, 0.03);
}
