shader_type sky;

// The painted street-level sky of the eye view (cards eyesky, SK2 variant B). A perspective camera
// at eye height sees a horizon, so the sky is painted there: a luminous zenith-to-haze gradient, a
// warm band toward the sun, flat painted cloud banks each of its own shape (lilac undersides,
// cream tops) under a higher layer of small cloudlets, and up to four ridge layers (distant peaks,
// snow-capped for alpine, rolling hills, tree-lines) that hide where the map's ground ends. The
// nearest ridge is cut crisp; the farther ones keep soft painted edges. EyeSky installs it for the eye view only and takes it away on leaving; the
// per-biome numbers live in utils/street_sky_look.gd.
//
// Lighting equivalence. In the cubemap pass (AT_CUBEMAP_PASS, the pass that fills the radiance map
// the ambient light and reflections read) this shader returns exactly what the sky it replaces
// returns: texture(source_panorama, SKY_COORDS) * exposure for an HDRI sky (the stock
// PanoramaSkyMaterial's formula, filter_linear), or the flat level colour. Only the visible pass
// paints the sky, clouds and ridges. TIME, POSITION and LIGHTn are never read, so the radiance map
// stays a one-time render. Verified by tools/streetsky_radiance_probe.gd (diffuse, rough and mirror
// spheres: 0.0000 mean byte difference against the old sky).
//
// Everything is a function of the view direction in the sky's frame (EYEDIR, which already
// includes Environment.sky_rotation). The orthographic home view looks 21.6 degrees below the
// horizon (sky_custom_fov 2) and never swaps this sky in at all; a perspective eye camera needs
// sky_custom_fov 0.
//
// The nearest ridge's foot melts into foot_color, which is also the depth fog colour and the colour
// the ground skirt fades to (SkirtBackdrop reads foot_on and foot_color), so grass, skirt, fogged
// ground and ridge foot are one tone and there is no seam. Layers are drawn far to near, each with
// its own lattice size and seeds so they do not run parallel.

uniform sampler2D source_panorama : filter_linear, source_color, repeat_enable;
uniform float exposure : hint_range(0.0, 128.0, 0.01) = 1.0;
// A default level has a flat background colour, not a panorama: with use_panorama off the sky is
// flat_color in the cubemap pass too, so reflections still see the level's colour.
uniform bool use_panorama = false;
uniform vec3 flat_color : source_color = vec3(0.3, 0.3, 0.3);

group_uniforms sky;
// 0 draws only the panorama or flat colour, 1 the whole painted sky and ridges.
uniform float band_on : hint_range(0.0, 1.0) = 1.0;
uniform float band_energy : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform vec3 zenith_color : source_color = vec3(0.3, 0.52, 0.9);
// The sky just above the horizon (a pale blue haze) and the warm haze on the sun side.
uniform vec3 horizon_color : source_color = vec3(0.78, 0.89, 0.98);
uniform vec3 warm_color : source_color = vec3(1.0, 0.84, 0.62);
uniform float sky_curve : hint_range(0.2, 2.0) = 0.7;
uniform float warm_amount : hint_range(0.0, 1.0) = 0.4;
uniform float warm_width_deg : hint_range(1.0, 40.0) = 9.0;
// The sun's azimuth and elevation in the sky's frame (SkyLook.sun_angles from the level's light).
uniform float glow_az_deg : hint_range(0.0, 360.0) = 0.0;
uniform float sun_el_deg : hint_range(0.0, 90.0) = 40.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.92, 0.72);
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;

