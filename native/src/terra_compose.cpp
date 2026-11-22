// Stage 1, compose (from spike terraform-s2-cpu): the landform primitives and sculpt strokes summed
// into one height, per sample in document order. Every kernel is additive (or, for smoothing, writes
// a weight the smooth pass reads), so a dab only changes the samples under it. Positions are in the
// map document's centred frame (terra_core.h Grid); a plane's base is its height at the map centre.
#include "terra_kernels.h"
#include "terra_stages.h"

namespace terra {

void compose_rect(const std::vector<const Prim *> &prims, const std::vector<const ComposeKernel *> &kinds,
		const std::vector<Rect> &bounds, const Grid &g, const Rect &r, float *Hraw, float *SW) {
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			Hraw[int64_t(j) * g.w + i] = 0.0f;
			SW[int64_t(j) * g.w + i] = 0.0f;
		}
	}
	for (size_t k = 0; k < prims.size(); k++) {
		Rect b = bounds[k].inter(r);
		if (!b.empty()) {
			kinds[k]->apply(*prims[k], g, b, Hraw, SW);
		}
	}
}

void smooth_rect(const Grid &g, const Rect &r, const float *Hraw, const float *SW, float *H0) {
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			float sw = SW[o];
			if (sw <= 0.0f) {
				H0[o] = Hraw[o];
				continue;
			}
			int ja = std::max(0, j - SMOOTH_R), jb = std::min(g.h - 1, j + SMOOTH_R);
			int ia = std::max(0, i - SMOOTH_R), ib = std::min(g.w - 1, i + SMOOTH_R);
			double s = 0.0;
			for (int y = ja; y <= jb; y++) {
				for (int x = ia; x <= ib; x++) {
					s += Hraw[int64_t(y) * g.w + x];
				}
			}
			double mean = s / double((jb - ja + 1) * (ib - ia + 1));
			double w = std::min(double(sw), 1.0);
			H0[o] = float(Hraw[o] + (mean - Hraw[o]) * w);
		}
	}
}

bool dab_bounds(const Prim &p, int stride, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	for (size_t k = 0; k + stride <= p.d.size(); k += stride) {
		double r = p.d[k + 2];
		x0 = std::min(x0, p.d[k] - r);
		z0 = std::min(z0, p.d[k + 1] - r);
		x1 = std::max(x1, p.d[k] + r);
		z1 = std::max(z1, p.d[k + 1] + r);
	}
	return true;
}

static bool plane_bounds(const Prim &, double &, double &, double &, double &) {
	return false;
}

static void plane_apply(const Prim &p, const Grid &g, const Rect &r, float *H, float *) {
	if (p.d.size() < 3) {
		return;
	}
	double base = p.d[0], sx = p.d[1], sz = p.d[2];
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			float &h = H[int64_t(j) * g.w + i];
			h = float(h + (base + sx * g.wx(i) + sz * g.wz(j)));
		}
	}
}

static bool hill_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	double r = p.d.size() >= 4 ? p.d[3] : 0.0;
	x0 = p.d[0] - r;
	z0 = p.d[1] - r;
	x1 = p.d[0] + r;
	z1 = p.d[1] + r;
	return true;
}

static void hill_apply(const Prim &p, const Grid &g, const Rect &r, float *H, float *) {
	if (p.d.size() < 5) {
		return;
	}
	double cx = p.d[0], cz = p.d[1], hgt = p.d[2], rad = p.d[3], prof = p.d[4];
	Rect b = g.rect_world(cx - rad, cz - rad, cx + rad, cz + rad).inter(r);
	for (int j = b.y0; j < b.y1; j++) {
		for (int i = b.x0; i < b.x1; i++) {
			double dx = g.wx(i) - cx, dz = g.wz(j) - cz;
			double t2 = (dx * dx + dz * dz) / (rad * rad);
			if (t2 >= 1.0) {
				continue;
			}
			float &h = H[int64_t(j) * g.w + i];
			h = float(h + hgt * det_pow(1.0 - t2, prof));
		}
	}
}

static bool ridge_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	double w = p.d.size() >= 2 ? p.d[1] : 0.0;
	for (size_t k = 3; k + 1 < p.d.size(); k += 2) {
		x0 = std::min(x0, p.d[k] - w);
		z0 = std::min(z0, p.d[k + 1] - w);
		x1 = std::max(x1, p.d[k] + w);
		z1 = std::max(z1, p.d[k + 1] + w);
	}
	return true;
}

static void ridge_apply(const Prim &p, const Grid &g, const Rect &r, float *H, float *) {
	if (p.d.size() < 7) {
		return;
	}
	double hgt = p.d[0], wid = p.d[1], prof = p.d[2];
	Line l;
	for (size_t k = 3; k + 1 < p.d.size(); k += 2) {
		l.x.push_back(p.d[k]);
		l.z.push_back(p.d[k + 1]);
	}
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	std::vector<int> segs;
	segments_near(l, wid, bx0, bz0, bx1, bz1, segs);
	if (segs.empty()) {
		return;
	}
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			double best = 1e30, t;
			for (int k : segs) {
				best = std::min(best, seg_d2(l, k, g.wx(i), g.wz(j), t));
			}
			double t2 = best / (wid * wid);
			if (t2 >= 1.0) {
				continue;
			}
			float &h = H[int64_t(j) * g.w + i];
			h = float(h + hgt * det_pow(1.0 - t2, prof));
		}
	}
}

static bool stroke_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return dab_bounds(p, 5, x0, z0, x1, z1);
}

static void stroke_apply(const Prim &p, const Grid &g, const Rect &r, float *H, float *SW) {
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	for (size_t k = 0; k + 5 <= p.d.size(); k += 5) {
		double cx = p.d[k], cz = p.d[k + 1], rad = p.d[k + 2], str = p.d[k + 3];
		int mode = int(p.d[k + 4]);
		if (cx + rad < bx0 || cx - rad > bx1 || cz + rad < bz0 || cz - rad > bz1) {
			continue;
		}
		Rect b = g.rect_world(cx - rad, cz - rad, cx + rad, cz + rad).inter(r);
		for (int j = b.y0; j < b.y1; j++) {
			for (int i = b.x0; i < b.x1; i++) {
				double dx = g.wx(i) - cx, dz = g.wz(j) - cz;
				double t2 = (dx * dx + dz * dz) / (rad * rad);
				if (t2 >= 1.0) {
					continue;
				}
				double f = (1.0 - t2) * (1.0 - t2) * str;
				int64_t o = int64_t(j) * g.w + i;
				if (mode == 0) {
					H[o] = float(H[o] + f);
				} else if (mode == 1) {
					H[o] = float(H[o] - f);
				} else {
					SW[o] = float(SW[o] + f);
				}
			}
		}
	}
}

static const ComposeKernel KERNELS[] = {
	{ P_PLANE, plane_bounds, plane_apply },
	{ P_HILL, hill_bounds, hill_apply },
	{ P_RIDGE, ridge_bounds, ridge_apply },
	{ P_STROKE, stroke_bounds, stroke_apply },
};

const ComposeKernel *compose_kernel(int type) {
	for (const ComposeKernel &k : KERNELS) {
		if (k.type == type) {
			return &k;
		}
	}
	return nullptr;
}

} // namespace terra
