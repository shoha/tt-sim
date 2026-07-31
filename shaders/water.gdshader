shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

/*
 * Water Shader
 * ============
 *
 * PURPOSE:
 * Automatically applied by GlbUtils.process_water_meshes() (utils/glb_utils.gd) to any
 * mesh whose name ends in "-water" in a runtime-loaded GLB map. Gives terrain-paint
 * water planes (see the terrain-paint Blender addon's README "Water" section) a real
 * animated look with zero per-map setup -- the Blender-side plane only needs the right
 * name suffix, no material tuning survives export or needs to.
 *
 * DESIGN:
 * tt-sim's camera is an oblique/top-down tabletop view (see DragAndDrop3D, grid snap),
 * not a first-person swimming view, so this deliberately skips true wave geometry -- a
 * small sine-based vertex bob gives just enough sense of motion, while the actual
 * "water" read comes from a procedural (no texture asset) scrolling-noise ripple normal
 * plus a fresnel-driven rim, both clearly visible from any oblique angle.
 *
 * MANAGED BY: GlbUtils._get_water_material() builds one shared ShaderMaterial instance
 * from this shader at the defaults below and reuses it across every map -- there's no
 * per-map tuning yet (matches the naming-convention-only, zero-manual-setup design).
 */

uniform vec4 water_color : source_color = vec4(0.04, 0.22, 0.28, 0.75);
// Shallow-water tint blended in near the shoreline (see depth_tex below) -- lighter and
// more saturated than water_color so the same plane reads as "shallow" near shore and
// "deep" further out, instead of a single flat tint across the whole mesh.
uniform vec4 shore_color : source_color = vec4(0.35, 0.75, 0.7, 0.55);
// How many view-space units of depth separation from shore -> "fully deep" -- small
// values give a thin, crisp shoreline band; large values fade the shore tint gradually
// across most of the water body, which reads wrong for tabletop-scale ponds/lakes.
uniform float shore_depth_range : hint_range(0.05, 3.0) = 0.6;
uniform vec3 shimmer_color : source_color = vec3(0.65, 0.85, 0.9);
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.08;
// Kept as a separate uniform (rather than a baked constant) so a brighter/duller glint
// can be dialed in later without touching the shader -- SPECULAR has no default lighting
// contribution of its own in Godot's spatial shader, so this must be set explicitly.
uniform float specular_value : hint_range(0.0, 1.0) = 0.6;
uniform float wave_speed : hint_range(0.0, 5.0) = 0.6;
uniform float ripple_scale : hint_range(0.1, 20.0) = 4.0;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.6;
uniform float bob_height : hint_range(0.0, 0.2) = 0.02;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.5;
// Screen-space refraction strength -- reuses the ripple gradient (see grad below) as a
// UV offset so refraction distorts in sync with the visible ripple normal instead of
// needing its own noise pass. Capped low (hint_range max 0.2) because at tabletop zoom
// levels even a small UV offset reads as a large visual shift of the terrain underneath.
uniform float refraction_strength : hint_range(0.0, 0.2) = 0.04;
// hint_depth_texture / hint_screen_texture pull Godot's built-in depth and opaque-color
// prepasses -- both require blend_mix (already set above) and only see geometry drawn
// before this transparent pass, which is exactly the terrain/tokens under the water.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 world_pos;

// Cheap hash-based value noise -- no texture asset needed, matches this project's other
// procedural shaders (e.g. occlusion_fade.gdshader builds its Bayer dither the same way:
// pure math, no sampler).
float water_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float water_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = water_hash(i);
	float b = water_hash(i + vec2(1.0, 0.0));
	float c = water_hash(i + vec2(0.0, 1.0));
	float d = water_hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float bob = sin(world_pos.x * 0.6 + t) * cos(world_pos.z * 0.5 - t * 1.3);
	VERTEX.y += bob * bob_height;
}


