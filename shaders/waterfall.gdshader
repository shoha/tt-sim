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
 *            side edge fade, COLOR.a the fall's crest width over WIDTH_DECODE_M
 *            (WaterFallMesh.WIDTH_ENCODE_M); NORMAL the surface normal facing downstream.
 *   ring     UV (metres across, metres downstream) from its centre, UV2 (radius, pool level),
 *            COLOR.r 1 at the centre to 0 at the rim.
 *   mist     all four vertices at the puff's centre, UV the corner (0..1), UV2 the corner's
 *            offset in metres (camera right, up), COLOR.b the puff's seed.
 *
 * The look (P4c-6b) is painterly: a handful of broad shapes, not fine noise. White water is
 * luminous white with a pale sky-blue shadow side (FOAM_SHADOW_TINT on the emission, so it
 * never goes grey in the cliff's shadow); the glass between is the water palette as a tint.
 *
 * Curtain: white water at the lip roll and toward the pool, translucent glass between, in
 * a few broad tongues. The tongues are gradient noise sampled in (across, fall time) space,
 * t_fall = sqrt(2 v / g), scrolled slowly by the clock, so a band at v = g (t - t0)^2 / 2
 * falls with the water: accelerating and lengthening down the curtain. The roll over the
 * brink breaks into bold scallops (LIP_SCALLOP_*): along the water's run from the lip
 * (lip_run(), metres, from the mesh's level strip and the nominal launch speed) the white
 * starts where a slow noise across the lip says, glass before it, so the brink is never a
 * straight line; its lower edge wavers the same way. The far LIP_FLOOR_M of the level
 * strip is white whatever the scallops do (P4c-6c): an away-facing fall shows only that
 * strip, and the cue must read as water pouring over the brink, not a pale band. Broad
 * noise bites the side edges through COLOR.r (EDGE_BITE, deeper over the lowest
 * BOTTOM_TAPER_SHARE so the sheet tapers), and the bottom tears up to BOTTOM_TEAR_M above
 * the pool level (UV2.y against the world height), where the foam ring takes over. The
 * tongues tilt the normal, roughness sits about 0.5 on the glass. No FRONT_FACING flip:
 * Godot already flips the back face's normal of a cull_disabled material (probe d), so an
 * away-facing fall is lit from the viewer's side as a facing one is.
 *
 * Width (P4c-6c): the aeration and the edge bite were tuned on a 1.3 m curtain, and a 0.5 m
 * ankle fall came out mostly glass with its sides bitten to nothing. The fall's crest width
 * (COLOR.a) now blends the two regimes: a fall NARROW_WIDTH_M or narrower is a bright white
 * ribbon (NARROW_* air high, the bite shallow, the tongues gentle brightness bands); a fall
 * WIDE_WIDTH_M or wider keeps the glass between bold tongues; between them, a mix.
 *
 * Ring: bold white arcs spreading outward from the curtain's foot (RING_FOOT radii upstream
 * of the centre, WaterFallMesh.RING_FORWARD), RING_ARCS per radius at RING_ARC_SPEED, broken
 * by churn noise advected the same way, densest at the foot and thinning to nothing before
 * the rim, so it reads as churn on the pool and never as a plate. Its vertices ride the
 * water shader's bob exactly (the same formula and uniforms) over the 1 cm the mesh lifts
 * them.
 *
 * Mist: vertex billboards (the P4c-0 probe c form), each puff rising MIST_RISE_M and growing
 * over a MIST_CYCLE_S cycle at its own phase (COLOR.b). A puff is three overlapping round
 * lobes (MIST_LOBE_*, laid out by the seed and spreading over the cycle) with a light domain
 * warp, summed into one rounded cloud whose rim softens over the outer MIST_LOBE_SOFT of
 * each lobe's radius (P4c-6c: a hard clip to the quad and a re-sharpened body made the
 * lobes white blobs), bright white in the core and sky blue at the rim, faded where the
 * scene is within MIST_SOFT_M behind it (hint_depth_texture), so it never cuts the rock or
 * the pool. The lobes stay inside the quad by construction (spread + radius + warp under
 * 1), so nothing is clipped. WaterFallMesh grows the mesh's custom AABB for the rise and
 * growth (MIST_SHADER_RISE_M, MIST_SHADER_GROW mirror the constants here).
 *
 * Water Quality (Settings > Graphics): water_quality_skip_fine_detail drops the second noise
 * octave of the tongues, the scallops, the edge bite and the churn (never the shapes
 * themselves), and discards the mist entirely.
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
// Alpha of the glassy water between the streaks (the rock shows through it). 0.6 read as
// an opaque sheet at zoom 8 with BASE_AIR 0.25 (the P4c-6 judgment set); 0.5 with 0.12.
uniform float glass_alpha : hint_range(0.0, 1.0) = 0.5;
// How much the streaks whiten the glass.
uniform float streak_strength : hint_range(0.0, 1.0) = 0.8;
// Peak alpha of a mist puff (its core; the rim is softer). 0.35 read as translucent grey
// smudges at zoom 8 (P4c-6); the P4c-6b clouds are meant to be bright.
uniform float mist_alpha : hint_range(0.0, 1.0) = 0.6;
// Self-lit share of the aerated water, so froth stays white in a cliff's or a tree's
// shadow instead of going grey (white water scatters the sky from every side).
uniform float foam_glow : hint_range(0.0, 1.0) = 0.18;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

