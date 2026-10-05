/*
 * The ground skirt's fade, shared by the skirt (authored_ground.gdshaderinc with GROUND_SKIRT)
 * and the water that runs on past the map edge in it (water.gdshader, water_skirt_fade; phase
 * 6, P6-1), so the river and the ground dissolve into the backdrop in exactly the same place.
 * RiverExits.skirt_alpha (utils/river_exits.gd) is its CPU twin.
 *
 * skirt_alpha_seeded(): 1 on the map, falling to 0 skirt_fade_m past its edge, the distance to
 * the map rectangle (rounded at the corners) stretched +- skirt_wobble by two octaves of value
 * noise on the map seed, so the outline is organic, not a rectangle; it holds near the map,
 * then falls off softly, like haze rather than a linear ramp.
 *
 * skirt_backdrop_color(): what the camera shows behind the skirt (the environment's flat
 * colour, or a panorama sky in the view direction), fogged as Godot fogs the background;
 * skirt_fog_at(): Godot's fog at a point. SkirtBackdrop (scenes/terrain/) keeps the uniforms
 * in step with the environment, on the skirt's material and the river ribbon's. The skirt
 * fades toward the backdrop in colour, and the water past the edge by the same law (lit * a +
 * backdrop * (1 - a), water.gdshader), so it dissolves exactly as the ground beside it does.
 * skirt_lit_share() (the share of lit ground left in that blend) faded the water's alpha in
 * P6-1 and is kept for diagnostics.
 */

// Half the map's extent in map metres: the skirt fades out from this rectangle.
uniform vec2 skirt_half_extent = vec2(30.0);
// Distance past the map edge at which the skirt is fully faded.
uniform float skirt_fade_m : hint_range(1.0, 100.0) = 24.0;
// How much low-frequency noise stretches and shrinks the fade (0 = a clean rounded rect).
uniform float skirt_wobble : hint_range(0.0, 1.0) = 0.45;
// The backdrop the fade goes to: 0 the flat colour skirt_backdrop (linear), 1 the panorama sky
// skirt_sky_panorama in the camera's view direction (turned by skirt_sky_basis, times
// skirt_sky_energy), 2 a per-pixel dither of the fade instead of a colour.
uniform int skirt_backdrop_mode = 0;
uniform vec3 skirt_backdrop = vec3(0.3);
uniform sampler2D skirt_sky_panorama : source_color, filter_linear, repeat_enable, hint_default_black;
uniform mat3 skirt_sky_basis = mat3(1.0);
uniform float skirt_sky_energy = 1.0;
// The environment's fog: rgb its colour times its energy (linear), a 1 when it is on;
// (density, height, height density, sky affect); (depth mode 1 / exponential 0, depth begin,
// depth end, depth curve).
uniform vec4 skirt_fog = vec4(0.0);
uniform vec4 skirt_fog_params = vec4(0.01, 0.0, 0.0, 1.0);
uniform vec4 skirt_fog_depth = vec4(0.0, 10.0, 100.0, 1.0);

// The luminance of lit ground the backdrop is weighed against (skirt_lit_share): a sunlit
// grass or dirt tile's, linear.
const float SKIRT_LIT_LUMA = 0.25;

// What the camera shows behind the skirt at this pixel, fogged as Godot fogs the background.
vec3 skirt_backdrop_color(mat4 inv_view) {
	vec3 backdrop = skirt_backdrop;
	if (skirt_backdrop_mode == 1) {
		// Godot's panorama coordinates (sky.glsl) of the view direction in the sky's frame.
		vec3 dir = normalize(skirt_sky_basis * -inv_view[2].xyz);
		vec2 coords = vec2(atan(dir.x, -dir.z), acos(clamp(dir.y, -1.0, 1.0)));
		coords.x += coords.x < 0.0 ? 6.28318530718 : 0.0;
		coords /= vec2(6.28318530718, 3.14159265359);
		backdrop = textureLod(skirt_sky_panorama, coords, 0.0).rgb * skirt_sky_energy;
	}
	if (skirt_fog.a > 0.0) {
		backdrop = mix(backdrop, skirt_fog.rgb, skirt_fog_params.w);
	}
	return backdrop;
}

// The share of lit ground in the skirt's colour where its fade is `a`: lit * a over
// lit * a + backdrop * (1 - a), with the backdrop's luminance weighed against SKIRT_LIT_LUMA:
// over a bright sky the ground is swallowed early and the water with it, over a dark one both
// stay longer.
float skirt_lit_share(float a, mat4 inv_view) {
	float luma = dot(skirt_backdrop_color(inv_view), vec3(0.2126, 0.7152, 0.0722));
	float ratio = clamp(luma / SKIRT_LIT_LUMA, 0.1, 20.0);
	return a / max(a + (1.0 - a) * ratio, 1e-5);
}

// Godot's fog at view-space point `vertex` (scene_forward_clustered.glsl fog_process, without
// sun scatter and aerial perspective, which no preset uses): its colour and amount.
vec4 skirt_fog_at(vec3 vertex, mat4 inv_view) {
	if (skirt_fog.a <= 0.0) {
		return vec4(0.0);
	}
	float amount;
	if (skirt_fog_depth.x > 0.5) {
		float fog_z = smoothstep(skirt_fog_depth.y, skirt_fog_depth.z, length(vertex));
		amount = pow(fog_z, skirt_fog_depth.w) * skirt_fog_params.x;
	} else {
		amount = 1.0 - exp(min(0.0, -length(vertex) * skirt_fog_params.x));
	}
	if (abs(skirt_fog_params.z) >= 0.0001) {
		float y = (inv_view * vec4(vertex, 1.0)).y;
		float height_amount = 1.0 - exp(min(0.0, (y - skirt_fog_params.y) * skirt_fog_params.z));
		amount = max(height_amount, amount);
	}
	return vec4(skirt_fog.rgb, amount);
}

uvec2 skirt_pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v = v ^ (v >> 16u);
	return v;
}

// The ground shader's value_noise(), on an explicit seed.
float skirt_value_noise(vec2 p, int seed) {
	vec2 i = floor(p);
	vec2 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	uvec2 c = uvec2(ivec2(i) + ivec2(seed, seed * 7919));
	float a = float(skirt_pcg2d(c).x);
	float b = float(skirt_pcg2d(c + uvec2(1u, 0u)).x);
	float d = float(skirt_pcg2d(c + uvec2(0u, 1u)).x);
	float e = float(skirt_pcg2d(c + uvec2(1u, 1u)).x);
	return mix(mix(a, b, u.x), mix(d, e, u.x), u.y) * (1.0 / 4294967295.0);
}

float skirt_alpha_seeded(vec2 world_xz, int seed) {
	float d = length(max(abs(world_xz) - skirt_half_extent, vec2(0.0)));
	vec2 p = world_xz / 11.0;
	float n = skirt_value_noise(p + vec2(3.7, -8.2), seed) * 0.7
		+ skirt_value_noise(p * 2.3 + vec2(-5.1, 2.9), seed) * 0.3;
	d *= 1.0 + (n - 0.5) * 2.0 * skirt_wobble;
	float t = clamp(d / skirt_fade_m, 0.0, 1.0);
	return 1.0 - t * t * (3.0 - 2.0 * t);
}
