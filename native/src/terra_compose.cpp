// Stage 1, compose, and stage 5d, paint (from spike terraform-s2-cpu): the stamp stages. Each
// primitive of the stage is applied by its kind's kernel (src/kinds/, terra_kinds.h), per sample in
// document order, so any rect gives the same bits. Compose sums the landform primitives and sculpt
// strokes into one height (every kernel is additive, writes a weight the smooth pass reads, or, as
// the terrace, reads the height composed so far); paint lays the coats. Positions are in the map
// document's centred frame (terra_core.h Grid). Stage 1b, smooth, is here too.
#include <cstring>

#include "terra_kinds.h"
#include "terra_stages.h"

namespace terra {

void stamp_rect(const std::vector<const Prim *> &prims, const std::vector<const KindDef *> &kinds,
		const std::vector<Rect> &bounds, const Grid &g, const Rect &r, const StampOut &out) {
	for (int j = r.y0; j < r.y1; j++) {
		int64_t o = int64_t(j) * g.w + r.x0;
		size_t n = size_t(r.x1 - r.x0);
		for (float *a : { out.H, out.SW }) {
			if (a) {
				std::memset(a + o, 0, n * sizeof(float));
			}
		}
	}
	for (size_t k = 0; k < prims.size(); k++) {
		Rect b = bounds[k].inter(r);
		if (!b.empty()) {
			kinds[k]->apply(*prims[k], g, b, out);
		}
	}
}

// The smooth stage's model (card terraform-p2-sculpt-kinds). HeightStroke smooths once per dab,
// each time moving a sample toward the mean of a box around it by 1 - exp(-rate w s): repeated, that
// is diffusion, whose spread grows with the exposure. One pass reproduces it to second order: a
// sample of summed exposure sw (tau = SMOOTH_RATE sw) moves by a = 1 - exp(-tau) toward the mean of
// a box whose variance is SMOOTH_VAR_M2 tau / a (the per-dab box's variance times the diffusion time,
// over the blend), so a light touch is HeightStroke's one box and a long hold spreads wider. The box
// half width is continuous: the means of the two whole widths around it are blended. The box sums
// come from a summed-area table of the heights in fixed point (int64, exact), so any rect gives the
// same bits.
namespace {
// The variance (m^2, per axis) of HeightStroke's smoothing box at the default brush: half width
// HeightBrush.smooth_kernel(3 m, 0.25 m) = 4 document samples, (k (k + 1) / 3) 0.25^2.
constexpr double SMOOTH_VAR_M2 = 4.0 * 5.0 / 3.0 * 0.0625;
// Fixed point of the summed-area table: 2^20 units a metre.
constexpr double SAT_UNIT = 1048576.0;

// The continuous half width (samples) of a box of `var` m^2 at `step`: R (R + 1) / 3 step^2 = var.
double box_half(double var, double step) {
	return 0.5 * (std::sqrt(1.0 + 12.0 * var / (step * step)) - 1.0);
}
} // namespace

void smooth_rect(const Grid &g, const Rect &r, const float *Hraw, const float *SW, float *H0) {
	bool any = false;
	for (int j = r.y0; j < r.y1 && !any; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			if (SW[int64_t(j) * g.w + i] > 0.0f) {
				any = true;
				break;
			}
		}
	}
	if (!any) {
		for (int j = r.y0; j < r.y1; j++) {
			int64_t o = int64_t(j) * g.w + r.x0;
			std::memcpy(H0 + o, Hraw + o, size_t(r.x1 - r.x0) * sizeof(float));
		}
		return;
	}
	Rect e = r.grow(SMOOTH_R + 1).clip(g.w, g.h);
	int ew = e.x1 - e.x0 + 1, eh = e.y1 - e.y0 + 1;
	std::vector<int64_t> S(size_t(ew) * eh, 0);
	for (int y = 1; y < eh; y++) {
		int64_t run = 0;
		const float *row = Hraw + int64_t(e.y0 + y - 1) * g.w + e.x0;
		for (int x = 1; x < ew; x++) {
			run += std::llround(double(row[x - 1]) * SAT_UNIT);
			S[size_t(y) * ew + x] = S[size_t(y - 1) * ew + x] + run;
		}
	}
	// The mean of the box of half widths (rx, rz) around (i, j), clipped to the grid.
	auto mean = [&](int i, int j, int rx, int rz) {
		int x0 = std::max(i - rx, 0), x1 = std::min(i + rx + 1, g.w);
		int z0 = std::max(j - rz, 0), z1 = std::min(j + rz + 1, g.h);
		x0 -= e.x0, x1 -= e.x0, z0 -= e.y0, z1 -= e.y0;
		int64_t s = S[size_t(z1) * ew + x1] - S[size_t(z0) * ew + x1] - S[size_t(z1) * ew + x0] + S[size_t(z0) * ew + x0];
		return double(s) / SAT_UNIT / double(int64_t(x1 - x0) * (z1 - z0));
	};
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			float sw = SW[o];
			if (sw <= 0.0f) {
				H0[o] = Hraw[o];
				continue;
			}
			double tau = SMOOTH_RATE * double(sw);
			double a = 1.0 - det_exp(-tau);
			double var = SMOOTH_VAR_M2 * (a > 1e-9 ? tau / a : 1.0);
			double hx = std::min(box_half(var, g.sx), double(SMOOTH_R - 1));
			double hz = std::min(box_half(var, g.sz), double(SMOOTH_R - 1));
			int rx = int(hx), rz = int(hz);
			double fx = hx - rx, fz = hz - rz;
			// Bilinear in the two half widths: the four whole boxes around the continuous one.
			double m = mean(i, j, rx, rz) * (1.0 - fx) * (1.0 - fz) + mean(i, j, rx + 1, rz) * fx * (1.0 - fz) +
					mean(i, j, rx, rz + 1) * (1.0 - fx) * fz + mean(i, j, rx + 1, rz + 1) * fx * fz;
			H0[o] = float(Hraw[o] + (m - Hraw[o]) * a);
		}
	}
}

} // namespace terra
