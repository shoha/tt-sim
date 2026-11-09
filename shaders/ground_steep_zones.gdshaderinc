// GROUND LOOK on steep faces (steepzones, 2026-11-08; docs/ARCHITECTURE.md "Steep faces").
// Included by authored_ground.gdshaderinc under GROUND_LOOK, after look_fetch.
//
// The look bake is evaluated top-down in XZ, so on a face a zone edge crossing the wall runs down
// the fall line as a stripe and the strokes smear along it. Here a face reads the look's fields in
// 3D instead. GroundLookBake bakes each slot's fields before their thresholds
// (ground_steep_bake.gdshader) into look_steep: per slot a band of STEEP_LAYERS height layers (the
// same fields at a far XZ shift each, layer 0 unshifted) by two rows, row 0 the three zone shapes
// and the light's field, row 1 the zones' ragged-edge octave. A fragment blends the layers along
// its height (layer k mod STEEP_LAYERS between k and k + 1 layer lengths, offset by STEEP_PHASE,
// smoothstep, the variance kept), each field with its own layer length: its own scale (zones.scale_m, light
// scale_m, zones.rag_m), so it varies as fast up a face as across it. Then it thresholds and
// lights them as the bake does, without the strokes, the edge variation and the light's streaks
// (marks drawn along a direction, which would run down the face). steep_weight (0 under about
// 29.5 degrees, 1 over 44.8) mixes that into the top-down texel, so ground under 29.5 degrees
// takes exactly the old path.
//
// look_steep_atlas: (slots in the atlas, a layer's texels across, down, unused).
// look_steep_params, STEEP_PARAMS vec4s per slot (GroundSteepZones.params):
//   0..3  zone colours 0..3 (rgb, linear); w: zone_oklab, zone_rag, the rag's layer length, 0
//   4     zone cover (xyz), light key       5  zone edge (xyz), the light's edge
//   6     layer lengths (zone 1, 2, 3, light; metres)
//   7     lit multiplier (rgb), the light's softness    8  shade multiplier (rgb), light shade
//   9     zone_shade_warm (rgb)             10 the light reference (rgb, linear, as the bake's)

const float STEEP_FLAT_NY = 0.87;
const float STEEP_FULL_NY = 0.71;
const float STEEP_LAYERS = 3.0;
const float STEEP_PHASE = 0.5;
const int STEEP_PARAMS = 12;
uniform sampler2D look_steep : hint_default_white, filter_linear, repeat_disable;
uniform vec4 look_steep_atlas = vec4(1.0, 8.0, 8.0, 0.0);
uniform vec4 look_steep_params[48];

// How much of a face's look comes from its 3D fields, by its normal's height (GroundSteepZones
// .weight): exactly 0 at ny 0.87 and over, 1 at 0.71 and under.
float steep_weight(float ny) {
	return 1.0 - smoothstep(STEEP_FULL_NY, STEEP_FLAT_NY, ny);
}

// Slot `s`'s row `row` fields at layer uv `uv`, each channel blended over the height layers at its
// own height `h` (metres over its layer length; GroundSteepZones.blend): three fetches.
vec4 steep_layers(int s, float row, vec2 uv, vec4 h) {
	// Half a layer of phase: at a whole h a field's height rate is 0 (the smoothstep's ends), and
	// unshifted every field would have it at height 0, where most walls meet the plain (the
	// savanna valley walls read 1.3 to 3.6 times as fast along as down without it).
	h += STEEP_PHASE;
	vec2 at = vec2(uv.x / STEEP_LAYERS, (float(s) * 2.0 + row + uv.y) / (2.0 * look_steep_atlas.x));
	vec4 a = textureLod(look_steep, at, 0.0);
	vec4 b = textureLod(look_steep, at + vec2(1.0 / STEEP_LAYERS, 0.0), 0.0);
	vec4 c = textureLod(look_steep, at + vec2(2.0 / STEEP_LAYERS, 0.0), 0.0);
	vec4 k = floor(h);
	vec4 t = h - k;
	t = t * t * (3.0 - 2.0 * t);
	// The layer below and above, near 0, 1 or 2 (the half keeps a rounded k off the boundary).
	vec4 j = mod(k + 0.5, STEEP_LAYERS) - 0.5;
	vec4 j1 = mod(k + 1.5, STEEP_LAYERS) - 0.5;
	vec4 lo = mix(mix(a, b, step(0.5, j)), c, step(1.5, j));
	vec4 hi = mix(mix(a, b, step(0.5, j1)), c, step(1.5, j1));
	return 0.5 + (mix(lo, hi, t) - 0.5) * inversesqrt(t * t + (1.0 - t) * (1.0 - t));
}