global uniform bool water_quality_skip_fine_detail;

const float GRAVITY = 9.81;
// White water's self-lit colour is the foam tinted toward a pale sky blue, so its shadow
// side reads blue, never grey; the glow is foam_glow x this gain.
const vec3 FOAM_SHADOW_TINT = vec3(0.74, 0.88, 1.0);
const float FOAM_GLOW_GAIN = 1.6;
// The white roll over the brink: full at the lip, gone this far down (WaterFallMesh.LIP_ROLL_M
// is where the geometry stops running level; the foam bleeds a little past it). 0.6 read as
// a solid white cap a fifth of a tier fall high in every biome of the P4c-6 judgment set.
const float LIP_ROLL_M = 0.4;
// The scallops of the roll: the run along the water (metres from the lip) the white can
// start at (0 to LIP_SCALLOP_REACH_M, by a slow noise across the lip at LIP_SCALLOP_ACROSS per
// metre, LIP_SCALLOP_SPEED per second), the width of a scallop's edge, how far the roll's
// lower edge wavers (metres of fall), and the alpha of the glass over the brink before the
// white starts (the river surface going over the edge).
const float LIP_SCALLOP_REACH_M = 0.3;
const float LIP_SCALLOP_ACROSS = 1.3;
const float LIP_SCALLOP_SPEED = 0.12;
const float LIP_SCALLOP_SOFT_M = 0.08;
const float LIP_WAVER_M = 0.2;
const float LIP_GLASS_ALPHA = 0.55;
// The mesh's level strip over the brink: its first row is ROLL_FIRST_ROW_M of fall
// (WaterFallMesh.ROLL_ROW_FALL_M) and runs LIP_STRIP_RUN_M level along the water
// (WaterFallMesh.LIP_ROLL_M) before the parabola, at the nominal launch speed LIP_V0
// (WaterFallMesh.V0_BASE + V0_PER_SPEED at the default river speed), for lip_run().
const float ROLL_FIRST_ROW_M = 0.03;
const float LIP_STRIP_RUN_M = 0.3;
const float LIP_V0 = 1.4;
// The white floor over the far end of the level strip: from this far before LIP_STRIP_RUN_M
// of run the roll is foam white at alpha 1 whatever the scallops say (the away-facing bar).
const float LIP_FLOOR_M = 0.1;
// The fall's crest width, COLOR.a x this (WaterFallMesh.WIDTH_ENCODE_M); a fall
// NARROW_WIDTH_M or narrower is a white ribbon, WIDE_WIDTH_M or wider the glass-and-tongues
// curtain, between them a blend.
const float WIDTH_DECODE_M = 8.0;
const float NARROW_WIDTH_M = 1.2;
const float WIDE_WIDTH_M = 3.0;
// The lowest share of the drop whitens toward the pool.
const float BOTTOM_WHITE_SHARE = 0.3;
// The curtain's alpha fades to 0 over this much above the bottom tear, which stands up to
// BOTTOM_TEAR_M above the pool level by a slow noise across the fall.
const float BOTTOM_FADE_M = 0.12;
const float BOTTOM_TEAR_M = 0.3;
// A falling sheet is white water more than glass: the aeration everywhere, plus the air
// entrained on the way down, growing over this many metres of fall. (0.25 and 0.3 left no
// glass at all at tabletop zoom, P4c-6.)
const float BASE_AIR = 0.06;
const float ENTRAIN_M = 2.5;
const float ENTRAIN_MAX = 0.15;
// The narrow ribbon's regime: its aeration everywhere and entrained on the way down, the
// gentle brightness bands its tongues become (their weight), its alpha floor, and how far
// the ropes toward the pool still break it (a share of the wide curtain's).
const float NARROW_BASE_AIR = 0.55;
const float NARROW_ENTRAIN_MAX = 0.3;
const float NARROW_BAND = 0.4;
const float NARROW_ALPHA = 0.85;
const float NARROW_ROPES = 0.25;
// The glass between the tongues: the water and shore tints lifted this far toward the foam.
const float GLASS_LIFT = 0.22;
// Tongue noise frequencies: across the curtain (per metre) and along the fall (per second
// of fall time), coarse and fine octaves, and the fine octave's weight. 1.6 across gives a
// waist fall four or five tongues; 2.5 with a 6.0 fine octave at half weight read as fast
// fine streaks (P4c-6).
const float STREAK_ACROSS = 1.6;
const float STREAK_ALONG = 3.0;
const float STREAK_FINE_ACROSS = 4.0;
const float STREAK_FINE_ALONG = 5.5;
const float STREAK_FINE_WEIGHT = 0.35;
// The clock's rate down the curtain, per unit of wave_speed (the bands drift slowly).
const float STREAK_RATE = 0.4;
// How much the tongues tilt the normal.
const float STREAK_NORMAL = 0.08;
// The side edges: how far the bite reaches into the edge fade (COLOR.r units, 1 is
// WaterFallMesh.EDGE_FADE_M), by a broad noise (EDGE_RAG_ACROSS per metre, EDGE_RAG_ALONG per
// second of fall time); the extra taper over the lowest BOTTOM_TAPER_SHARE of the drop; the
// width of the torn edge. EDGE_BITE + BOTTOM_TAPER stays under 1 - EDGE_SOFT, so the
// interior is never touched.
const float EDGE_BITE = 0.5;
const float EDGE_RAG_ACROSS = 1.5;
const float EDGE_RAG_ALONG = 5.0;
const float BOTTOM_TAPER = 0.2;
const float BOTTOM_TAPER_SHARE = 0.45;
const float EDGE_SOFT = 0.12;
// The narrow ribbon's bite and taper: a 0.5 m fall's edge fade covers its whole width
// (COLOR.r peaks at 0.7), so the wide curtain's bite ate it to nothing; 0.15 left the
// sides dead straight at zoom 8.
const float NARROW_EDGE_BITE = 0.3;
const float NARROW_BOTTOM_TAPER = 0.08;
// The ring's churn: the foot's position in radii upstream of the centre
// (WaterFallMesh.RING_FORWARD), how far from it the foam has thinned to nothing (radii),
// the downstream stretch of the churn, the noise scale (per metre), the arcs per radius
// spreading from the foot and their speed (radii per second, per unit of wave_speed).
// 2.2 noise with an unbounded drift streaked into a radial starburst (P4c-6).
const float RING_FOOT = 0.3;
const float RING_REACH = 0.9;
const float RING_STRETCH = 1.25;
const float RING_NOISE = 1.6;
const float RING_ARCS = 2.5;
const float RING_ARC_SPEED = 0.35;
// The churn's advection: cycles per second (per unit of flow_strength) and the travel per
// cycle in noise units (RING_TRAVEL / RING_NOISE metres).
const float RING_CHURN_RATE = 0.3;
const float RING_TRAVEL = 1.0;
// Mist: the rise per cycle (metres), the cycle (seconds), the growth over it, the soft fade
// against the scene (metres); the three lobes of a puff in the quad's -1..1 space (their
// spread from the centre, growing MIST_LOBE_SPREAD_GROW over the cycle; their radii; the
// share of each radius its rim softens over) and the domain warp that wobbles their rims.
// Spread + growth + the largest radius + the warp stays under 1, so no lobe leaves the quad.
const float MIST_RISE_M = 0.5;
const float MIST_CYCLE_S = 4.0;
const float MIST_GROW = 1.3;
const float MIST_SOFT_M = 0.25;
const float MIST_LOBE_SPREAD = 0.22;
const float MIST_LOBE_SPREAD_GROW = 0.08;
const vec3 MIST_LOBE_RADII = vec3(0.55, 0.48, 0.42);
const float MIST_LOBE_SOFT = 0.5;
const float MIST_WARP = 0.1;

