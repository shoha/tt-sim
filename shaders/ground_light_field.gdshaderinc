// The ground look's colour zones and painted light (ground ship card 3b, from round 20 of the
// treecube ground looks pass; contract: docs/ASSET_PIPELINE.md section 9 "Ground look and grass
// masses"; system doc: docs/systems/authored_terrain.md "Ground look").
//
// A biome's ground is three or four turf colours (zone_color_0 the base, 1 to 3 laid over it in
// order, linear) in low-frequency, domain-warped world-space shapes, under a painted light: soft
// lit and shaded pools, broad soft streaks or the savanna's ripples. Both are evaluated only in
// a bake (shaders/ground_light_field_bake.gdshader, run by GroundLookBake once per map and look):
// each texel holds, square-root encoded over ZONE_RANGE, the zone colour times the light over the
// biome's light reference (rgb, the biome ground's multiplier) and the light's luminance (a, the
// multiplier of every other surface). The ground (authored_ground) and the grass
// (wind_foliage_main) read it with one fetch; nothing here costs frame time but that fetch.
//
// Sections, by define before the include:
//   (none)              the shared decode and the cap, for the ground.
//   LIGHT_FIELD_BAKE    the bake's uniforms and the zone and light functions.
//   LIGHT_FIELD_TUFT    the grass tuft's uniforms and zone_tuft_albedo (wind_foliage_main).
// Every uniform defaults off: a material nobody sets draws as before the ground ship.

const float ZONE_RANGE = 4.0;
const vec3 ZONE_LUMA = vec3(0.2126, 0.7152, 0.0722);

// A baked texel decoded (see the header).
vec4 zone_decode(vec4 t) {
	return t * t * ZONE_RANGE;
}

// A colour under the light, capped: above `knee` (linear, the brightest channel) the value eases
// toward `cap` with the hue held, and the saturation (measured on a square root, near sRGB) is held
// under `sat_cap`, so a lit pool brightens without turning into a pure-yellow hotspot.
vec3 light_field_capped_by(vec3 c, float knee, float cap, float sat_cap) {
	float v = max(c.r, max(c.g, c.b));
	if (v > knee) {
		float over = v - knee;
		float room = max(cap - knee, 1e-3);
		float eased = knee + over / (1.0 + over / room);
		c *= eased / v;
		v = eased;
	}
	float lo = min(c.r, min(c.g, c.b));
	float sv = sqrt(max(v, 1e-6));
	float sat = 1.0 - sqrt(max(lo, 0.0)) / sv;
	if (sat > sat_cap) {
		float floor_lo = v * (1.0 - sat_cap) * (1.0 - sat_cap);
		c = mix(vec3(v), c, (v - floor_lo) / max(v - lo, 1e-5));
	}
	return c;
}

