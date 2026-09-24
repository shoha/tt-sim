shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

/*
 * Water Shader
 * ============
 *
 * PURPOSE:
 * Automatically applied by WaterGlbUtils.process_water_meshes() (utils/water_glb_utils.gd) to any
 * mesh whose name ends in "-water" in a runtime-loaded GLB map. Gives terrain-paint
 * water planes (see the terrain-paint Blender addon's README "Water" section) a real
 * animated look with zero per-map setup -- the Blender-side plane only needs the right
 * name suffix, no material tuning survives export or needs to.
 *
 * DESIGN:
 * tt-sim's camera is an oblique/top-down tabletop view, so the "water" read has to come
 * from what is visible from above, not from a horizon-hugging first-person view:
 *
 *   1. Band-limited ripples. The surface normal comes from a few octaves of gradient
 *      noise with analytic derivatives (each rotated and drifting its own way) plus one
 *      long directional swell. Smooth, low-frequency normals let Godot's own GGX
 *      specular produce moving sun glints. The previous version derived the normal from
 *      hash-based value noise at several cycles per world unit, which at tabletop scale
 *      collapsed into sub-centimeter speckle and axis-aligned cell blockiness.
 *   2. Depth by absorption. The opaque scene color under the surface (screen prepass) is
 *      attenuated per channel with Beer-Lambert style exponential absorption, so the
 *      riverbed shows through in the shallows and fades to the deep tint further out.
 *   3. Caustics. A cheap animated ridged-noise pattern brightens the refracted bed in
 *      shallow water -- the strongest "this is water" cue for a top-down camera.
 *   4. Foam that breaks up. Shoreline foam is a soft depth band, modulated by animated
 *      noise into patches and pulsed slowly toward the shore, plus the existing
 *      depth-slope detector for rocks breaking the surface.
 *   5. Flow. Where terrain-paint baked a flow map, the ripple field, caustics and foam
 *      breakup are advected along the local flow with a two-phase cross-fade, the swell
 *      travels downstream, foam stretches into streaks and token ripples become wakes.
 *      Without a map nothing changes.
 *
 * The world-space normal is written to NORMAL directly (rather than via NORMAL_MAP) so the
 * result does not depend on the GLB plane carrying a sensible tangent basis.
 *
 * MANAGED BY: WaterGlbUtils._get_water_material() builds one shared ShaderMaterial instance
 * from this shader and reuses it across every map. Per-level tuning is a WaterSettings
 * resource (resources/water_settings.gd) applied by WaterGlbUtils.apply_water_settings();
 * WaterPresets groups the starting values into looks, palettes and motions.
 */

