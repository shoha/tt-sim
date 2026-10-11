shader_type spatial;
// A fire's smoke (SmokePuffs): a billow is a smoke crown, built the way a tree's crown is
// (wind_foliage.gdshader's leaf cards): a mesh of small cards, each turned here to face the
// camera about its own centre, each drawing one painted puff with a crisp cut-out outline. The
// cards fill a low dome, large in the middle and small at the rim, so the billow's outline is
// broken like a crown's, not a smooth ball.
//
// Its light is the crowns' read: every card carries the crown's volume normal (from the dome's
// heart out through the card), tipped a little by the puff's own roundness and the fire's
// noise, and the sun lights it through a two-tone step (a lit side and a shade side the sky
// fills, held down and warmed by a fill of the smoke's own colour), so the billow has a
// luminous lit flank and a warm grey shade side in patches, card by card.
//
// Opaque with an antialiased edge (alpha scissor with alpha to coverage, as the foliage cards
// are), it thins by erosion, never by fading: the fire's one rule (fire_noise.gdshaderinc) eats
// the cards' edges with a noise laid across the whole billow, and each card's rank (the rim's
// first) takes whole cards out, so an old billow breaks into a few puffs and is gone by about
// ERODE_DONE of its life.
//
// Its palette runs on from the flames' (event_puff.gdshader): a warm dark charcoal-brown with
// an ember glow at its foot while young and close to the fire, paling to a pale neutral grey as
// it rises and ages. INSTANCE_CUSTOM: x the seed, z its age (0..1). Card attributes: VERTEX the
// card's centre, UV its corner, UV2 its half-size and rank, COLOR.r its draw. Colours are
// linear and shown through the filmic tonemap (FireSweep's header).
render_mode skip_vertex_transform, cull_disabled, depth_draw_opaque, specular_disabled, alpha_to_coverage;

#include "res://shaders/fire_noise.gdshaderinc"

// Young smoke close to the fire, and its old body.
const vec3 SMOKE_DARK = vec3(0.05, 0.036, 0.026);
// A pale neutral grey, high enough to read luminous beside the crowns' lit sides (at 0.47 it
// read as grey cut paper). The sun's colour reaches it at SUN_TINT only: an afternoon sun at
// full colour turned a cool grey's lit side a pink-mauve (measured 175, 161, 159 in the raw
// frame), so the smoke takes the sun's brightness and a small share of its warmth.
const vec3 SMOKE_PALE = vec3(0.6, 0.6, 0.58);
const float SUN_TINT = 0.2;
// The shade side: the sky's blue fill held down (SHADE_AO, ambient only) and a warm neutral
// fill of the smoke's own colour in its place (SHADE_FILL, emission), so the shade reads a warm
// grey rather than slate blue.
const float SHADE_AO = 0.5;
const vec3 SHADE_FILL = vec3(0.2, 0.185, 0.16);
// The fire's underlight on young smoke: its colour, strength and the share of the billow's life
// it lasts.
const vec3 SMOKE_GLOW = vec3(0.9, 0.22, 0.03);
const float GLOW_STRENGTH = 0.5;
const float GLOW_LIFE = 0.18;
// A card's painted tones (dark patch, body, light patch) and where the noise steps between
// them.
const vec3 PAINT_TONES = vec3(0.64, 0.92, 1.12);
// (The dark step at 0.38 on a noise at corner * 1.6 left small round dark spots, fire-look-6:
// 0.34 on a broader noise keeps the dark tone to a few larger patches.)
const vec2 PAINT_STEPS = vec2(0.34, 0.62);
// The two-tone step: lit from where the wrapped light crosses RAMP.x to RAMP.y.
const vec2 RAMP = vec2(0.46, 0.54);
// The erosion starts this far through a billow's life and is done by ERODE_DONE.
const float ERODE_FROM = 0.3;
const float ERODE_DONE = 0.8;
// How far the cards open out from the crown's heart by its end, and how much they grow.
const float OPEN = 0.35;
const float SWELL = 0.15;
// The dome's heart its volume normals leave from (the crown's unit), and how much the puff's
// own roundness and the noise tip a card's normal.
const vec3 HEART = vec3(0.0, -0.12, 0.0);
const float ROUND = 0.8;
const float TIP = 0.35;

varying vec2 corner;
varying vec3 crown_at;
varying float card_rank;
varying float card_draw;
varying float puff_seed;
varying float puff_age;

