// The ridge (built-in kind 2; utils/terraform/kinds/ridge/): [height, width, profile, x0, z0, x1,
// z1, ...], a rise (or, with a negative height, a valley) along a polyline, added to the composed
// height as height * (1 - d^2 / w^2)^profile within the width of the nearest segment.
#include "terra_kinds.h"

namespace terra {

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

static void ridge_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	if (p.d.size() < 7) {
		return;
	}
	float *H = out.H;
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

TERRA_KIND(2, "ridge", STAGE_COMPOSE, 3, 2, ridge_bounds, ridge_apply);

} // namespace terra
