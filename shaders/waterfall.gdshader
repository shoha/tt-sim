shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

/*
 * Waterfall Shader (phase 4c, P4c-4)
 * ===================================
 *
 * Draws the `AuthoredWater-falls` mesh WaterFallMesh builds (utils/water_fall_mesh.gd): for
 * every fall of an authored map a falling curtain, a foam ring on the plunge pool and a few
 * mist puffs, all in one surface on one shared ShaderMaterial (AuthoredWater.fall_material())
 * at AuthoredWater.FALLS_RENDER_PRIORITY, strictly above the water material's, since at an
 * equal priority the water (alpha 1) paints over the curtain (P4c-0 probe a). No screen
 * texture: the pool's refraction never sees a transparent curtain (probe b), and this pass
 * reads nothing but the depth prepass the water already pays for (probe c).
 *
 * The three kinds are told apart by COLOR.g (0 curtain, 0.5 ring, 1 mist; vertex colours are
 * 8-bit, so the tests are against 0.25 and 0.75). The vertex layout is WaterFallMesh's header:
 *   curtain  UV (metres across, metres fallen), UV2 (fall height, pool level), COLOR.r the
 *            side edge fade; NORMAL the surface normal facing downstream.
 *   ring     UV (metres across, metres downstream) from its centre, UV2 (radius, pool level),
 *            COLOR.r 1 at the centre to 0 at the rim.
 *   mist     all four vertices at the puff's centre, UV the corner (0..1), UV2 the corner's
 *            offset in metres (camera right, up), COLOR.b the puff's seed.
 *
 * Curtain: aeration (white water) at the lip roll and toward the pool, translucent streaky
 * glass between. The streaks are gradient noise sampled in (across, fall time) space,
 * t_fall = sqrt(2 v / g), scrolled by the clock, so a feature at v = g (t - t0)^2 / 2 falls
 * with the water: accelerating and lengthening down the curtain. Ragged noise eats the side
 * edges through COLOR.r; alpha fades to nothing over the last BOTTOM_FADE_M above the pool
 * level (UV2.y against the world height), where the foam ring takes over. The streaks tilt
 * the normal, roughness sits about 0.5 on the glass. No FRONT_FACING flip: Godot already
 * flips the back face's normal of a cull_disabled material (probe d), so an away-facing fall
 * is lit from the viewer's side as a facing one is.
 *
 * Ring: churn noise advected outward from the curtain's foot (RING_FOOT radii upstream of the
 * centre, WaterFallMesh.RING_FORWARD), densest there and thinning to nothing before the rim,
 * with a ragged edge and a slow pulse, so it reads as foam on the pool and never as a plate.
 * Its vertices ride the water shader's bob exactly (the same formula and uniforms) over the
 * 1 cm the mesh lifts them.
 *
 * Mist: vertex billboards (the P4c-0 probe c form), each puff rising MIST_RISE_M and growing
 * over a MIST_CYCLE_S cycle at its own phase (COLOR.b), soft noise puffs at low alpha, faded
 * where the scene is within MIST_SOFT_M behind them (hint_depth_texture), so they never cut
 * the rock or the pool. WaterFallMesh grows the mesh's custom AABB for the rise and growth
 * (MIST_SHADER_RISE_M, MIST_SHADER_GROW mirror the constants here).
 *
 * Water Quality (Settings > Graphics): water_quality_skip_fine_detail drops the second noise
 * octave of the streaks and the churn, and discards the mist entirely.
 *
 * Settings: the uniforms below that share a name with water.gdshader's are the WaterSettings
 * keys WaterGlbUtils.apply_water_settings() forwards onto the fall material
 * (WaterGlbUtils.FALL_SETTINGS_KEYS), so a palette or motion tile restyles the falls live and
 * over the network with no new LevelData field. Keep the names exactly.
 */

// ---- Shared with water.gdshader (forwarded by WaterGlbUtils.apply_water_settings) --------
uniform vec4 water_color : source_color = vec4(0.05, 0.30, 0.38, 0.8);
uniform vec4 shore_color : source_color = vec4(0.35, 0.75, 0.70, 0.6);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.96, 0.9);
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float bob_height : hint_range(0.0, 0.2) = 0.02;
uniform float flow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;

// ---- The falls' own -----------------------------------------------------------------------
// Alpha of the glassy water between the streaks (the rock shows through it).
uniform float glass_alpha : hint_range(0.0, 1.0) = 0.6;
// How much the streaks whiten the glass.
uniform float streak_strength : hint_range(0.0, 1.0) = 0.8;
// Peak alpha of a mist puff.
uniform float mist_alpha : hint_range(0.0, 1.0) = 0.35;
// Self-lit share of the aerated water, so froth stays white in a cliff's or a tree's
// shadow instead of going grey (white water scatters the sky from every side).
uniform float foam_glow : hint_range(0.0, 1.0) = 0.18;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

global uniform bool water_quality_skip_fine_detail;

