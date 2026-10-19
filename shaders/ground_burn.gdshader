shader_type spatial;
// The fire on the ground (GroundBurn): a box over the burning stand that paints the ground seen
// through it, read back from the depth buffer (the grid overlay's way), so the burn is a field
// laid on the map rather than a texture stretched over it, and it moves.
//
// The front is a level line of the fire's noise, not a circle: a point burns once the front's
// radius passes its reach (its distance from the centre pulled in or pushed out by the lobe
// field, GroundBurn.reach, the same texture the tongues and the trees are timed by), so lobes
// run ahead and bays lag behind as the front grows, and a finer noise rags its edge. Ahead of it
// the grass dries in a soft mottled band (green, straw, brown); on it a hot band of varying
// width burns in the flames' stepped colours (deep red outside, orange, gold in its hottest
// patches), broken into segments that crawl; behind it the ground is charred, with ash
// blotches, a deep red smoulder in broad patches and glowing specks that pulse and cool as the
// front leaves them. The grass tufts and a trunk's foot (steep faces standing low) take the same
// paint, so the edge is in the vegetation too: straw tufts ahead, flame-lit tufts on the band,
// black tufts behind (green tufts on the char read as the fakest thing in the frame,
// fire-look-7).
//
// Colours are the ground's own light reworked (the opaque frame under it), so the char and the
// dry grass keep the sun and shade they lie in: dry and charred ground are the frame's
// brightness times a tint, the glow is added. Drawn first among the transparent passes (below
// the water's priority), so nothing drawn later is painted over. Linear colours, shown through
// the filmic tonemap (FireSweep's header).
//
// Along a path (path_count of 2 or more, GroundBurn.setup_path) the front runs along the line:
// a point's reach is its arc length to the nearest point of the path, lobed the same way, and
// past the path's half-width (lobed too) it does not burn, so the same dry band and ragged
// edge run along both sides and round both ends. The ground's height there is the line's,
// so a long path over a slope keeps to the ground.
//
// Its noise is glow_noise's integer hash (card F4b-5): fire_noise's float hash, at the inputs
// the fire's offset gives here (up to about 90), hashed a lattice point differently from the
// cells either side of it, so the specks, the smoulder and the band's breaks came out as
// straight-edged cells and slivers along the map's axes instead of round blobs.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_front, fog_disabled;

#include "res://shaders/fire_glow_noise.gdshaderinc"

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
// The lobe field (GroundBurn.lobe_texture): the fire's noise, painted once, wrapping.
uniform sampler2D lobe_texture : filter_linear, repeat_enable;
// The front's radius (metres, the box's frame), the lobe field's reach and scale (metres), its
// offset for this fire and period (noise units), the event's clock, the glow (0..1), the whole
// burn's fade (0..1) and the box's half height (metres).
uniform float front = 1.0;
uniform float lobe_m = 2.0;
uniform float lobe_scale = 3.0;
uniform vec2 lobe_offset = vec2(0.0);
uniform float lobe_period = 8.0;
uniform float elapsed = 0.0;
uniform float glow = 0.0;
uniform float fade = 1.0;
uniform float half_height = 1.5;
// How far the char has drifted toward the landed ash's colour while it is held (GroundBurn
// ashen_at), 0..1.
uniform float ashen = 0.0;
// A path: its points in the fire's frame (x, z metres from its first point; z holds the arc
// length there, w the ground's height in the box's frame), how many there are (0: a circle),
// its half-width, and where the box's centre lies in the fire's frame.
uniform vec4 path_points[64];
uniform int path_count = 0;
uniform float path_width = 1.0;
uniform vec2 frame_offset = vec2(0.0);

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
// The ragged edge: a finer noise (blobs this many metres across) moving the front this far.
const float RAG_BLOB_M = 0.6;
const float RAG_M = 0.5;
// Steep faces lower than this (metres over the stand's ground) are painted with the ground (at
// 0.7 m the taller tufts' tops stayed green on the char).
const float LOW_M = 1.0;
// The hot band's width (metres, scaled 0.45..1.55 by its noise; at 0.9-1.2 m it lay on bare
// ground as a glossy lava stripe), where its noise breaks it (higher, more gaps), and the dry
// band's width.
const float HOT_M = 0.7;
const float GAPS = 0.55;
const float SCORCH_M = 2.2;
// How far behind the band the specks and the smoulder have cooled (metres, e-folding), and how
// bright the smoulder glows (at 0.7 over 1 m the char read as molten).
const float SPECK_FADE_M = 1.6;
const float SMOULDER_FADE_M = 0.6;
const float SMOULDER = 0.35;
// The flames' stepped bands and the ember glow (linear, added), and how bright they burn.
const vec3 HOT_RED = vec3(0.55, 0.03, 0.005);
const vec3 HOT_ORANGE = vec3(1.0, 0.2, 0.012);
const vec3 HOT_GOLD = vec3(1.0, 0.45, 0.06);
const vec3 EMBER = vec3(0.75, 0.1, 0.01);
const float ENERGY = 2.0;
// Ground tints over the frame's brightness: char (warm near-black), ash blotches, and the
// drying grass (olive straw, straw, brown, scorched).
const vec3 CHAR_TINT = vec3(0.3, 0.24, 0.21);
const vec3 ASH_TINT = vec3(0.62, 0.58, 0.55);
// The landed ash surface's warm grey over the frame's brightness, which a held char drifts to.
const vec3 ASH_LANDED = vec3(0.78, 0.64, 0.5);
const vec3 OLIVE = vec3(1.15, 1.08, 0.4);
const vec3 STRAW = vec3(1.75, 1.25, 0.4);
const vec3 BROWN = vec3(1.05, 0.6, 0.28);
const vec3 SCORCHED = vec3(0.55, 0.34, 0.2);