// Deep-water tint. Alpha is only used when the screen prepass is unavailable (Water
// Quality "Low" skips refraction, see water_quality_skip_refraction below); with
// refraction on, the surface composites the attenuated bed color itself and is opaque.
uniform vec4 water_color : source_color = vec4(0.05, 0.30, 0.38, 0.8);
// Shallow-water tint blended in near the shoreline -- lighter and more saturated than
// water_color so the same plane reads as "shallow" near shore and "deep" further out.
uniform vec4 shore_color : source_color = vec4(0.35, 0.75, 0.70, 0.6);
// View-space depth over which the shore tint gives way to water_color, and the width
// reference for the shoreline foam band (foam covers roughly the first fifth of it).
uniform float shore_depth_range : hint_range(0.05, 3.0) = 0.6;
// Per-unit-depth extinction of the refracted bed color (red channel; green and blue are
// absorbed more slowly, see ABSORB_TINT). Higher = murkier, bed disappears sooner.
uniform float depth_absorption : hint_range(0.0, 8.0) = 1.4;
// Crest highlight tinted onto the surface where the summed waves peak -- keeps some
// sparkle visible even under flat ambient light where the specular glint is absent.
uniform vec3 shimmer_color : source_color = vec3(0.75, 0.9, 0.95);
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.3;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.1;
// SPECULAR has no default lighting contribution of its own in Godot's spatial shader, so
// this must be set explicitly.
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
// Base ripple frequency in noise features per world unit -- the coarsest octave has
// features about 1 / ripple_scale units across; the finer octaves and the swell are
// fixed multiples of it (see water_ripple()).
uniform float ripple_scale : hint_range(0.1, 20.0) = 1.6;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.5;
uniform float bob_height : hint_range(0.0, 0.2) = 0.02;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.5;
// Blend toward water_ambient_reflection_color (global uniform below) as a cheap stand-in
// for a real reflection. Weighted by fresnel with a floor, since fresnel alone is ~0 for
// this project's near-top-down camera. Not gated by Water Quality (inexpensive); contrast
// with Environment.ssr_enabled, controlled by its own Settings > Graphics > SSR toggle.
uniform float sky_blend_strength : hint_range(0.0, 1.0) = 0.15;
// Screen-space refraction strength -- the wave gradient is reused as a UV offset so the
// bed distorts in sync with the visible ripple. Capped low because at tabletop zoom even
// a small UV offset reads as a large shift of the terrain underneath.
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.03;
// Caustic brightening of the refracted bed in shallow water. Scale is in cycles per world
// unit; strength is the peak brightness multiplier added at zero depth.
uniform float caustic_scale : hint_range(0.1, 10.0) = 1.3;
uniform float caustic_strength : hint_range(0.0, 3.0) = 0.7;
// hint_depth_texture / hint_screen_texture pull Godot's built-in depth and opaque-color
// prepasses -- both require blend_mix (already set above) and only see geometry drawn
// before this transparent pass, which is exactly the terrain/tokens under the water.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
// Positions of tokens currently resting in water (see WaterRippleRegistry /
// WaterZone), pushed via WaterGlbUtils.push_disturbance_points() every frame. xy =
// world XZ position, w = 1.0 if active / 0.0 if this slot is unused.
uniform vec4 water_disturbance_points[8];
uniform float disturbance_ripple_radius : hint_range(0.1, 5.0) = 1.2;
uniform float disturbance_ripple_strength : hint_range(0.0, 2.0) = 0.5;
// Foam: a soft shoreline band (see shore_depth_range) plus wherever depth changes sharply
// over a short world distance -- typically a rock breaking the surface. Both are modulated
// by animated noise so they form patches rather than a solid painted stripe.
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.96, 0.9);
uniform float foam_edge_sensitivity : hint_range(0.1, 6.0) = 1.5;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
// Flow map: RG = the flow direction in the water plane's LOCAL (Blender XY) axes times a
// 0..1 speed factor, packed as v * 0.5 + 0.5, sampled by the plane's UV. Baked by
// terrain-paint from '-flow' curves and carried in the GLB as the preview material's
// emission texture; WaterGlbUtils.process_water_meshes() moves it here and flags the one
// plane it belongs to with the per-instance water_flow_present. Every other plane, and
// every level without a map, renders exactly as before. See
// docs/superpowers/specs/2026-09-23-water-flow-design.md.
uniform sampler2D water_flow_map : hint_default_black, filter_linear, repeat_disable;
instance uniform bool water_flow_present = false;
// Per-level multiplier on the baked speed (WaterSettings.flow_strength, Motion group).
uniform float flow_strength : hint_range(0.0, 2.0) = 1.0;

// Water Quality graphics setting (Settings > Graphics) -- engine-wide global uniforms
// rather than per-material uniforms, so SettingsMenu can apply them via
// RenderingServer.global_shader_parameter_set() even before any water material
// exists yet. See docs/superpowers/specs/2026-08-11-water-shader-quality-design.md.
// skip_fine_detail drops the shortest wave and the caustics; skip_refraction drops the
// screen prepass sample (and with it the caustics, which brighten that sample).
global uniform bool water_quality_skip_fine_detail;
global uniform bool water_quality_skip_refraction;
// Updated by LevelEnvironmentManager whenever it applies environment settings,
// so the sky-blend above tracks the level's actual ambient/sky color.
global uniform vec3 water_ambient_reflection_color;

// Red is absorbed fastest, blue slowest -- gives the shallow-to-deep shift its
// natural warm-to-cool progression without a second color uniform.
const vec3 ABSORB_TINT = vec3(1.0, 0.62, 0.42);