const float GRAVITY = 9.81;
// The white roll over the brink: full at the lip, gone this far down (WaterFallMesh.LIP_ROLL_M
// is where the geometry stops running level; the foam bleeds a little past it).
const float LIP_ROLL_M = 0.6;
// The lowest share of the drop whitens toward the pool.
const float BOTTOM_WHITE_SHARE = 0.35;
// The curtain's alpha fades to 0 over this much above the pool level.
const float BOTTOM_FADE_M = 0.1;
// A falling sheet is white water more than glass: the aeration everywhere, plus the air
// entrained on the way down, growing over this many metres of fall.
const float BASE_AIR = 0.25;
const float ENTRAIN_M = 2.5;
const float ENTRAIN_MAX = 0.3;
// The glass between the streaks: the shore and water tints lifted this far toward the foam.
const float GLASS_LIFT = 0.3;
// Streak noise frequencies: across the curtain (per metre) and along the fall (per second
// of fall time), coarse and fine octaves.
const float STREAK_ACROSS = 2.5;
const float STREAK_ALONG = 4.0;
const float STREAK_FINE_ACROSS = 6.0;
const float STREAK_FINE_ALONG = 7.0;
// How much the streaks tilt the normal.
const float STREAK_NORMAL = 0.08;
// The ring's churn: the foot's position in radii upstream of the centre
// (WaterFallMesh.RING_FORWARD), how far from it the foam has thinned to nothing (radii),
// the downstream stretch of the churn, and the noise scale (per metre).
const float RING_FOOT = 0.3;
const float RING_REACH = 0.9;
const float RING_STRETCH = 1.25;
const float RING_NOISE = 2.2;
// Mist: the rise per cycle (metres), the cycle (seconds), the growth over it, the soft fade
// against the scene (metres).
const float MIST_RISE_M = 0.9;
const float MIST_CYCLE_S = 4.0;
const float MIST_GROW = 1.3;
const float MIST_SOFT_M = 0.25;

varying vec3 world_pos;
varying float kind;
varying float edge;
varying float seed;
varying vec2 uv;
varying vec2 uv2;
varying float mist_phase;


// Gradient noise with a quintic fade (water.gdshader's), roughly [-1, 1].
vec2 fall_grad_hash(vec2 p) {
	vec2 h = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(h) * 43758.5453123);
}


