// The consolidated sculpt raster (kind 9, the id phase 1 reserved for it; card
// terraform-p2-sculpt-kinds; utils/terraform/kinds/sculpt/): old sculpt strokes folded into data.
// Floats: a header [x0, z0, sx, sz, nx, nz, layers], the world position of the raster's first sample,
// the grid's steps, its size in samples (at most a 64-sample tile) and 1 or 2 layers; then nx * nz
// height deltas, row-major, and with 2 layers as many smoothing-weight deltas. Compose adds them to
// the height (and the weight the smooth stage reads) composed so far, at the raster's place in
// document order. TerraDerive::consolidate (terra_consolidate.cpp) makes them: the difference the
// folded run of strokes made, so the derive after a fold equals the one before it (within float
// rounding) and peers receive the rasters as data, never recomputing them.
//
// The header holds world positions and steps rather than sample indices because a kind's bounds
// see no grid; the kernel finds its samples by rounding, and a raster made on another grid (steps
// that differ) is ignored.
#include <cmath>

#include "terra_kinds.h"

namespace terra {

namespace {

constexpr int HEADER = 7;

// The raster's size, or false when its header does not describe its floats.
bool shape(const Prim &p, int &nx, int &nz, int &layers) {
	if (p.d.size() < size_t(HEADER)) {
		return false;
	}
	nx = int(p.d[4]);
	nz = int(p.d[5]);
	layers = int(p.d[6]);
	return nx > 0 && nz > 0 && (layers == 1 || layers == 2) &&
			p.d.size() == size_t(HEADER) + size_t(nx) * size_t(nz) * size_t(layers);
}

} // namespace

static bool sculpt_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	int nx = 0, nz = 0, layers = 0;
	x0 = p.d.size() > 0 ? p.d[0] : 0.0;
	z0 = p.d.size() > 1 ? p.d[1] : 0.0;
	x1 = x0;
	z1 = z0;
	if (shape(p, nx, nz, layers)) {
		x1 = x0 + double(p.d[2]) * (nx - 1);
		z1 = z0 + double(p.d[3]) * (nz - 1);
	}
	return true;
}

static void sculpt_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	int nx = 0, nz = 0, layers = 0;
	if (!shape(p, nx, nz, layers)) {
		return;
	}
	if (std::abs(double(p.d[2]) - g.sx) > 1e-4 * g.sx || std::abs(double(p.d[3]) - g.sz) > 1e-4 * g.sz) {
		return;
	}
	int i0 = int(std::floor(g.fx(p.d[0]) + 0.5)), j0 = int(std::floor(g.fz(p.d[1]) + 0.5));
	Rect b = Rect{ i0, j0, i0 + nx, j0 + nz }.inter(r);
	const float *dh = p.d.data() + HEADER;
	const float *dsw = layers == 2 ? dh + size_t(nx) * nz : nullptr;
	for (int j = b.y0; j < b.y1; j++) {
		for (int i = b.x0; i < b.x1; i++) {
			size_t q = size_t(j - j0) * nx + (i - i0);
			int64_t o = int64_t(j) * g.w + i;
			out.H[o] = float(out.H[o] + dh[q]);
			if (dsw) {
				out.SW[o] = float(out.SW[o] + dsw[q]);
			}
		}
	}
}

TERRA_KIND(9, "sculpt", STAGE_COMPOSE, 7, 1, sculpt_bounds, sculpt_apply);

} // namespace terra
