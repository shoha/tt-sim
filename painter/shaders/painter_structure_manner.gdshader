shader_type spatial;
render_mode cull_back, specular_disabled, ambient_light_disabled;

/*
 * Painted structure with procgen's manner data (the hand-drawn manner, the Painted default)
 * =======================================================================================
 *
 * painter_structure.gdshader (A3b) with the strokes laid along each piece's own frame instead of
 * along the world. PainterMannerMesh writes per vertex the piece's (u, v) metres (UV2) and
 * [u_len, v_len, code, accent] (CUSTOM0; code 1 wall, 2 roof slope, 3 gable end, 4 beam or trim
 * box, 5 door leaf, 6 ridge, 7 thatch tooth, 8 flat roof, 0 no record: the A3b patterns; a
 * wall's course in metres in the code's fraction, a hip face's taper in the accent's whole
 * part). The prototype's stroke families (spike_built3), drawn from the piece frame:
 *   ruled lines just inside each face edge, at least about two pixels wide: the eave dark, the
 *   verges and the ridge pale (the prototype's ruled verge), a wall's corners dark;
 *   a plaster wall: broad dry-brush washes, lighter or darker, each its own length and height,
 *   over a slow drift of value across the wall;
 *   a stone wall: dry-brushed stones (p_stones), crisp and irregular, each its own tone, with a
 *   few dark joint strokes under the courses and beside the stones;
 *   a thatch slope: strokes down the slope with course lines; tiles, slates and shingles: dashes
 *   under each course;
 *   a beam (widened past its recipe width by the mesh): a broad stroke, a light and a dark line
 *   along it and a dark brush rim broken by the dry brush;
 *   a door: plank seams, a wandering grain, a brace stroke, darker at the head;
 *   a thatch tooth: strands and a darker tip.
 * A door or shutter takes the timber ramp, or the clay, turf or slate accent by its paint
 * (pick 3). Winter (`snow` above 0, the sheet's roof-snow, cards painter-roof-snow,
 * painter-buildings-fix and -fix2): a roof slope lies under a blanket mesh (code 10,
 * PainterMannerBlanket: thick in the middle, soft at the edges, its normals carry its shape)
 * painted as the shared snow layer (painter_snow.gdshaderinc, the street lots' and the props'
 * too): broad brush washes, swells and hollows, a soft light broken into dabs, a few soft gaps
 * along the ridge and a blue shade under the eave's lip (the code's fraction); a roof piece under
 * it hides its own marks whole, and a roof with no record wears the layer painted on its face.
 * The other snow strips (code 9, PainterMannerSnow: chimney cushions and collars, sill
 * pads, the lips and caps of a roof without a blanket) take the snow's ramp whole, lit by their
 * own normals, with a slightly darker foot and a blue underside. The light's wobble (and so a light edge or
 * a tree's shadow) follows each piece's strokes: along the courses on a wall, down the fall line
 * on a roof. Light, tones and the uniforms the sheet sets are the A3b shader's
 * (PainterBuildings._tone). Marks fade out with their pixel footprint (far views draw only the
 * wash).
 *
 * MANAGED BY: PainterMannerHost (painter/buildings/manner_host.gd).
 */

#include "res://painter/shaders/painter_noise.gdshaderinc"
#include "res://painter/shaders/painter_structure_common.gdshaderinc"
#include "res://painter/shaders/painter_snow.gdshaderinc"
#include "res://painter/shaders/painter_building_burn.gdshaderinc"

uniform int pattern = 0;
uniform int pick = 0;
uniform vec3 ramps[30];
// A roof's: the OKLab of each ramp's middle tone in the mood a recipe's paint is read in
// (PainterBuildings.paint_refs), what a roof piece with no record turns from to its own paint.
uniform vec3 paint_ref[5];
uniform float snow = 0.0;
uniform vec3 snow_ramp[3];
// False draws winter's roofs without their blanket meshes: every roof takes the shared layer
// painted on its face, as a roof with no record does (an A/B switch, PainterMannerHost.snow_body).
uniform bool snow_body = true;
// The snow body's calm paint (card snow-calm-cells, the owner's pick of spike 8's three: cells;
// owner: "too ripply-swirly", "less oil-slick like"). The body's plan is cut into jittered cells
// (`calm_cell` metres across the wind, longer along it), keyed to the asset's own plan point (v_ap)
// so they ride with it and run on over a ridge or round a cone. Each cell shifts the shared washes
// by its own constant (up to `calm_shift` metres along the eave, 0.45 of it up the slope), turns
// them by up to `calm_turn` radians and takes its own tone (`calm_cell_tone`), so a roof breaks into
// a few soft patches of brushwork that do not line up. Within `calm_edge` (of a cell) of an edge the
// two nearest cells' PAINT is cross-faded (blending their frames sheared the washes into thin
// straight creases, spike 8 round 2). `calm_wash` the washes' strength (1: as snow_paint lays them).
// Tuned from the owner's verdict settings (edge 0.3, turn 0.6, tone 0.35) toward calmer (card
// snow-calm-cells round 1, zoom 16 on the street and low sun): each cell's own tone with a narrow
// edge read as a flat angular plane, and neighbours' washes crossing steeply as crumpled paper;
// so a wider edge (0.5), a smaller tone step (0.22) and a smaller turn (0.4).
uniform float calm_cell = 2.2;
uniform float calm_shift = 1.8;
uniform float calm_edge = 0.5;
uniform float calm_turn = 0.4;
uniform float calm_cell_tone = 0.22;
uniform float calm_wash = 1.35;
uniform float tone_lo = -0.08;
uniform float tone_hi = 0.48;
uniform float cast_amount = 0.94;
uniform float patch_freq = 0.42;
uniform float patch_mix = 0.85;
uniform float dab_freq = 1.1;
uniform float dabs = 0.3;
uniform float dab_wall = 0.45;
uniform float marks = 1.0;
uniform float ink = 0.55;
uniform float contact = 0.4;
uniform float contact_m = 0.8;
uniform float eave = 0.35;

varying vec3 v_wp;
varying vec3 v_wn;
varying float v_h;
varying flat int v_tone;
// Two numbers (0..1) of the building, set per mesh instance by PainterMannerHost.building_seed, so
// a building's walls, roof, door and chimney agree and two houses of one kind do not (card
// painter-look-houses3: three stone houses with one grey wall, one door and one roof). A part
// that is not set takes the middle.
instance uniform vec2 bld = vec2(0.5);
// How far the wind scoured a blanket's crest (snow_gap; 1 on the hand-drawn houses). A wall
// layer's blanket sets 0 (PainterStreetSnow, card painter-roof-round4): its lots lay their slopes in
// one frame each, so the gaps fell at one place on every house of a row, beside its chimney, and
// read as a brown slit (owner, final60) rather than wind.
instance uniform float scour = 1.0;
varying flat vec2 v_bld;
varying vec2 v_fuv;
varying vec4 v_rec;
// A narrow level face's width in metres (CUSTOM1, PainterMannerMesh.FORMAT: the source's UV2.y,
// StructureGeometry.with_ledges; 0 wide or not level).
varying float v_ledge;
// A roof piece with no record (a round or Taper roof): the turn of its ramp to its recipe's paint
// (painter_structure_common's paint_turn); z 0: none.
varying flat vec4 v_turn;
// The point's plan in the mesh's own space (the asset's: a snow body is its child), what the calm
// paint's cells key to.
varying vec2 v_ap;

varying vec3 f_n;
varying vec3 f_shd;
varying vec3 f_mid;
varying vec3 f_lit;
varying float f_wob;
// x: half the width of the light's steps, crisp on paint, a little softer on a roof slope and
// soft on snow (a blanket's light turns); y: how far the wobble moves a cast shadow's edge (a
// wall's is broken into strokes along its courses: a tree's soft shadow on a wall read as pale
// diagonal smears); z: how far it moves the light's steps (half on a roof slope, where a step
// crossing the slope read as a dark blot); w: the light's share under which a point is in cast
// shadow (lower on a roof and its snow, so a twig's thin partial shadow draws no dark mark).
varying vec4 f_tune;
// x: half the width of the cast shadow's edge (a roof's is wide and ragged); y: how much of the
// shade a cast shadow takes (a roof's a tint, not a black shape).
varying vec2 f_cast;

