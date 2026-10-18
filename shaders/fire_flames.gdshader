shader_type spatial;
// The persistent fire's flames (FireField places them, FireLook draws them and binds the book):
// drawings baked by a small 2D fire simulation (tools/fire_sim/bake_fire_book.py, shipped as
// assets/fire/fire_book.res, FireBook). Each drawing grows out of the last: a lumpy emitter
// feeds a flame scalar that rises on its own heat, curls and burns down, so the tips stretch and
// tear off as pieces that rise, shrink and cool. Round 6 of the reference fit (spike-flipbook
// de7f3d16), its tuning folded into the constants below.
//
// A layer holds what the draw thresholds, not colours: R the flame field (0.5 at the edge), G
// the material's heat (baked from its age, the heat it carries from the inlet, a carried patch
// noise and, for old material, its depth inside its piece), B the sparks (short ovals along the
// flow), A a soft halo. Per pixel: one fetch, the edge thresholded crisp at any size (by the
// field's own screen gradient), and the colour banded on the heat (white-yellow where fresh and
// hot, cream, yellow, then orange and red as patches, licks, tips and pieces). No colour depends
// on the distance to the edge, so the body has no rim. Blended premultiplied, so the halo adds
// light; the orange and red bands glow a little and the sparks bloom under the screen glow.
//
// The book holds sequences of a few emitter widths, sorted into classes (narrow tongue, medium,
// wide mass; class_first gives each class's first sequence). A fire picks its class by its width
// share (the plan's width over its height), and a sequence in the class, a start drawing, a
// mirror, a size and its own height, width and lean by hashing its seed: the plan's per-fire
// seed (the map seed and the lattice point) in INSTANCE_CUSTOM.w, an integer hashed with integer
// arithmetic, so every GPU and every transform draws the same fire and neighbours are never one
// stamp. The quad keeps the tile's texels square (its width follows its height), is tightened to
// the sequence's baked bounds, split into rows (FireLook.ROW_CUTS) and leaned by moving them.
//
// The book's last layer is a tiling tear tile (straight creases and upward ridges) that one more
// fetch reads at TEAR_SCALE repeats across the drawing and adds to the field before the
// threshold (more on old material: the tips and pieces tear most) and a little to the heat (the
// bands' edges tear too); it rises TEAR_TURNS whole tiles a loop, so the loop still closes. The
// drawing's texels a pixel (from f_uv's screen gradient, no fetch) turn the draw to its far form
// over TEAR_FAR: the tear fades to the tile's coarse lumps (its B) at TEAR_FAR_AMP of its weight,
// adding only TEAR_FAR_ADD outside the edge (no island flakes at home), the book is read up to
// FAR_BLUR mips coarser and its colour bands blend over FAR_SOFT more heat, so the drawings'
// colour streaks calm to lobes at the default zoom. The foot lifts the field near the bottom and
// feathers out along a torn line, so no fire stands on a flat card edge. The baked halo shows at
// night (DAY_HALO of it by day), cut at HALO_CUT so the quad's edge never shows; at night the body
// gets an orange over-bright the screen glow blooms into an aura; by day a lone fire's white core
// blooms less (DAY_CORE), a hot merged one as much as at night. The night gate sits below
// sunset's low sun, so sunset gets the day's dim aura. Depth melt against the scene's depth.
//
// Until FireLook binds the book, `drawings` is 0 and every quad collapses: nothing draws.
render_mode unshaded, blend_premul_alpha, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/fire_noise.gdshaderinc"

global uniform vec4 foliage_sun;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear;
// The book (FireLook binds it from FireBook): its layers, each sequence's bounds in the tile's UV
// (left, top, right, bottom), each class's first sequence, the drawings a sequence and the tear
// tile's layer (-1: none).
uniform sampler2DArray flipbook : filter_linear_mipmap, repeat_disable;
uniform vec4 seq_bounds[16];
uniform ivec4 class_first = ivec4(0, 3, 5, 8);
uniform int drawings = 0;
uniform int tear_layer = -1;
// The map's wind (FireLook.wind_for): a direction in world XZ times FireLook.WIND_LEAN.
uniform vec2 wind = vec2(0.25, 0.0);