void fragment() {
	float t = TIME * wave_speed;
	// The second octave is rotated 37 degrees from the first (rather than just scaled)
	// so their grid-aligned interpolation artifacts don't reinforce each other -- plain
	// value noise (unlike gradient/simplex noise) shows visible axis-aligned blockiness
	// on its own; summing two differently-oriented layers breaks that up.
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 uv_a = world_pos.xz * ripple_scale + vec2(t * 0.4, t * 0.28);
	vec2 uv_b = rot * world_pos.xz * ripple_scale * 2.3 - vec2(t * 0.25, t * 0.36);
	float n_a = water_noise(uv_a);
	float n_b = water_noise(uv_b);

	// A third, finer/faster octave feeds only the shimmer highlight (not the normal
	// gradient below, to keep the per-pixel cost down) -- breaks up the two-octave
	// pattern's large single-scale "blocky" cells into finer sparkle detail, which
	// reads much more like water glinting than plain value noise does on its own.
	vec2 uv_c = rot * world_pos.xz * ripple_scale * 5.1 + vec2(t * 0.6, -t * 0.5);
	float n_c = water_noise(uv_c);

	// Approximate a normal-map perturbation from each noise layer's local gradient
	// (proper finite-difference derivative, divided by eps) rather than sampling an
	// actual normal texture -- cheap, tileless, and seamless at any scale or map size.
	float eps = 0.08;
	vec2 grad_a = vec2(water_noise(uv_a + vec2(eps, 0.0)) - n_a, water_noise(uv_a + vec2(0.0, eps)) - n_a) / eps;
	vec2 grad_b = vec2(water_noise(uv_b + vec2(eps, 0.0)) - n_b, water_noise(uv_b + vec2(0.0, eps)) - n_b) / eps;
	vec2 grad = (grad_a + grad_b) * ripple_strength * 0.15;

	NORMAL_MAP = normalize(vec3(-grad, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// Reconstruct the view-space depth of whatever opaque geometry is behind this water
	// fragment (terrain, riverbed, tokens) and compare it to the water surface's own
	// view-space depth -- this is the standard Godot screen-space water depth-difference
	// pattern (see Godot's official water-shader demos), not something derived here from
	// scratch. depth_diff is ~0 right at the shoreline (opaque geometry sits close behind
	// the water surface) and rises to 1 in open/deep water, giving a cheap, texture-free
	// stand-in for actual water depth without needing a baked depth map per map.
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_surface_depth = -VERTEX.z;
	float depth_diff = clamp((scene_depth - water_surface_depth) / shore_depth_range, 0.0, 1.0);

	// Bright sparkle patches wherever the blended noise layers peak -- guarantees
	// visible ripple variation in ALBEDO itself, not just in the (much subtler)
	// lighting response to NORMAL_MAP, so the effect still reads even under flat/
	// ambient light. Averaging three differently-scaled/rotated layers (rather than
	// thresholding a single one) softens plain value noise's characteristic blocky
	// cell edges into finer, more organic-looking sparkle.
	float blended = (n_a + n_b + n_c) / 3.0;
	float shimmer = smoothstep(0.45, 0.85, blended) * shimmer_strength;

	// Depth-blended base replaces the old flat water_color -- shore_color near the bank,
	// water_color further out -- with the shimmer sparkle layered on top of that blend
	// rather than replacing it, so glints still show at any depth.
	vec3 depth_color = mix(shore_color.rgb, water_color.rgb, depth_diff);
	float depth_alpha = mix(shore_color.a, water_color.a, depth_diff);
	vec3 base_color = mix(depth_color, shimmer_color, shimmer);

	// Screen-space refraction reuses `grad` (the same ripple gradient driving
	// NORMAL_MAP) so the terrain-under-water distortion animates in lockstep with the
	// visible ripple normal instead of needing a second noise sample. Weighted by
	// (1.0 - depth_diff) so shallow water near the shore shows more of the refracted
	// terrain underneath (matching real water's transparency at low depth) while deep
	// water leans on the tinted color instead -- clamped well inside [0,1] to avoid
	// sampling outside the screen texture at the viewport edges.
	vec2 refract_uv = clamp(SCREEN_UV + grad * refraction_strength, vec2(0.001), vec2(0.999));
	vec3 refracted = textureLod(screen_tex, refract_uv, 0.0).rgb;
	vec3 final_color = mix(base_color, refracted, (1.0 - depth_diff) * 0.6);

	ALBEDO = final_color;
	ALPHA = clamp(depth_alpha + fresnel * fresnel_strength, 0.0, 1.0);
	SPECULAR = specular_value;
	// Shimmer peaks get slightly smoother (lower roughness) instead of a flat
	// roughness_value everywhere -- a uniform roughness makes the shimmer read as a
	// color-only sparkle, while dipping roughness right where shimmer peaks lets those
	// spots pick up a sharper specular highlight, closer to how a glinting water surface
	// actually looks.
	ROUGHNESS = clamp(roughness_value - shimmer * 0.05, 0.0, 1.0);
	METALLIC = 0.0;
}
