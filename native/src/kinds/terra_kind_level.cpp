// The level brush (kind 17; card terraform-p2-sculpt-kinds; utils/terraform/kinds/level/): Flatten
// and Tier. Dabs [ax, az, bx, bz, radius, target_y, strength, edge], each one frame's capsule from a
// to b (a press: a == b), d a sample's distance to the segment, as HeightStroke.dab sweeps it (point
// dabs missed HeightStroke's flatten by 4.6 cm in test_terra_sculpt_kinds; the capsule matches it).
// Not additive: like the terrace it reads the height composed so far, in document order.
//
// Edge 0, Flatten: HeightBrush FLATTEN ported. Each dab moves the height toward target_y by
// 1 - exp(-FLATTEN_RATE * w * strength) of the remaining way, w = (1 - d^2 / r^2)^2 and strength the
// dab's seconds of exposure, so a run of dabs at one target composes exactly as HeightStroke's
// approach does (the remainders multiply).
//
// Edge 1 and 2, Tier and Tier cut: HeightBrush.tier_goal ported. A run of consecutive tier dabs with
// one target and edge is one tier stroke: each sample's inset is the largest over the run of
// radius + TIER_SOFTEN_M - d (the soft profile's toe starts TIER_SOFTEN_M outside the ring, as in
// HeightStroke), and the sample takes tier_goal(start, target, inset) of its height when the run
// began, the stroke completed (HeightStroke.complete()). Tier (1) only raises samples that began
// below the target, Tier cut (2) only cuts samples above it. A tier is geometry, not exposure:
// strength is ignored. The riser is steeper than the 44 degree cliff rule, so the ground rules
// paint its face as rock.
#include <cmath>
#include <vector>

#include "terra_kinds.h"
#include "terra_math.h"

namespace terra {

namespace {

constexpr int STRIDE = 8;
// HeightBrush's constants (utils/height_brush.gd), the same names.
constexpr double FLATTEN_RATE = 4.0;
constexpr double TIER_MIN_FACE_M = 0.3;
constexpr double TIER_LIP_M = 0.25;
constexpr double TIER_LIP_WIDTH_M = 0.5;
constexpr double TIER_LIP_SHARE = 0.3;
constexpr double TIER_SOFTEN_M = 0.5;
// tan(TIER_FACE_DEG), TIER_FACE_DEG = 74: a constant, so no libm call (terra_math.h).
constexpr double TAN_FACE = 3.4874144438409087;

double face_width(double rise) {
	return std::max(TIER_MIN_FACE_M, std::abs(rise) / TAN_FACE);
}

// HeightBrush._tier_g2: the second antiderivative of the sharp raising profile.
double tier_g2(double x, double rise, double lip, double face, double w) {
	if (x <= 0.0) {
		return 0.0;
	}
	double slope = (rise - lip) / face;
	if (x < face) {
		return slope * x * x * x / 6.0;
	}
	double g1_face = slope * face * face * 0.5;
	double g2_face = slope * face * face * face / 6.0;
	if (x < face + w) {
		double d = x - face;
		double q = 1.0 - d / w;
		return g2_face + g1_face * d + rise * d * d * 0.5 - lip * w / 3.0 * (d - w * (1.0 - q * q * q * q) * 0.25);
	}
	double e = x - face - w;
	double g1_top = g1_face + rise * w - lip * w / 3.0;
	double g2_top = g2_face + g1_face * w + rise * w * w * 0.5 - lip * w * w * 0.25;
	return g2_top + g1_top * e + rise * e * e * 0.5;
}

// HeightBrush.soft_tier_offset: the sharp profile averaged over the TIER_SOFTEN_M tent.
double soft_offset(double x, double rise, double lip, double face) {
	const double b = TIER_SOFTEN_M, w = TIER_LIP_WIDTH_M;
	if (x + b <= 0.0) {
		return 0.0;
	}
	if (x - b >= face + w) {
		return rise;
	}
	double g = tier_g2(x + b, rise, lip, face, w) - 2.0 * tier_g2(x, rise, lip, face, w) + tier_g2(x - b, rise, lip, face, w);
	return std::clamp(g / (b * b), 0.0, rise);
}

// HeightBrush.tier_goal.
double tier_goal(double start, double target, double inset) {
	if (inset <= 0.0 || start == target) {
		return start;
	}
	double rise = std::abs(target - start);
	double lip = std::min(TIER_LIP_M, rise * TIER_LIP_SHARE);
	double face = face_width(rise - lip);
	double span = face + TIER_LIP_WIDTH_M + 2.0 * TIER_SOFTEN_M;
	if (inset >= span) {
		return target;
	}
	if (target > start) {
		return start + soft_offset(inset - TIER_SOFTEN_M, rise, lip, face);
	}
	return start - (rise - soft_offset(span - TIER_SOFTEN_M - inset, rise, lip, face));
}

// A dab's reach: its radius, plus the soft toe for a tier dab.
double reach(const Prim &p, size_t k) {
	return double(p.d[k + 4]) + (p.d[k + 7] != 0.0f ? TIER_SOFTEN_M : 0.0);
}

// The samples a capsule dab of reach `out` can touch, clipped to r.
Rect dab_rect(const Prim &p, size_t k, double out, const Grid &g, const Rect &r) {
	double ax = p.d[k], az = p.d[k + 1], bx = p.d[k + 2], bz = p.d[k + 3];
	return g.rect_world(std::min(ax, bx) - out, std::min(az, bz) - out, std::max(ax, bx) + out, std::max(az, bz) + out)
			.inter(r);
}

// The squared distance from sample (i, j) to dab k's segment, as HeightStroke.dab measures it.
double seg_d2(const Prim &p, size_t k, const Grid &g, int i, int j) {
	double ax = p.d[k], az = p.d[k + 1];
	double sx = double(p.d[k + 2]) - ax, sz = double(p.d[k + 3]) - az;
	double px = g.wx(i) - ax, pz = g.wz(j) - az;
	double l2 = sx * sx + sz * sz;
	double t = l2 > 0.0 ? std::clamp((px * sx + pz * sz) / l2, 0.0, 1.0) : 0.0;
	double dx = px - sx * t, dz = pz - sz * t;
	return dx * dx + dz * dz;
}

} // namespace

static bool level_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	for (size_t k = 0; k + STRIDE <= p.d.size(); k += STRIDE) {
		double r = reach(p, k);
		x0 = std::min(x0, std::min(double(p.d[k]), double(p.d[k + 2])) - r);
		z0 = std::min(z0, std::min(double(p.d[k + 1]), double(p.d[k + 3])) - r);
		x1 = std::max(x1, std::max(double(p.d[k]), double(p.d[k + 2])) + r);
		z1 = std::max(z1, std::max(double(p.d[k + 1]), double(p.d[k + 3])) + r);
	}
	return true;
}