varying vec3 world_pos;
varying float kind;
varying float edge;
varying float seed;
varying float fall_width;
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


// The water's run from the lip, in metres, for `v` metres fallen (fall time `t_fall`):
// linear across the mesh's level strip (its first row), then along the parabola at the
// nominal launch speed. Approximate (the real speed is the river's), good enough to place
// the roll's scallops along the brink.
float lip_run(float v, float t_fall) {
	float t_first = sqrt(2.0 * ROLL_FIRST_ROW_M / GRAVITY);
	float strip = LIP_STRIP_RUN_M + LIP_V0 * t_first;
	return strip * clamp(v / ROLL_FIRST_ROW_M, 0.0, 1.0) + LIP_V0 * max(t_fall - t_first, 0.0);
}


// White water's self-lit colour (see FOAM_SHADOW_TINT).
vec3 foam_glow_color() {
	return foam_color.rgb * FOAM_SHADOW_TINT * foam_glow * FOAM_GLOW_GAIN;
}


void vertex() {
	kind = COLOR.g;
	edge = COLOR.r;
	seed = COLOR.b;
	fall_width = COLOR.a * WIDTH_DECODE_M;
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
		// A scalloped cloud: three round lobes laid out by the seed, drifting apart as the
		// puff grows, their rims softened by a slow domain warp.
		float angle = seed * TAU;
		vec2 axis = vec2(cos(angle), sin(angle));
		float spread = MIST_LOBE_SPREAD + MIST_LOBE_SPREAD_GROW * mist_phase;
		vec2 wp = q * 1.7 + seed * 9.0 + vec2(TIME * 0.1, -TIME * 0.2);
		vec2 w = q + MIST_WARP * vec2(fall_gnoise(wp), fall_gnoise(wp + vec2(5.2, 1.3)));
		vec2 c0 = axis * spread + vec2(0.0, -0.05);
		vec2 c1 = -axis * spread * 0.9 + vec2(0.0, 0.05);
		vec2 c2 = vec2(axis.y, -axis.x) * spread * 0.5 + vec2(0.0, 0.25);
		vec3 inner = MIST_LOBE_RADII * (1.0 - MIST_LOBE_SOFT);
		float l0 = 1.0 - smoothstep(inner.x, MIST_LOBE_RADII.x, length(w - c0));
		float l1 = 1.0 - smoothstep(inner.y, MIST_LOBE_RADII.y, length(w - c1));
		float l2 = 1.0 - smoothstep(inner.z, MIST_LOBE_RADII.z, length(w - c2));
		// The lobes add up into one rounded cloud: where two overlap the body is solid,
		// each rim stays as soft as its own falloff.
		float cloud = min(l0 + l1 + l2, 1.0);
		float body = smoothstep(0.0, 0.7, cloud);
		float core = smoothstep(0.55, 1.0, cloud);
		// Born faint, gone faint: no puff pops in or out.
		float life = sin(mist_phase * PI);
		float soft = smoothstep(
			0.0, MIST_SOFT_M, fall_scene_depth(SCREEN_UV, INV_PROJECTION_MATRIX) + VERTEX.z
		);
		// Bright white in the core, sky blue at the rim.
		ALBEDO = mix(foam_color.rgb * FOAM_SHADOW_TINT, foam_color.rgb, core);
		EMISSION = foam_glow_color() * (0.6 + 0.4 * core);
		ALPHA = body * mix(0.75, 1.0, core) * life * soft * mist_alpha;
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
		// The churn spreads outward from the foot with the current: two copies of the noise
		// advected over a bounded cycle each, crossfaded where either wraps (a flow map), so
		// the field never smears into radial spokes as an unbounded drift did (P4c-6b).
		float cycle = TIME * RING_CHURN_RATE * (0.5 + 0.5 * flow_strength);
		float p0 = fract(cycle);
		float p1 = fract(cycle + 0.5);
		float wrap = abs(p0 * 2.0 - 1.0);
		vec2 a0 = uv * RING_NOISE - outward * p0 * RING_TRAVEL;
		vec2 a1 = uv * RING_NOISE - outward * p1 * RING_TRAVEL + 7.0;
		float churn = mix(fall_gnoise(a0), fall_gnoise(a1), wrap);
		if (!water_quality_skip_fine_detail) {
			churn += 0.4 * mix(fall_gnoise(a0 * 2.1 + 11.0), fall_gnoise(a1 * 2.1 + 11.0), wrap);
		}
		churn = churn * 0.5 + 0.5;
		// Bold arcs rolling outward from the foot, broken by the churn.
		float arcs = 0.5 + 0.5 * sin((d * RING_ARCS - TIME * RING_ARC_SPEED * max(wave_speed, 0.2)) * TAU);
		float foam = smoothstep(0.32, 0.6, density * (0.5 + 0.5 * arcs) + (churn - 0.5) * 0.55);
		foam *= smoothstep(0.0, 0.25, edge);
		ALBEDO = foam_color.rgb;
		EMISSION = foam_glow_color() * foam;
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
		float t_now = TIME * STREAK_RATE * (1.0 + wave_speed);
		vec3 coarse = fall_gnoise_d(vec2(u * STREAK_ACROSS, (t_fall - t_now) * STREAK_ALONG));
		float streak = coarse.x;
		vec2 dn = coarse.yz;
		if (!water_quality_skip_fine_detail) {
			vec3 fine = fall_gnoise_d(
				vec2(u * STREAK_FINE_ACROSS + 3.1, (t_fall - t_now * 1.15) * STREAK_FINE_ALONG)
			);
			streak += STREAK_FINE_WEIGHT * fine.x;
			dn += STREAK_FINE_WEIGHT * fine.yz;
		}
		streak = clamp(streak * 0.5 + 0.5, 0.0, 1.0);
		// The roll's scallops: a slow noise across the lip says where along the run the white
		// starts, and how far down the roll's lower edge reaches.
		float scallop_n = fall_gnoise(vec2(u * LIP_SCALLOP_ACROSS + 3.7, TIME * LIP_SCALLOP_SPEED));
		if (!water_quality_skip_fine_detail) {
			scallop_n += 0.35 * fall_gnoise(
				vec2(u * LIP_SCALLOP_ACROSS * 2.3 + 9.1, TIME * LIP_SCALLOP_SPEED * 1.4 + 2.0)
			);
		}
		scallop_n = clamp(scallop_n * 0.5 + 0.5, 0.0, 1.0);
		float run = lip_run(v, t_fall);
		float start = LIP_SCALLOP_REACH_M * scallop_n;
		float scallop = smoothstep(start, start + LIP_SCALLOP_SOFT_M, run);
		float waver = LIP_WAVER_M * (0.5 - scallop_n);
		float roll_fade = 1.0 - smoothstep(0.1 + waver, LIP_ROLL_M + waver, v);
		// The white floor over the far end of the level strip, whatever the scallops say.
		float floor_start = LIP_STRIP_RUN_M - LIP_FLOOR_M;
		float lip_floor = smoothstep(floor_start - LIP_SCALLOP_SOFT_M, floor_start, run) * roll_fade;
		float lip = max(scallop * roll_fade, lip_floor);
		// Over the brink before the white starts: the river surface going over the edge.
		float lip_glass = 1.0 - smoothstep(ROLL_FIRST_ROW_M, 0.2, v);
		// The width regime: 1 on a narrow ribbon, 0 on a wide curtain.
		float narrow = 1.0 - smoothstep(NARROW_WIDTH_M, WIDE_WIDTH_M, fall_width);
		// Aeration: the white roll at the lip, the churn toward the pool, air entrained on the
		// way and the white tongues (gentle brightness bands on a ribbon).
		float bottom = smoothstep(height * (1.0 - BOTTOM_WHITE_SHARE), height, v);
		float entrained = mix(BASE_AIR, NARROW_BASE_AIR, narrow)
			+ smoothstep(0.0, ENTRAIN_M, v) * mix(ENTRAIN_MAX, NARROW_ENTRAIN_MAX, narrow);
		float tongue = smoothstep(0.5, 0.64, streak);
		float band = smoothstep(0.3, 0.8, streak) * NARROW_BAND;
		float streak_foam = mix(tongue * streak_strength, band, narrow) * foam_gain;
		float aeration = clamp(max(lip, bottom) + entrained + streak_foam, 0.0, 1.0);
		// Over the brink before a scallop: the water itself, not foam.
		float brink_glass = lip_glass * (1.0 - scallop) * (1.0 - lip_floor);
		aeration *= 1.0 - brink_glass * 0.9;
		vec3 glass = mix(mix(water_color.rgb, shore_color.rgb, 0.5), foam_color.rgb, GLASS_LIFT);
		glass = mix(
			glass, mix(mix(water_color.rgb, shore_color.rgb, 0.5), foam_color.rgb, 0.1), brink_glass
		);
		vec3 albedo = mix(glass, foam_color.rgb, aeration);
		// The roll over the brink is solid white; between the tongues the rock shows through;
		// the white toward the pool is broken into ropes by the same tongues.
		float alpha = max(mix(glass_alpha * (0.3 + 0.6 * streak), foam_color.a, aeration), lip);
		alpha = max(alpha, narrow * NARROW_ALPHA);
		alpha = mix(alpha, LIP_GLASS_ALPHA, brink_glass);
		alpha *= mix(1.0, 0.35 + 0.65 * tongue, bottom * 0.8 * mix(1.0, NARROW_ROPES, narrow));
		// Torn side edges: broad noise along the fall bites into the edge fade, deeper toward
		// the pool so the sheet tapers.
		float rag = fall_gnoise(vec2(u * EDGE_RAG_ACROSS + 7.3, (t_fall - t_now) * EDGE_RAG_ALONG));
		if (!water_quality_skip_fine_detail) {
			rag += 0.4 * fall_gnoise(
				vec2(u * EDGE_RAG_ACROSS * 2.4 + 1.9, (t_fall - t_now) * EDGE_RAG_ALONG * 2.2)
			);
		}
		// Pushed to its extremes, so the edge alternates between deep bites and full width
		// (bold scallops) rather than wandering gently.
		rag = smoothstep(0.3, 0.7, rag * 0.5 + 0.5);
		float bite = mix(EDGE_BITE, NARROW_EDGE_BITE, narrow);
		float taper = mix(BOTTOM_TAPER, NARROW_BOTTOM_TAPER, narrow)
			* smoothstep(height * (1.0 - BOTTOM_TAPER_SHARE), height, v);
		float edge_mask = smoothstep(0.0, EDGE_SOFT, edge - bite * rag - taper);
		// Tears into the pool: the bottom edge stands up to BOTTOM_TEAR_M over the pool level
		// by a slow noise across the fall; nothing below it, where the foam ring is.
		float tear = fall_gnoise(vec2(u * EDGE_RAG_ACROSS + 2.0, TIME * 0.15)) * 0.5 + 0.5;
		float tear_level = pool + BOTTOM_TEAR_M * tear;
		float pool_fade = smoothstep(tear_level, tear_level + BOTTOM_FADE_M, world_pos.y);
		ALBEDO = albedo;
		EMISSION = foam_glow_color() * aeration;
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