// The depth melt: how far behind the scene a flame fades out, and how far in front it is whole.
const float PROXIMITY_FADE = 0.35;
const float OCCLUDE_TOLERANCE = 0.25;
// The book's drawings a second (12 drawings a second, a drawing's own rate jittered a little).
const float DRAWING_RATE = 12.0;
const float RATE_JITTER = 0.08;
// The halo's strength and the over-bright the screen glow blooms (shares).
const float HALO_STRENGTH = 1.0;
const float HDR_BOOST = 1.0;
// The age bands: white-yellow to cream, cream to yellow, yellow to orange, orange to red.
const vec4 AGE_STOPS = vec4(0.035, 0.07, 0.14, 0.26);
// The tile's height in flame heights, and the width shares a medium and a wide mass start at
// (the stragglers, below 0.8, take the small lively flames; the fires, 0.9-1.1, and the blaze's
// flames, 1.05, the masses).
const float ROOM = 2.1;
const vec2 CLASS_SHARE = vec2(0.8, 1.0);
// The over-bright the orange and red bands (tips, pieces) and the sparks get, as shares of
// HDR_BOOST.
const float EMBER_GLOW = 0.35;
const float SPARK_GLOW = 1.2;
// How far a flame stands toward the camera (metres, and a share of its half width), so it draws
// over the ground it stands in.
const float TOWARD_CAMERA_M = 0.12;
const float TOWARD_CAMERA = 0.25;
// The tear tile: its repeats across the drawing, its weight on the field (fresh, old material)
// and on the heat, and the whole tiles it rises a loop.
const float TEAR_SCALE = 2.5;
const vec2 TEAR_AMP = vec2(0.1, 0.22);
const float TEAR_HEAT = 0.03;
const float TEAR_TURNS = 2.0;
// The halo's cut, its share by day, the body's orange over-bright at night and a lone fire's
// core bloom by day.
const float HALO_CUT = 0.08;
const float DAY_HALO = 0.2;
const float NIGHT_GLOW = 0.25;
const float DAY_CORE = 0.2;
// Each fire's size range (a share of its plan size).
const vec2 SIZE_JITTER = vec2(0.87, 1.13);
// The drawing's texels a pixel over which the tear turns to its far form (zoom 8 is about
// 0.2-0.6, the default zoom 0.8-1.5), how far it turns to the coarse lumps, its weight there and
// the share of what it adds outside the edge.
const vec2 TEAR_FAR = vec2(0.5, 1.0);
const float TEAR_LUMPS = 1.0;
const float TEAR_FAR_AMP = 0.5;
const float TEAR_FAR_ADD = 0.35;
// The mips the book is read coarser at the far end of TEAR_FAR, and how much softer the colour
// bands blend there (heat units).
const float FAR_BLUR = 1.5;
const float FAR_SOFT = 0.025;
// The night gate on foliage_sun.w (the sun's weight: about 0.01 at the sunset preset's low sun,
// 0 at night).
const vec2 NIGHT_GATE = vec2(0.002, 0.008);
// Each fire's height, width and lean jitter (shares of its height; a hot blaze fire takes them
// whole, any other half).
const vec3 SHAPE_JITTER = vec3(0.25, 0.18, 0.15);
// The tile's height in texels (the drawing's texels a pixel).
const float BOOK_TEXELS = 128.0;
// The flame height (m) at which the tear repeats TEAR_SCALE times across the drawing.
const float TEAR_REF_H = 2.2;
// The tile's width over its height (96 x 128 texels).
const float TILE_ASPECT = 0.75;
// Linear colours: the cream and yellow saturated, so the bodies do not read pastel after the
// tonemap.
const vec3 SIM_WHITE = vec3(1.0, 0.9, 0.55);
const vec3 SIM_CREAM = vec3(1.0, 0.68, 0.2);
const vec3 SIM_YELLOW = vec3(1.0, 0.48, 0.06);
const vec3 SIM_ORANGE = vec3(1.0, 0.22, 0.02);
const vec3 SIM_RED = vec3(0.6, 0.03, 0.015);
const vec3 HALO_COLOUR = vec3(1.0, 0.3, 0.045);
const vec3 HOT_GLOW = vec3(1.0, 0.32, 0.05);
const vec3 SPARK_WHITE = vec3(1.0, 0.95, 0.72);
const vec3 SPARK_GOLD = vec3(1.0, 0.6, 0.16);
const float KIND_SPARK = 1.0;
// The bed temperature at a flame's foot rides in its kind's fraction, scaled by this
// (FireLook.FOOT_SHARE).
const float FOOT_SHARE = 0.99;
// The foot's soft fade (flame heights) so the drawing never ends on a straight cut; it reaches
// higher toward the tile's sides (FOOT_CURVE), so the foot fades as one round bottom; its line
// ragged by the tear (FOOT_RAG flame heights), and the field lifted by up to FOOT_LIFT over the
// bottom FOOT_LIFT_H (the foot's corners round off).
const float FOOT_SOFT = 0.2;
const float FOOT_CURVE = 2.5;
const float FOOT_RAG = 0.14;
const float FOOT_LIFT = 0.18;
const float FOOT_LIFT_H = 0.3;
// The foot's heat over which a fire counts as a hot, merged one.
const vec2 HOT_FROM = vec2(0.35, 0.95);
// The lean: its least share of the wind's when the wind blows along the view, and the most
// (squared rows) a row moves.
const float LEAN_MIN = 0.65;
const float LEAN_REACH = 1.4;
// A spark's rise and drift (metres) over its life, and its lives a second.
const float SPARK_RISE_M = 1.8;
const float SPARK_RATE = 0.45;
const float SPARK_DRIFT_M = 0.45;
// The picks hashed from a fire's seed.
const uint PICK_SEQUENCE = 1u;
const uint PICK_PHASE = 2u;
const uint PICK_MIRROR = 3u;
const uint PICK_TEAR = 4u;
const uint PICK_SIZE = 5u;
const uint PICK_TALL = 6u;
const uint PICK_WIDE = 7u;
const uint PICK_TILT = 8u;
const uint PICK_HOTNESS = 9u;