group_uniforms ridges;
uniform vec3 far_color : source_color = vec3(0.4, 0.56, 0.8);
uniform vec3 near_color : source_color = vec3(0.08, 0.42, 0.4);
// Colour the nearest ridge's foot, the depth fog and the skirt melt into.
uniform vec3 foot_color : source_color = vec3(0.35, 0.58, 0.45);
// 1 in the eye view: SkirtBackdrop fades the ground skirt to foot_color (this shader never reads it).
uniform float foot_on : hint_range(0.0, 1.0) = 1.0;
// Degrees above base_deg over which the nearest ridge rises out of foot_color: past the farthest
// skirt end (about -1.9 degrees) and below the lowest tree-line, so the crowns stay solid.
uniform float foot_rise_deg : hint_range(0.5, 20.0) = 2.5;
uniform float base_deg = -2.5;
uniform float height_deg = 18.0;
uniform int layers : hint_range(1, 4) = 3;
uniform float soften_deg : hint_range(0.05, 4.0) = 0.5;
// How far each ridge's lower part fades into the haze (far layers) or foot colour (nearest).
uniform float mist : hint_range(0.0, 1.0) = 0.5;
uniform float haze_far : hint_range(0.0, 1.0) = 0.6;
// Lattice cells per turn of the farthest ridge, and the seed: the two numbers that make a biome's
// skyline its own (the map's seed is added to noise_seed so two maps of a biome differ).
uniform float noise_period : hint_range(2.0, 24.0, 1.0) = 5.0;
uniform float noise_seed = 1.0;
// 0 smooth rolling hills, 1 angular peaks (the far layers; nearer ones ease back to rounded).
uniform float angular : hint_range(0.0, 1.0) = 0.0;
// Tree crowns along the nearer ridge tops: height in degrees, crowns per turn of the nearest
// layer, and their shape (0 round deciduous crowns, 1 conifer cones).
uniform float teeth_deg : hint_range(0.0, 3.0) = 0.0;
uniform float teeth_freq = 50.0;
uniform float tree_shape : hint_range(0.0, 1.0) = 0.0;
// The sunlit canopy strip under each ridge top: how strongly it lifts toward the warm colour, and
// its thickness as a fraction of the ridge's height.
uniform float lit_amount : hint_range(0.0, 1.0) = 0.5;
uniform float lit_thick : hint_range(0.05, 0.6) = 0.3;
// Soft warm light along the ridge tops on the sun side.
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.72);
uniform float rim_amount : hint_range(0.0, 1.0) = 0.25;

group_uniforms clouds;
// 0 none. Cloud banks draw their shapes from a continuous family (long flat banks to heaped
// towers, lopsided or even), flat-bottomed, with a cool underside, a cream top and a lit rim on the
// sun side.
uniform float cloud_amount : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.7;
uniform float cloud_cells : hint_range(3.0, 16.0, 1.0) = 8.0;
uniform float cloud_min_deg = 8.0;
uniform float cloud_span_deg = 18.0;
uniform float cloud_size_deg = 34.0;
uniform vec3 cloud_light : source_color = vec3(1.0, 0.97, 0.9);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.64, 0.88);
// The high layer of small cloudlets: how many cells hold one (0 none), where their bases lie and
// their size as a fraction of the banks'.
uniform float cloud2_cover : hint_range(0.0, 1.0) = 0.5;
uniform float cloud2_min_deg = 24.0;
uniform float cloud2_span_deg = 18.0;
uniform float cloud2_scale : hint_range(0.1, 1.0) = 0.4;

group_uniforms snow;
// Snow on the far peaks (alpine): how much of the farthest ridge's upper part turns snow_color,
// above a wavy snow line at snow_line of the ridge's height. 0 none.
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float snow_line : hint_range(0.0, 1.0) = 0.62;
uniform vec3 snow_color : source_color = vec3(0.93, 0.95, 1.0);

const float TURN = 6.28318530718;
const float HALF_TURN = 3.14159265359;


float h1(float n, float off) {
	return fract(sin(n * 127.1 + off * 311.7 + noise_seed * 74.7) * 43758.5453);
}

// Periodic 1D value noise over one turn of azimuth: t in [0, TURN), period integer cells. ang 0
// eases the lattice (hills), 1 interpolates linearly (angular zig-zag peaks).
float vnoise(float t, float period, float off, float ang) {
	float x = t / TURN * period;
	float i = floor(x);
	float f = x - i;
	float a = h1(mod(i, period), off);
	float b = h1(mod(i + 1.0, period), off);
	f = mix(f * f * (3.0 - 2.0 * f), f, ang);
	return mix(a, b, f);
}

// One tree crown per cell: a round bump or a cone, its height drawn per cell, so a tree-line is a
// run of bold crowns of different heights (0 at the cell edges, up to 1).
float crowns(float t, float freq, float off, float shape) {
	float x = t / TURN * freq;
	float i = floor(x);
	float f = x - i;
	float hgt = 0.3 + 0.7 * h1(mod(i, freq), off);
	float u = 2.0 * f - 1.0;
	float round_crown = sqrt(max(1.0 - u * u, 0.0));
	float cone = 1.0 - abs(u);
	return hgt * mix(round_crown, cone, shape);
}