#ifdef LIGHT_FIELD_BAKE
// The painted light (contract `light`): soft lit pools about light_field_scale_m across lift the
// value (light_field_lift) and lean toward light_field_lit_tint, shaded pools drop it
// (light_field_shade, light_field_shade_tint), light_field_key lifts the whole field.
// light_field_broad groups the pools into a few large regions, light_field_stretch draws them
// longer along the streaks' bending direction, light_field_crisp narrows their soft edges.
// Broad soft streaks (light_field_streak, a value amplitude either side) about
// light_field_streak_m across and light_field_streak_stretch times as long, along
// light_field_streak_angle (radians) bending slowly, over light_field_streak_cover of the map;
// light_field_streak_ripple 1 turns them into the sand's ripple bands, which
// light_field_ripple_curve curves, varies and breaks into lengths.
uniform float light_field_key = 1.0;
uniform float light_field_scale_m = 6.0;
uniform float light_field_cover = 0.3;
uniform float light_field_lift = 0.5;
uniform vec3 light_field_lit_tint = vec3(1.04, 1.0, 0.8);
uniform float light_field_shade = 0.22;
uniform vec3 light_field_shade_tint = vec3(0.9, 1.0, 1.1);
uniform float light_field_streak = 0.0;
uniform float light_field_streak_m = 2.0;
uniform float light_field_streak_stretch = 3.0;
uniform float light_field_streak_angle = 0.5;
uniform float light_field_streak_ripple = 0.0;
uniform float light_field_streak_cover = 1.0;
uniform float light_field_broad = 0.0;
uniform float light_field_stretch = 1.0;
uniform float light_field_crisp = 0.0;
uniform float light_field_ripple_curve = 0.0;
// The biome's light reference (its ref_surface's mean albedo, linear): the bake divides by it.
uniform vec3 light_field_ref = vec3(0.25, 0.35, 0.05);
// The zones (contract `zones`): each zone's shape zone_scale_m across, covering zone_cover of the
// map, zone_stretch (times zone_stretch_k) longer along zone_angle (plus zone_angle_k), warped
// by zone_warp, its soft edge zone_edge wide (noise units) varying along the boundary by
// zone_edge_vary over about zone_edge_vary_m, ragged at about zone_rag_m by zone_rag. zone_nest 1
// lays the third zone inside the second's shapes. zone_shade_warm: the tint a yellow zone takes
// in the light's shade (1 is off). zone_oklab mixes what blend remains in OKLab (2: with the
// chroma kept). zone_seed_m shifts zones and light by the map seed's offset (GroundZones).
uniform vec3 zone_color_0 = vec3(0.27, 0.39, 0.05);
uniform vec3 zone_color_1 = vec3(0.27, 0.39, 0.05);
uniform vec3 zone_color_2 = vec3(0.27, 0.39, 0.05);
uniform vec3 zone_color_3 = vec3(0.27, 0.39, 0.05);
uniform vec3 zone_cover = vec3(0.0);
uniform vec3 zone_scale_m = vec3(12.0, 9.0, 6.0);
uniform float zone_stretch = 1.0;
uniform float zone_angle = 0.0;
uniform float zone_warp = 0.6;
uniform vec3 zone_edge = vec3(0.03);
uniform float zone_rag = 0.1;
uniform float zone_rag_m = 1.2;
uniform float zone_nest = 0.0;
uniform vec2 zone_seed_m = vec2(0.0);
uniform vec3 zone_angle_k = vec3(0.0);
uniform vec3 zone_stretch_k = vec3(1.0);
uniform float zone_edge_vary = 0.0;
uniform float zone_edge_vary_m = 24.0;
uniform vec3 zone_shade_warm = vec3(1.0);
uniform float zone_oklab = 0.0;
// The strokes (contract `strokes`): zone_stroke 1 resolves a zone's edge per brush stroke (value
// noise zone_stroke_m wide, zone_stroke_len times longer along the zone's sweep, bent a little)
// rather than crossfading it; each stroke's own edge is soft between zone_stroke_soft_lo and _hi
// (weight units), varying over about zone_stroke_soft_m; zone_stroke_edge widens every zone's
// edge so the interleaving band reads at map scale.
uniform float zone_stroke = 0.0;
uniform float zone_stroke_m = 1.6;
uniform float zone_stroke_len = 3.5;
uniform float zone_stroke_soft_lo = 0.04;
uniform float zone_stroke_soft_hi = 0.25;
uniform float zone_stroke_soft_m = 9.0;
uniform float zone_stroke_edge = 1.0;

// A fract hash (no sine, so GroundZones' CPU copy agrees with the GPU's).
float light_field_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float light_field_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	float a = light_field_hash(i);
	float b = light_field_hash(i + vec2(1.0, 0.0));
	float c = light_field_hash(i + vec2(0.0, 1.0));
	float d = light_field_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// The streaks' direction at `xz`: light_field_streak_angle bending slowly over the map.
vec2 light_field_flow(vec2 xz) {
	float bend = (light_field_noise(xz / (light_field_streak_m * 9.0) + vec2(-9.1, 4.4)) - 0.5) * 1.6;
	float a = light_field_streak_angle + bend;
	return vec2(cos(a), sin(a));
}

