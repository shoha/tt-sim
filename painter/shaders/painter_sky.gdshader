// The painted look's sky (docs/systems/painter.md). PainterScene sets every colour from the
// level's mood at the sun's elevation: a soft gradient from the horizon tone to the zenith, a
// broad warm glow toward the sun (the level's sun, LIGHT0), and below the horizon the far ground
// in haze, which is what the table view's narrow sky FOV shows past the board. Few bold, soft
// shapes, no noise: the sheet's colours reach the screen as written (linear tonemap).
//
// The eye backdrop (card painter-eye-backdrop). At the eye EyeSky sets eye_on and the map's
// skyline numbers, and the visible pass paints a band of far hills (three layers, far to near:
// a pale blue range, a middle range, and near rolling hills with a tree-line of round crowns that
// rise out of the far ground's tone, so the ground skirt meets them without a line) under a few
// large cloud banks, each its own heaped or long shape with a cool underside in the mood's shade
// hue and a lit top toward the sun. Every colour is the mood's (PainterBackdrop); the shapes are
// the map's (the biome's silhouette from StreetSkyLook, the map's seed). The table view never sets
// eye_on, so it draws exactly what it drew before. The cubemap pass (the radiance map) never
// draws the backdrop either, so reflections are the gradient's at the eye too.

shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.62, 0.78, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.88, 0.93, 0.95);
uniform vec3 foot_color : source_color = vec3(0.66, 0.74, 0.55);
uniform vec3 glow_color : source_color = vec3(1.0, 0.96, 0.88);
// How much of the sun's colour the sky gathers around it (0 none).
uniform float glow_amount : hint_range(0.0, 1.0) = 0.35;
// Below 1 the zenith colour reaches lower (a deeper sky).
uniform float sky_curve : hint_range(0.1, 2.0) = 0.6;
// The width of the soft band where the sky meets the far ground (EYEDIR.y).
uniform float foot_blend : hint_range(0.001, 0.5) = 0.08;

group_uniforms eye;
// 0 in the table view; 1 at the eye (EyeSky), where the hills and clouds are drawn.
uniform float eye_on : hint_range(0.0, 1.0) = 0.0;
// The map's skyline: the lattice seed (the biome's plus the map's), the hills' height above
// hill_base_deg, lattice cells per turn of the farthest range, how angular the far ranges are, and
// the near tree-line's crowns (height in degrees, crowns per turn, 0 round to 1 cone).
uniform float eye_seed = 5.0;
uniform float hill_base_deg = -2.5;
uniform float hill_height_deg = 14.0;
uniform float hill_period : hint_range(2.0, 24.0, 1.0) = 5.0;
uniform float hill_angular : hint_range(0.0, 1.0) = 0.0;
uniform float crown_deg : hint_range(0.0, 3.0) = 0.6;
uniform float crown_freq = 50.0;
uniform float crown_shape : hint_range(0.0, 1.0) = 0.3;
// The mood's backdrop tones (PainterBackdrop): the three ranges, the tree-line, the sunlit tops.
uniform vec3 hill_far_color : source_color = vec3(0.62, 0.74, 0.90);
uniform vec3 hill_mid_color : source_color = vec3(0.50, 0.68, 0.62);
uniform vec3 hill_near_color : source_color = vec3(0.40, 0.62, 0.40);
uniform vec3 crown_color : source_color = vec3(0.24, 0.48, 0.32);
uniform vec3 hill_lit_color : source_color = vec3(0.62, 0.78, 0.42);
// The clouds' lit top, their cool underside, and the share of the sky's cells that hold a bank.
uniform vec3 cloud_light_color : source_color = vec3(1.0, 0.98, 0.92);
uniform vec3 cloud_shade_color : source_color = vec3(0.70, 0.72, 0.92);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.55;

const float TURN = 6.28318530718;
const float HALF_TURN = 3.14159265359;
// Cloud banks per turn, the lowest base and the span of bases in degrees, the widest bank.
const float CLOUD_CELLS = 6.0;
const float CLOUD_MIN_DEG = 3.0;
const float CLOUD_SPAN_DEG = 10.0;
const float CLOUD_SIZE_DEG = 36.0;
// Degrees over which the near range rises out of the far ground's tone at its foot.
const float FOOT_RISE_DEG = 1.6;


float h1(float n, float off) {
	return fract(sin(n * 127.1 + off * 311.7 + eye_seed * 74.7) * 43758.5453);
}


// Periodic 1D value noise over one turn of azimuth (t in [0, TURN), period whole cells): ang 0
// eases the lattice (rolling hills), 1 interpolates straight (angular ranges).
float vnoise(float t, float period, float off, float ang) {
	float x = t / TURN * period;
	float i = floor(x);
	float f = x - i;
	float a = h1(mod(i, period), off);
	float b = h1(mod(i + 1.0, period), off);
	f = mix(f * f * (3.0 - 2.0 * f), f, ang);
	return mix(a, b, f);
}