// Elevation of layer i's top at azimuth t. tt is 0 for the farthest layer, 1 for the nearest.
float ridge_top(float t, int i, float tt) {
	float fi = float(i);
	float ang = angular * (1.0 - 0.7 * tt);
	// Each layer has its own lattice size (nearer layers have more, smaller features) and seeds.
	float p1 = floor(noise_period * mix(1.0, 2.2, tt) + 0.5) + fi;
	float p2 = floor(p1 * 2.3) + 1.0;
	float p3 = floor(p1 * 5.3) + 2.0;
	// Three octaves: the broad shape, hill shoulders, and a few small knolls on top.
	float n = 0.58 * vnoise(t, p1, fi * 17.3 + 2.0, ang)
		+ 0.28 * vnoise(t, p2, fi * 5.1 + 9.0, ang)
		+ 0.14 * vnoise(t, p3, fi * 3.7 + 31.0, ang * 0.5);
	float profile = max(0.5 + (n - 0.5) * 1.7, 0.3);
	float top = base_deg + height_deg * mix(1.0, 0.5, tt) * profile;
	if (teeth_deg > 0.0 && tt > 0.3) {
		float k = floor(teeth_freq * (0.7 + 0.5 * fi));
		// Full crowns on the nearest layer only; a middle layer gets a low canopy texture, so two
		// tree-lines of one shape never stand one behind the other like a double image.
		top += teeth_deg * (0.08 + 0.92 * tt * tt) * crowns(t, k, fi + 9.0, tree_shape);
	}
	return top;
}

// Distance field of a cloud layer's banks (negative inside, in units of the bank's radius) at
// (az, el), and the base elevation and height of the nearest bank. `layer` is (cells per turn,
// cover, lowest base in degrees, base span in degrees); `size_deg` the largest bank's width; `off`
// the layer's hash offset. Every bank draws its own shape from a few continuous numbers (how long
// it is against how tall, how its four lobes are spread and heaped, which side leans higher), so a
// sky of them is a family of shapes, not one shape repeated: long flat banks, heaped cumulus,
// lopsided domes and small puffs.
float cloud_s(
	float az, float el, vec4 layer, float size_deg, float off, int lobes, out float base_out, out float h_out
) {
	float cells = layer.x;
	float x = az / TURN * cells;
	float ci = floor(x);
	float s_best = 9.0;
	base_out = 0.0;
	h_out = 1.0;
	for (int k = -1; k <= 1; k++) {
		float c = ci + float(k);
		float cw = mod(c, cells);
		if (h1(cw, off + 41.0) > layer.y) {
			continue;
		}
		float az_c = (c + 0.25 + 0.5 * h1(cw, off + 42.0)) / cells * TURN;
		float size = size_deg * (0.45 + 0.75 * h1(cw, off + 44.0));
		float base = layer.z + layer.w * h1(cw, off + 43.0);
		// Long (1) against tall (0): a long bank is low and wide, a tall one a heaped tower. The
		// lobes are nearly round and spaced a little wider than they are, so the top is a row of
		// distinct bumps (a cumulus outline), never a smooth pill.
		float longness = h1(cw, off + 45.0);
		float h = size * mix(0.30, 0.15, longness);
		float ratio = mix(1.05, 1.5, longness);
		float spacing = h * ratio * mix(0.95, 1.35, longness);
		// The heap: how much the middle lobes climb on the outer ones, and which side leans higher.
		float heap = h1(cw, off + 46.0) * (1.0 - 0.7 * longness);
		float lean = h1(cw, off + 47.0) * 2.0 - 1.0;
		float dx = degrees(az - az_c) * cos(radians(base + h * 0.5));
		float half_n = float(lobes - 1) * 0.5;
		float s_cell = 9.0;
		for (int j = 0; j < lobes; j++) {
			float fj = float(j);
			float u = (fj - half_n) / max(half_n, 1.0);
			float centre = 1.0 - abs(u) * 0.45;
			float ox = (fj - half_n + 0.35 * (h1(cw, off + 50.0 + fj) - 0.5)) * spacing;
			float r = h * centre * (0.6 + 0.55 * h1(cw, off + 60.0 + fj));
			float stack = h * (heap * 0.8 * centre * centre + 0.3 * lean * u);
			float s = length(vec2((dx - ox) / ratio, el - base - r * 0.5 - max(stack, 0.0))) / r - 1.0;
			s_cell = min(s_cell, s);
		}
		// A low body under the lobes, so the bank is one mass with a bumpy top.
		float body_w = (half_n * spacing + 0.4 * h * ratio) * mix(0.85, 1.0, longness);
		float body = length(vec2(dx / body_w, (el - base - 0.2 * h) / (0.55 * h))) - 1.0;
		s_cell = min(s_cell, body * 2.0);
		// Flat base.
		s_cell = max(s_cell, (base - el) / (0.25 * h));
		if (s_cell < s_best) {
			s_best = s_cell;
			base_out = base;
			h_out = h;
		}
	}
	return s_best;
}

