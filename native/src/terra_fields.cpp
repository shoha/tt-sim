// Stages 5 and 6 (spike terraform-s2-cpu): the fields every look and rule reads (slope, capped
// distances to water, path and footprint by an exact two-pass transform, wetness), and the ground
// rule table resolved into the packed control map. No shader guesses a distance or a direction.
#include "terra_stages.h"

namespace terra {

void slope_rect(const Grid &g, const Rect &r, const float *H2, float *SL) {
	for (int j = r.y0; j < r.y1; j++) {
		int ja = std::max(j - 1, 0), jb = std::min(j + 1, g.h - 1);
		for (int i = r.x0; i < r.x1; i++) {
			int ia = std::max(i - 1, 0), ib = std::min(i + 1, g.w - 1);
			double gx = (double(H2[int64_t(j) * g.w + ib]) - H2[int64_t(j) * g.w + ia]) / (double(ib - ia) * g.sx);
			double gz = (double(H2[int64_t(jb) * g.w + i]) - H2[int64_t(ja) * g.w + i]) / (double(jb - ja) * g.sz);
			SL[int64_t(j) * g.w + i] = float(det_atan(std::sqrt(gx * gx + gz * gz)) * (180.0 / PI));
		}
	}
}

void edt_rect(const Grid &g, const Rect &r, const uint8_t *mask, int cap, float *dist) {
	Rect win = r.grow(cap).clip(g.w, g.h);
	int W = win.x1 - win.x0, RH = r.y1 - r.y0;
	const double INF = 1e18;
	// Distances are in metres with each axis's own step: the column pass keeps (dy sz)^2, the row
	// pass weighs the parabolas by sx^2. The cap is `cap` samples of the smaller step, so a source
	// outside the window (more than `cap` samples away on an axis) is past the cap either way.
	const double ax = g.sx * g.sx, sz = g.sz;
	// Column pass: squared distance to the nearest source in each column of the window, kept for
	// the rows of r only.
	std::vector<double> col(size_t(W) * RH, INF);
	for (int x = 0; x < W; x++) {
		int gx = win.x0 + x;
		int last = -1000000;
		std::vector<int> down(win.y1 - win.y0);
		for (int y = win.y0; y < win.y1; y++) {
			if (mask[int64_t(y) * g.w + gx]) {
				last = y;
			}
			down[y - win.y0] = last;
		}
		int next = 1000000;
		for (int y = win.y1 - 1; y >= win.y0; y--) {
			if (mask[int64_t(y) * g.w + gx]) {
				next = y;
			}
			if (y >= r.y0 && y < r.y1) {
				int dy = std::min(y - down[y - win.y0], next - y);
				if (dy < 100000) {
					col[size_t(y - r.y0) * W + x] = (double(dy) * sz) * (double(dy) * sz);
				}
			}
		}
	}
	// Row pass: the lower envelope of parabolas (Felzenszwalb and Huttenlocher) over finite entries.
	std::vector<int> v(W);
	std::vector<double> zb(W + 1);
	double capd = double(cap) * g.step_min();
	for (int y = 0; y < RH; y++) {
		const double *f = &col[size_t(y) * W];
		int k = -1;
		for (int q = 0; q < W; q++) {
			if (f[q] >= INF) {
				continue;
			}
			if (k < 0) {
				k = 0;
				v[0] = q;
				zb[0] = -INF;
				zb[1] = INF;
				continue;
			}
			double s;
			while (true) {
				int p = v[k];
				s = ((f[q] + ax * (double(q) * q)) - (f[p] + ax * (double(p) * p))) / (ax * (2.0 * q - 2.0 * p));
				if (s <= zb[k] && k > 0) {
					k--;
				} else {
					break;
				}
			}
			if (s <= zb[k]) {
				v[0] = q; // k == 0 and the new parabola dominates
				zb[0] = -INF;
				zb[1] = INF;
				continue;
			}
			k++;
			v[k] = q;
			zb[k] = s;
			zb[k + 1] = INF;
		}
		int gy = r.y0 + y;
		int kk = 0;
		for (int gx = r.x0; gx < r.x1; gx++) {
			int q = gx - win.x0;
			double d2 = INF;
			if (k >= 0) {
				while (kk < k && zb[kk + 1] < q) {
					kk++;
				}
				int p = v[kk];
				d2 = ax * (double(q - p) * double(q - p)) + f[p];
			}
			double d = d2 >= INF ? capd : std::min(std::sqrt(d2), capd);
			dist[int64_t(gy) * g.w + gx] = float(d);
		}
	}
}

/// Box sums of H2 of half width R over rect r: rows first over r's columns for the rows r needs
/// (clamped at the map), then columns. Each output adds the same samples in the same order
/// whatever rect it is computed in, so update equals build bitwise. Round 4: `S` takes every S-th
/// tap of the box (-R, -R + S, ..., R; R a multiple of S): the wide box at stride 2 is 15 taps a
/// pass instead of 29, the same reach.
static void box_rect(const Grid &g, const Rect &r, const float *H2, int R, std::vector<double> &out, int S = 1) {
	int rw = r.x1 - r.x0, rh = r.y1 - r.y0;
	int y0 = std::max(r.y0 - R, 0), y1 = std::min(r.y1 + R, g.h);
	std::vector<double> rows(size_t(y1 - y0) * rw);
	for (int y = y0; y < y1; y++) {
		const float *row = H2 + int64_t(y) * g.w;
		for (int i = r.x0; i < r.x1; i++) {
			double s = 0.0;
			for (int d = -R; d <= R; d += S) {
				s += row[std::clamp(i + d, 0, g.w - 1)];
			}
			rows[size_t(y - y0) * rw + (i - r.x0)] = s;
		}
	}
	out.assign(size_t(rw) * rh, 0.0);
	int taps = 2 * (R / S) + 1;
	double inv = 1.0 / double(taps * taps);
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = 0; i < rw; i++) {
			double s = 0.0;
			for (int d = -R; d <= R; d += S) {
				s += rows[size_t(std::clamp(j + d, 0, g.h - 1) - y0) * rw + i];
			}
			out[size_t(j - r.y0) * rw + i] = s * inv;
		}
	}
}

