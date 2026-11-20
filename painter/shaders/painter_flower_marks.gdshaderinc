// A flower's bloom as painted marks (card painter-flower-marks; the spike painter-flower-spike's
// option BC). Included by painter_plant.gdshader after painter_selector.gdshaderinc, whose
// bloom_centres, dab_box, petal_role and p_hash it reads.
//
// The model. A core flower's bloom surface is cards: a single head is three crossed cards, a mound
// (PainterFlowerHue.carpet_of) 40 to 65 small ones over its leaves. Drawn as the cards are they
// read at the orbit view as hard-edged coloured pinwheels, and grown to a floor and drawn together
// (the earlier carpet: card painter-flower-carpet) as candy-striped pom-poms, every mound alike.
// Here every head is ONE view-facing mark instead: a six-petal rosette (flower_form), flower-head
// metres wide (never under flower-floor pixels), its crossed twin cards collapsed away (the
// centres texture's flags, PainterFlowerHue.twins_of), a mound's cards each a small mark. A clump
// behaves like one: a share of the heads is left out so the leaves show between (flower-thin), a
// share are small dark buds (flower-bud), the rest vary in size, and a head takes the plant's own
// colour (flower-own) or else the plant's one other, never a random six. A spike (lavender, bells:
// a long dab box) is a chain of florets (spike_form), narrower and as tall as its box.
//
// Far zoom. Small marks lose colour mass: past about zoom 14 they read as speckle, paler than the
// balls they replace (a raised pixel floor alone, 8 px, did not cure it: a third of the heads are
// still left out; measured 2026-11-19). So a mound's marks blend, from flower-far-lo to
// flower-far-hi metres a pixel (the orbit camera only), into one cushion: each grows to a floor of FL_GROW_PX pixels and
// FL_SWELL more, is drawn FL_PULL of the way in to the mound's middle and FL_LIFT up to its top
// card's height, every card present (none thinned, no buds) and shaded low to high as a dome. Its
// rosette's facets keep it a flower, in one hue. Single heads (poppy, daisy) are never pulled.
//
// A pixel's size in metres is 2 / (|projection[1][1]| * viewport height): the world is drawn into a
// viewport whose projection is flipped in y, so [1][1] is negative there and the unsigned form came
// out negative (measured 2026-11-19, card painter-flower-carpet).
uniform float fl_head = 0.11;
uniform float fl_floor = 5.0;
// Thinned share, bud share, own-colour share.
uniform vec3 fl_clump = vec3(0.2, 0.12, 0.85);
// The pixel footprints (m) between which a mound's marks blend into a cushion.
uniform vec2 fl_far = vec2(0.007, 0.013);

// A mark's width is its own scale of the head's width.
const vec2 FL_HEAD_VAR = vec2(0.8, 1.25);
// A clump head's size factor, a bud's size and value.
const vec2 FL_SIZE = vec2(0.7, 1.2);
const float FL_BUD_SIZE = 0.5;
const float FL_BUD_VALUE = 0.8;
// The share of a head's width taken from its card's own dab size (species differ a little).
const float FL_OWN_SIZE = 0.35;
// A spike's width as a share of the head's, its floor as a share of the head's, and the most
// heads tall it stands.
const float FL_SPIKE_WIDTH = 0.55;
const float FL_SPIKE_FLOOR = 0.7;
const float FL_SPIKE_TALL = 4.5;
// Mesh units toward the eye under the orbit camera, so a mark wins the depth test over the leaves
// (core's mound leaves stand to 0.20 to 0.26, their blooms' centres only to 0.10 to 0.13).
const float FL_FRONT = 0.25;
// The cushion: its floor in pixels, its swell, pull toward the middle, lift to the top, its dome's
// shade low and high.
const float FL_GROW_PX = 8.0;
const float FL_SWELL = 0.7;
const float FL_PULL = 0.3;
const float FL_LIFT = 0.8;
const vec2 FL_DOME = vec2(0.82, 1.04);
// A mark's seed (x) and its share of the cushion (y): constant over a card, read by the fragment.
varying flat vec2 v_fl;

// A head whose card box is near round (a spike's long box is a chain of florets).
bool fl_round() {
	float asp = dab_box.w / max(dab_box.z, 0.01);
	return asp > 0.55 && asp < 1.8;
}