// The light's multiplier at map-frame XZ `xz` (metres, the seed offset added).
vec3 light_field_procedural(vec2 xz) {
	vec2 p = xz / light_field_scale_m;
	if (light_field_stretch != 1.0) {
		// Pools drawn longer along the streaks' direction.
		vec2 along = light_field_flow(xz);
		p = vec2(dot(p, along) / light_field_stretch, dot(p, vec2(-along.y, along.x)));
	}
	// A slow warp, so the pools are ragged painted shapes rather than noise blobs.
	vec2 warp = vec2(
		light_field_noise(p * 0.45 + vec2(3.1, -7.3)), light_field_noise(p * 0.45 + vec2(-5.7, 2.9))
	);
	p += (warp - 0.5) * 1.4;
	float f = light_field_noise(p) * 0.72 + light_field_noise(p * 2.03 + vec2(11.1, 4.7)) * 0.28;
	if (light_field_broad > 0.0) {
		// A coarser octave groups the pools into a few large regions of different sizes.
		float g = light_field_noise(p * 0.4 + vec2(-13.7, 6.1));
		f = mix(f, 0.5 + (f - 0.5) * 0.8 + (g - 0.5) * 0.9, light_field_broad);
	}
	// Two-octave value noise sits around 0.5 with a spread of about 0.12; the cover moves the
	// thresholds out from the middle.
	float edge = mix(0.2, 0.02, clamp(light_field_cover / 0.5, 0.0, 1.0));
	float soft = mix(1.0, 0.35, clamp(light_field_crisp, 0.0, 1.0));
	float lit = smoothstep(0.5 + edge - 0.04 * soft, 0.5 + edge + 0.08 * soft, f);
	float shade = smoothstep(0.5 - edge + 0.04 * soft, 0.5 - edge - 0.08 * soft, f);
	vec3 m = vec3(light_field_key);
	m *= mix(vec3(1.0), light_field_lit_tint * (1.0 + light_field_lift), lit);
	m *= mix(vec3(1.0), light_field_shade_tint * (1.0 - light_field_shade), shade);
	if (light_field_streak > 0.0) {
		// Broad soft streaks or ripple bands, along a direction that bends slowly.
		vec2 along = light_field_flow(xz);
		vec2 r = vec2(dot(xz, along), dot(xz, vec2(-along.y, along.x))) / light_field_streak_m;
		float soft_s = light_field_noise(vec2(r.x / light_field_streak_stretch, r.y) + vec2(2.3, 7.7));
		float wobble = light_field_noise(vec2(r.x * 0.35, r.y * 0.5) + vec2(4.1, -3.3));
		float wave = 0.5 + 0.5 * sin(TAU * (r.y + 1.2 * wobble));
		if (light_field_ripple_curve > 0.0) {
			// Crests that curve, spacing that varies, a lit windward slope and a sharp lee, and
			// crests broken into lengths.
			float c = light_field_ripple_curve;
			float bow = light_field_noise(vec2(r.x * 0.18, r.y * 0.12) + vec2(-6.2, 1.7)) - 0.5;
			float kink = light_field_noise(vec2(r.x * 0.6, r.y * 0.3) + vec2(3.9, 9.4)) - 0.5;
			float spacing = 1.0 + 0.35 * c * (light_field_noise(r * 0.15 + vec2(7.3, -4.1)) - 0.5);
			float phase = r.y * spacing + 1.2 * wobble + c * (3.2 * bow + 0.9 * kink);
			float t = fract(phase);
			float crest = smoothstep(0.0, 0.72, t) * (1.0 - smoothstep(0.72, 0.9, t));
			float lengths = smoothstep(0.3, 0.55, light_field_noise(vec2(r.x * 0.5, phase * 0.7) + vec2(1.1, 5.5)));
			wave = mix(wave, 0.5 + (crest - 0.45) * mix(0.35, 1.0, lengths), c);
		}
		float s = mix(soft_s, wave, light_field_streak_ripple) * 2.0 - 1.0;
		float region = smoothstep(0.38, 0.62, light_field_noise(xz / (light_field_scale_m * 1.7) + vec2(8.8, -2.2)));
		m *= 1.0 + light_field_streak * s * mix(1.0, region, 1.0 - light_field_streak_cover);
	}
	return m;
}

// One zone's shape field at `xz` (about 0.5 in the middle, spread about 0.12): two octaves
// zone_scale_m across in the zone's swept frame (`angle`, `stretch`), warped, plus the ragged
// edge octave. GroundZones._zone_shape is the CPU copy.
float zone_shape(vec2 xz, float scale_m, vec2 offset, float angle, float stretch) {
	vec2 cs = vec2(cos(angle), sin(angle));
	vec2 r = vec2(dot(xz, cs) / max(stretch, 0.1), dot(xz, vec2(-cs.y, cs.x)));
	vec2 p = r / scale_m;
	vec2 w = vec2(
		light_field_noise(p * 0.55 + offset + vec2(3.7, -1.9)),
		light_field_noise(p * 0.55 + offset + vec2(-8.3, 6.1))
	);
	p += (w - 0.5) * 2.0 * zone_warp;
	float f = light_field_noise(p + offset) * 0.7
		+ light_field_noise(p * 2.07 + offset * 1.3 + vec2(5.1, 2.2)) * 0.3;
	vec2 q = r / zone_rag_m + (w - 0.5) * 3.0;
	return f + (light_field_noise(q + offset * 0.7 + vec2(-2.9, 13.3)) - 0.5) * zone_rag;
}

