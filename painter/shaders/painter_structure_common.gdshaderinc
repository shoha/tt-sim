/*
 * What the two painted structure shaders share (painter_structure.gdshader, the A3b look, and
 * painter_structure_manner.gdshader, the hand-drawn manner): which of a material's four sheet
 * ramps a vertex takes from its recipe paint. Their roof snow is painter_snow.gdshaderinc's.
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
	// (6 and 7, a chimney's stack and cap: the stone's ramp, the shader picks among its own.)
	return (pick > 0 && pick < 6) ? roof_tone(c, pick == 2) : 0;
}

// A roof with no manner record follows its recipe's paint (card painter-roofs-ivy: every round and
// Taper roof read one blue-grey, where Classic draws red, brown, purple or pale blue). Its paint
// chooses the nearest role and the role's ramp is turned from the role's reference tone (paint_ref:
// the middle in the mood a paint is read in) to the paint in OKLab: the hue by their difference, the
// chroma and the lightness by their ratios (held to PAINT_CHROMA and PAINT_VALUE), so the mood's
// own moves of the role (grimdark's darker, greyer roofs) carry over and the shade and lit steps
// keep their relation. A paint under PAINT_GREY of chroma keeps its role and its hue, and takes
// only the ratios (a cream felt, a charcoal tile); a roof of a fixed kind (a slate or shingle
// roof: its role is its kind's, so the paint's hue is its only colour cue) turns its hue from
// PAINT_GREY_KIND (an alpine lot's blue-grey shingle, C 0.026, drew brown). The lightness ratio's
// range is wide enough for a pale or a dark paint to land on its own lightness (card
// painter-roof-polish: at 0.82 to 1.22 the crystal spire's pale aqua, 1.45 times its role's,
// drew a darker, more saturated azure), and a tone the ratio lifts past PAINT_KNEE rolls off
// toward white instead of clipping.
const float PAINT_GREY = 0.04;
const float PAINT_GREY_KIND = 0.015;
const vec2 PAINT_CHROMA = vec2(0.5, 2.6);
const vec2 PAINT_VALUE = vec2(0.7, 1.5);
const float PAINT_KNEE = 0.8;

// Whether a roof of `pattern` under pick mode `pick` (a ShaderMaterial's uniforms) follows its
// paint in the A3b shader: a picked tile or wooden roof, and a slate or shingle roof of its kind.
bool paint_turns(int pattern, int pick) {
	return pattern >= 5 && (pick == 1 || pick == 2 || (pick == 0 && (pattern == 6 || pattern == 7)));
}

// The chroma under which a paint is grey to a roof of pick mode `pick` (0 a fixed kind).
float paint_grey(int pick) {
	return pick == 0 ? PAINT_GREY_KIND : PAINT_GREY;
}

// A LINEAR colour in OKLab (L, a, b).
vec3 paint_lab(vec3 c) {
	vec3 lms = vec3(
		0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b,
		0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b,
		0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b);
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(
		0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z,
		1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z,
		0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z);
}

// OKLab back to a LINEAR colour (out of gamut clipped at black).
vec3 paint_linear(vec3 lab) {
	vec3 lms = vec3(
		lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z,
		lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z,
		lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z);
	lms = lms * lms * lms;
	return max(vec3(
		4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
		-1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
		-0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z), vec3(0.0));
}

// The picked roof role (0 clay, 1 slate, 2 shingle, 3 turf) nearest a coloured paint `lab`: red and
// orange the clay, ochre and brown the shingle, green the turf, the rest (blue, violet) the slate.
int paint_roof_tone(vec3 lab) {
	float hue = mod(degrees(atan(lab.z, lab.y)) + 360.0, 360.0);
	if (hue >= 340.0 || hue < 58.0) {
		return 0;
	}
	if (hue < 100.0) {
		return 2;
	}
	return hue < 200.0 ? 3 : 1;
}

// The tone a slate roof of a fixed kind takes by its coloured paint `lab`, among its material's own
// ramps (0 the slate, 1 the moss's leaf, 2 the ridge cap's clay): a red, orange or ochre paint the
// clay, a green or teal the leaf, the rest the slate, so its turn stays small (card
// painter-roof-polish: the slate's ramp turned 146 degrees to a modern row's peach paint drew pink,
// since its lit step is near grey, the sun's yellow pull cancelling the slate's blue).
int paint_slate_tone(vec3 lab) {
	int t = paint_roof_tone(lab);
	return t == 0 || t == 2 ? 2 : (t == 3 ? 1 : 0);
}

// The turn from reference tone `ref` (OKLab) to paint `lab`: (cos, sin) of the hue turn (none for a
// `grey` paint), the chroma ratio and the lightness ratio.
vec4 paint_turn(vec3 lab, vec3 ref, bool grey) {
	float c = length(lab.yz);
	float rc = max(length(ref.yz), 0.005);
	float turn = grey ? 0.0 : atan(lab.z, lab.y) - atan(ref.z, ref.y);
	return vec4(cos(turn), sin(turn), clamp(c / rc, PAINT_CHROMA.x, PAINT_CHROMA.y),
		clamp(lab.x / max(ref.x, 0.05), PAINT_VALUE.x, PAINT_VALUE.y));
}

// A ramp tone `col` (LINEAR) turned by `t` (paint_turn).
vec3 paint_turned(vec3 col, vec4 t) {
	vec3 lab = paint_lab(col);
	vec2 ab = vec2(lab.y * t.x - lab.z * t.y, lab.y * t.y + lab.z * t.x) * t.z;
	float l = lab.x * t.w;
	float over = max(l - PAINT_KNEE, 0.0);
	return paint_linear(vec3(l - over + over / (1.0 + over * 4.0), ab));
}

// (Where a roof lies under snow is painter_snow.gdshaderinc's, shared with the props: card
// painter-roof-snow 2026-11-18 replaced snow_cover's patches and roof_snow_body here.)