// The local `vertex` of card vertex `id` (at `uv`) of a bloom surface, for the view of `inv_view` and
// `projection` on a viewport `viewport` pixels in size. `card` is the card's accent (x, a ROLES
// index) and value (y, a factor); `fl` its seed (x, 0..1) and its share of the cushion (y, 0..1).
vec3 flower_card(
	vec3 vertex, vec2 uv, int id, mat4 model, mat4 inv_view, mat4 projection, vec2 viewport,
	out vec2 card, out vec2 fl
) {
	card = vec2(float(petal_role), 1.0);
	fl = vec2(0.0);
	ivec2 size = textureSize(bloom_centres, 0);
	if (size.x < 256) {
		return vertex;
	}
	int rows = (size.y - 1) / 2;
	ivec2 at = ivec2(id % 256, id / 256);
	vec4 c = texelFetch(bloom_centres, at, 0);
	if (c.w <= 0.0) {
		return vertex;
	}
	bool twin = texelFetch(bloom_centres, at + ivec2(0, rows), 0).r > 0.5;
	vec4 carpet = texelFetch(bloom_centres, ivec2(0, 2 * rows), 0);
	float scale = length(model[1].xyz);
	vec3 plant = floor(model[3].xyz * 10.0);
	vec3 key = floor(c.xyz * 1000.0) + plant;
	float h = p_hash(key);
	float h2 = p_hash(key + 11.0);
	float h3 = p_hash(key + 23.0);
	bool ortho = projection[3][3] != 0.0;
	vec3 wc = (model * vec4(c.xyz, 1.0)).xyz;
	float px = (ortho ? 2.0 : length(inv_view[3].xyz - wc) * 2.0) / (abs(projection[1][1]) * viewport.y);
	// The cushion's share: a mound's, under the orbit camera only (the eye's perspective keeps marks).
	float g = (ortho && carpet.w > 0.5) ? smoothstep(fl_far.x, fl_far.y, px) : 0.0;
	// The colour: the plant's own, or its one other (never the own again).
	float role = float(petal_role);
	if (h2 >= fl_clump.z) {
		role = mod(role + 1.0 + floor(p_hash(plant + vec3(7.0, 13.0, 29.0)) * 4.999), 6.0);
	}
	card = vec2(role, mix(0.9, 1.08, h3));
	// The size: left out (thin, a crossed twin), a bud, or a head of its own size.
	float s = mix(FL_SIZE.x, FL_SIZE.y, p_hash(key + 37.0));
	if (h < fl_clump.x) {
		s = 0.0;
	} else if (h < fl_clump.x + fl_clump.y) {
		s = FL_BUD_SIZE;
		card.y *= FL_BUD_VALUE;
	}
	// In the cushion every card is there at full size, shaded as a dome low to high.
	s = twin ? 0.0 : mix(s, 1.0, g);
	float dome = mix(FL_DOME.x, FL_DOME.y, smoothstep(0.0, 1.0, c.y / max(carpet.y, 0.01)));
	card.y = mix(card.y, dome * mix(0.9, 1.08, h3), g);
	fl = vec2(h3, g);
	// A spike: a chain of florets, a head's half as wide and as tall as its box.
	float head = mix(fl_head * mix(FL_HEAD_VAR.x, FL_HEAD_VAR.y, h3), c.w * scale, FL_OWN_SIZE);
	float floor_px = fl_floor;
	vec2 ext = vec2(1.0);
	if (!fl_round()) {
		head *= FL_SPIKE_WIDTH;
		floor_px *= FL_SPIKE_FLOOR;
		ext.y = mix(clamp(dab_box.w / max(dab_box.z, 0.01), 1.0, FL_SPIKE_TALL), 1.0, g);
	}
	float want = mix(
		max(head, floor_px * px), max(head, FL_GROW_PX * px) * (1.0 + FL_SWELL), g
	) * s;
	mat3 to_local = inverse(mat3(model));
	vec3 right = normalize(to_local * inv_view[0].xyz);
	vec3 up = normalize(to_local * inv_view[1].xyz);
	vec3 front = normalize(to_local * inv_view[2].xyz);
	vec3 pulled = vec3(
		mix(c.x, carpet.x, FL_PULL), mix(c.y, carpet.y, FL_LIFT), mix(c.z, carpet.z, FL_PULL)
	);
	vec3 centre = mix(c.xyz, pulled, g) + (ortho ? front * FL_FRONT : vec3(0.0));
	vec2 d = (uv - dab_box.xy) / max(dab_box.zw, vec2(0.05));
	return centre + (d.x * ext.x * right - d.y * ext.y * up) * (0.5 * want / scale);
}

// The rosette at `uv` (the card's dab box as -1..1): x 1 inside the outline (a six-lobed star,
// notched at 0.55 of the radius), y the plane (-1 the petal's shade half, 1 its lit half, cut down
// the petal's middle), z the centre's share (a disc of 0.25 radius). `seed` turns it.
vec3 flower_form(vec2 uv, float seed) {
	vec2 d = (uv - dab_box.xy) / max(dab_box.zw, vec2(0.05));
	float a = atan(d.y, d.x) + seed * 6.2832;
	float r = length(d);
	float lobe = pow(abs(cos(a * 3.0)), 0.8);
	float edge = mix(0.55, 1.0, lobe);
	float plane = sin(a * 6.0) > 0.0 ? 1.0 : -1.0;
	return vec3(r < edge ? 1.0 : 0.0, plane, 1.0 - smoothstep(0.2, 0.3, r));
}

// A spike's mark at `uv`: a column of five florets narrowing to the tip, each a round blot (x 1
// inside, y the plane by side, z 0).
vec3 spike_form(vec2 uv, float seed) {
	vec2 d = (uv - dab_box.xy) / max(dab_box.zw, vec2(0.05));
	float t = clamp((1.0 - d.y) * 0.5, 0.0, 0.999);
	float k = t * 5.0;
	float cell = floor(k);
	float rad = mix(0.8, 0.45, t);
	vec2 q = vec2((d.x - 0.18 * sin(cell * 2.1 + seed * 6.0)) / rad, (fract(k) - 0.5) * 1.5);
	return vec3(dot(q, q) < 1.0 ? 1.0 : 0.0, q.x > 0.0 ? 1.0 : -1.0, 0.0);
}

// The mark of the card point at `uv` (`fl` the card's v_fl): a rosette, or on a spike's chain of
// florets until its mound has become a cushion (then a rosette too).
vec3 flower_mark(vec2 uv, vec2 fl) {
	return (fl_round() || fl.y > 0.5) ? flower_form(uv, fl.x) : spike_form(uv, fl.x);
}