// A painted cloud layer: rgb and coverage. side is +1 when the sun lies to the right of the view
// azimuth, -1 to the left.
vec4 cloud_layer(float az, float el, float side) {
	if (el < cloud_min_deg - 2.0 || el > cloud_min_deg + cloud_span_deg + cloud_size_deg) {
		return vec4(0.0);
	}
	vec4 layer = vec4(cloud_cells, cloud_cover, cloud_min_deg, cloud_span_deg);
	float base;
	float h;
	float s = cloud_s(az, el, layer, cloud_size_deg, 0.0, 5, base, h);
	float m = 1.0 - smoothstep(-0.02, 0.1, s);
	if (m <= 0.0) {
		return vec4(0.0);
	}
	float b2;
	float h2;
	float off = 0.2 * h;
	float s2 = cloud_s(
		az + radians(off) * side / max(cos(radians(el)), 0.3), el + off * 0.7, layer, cloud_size_deg, 0.0, 5, b2, h2
	);
	float lit = smoothstep(-0.4, 0.0, s2);
	float t = clamp((el - base) / (h * 1.5), 0.0, 1.0);
	vec3 c = mix(cloud_shade, cloud_light, smoothstep(0.05, 0.75, t));
	c = mix(c, cloud_light * 1.08, lit * 0.8);
	return vec4(c, m);
}

// The high layer: small flat cloudlets scattered higher up the sky (so a look up is never an empty
// gradient), paler and flatter than the banks, with a soft cool underside and no lit rim.
vec4 high_cloud_layer(float az, float el) {
	float lo = cloud2_min_deg;
	float hi = cloud2_min_deg + cloud2_span_deg + cloud_size_deg * cloud2_scale;
	if (cloud2_cover <= 0.0 || el < lo - 1.0 || el > hi) {
		return vec4(0.0);
	}
	vec4 layer = vec4(cloud_cells * 2.0 + 1.0, cloud2_cover, cloud2_min_deg, cloud2_span_deg);
	float base;
	float h;
	float s = cloud_s(az, el, layer, cloud_size_deg * cloud2_scale, 100.0, 3, base, h);
	float m = 1.0 - smoothstep(-0.03, 0.12, s);
	if (m <= 0.0) {
		return vec4(0.0);
	}
	float t = clamp((el - base) / (h * 1.2), 0.0, 1.0);
	vec3 c = mix(mix(cloud_shade, cloud_light, 0.45), cloud_light, smoothstep(0.0, 0.6, t));
	return vec4(c, m * 0.9);
}

