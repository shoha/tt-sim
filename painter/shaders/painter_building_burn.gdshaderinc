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

// A burnt building's collapse (card painter-structure-fire; StructureBurn): the burn value runs on past
// BURN_CHARRED (FireSweep.BURN_RATE, where it is fully charred) toward BURN_CHARRED + 1.0 while the
// node squashes and sinks, and chunks of its charred parts drop away: a point goes when a brush noise
// (about 1.5 m patches) mixed with its height up the part falls under the share of the way through,
// so the roof's top breaks up first and a few low stumps stay to the end. Only a burning building
// (burn above BURN_CHARRED) takes the branch.
const float BURN_CHARRED = 1.7;
const float BURN_BREAK_CUT = 0.88;

// True where the collapse has dropped the point at world `wp`, part height `h` (0 foot .. 1 top).
bool building_break(vec3 wp, float h) {
	if (burn <= BURN_CHARRED) {
		return false;
	}
	float cut = clamp(burn - BURN_CHARRED, 0.0, 1.0) * BURN_BREAK_CUT;
	float keep = 0.6 * p_noise(wp * 0.65 + 17.0) + 0.4 * (1.0 - h);
	return keep < cut;
}

// Lays the burn on the three tones (shade, mid, lit: linear) of the surface at world point `wp`,
// part height `h`; returns the emission of the ember bands.
vec3 building_burn(vec3 wp, float h, inout vec3 shd, inout vec3 mid, inout vec3 lit) {
	if (burn <= 0.0) {
		return vec3(0.0);
	}
	float n = p_noise(wp * 0.9 + 41.0);
	float since = burn * 1.1 - (0.75 * h + 0.35 * n);
	if (since <= 0.0) {
		return vec3(0.0);
	}
	if (since >= BURN_EMBER_BAND) {
		float tone = mix(0.8, 1.2, p_noise(wp * 3.1 + 5.0));
		shd = vec3(0.022, 0.017, 0.016) * tone;
		mid = vec3(0.042, 0.032, 0.028) * tone;
		lit = vec3(0.075, 0.056, 0.046) * tone;
		return vec3(0.0);
	}
	shd = vec3(0.05, 0.02, 0.014);
	mid = vec3(0.11, 0.036, 0.016);
	lit = vec3(0.2, 0.07, 0.025);
	return since < BURN_EMBER_BAND * 0.4 ? vec3(0.9, 0.34, 0.05) : vec3(0.55, 0.1, 0.03);
}