void vertex() {
	puff_seed = INSTANCE_CUSTOM.x;
	puff_age = INSTANCE_CUSTOM.z;
	crown_at = VERTEX;
	card_rank = UV2.y;
	card_draw = COLOR.r;
	corner = UV * 2.0 - 1.0;
	float scale = length(MODEL_MATRIX[0].xyz);
	vec3 centre = (MODELVIEW_MATRIX * vec4(VERTEX * (1.0 + OPEN * puff_age), 1.0)).xyz;
	float half_size = UV2.x * (1.0 + SWELL * puff_age) * scale;
	VERTEX = centre + vec3(corner * half_size, 0.0);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(crown_at - HEART, 0.0)).xyz);
}

void fragment() {
	// The painted puff: a disc broken into a few lobes by its own noise, as a leaf card's
	// outline is broken.
	float r = length(corner);
	float lump = fire_cloud(corner * 2.3 + card_draw * 17.0 + puff_seed * 5.0);
	// Held inside the card, so no lobe is cut straight by its edge.
	float field = min(0.66 - r + (lump - 0.5) * 0.7, 0.94 - max(abs(corner.x), abs(corner.y)));
	// The erosion: one noise across the billow, so the cards break up together in bold pieces,
	// the card's rank taking whole cards out as it goes.
	float age = min(puff_age / ERODE_DONE, 1.0) * 0.9;
	vec2 across = crown_at.xy * 4.0 + vec2(crown_at.z * 2.3, 0.0) + corner * 0.25;
	float cloud = fire_cloud(across + puff_seed * 13.0 + vec2(0.0, -puff_age * 0.6));
	float taken = card_rank * 1.2 * smoothstep(ERODE_FROM, 0.6, age);
	ALPHA = fire_cut(fire_erode(field - taken, cloud, age, ERODE_FROM));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	// The crown's normal, rounded over the puff and tipped by the noise.
	vec3 round = vec3(corner / 0.75, sqrt(max(1.0 - dot(corner, corner) / 0.56, 0.0)));
	vec2 tip = vec2(fire_noise(corner * 2.0 + card_draw * 9.0), fire_noise(corner * 2.0 + 3.7)) - 0.5;
	NORMAL = normalize(NORMAL + round * ROUND + vec3(tip * TIP, 0.0));
	// The palette over its life (its top a little ahead of its foot), painted patches inside
	// each puff and a tone of its own for each card, so the crown reads as many pieces.
	float high = crown_at.y / 0.27;
	float pale = smoothstep(0.05, 0.6, puff_age + 0.12 * high);
	// Three tones a card, bold soft-edged shapes as a leaf card's paint is: a dark patch, the
	// body and a light patch, stepped by one broad noise (a two-tone patch from 0.82 to 1.06
	// read as smooth grey discs, fire-look-5).
	float shapes = fire_cloud(corner * 1.3 + card_draw * 31.0 + puff_seed * 3.0);
	float body = smoothstep(PAINT_STEPS.x - 0.05, PAINT_STEPS.x + 0.05, shapes);
	float bright = smoothstep(PAINT_STEPS.y - 0.05, PAINT_STEPS.y + 0.05, shapes);
	float paint = (PAINT_TONES.x + (PAINT_TONES.y - PAINT_TONES.x) * body
		+ (PAINT_TONES.z - PAINT_TONES.y) * bright) * mix(0.9, 1.06, fract(card_draw * 7.3));
	ALBEDO = mix(SMOKE_DARK, SMOKE_PALE, pale) * paint;
	AO = SHADE_AO;
	// The fire's light under the young smoke: a thin warm underlight on the lowest cards'
	// undersides only, gone early in its life (whole cards glowing tan read as orange leaves
	// beside a burning crown).
	float young = 1.0 - smoothstep(0.0, GLOW_LIFE, puff_age);
	// Broken into a few warm patches by the puff's own lump noise and the card's draw (one
	// even band along every low card read as a straight line, fire-look-6).
	float patches = smoothstep(0.5, 0.6, lump) * step(0.45, fract(card_draw * 5.3));
	float glow = young * smoothstep(-0.25, -0.55, high) * smoothstep(-0.1, -0.7, corner.y) * patches;
	EMISSION = SMOKE_GLOW * glow * GLOW_STRENGTH + ALBEDO * SHADE_FILL;
}

// The crowns' two-tone read: a lit side and a shade side with a short step.
void light() {
	float wrapped = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = smoothstep(RAMP.x, RAMP.y, wrapped);
	vec3 sun = mix(vec3(dot(LIGHT_COLOR, vec3(0.3333))), LIGHT_COLOR, SUN_TINT);
	DIFFUSE_LIGHT += lit * ATTENUATION * sun / PI;
}