void sky() {
	vec3 col = flat_color * exposure;
	if (use_panorama) {
		col = texture(source_panorama, SKY_COORDS).rgb * exposure;
	}
	if (!AT_CUBEMAP_PASS && band_on > 0.0) {
		vec3 dir = normalize(EYEDIR);
		float el = degrees(asin(clamp(dir.y, -1.0, 1.0)));
		// az is the panorama's column angle (u * 360), so glow_az_deg is the sun's azimuth in it.
		float az = atan(dir.x, -dir.z) + HALF_TURN;
		float sun_az = radians(glow_az_deg);
		float glow_t = pow(max(cos(az - sun_az), 0.0), 3.0);
		float side = clamp(sin(sun_az - az) * 3.0, -1.0, 1.0);

		// Painted sky: zenith to a pale blue horizon haze, a warm band and a soft sun glow.
		float up = smoothstep(0.0, 42.0, el);
		vec3 sky_c = mix(horizon_color, zenith_color, pow(up, sky_curve));
		float warm = exp(-max(el, 0.0) / warm_width_deg) * (0.3 + 0.7 * glow_t) * warm_amount;
		sky_c = mix(sky_c, warm_color, clamp(warm, 0.0, 1.0));
		float sel = radians(sun_el_deg);
		vec3 sun_dir = vec3(-sin(sun_az) * cos(sel), sin(sel), cos(sun_az) * cos(sel));
		float sd = max(dot(dir, sun_dir), 0.0);
		sky_c += glow_color * (0.6 * pow(sd, 10.0) + 0.4 * pow(sd, 120.0)) * sun_glow;
		col = mix(col, sky_c * band_energy, band_on);

		if (cloud_amount > 0.0) {
			vec4 high = high_cloud_layer(az, el);
			col = mix(col, high.rgb * band_energy, high.a * cloud_amount * band_on);
			vec4 cl = cloud_layer(az, el, side);
			col = mix(col, cl.rgb * band_energy, cl.a * cloud_amount * band_on);
		}

		// Ridges, far to near. The far layers keep soft painted edges; the nearest is cut crisp
		// (about a pixel of antialiasing), so its crowns never read as an out-of-focus double.
		float aa = max(fwidth(el), 0.005);
		for (int i = 0; i < 4; i++) {
			if (i >= layers) {
				break;
			}
			bool nearest = i == layers - 1;
			float tt = float(i) / float(max(layers - 1, 1));
			float top = ridge_top(az, i, tt);
			float soft = nearest ? aa : max(soften_deg * mix(1.8, 0.6, tt), aa);
			float m = 1.0 - smoothstep(top - soft, top + soft, el);
			if (m <= 0.0) {
				continue;
			}
			float fade = haze_far * pow(1.0 - tt, 1.2);
			vec3 c = mix(near_color, far_color, pow(1.0 - tt, 0.8));
			c = mix(c, horizon_color, fade * 0.5);
			// Two tones: a sunlit canopy strip under the top (its thickness wobbles with the
			// azimuth, and follows the crowns because it hangs from the top) over the shaded body.
			float depth = top - el;
			float thick = (top - base_deg) * lit_thick * (0.6 + 0.8 * vnoise(az, 11.0 + float(i), 77.0 + float(i), 0.0));
			float strip = 1.0 - smoothstep(thick * 0.55, thick * 1.1, depth);
			// Sunlit foliage is a brighter, yellower green, not a pale outline; far layers just lift.
			vec3 lit_c = mix(c * 1.1 + horizon_color * 0.05, c * vec3(1.22, 1.28, 0.95) + warm_color * 0.03, tt);
			c = mix(c * 0.9, lit_c, strip * lit_amount * mix(0.4, 1.0, tt));
			// Snow on the farthest peaks: above a wavy line, bold and flat, a cool blue low on the
			// snowfield and brightest at the summits.
			if (snow_amount > 0.0 && i == 0) {
				float rise = (el - base_deg) / max(height_deg, 0.1);
				float line = snow_line + 0.14 * (vnoise(az, 23.0, 91.0, 0.6) - 0.5);
				// Only peaks that stand well above the line carry a cap: one that barely reaches it
				// would show a thin white sliver along its top, which reads as a cloud streak.
				float top_rise = (top - base_deg) / max(height_deg, 0.1);
				float snow = smoothstep(line - 0.015, line + 0.015, rise) * snow_amount;
				snow *= smoothstep(line + 0.06, line + 0.16, top_rise);
				vec3 snow_c = mix(snow_color * vec3(0.80, 0.86, 0.98), snow_color, smoothstep(line, line + 0.25, rise));
				c = mix(c, snow_c, snow);
			}
			// The farther layers' lower parts mist into the horizon haze. The nearest takes no mist
			// of its own: the depth fog already hazes the ground in front of it into foot_color, so
			// a second haze on the ridge (its own mist over most of a low tree-line) blurred the
			// crowns into a grey band. It only rises out of foot_color at its very foot.
			if (!nearest) {
				float foot = 1.0 - clamp((el - base_deg) / max(top - base_deg, 0.1), 0.0, 1.0);
				c = mix(c, horizon_color, foot * foot * mist);
			} else {
				c = mix(c, foot_color, 1.0 - smoothstep(base_deg, base_deg + foot_rise_deg, el));
			}
			// A soft warm rim along the top on the sun side: wide and gentle, never a line. On the
			// nearest layer it is half as strong, so the crowns keep their dark silhouette against
			// the bright sky rather than melting into a pale halo.
			float rim = smoothstep(top - 4.5, top + 0.4, el);
			rim *= rim * (nearest ? 0.5 : 1.0);
			c = mix(c, rim_color, clamp(rim * glow_t * rim_amount * (0.35 + 0.65 * (1.0 - fade)), 0.0, 0.4));
			col = mix(col, c * band_energy, m * band_on);
		}
	}
	COLOR = col;
}
