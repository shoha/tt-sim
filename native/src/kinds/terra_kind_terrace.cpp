// The terrace brush's compose kernel (spike terraform-s2-cpu, added after the slice as the tool it
// was not designed for). Dabs [cx, cz, radius, tier_m, softness]: under each dab the composed
// height is pulled toward tiers of tier_m, each a flat tread and a soft riser (softness is the
// riser's share of a tier), by the dab's falloff. Not additive: it reads the height composed so
// far, in document order, so a terrace drawn after a hill snaps that hill. Kind 16, the first
// added through the registry (card terraform-p1-kinds; utils/terraform/kinds/terrace/).
#include "terra_kinds.h"

namespace terra {

static bool terrace_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return dab_bounds(p, 5, x0, z0, x1, z1);
}

static void terrace_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	float *H = out.H;
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	for (size_t k = 0; k + 5 <= p.d.size(); k += 5) {
		double cx = p.d[k], cz = p.d[k + 1], rad = p.d[k + 2], tier = std::max(0.05, double(p.d[k + 3]));
		double soft = std::clamp(double(p.d[k + 4]), 0.05, 1.0);
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
				double w = (1.0 - t2) * (1.0 - t2);
				int64_t o = int64_t(j) * g.w + i;
				double h = H[o], q = h / tier, fl = std::floor(q);
				double snapped = tier * (fl + smoothstep(1.0 - soft, 1.0, q - fl));
				H[o] = float(h + (snapped - h) * w);
			}
		}
	}
}

TERRA_KIND(16, "terrace", STAGE_COMPOSE, 0, 5, terrace_bounds, terrace_apply);

} // namespace terra
