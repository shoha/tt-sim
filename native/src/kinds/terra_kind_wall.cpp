// The wall (built-in kind 7; utils/terraform/kinds/wall/): [height, thickness, x0, z0, ...], a line
// kind of the pads stage. Its footprint pad is graded along the line against the benched ground,
// and it leaves an opening where solved water crosses it: the cut-through rule is the stage order
// (from spike terraform-s2-cpu).
#include "terra_kinds.h"
#include "terra_stages.h"

namespace terra {

constexpr double WALL_SLOPE = 0.35;
constexpr double WALL_APRON = 1.2;

void wall_geometry(Wall &w, const Prim &prim, const Grid &g) {
	w.id = prim.id;
	w.height = prim.d[0];
	w.thick = prim.d[1];
	line_from(prim, 2, 0.25, w.l);
	double x0, z0, x1, z1;
	w.l.bounds(x0, z0, x1, z1);
	double reach = w.thick * 0.5 + WALL_APRON + 0.4;
	w.sample_rect = g.rect_world(x0 - w.thick - 0.4, z0 - w.thick - 0.4, x1 + w.thick + 0.4, z1 + w.thick + 0.4);
	w.rect = g.rect_world(x0 - reach, z0 - reach, x1 + reach, z1 + reach);
	// The points solve_wall reads: each line point and its two offsets across the footprint.
	int n = w.l.n();
	w.rx.clear();
	w.rz.clear();
	for (int k = 0; k < n; k++) {
		double x = w.l.x[k], z = w.l.z[k];
		int a = std::max(k - 1, 0), b = std::min(k + 1, n - 1);
		double tx = w.l.x[b] - w.l.x[a], tz = w.l.z[b] - w.l.z[a];
		double len = std::sqrt(tx * tx + tz * tz);
		len = len > 0.0 ? len : 1.0;
		double nx = -tz / len, nz = tx / len, off = w.thick * 0.5 + 0.3;
		for (double sgn : { 0.0, 1.0, -1.0 }) {
			w.rx.push_back(x + nx * off * sgn);
			w.rz.push_back(z + nz * off * sgn);
		}
	}
}

static bool wet_at(const Grid &g, const float *H, const float *WL, double x, double z) {
	return g.bilinear(WL, x, z) > g.bilinear(H, x, z) + 0.01f;
}

void solve_wall(Wall &w, const Grid &g, const float *Hp, const float *WL) {
	int n = w.l.n();
	std::vector<double> v(n);
	std::vector<uint8_t> wet(n);
	for (int k = 0; k < n; k++) {
		double x = w.l.x[k], z = w.l.z[k];
		v[k] = g.bilinear(Hp, x, z);
		int a = std::max(k - 1, 0), b = std::min(k + 1, n - 1);
		double tx = w.l.x[b] - w.l.x[a], tz = w.l.z[b] - w.l.z[a];
		double len = std::sqrt(tx * tx + tz * tz);
		len = len > 0.0 ? len : 1.0;
		double nx = -tz / len, nz = tx / len, off = w.thick * 0.5 + 0.3;
		wet[k] = wet_at(g, Hp, WL, x, z) || wet_at(g, Hp, WL, x + nx * off, z + nz * off) ||
				wet_at(g, Hp, WL, x - nx * off, z - nz * off);
	}
	std::vector<double> pr = grade(window_mean(v, 4), WALL_SLOPE * 0.25);
	w.pad.resize(n);
	w.solid.assign(n, 1);
	for (int k = 0; k < n; k++) {
		w.pad[k] = float(pr[k]);
		for (int q = std::max(0, k - 2); q <= std::min(n - 1, k + 2); q++) {
			if (wet[q]) {
				w.solid[k] = 0;
			}
		}
	}
}

void pad_rect(const std::vector<Wall> &walls, const Grid &g, const Rect &r, const float *Hp, const float *WL,
		float *H2, uint8_t *FM, uint8_t *WM) {
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	std::vector<std::vector<int>> segs(walls.size());
	for (size_t i = 0; i < walls.size(); i++) {
		if (!walls[i].pad.empty() && !walls[i].rect.inter(r).empty()) {
			segments_near(walls[i].l, walls[i].thick * 0.5 + WALL_APRON, bx0, bz0, bx1, bz1, segs[i]);
		}
	}
	std::vector<std::vector<int>> cand(walls.size());
	std::vector<double> tmp;
	for_blocks(g, r, [&](const Rect &blk, double cx, double cz, double bh) {
	for (size_t wi = 0; wi < walls.size(); wi++) {
		block_candidates(walls[wi].l, segs[wi], cx, cz, bh, walls[wi].thick * 0.5 + WALL_APRON, cand[wi], tmp);
	}
	for (int j = blk.y0; j < blk.y1; j++) {
		for (int i = blk.x0; i < blk.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			double h = Hp[o];
			bool wet = WL[o] > Hp[o];
			uint8_t foot = 0;
			for (size_t wi = 0; wi < walls.size(); wi++) {
				if (cand[wi].empty() || wet) {
					continue;
				}
				const Wall &w = walls[wi];
				double d, t = 0.0;
				int k = nearest_seg(w.l, cand[wi], g.wx(i), g.wz(j), d, t);
				double half = w.thick * 0.5;
				if (k < 0 || d >= half + WALL_APRON) {
					continue;
				}
				int q = t < 0.5 ? k : k + 1;
				if (!w.solid[q]) {
					continue;
				}
				double pad = w.pad[k] + (double(w.pad[k + 1]) - w.pad[k]) * t;
				double b = smoothstep(half + 0.15, half + WALL_APRON, d);
				h = pad * (1.0 - b) + h * b;
				if (d < half + 0.1) {
					foot = 255;
				}
			}
			float out = float(h);
			H2[o] = out;
			FM[o] = foot;
			WM[o] = WL[o] > out ? 255 : 0;
		}
	}
	});
}

static bool wall_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return line_bounds(p, 2, p.d.size() > 1 ? p.d[1] + PAD_REACH_M : PAD_REACH_M, x0, z0, x1, z1);
}

TERRA_KIND(7, "wall", STAGE_PADS, 2, 2, wall_bounds, nullptr);

} // namespace terra