float fall_gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(fall_grad_hash(i), f);
	float b = dot(fall_grad_hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(fall_grad_hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(fall_grad_hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 1.4 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


// The same noise with its analytic derivative: (value, d/dx, d/dy).
vec3 fall_gnoise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = fall_grad_hash(i);
	vec2 gb = fall_grad_hash(i + vec2(1.0, 0.0));
	vec2 gc = fall_grad_hash(i + vec2(0.0, 1.0));
	vec2 gd = fall_grad_hash(i + vec2(1.0, 1.0));
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


// View-space depth of the opaque scene at screen `screen_uv` (the water shader's form).
float fall_scene_depth(vec2 screen_uv, mat4 inv_projection) {
	float depth_raw = texture(depth_tex, screen_uv).r;
	vec4 view = inv_projection * vec4(screen_uv * 2.0 - 1.0, depth_raw, 1.0);
	return -(view.z / view.w);
}


void vertex() {
	kind = COLOR.g;
	edge = COLOR.r;
	seed = COLOR.b;
	uv = UV;
	uv2 = UV2;
	mist_phase = 0.0;
	if (COLOR.g > 0.75) {
		// Mist: a billboard that rises, grows and sways over its cycle, at the puff's phase.
		float cycle = fract(TIME / MIST_CYCLE_S + COLOR.b);
		mist_phase = cycle;
		vec2 off = UV2 * mix(1.0, MIST_GROW, cycle);
		float sway = sin(TIME * 0.7 + COLOR.b * TAU) * 0.12;
		VERTEX.y += cycle * MIST_RISE_M;
		VERTEX += INV_VIEW_MATRIX[0].xyz * (off.x + sway) + INV_VIEW_MATRIX[1].xyz * off.y;
	} else if (COLOR.g > 0.25) {
		// Ring: the water shader's bob, exactly, so it rides the pool's surface.
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME * wave_speed;
		float bob = sin(wp.x * 0.6 + t) * cos(wp.z * 0.5 - t * 1.3);
		VERTEX.y += bob * bob_height;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	float foam_gain = clamp(foam_strength, 0.5, 1.5);
	if (kind > 0.75) {
		// ---- Mist ---------------------------------------------------------------------------
		if (water_quality_skip_fine_detail) {
			discard;
		}
		vec2 q = uv * 2.0 - 1.0;
		float puff = 1.0 - smoothstep(0.15, 1.0, length(q));
		float n = fall_gnoise(q * 2.2 + seed * 9.0 + vec2(TIME * 0.12, -TIME * 0.25)) * 0.5 + 0.5;
		float body = smoothstep(0.1, 0.65, puff * (0.6 + 0.8 * n));
		// Born faint, gone faint: no puff pops in or out.
		float life = sin(mist_phase * PI);
		float soft = smoothstep(
			0.0, MIST_SOFT_M, fall_scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z
		);
		ALBEDO = foam_color.rgb;
		EMISSION = foam_color.rgb * foam_glow;
		ALPHA = body * life * soft * mist_alpha;
		NORMAL = vec3(0.0, 0.0, 1.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		METALLIC = 0.0;
	} else if (kind > 0.25) {
		// ---- Foam ring ----------------------------------------------------------------------
		float radius = max(uv2.x, 1e-3);
		vec2 q = uv / radius;
		vec2 from_foot = (q - vec2(0.0, -RING_FOOT)) * vec2(RING_STRETCH, 1.0);
		float d = length(from_foot);
		vec2 outward = from_foot / max(d, 1e-3);
		float density = 1.0 - smoothstep(0.1, RING_REACH, d);
		// The churn spreads outward from the foot with the current.
		float drift = TIME * (0.35 + 0.35 * flow_strength);
		float churn = fall_gnoise(uv * RING_NOISE - outward * drift * 0.8);
		if (!water_quality_skip_fine_detail) {
			churn += 0.5 * fall_gnoise(uv * RING_NOISE * 2.3 - outward * drift * 1.3 + 11.0);
		}
		churn = churn * 0.5 + 0.5;
		float pulse = 0.85 + 0.15 * sin(TIME * 2.0 * max(wave_speed, 0.2) - d * 6.0);
		float foam = smoothstep(0.3, 0.7, density + (churn - 0.5) * 0.8) * pulse;
		foam *= smoothstep(0.0, 0.25, edge);
		ALBEDO = foam_color.rgb;
		EMISSION = foam_color.rgb * foam_glow * foam;
		ALPHA = foam * foam_color.a * foam_gain;
		ROUGHNESS = 0.9;
		SPECULAR = 0.2;
		METALLIC = 0.0;
	} else {
		// ---- Curtain ------------------------------------------------------------------------
		float v = max(uv.y, 0.0);
		float u = uv.x;
		float height = max(uv2.x, 0.01);
		float pool = uv2.y;
		// Fall time: a feature leaving the lip at t0 is at v = g (t - t0)^2 / 2, so noise in
		// (across, t_fall - t) falls with the water, accelerating and lengthening.
		float t_fall = sqrt(2.0 * v / GRAVITY);
		float t_now = TIME * (0.6 + 0.6 * wave_speed);
		vec3 coarse = fall_gnoise_d(vec2(u * STREAK_ACROSS, (t_fall - t_now) * STREAK_ALONG));
		float streak = coarse.x;
		vec2 dn = coarse.yz;
		if (!water_quality_skip_fine_detail) {
			vec3 fine = fall_gnoise_d(
				vec2(u * STREAK_FINE_ACROSS + 3.1, (t_fall - t_now * 1.15) * STREAK_FINE_ALONG)
			);
			streak += 0.5 * fine.x;
			dn += 0.5 * fine.yz;
		}
		streak = clamp(streak * 0.5 + 0.5, 0.0, 1.0);
		// Aeration: the white roll at the lip, the churn toward the pool, air entrained on the
		// way and the brighter streaks.
		float lip = 1.0 - smoothstep(0.1, LIP_ROLL_M, v);
		float bottom = smoothstep(height * (1.0 - BOTTOM_WHITE_SHARE), height, v);
		float entrained = BASE_AIR + smoothstep(0.0, ENTRAIN_M, v) * ENTRAIN_MAX;
		float streak_foam = smoothstep(0.3, 0.75, streak) * streak_strength * foam_gain;
		float aeration = clamp(max(lip, bottom) + entrained + streak_foam, 0.0, 1.0);
		vec3 glass = mix(mix(shore_color.rgb, water_color.rgb, 0.35), foam_color.rgb, GLASS_LIFT);
		vec3 albedo = mix(glass, foam_color.rgb, aeration);
		// The roll over the brink is solid white; between the streaks the rock shows through.
		float alpha = max(mix(glass_alpha * (0.5 + 0.8 * streak), foam_color.a, aeration), lip);
		// Ragged side edges: noise along the fall eats into the edge fade.
		float rag = fall_gnoise(vec2(u * 4.0 + 7.3, (t_fall - t_now) * 4.0)) * 0.5 + 0.5;
		float edge_mask = smoothstep(0.0, 0.5, edge - 0.45 * (1.0 - rag) * (1.0 - edge));
		// Melts into the pool: nothing below the pool level, where the foam ring is.
		float pool_fade = smoothstep(pool, pool + BOTTOM_FADE_M, world_pos.y);
		ALBEDO = albedo;
		EMISSION = foam_color.rgb * foam_glow * aeration;
		ALPHA = clamp(alpha, 0.0, 1.0) * edge_mask * pool_fade;
		// The streaks tilt the normal (view space: across is roughly screen x, down is -y);
		// the foam is matte and flat.
		float tilt = STREAK_NORMAL * (1.0 - aeration * 0.7);
		NORMAL = normalize(NORMAL + vec3(dn.x, -dn.y, 0.0) * tilt);
		ROUGHNESS = mix(0.45, 0.85, aeration);
		SPECULAR = 0.5;
		METALLIC = 0.0;
	}
}
