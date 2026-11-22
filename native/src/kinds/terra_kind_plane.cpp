// The plane (built-in kind 0; utils/terraform/kinds/plane/): [base, slope_x, slope_z], a tilted
// plane over the whole map, added to the composed height. Its base is its height at the map centre.
#include "terra_kinds.h"

namespace terra {

static bool plane_bounds(const Prim &, double &, double &, double &, double &) {
	return false;
}

static void plane_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	if (p.d.size() < 3) {
		return;
	}
	float *H = out.H;
	double base = p.d[0], sx = p.d[1], sz = p.d[2];
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			float &h = H[int64_t(j) * g.w + i];
			h = float(h + (base + sx * g.wx(i) + sz * g.wz(j)));
		}
	}
}

TERRA_KIND(0, "plane", STAGE_COMPOSE, 3, 0, plane_bounds, plane_apply);

} // namespace terra