// One round crown (or cone) per cell, each its own height: a tree-line along the near range.
float crowns(float t, float freq, float off) {
	float x = t / TURN * freq;
	float i = floor(x);
	float f = x - i;
	float hgt = 0.35 + 0.65 * h1(mod(i, freq), off);
	float u = 2.0 * f - 1.0;
	return hgt * mix(sqrt(max(1.0 - u * u, 0.0)), 1.0 - abs(u), crown_shape);
}


// The top of range i (0 far, 2 near) at azimuth t, in degrees: two broad octaves only, so a range
// is a few big shapes. tt is 0 for the farthest, 1 for the nearest.
float hill_top(float t, float fi, float tt) {
	float ang = hill_angular * (1.0 - 0.8 * tt);
	float p1 = floor(hill_period * mix(1.0, 2.0, tt) + 0.5) + fi;
	float p2 = floor(p1 * 2.3) + 1.0;
	float n = 0.7 * vnoise(t, p1, fi * 17.3 + 2.0, ang) + 0.3 * vnoise(t, p2, fi * 5.1 + 9.0, ang);
	// The far ranges keep a higher floor, so a dip in the near range never leaves the horizon bare.
	float profile = max(0.5 + (n - 0.5) * 1.8, mix(0.45, 0.22, tt));
	return hill_base_deg + hill_height_deg * mix(1.0, 0.42, tt) * profile;
}


// The cloud banks at (az, el): x the signed distance to the nearest bank (negative inside, in lobe
// radii), y the height within it (0 its flat base, 1 its top), z that bank's height in degrees.
// Each bank draws its own shape from a few numbers: long and low or heaped and tall, how its five
// lobes climb on one another and which side leans higher. `flat_base` false leaves the base's cut
// off (the light test: the sky just under a higher bank's base reads as its shadow).
vec3 cloud_banks(float az, float el, bool flat_base) {
	float ci = floor(az / TURN * CLOUD_CELLS);
	vec3 best = vec3(9.0, 0.0, 1.0);
	for (int k = -1; k <= 1; k++) {
		float c = ci + float(k);
		float cw = mod(c, CLOUD_CELLS);
		if (h1(cw, 41.0) > cloud_cover) {
			continue;
		}
		float az_c = (c + 0.2 + 0.6 * h1(cw, 42.0)) / CLOUD_CELLS * TURN;
		float size = CLOUD_SIZE_DEG * (0.5 + 0.6 * h1(cw, 44.0));
		float base = CLOUD_MIN_DEG + CLOUD_SPAN_DEG * h1(cw, 43.0);
		float longness = h1(cw, 45.0);
		float h = size * mix(0.30, 0.16, longness);
		float ratio = mix(1.05, 1.45, longness);
		float spacing = h * ratio * mix(0.95, 1.3, longness);
		float heap = h1(cw, 46.0) * (1.0 - 0.6 * longness);
		float lean = h1(cw, 47.0) * 2.0 - 1.0;
		float dx = degrees(az - az_c) * cos(radians(base + h * 0.5));
		float s_cell = 9.0;
		for (int j = 0; j < 5; j++) {
			float fj = float(j);
			float u = (fj - 2.0) * 0.5;
			float centre = 1.0 - abs(u) * 0.45;
			float ox = (fj - 2.0 + 0.35 * (h1(cw, 50.0 + fj) - 0.5)) * spacing;
			float r = h * centre * (0.62 + 0.5 * h1(cw, 60.0 + fj));
			float cy = base + r * 0.5 + max(h * (heap * 0.8 * centre * centre + 0.3 * lean * u), 0.0);
			s_cell = min(s_cell, length(vec2((dx - ox) / ratio, el - cy)) / r - 1.0);
		}
		// A low body under the lobes, so a bank is one mass with a bumpy top, and a flat base.
		float body_w = 2.0 * spacing + 0.4 * h * ratio;
		float body = length(vec2(dx / body_w, (el - base - 0.2 * h) / (0.55 * h))) - 1.0;
		s_cell = min(s_cell, body * 2.0);
		if (flat_base) {
			s_cell = max(s_cell, (base - el) / (0.25 * h));
		}
		if (s_cell < best.x) {
			best = vec3(s_cell, clamp((el - base) / (h * 1.6), 0.0, 1.0), h);
		}
	}
	return best;
}