// A wall's share of the variant patches and of the dabs, and its light step's wobble (card
// painter-walls-round3, owner on the grimdark streets: "the walls are still splotchy"): a wall is a
// few broad soft tones, lit or not as a whole face, its weathering at the foot.
const float WALL_PATCHES = 0.55;
const float WALL_DABS = 0.45;
const float WALL_WOBBLE = 0.03;
// The wind in the plan (PainterSnowForms.WIND): the calm paint's cells run longer along it.
const vec2 CALM_WIND = vec2(0.8, 0.6);

// The calm paint. Cell `c`'s frame for slope frame point `f`: the washes turned by up to
// `calm_turn` radians and shifted (metres along the eave and up the slope); z the cell's tone
// (-1 darker to 1 lighter).
vec3 calm_cell_frame(vec2 c, vec2 f) {
	vec2 h = vec2(p_hash(vec3(c, 93.0)), p_hash(vec3(c, 94.0))) * 2.0 - 1.0;
	float a = (p_hash(vec3(c, 95.0)) * 2.0 - 1.0) * calm_turn;
	vec2 r = vec2(cos(a) * f.x - sin(a) * f.y, sin(a) * f.x + cos(a) * f.y);
	return vec3(r + calm_shift * h * vec2(1.0, 0.45), p_hash(vec3(c, 96.0)) * 2.0 - 1.0);
}

// The calm paint's cells at asset plan point `plan`: the nearest cell (`c1`), the second nearest
// (`c2`) and the second's share (0 inside a cell, 0.5 on the edge). A 3x3 search: the jitter (0.7
// of a cell) puts a nearer point outside a 2x2 block, and a 2x2 block's switch at a cell's middle
// would draw a straight seam.
float calm_cells(vec2 plan, out vec2 c1, out vec2 c2) {
	vec2 q = vec2(dot(plan, CALM_WIND) * 0.6, dot(plan, vec2(-CALM_WIND.y, CALM_WIND.x))) / calm_cell;
	vec2 i = floor(q);
	vec2 fq = fract(q);
	float d1 = 9.0;
	float d2 = 9.0;
	c1 = i;
	c2 = i;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 c = i + o;
			vec2 jit = vec2(p_hash(vec3(c, 91.0)), p_hash(vec3(c, 92.0)));
			vec2 dv = o + 0.15 + 0.7 * jit - fq;
			float d = dot(dv, dv);
			if (d < d1) {
				d2 = d1;
				c2 = c1;
				d1 = d;
				c1 = c;
			} else if (d < d2) {
				d2 = d;
				c2 = c;
			}
		}
	}
	return 0.5 * (1.0 - smoothstep(0.0, calm_edge, sqrt(d2) - sqrt(d1)));
}

// The snow body's paint (snow_paint's x, y, z, w) at asset plan point `plan`, slope frame point
// `f`, `broad` as snow_paint's: the shared paint in the nearest cell's frame, cross-faded with the
// second's only inside the edge band (where the second's share passes 1 %: below it the paint's
// step is a few thousandths of a tone), then the washes strengthened and the two cells' tones laid
// on, cross-faded everywhere (one hash).
vec4 calm_paint(vec2 plan, vec2 f, float broad) {
	vec2 c1;
	vec2 c2;
	float k = calm_cells(plan, c1, c2);
	vec3 f1 = calm_cell_frame(c1, f);
	vec4 sp = snow_paint(f1.xy, broad);
	if (k > 0.01) {
		sp = mix(sp, snow_paint(calm_cell_frame(c2, f).xy, broad), k);
	}
	float tone = mix(f1.z, p_hash(vec3(c2, 96.0)) * 2.0 - 1.0, k);
	sp.xy *= calm_wash;
	sp.x += max(-tone, 0.0) * calm_cell_tone;
	sp.y += max(tone, 0.0) * calm_cell_tone * 1.5;
	return sp;
}

void vertex() {
	v_ap = VERTEX.xz;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_h = COLOR.a;
	v_bld = bld;
	v_tone = tone_of(pick, COLOR.rgb);
	if (pick == 3 && v_tone <= 1) {
		// A door or shutter's paint, by building: timber, the clay's red, the slate's blue or the
		// turf's green (the palette's own roles), so a street of one house kind has doors of several
		// colours. A wall's shutters and its door share the building's pick.
		v_tone = v_bld.x < 0.3 ? 0 : (v_bld.x < 0.58 ? 1 : (v_bld.x < 0.8 ? 3 : 2));
	} else if (pick == 2 && v_tone != 0) {
		// A wooden roof (a stone house's): slate, shingle or, now and then, a turfed one.
		v_tone = v_bld.y < 0.4 ? 1 : (v_bld.y < 0.82 ? 2 : 3);
	} else if (pick == 8) {
		// The snow's own material (card painter-look-roofs-winter): a blanket carries its roof's
		// paint in COLOR.rgb and the roof's kind in COLOR.a (eighths: 1 tile, 2 wood, 3 thatch, 4
		// slate, 5 shingle, 6 turf; a strip or cap keeps white, 8), so the snow can take the tone of
		// the roof under it: tinted by roof type and cut away to its ramp. The picks agree with the
		// roof piece's own (a wooden roof's slate, shingle or turf by building).
		int rk = int(COLOR.a * 8.0 + 0.5);
		v_tone = rk == 1 ? roof_tone(COLOR.rgb, false) : (rk == 2 ? roof_tone(COLOR.rgb, true) : (rk == 3 ? 4 : (rk >= 4 && rk <= 6 ? rk - 3 : 0)));
		if (rk == 2 && v_tone != 0) {
			v_tone = v_bld.y < 0.4 ? 1 : (v_bld.y < 0.82 ? 2 : 3);
		}
	}
	v_fuv = UV2;
	v_rec = CUSTOM0;
	v_ledge = CUSTOM1.x;
	v_turn = vec4(1.0, 0.0, 0.0, 1.0);
	if (pattern >= 5 && pick <= 2 && CUSTOM0.z < 0.5) {
		// A roof piece with no record (round and Taper roofs: a roundhouse, a wizard tower's spire,
		// a pagoda; card painter-roofs-ivy, they all read one blue-grey): its colour follows the
		// recipe's roof paint, as Classic's does. A picked roof takes the role nearest the paint,
		// and every roof's ramp is turned from that role's tone to the paint (paint_turn); a grey
		// paint keeps its role's hue and takes only its lightness and greyness (a cream felt yurt,
		// a charcoal pagoda); a roof of a fixed kind turns its hue from a lower chroma (paint_grey),
		// and a slate roof takes the nearest of its own three ramps (paint_slate_tone).
		vec3 lab = paint_lab(COLOR.rgb);
		bool grey = paint_grey(lab, pick);
		if (pick > 0 && !grey) {
			v_tone = paint_roof_tone(lab);
		} else if (pick == 0 && pattern == 6 && !grey) {
			v_tone = paint_slate_tone(lab);
		}
		v_turn = paint_turn(lab, paint_ref[v_tone], grey);
	}
}

// (p_n2 and p_wash, the 2D stroke noise and the broad washes, live in painter_noise.gdshaderinc:
// the shared roof snow paints with them too.)

float p_line(float x, float w) {
	float f = fract(x);
	float d = min(f, 1.0 - f);
	float detail = 1.0 - smoothstep(0.25, 0.6, fwidth(x));
	return (1.0 - smoothstep(w * 0.5, w, d)) * detail;
}

// A band `w` metres wide centred `at` metres along x.
float p_band(float x, float at, float w) {
	return 1.0 - smoothstep(w * 0.35, w * 0.5, abs(x - at));
}

// Short strokes along x in rows `row` metres high: cells about `cell` metres long (each row its
// own length, 0.6 to 1.5 times), `share` of them drawn, each its own width (0.6 to 1.3 times
// `width`) and place in the row, tapered and dry. Returns (dark, light) for the cell's own value.
vec2 p_strokes(vec2 f, float row, float cell, float share, float width, float dark_share, float seed) {
	float r = f.y / row;
	float ri = floor(r);
	float len = cell * mix(0.6, 1.5, p_hash(vec3(ri, seed, 2.0)));
	float x = f.x / len + p_hash(vec3(ri, seed, 1.0)) * 7.0;
	float ci = floor(x);
	float h = p_hash(vec3(ri, ci, seed));
	float h2 = p_hash(vec3(ci, ri, seed + 4.0));
	float fx = fract(x);
	float fy = fract(r) - (h2 - 0.5) * 0.3;
	float w = width * mix(0.6, 1.3, h2);
	float body = smoothstep(0.0, 0.18, fx) * (1.0 - smoothstep(0.72, 1.0, fx));
	body *= 1.0 - smoothstep(w * 0.3, w * 0.5, abs(fy - 0.5));
	float dry = smoothstep(0.25, 0.45, p_n2(vec2(f.x * 7.0, ri * 3.1), seed));
	float on = step(1.0 - share, h) * body * mix(0.35, 1.0, dry);
	float is_dark = step(h, 1.0 - share + share * dark_share);
	return vec2(on * is_dark, on * (1.0 - is_dark));
}

