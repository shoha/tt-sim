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
		for (float *a : { out.H, out.SW, out.PW }) {
			if (a) {
				std::memset(a + o, 0, n * sizeof(float));
			}
		}
		if (out.PI) {
			std::memset(out.PI + o, 0, n);
		}
	}
	for (size_t k = 0; k < prims.size(); k++) {
		Rect b = bounds[k].inter(r);
		if (!b.empty()) {
			kinds[k]->apply(*prims[k], g, b, out);
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

} // namespace terra
