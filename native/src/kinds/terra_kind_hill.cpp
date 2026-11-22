// The hill (built-in kind 1; utils/terraform/kinds/hill/): [cx, cz, height, radius, profile], a
// round rise added to the composed height, height * (1 - d^2 / r^2)^profile inside the radius.
#include "terra_kinds.h"

namespace terra {

static bool hill_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	double r = p.d.size() >= 4 ? p.d[3] : 0.0;
	x0 = p.d[0] - r;
	z0 = p.d[1] - r;
	x1 = p.d[0] + r;
	z1 = p.d[1] + r;
	return true;
}

static void hill_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	if (p.d.size() < 5) {
		return;
	}
	float *H = out.H;
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

TERRA_KIND(1, "hill", STAGE_COMPOSE, 5, 0, hill_bounds, hill_apply);

} // namespace terra