void look_rect(const Grid &g, const Rect &r, const float *H2, float *HB, float *CV) {
	std::vector<double> nb, wb;
	box_rect(g, r, H2, LOOK_NARROW, nb);
	box_rect(g, r, H2, LOOK_WIDE, wb, LOOK_WIDE_STRIDE);
	int rw = r.x1 - r.x0;
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			size_t k = size_t(j - r.y0) * rw + (i - r.x0);
			int64_t o = int64_t(j) * g.w + i;
			HB[o] = float(nb[k]);
			CV[o] = float(wb[k] - nb[k]);
		}
	}
}

void rules_rect(const std::vector<Rule> &rules, const Grid &g, const Rect &r, const FieldInputs &in, uint8_t *CT) {
	constexpr int NC = 32;
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			double depth = std::max(0.0, double(in.WL[o]) - in.H2[o]);
			double wet = depth > 0.0 ? 1.0 : det_exp(-double(in.DW[o]) / 1.2);
			double f[F_COUNT] = { depth, in.SL[o], in.DW[o], in.DP[o], in.DF[o], wet, in.PW[o * 4] / 255.0, in.H2[o],
				in.PM[o] / 255.0, in.CV[o] };
			double acc[NC] = {};
			double rem = 1.0;
			for (int ri = int(rules.size()) - 1; ri >= 0 && rem > 0.0; ri--) {
				const Rule &rule = rules[ri];
				double w = 1.0;
				for (const Term &t : rule.terms) {
					double val = f[t.field];
					if (t.lo > -1e8f) {
						w *= t.soft > 0.0f ? smoothstep(t.lo - t.soft, t.lo + t.soft, val) : (val >= t.lo ? 1.0 : 0.0);
					}
					if (t.hi < 1e8f) {
						w *= 1.0 - (t.soft > 0.0f ? smoothstep(t.hi - t.soft, t.hi + t.soft, val) : (val > t.hi ? 1.0 : 0.0));
					}
				}
				if (w <= 0.0) {
					continue;
				}
				int cls = rule.cls < 0 ? in.PI[o * 4] : rule.cls;
				acc[std::clamp(cls, 0, NC - 1)] += w * rem;
				rem *= 1.0 - w;
			}
			int a = 0, b = 0;
			double ca = -1.0, cb = -1.0;
			for (int c = 0; c < NC; c++) {
				if (acc[c] > ca) {
					b = a;
					cb = ca;
					a = c;
					ca = acc[c];
				} else if (acc[c] > cb) {
					b = c;
					cb = acc[c];
				}
			}
			double blend = (ca + cb) > 0.0 && cb > 0.0 ? cb / (ca + cb) : 0.0;
			uint8_t *out = CT + o * 4;
			out[0] = uint8_t(a);
			out[1] = uint8_t(cb > 0.0 ? b : a);
			out[2] = unit_u8(blend);
			out[3] = unit_u8(wet);
		}
	}
}

} // namespace terra
