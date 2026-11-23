// The sculpt stroke (built-in kind 3; utils/terraform/kinds/stroke/): dabs [cx, cz, radius,
// strength, mode] (mode 0 raise, 1 lower, 2 smooth). The falloff is HeightBrush's, (1 - d^2 / r^2)^2.
// Raise and lower add falloff * strength (metres) to the composed height; smooth adds falloff *
// strength (seconds of exposure) to the weight the smooth stage reads, which approaches the local
// mean by 1 - exp(-SMOOTH_RATE * weight) as HeightBrush SMOOTH does (smooth_rect). The gain
// (HeightBrush.raise_speed) and the split of a frame's capsule into point dabs are the kind
// script's (StrokeKind.capsule_dabs), so the kernel stays linear and appended dabs stay local.
#include "terra_kinds.h"

namespace terra {

static bool stroke_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return dab_bounds(p, 5, x0, z0, x1, z1);
}

static void stroke_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	float *H = out.H, *SW = out.SW;
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

TERRA_KIND(3, "stroke", STAGE_COMPOSE, 0, 5, stroke_bounds, stroke_apply);

} // namespace terra
