// The paint coat (built-in kind 8; utils/terraform/kinds/paint/): dabs [cx, cz, radius,
// surface_id]. Per sample the newest coat wins where it is strong (weight 1 inside half the radius,
// a smooth fall to 0 at the edge): the same surface keeps its strongest weight, another one takes
// over at half weight or more and otherwise only thins the coat under it. The rule table reads the
// coat (PI, PW) as the painted surface.
#include "terra_kinds.h"

namespace terra {

static bool paint_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return dab_bounds(p, 4, x0, z0, x1, z1);
}

static void paint_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	uint8_t *PI = out.PI;
	float *PW = out.PW;
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	for (size_t k = 0; k + 4 <= p.d.size(); k += 4) {
		double cx = p.d[k], cz = p.d[k + 1], rad = p.d[k + 2];
		int id = int(p.d[k + 3]);
		if (cx + rad < bx0 || cx - rad > bx1 || cz + rad < bz0 || cz - rad > bz1) {
			continue;
		}
		Rect b = g.rect_world(cx - rad, cz - rad, cx + rad, cz + rad).inter(r);
		for (int j = b.y0; j < b.y1; j++) {
			for (int i = b.x0; i < b.x1; i++) {
				double dx = g.wx(i) - cx, dz = g.wz(j) - cz;
				double t = std::sqrt(dx * dx + dz * dz) / rad;
				if (t >= 1.0) {
					continue;
				}
				double c = 1.0 - smoothstep(0.5, 1.0, t);
				int64_t o = int64_t(j) * g.w + i;
				if (PI[o] == id) {
					PW[o] = float(std::max(double(PW[o]), c));
				} else if (c >= 0.5 || PW[o] == 0.0f) {
					PI[o] = uint8_t(id);
					PW[o] = float(c);
				} else {
					PW[o] = float(PW[o] * (1.0 - c));
				}
			}
		}
	}
}

TERRA_KIND(8, "paint", STAGE_PAINT, 0, 4, paint_bounds, paint_apply);

} // namespace terra