// The lobe field at map point `p` (the box's frame), 0..1, bilinear like GroundBurn.lobe_at.
float lobes(vec2 p) {
	return texture(lobe_texture, (p / lobe_scale + lobe_offset) / lobe_period).r;
}

// A soft step between two tones, about a tenth wide: the paint's bold, soft-edged shapes.
float tone(float edge, float v) {
	return smoothstep(edge - 0.05, edge + 0.05, v);
}

// The path's point nearest `p` (the fire's frame): x its arc length, y the distance to it, z
// the ground's height there (FirePath.project).
vec3 along_path(vec2 p) {
	float best = 1e12;
	vec3 on_line = vec3(0.0);
	for (int i = 0; i < path_count - 1; i++) {
		vec4 a = path_points[i];
		vec4 c = path_points[i + 1];
		vec2 ab = c.xy - a.xy;
		float t = clamp(dot(p - a.xy, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		vec2 q = p - a.xy - ab * t;
		float d2 = dot(q, q);
		if (d2 < best) {
			best = d2;
			on_line = vec3(mix(a.z, c.z, t), 0.0, mix(a.w, c.w, t));
		}
	}
	on_line.y = sqrt(best);
	return on_line;
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(view.xyz / view.w, 1.0)).xyz;
	vec3 facet = normalize(cross(dFdx(world), dFdy(world)));
	vec3 local = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	vec2 p = local.xz + frame_offset;
	// The height over the burn's ground: the box's middle, or along a path the line's ground.
	float up = local.y;
	vec3 on_line = vec3(0.0);
	if (path_count > 1) {
		on_line = along_path(p);
		up = local.y - on_line.z;
	}
	// Only the ground and what stands low on it: within the box's height, and off steep faces
	// above LOW_M (the trunks and crowns burn by their own shader).
	float low = 1.0 - smoothstep(LOW_M * 0.6, LOW_M, up);
	float upright = max(smoothstep(0.2, 0.5, abs(facet.y)), low);
	float keep = fade * (1.0 - smoothstep(half_height * 0.7, half_height, abs(up))) * upright;
	if (depth < 0.0001 || keep < 0.002) {
		discard;
	}
	// Metres behind the front (above 0 burnt): the lobed reach, ragged. Along a path, behind the
	// front along the line (b_front, which alone carries the hot band and the cooling behind it,
	// so the band runs with the front instead of lining both sides like lava banks) and inside
	// the half-width, whichever is nearer its edge (b: the char and the dry edge).
	float wobble = lobe_m * (lobes(p) - 0.5);
	float rag = (glow_noise(p / RAG_BLOB_M + lobe_offset * 3.0) - 0.5) * RAG_M;
	float b_front = front - (length(p) - wobble) + rag;
	float b = b_front;
	if (path_count > 1) {
		b_front = front - (on_line.x - wobble) + rag;
		b = min(b_front, path_width * 1.05 - (on_line.y - wobble) + rag);
	}
	vec3 ground = texture(screen_texture, SCREEN_UV).rgb;
	float luma = dot(ground, LUMA);

	// Ahead: the grass dries in a mottled band, wide and narrow by its noise.
	float wide = SCORCH_M * (0.55 + 0.9 * glow_cloud(p * 0.33 + lobe_offset * 4.0));
	float dry = clamp(1.0 + b / wide, 0.0, 1.0);
	dry += (glow_cloud(p * 1.3 + lobe_offset * 6.0) - 0.5) * 0.4;
	vec3 colour = mix(ground, luma * OLIVE, tone(0.12, dry));
	colour = mix(colour, luma * STRAW, tone(0.38, dry));
	colour = mix(colour, luma * BROWN, tone(0.66, dry));
	colour = mix(colour, luma * SCORCHED, tone(0.9, dry));
	float alpha = smoothstep(0.0, 0.14, dry);

	// Behind: char with ash blotches.
	float burnt = smoothstep(-0.03, 0.03, b);
	float ash = tone(0.66, glow_cloud(p * 0.9 + lobe_offset * 5.0));
	vec3 charred = mix(mix(CHAR_TINT, ASH_TINT, ash * 0.6), ASH_LANDED, ashen);
	colour = mix(colour, luma * charred, burnt);
	alpha = max(alpha, burnt);

	// On it: the hot band, its width and its breaks crawling with the clock. Deep red outside,
	// an orange body, gold only in the hottest patches (a gold line all along tonemapped to a
	// near-white neon stroke).
	float clock = elapsed;
	float width = HOT_M * (0.45 + 1.1 * glow_cloud(p * 0.5 + lobe_offset + vec2(clock * 0.35, 0.0)));
	float whole = tone(GAPS, glow_cloud(p * 0.38 + lobe_offset * 2.0 - vec2(0.0, clock * 0.3)));
	float x = b_front / width;
	// Along a path only inside the half-width (a circle's band is its front, b itself).
	float inside = path_count > 1 ? step(0.0, b) : 1.0;
	float on_band = step(0.0, x) * (1.0 - tone(0.92, x)) * whole * inside;
	float hottest = tone(0.55, glow_cloud(p * 0.9 + lobe_offset * 9.0 + vec2(0.0, clock * 0.5)));
	vec3 bands = mix(HOT_RED, HOT_ORANGE, tone(0.3, x));
	bands = mix(bands, HOT_GOLD, tone(0.55, x) * hottest);
	vec3 hot = bands * on_band;

	// Behind it: a deep red smoulder in broad patches, and glowing specks of two sizes (fewer
	// of the large, so they read as embers rather than confetti) that pulse; both cool as the
	// front leaves them.
	float behind = max(b_front - width, 0.0);
	float off_band = burnt * (1.0 - on_band);
	float smoulder = tone(0.5, glow_cloud(p * 0.7 + lobe_offset * 8.0 + vec2(clock * 0.1)));
	hot += HOT_RED * SMOULDER * smoulder * exp(-behind / SMOULDER_FADE_M) * off_band;
	vec2 speck_at = p * 2.6 + lobe_offset * 7.0;
	float big = tone(0.8, glow_noise(p * 1.1 + lobe_offset * 11.0));
	float speck = max(tone(0.84, glow_noise(speck_at)), big);
	float pulse = 0.6 + 0.4 * sin(clock * 6.0 + glow_hash(ivec2(floor(speck_at))) * 30.0);
	hot += EMBER * speck * pulse * exp(-behind / SPECK_FADE_M) * off_band;

	ALBEDO = colour + hot * ENERGY * glow;
	ALPHA = alpha * keep;
}
