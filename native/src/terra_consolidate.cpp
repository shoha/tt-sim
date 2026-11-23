// TerraDerive::consolidate (card terraform-p2-sculpt-kinds; docs/systems/terraform.md "Folding"):
// a run of old sculpt primitives folded into sculpt rasters (kind 9, kinds/terra_kind_sculpt.cpp).
//
// The run is consecutive among the compose primitives (strokes, levels, terraces). Over every
// 64-sample tile the run's influence meets, compose runs twice from the same start: the primitives
// before the run, then that plus the run, and the raster is their difference (heights, and the
// smoothing weight as a second layer where the run smoothed). Composing is per sample in document
// order, so the run's difference at a sample depends only on what came before it there: the rasters
// put in the run's place give the same Hraw and SW, within one float rounding of each sum. What a fold
// freezes is the run's reading of the ground before it (a level or terrace over a hill that later
// moves). Tiles run on the derive's pool; nothing of the derive is written.
#include <cstring>

#include "terra_derive.h"
#include "terra_kinds.h"
#include "terra_pool.h"

using namespace terra;

namespace godot {

Array TerraDerive::consolidate(const PackedInt32Array &ids) const {
	Array out;
	if (async_running || ids.is_empty()) {
		return out;
	}
	// The compose primitives in document order, and where the run sits among them.
	std::vector<const Prim *> cp;
	std::vector<const KindDef *> ck;
	std::vector<Rect> cr;
	for (const Prim &p : prims) {
		const KindDef *k = kind_def(p.type);
		if (k && k->stage == STAGE_COMPOSE) {
			cp.push_back(&p);
			ck.push_back(k);
			cr.push_back(influence(p));
		}
	}
	int first = -1;
	for (int i = 0; i < int(cp.size()); i++) {
		if (cp[i]->id == ids[0]) {
			first = i;
			break;
		}
	}
	int n = int(ids.size());
	if (first < 0 || first + n > int(cp.size())) {
		return out;
	}
	Dirty touched;
	touched.init(g);
	for (int k = 0; k < n; k++) {
		if (cp[first + k]->id != ids[k]) {
			return out;
		}
		touched.add(cr[first + k], g);
	}
	std::vector<int> tiles;
	for (int t = 0; t < g.ntiles(); t++) {
		if (!touched.t[t].empty()) {
			tiles.push_back(t);
		}
	}
	std::vector<const Prim *> before_p(cp.begin(), cp.begin() + first);
	std::vector<const KindDef *> before_k(ck.begin(), ck.begin() + first);
	std::vector<Rect> before_r(cr.begin(), cr.begin() + first);
	size_t total = size_t(g.w) * g.h;
	std::vector<float> Hb(total), SWb(total), Hw(total), SWw(total);
	std::vector<PackedFloat32Array> rasters(tiles.size());
	pool->run(int(tiles.size()), [&](int q) {
		Rect r = g.tile_rect(tiles[q]);
		StampOut sb, sw;
		sb.H = Hb.data();
		sb.SW = SWb.data();
		sw.H = Hw.data();
		sw.SW = SWw.data();
		stamp_rect(before_p, before_k, before_r, g, r, sb);
		for (int j = r.y0; j < r.y1; j++) {
			int64_t o = int64_t(j) * g.w + r.x0;
			size_t bytes = size_t(r.x1 - r.x0) * sizeof(float);
			std::memcpy(&Hw[o], &Hb[o], bytes);
			std::memcpy(&SWw[o], &SWb[o], bytes);
		}
		for (int k = first; k < first + n; k++) {
			Rect b = cr[k].inter(r);
			if (!b.empty()) {
				ck[k]->apply(*cp[k], g, b, sw);
			}
		}
		int nx = r.x1 - r.x0, nz = r.y1 - r.y0;
		bool any_h = false, any_w = false;
		for (int j = r.y0; j < r.y1 && !(any_h && any_w); j++) {
			for (int i = r.x0; i < r.x1; i++) {
				int64_t o = int64_t(j) * g.w + i;
				any_h = any_h || Hw[o] != Hb[o];
				any_w = any_w || SWw[o] != SWb[o];
			}
		}
		if (!any_h && !any_w) {
			return;
		}
		int layers = any_w ? 2 : 1;
		size_t cells = size_t(nx) * nz;
		PackedFloat32Array d;
		d.resize(int64_t(7 + cells * layers));
		float *f = d.ptrw();
		f[0] = float(g.wx(r.x0));
		f[1] = float(g.wz(r.y0));
		f[2] = float(g.sx);
		f[3] = float(g.sz);
		f[4] = float(nx);
		f[5] = float(nz);
		f[6] = float(layers);
		for (int j = r.y0; j < r.y1; j++) {
			for (int i = r.x0; i < r.x1; i++) {
				int64_t o = int64_t(j) * g.w + i;
				size_t c = size_t(j - r.y0) * nx + (i - r.x0);
				f[7 + c] = Hw[o] - Hb[o];
				if (layers == 2) {
					f[7 + cells + c] = SWw[o] - SWb[o];
				}
			}
		}
		rasters[q] = d;
	});
	for (const PackedFloat32Array &d : rasters) {
		if (!d.is_empty()) {
			out.push_back(d);
		}
	}
	return out;
}

} // namespace godot