// zone_mix with the mode `oklab` (keep in step with it).
vec3 steep_mix(vec3 a, vec3 b, float t, float oklab) {
	if (oklab < 0.5 || t <= 0.0 || t >= 1.0) {
		return mix(a, b, t);
	}
	vec3 la = zone_oklab_from(a);
	vec3 lb = zone_oklab_from(b);
	vec3 m = mix(la, lb, t);
	if (oklab > 1.5) {
		float cm = length(m.yz);
		if (cm > 1e-4) {
			m.yz *= mix(length(la.yz), length(lb.yz), t) / cm;
		}
	}
	return zone_oklab_to(m);
}

// Slot `s`'s look texel, decoded, for a face point at map-frame XZ `world_xz` and height `y`: the
// bake's texel (ground_light_field_bake.gdshader) made from the 3D fields.
vec4 steep_texel(int s, vec2 world_xz, float y) {
	int o = s * STEEP_PARAMS;
	vec2 inset = 0.5 / look_steep_atlas.yz;
	vec2 uv = clamp((world_xz - look_rect.xy) / look_rect.zw, inset, 1.0 - inset);
	vec4 f = steep_layers(s, 0.0, uv, y / look_steep_params[o + 6]);
	f.xyz += (steep_layers(s, 1.0, uv, vec4(y / look_steep_params[o + 2].w)).xyz - 0.5) * look_steep_params[o + 1].w;
	vec4 cover = look_steep_params[o + 4];
	vec4 edge = look_steep_params[o + 5];
	vec3 thr = mix(vec3(0.7), vec3(0.3), clamp(cover.xyz, 0.0, 1.0));
	vec3 e = max(edge.xyz, vec3(1e-4));
	vec3 m = smoothstep(thr - e, thr + e, f.xyz) * step(vec3(1e-6), cover.xyz);
	float oklab = look_steep_params[o].w;
	vec3 c = look_steep_params[o].rgb;
	c = steep_mix(c, look_steep_params[o + 1].rgb, m.x, oklab);
	c = steep_mix(c, look_steep_params[o + 2].rgb, m.y, oklab);
	c = steep_mix(c, look_steep_params[o + 3].rgb, m.z, oklab);
	// light_field_procedural's pools from the light's field, and zone_lit (keep in step).
	float key = cover.w;
	float soft = look_steep_params[o + 7].w;
	float lit = smoothstep(0.5 + edge.w - 0.04 * soft, 0.5 + edge.w + 0.08 * soft, f.w);
	float shade = smoothstep(0.5 - edge.w + 0.04 * soft, 0.5 - edge.w - 0.08 * soft, f.w);
	vec3 light = vec3(key) * mix(vec3(1.0), look_steep_params[o + 7].rgb, lit);
	light *= mix(vec3(1.0), look_steep_params[o + 8].rgb, shade);
	vec3 col = c * light;
	vec3 warm = look_steep_params[o + 9].rgb;
	if (any(notEqual(warm, vec3(1.0)))) {
		float yellow = smoothstep(0.45, 0.85, c.r / max(c.g, 1e-3));
		float shaded = clamp(
			(key - dot(light, ZONE_LUMA)) / max(key * look_steep_params[o + 8].w, 1e-3), 0.0, 1.0
		);
		col *= mix(vec3(1.0), warm, yellow * shaded);
	}
	vec3 ref = max(look_steep_params[o + 10].rgb, vec3(1e-3));
	return clamp(vec4(col / ref, dot(light, ZONE_LUMA)), vec4(0.0), vec4(ZONE_RANGE));
}

// Slot `slot`'s look texel, decoded, for a ground fragment at map-frame XZ `world_xz`, height `y`
// and normal height `ny`: look_fetch's top-down texel, toward steep_texel on a face.
vec4 look_texel(int slot, vec2 world_xz, float y, float ny) {
	vec4 t = look_fetch(slot, world_xz);
	float w = steep_weight(ny);
	if (w > 0.0) {
		t = mix(t, steep_texel(slot, world_xz, y), w);
	}
	return t;
}
