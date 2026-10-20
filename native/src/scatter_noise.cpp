// The CPU noises the grass masses read, line for line with utils/ground_zones.gd (the ground
// shader's colour zones: its fract-hash value noise with the record's lattice memo),
// utils/ground_accents.gd's octave lattice with ScatterMass._accent_noise and bare_keep (the
// bare openings), and TerrainRules.value_noise_memo and pcg2d_x; plus the pattern noise's
// FastNoiseLite set up as Godot's resource sets it up.
#include "scatter_gen.h"

namespace ttscatter {

// ---- GroundZones ------------------------------------------------------------------------------

void ZonesRecord::zone_weights(double x, double z, double *w) {
	w[0] = 1.0;
	w[1] = 0.0;
	w[2] = 0.0;
	w[3] = 0.0;
	Vector2 p = v2(x, z) + seed;
	double masks[3] = { 0.0, 0.0, 0.0 };
	int lowest = 0;
	for (int k = 2; k >= 0; k--) {
		if (cover[k] <= 0.0) {
			continue;
		}
		masks[k] = zone_mask(p, k);
		if (masks[k] == 1.0) {
			lowest = k;
			break;
		}
	}
	for (int k = lowest; k < 3; k++) {
		if (cover[k] <= 0.0) {
			continue;
		}
		double m = masks[k];
		for (int j = 0; j < k + 1; j++) {
			w[j] *= 1.0 - m;
		}
		w[k + 1] = m;
	}
}

double ZonesRecord::family_share(const double *w, const int *families, int family) {
	double total = 0.0;
	for (int k = 0; k < 4; k++) {
		total += families[k] == family ? w[k] : 0.0;
	}
	return total;
}

bool ZonesRecord::share_reaches(double x, double z, const int *families, int family, double share) {
	Vector2 p = v2(x, z) + seed;
	double held = 0.0, left = 1.0;
	int top = 3;
	const double slack = c->bound_slack;
	while (true) {
		double least = 1.0, most = 0.0;
		for (int j = 0; j < top + 1; j++) {
			double mine = families[j] == family ? 1.0 : 0.0;
			least = gmin(least, mine);
			most = gmax(most, mine);
		}
		if (held + left * least >= share + slack) {
			return true;
		}
		if (held + left * most < share - slack) {
			return false;
		}
		if (top == 0) {
			break;
		}
		top -= 1;
		if (cover[top] > 0.0) {
			double m = zone_mask(p, top);
			if (families[top + 1] == family) {
				held += left * m;
			}
			left *= 1.0 - m;
		}
	}
	double scratch[4];
	zone_weights(x, z, scratch);
	return family_share(scratch, families, family) >= share;
}

double ZonesRecord::zone_mask(Vector2 p, int k) {
	double t = glerp(0.7, 0.3, gclamp(cover[k], 0.0, 1.0));
	double e0 = edge[k] * stroke_edge;
	double vary = edge_vary;
	const double slack = c->bound_slack;
	if (e0 < 0.0 || vary > 1.0) {
		double plain = edge_at(p, e0, k + 1.0);
		double f_plain = zone_shape(p, k, true, -INFINITY, INFINITY);
		return stroke_pick(p, smoothstep(t - plain, t + plain, f_plain), k + 1);
	}
	double widest = e0 * gmax(1.0 + 1.5 * vary, 1.0) + slack;
	double octave = (0.5 + slack) * std::fabs(rag) + slack;
	double f = zone_shape(p, k, true, t - widest - octave, t + widest + octave);
	if (f <= t - widest) {
		return 0.0;
	}
	if (f >= t + widest) {
		return 1.0;
	}
	double e = edge_at(p, e0, k + 1.0);
	return stroke_pick(p, smoothstep(t - e, t + e, f), k + 1);
}

double ZonesRecord::zone_flow(double x, double z) {
	Vector2 p = v2(x, z) + seed;
	double best = INFINITY;
	double flow = angle;
	for (int k = 0; k < 3; k++) {
		double share = cover[k];
		if (share <= 0.0) {
			continue;
		}
		double f = zone_shape(p, k, false, -INFINITY, INFINITY);
		Vector2 gr = zone_slope(p, k);
		double edge_d = std::fabs(f - glerp(0.7, 0.3, gclamp(share, 0.0, 1.0))) / gmax((double)gr.length(), 1e-4);
		if (edge_d < best) {
			best = edge_d;
			flow = std::atan2((double)gr.x, -(double)gr.y);
		}
	}
	return flow;
}

double ZonesRecord::stroke_pick(Vector2 p, double m, int k) {
	if (stroke <= 0.0 || m <= 0.0 || m >= 1.0) {
		return m;
	}
	double a = angle + angle_k[k - 1];
	Vector2 cs = v2(std::cos(a), std::sin(a));
	Vector2 r(p.dot(cs), p.dot(Vector2(-cs.y, cs.x)));
	double width = stroke_m;
	Vector2 q = v2(r.x / (width * gmax(stroke_len, 1.0)), r.y / width);
	Vector2 o = v2(k * 13.7, -k * 7.9);
	q = Vector2(q.x, (float)(q.y + (noise(v2(q.x * 0.6, q.y * 0.25) + o + Vector2(3.3f, 1.1f)) - 0.5) * 2.4));
	double s = noise(q + o) * 0.62 + noise(q * Vector2(1.7f, 2.1f) + o * 1.3f + Vector2(-4.1f, 9.2f)) * 0.38;
	s = gclamp((s - 0.5) * 2.6 + 0.5, 0.0, 1.0);
	double soft_m = gmax(stroke_soft_m, 0.5);
	double soft_n = noise(p / (float)soft_m + o * 0.5f + Vector2(-6.6f, 2.4f));
	double soft = glerp(stroke_soft_lo, stroke_soft_hi, smoothstep(0.3, 0.7, soft_n));
	s = glerp(soft, 1.0 - soft, s);
	return glerp(m, smoothstep(s - soft, s + soft, m), stroke);
}

double ZonesRecord::edge_at(Vector2 xz, double edge_value, double k) {
	double vary = edge_vary;
	if (vary <= 0.0) {
		return edge_value;
	}
	Vector2 q = xz / (float)gmax(edge_vary_m, 0.5) + v2(k * 7.31, -k * 3.17);
	double n = smoothstep(0.3, 0.7, noise(q) * 0.75 + noise(q * 2.3f) * 0.25);
	return edge_value * glerp(1.0 - vary, 1.0 + 1.5 * vary, n);
}

Vector2 ZonesRecord::zone_slope(Vector2 p, int k) {
	const double step = c->flow_step;
	Vector2 dx = v2(step, 0.0);
	Vector2 dz = v2(0.0, step);
	return v2(zone_shape(p + dx, k, false, -INFINITY, INFINITY) - zone_shape(p - dx, k, false, -INFINITY, INFINITY),
				   zone_shape(p + dz, k, false, -INFINITY, INFINITY) - zone_shape(p - dz, k, false, -INFINITY, INFINITY)) /
			(float)(2.0 * step);
}

double ZonesRecord::zone_shape(Vector2 xz, int k, bool ragged_edge, double bare_lo, double bare_hi) {
	double a = shape_angle[k];
	Vector2 offset = shape_offset[k];
	Vector2 cs = v2(std::cos(a), std::sin(a));
	Vector2 r = v2(xz.dot(cs) / gmax(shape_stretch[k], 0.1), xz.dot(Vector2(-cs.y, cs.x)));
	Vector2 p = r / (float)shape_scale[k];
	Vector2 w = v2(noise(p * 0.55f + offset + Vector2(3.7f, -1.9f)), noise(p * 0.55f + offset + Vector2(-8.3f, 6.1f)));
	p = p + (w - Vector2(0.5f, 0.5f)) * 2.0f * (float)warp;
	double f = noise(p + offset) * 0.7 + noise(p * 2.07f + offset * 1.3f + Vector2(5.1f, 2.2f)) * 0.3;
	if (!ragged_edge || f <= bare_lo || f >= bare_hi) {
		return f;
	}
	Vector2 q = r / (float)gmax(rag_m, 0.1) + (w - Vector2(0.5f, 0.5f)) * 3.0f;
	double ragged = noise(q + offset * 0.7f + Vector2(-2.9f, 13.3f)) - 0.5;
	return f + ragged * rag;
}

double ZonesRecord::noise(Vector2 p) {
	Vector2 i = p.floor();
	Vector2 u = p - i;
	u = u * u * (Vector2(3.0f, 3.0f) - u * 2.0f);
	int64_t k = key_of(i);
	const Hash4 *known = hashes.find(k);
	Hash4 h;
	if (known) {
		h = *known;
	} else {
		h = { hash(i), hash(i + Vector2(1.0f, 0.0f)), hash(i + Vector2(0.0f, 1.0f)), hash(i + Vector2(1.0f, 1.0f)) };
		hashes.set(k, h);
	}
	return glerp(glerp(h[0], h[1], u.x), glerp(h[2], h[3], u.x), u.y);
}

double ZonesRecord::hash(Vector2 p) {
	Vector3 q((float)fposmod(p.x * 0.1031, 1.0), (float)fposmod(p.y * 0.1030, 1.0), (float)fposmod(p.x * 0.0973, 1.0));
	float s = q.dot(Vector3((float)(q.y + 33.33), (float)(q.z + 33.33), (float)(q.x + 33.33)));
	q = q + Vector3(s, s, s);
	return fposmod(((double)q.x + q.y) * q.z, 1.0);
}

// ---- GroundAccents and the bare openings -------------------------------------------------------

double Accents::bare_keep(const std::vector<BareRecord> &bare, double x, double z) {
	double keep = 1.0;
	for (const BareRecord &record : bare) {
		double t = record.threshold - c.accent_edge;
		double lo = t - record.margin;
		double n = lo <= t ? accent_noise(v2(x, z), record, lo, t) : accent_noise(v2(x, z), record, -INFINITY, INFINITY);
		keep *= 1.0 - smoothstep(lo, t, n);
		if (keep == 0.0) {
			return keep;
		}
	}
	return keep;
}

double Accents::accent_noise(Vector2 xz, const BareRecord &record, double below, double above) {
	Vector2 rot = c.rotation;
	Vector2 q = v2((double)rot.x * xz.x - (double)rot.y * xz.y, (double)rot.y * xz.x + (double)rot.x * xz.y);
	double stretch = record.stretch;
	double warp = record.brk;
	Vector2 p;
	if (stretch != 1.0 || warp > 0.0) {
		Vector2 cs = v2(record.cos_a, record.sin_a);
		Vector2 r = v2((double)cs.x * q.x - (double)cs.y * q.y, (double)cs.y * q.x + (double)cs.x * q.y);
		r = Vector2((float)(r.x / gmax(stretch, 0.1)), r.y);
		p = r / (float)record.scale_m + record.offset;
		int64_t s = record.seed;
		Vector2 w = v2(value_noise_memo(p * 2.7f + Vector2(5.3f, 1.7f), s),
				value_noise_memo(p * 2.7f + Vector2(-8.1f, 4.4f), s));
		p = p + (w - Vector2(0.5f, 0.5f)) * (float)warp;
	} else {
		p = q / (float)record.scale_m + record.offset;
	}
	double slack = c.bound_slack;
	double broad = octave(p, 0) * (1.0 - c.detail - c.fine);
	if (broad + c.detail + c.fine + slack <= below || broad > above + slack) {
		return broad;
	}
	double detail = octave(p * (float)c.detail_scale + c.detail_offset, 1);
	double sum = broad + detail * c.detail;
	if (sum + c.fine + slack <= below || sum > above + slack) {
		return sum;
	}
	double fine = octave(p * (float)c.fine_scale + c.fine_offset, 2);
	return sum + fine * c.fine;
}

double Accents::octave(Vector2 p, int channel) const {
	int64_t ix = floori(p.x);
	int64_t iy = floori(p.y);
	Vector2 f = v2((double)p.x - ix, (double)p.y - iy);
	f = f * f * (Vector2(3.0f, 3.0f) - f * 2.0f);
	int64_t cells = c.noise_cells;
	int64_t x0 = posmod(ix, cells);
	int64_t y0 = posmod(iy, cells);
	int64_t x1 = (x0 + 1) % cells;
	int64_t y1 = (y0 + 1) % cells;
	const uint8_t *lattice = c.lattice.data();
	double a = lattice[(y0 * cells + x0) * 4 + channel];
	double b = lattice[(y0 * cells + x1) * 4 + channel];
	double cc = lattice[(y1 * cells + x0) * 4 + channel];
	double d = lattice[(y1 * cells + x1) * 4 + channel];
	return glerp(glerp(a, b, f.x), glerp(cc, d, f.x), f.y) / 255.0;
}

double Accents::value_noise_memo(Vector2 p, int64_t seed) {
	int64_t ix = floori(p.x);
	int64_t iz = floori(p.y);
	Vector2 u = v2((double)p.x - ix, (double)p.y - iz);
	u = u * u * (Vector2(3.0f, 3.0f) - u * 2.0f);
	int64_t cell = (int64_t)(((uint64_t)ix << 32) ^ (uint64_t)(iz & MASK32));
	const Hash4 *known = memo.find(cell);
	Hash4 h;
	if (known) {
		h = *known;
	} else {
		int64_t cx = (ix + seed) & MASK32;
		int64_t cz = (iz + ((seed * 7919) & MASK32)) & MASK32;
		h = { (double)pcg2d_x(cx, cz), (double)pcg2d_x((cx + 1) & MASK32, cz), (double)pcg2d_x(cx, (cz + 1) & MASK32),
			(double)pcg2d_x((cx + 1) & MASK32, (cz + 1) & MASK32) };
		memo.set(cell, h);
	}
	return glerp(glerp(h[0], h[1], u.x), glerp(h[2], h[3], u.x), u.y) * c.inv_uint_max;
}

int64_t pcg2d_x(int64_t x, int64_t y) {
	int64_t vx = (x * 1664525 + 1013904223) & MASK32;
	int64_t vy = (y * 1664525 + 1013904223) & MASK32;
	vx = (vx + vy * 1664525) & MASK32;
	vy = (vy + vx * 1664525) & MASK32;
	vx ^= vx >> 16;
	vy ^= vy >> 16;
	vx = (vx + vy * 1664525) & MASK32;
	return vx ^ (vx >> 16);
}

// ---- pattern noise ------------------------------------------------------------------------------

void setup_pattern_noise(fastnoiselite::FastNoiseLite &noise, int seed, float frequency, int octaves) {
	// Godot's FastNoiseLite resource sets every parameter from its defaults in its constructor
	// (fractal lacunarity 2, gain 0.5, weighted strength 0, ping-pong 2), then the setters
	// ScatterGenerator._noise calls; the bounding is recomputed by each fractal setter.
	noise.SetNoiseType(fastnoiselite::FastNoiseLite::NoiseType_Perlin);
	noise.SetSeed(seed);
	noise.SetFrequency(frequency);
	noise.SetFractalType(fastnoiselite::FastNoiseLite::FractalType_FBm);
	noise.SetFractalOctaves(octaves);
	noise.SetFractalLacunarity(2.0f);
	noise.SetFractalGain(0.5f);
	noise.SetFractalWeightedStrength(0.0f);
	noise.SetFractalPingPongStrength(2.0f);
}

} // namespace ttscatter