// The backdrop over `col` along `dir`: clouds, then the ranges far to near.
vec3 backdrop(vec3 col, vec3 dir, vec3 to_sun, bool sun_on) {
	float el = degrees(asin(clamp(dir.y, -1.0, 1.0)));
	float az = atan(dir.x, -dir.z) + HALF_TURN;
	float sun_az = atan(to_sun.x, -to_sun.z) + HALF_TURN;
	float facing = sun_on ? cos(az - sun_az) : 0.0;
	// Which side of the view the sun lies on (+1 toward larger azimuth), 0 when it is ahead or behind.
	float side = sun_on ? clamp(sin(sun_az - az) * 2.0, -1.0, 1.0) : 0.0;
	float aa = max(fwidth(el), 0.004);

	if (el > CLOUD_MIN_DEG - 1.0 && el < CLOUD_MIN_DEG + CLOUD_SPAN_DEG + CLOUD_SIZE_DEG * 0.7) {
		vec3 cl = cloud_banks(az, el, true);
		float m = 1.0 - smoothstep(-0.03, 0.05, cl.x);
		if (m > 0.0) {
			// Lit where a step up and toward the sun leaves every bank: a band along the outline
			// on the sun's side that follows the lobes (the field is continuous, so the band has
			// no seams where one lobe meets the next).
			float off = 0.22 * cl.z;
			float s2 = cloud_banks(
				az + radians(off) * side / max(cos(radians(el)), 0.3), el + off * 0.75, false
			).x;
			float lit = smoothstep(-0.35, 0.0, s2);
			// Three painted values with soft steps: the cool underside, the body, the lit tops; a
			// bank with the sun behind the viewer is lit across more of its face.
			float tone = 0.62 * smoothstep(0.02, 0.8, cl.y) + 0.55 * lit + 0.15 * max(-facing, 0.0);
			vec3 mid = mix(cloud_shade_color, cloud_light_color, 0.55);
			vec3 c = mix(cloud_shade_color, mid, smoothstep(0.24, 0.34, tone));
			c = mix(c, cloud_light_color, smoothstep(0.62, 0.72, tone));
			col = mix(col, c, m);
		}
	}

	if (el < hill_base_deg + hill_height_deg + crown_deg + 1.0) {
		float glow_t = pow(max(facing, 0.0), 2.0);
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float tt = fi * 0.5;
			bool nearest = i == 2;
			float top = hill_top(az, fi, tt);
			float crown_top = top;
			if (nearest) {
				crown_top += crown_deg * crowns(az, floor(crown_freq), 9.0);
			}
			float soft = nearest ? aa * 1.2 : max(mix(0.7, 0.3, tt), aa);
			float m = 1.0 - smoothstep(crown_top - soft, crown_top + soft, el);
			if (m <= 0.0) {
				continue;
			}
			vec3 c = i == 0 ? hill_far_color : (i == 1 ? hill_mid_color : hill_near_color);
			// A broad sunlit band under each top on the sun's side, wider on the near range.
			float depth = top - el;
			float band = (top - hill_base_deg) * mix(0.25, 0.4, tt);
			float lit = 1.0 - smoothstep(band * 0.55, band, depth);
			c = mix(c, hill_lit_color, lit * mix(0.25, 0.55, tt) * (0.35 + 0.65 * glow_t));
			if (nearest) {
				// The tree-line: crowns above the hill's own top, and a canopy under it whose lower
				// edge wanders, all in the crowns' tone, their sun side lifted.
				float canopy = crown_deg * (0.6 + 0.9 * vnoise(az, floor(crown_freq * 0.15), 71.0, 0.0));
				float in_crown = smoothstep(-0.15, 0.15, el - (top - canopy));
				vec3 crown_c = mix(crown_color, hill_lit_color, 0.3 * glow_t);
				c = mix(c, crown_c, in_crown * step(0.05, crown_deg));
				c = mix(c, foot_color, 1.0 - smoothstep(hill_base_deg, hill_base_deg + FOOT_RISE_DEG, el));
			} else {
				// The farther ranges mist into the horizon toward their feet.
				float foot = 1.0 - clamp((el - hill_base_deg) / max(top - hill_base_deg, 0.1), 0.0, 1.0);
				c = mix(c, horizon_color, foot * foot * mix(0.7, 0.45, tt));
			}
			col = mix(col, c, m);
		}
	}
	return col;
}


void sky() {
	float y = EYEDIR.y;
	vec3 color = mix(horizon_color, zenith_color, pow(clamp(y, 0.0, 1.0), sky_curve));
	float below = smoothstep(0.0, -foot_blend, y);
	if (LIGHT0_ENABLED) {
		float toward = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		float glow = (pow(toward, 4.0) * 0.6 + pow(toward, 24.0) * 0.4) * glow_amount;
		color = mix(color, glow_color, clamp(glow, 0.0, 1.0));
	}
	color = mix(color, foot_color, below);
	if (eye_on > 0.5 && !AT_CUBEMAP_PASS) {
		color = backdrop(color, normalize(EYEDIR), LIGHT0_DIRECTION, LIGHT0_ENABLED);
	}
	COLOR = color;
}