// The weight of a zone whose shape field is `f`, covering about `cover` of the map, its edge
// `edge` wide (noise units).
float zone_mask(float f, float cover, float edge) {
	if (cover <= 0.0) {
		return 0.0;
	}
	float t = mix(0.7, 0.3, clamp(cover, 0.0, 1.0));
	return smoothstep(t - edge, t + edge, f);
}

// Zone `k`'s edge width at `xz`, varying along its boundary (zone_edge_vary).
float zone_edge_at(vec2 xz, float edge, float k) {
	if (zone_edge_vary <= 0.0) {
		return edge;
	}
	vec2 q = xz / max(zone_edge_vary_m, 0.5) + vec2(k * 7.31, -k * 3.17);
	float n = smoothstep(0.3, 0.7, light_field_noise(q) * 0.75 + light_field_noise(q * 2.3) * 0.25);
	return edge * mix(1.0 - zone_edge_vary, 1.0 + 1.5 * zone_edge_vary, n);
}

// Linear sRGB to OKLab and back (Ottosson), for zone_oklab.
vec3 zone_oklab_from(vec3 c) {
	vec3 lms = vec3(
		dot(c, vec3(0.4122214708, 0.5363325363, 0.0514459929)),
		dot(c, vec3(0.2119034982, 0.6806995451, 0.1073969566)),
		dot(c, vec3(0.0883024619, 0.2817188376, 0.6299787005))
	);
	lms = pow(max(lms, vec3(0.0)), vec3(1.0 / 3.0));
	return vec3(
		dot(lms, vec3(0.2104542553, 0.7936177850, -0.0040720468)),
		dot(lms, vec3(1.9779984951, -2.4285922050, 0.4505937099)),
		dot(lms, vec3(0.0259040371, 0.7827717662, -0.8086757660))
	);
}

vec3 zone_oklab_to(vec3 lab) {
	vec3 lms = vec3(
		dot(lab, vec3(1.0, 0.3963377774, 0.2158037573)),
		dot(lab, vec3(1.0, -0.1055613458, -0.0638541728)),
		dot(lab, vec3(1.0, -0.0894841775, -1.2914855480))
	);
	lms = lms * lms * lms;
	return max(
		vec3(
			dot(lms, vec3(4.0767416621, -3.3077115913, 0.2309699292)),
			dot(lms, vec3(-1.2684380046, 2.6097574011, -0.3413193965)),
			dot(lms, vec3(-0.0041960863, -0.7034186147, 1.7076147010))
		),
		vec3(0.0)
	);
}

// `a` toward `b` by `t`, in OKLab when zone_oklab is set (linear RGB otherwise). At zone_oklab 2
// the chroma is interpolated too, so a gold-to-green blend keeps its colours' vividness.
vec3 zone_mix(vec3 a, vec3 b, float t) {
	if (zone_oklab < 0.5 || t <= 0.0 || t >= 1.0) {
		return mix(a, b, t);
	}
	vec3 la = zone_oklab_from(a);
	vec3 lb = zone_oklab_from(b);
	vec3 m = mix(la, lb, t);
	if (zone_oklab > 1.5) {
		float cm = length(m.yz);
		if (cm > 1e-4) {
			m.yz *= mix(length(la.yz), length(lb.yz), t) / cm;
		}
	}
	return zone_oklab_to(m);
}