// Octave rotations for the ripple field -- each layer is turned so its lattice never
// lines up with another's, and the long swell travels along SWELL_DIR.
const mat2 RIPPLE_ROT_1 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
const mat2 RIPPLE_ROT_2 = mat2(vec2(-0.6, 0.8), vec2(-0.8, -0.6));
const mat2 RIPPLE_ROT_3 = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28));
const vec2 SWELL_DIR = vec2(0.94, 0.34);
// World units per second the surface travels at flow magnitude 1 (before flow_strength),
// so the same curve reads at the same speed on a large and a small map.
const float FLOW_SPEED_UNITS_PER_SEC = 0.6;
// Below this decoded magnitude a texel is still water: 8-bit mid-grey decodes to 0.004.
const float FLOW_DEAD_ZONE = 0.02;
// Two-phase flow-map advection: each copy of a drifting field is displaced along the
// flow for this many seconds, then reset; the two copies are half a cycle apart and
// cross-faded so neither ever stretches far. A single displaced copy shears apart
// wherever the flow bends, which is exactly the river the map exists for.
const float FLOW_CYCLE_SECONDS = 4.0;
// Extra swell phase speed per unit of flow speed, so a fast channel's long wave hurries.
const float FLOW_SWELL_SPEED_GAIN = 2.0;
// Foam breakup noise is sampled in a basis aligned to the local flow, compressed along it
// and squeezed across it in proportion to speed, so foam patches stretch into streaks
// pointing downstream. Tuned on the River level.
const float FOAM_STREAK_STRETCH = 2.5;
const float FOAM_STREAK_SQUEEZE = 0.6;
// Token wake: downstream of a submerged token the ring's distance is stretched into a
// teardrop and its phase drifts with the flow. Tuned on the River level.
const float WAKE_STRETCH = 2.0;
const float WAKE_DRIFT = 2.0;

varying vec3 world_pos;

// Gradient (Perlin-style) noise with a quintic fade, returning roughly [-1, 1]. Chosen
// over the value noise the previous version used: gradient noise has no visible
// axis-aligned cell edges, which were a large part of the old "blocky" read. Pure math,
// no texture asset -- matches this project's other procedural shaders.
vec2 water_grad_hash(vec2 p) {
	vec2 h = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(h) * 43758.5453123);
}