// Dry-brushed stones on a wall frame `f` (metres) in courses `cr` high (`fw` a metre's pixel
// footprint): per course its own stone length (1.4 to 2.4 courses) and offset; per stone a crisp
// shape (each side its own inset, the edge broken by the drag of a dry brush along the course)
// and a tone of its own: about a third darker, a quarter lighter, the rest the wall's. A dark
// joint stroke runs under some stretches of a course and beside some stones. Returns (dark,
// light, a value shift for the stone).
vec3 p_stones(vec2 f, float cr, float fw, float seed) {
	float r = f.y / cr;
	float ri = floor(r);
	float len = cr * mix(1.4, 2.4, p_hash(vec3(ri, seed, 3.0)));
	float x = f.x / len + p_hash(vec3(ri, seed, 1.0)) * 5.0;
	float ci = floor(x);
	float h = p_hash(vec3(ri, ci, seed + 2.0));
	float h2 = p_hash(vec3(ci, ri, seed + 4.0));
	vec2 q = vec2(fract(x) * len, fract(r) * cr);
	float drag = p_n2(vec2(f.x * 4.0, f.y * 18.0), seed);
	float l = 0.02 + 0.06 * h2;
	float rt = 0.02 + 0.06 * fract(h2 * 7.3);
	float b = 0.015 + 0.035 * fract(h * 5.1);
	float t = 0.015 + 0.035 * fract(h * 9.7);
	float edge = min(min(q.x - l, len - rt - q.x), min(q.y - b, cr - t - q.y)) + (drag - 0.5) * 0.05;
	float inside = smoothstep(0.0, max(fw * 1.2, 0.006), edge);
	float dry = mix(0.45, 1.0, smoothstep(0.3, 0.6, drag));
	float dk = inside * dry * smoothstep(0.6, 0.66, h) * mix(0.35, 0.72, fract(h * 13.1));
	float lt = inside * dry * (1.0 - smoothstep(0.26, 0.32, h)) * mix(0.35, 0.65, fract(h * 17.3));
	float jw = max(0.02, fw * 1.6);
	float under = (1.0 - smoothstep(jw * 0.5, jw, q.y)) * step(0.6, p_n2(vec2(f.x * 0.9, ri), seed + 8.0));
	float beside = (1.0 - smoothstep(jw * 0.5, jw, q.x)) * step(0.72, h2);
	float joint = max(under, beside) * mix(0.55, 1.0, drag);
	return vec3(dk + joint * 0.55, lt, (fract(h * 3.7) - 0.5) * inside);
}