// Mirrors GroundZones._stroke_pick in utils/ground_zones.gd (keep the two in step): zone `k`'s
// weight `m` resolved per brush stroke (zone_stroke): a stroke pattern in the zone's swept frame
// (`angle`), spread to about 0..1, picks the zone where the weight is above it.
float zone_stroke_pick(vec2 xz, float m, float angle, float k) {
	if (zone_stroke <= 0.0 || m <= 0.0 || m >= 1.0) {
		return m;
	}
	vec2 cs = vec2(cos(angle), sin(angle));
	vec2 r = vec2(dot(xz, cs), dot(xz, vec2(-cs.y, cs.x)));
	vec2 p = vec2(r.x / (zone_stroke_m * max(zone_stroke_len, 1.0)), r.y / zone_stroke_m);
	vec2 o = vec2(k * 13.7, -k * 7.9);
	// The strokes bend: their across coordinate drifts slowly along them.
	p.y += (light_field_noise(vec2(p.x * 0.6, p.y * 0.25) + o + vec2(3.3, 1.1)) - 0.5) * 2.4;
	float s = light_field_noise(p + o) * 0.62 + light_field_noise(p * vec2(1.7, 2.1) + o * 1.3 + vec2(-4.1, 9.2)) * 0.38;
	s = clamp((s - 0.5) * 2.6 + 0.5, 0.0, 1.0);
	float soft_n = light_field_noise(xz / max(zone_stroke_soft_m, 0.5) + o * 0.5 + vec2(-6.6, 2.4));
	float soft = mix(zone_stroke_soft_lo, zone_stroke_soft_hi, smoothstep(0.3, 0.7, soft_n));
	s = mix(soft, 1.0 - soft, s);
	return mix(m, smoothstep(s - soft, s + soft, m), zone_stroke);
}

// The biome ground's turf colour at `xz` (linear): the zones laid over the base in order, each
// weight resolved per stroke and mixed in OKLab when set. GroundZones.zone_weights is the CPU copy.
vec3 zone_color(vec2 xz) {
	vec3 c = zone_color_0;
	vec3 ang = vec3(zone_angle) + zone_angle_k;
	vec3 str = vec3(zone_stretch) * zone_stretch_k;
	vec3 edge = zone_edge * (zone_stroke > 0.0 ? zone_stroke_edge : 1.0);
	float f1 = zone_shape(xz, zone_scale_m.x, vec2(17.3, -4.1), ang.x, str.x);
	float m1 = zone_mask(f1, zone_cover.x, zone_edge_at(xz, edge.x, 1.0));
	c = zone_mix(c, zone_color_1, zone_stroke_pick(xz, m1, ang.x, 1.0));
	float f2 = zone_shape(xz, zone_scale_m.y, vec2(-23.9, 11.7), ang.y, str.y);
	float m2 = zone_mask(f2, zone_cover.y, zone_edge_at(xz, edge.y, 2.0));
	c = zone_mix(c, zone_color_2, zone_stroke_pick(xz, m2, ang.y, 2.0));
	float f3 = zone_nest > 0.5 ? f2 : zone_shape(xz, zone_scale_m.z, vec2(7.7, 29.3), ang.z, str.z);
	float m3 = zone_mask(f3, zone_cover.z, zone_edge_at(xz, edge.z, 3.0));
	return zone_mix(c, zone_color_3, zone_stroke_pick(xz, m3, ang.z, 3.0));
}

// The light's multiplier `light` on the turf colour `c` (both linear), a yellow turf's shade
// leaning toward zone_shade_warm (amber rather than olive).
vec3 zone_lit(vec3 c, vec3 light) {
	vec3 m = c * light;
	if (all(equal(zone_shade_warm, vec3(1.0)))) {
		return m;
	}
	float yellow = smoothstep(0.45, 0.85, c.r / max(c.g, 1e-3));
	float shade = clamp(
		(light_field_key - dot(light, ZONE_LUMA)) / max(light_field_key * light_field_shade, 1e-3), 0.0, 1.0
	);
	return m * mix(vec3(1.0), zone_shade_warm, yellow * shade);
}
#endif

