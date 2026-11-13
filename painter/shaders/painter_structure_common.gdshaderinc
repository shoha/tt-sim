/*
 * What the two painted structure shaders share (painter_structure.gdshader, the A3b look, and
 * painter_structure_manner.gdshader, the hand-drawn manner): which of a material's four sheet
 * ramps a vertex takes from its recipe paint, and where a roof lies under snow.
 * Needs painter_noise.gdshaderinc included first.
 */

// The paint (linear RGB) in OKLab's colour plane: (a, b).
vec2 paint_ab(vec3 c) {
	vec3 lms = vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec2(
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

// The sheet roof tone a roof paint chooses (0 clay, 1 slate, 2 shingle, 3 turf: the spike's
// _roof_tone): grey to slate, red-orange to clay, brown to shingle. `woody` never takes clay.
int roof_tone(vec3 c, bool woody) {
	vec2 ab = paint_ab(c);
	float hue = mod(degrees(atan(ab.y, ab.x)) + 360.0, 360.0);
	if (length(ab) < 0.04) {
		return 1;
	}
	if (hue >= 340.0 || hue < 18.0) {
		return 0;
	}
	if (hue < 58.0) {
		return woody ? 2 : 0;
	}
	if (hue < 100.0) {
		return 2;
	}
	return 1;
}

// A door's or shutter's tone by its paint (PainterBuildings.ACCENT_ROLES: 0 timber, 1 clay, 2 turf,
// 3 slate): wood and dull paint stay timber; a red or orange paint takes the clay, a green the
// turf, a blue the slate.
int paint_tone(vec3 c) {
	vec2 ab = paint_ab(c);
	float hue = mod(degrees(atan(ab.y, ab.x)) + 360.0, 360.0);
	if (length(ab) < 0.09) {
		return 0;
	}
	// Orange and ochre paints sit near 70 to 90 degrees in OKLab: still the clay, not the turf.
	if (hue >= 340.0 || hue < 100.0) {
		return 1;
	}
	if (hue < 180.0) {
		return 2;
	}
	return 3;
}

// The tone a vertex of paint `c` takes under pick mode `pick` (0 its own, 1 a tile roof's, 2 a
// wooden roof's, 3 a door's or shutter's).
int tone_of(int pick, vec3 c) {
	if (pick == 3) {
		return paint_tone(c);
	}
	return pick > 0 ? roof_tone(c, pick == 2) : 0;
}

// How much of a roof point lies under snow: `snow` the sheet's share (0 none), `wp` the world
// point, `up` the normal's Y, `h` 0 at the eave to 1 at the ridge. Broad soft drifts, thicker
// toward the ridge, none on a steep run or under the eave.
float snow_cover(float snow, vec3 wp, float up, float h) {
	if (snow <= 0.0) {
		return 0.0;
	}
	float sn = p_noise(wp * 0.45 + 71.0) * 0.6 + p_noise(wp * 1.9 + 13.0) * 0.15 + h * 0.3;
	float edge = 1.0 - snow * 1.05;
	return smoothstep(edge - 0.03, edge + 0.03, sn) * smoothstep(0.3, 0.5, up)
		* smoothstep(0.02, 0.12, h);
}