float water_gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(water_grad_hash(i), f);
	float b = dot(water_grad_hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(water_grad_hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(water_grad_hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 1.4 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Same noise, returning (value, d/dx, d/dy) with the derivative computed analytically
// from the same lattice gradients -- one evaluation gives both the height (crest
// highlight) and the exact slope (normal), with no finite differencing and none of the
// stair-stepping a finite difference picks up from the quintic fade.
vec3 water_gnoise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = water_grad_hash(i);
	vec2 gb = water_grad_hash(i + vec2(1.0, 0.0));
	vec2 gc = water_grad_hash(i + vec2(0.0, 1.0));
	vec2 gd = water_grad_hash(i + vec2(1.0, 1.0));
	float va = dot(ga, f);
	float vb = dot(gb, f - vec2(1.0, 0.0));
	float vc = dot(gc, f - vec2(0.0, 1.0));
	float vd = dot(gd, f - vec2(1.0, 1.0));
	float k = va - vb - vc + vd;
	float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
	vec2 deriv = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
		+ du * (u.yx * k + vec2(vb, vc) - va);
	return 1.4 * vec3(value, deriv);
}

// One rotated, drifting noise octave of the ripple field. Returns (height, dh/dx, dh/dz)
// in world units; the chain rule through the rotation is `grad * rot`, which GLSL
// evaluates as transpose(rot) * grad.
vec3 water_ripple_octave(vec2 p, mat2 rot, float freq, vec2 drift, float amp) {
	vec3 n = water_gnoise_d(rot * p * freq + drift);
	return vec3(n.x, (n.yz * rot) * freq) * amp;
}

// Ripple height field: three (four with fine detail) octaves of gradient noise, each
// rotated and drifting its own way so the surface reads as organic, wandering ripples
// with no repeating corrugation, plus one long directional swell so it also has a
// sense of travel; with a flow map the swell travels along the local flow, faster in
// fast water, otherwise along SWELL_DIR. Frequencies are fixed multiples of ripple_scale.
// aa_fine fades the finest octave as it nears one screen pixel per feature so extreme
// zoom-out stays smooth instead of aliasing.
vec3 water_ripple(vec2 p, float t, float aa_fine, vec2 flow) {
	float f = ripple_scale;
	vec3 sum = water_ripple_octave(p, mat2(vec2(1.0, 0.0), vec2(0.0, 1.0)), f, vec2(t * 0.35, t * 0.2), 1.0);
	sum += water_ripple_octave(p, RIPPLE_ROT_1, f * 2.1, vec2(-t * 0.3, t * 0.45), 0.5);
	sum += water_ripple_octave(p, RIPPLE_ROT_2, f * 4.3, vec2(t * 0.5, -t * 0.4), 0.25);
	if (!water_quality_skip_fine_detail) {
		sum += water_ripple_octave(p, RIPPLE_ROT_3, f * 8.5, vec2(-t * 0.7, -t * 0.55), 0.12 * aa_fine);
	}
	float flow_len = length(flow);
	vec2 swell_dir = flow_len > 0.0 ? flow / flow_len : SWELL_DIR;
	float swell_speed = 1.2 + flow_len * FLOW_SWELL_SPEED_GAIN;
	float swell_phase = dot(swell_dir, p) * f * 0.5 - t * swell_speed;
	sum += vec3(sin(swell_phase), cos(swell_phase) * f * 0.5 * swell_dir) * 0.4;
	return sum;
}

// Ridged noise product -- two moving layers of |gradient noise| inverted so their zero
// crossings become bright lines, multiplied so only their intersections stay bright, then
// sharpened. Reads as the wandering light network real caustics make on a shallow bed.
float water_caustic(vec2 p, float t) {
	float c1 = 1.0 - abs(water_gnoise(p + vec2(t * 0.30, t * 0.21)));
	float c2 = 1.0 - abs(water_gnoise(p * 1.7 + vec2(-t * 0.24, t * 0.33) + vec2(13.7, 5.1)));
	return pow(clamp(c1 * c2, 0.0, 1.0), 3.0);
}

// View-space linear depth of the opaque scene at a screen UV -- the standard Godot
// screen-space depth reconstruction (see Godot's official water-shader demos).
float water_scene_depth(vec2 uv, mat4 inv_projection) {
	float depth_raw = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth_raw);
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return -view.z / view.w;
}


// World-XZ flow at this fragment: the plane-local direction from the map, rotated by the
// plane's own model matrix (which carries its rotation and the level scale), times the
// baked speed factor, flow_strength and the nominal travel speed. Zero without a map.
vec2 water_flow(vec2 uv, mat4 model) {
	if (!water_flow_present) {
		return vec2(0.0);
	}
	vec2 f = texture(water_flow_map, uv).rg * 2.0 - 1.0;
	float speed = length(f);
	if (speed <= FLOW_DEAD_ZONE) {
		return vec2(0.0);
	}
	// Blender local (x, y) is glTF/Godot local (x, 0, -y): the swap the exporter applies
	// to the mesh itself, so the direction lands on the same geometry it was baked over.
	vec3 local_dir = vec3(f.x, 0.0, -f.y) / speed;
	vec2 world_dir = (model * vec4(local_dir, 0.0)).xz;
	float world_len = length(world_dir);
	if (world_len <= 0.0001) {
		return vec2(0.0);
	}
	return world_dir / world_len * speed * flow_strength * FLOW_SPEED_UNITS_PER_SEC;
}


// Coordinates for the foam breakup noise: unchanged with no flow, otherwise rotated into
// the (along, across) basis of the local flow and stretched along it.
vec2 water_flow_aligned(vec2 q, vec2 flow, float speed) {
	if (speed <= 0.0) {
		return q;
	}
	vec2 d = flow / speed;
	vec2 n = vec2(-d.y, d.x);
	return vec2(
		dot(q, d) / (1.0 + FOAM_STREAK_STRETCH * speed),
		dot(q, n) * (1.0 + FOAM_STREAK_SQUEEZE * speed)
	);
}

// The animated breakup both foam sources share (see the Foam section of fragment()).
float water_foam_noise(vec2 q, float t) {
	return water_gnoise(q * 3.1 + vec2(t * 0.35, -t * 0.2)) * 0.6
		+ water_gnoise(q * 7.4 - vec2(t * 0.2, t * 0.45)) * 0.4;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float bob = sin(world_pos.x * 0.6 + t) * cos(world_pos.z * 0.5 - t * 1.3);
	VERTEX.y += bob * bob_height;
}


void fragment() {
	float t = TIME * wave_speed;
	vec2 p = world_pos.xz;
	// World units covered by one screen pixel -- used to fade anything whose frequency
	// exceeds what the current zoom can resolve, and to normalize the slope detector.
	float world_units_per_pixel = length(fwidth(p)) + 0.0001;

	// ---- Flow -----------------------------------------------------------------------
	// Two displaced copies of every drifting field (ripples, caustics, foam breakup),
	// half a cycle apart, cross-faded by flow_w. Zero flow makes p0 == p1 == p and every
	// branch below skips the second copy, so lakes and older maps pay one branch and a few
	// ALU ops.
	vec2 flow_ws = water_flow(UV, MODEL_MATRIX);
	float flow_speed = length(flow_ws);
	// Advection runs on raw TIME, not t: flow is a world-units-per-second quantity, so
	// wave_speed does not slow the current (and wave_speed 0 no longer freezes a flowing
	// plane).
	float flow_phase0 = fract(TIME / FLOW_CYCLE_SECONDS);
	float flow_phase1 = fract(flow_phase0 + 0.5);
	// Weight of the second copy: 1 exactly when the first copy resets (hiding its jump),
	// 0 exactly when the second one resets.
	float flow_w = abs(2.0 * flow_phase0 - 1.0);
	vec2 p0 = p - flow_ws * flow_phase0 * FLOW_CYCLE_SECONDS;
	vec2 p1 = p - flow_ws * flow_phase1 * FLOW_CYCLE_SECONDS;

	// ---- Surface normal from the layered ripple field ---------------------------------
	float fine_features_per_pixel = ripple_scale * 8.5 * world_units_per_pixel;
	float aa_fine = 1.0 - smoothstep(0.15, 0.4, fine_features_per_pixel);
	vec3 wave = water_ripple(p0, t, aa_fine, flow_ws);
	if (flow_speed > 0.0) {
		wave = mix(wave, water_ripple(p1, t, aa_fine, flow_ws), flow_w);
	}
	// Sum of octave amplitudes normalizes the height into roughly [-1, 1] for the crest term.
	float crest = wave.x / 2.2;
	vec2 grad = wave.yz * ripple_strength * 0.25;

	// Persistent ripple rings around any token currently standing in the water (see
	// WaterRippleRegistry / WaterZone) -- distance-based falloff around each active
	// disturbance point, layered on top of the ambient waves above.
	vec2 disturbance_grad = vec2(0.0);
	float disturbance_boost = 0.0;
	for (int i = 0; i < 8; i++) {
		if (water_disturbance_points[i].w < 0.5) {
			continue;
		}
		vec2 to_point = p - water_disturbance_points[i].xy;
		float dist = length(to_point);
		float along = 0.0;
		if (flow_speed > 0.0) {
			// Wake: measure distance in the flow basis with the downstream half compressed,
			// so the ring region becomes a teardrop trailing the token. Flow is read at the
			// fragment rather than at the token; over a ripple radius the two agree.
			vec2 d = flow_ws / flow_speed;
			along = dot(to_point, d);
			float across = dot(to_point, vec2(-d.y, d.x));
			float stretched = along > 0.0 ? along / (1.0 + WAKE_STRETCH * flow_speed) : along;
			dist = length(vec2(stretched, across));
		}
		float falloff = 1.0 - smoothstep(0.0, disturbance_ripple_radius, dist);
		if (falloff <= 0.0) {
			continue;
		}
		float ring = sin(dist * 6.0 - t * 3.0 - max(along, 0.0) * flow_speed * WAKE_DRIFT) * falloff;
		disturbance_grad += normalize(to_point + 0.0001) * ring * disturbance_ripple_strength;
		disturbance_boost += falloff * disturbance_ripple_strength;
	}
	grad += disturbance_grad * 0.2;

	// World-space normal for a Y-up plane, pushed straight into view space -- independent
	// of whatever tangent basis (if any) the imported plane carries.
	vec3 world_normal = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// ---- Depth of the bed below this fragment ---------------------------------------
	float water_surface_depth = -VERTEX.z;
	float bed_depth = max(water_scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) - water_surface_depth, 0.0);
	// 0 right at the shoreline, saturating toward 1 over shore_depth_range.
	float depth01 = 1.0 - exp(-bed_depth / shore_depth_range);
	vec3 tint = mix(shore_color.rgb, water_color.rgb, depth01);

	// ---- Bed color: refracted screen prepass, absorbed and caustic-lit --------------
	vec3 surface = tint;
	float alpha = mix(shore_color.a, water_color.a, depth01) + fresnel * fresnel_strength;
	if (!water_quality_skip_refraction) {
		vec2 refract_uv = clamp(SCREEN_UV + grad * refraction_strength, vec2(0.001), vec2(0.999));
		// Classic shoreline-bleed guard: if the offset sample lands on geometry that is in
		// front of the water surface (a bank, a token), it is not "under" this water, so
		// fall back to the unrefracted sample rather than smearing the bank into the river.
		float refracted_bed_depth = water_scene_depth(refract_uv, INV_PROJECTION_MATRIX) - water_surface_depth;
		if (refracted_bed_depth < 0.0) {
			refract_uv = SCREEN_UV;
			refracted_bed_depth = bed_depth;
		}
		vec3 bed = textureLod(screen_tex, refract_uv, 0.0).rgb;
		if (!water_quality_skip_fine_detail) {
			float caustic_cycles_per_pixel = caustic_scale * 1.7 * world_units_per_pixel;
			float aa_caustic = 1.0 - smoothstep(0.12, 0.3, caustic_cycles_per_pixel);
			float caustic = water_caustic(p0 * caustic_scale, t) * aa_caustic;
			if (flow_speed > 0.0) {
				caustic = mix(caustic, water_caustic(p1 * caustic_scale, t) * aa_caustic, flow_w);
			}
			// Multiplicative so the pattern keeps the bed's own hue, plus a small additive
			// lift toward white so it reads as focused light rather than a saturated stain.
			float caustic_lift = caustic * caustic_strength * (1.0 - depth01);
			bed += caustic_lift * (bed + vec3(0.25));
		}
		// Beer-Lambert transmittance of the bed color through the water column.
		vec3 transmittance = exp(-max(refracted_bed_depth, 0.0) * depth_absorption * ABSORB_TINT);
		surface = mix(tint, bed, transmittance);
		alpha = 1.0;
	}

	// ---- Crest shimmer and sky blend --------------------------------------------------
	float shimmer = clamp(
		smoothstep(0.65, 1.0, crest) * shimmer_strength + disturbance_boost * 0.3, 0.0, 1.0
	);
	surface = mix(surface, shimmer_color, shimmer * 0.35);
	surface = mix(
		surface, water_ambient_reflection_color, sky_blend_strength * mix(0.3, 1.0, fresnel)
	);

	// ---- Foam -------------------------------------------------------------------------
	// Thin soft shoreline band (a small fraction of shore_depth_range -- tabletop rivers
	// are only a few tenths of a unit deep, so a wide band would swallow the whole
	// channel), pulsing slowly so it reads as lapping rather than a static stripe. The
	// pulse spans under one cycle across the band so it never forms iso-depth stripes.
	float foam_band_width = shore_depth_range * 0.2;
	float shore_foam = 1.0 - smoothstep(0.0, foam_band_width, bed_depth);
	float lap = 0.75 + 0.25 * sin(bed_depth * (4.0 / foam_band_width) - t * 2.0);
	shore_foam *= lap;
	// Depth-slope detector for rocks and near-vertical banks breaking the surface,
	// normalized to world units so its sensitivity does not change with camera zoom. The
	// slope is depth change per world unit of travel, so 1.0 is a 45 degree bank; the
	// preset sensitivities sit well above that, otherwise every gently sloping riverbed
	// under the shallows foams over.
	float depth_slope = fwidth(bed_depth) / world_units_per_pixel;
	float edge_foam = smoothstep(foam_edge_sensitivity, foam_edge_sensitivity * 3.0, depth_slope);
	// Animated breakup so both foam sources form patches instead of a flat fill.
	// Streaks: the breakup noise is advected two-phase like the ripples and stretched
	// along the flow, so shore foam and rock foam both trail downstream.
	float foam_noise = water_foam_noise(water_flow_aligned(p0, flow_ws, flow_speed), t);
	if (flow_speed > 0.0) {
		float foam_noise_1 = water_foam_noise(water_flow_aligned(p1, flow_ws, flow_speed), t);
		foam_noise = mix(foam_noise, foam_noise_1, flow_w);
	}
	float foam_pattern = smoothstep(-0.25, 0.45, foam_noise);
	float foam = clamp((shore_foam + edge_foam * 0.8) * foam_pattern * foam_strength, 0.0, 1.0);
	surface = mix(surface, foam_color.rgb, foam * foam_color.a);

	ALBEDO = surface;
	ALPHA = clamp(alpha + foam * 0.3, 0.0, 1.0);
	SPECULAR = specular_value;
	// Foam is matte; wave crests are slightly glossier than the troughs so the glint sits
	// where a real surface would catch it.
	ROUGHNESS = clamp(mix(roughness_value - shimmer * 0.05, 0.9, foam), 0.0, 1.0);
	METALLIC = 0.0;
}