#ifdef LIGHT_FIELD_TUFT
// The grass (contract `tuft` and `mass`). Each tuft reads the bake once, at its MultiMesh
// instance origin (wind_foliage_main), and takes its zone's hue and saturation at its own
// luminance: the ground's turf there (light_field_ref times the texel, capped as the ground
// draws it with zone_tuft_capped) times its luminance over its texture's mean (zone_tuft_ref,
// linear, measured per material by GroundLookUniforms.opaque_mean_linear) raised to
// zone_tuft_contrast, zone_tuft_hue of its own hue, zone_tuft_step over the turf, eased above
// zone_tuft_knee toward zone_tuft_cap. A tuft of a grass mass (its instance carries the mass
// anchor, INSTANCE_CUSTOM.w 1) reads the zone at its anchor, steps zone_mass_step more, takes
// zone_mass_sat more saturation, zone_mass_lit more on its sunward side (zone_mass_lit_dir, unit
// world XZ toward the sun, over zone_mass_lit_m), its own zone_mass_contrast (below 0 keeps the
// tuft's) and a ramp from zone_mass_base at its foot to zone_mass_tip at zone_mass_h_m (power
// zone_mass_up_pow); zone_mass_own moves its read from the anchor toward where it stands.
// zone_tuft_strength 0 (the default) leaves the grass as it was.
uniform sampler2D light_field_tex : hint_default_white, filter_linear, repeat_disable;
uniform vec4 light_field_rect = vec4(-64.0, -64.0, 128.0, 128.0);
uniform vec3 light_field_ref = vec3(0.25, 0.35, 0.05);
uniform float light_field_knee = 1.0;
uniform float light_field_cap = 1.0;
uniform float light_field_sat_cap = 1.0;
uniform float zone_tuft_strength = 0.0;
uniform vec3 zone_tuft_ref = vec3(0.12, 0.2, 0.04);
uniform float zone_tuft_step = 1.25;
uniform float zone_tuft_contrast = 0.8;
uniform float zone_tuft_hue = 0.2;
uniform float zone_tuft_knee = 0.55;
uniform float zone_tuft_cap = 0.9;
uniform float zone_tuft_capped = 0.0;
uniform float zone_mass_step = 1.0;
uniform float zone_mass_sat = 1.0;
uniform float zone_mass_lit = 0.0;
uniform vec2 zone_mass_lit_dir = vec2(0.0, -1.0);
uniform float zone_mass_lit_m = 1.5;
uniform float zone_mass_contrast = -1.0;
uniform float zone_mass_base = 1.0;
uniform float zone_mass_tip = 1.0;
uniform float zone_mass_h_m = 0.6;
uniform float zone_mass_own = 0.0;
uniform float zone_mass_up_pow = 1.0;

// The baked texel at world XZ `xz`, decoded (outside the rect the edge texel holds).
vec4 zone_fetch(vec2 xz) {
	return zone_decode(textureLod(light_field_tex, (xz - light_field_rect.xy) / light_field_rect.zw, 0.0));
}

// A grass fragment's albedo `a` recoloured by its tuft's zone texel `zone` (see the section's
// header). `mass` is (1 for a massed tuft, its side of the mass from -1 far to 1 lit, its height
// in metres above the tuft's origin), (0, 0, 0) for fine cover. `a` itself at strength 0.
vec3 zone_tuft_albedo(vec3 a, vec4 zone, vec3 mass) {
	vec3 tref = max(zone_tuft_ref, vec3(1e-3));
	float ratio = max(dot(a, ZONE_LUMA), 1e-4) / dot(tref, ZONE_LUMA);
	vec3 hue = mix(vec3(1.0), a / (tref * ratio), zone_tuft_hue);
	vec3 turf = max(light_field_ref, vec3(1e-3)) * zone.rgb;
	if (zone_tuft_capped > 0.5) {
		turf = light_field_capped_by(turf, light_field_knee, light_field_cap, light_field_sat_cap);
	}
	float own = step(0.5, mass.x) * step(0.0, zone_mass_contrast);
	float contrast = mix(zone_tuft_contrast, zone_mass_contrast, own);
	vec3 t = turf * zone_tuft_step * pow(ratio, contrast) * hue;
	// The tuft's own softer ease (the ground's knee would hold it under the ground's value).
	float v = max(t.r, max(t.g, t.b));
	if (v > zone_tuft_knee) {
		float over = v - zone_tuft_knee;
		float room = max(zone_tuft_cap - zone_tuft_knee, 1e-3);
		t *= (zone_tuft_knee + over / (1.0 + over / room)) / v;
	}
	if (mass.x > 0.5) {
		// The mass's own step and its lit side, the mound's lit top and dark base, then its
		// saturation at the same brightest channel.
		float side = max(mass.y, 0.0) + 0.5 * min(mass.y, 0.0);
		t *= zone_mass_step * (1.0 + zone_mass_lit * side);
		float up = pow(clamp(mass.z / max(zone_mass_h_m, 1e-3), 0.0, 1.0), zone_mass_up_pow);
		t *= mix(zone_mass_base, zone_mass_tip, up);
		float tv = max(max(t.r, max(t.g, t.b)), 1e-4);
		t = tv * pow(max(t / tv, vec3(0.0)), vec3(zone_mass_sat));
	}
	return mix(a, t, zone_tuft_strength);
}
#endif