// The corner stones of a stone wall frame `f` (`ul` its length, courses `cr` high): from each
// corner a long stone, then a short one, course by course (0.52 and 0.3 m, each its own length),
// paler than the wall, each with a dark joint at its inner end and under it, its edge broken by
// the dry brush (card painter-buildings-fix4: the stone house's corners read ruled). Returns
// (dark, light, a value shift, the share that is corner stone).
vec4 p_quoin(vec2 f, float cr, float ul, float fw, float seed) {
	float r = f.y / cr;
	float ri = floor(r);
	float h = p_hash(vec3(ri, seed, 21.0));
	float len = (mod(ri, 2.0) < 1.0 ? 0.52 : 0.3) * mix(0.8, 1.2, h);
	float cd = min(f.x, ul - f.x);
	float drag = p_n2(vec2(f.x * 4.0, f.y * 18.0), seed + 5.0);
	float w = max(fw * 1.2, 0.006);
	float in_q = 1.0 - smoothstep(len - w, len, cd + (drag - 0.5) * 0.05);
	float qy = fract(r) * cr;
	float jw = max(0.02, fw * 1.6);
	float beside = (1.0 - smoothstep(jw * 0.5, jw, abs(cd + (drag - 0.5) * 0.05 - len)));
	float under = (1.0 - smoothstep(jw * 0.5, jw, qy)) * (1.0 - smoothstep(len, len + 0.06, cd));
	float dry = mix(0.5, 1.0, smoothstep(0.3, 0.6, drag));
	return vec4(max(beside, under) * 0.6 * dry, in_q * 0.32 * dry, (fract(h * 5.3) - 0.5) * 0.5, in_q);
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
	int code = int(floor(v_rec.z + 0.01));
	// A wall's course in metres rides in the code's fraction (0: the pattern's own), a hip face's
	// taper (metres along the eave a metre up the slope) in sixteenths in the accent's whole part.
	float course_m = fract(v_rec.z + 0.01) - 0.01;
	float taper = floor(v_rec.w) / 16.0;
	float acc = fract(v_rec.w);
	vec2 f = v_fuv;
	float ul = v_rec.x;
	float vl = v_rec.y;
	bool on_course = code == 1 || code == 3;
	bool on_slope = code == 2 || code == 8;
	// The dabs' noise and the light's wobble. A piece with a record draws them from its own frame,
	// stretched along its strokes (along the courses on a wall, down the fall line on a roof), so
	// a dab is a brushed patch and a light edge or a tree's shadow breaks into brush marks, never
	// a round blot or a smear; two noises there, so a dab never carries a ring of light (card
	// painter-buildings-fix). A piece with none keeps A3b's one 3D noise for both.
	float bn;
	float wob;
	if (code > 0) {
		vec2 k = on_course ? vec2(0.8, 3.5) : (on_slope ? vec2(0.45, 0.9) : vec2(1.1));
		bn = p_n2(f * k + acc * 13.0, 33.0);
		wob = bn;
		if (on_course || on_slope) {
			// On a roof slope, patches laid along the courses (streaks down the fall line read as
			// grey smears in a tree shadow's penumbra, card painter-buildings-fix2).
			wob = p_n2(f * (on_course ? vec2(1.2, 6.0) : vec2(1.0, 2.2)) + acc * 5.0, 35.0);
			bn += on_slope ? (wob - 0.5) * 0.25 : 0.0;
		}
	} else {
		bn = p_noise(wp * dab_freq + 33.0);
		wob = bn;
	}
	float pn = mix(p_noise(wp * patch_freq + 7.0), bn, 0.3);
	float variant = mix(0.5, smoothstep(0.36, 0.64, pn), patch_mix);
	float dark = 0.0;
	float light = 0.0;
	// How much of the leaf ramp (ramps 6 to 11 of a stone or slate material) lies over the tone:
	// moss climbing a wall from its foot, lichen dabs on stones and slates (card painter-look-houses).
	float moss = 0.0;
	// A slate roof (a tile roof whose paint picks slate too) is laid slate by slate and wears a
	// ridge cap of the clay's ramp (card painter-look-houses2): `cap` the share of the ridge cap,
	// `warm` the share of slates weathered to the shingle's brown; a chimney (pick 6 and 7)
	// takes the stone's ramp (slot 0) or the clay's (slot 12), `pale` the share of its collar.
	bool slate = code == 2 && (pattern == 6 || ((pattern == 5 || pattern == 7) && v_tone == 1));
	float cap = 0.0;
	float warm = 0.0;
	float mauve = 0.0;
	float pale = 0.0;
	// A stone's own shift (the p_stones value, -0.5 to 0.5, where the stones are drawn): it also
	// turns the stone's colour, warm or cool (card painter-look-houses3: a flat khaki-grey wall).
	float stone_z = 0.0;
	int chim_base = 0;
	if (code == 4 && pick >= 6) {
		chim_base = (pick == 7 && ul < 0.5) || (pick == 6 && v_bld.x < 0.42) ? 12 : 0;
	}
	float dab = (pattern >= 5 ? 1.0 : dab_wall * WALL_DABS) * dabs;
	// A roof's dabs are a few subtle brushed patches (blotches read as stains); a slate's fewer. A
	// roof with no record (a round or Taper roof: one broad mass) takes half its variant patches and
	// half its dabs as well (card painter-roofs-ivy: they read blotchy).
	bool loose_roof = code == 0 && pattern >= 5;
	variant = mix(0.5, variant, loose_roof ? 0.5 : (pattern < 5 ? WALL_PATCHES : 1.0));
	float dab_hi = on_slope ? 0.68 : 0.62;
	float dab_lit = on_slope || loose_roof ? 0.5 : 1.0;
	// (A roof's dark dabs are halved, card painter-look-houses3: soft dark blotches read as damp stains.)
	dark += smoothstep(dab_hi, dab_hi + 0.1, bn) * dab * (pattern == 6 ? 0.35 : (on_slope ? 0.5 : 1.0)) * dab_lit;
	light += (1.0 - smoothstep(0.28, 0.38, bn)) * dab * 0.8 * dab_lit;
	vec2 flat_n = n.xz;
	float flat_len = length(flat_n);
	vec2 down = flat_len > 0.02 ? flat_n / flat_len : vec2(0.0, 1.0);
	vec2 across = vec2(-down.y, down.x);
	float up = n.y;
	// The face's own up (its flat normal from the position's derivatives, taken outside every
	// branch), which the snow law asks on a face with no roof: a trim board's smoothed normals tilt
	// up along its whole side, and asked with them the law laid a white stripe down a door jamb
	// (card snow-one-law round 1).
	vec3 face_n = normalize(cross(dFdx(wp), dFdy(wp)));
	float face_up = dot(face_n, n) < 0.0 ? -face_n.y : face_n.y;
	float u = dot(wp.xz, across);
	float h = clamp(v_h, 0.0, 1.0);
	// A metre's pixel footprint on the piece: fine marks fade from 4 cm a pixel, broad ones from
	// 8 cm, the ruled lines from 16 cm; past 30 cm no stroke is drawn at all (far views).
	float fw = length(fwidth(f));
	float detail = 1.0 - smoothstep(0.04, 0.09, fw);
	float broad = 1.0 - smoothstep(0.08, 0.16, fw);
	bool roofy = pattern >= 5;
	if (code > 0) {
		bool flat_roof = code == 8;
		bool wall = code == 1 || code == 3 || (flat_roof && pattern < 5);
		bool face = code == 1 || code == 3 || flat_roof;
		bool roof = code == 2 || (flat_roof && pattern >= 5);
		if (code == 2) {
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
			light += 0.35 * smoothstep(0.82, 1.0, h);
			if (slate) {
				// A slate roof is one painted mass (card painter-look-houses3: a grid of tiles each
				// recoloured, with a dash on every one, read as a quilt). A broad sweep across the
				// plane carries the colour, light to dark and blue to mauve like the clay roofs'
				// orange to crimson; the slates are only suggested: every row a touch of its own
				// value (a stretch of rows, not confetti), each slate barely, a row's foot in
				// soft shade along some of its length, a few slab joints, no mark repeated.
				float sweep = p_n2(f * vec2(0.2, 0.3) + acc * 9.0, 90.0);
				float sweep2 = p_n2(f * vec2(0.5, 0.7) + acc * 5.0, 96.0);
				float blk = 1.0 - smoothstep(0.1, 0.3, fw / 0.26);
				float sr = (f.y + 0.1) / 0.26;
				float rowi = floor(sr);
				float rown = p_hash(vec3(rowi, 5.0, 3.0));
				float sc = f.x / 0.36 + 0.5 * mod(rowi, 2.0) + rown * 0.5;
				float sid = p_hash(vec3(rowi, floor(sc), 17.0 + acc * 9.0));
				variant = clamp(mix(variant, smoothstep(0.22, 0.78, sweep), 0.65) + (rown - 0.5) * 0.16 * blk + (sid - 0.5) * 0.1 * blk, 0.0, 1.0);
				// The sweep: a lit, slightly green-teal end to a deep mauve-blue one (the slate's own
				// ramp has little spread, so value and the clay's rose carry it).
				float sv = smoothstep(0.2, 0.8, sweep);
				light += (1.0 - sv) * 0.5 + smoothstep(0.62, 0.8, sweep2) * 0.1;
				dark += sv * 0.42;
				mauve = smoothstep(0.45, 0.85, sweep) * 0.32;
				// Lichen in a broad patch or two, most along the lower half, and a warm weathered
				// patch of the shingle's brown (a picked roof only) as one wash, not slate by slate.
				moss = smoothstep(0.6, 0.76, p_n2(f * vec2(0.35, 1.1) + acc * 9.0, 64.0)) * 0.24 * (1.0 - 0.6 * h);
				warm = smoothstep(0.7, 0.84, p_n2(f * vec2(0.4, 0.6) + acc * 7.0, 97.0)) * 0.3 * (pick > 0 ? 1.0 : 0.0);
				float rowvis = smoothstep(0.35, 0.62, p_n2(vec2(f.x * 0.45, rowi), 95.0));
				dark += smoothstep(0.76, 1.0, fract(sr)) * 0.17 * blk * rowvis
					+ p_line(sc, 0.06) * step(0.8, sid) * 0.14 * blk;
				light += (1.0 - smoothstep(0.0, 0.12, fract(sr))) * 0.16 * blk * rowvis;
				// The ridge cap: a roll along the ridge (0.27 m down each slope, its lower edge
				// wandering and soft), cut in 0.6 m lengths, a soft shade under it.
				float dr = vl - f.y;
				float edge = 0.4 + (p_n2(vec2(f.x * 2.4, acc * 5.0), 73.0) - 0.5) * 0.14;
				cap = (1.0 - smoothstep(edge - 0.06, edge + 0.05, dr)) * step(0.02, dr);
				dark += p_band(dr, edge + 0.06, 0.12) * 0.3 * step(0.02, dr) + cap * p_line(f.x / 0.6, 0.05) * 0.22;
				light += cap * (1.0 - smoothstep(0.0, 0.09, abs(dr - 0.07))) * 0.3;
			}
		}
		if (code == 1 || code == 3) {
			// The foot's contact shade, its top edge wandering (a hand-drawn base line).
			float hm = h * 16.0;
			float reach = contact_m * (0.55 + 0.9 * p_n2(vec2(f.x * 0.9, acc * 4.0), 12.0));
			dark += contact * (1.0 - smoothstep(reach * 0.25, reach, hm));
			if (pattern == 1) {
				// Moss climbs the stone from its foot in ragged tongues, with a few lichen dabs
				// higher up, so a stone wall has a coloured base and a hand of its own.
				float mn = p_n2(vec2(f.x * 1.7, acc * 6.0), 61.0);
				float climb = 0.22 + 0.55 * mn;
				float tongue = 0.55 + 0.45 * smoothstep(0.35, 0.62, p_n2(f * vec2(5.0, 9.0) + acc * 3.0, 62.0));
				// (small, broken dabs on single stones: a broad one read as a green ink blot)
				float lichen = smoothstep(0.78, 0.9, p_n2(f * vec2(5.5, 7.5) + acc * 7.0, 63.0))
					* smoothstep(0.3, 0.6, p_n2(f * vec2(21.0, 27.0), 65.0)) * 0.45;
				moss = max((1.0 - smoothstep(climb * 0.4, climb, hm)) * tongue, lichen * step(0.3, hm));
			}
		}
		float cr = course_m > 0.05 ? course_m : (pattern == 2 ? 0.3 : (pattern == 3 ? 0.24 : 0.34));
		float block = 0.0;
		if (wall && pattern == 1) {
			// Stone, dry-brushed (p_stones; card painter-buildings-fix: soft blurred blocks read as
			// an upscaled texture): it reads at home zoom and fades when a course is under about
			// three pixels.
			// The courses wander up and down along the wall (up to a fifth of a course), and from
			// each corner the corner stones step long and short (card painter-buildings-fix4: ruled
			// courses and a ruled corner at eye level).
			vec2 fs = vec2(f.x, f.y + (p_n2(vec2(f.x * 0.6, acc * 3.0), 14.0) - 0.5) * cr * 0.4);
			vec3 st = p_stones(fs, cr, fw, 3.0 + acc * 17.0);
			if (code == 1) {
				vec4 q = p_quoin(fs, cr, ul, fw, 5.0 + acc * 11.0);
				st = vec3(st.x * (1.0 - q.w) + q.x, mix(st.y, q.y, q.w), mix(st.z, q.z, q.w));
			}
			block = 1.0 - smoothstep(0.15, 0.35, fw / cr);
			// Where the stones are drawn, they carry the wall's light and dark: the wall's dabs
			// (laid along the courses) read as long pale bands at eye level, so they give way to
			// the stones' own (card painter-buildings-fix3).
			dark += (st.x - smoothstep(dab_hi, dab_hi + 0.1, bn) * dab) * block;
			light += (st.y - (1.0 - smoothstep(0.28, 0.38, bn)) * dab * 0.8) * block;
			variant = clamp(variant + st.z * 0.9 * block, 0.0, 1.0);
			stone_z = st.z * block;
			// A tree's dappled light breaks along the stones: each stone moves the cast edge its
			// own way (pale ovals of light on the wall read as glare, card painter-buildings-fix2).
			wob = mix(wob, 0.5 + st.z * 1.4, block);
		}
		if (fw < 0.3) {
			if (face || code == 2) {
				// The ruled line just inside each edge (a hip face's sides follow its taper),
				// wobbling and broken, never under about three pixels wide or inset less than
				// three.
				// A slate roof's trim is bolder: its verge and ridge lines wider.
				float lw = max(0.03, fw * 1.4);
				float inset = max(0.07, fw * 3.0);
				// Up close a finer wander too, so an edge read at eye level is drawn, not ruled.
				float wob = (p_n2(f * 1.4, acc * 9.0) - 0.5) * 0.06
					+ (p_n2(f * 4.5, acc * 9.0 + 3.0) - 0.5) * 0.05 * detail;
				float dx = min(f.x - taper * f.y, ul - taper * f.y - f.x) / sqrt(1.0 + taper * taper);
				float dy0 = f.y;
				float dy1 = vl - f.y;
				float de = min(dx, min(dy0, dy1));
				float line = 1.0 - smoothstep(lw, lw + max(0.012, fw), abs(de - inset - wob));
				line *= step(0.2, p_n2(vec2((f.x + f.y) * 1.1, acc * 5.0), 2.0));
				line *= 1.0 - smoothstep(0.16, 0.3, fw);
				float at_low = step(dy0, min(dx, dy1));
				float at_high = step(dy1, min(dx, dy0));
				float at_side = 1.0 - at_low - at_high;
				if (code == 2) {
					dark += line * 0.9 * at_low;
					light += line * (0.75 * at_high + 0.6 * at_side) * (slate ? 0.7 : 1.0);
				} else if (code == 3) {
					light += line * 0.55 * (1.0 - at_low);
					dark += line * 0.5 * at_low;
				} else {
					dark += line * 0.45;
				}
			}
			if (wall) {
				if (pattern == 1) {
					// Stone: one broad dry stroke along a course here and there (the stones and
					// their joints are p_stones'), only where the stones are not drawn: a light
					// one read as a pale band along the course (card painter-buildings-fix3).
					vec2 m = p_wash(f, cr, cr * 3.0, 0.3, 0.22, 0.5, 11.0 + acc * 9.0);
					dark += m.x * 0.3 * broad * (1.0 - block * 0.5);
					light += m.y * 0.3 * broad * (1.0 - block);
				} else if (pattern == 2 || pattern == 3) {
					vec2 g = pattern == 2 ? f : f.yx;
					dark += p_line(g.y / cr, 0.12) * step(0.3, p_n2(vec2(g.x * 0.9, floor(g.y / cr)), 4.0)) * 0.55;
				} else {
					// Plaster: broad dry-brush washes, lighter or darker, each its own size, over
					// a slow drift of value across the wall (a stretch lighter, the next darker).
					vec2 m = p_wash(f, 0.85, 2.0, 0.5, 0.26, 0.45, 3.0 + acc * 9.0);
					dark += m.x * 0.4 * broad;
					light += m.y * 0.36 * broad;
					float drift = p_n2(f * vec2(0.45, 0.6) + acc * 7.0, 37.0);
					dark += smoothstep(0.55, 0.8, drift) * 0.22 * broad;
					light += (1.0 - smoothstep(0.2, 0.45, drift)) * 0.2 * broad;
				}
			} else if (roof) {
				if (pattern == 8) {
					vec2 m = p_strokes(f.yx, 0.075, 0.8, 0.42, 0.7, 0.45, 5.0);
					dark += m.x * 0.45 * detail;
					light += m.y * 0.4 * detail;
					for (int c = 1; c <= 3; c++) {
						float at = vl * 0.25 * float(c) + (p_n2(vec2(f.x * 0.8, float(c)), 6.0) - 0.5) * 0.2;
						float band = p_band(f.y, at, 0.06) * step(0.25, p_n2(vec2(f.x * 1.2, float(c)), 8.0));
						dark += band * 0.5 * detail;
					}
				} else if (pattern == 9) {
					vec2 m = p_strokes(f, 0.25, 0.35, 0.35, 0.8, 0.5, 9.0);
					dark += m.x * 0.35 * detail;
					light += m.y * 0.35 * detail;
				} else if (pattern == 6) {
					// Slate: a few long thin ruled dashes, each its own length and place (the
					// prototype's sparse slate lines over its broad blotches).
					vec2 m = p_strokes(f + vec2(0.0, 0.2), 0.48, 1.7, 0.28, 0.16, 0.85, 7.0);
					dark += m.x * 0.6 * broad;
					light += m.y * 0.4 * broad;
				} else if (!slate) {
					float course = pattern == 5 ? 0.42 : 0.26;
					vec2 m = p_strokes(f + vec2(0.0, course * 0.35), course, 0.45, 0.55, 0.22, 0.82, 7.0);
					dark += m.x * 0.6 * detail;
					light += m.y * 0.45 * detail;
				}
			}
			if (code == 4 && pick >= 6) {
				// A chimney (card painter-look-houses2: pale untextured boxes). Its stack (pick 6; the
				// record's u runs up it, so f.x is the height above its foot) is brick or stone by
				// where it stands (its cap and pots stand within a metre of it), laid in staggered
				// bricks by world height, a pale collar a hand below its crown, soot under the cap and
				// a dark foot where it meets the roof; its pots are terracotta, its cap pale stone.
				bool stack = pick == 6;
				float side = 1.0 - smoothstep(0.5, 0.8, abs(n.y));
				float crh = 0.17;
				float row = wp.y / crh;
				float ri = floor(row);
				float bc = dot(wp.xz, vec2(-n.z, n.x)) / 0.36 + 0.5 * mod(ri, 2.0);
				float bid = p_hash(vec3(ri, floor(bc), 31.0 + acc * 7.0));
				float bk = (1.0 - smoothstep(0.1, 0.3, fw / crh)) * side;
				variant = clamp(variant + (bid - 0.5) * 0.9 * bk, 0.0, 1.0);
				dark += (p_line(row, 0.1) * 0.32 + p_line(bc, 0.07) * 0.25 + step(0.86, bid) * 0.15) * bk;
				light += step(bid, 0.12) * 0.2 * bk;
				if (stack && ul > 0.01) {
					float tm = ul - f.x;
					pale = p_band(tm, 0.2, 0.12) * step(0.02, tm);
					dark += p_band(tm, 0.11, 0.05) * 0.45 + (1.0 - smoothstep(0.0, 0.1, tm)) * 0.3
						+ (1.0 - smoothstep(0.0, 0.25, f.x)) * 0.3;
				}
			} else if (code == 4 || code == 6) {
				// A beam: one broad stroke, a light and a dark line along it, and a dark brush
				// rim where the mesh widened it, dragged dry so it breaks.
				float across_b = vl > 0.0 ? f.y / vl : 0.5;
				light += p_band(across_b, 0.66, 0.22) * 0.45 * smoothstep(0.1, 0.3, p_n2(vec2(f.x * 1.5, acc * 7.0), 1.0));
				dark += p_band(across_b, 0.3, 0.2) * 0.4;
				float rim = min(across_b, 1.0 - across_b) + (p_n2(vec2(f.x * 2.6, acc * 3.0), 9.0) - 0.5) * 0.14;
				// Up close a finer wander on the rim and a lighter, wandering outer lip, so the
				// edge the eye follows is the brushed one, not the mesh's straight one (card
				// painter-buildings-fix3: beams read ruler straight at eye level).
				float side = across_b < 0.5 ? 1.0 : 2.0;
				float fine = (p_n2(vec2(f.x * 7.0, side * 5.0 + acc * 3.0), 10.0) - 0.5) * detail;
				// and a slower, wider one (card painter-buildings-fix4: still near straight at eye
				// level): the rim's inner edge, the one the eye follows, swings across a quarter of
				// the beam every half metre or so.
				float slow = (p_n2(vec2(f.x * 2.2, side * 7.0 + acc * 5.0), 12.0) - 0.5) * detail;
				rim += fine * 0.16 + slow * 0.32;
				float lip = (code == 4 ? detail : 0.0)
					* (1.0 - smoothstep(0.0, 0.04 + 0.14 * (fine + slow + 0.5), min(across_b, 1.0 - across_b)));
				dark += (1.0 - smoothstep(0.04, 0.17, rim)) * 0.7 * (code == 4 ? 1.0 : 0.0) * (1.0 - lip);
				light += lip * 0.7;
			} else if (code == 5) {
				// A door: plank seams, a wandering grain, one brace stroke, a darker head.
				float x = f.y + sin(f.x * 4.0 + acc * 20.0) * 0.012;
				dark += p_line(f.y / 0.16, 0.12) * 0.5;
				dark += p_line(x / 0.045, 0.18) * 0.22 * detail;
				float diag = ul > 0.0 && vl > 0.0 ? f.y / vl - f.x / ul : 1.0;
				dark += p_band(diag, 0.0, 0.07) * 0.35 * step(0.3, p_n2(vec2(f.x * 3.0, acc), 3.0));
				dark += smoothstep(0.7, 1.0, ul > 0.0 ? f.x / ul : 0.0) * 0.3;
			} else if (code == 7) {
				// A thatch tooth: strands down it, a darker tip.
				// (Under snow the tip is not darkened: a dark ragged row read as bunting.)
				dark += p_line(f.x / 0.05, 0.3) * 0.4
					+ smoothstep(-0.05, -0.25, f.y) * 0.3 * (1.0 - clamp(snow, 0.0, 1.0));
			}
		}
		if (code == 4 || code == 6) {
			variant = clamp(variant + (acc - 0.5) * 0.6, 0.0, 1.0);
		}
		roofy = roof || code == 6 || code == 7;
	} else {
		// No record: the A3b patterns, unchanged.
		if (pattern >= 5) {
			float tiled = smoothstep(0.25, 0.5, up);
			dark += eave * (1.0 - smoothstep(0.0, 0.16, h));
			light += 0.35 * smoothstep(0.82, 1.0, h) * tiled;
		} else {
			float hm = h * 16.0;
			dark += contact * (1.0 - smoothstep(0.0, contact_m, hm)) * (1.0 - smoothstep(0.6, 0.9, abs(up)));
			if (pattern == 1) {
				float r = wp.y / 0.34;
				float row = floor(r);
				float c = u / 0.62 + 0.5 * mod(row, 2.0) + p_hash(vec3(row, 3.0, 1.0)) * 0.3;
				float blk = p_hash(vec3(row, floor(c), 7.0));
				variant = clamp(variant + (blk - 0.5) * 0.8, 0.0, 1.0);
				dark += max(p_line(r, 0.1), p_line(c, 0.06)) * 0.4;
			}
		}
	}
	bool strip = code == 9;
	if (!strip) {
		dark += smoothstep(0.2, 0.6, length(fwidth(NORMAL))) * ink;
	}
	float cover = 0.0;
	float hide = 0.85;
	float snow_dark = 0.0;
	float snow_light = 0.0;
	float soft = 0.01;
	float swell = 0.0;
	float snow_mark = 0.0;
	// The painted layer's rounded underside on a roof with no record (snow_roll's y).
	float snow_under = 0.0;
	// 1 where the snow law laid the layer (a face with no record), whose shade faces the sky.
	float law_laid = 0.0;
	if (snow > 0.0) {
		// The shared layer's frame on a face with no record (taken here, outside the branches on
		// the piece's code: it reads screen derivatives) and how broad a metre is on it.
		vec4 fr = snow_frame(wp, n, h);
		float fbroad = 1.0 - smoothstep(0.08, 0.16, length(fwidth(fr.xy)));
		// (A roof piece steeper than the law sheds at has no blanket, PainterMannerSnow.ROOF_UP_MIN:
		// it asks the law below, which leaves it bare, card snow-steep-roofs.)
		if (code == 10 || (snow_body && code > 0 && roofy && code != 7 && up >= SNOW_SHED_LO)) {
			// The blanket (code 10, PainterMannerBlanket), or a roof piece under it (its own
			// marks hidden whole: dashes through the snow read as dirt, cards
			// painter-buildings-fix and -fix2): all snow, with broad brush washes, lighter or
			// bluer, laid along the eave, the light turning softly along them; a blanket's shade
			// (the code's fraction) darkens it to blue under the eave's lip. Under them the mass
			// (card painter-buildings-fix3: the middle read flat white): broad soft strokes down
			// the fall line, a hollow blue-white and a swell warm-white, their edges dragged dry,
			// low, so the blanket reads modelled at home zoom without a pattern.
			float under = code == 10 ? clamp(course_m / 0.9, 0.0, 1.0) : 0.0;
			cover = 1.0;
			hide = 1.0;
			// Roof colour through the snow (cards painter-look-houses3 and -roofs-winter: every roof
			// one white slab): the blanket carries its roof's tone (v_tone, from the snow mesh's
			// vertex colour), so where the wind scoured the crest it is drawn in that roof's own
			// ramp. Only there (card painter-roof-snow 2026-11-18, owner: "much patchier"): the
			// shared layer's few short soft gaps along the ridge (snow_gap); the verge stretches,
			// eave strokes, flecks and the veil of thin snow are gone. The roof piece under the
			// blanket stays plain snow.
			// The layer's frame: the slope's own metres, offset per piece by its accent.
			vec2 sf = f + acc * 13.0;
			if (code == 10 && under < 0.05 && up > 0.3) {
				cover = 1.0 - snow_gap(sf, vl - f.y) * step(0.0, vl - f.y) * scour;
			}
			// The shared paint (broad washes, swells and hollows wider along the eave than down the
			// slope, and the dabs that break the light's turn, painter_snow.gdshaderinc) in the calm
			// paint's cells (calm_paint), so a roof is a few soft patches of tone, not one sheet of
			// washes. (The crest gaps and the bare roof's stroke rows keep the slope's own frame.)
			vec4 sp = calm_paint(v_ap, sf, broad);
			swell = sp.w * (1.0 - under);
			vec2 sm = snow_marks(cover, sp, under, 0.0);
			snow_dark = sm.x;
			snow_light = sm.y;
			if (code == 10 && cover < 0.95) {
				// The bare roof's own marks, short dark and light strokes along the eave (the rows of
				// tile, shingle or straw), so a tongue is a painted stretch of roof, not a flat tone.
				vec2 mk = p_strokes(f, 0.2, 0.85, 0.8, 0.6, 0.55, 130.0);
				snow_dark += (1.0 - cover) * mk.x * (v_tone == 1 ? 0.3 : 0.5) * broad;
				snow_mark = (1.0 - cover) * mk.y * 0.4 * broad;
			}
			// (Where the snow is off, the bare roof takes a lift of light: a patch in the blue shade
			// read as a dark olive hole.)
			snow_light = snow_light * cover + (1.0 - cover) * 0.5 + snow_mark;
			swell *= cover;
			// The blanket's rounded shape would read as soft airbrushed gradients, so its light and
			// shade are cut into the layer's broad brush dabs (the wobble shifts where the light
			// turns). (The dry-brush grain of fine streaks is gone, card painter-roof-snow: softer.)
			wob = mix(wob, sp.z, cover);
			// A blanket's light turns over a narrow step (card painter-look-roofs-winter2: a wide one,
			// 0.15, read as a glossy airbrushed sheen, measured); its shape's light and shade break
			// along the dabs above instead.
			soft = 0.06;
		} else if (strip || (snow_body && code == 6)) {
			// A strip (or the ridge beam under a cap): all snow, a slightly darker foot where it
			// sits and a blue underside under a lip's nose.
			cover = 1.0;
			hide = 1.0;
			soft = 0.06;
			snow_dark = strip
				? 0.15 * (1.0 - smoothstep(0.0, 0.6, f.y)) + 0.55 * smoothstep(1.8, 3.0, f.y)
				: 0.0;
		} else if (snow_body && code == 7) {
			// A thatch tooth under the eave's snow (card painter-look-houses: the bare teeth read
			// as a dark row of bunting): the lip's snow runs down its top and breaks into ragged
			// dabs toward the tip, so the eave reads as thatch carrying snow.
			float rag = p_n2(vec2(f.x * 11.0, 4.0), 51.0);
			// The teeth are short stubs under snow (ragged lengths), not dangling points.
			if (f.y < -(0.09 + 0.1 * rag)) {
				discard;
			}
			cover = clamp(1.0 - smoothstep(-0.03, -0.08 - rag * 0.06, f.y), 0.0, 1.0);
			cover = max(cover, 0.5 * smoothstep(0.3, 0.7, rag));
			hide = 0.6;
			soft = 0.06;
		} else if (roofy || snow_hold(snow, face_up) > 0.0) {
			// Every face left with no record: a round or Taper roof, any roof while snow_body is
			// off, a sill, a step, a chimney's top. The shared layer painted on its face
			// (painter_snow.gdshaderinc, as the street lots' A3b roofs), its frame from the face and
			// h, its body in its rolled shading normal. Where it lies is the snow law (card
			// snow-one-law): a roof sheds it above 60 degrees (card snow-steep-roofs: a spire's
			// painted cap read as a smudge), so a spire reads clean in its own colour and a bell
			// roof's flatter flare keeps a few broad soft shapes; any other face takes the law's
			// broad shapes and its rim, and none on a level face narrower than a ledge (snow_ledge: a
			// shutter's batten tops, card snow-one-law round 4).
			vec3 law = snow_law(snow, roofy ? up : face_up, wp, roofy);
			cover = law.x * (roofy ? 1.0 - snow_gap(fr.xy, fr.w) : snow_ledge(v_ledge));
			hide = roofy ? 1.0 : hide;
			vec4 sp = snow_paint(fr.xy, fbroad);
			vec3 roll = roofy
				? snow_roll(fr.z, fr.w, fr.xy)
				: snow_roll(SNOW_FAR, SNOW_FAR, fr.xy);
			roll.y = max(roll.y, law.z);
			vec2 sm = snow_marks(cover, sp, roll.y, roll.z);
			snow_dark = sm.x;
			snow_light = sm.y;
			snow_under = roll.y;
			law_laid = 1.0;
			swell = sp.w * cover;
			wob = mix(wob, sp.z, cover);
			soft = mix(0.01, 0.06, cover);
			n = normalize(n + vec3(down.x, 0.0, down.y) * roll.x * cover);
		}
	}
	dark = clamp(dark * marks * (1.0 - cover * hide) + snow_dark, 0.0, 0.85);
	light = clamp(light * marks * (1.0 - cover * hide) + snow_light, 0.0, 0.8);
	// Each building's own value: its stone lighter or darker, its straw bleached or russet, its
	// tiles a shade apart.
	variant = clamp(variant + (v_bld.y - 0.5) * (pattern == 1 || pattern == 8 ? 0.5 : (pattern == 5 ? 0.2 : 0.0)), 0.0, 1.0);
	int base = (pick >= 6 && pick != 8) ? chim_base : v_tone * 6;
	vec3 shd = mix(ramps[base], ramps[base + 3], variant);
	vec3 mid = mix(ramps[base + 1], ramps[base + 4], variant);
	vec3 lit = mix(ramps[base + 2], ramps[base + 5], variant);
	if (v_turn.z > 0.0) {
		// A round or Taper roof in its recipe's own colour (v_turn, from its paint).
		shd = paint_turned(shd, v_turn);
		mid = paint_turned(mid, v_turn);
		lit = paint_turned(lit, v_turn);
	}
	if (pale > 0.0) {
		// A brick stack's collar is the stone's ramp (slot 0); a stone stack's is lighter.
		int pb = chim_base == 12 ? 0 : 12;
		float pm = chim_base == 12 ? pale : 0.0;
		shd = mix(shd, mix(ramps[pb], ramps[pb + 3], variant), pm);
		mid = mix(mid, mix(ramps[pb + 1], ramps[pb + 4], variant), pm);
		lit = mix(lit, mix(ramps[pb + 2], ramps[pb + 5], variant), pm);
		light = min(light + pale * (chim_base == 12 ? 0.0 : 0.5), 0.8);
	}
	if (cap > 0.0 || warm > 0.0 || mauve > 0.0) {
		// The ridge cap in the clay's ramp (slot 0 of a picked roof, 12 of a plain slate roof's),
		// the weathered slates in the shingle's (slot 12 of a picked roof).
		// (One variant along the whole ridge, and only 0.7 of the clay laid over the slate, so the
		// roll is a warm soft accent of the roof's own colour, not a hard red stripe.)
		float cv = max(cap * 0.75, mauve) * (1.0 - cover);
		int cb = pick > 0 ? 0 : 12;
		shd = mix(shd, mix(ramps[cb], ramps[cb + 3], 0.5), cv);
		mid = mix(mid, mix(ramps[cb + 1], ramps[cb + 4], 0.5), cv);
		lit = mix(lit, mix(ramps[cb + 2], ramps[cb + 5], 0.5), cv);
		float wv = warm * (1.0 - cover) * (1.0 - cap);
		shd = mix(shd, mix(ramps[12], ramps[15], variant), wv);
		mid = mix(mid, mix(ramps[13], ramps[16], variant), wv);
		lit = mix(lit, mix(ramps[14], ramps[17], variant), wv);
	}
	if (moss > 0.0) {
		float m = moss * (1.0 - cover);
		// A stone or slate material keeps the leaf's ramp in slots 6 to 11; a picked roof's moss is
		// its own turf tone (the pick's fourth ramp).
		int mb = pick > 0 ? 18 : 6;
		shd = mix(shd, mix(ramps[mb], ramps[mb + 3], variant), m);
		mid = mix(mid, mix(ramps[mb + 1], ramps[mb + 4], variant), m);
		lit = mix(lit, mix(ramps[mb + 2], ramps[mb + 5], variant), m);
	}
	vec3 snow_tint = vec3(1.0);
	float lay = cover;
	if (code == 10) {
		// The snow takes its roof's tone: a warm cast over clay, thatch and shingle, a cool one over
		// slate and turf.
		snow_tint = v_tone == 0 ? vec3(1.015, 0.985, 0.955) : (v_tone == 1 ? vec3(0.97, 0.99, 1.035) : (v_tone == 2 ? vec3(1.01, 0.985, 0.95) : (v_tone == 3 ? vec3(0.98, 1.01, 0.97) : vec3(1.02, 1.0, 0.93))));
		// Where the roof shows, the winter ramps are lifted a little so a bare stroke is a colour
		// and not a dark slab: the straw (a pale cream) to gold, the slate to a clearer blue, the
		// shingle's brown warmer.
		vec3 bare_tint = v_tone == 4 ? vec3(1.14, 1.04, 0.7) : (v_tone == 1 ? vec3(1.2, 1.42, 1.85) : (v_tone == 2 ? vec3(1.12, 1.08, 1.0) : vec3(1.0)));
		shd *= bare_tint;
		mid *= bare_tint;
		lit *= bare_tint;
	}
	shd = mix(shd, snow_ramp[0] * snow_tint, lay);
	mid = mix(mid, snow_ramp[1] * snow_tint, lay);
	lit = mix(lit, snow_ramp[2] * snow_tint, lay);
	// A stone wall in the shade keeps its stones apart (card painter-look-houses3: winter's shaded
	// stone was one flat khaki-grey): deeper joints, and the paler stones lift further.
	float stony = pattern == 1 && on_course ? 1.0 : 0.0;
	vec3 deep = shd * (0.82 - 0.1 * stony);
	f_shd = mix(mix(shd, deep, dark), mid, light * (0.5 + 0.3 * stony));
	f_mid = mix(mix(mid, shd, dark), lit, light * 0.6);
	f_lit = mix(mix(lit, mid, dark), lit * 1.06, light);
	// Swells of snow and the sunlit stone are warm: a stone wall's light side leans to straw.
	f_lit = snow_warm(f_lit, swell);
	f_lit = mix(f_lit, f_lit * vec3(1.06, 1.0, 0.86), pattern == 1 && on_course ? 0.7 : 0.0);
	float bk = v_bld.x * 2.0 - 1.0;
	if (pattern == 1 && on_course) {
		// Stone has colour (card painter-look-houses3: grey khaki blocks): each stone leans warm
		// sandstone or cool blue-violet, broad washes lean whole stretches, and each building its
		// own way; the sun side warm, the shade cool.
		float sk = p_n2(f * vec2(0.3, 0.45) + acc * 7.0, 83.0);
		float z = clamp(stone_z * 2.0 + (smoothstep(0.45, 0.7, sk) - (1.0 - smoothstep(0.25, 0.5, sk))) * 0.8 + bk * 0.5, -1.2, 1.2);
		f_lit *= vec3(1.0 + 0.08 * z, 1.0 + 0.01 * z, 1.0 - 0.12 * z);
		f_mid *= vec3(1.0 + 0.07 * z, 1.0, 1.0 - 0.1 * z);
		f_shd *= vec3(0.94 + 0.07 * z, 1.0, 1.2 - 0.08 * z);
		if (snow > 0.0) {
			// Winter's stone was the dullest surface (card painter-look-roofs-winter): the low sun
			// lays warm sandstone on its lit faces, and the shade under the snow's blue sky goes
			// blue-violet, so the wall reads as lit stone and not a grey-blue board.
			f_lit *= vec3(1.14, 1.04, 0.84);
			f_mid *= vec3(1.1, 1.01, 0.88);
			f_shd *= vec3(0.9, 0.93, 1.3);
		}
	} else if (slate) {
		// Slate is luminous, not grey: its sun side warm, its body and shade a bluer violet.
		float sc2 = 1.0 - cover;
		f_lit *= mix(vec3(1.0), vec3(1.08, 1.04, 0.96), sc2);
		f_mid *= mix(vec3(1.0), vec3(0.97, 0.98, 1.1), sc2);
		f_shd *= mix(vec3(1.0), vec3(0.95, 0.95, 1.14), sc2);
	} else if (pattern == 8) {
		// Straw: golden to silvery grey by building, the snow's cover left alone.
		float tc = 1.0 - cover;
		float tk = v_bld.y * 2.0 - 1.0;
		vec3 straw = vec3(1.0 + 0.08 * tk, 1.0 + 0.01 * tk, 1.0 - 0.2 * tk);
		f_lit *= mix(vec3(1.0), straw, tc);
		f_mid *= mix(vec3(1.0), straw, tc);
		f_shd *= mix(vec3(1.0), straw, tc);
	}
	if (pattern == 0 && on_course) {
		// Plaster (card painter-look-houses2: a flat lilac-grey): its sun side leans warm and its
		// shade cool, and a few broad washes push each further, a stretch warm as if the light lay
		// on it, the next cool and blue, a colour change across the wall, not a value one.
		float tw = p_n2(f * vec2(0.26, 0.38) + acc * 11.0, 81.0);
		float wm = smoothstep(0.46, 0.72, tw);
		float cl = 1.0 - smoothstep(0.26, 0.52, tw);
		f_lit *= mix(vec3(1.03, 0.995, 0.93), vec3(1.08, 0.985, 0.78), wm);
		f_mid *= mix(mix(vec3(1.0), vec3(1.1, 0.985, 0.82), wm), vec3(0.95, 0.985, 1.06), cl);
		f_shd *= mix(mix(vec3(1.0), vec3(1.16, 0.95, 0.78), wm), vec3(0.88, 0.95, 1.12), cl);
		// Each building's plaster leans its own way, pale and cool to straw and peach.
		vec3 plaster = vec3(1.04 + 0.04 * bk, 1.0, 0.95 - 0.1 * bk);
		f_lit *= plaster;
		f_mid *= plaster * vec3(1.03, 1.0, 0.96);
		// (A wall in shade was a cool grey-pink next to the sunlit cream: its shade leans peach.)
		f_shd *= plaster * vec3(1.08, 1.0, 0.9);
		// The ground's warm bounce lights the foot of the wall (a peach glow in the shade), the sky
		// the upper wall's cool.
		float bounce = 1.0 - smoothstep(0.0, 0.18, h);
		f_shd *= mix(vec3(1.0), vec3(1.14, 0.97, 0.82), bounce);
		f_mid *= mix(vec3(1.0), vec3(1.06, 0.99, 0.9), bounce);
	} else if (pick >= 6 && pick != 8) {
		// A chimney's sun side is warm and its shade cool, the split the stone wall has.
		if (chim_base == 12 && pale < 0.5) {
			// A brick stack keeps its red in the sun: the clay's lit step is a pale cream, so the
			// sunlit face takes the body tone, brightened (card painter-look-houses3: every chimney
			// a pale box).
			f_lit = mix(f_lit, f_mid * vec3(1.14, 1.06, 1.0), 0.7);
		}
		f_lit *= vec3(1.05 + 0.05 * bk, 1.0, 0.89 - 0.06 * bk);
		f_shd *= vec3(0.93, 0.97, 1.07);
	}
	if (code == 10) {
		// Snow facing the sky is never the deep shade blue (snow_sky_shade): a blanket's top in the
		// roof's own shade takes some of the mid tone, its lip's front and underside stay blue.
		float sky = clamp(n.y, 0.0, 1.0) * (1.0 - clamp(course_m / 0.9, 0.0, 1.0));
		f_shd = snow_sky_shade(f_shd, f_mid, sky);
	} else if (law_laid > 0.0 && cover > 0.0) {
		f_shd = mix(f_shd, snow_sky_shade(f_shd, f_mid, clamp(up, 0.0, 1.0) * (1.0 - snow_under)), cover);
	}
	// A varying cannot be an inout argument: the burn works on copies.
	vec3 burn_shd = f_shd;
	vec3 burn_mid = f_mid;
	vec3 burn_lit = f_lit;
	EMISSION = building_burn(wp, clamp(v_h, 0.0, 1.0), burn_shd, burn_mid, burn_lit);
	f_shd = burn_shd;
	f_mid = burn_mid;
	f_lit = burn_lit;
	f_n = n;
	f_wob = wob;
	bool paint_slope = on_slope && cover < 0.5;
	// A tree's shadow on a painted roof is a soft tint with a ragged edge, not a crisp dark shape (card
	// painter-look-houses2: camouflage blotches on the brown roof and the thatch); on a wall a little
	// softer than before.
	f_cast = vec2(paint_slope ? 0.2 : (on_course ? 0.09 : 0.05), paint_slope ? 0.55 : 1.0);
	// A wall's light step turns a little softer and barely wobbles (WALL_WOBBLE), so a face at the
	// step is one even blend and not tan patches over brown (card painter-walls-round3).
	bool wall_face = on_course && !roofy;
	f_tune = vec4(
		paint_slope ? 0.025 : (wall_face ? max(soft, 0.03) : soft),
		on_course ? 0.7 : (on_slope ? 0.45 : (code == 10 ? 0.5 : 0.2)),
		paint_slope ? 0.06 : (code == 10 ? 0.32 : (wall_face ? WALL_WOBBLE : mix(0.12, 0.32, roofy && code == 0 ? cover : 0.0))),
		on_slope || code == 10 ? 0.3 : 0.5);
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 lw = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		float cast = 1.0 - smoothstep(f_tune.w - f_cast.x, f_tune.w + f_cast.x, ATTENUATION + (f_wob - 0.5) * f_tune.y);
		float x = dot(normalize(f_n), lw) + (f_wob - 0.5) * f_tune.z;
		vec3 col = mix(f_shd, f_mid, smoothstep(tone_lo - f_tune.x, tone_lo + f_tune.x, x));
		col = mix(col, f_lit, smoothstep(tone_hi - f_tune.x, tone_hi + f_tune.x, x));
		// (A roof's cast tint is also patchy inside: the brush wobble thins it in places.)
		float dapple = f_cast.y < 0.9 ? mix(0.6, 1.0, smoothstep(0.2, 0.8, f_wob)) : 1.0;
		DIFFUSE_LIGHT += mix(col, f_shd, cast * cast_amount * f_cast.y * dapple);
	}
}