// (kind, spark life, hot, the fire's tear offset)
varying flat vec4 f_state;
// (hotness, the tear's rise in tear tiles, the tear's repeats across the drawing, layer)
varying flat vec4 f_bands;
// The tile's UV (unmirrored), or a spark's quad UV.
varying vec2 f_uv;

// PCG's integer hash.
uint fire_pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// Pick `k` (0..1) of the fire whose seed is `fire`, in integer arithmetic.
float fire_pick(uint fire, uint k) {
	return float(fire_pcg(fire ^ fire_pcg(k)) >> 8u) * (1.0 / 16777216.0);
}

void vertex() {
	float kind = floor(INSTANCE_CUSTOM.z + 1e-4);
	float foot = clamp((INSTANCE_CUSTOM.z - kind) / FOOT_SHARE, 0.0, 1.0);
	float seed = fract(INSTANCE_CUSTOM.x);
	uint fire = uint(INSTANCE_CUSTOM.w + 0.5);
	float w = length(MODEL_MATRIX[0].xyz);
	float h = length(MODEL_MATRIX[1].xyz);
	float grow = 1.0;
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	up = length(up) > 1e-4 ? normalize(up) : vec2(0.0, 1.0);
	vec2 right = vec2(up.y, -up.x);
	vec2 local = VERTEX.xy + 0.5;
	vec3 centre = (VIEW_MATRIX * vec4(origin, 1.0)).xyz;
	vec4 bands = vec4(0.0);
	float hot = 0.0;
	float clock = 0.0;
	float tear_seed = 0.0;
	vec2 offset;
	if (abs(kind - KIND_SPARK) < 0.5) {
		float life = fract(TIME * SPARK_RATE * (0.7 + 0.6 * fract(seed * 7.1)) + seed * 5.0);
		clock = life;
		vec2 drift = length(wind) > 1e-4 ? normalize(wind) * SPARK_DRIFT_M : vec2(0.0);
		vec3 rise = vec3(drift.x, 0.0, drift.y) * life;
		rise.y = life * SPARK_RISE_M;
		centre = (VIEW_MATRIX * vec4(origin + rise, 1.0)).xyz;
		centre.xy += right * sin(life * 9.0 + seed * 20.0) * 0.08;
		grow *= 1.0 - 0.5 * life;
		offset = (right * VERTEX.x + up * VERTEX.y) * w;
		f_uv = UV;
	} else {
		vec2 wind_view = (VIEW_MATRIX * vec4(wind.x, 0.0, wind.y, 0.0)).xy;
		float across = dot(wind_view, right) / max(length(wind_view), 1e-4);
		float gust = fire_noise(origin.xz * 0.22 - wind * TIME * 2.4);
		float lean_m = (across < 0.0 ? -1.0 : 1.0) * mix(LEAN_MIN, 1.0, abs(across)) * length(wind) * h;
		lean_m *= (0.85 + 0.3 * gust) * (0.9 + 0.2 * fract(seed * 29.3));
		tear_seed = fire_pick(fire, PICK_TEAR);
		grow *= mix(SIZE_JITTER.x, SIZE_JITTER.y, fire_pick(fire, PICK_SIZE));
		// Each fire's own height, width and lean (a blaze row of one height and lean reads as a
		// comb), the most on a hot blaze fire.
		hot = smoothstep(HOT_FROM.x, HOT_FROM.y, foot);
		vec3 jit = SHAPE_JITTER * mix(0.5, 1.0, hot);
		float tall = 1.0 + jit.x * (2.0 * fire_pick(fire, PICK_TALL) - 1.0);
		float wide = 1.0 + jit.y * (2.0 * fire_pick(fire, PICK_WIDE) - 1.0);
		float tilt = jit.z * (2.0 * fire_pick(fire, PICK_TILT) - 1.0) * h;
		float rate = DRAWING_RATE * (1.0 + RATE_JITTER * (2.0 * fract(seed * 13.7) - 1.0));
		float drawing = floor(TIME * rate + seed * 17.0);
		drawing += floor(fire_pick(fire, PICK_PHASE) * float(drawings));
		// The class by the plan's width share (a straggler's single flame is narrow, a fire's
		// mass wide), a sequence in it by the seed.
		float share = w / max(h, 1e-3);
		int klass = share < CLASS_SHARE.x ? 0 : (share < CLASS_SHARE.y ? 1 : 2);
		int first = class_first[klass];
		int count = max(class_first[klass + 1] - first, 1);
		int pick = first + min(int(fire_pick(fire, PICK_SEQUENCE) * float(count)), count - 1);
		int d = int(mod(drawing, float(max(drawings, 1))));
		float layer = float(pick * drawings + d);
		bool mirrored = fire_pick(fire, PICK_MIRROR) < 0.5;
		vec4 b = seq_bounds[pick];
		vec2 span = mirrored ? vec2(1.0 - b.z, 1.0 - b.x) : b.xz;
		float uv_y = mix(b.w, b.y, local.y);
		float v = (1.0 - uv_y) * ROOM;
		float u = mix(span.x, span.y, local.x);
		f_uv = vec2(mirrored ? 1.0 - u : u, uv_y);
		// Square texels: the tile is TILE_ASPECT as wide as it is tall.
		float tile_w = TILE_ASPECT * ROOM * h;
		offset = right * ((u - 0.5) * tile_w * wide + (lean_m + tilt) * min(v * v, LEAN_REACH));
		offset += up * v * h * tall;
		float hotness = mix(-0.04, 0.04, fire_pick(fire, PICK_HOTNESS)) - 0.05 * hot;
		// The tear rises TEAR_TURNS whole tiles over the loop, so drawing 0 meets the last one. Its
		// repeats follow the fire's height, so a small flame tears at the same world size as a big
		// one.
		float repeats = TEAR_SCALE * clamp(h / TEAR_REF_H, 0.45, 1.4);
		bands = vec4(hotness, float(d) / float(max(drawings, 1)) * TEAR_TURNS, repeats, layer);
	}
	f_state = vec4(kind, clock, hot, tear_seed);
	f_bands = bands;
	vec3 at = centre + vec3(offset * grow, TOWARD_CAMERA_M + TOWARD_CAMERA * 0.5 * w);
	// No book bound yet: every corner on one point, so nothing is drawn.
	VERTEX = drawings > 0 ? at : vec3(0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec3 colour;
	float shape;
	vec3 glow = vec3(0.0);
	if (abs(f_state.x - KIND_SPARK) < 0.5) {
		float r = length(f_uv * 2.0 - 1.0);
		float life = f_state.y;
		shape = (1.0 - smoothstep(0.25, 1.0, r)) * (1.0 - smoothstep(0.55, 0.95, life));
		colour = mix(SPARK_WHITE, SPARK_GOLD, smoothstep(0.0, 0.6, r));
		colour = mix(colour, SIM_ORANGE, smoothstep(0.3, 0.9, life));
	} else {
		// The drawing's texels a pixel; past TEAR_FAR.x the draw turns to its far form: the book
		// read up to FAR_BLUR mips coarser and the tear's far form below.
		float rho = max(length(dFdx(f_uv)), length(dFdy(f_uv))) * BOOK_TEXELS;
		float far = smoothstep(TEAR_FAR.x, TEAR_FAR.y, rho);
		vec4 book = texture(flipbook, vec3(f_uv, f_bands.w), FAR_BLUR * far);
		// The tear: one fetch of the book's last layer, wrapped by hand (the array does not
		// repeat) with the unwrapped coordinate's gradients, so its mips stay continuous.
		vec3 tear = vec3(0.0);
		if (tear_layer >= 0) {
			vec2 tuv = f_uv * f_bands.z + vec2(f_state.w * 7.31, f_state.w * 3.77 + f_bands.y);
			vec3 at = vec3(fract(tuv), float(tear_layer));
			tear = textureGrad(flipbook, at, dFdx(tuv), dFdy(tuv)).rgb - 0.5;
		}
		// Far: the coarse lumps, weaker, adding little outside the edge (no island flakes).
		float far_amp = mix(1.0, TEAR_FAR_AMP, far);
		float rag = mix(tear.x, tear.z, far * TEAR_LUMPS);
		rag = (max(rag, 0.0) * mix(1.0, TEAR_FAR_ADD, far) + min(rag, 0.0)) * far_amp;
		float heat_rag = mix(tear.y, tear.z, far * TEAR_LUMPS) * far_amp;
		float old = smoothstep(AGE_STOPS.x, AGE_STOPS.z, book.g);
		float inside = book.r - 0.5 + rag * mix(TEAR_AMP.x, TEAR_AMP.y, old);
		float v = (1.0 - f_uv.y) * ROOM;
		// The foot: the field lifts near the bottom and the feather's line is torn.
		float lift = 1.0 - smoothstep(0.0, FOOT_LIFT_H, v);
		inside -= FOOT_LIFT * lift * lift;
		float px = max(fwidth(inside), 1e-4);
		float across = 2.0 * f_uv.x - 1.0;
		float foot_soft = FOOT_SOFT * (1.0 + FOOT_CURVE * across * across);
		shape = smoothstep(-px, px, inside) * smoothstep(0.0, foot_soft, v + rag * FOOT_RAG);
		float spark = min(book.b * (1.0 + 0.6 * FAR_BLUR * far), 1.0);
		float night = 1.0 - smoothstep(NIGHT_GATE.x, NIGHT_GATE.y, foliage_sun.w);
		float halo = clamp((book.a - HALO_CUT) / (1.0 - HALO_CUT), 0.0, 1.0);
		halo = pow(halo, 1.5) * HALO_STRENGTH * mix(DAY_HALO, 1.0, night);
		if (shape <= 0.0 && spark <= 0.004 && halo <= 0.002) {
			discard;
		}
		// The age, per fire a little hotter or cooler, torn a little; the bands crisp at the
		// pixel's own scale.
		float e = book.g + heat_rag * TEAR_HEAT + f_bands.x;
		// Far, the bands blend softly (crisp band edges along the streaks read as strands at the
		// default zoom); the outline stays crisp.
		float bleed = max(0.008 + FAR_SOFT * far, fwidth(e));
		vec4 s = AGE_STOPS;
		colour = mix(SIM_WHITE, SIM_CREAM, smoothstep(s.x - bleed, s.x + bleed, e));
		colour = mix(colour, SIM_YELLOW, smoothstep(s.y - bleed, s.y + bleed, e));
		colour = mix(colour, SIM_ORANGE, smoothstep(s.z - bleed, s.z + bleed, e));
		float hot_red = smoothstep(s.w - bleed, s.w + bleed, e);
		colour = mix(colour, SIM_RED, hot_red);
		// Only the freshest material (the white-yellow foot and core) blooms; the orange and red
		// (tips, torn pieces) glow a little. By day a lone fire's core blooms less (its cream and
		// yellow stay readable); a hot, merged fire keeps it. At night the body gets an orange
		// over-bright for the aura.
		float core_glow = mix(DAY_CORE, 1.0, max(night, f_state.z));
		colour += HOT_GLOW * HDR_BOOST * core_glow * (1.0 - smoothstep(0.0, 0.4 * s.x, e));
		colour += HOT_GLOW * HDR_BOOST * NIGHT_GLOW * night * (1.0 - smoothstep(s.y, s.z, e));
		float ember = smoothstep(s.z - bleed, s.z + bleed, e) * (1.0 - 0.5 * hot_red);
		colour += SIM_ORANGE * HDR_BOOST * EMBER_GLOW * ember;
		// Sparks over the body or in the air: white-gold, cooler as they fade, bright enough to
		// bloom.
		vec3 spark_colour = mix(SPARK_GOLD, SPARK_WHITE, smoothstep(0.4, 0.9, spark));
		spark_colour *= 1.0 + HDR_BOOST * SPARK_GLOW * smoothstep(0.3, 0.8, spark);
		colour = mix(colour, spark_colour, spark * (1.0 - shape));
		shape = max(shape, smoothstep(0.05, 0.5, spark));
		glow = HALO_COLOUR * halo;
	}
	float depth_tex = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
	behind.xyz /= behind.w;
	float melt = smoothstep(-OCCLUDE_TOLERANCE, PROXIMITY_FADE, VERTEX.z - behind.z);
	float alpha = clamp(shape, 0.0, 1.0) * melt;
	ALBEDO = colour * alpha + glow * (1.0 - alpha) * melt;
	ALPHA = alpha;
}