// Flatten dab k over the samples of r.
static void flatten_dab(const Prim &p, size_t k, const Grid &g, const Rect &r, float *H) {
	double rad = p.d[k + 4], target = p.d[k + 5], sec = p.d[k + 6];
	Rect b = dab_rect(p, k, rad, g, r);
	for (int j = b.y0; j < b.y1; j++) {
		for (int i = b.x0; i < b.x1; i++) {
			double t2 = seg_d2(p, k, g, i, j) / (rad * rad);
			if (t2 >= 1.0) {
				continue;
			}
			double w = (1.0 - t2) * (1.0 - t2);
			double a = 1.0 - det_exp(-FLATTEN_RATE * w * sec);
			int64_t o = int64_t(j) * g.w + i;
			H[o] = float(H[o] + (target - H[o]) * a);
		}
	}
}

// The tier run of dabs [k0, k1) over the samples of r (see the header).
static void tier_run(const Prim &p, size_t k0, size_t k1, const Grid &g, const Rect &r, float *H) {
	double target = p.d[k0 + 5];
	bool up = p.d[k0 + 7] == 1.0f;
	Rect box;
	for (size_t k = k0; k < k1; k += STRIDE) {
		box = box.unite(dab_rect(p, k, reach(p, k), g, r));
	}
	if (box.empty()) {
		return;
	}
	int bw = box.x1 - box.x0;
	std::vector<double> inset(size_t(box.area()), 0.0);
	for (size_t k = k0; k < k1; k += STRIDE) {
		double out = reach(p, k);
		Rect b = dab_rect(p, k, out, g, box);
		for (int j = b.y0; j < b.y1; j++) {
			for (int i = b.x0; i < b.x1; i++) {
				double d2 = seg_d2(p, k, g, i, j);
				if (d2 >= out * out) {
					continue;
				}
				double &v = inset[size_t(j - box.y0) * bw + (i - box.x0)];
				v = std::max(v, out - std::sqrt(d2));
			}
		}
	}
	for (int j = box.y0; j < box.y1; j++) {
		for (int i = box.x0; i < box.x1; i++) {
			double in = inset[size_t(j - box.y0) * bw + (i - box.x0)];
			int64_t o = int64_t(j) * g.w + i;
			double start = H[o];
			if (in <= 0.0 || (up && start >= target) || (!up && start <= target)) {
				continue;
			}
			H[o] = float(tier_goal(start, target, in));
		}
	}
}

static void level_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	size_t n = p.d.size() - p.d.size() % STRIDE;
	size_t k = 0;
	while (k < n) {
		if (p.d[k + 7] == 0.0f) {
			flatten_dab(p, k, g, r, out.H);
			k += STRIDE;
			continue;
		}
		size_t e = k + STRIDE;
		while (e < n && p.d[e + 7] == p.d[k + 7] && p.d[e + 5] == p.d[k + 5]) {
			e += STRIDE;
		}
		tier_run(p, k, e, g, r, out.H);
		k = e;
	}
}

TERRA_KIND(17, "level", STAGE_COMPOSE, 0, 8, level_bounds, level_apply);

} // namespace terra
