// Stages 3b and 4 (spike terraform-s2-cpu): paths benched against the carved ground (graded to a
// maximum slope, stairs where a bench would cut or fill too far, a ford where they meet water),
// wall pads (a wall leaves an opening where solved water crosses it: the cut-through rule is the
// stage order), and the paint coats the rule table reads.
#include "terra_stages.h"

namespace terra {

constexpr double PATH_SLOPE = 0.18;
constexpr double PATH_SHOULDER = 1.2;
constexpr double PATH_STAIR_AT = 0.3;
constexpr double PATH_STAIR_BLEND = 0.3;
constexpr double PATH_RISE = 0.45;
constexpr double PATH_RISER = 0.45;
constexpr double WALL_SLOPE = 0.35;
constexpr double WALL_APRON = 1.2;

static void line_from(const Prim &prim, int skip, double ds, Line &out, int rounding = 0) {
	int count = int((prim.d.size() - skip) / 2);
	std::vector<float> pts = chaikin(prim.d.data() + skip, count, rounding);
	out = resample(pts.data(), int(pts.size() / 2), ds);
}

/// The window mean of v over +-half samples (fixed order, clamped at the ends).
static std::vector<double> window_mean(const std::vector<double> &v, int half) {
	int n = int(v.size());
	std::vector<double> out(n);
	for (int k = 0; k < n; k++) {
		int a = std::max(0, k - half), b = std::min(n - 1, k + half);
		double s = 0.0;
		for (int q = a; q <= b; q++) {
			s += v[q];
		}
		out[k] = s / double(b - a + 1);
	}
	return out;
}

/// The mean of the largest and smallest m-Lipschitz profiles under and over v: graded to m.
static std::vector<double> grade(const std::vector<double> &v, double m) {
	int n = int(v.size());
	std::vector<double> up(v), lo(v), out(n);
	for (int k = 1; k < n; k++) {
		up[k] = std::min(up[k], up[k - 1] + m);
		lo[k] = std::max(lo[k], lo[k - 1] - m);
	}
	for (int k = n - 2; k >= 0; k--) {
		up[k] = std::min(up[k], up[k + 1] + m);
		lo[k] = std::max(lo[k], lo[k + 1] - m);
	}
	for (int k = 0; k < n; k++) {
		out[k] = (up[k] + lo[k]) * 0.5;
	}
	return out;
}

static int nearest_seg(const Line &l, const std::vector<int> &segs, double x, double z, double &d, double &t) {
	double best = 1e30;
	int bk = -1;
	for (int k : segs) {
		double tt;
		double d2 = seg_d2(l, k, x, z, tt);
		if (d2 < best) {
			best = d2;
			bk = k;
			t = tt;
		}
	}
	d = std::sqrt(best);
	return bk;
}

void path_geometry(PathL &p, const Prim &prim, const Grid &g) {
	p.id = prim.id;
	p.hw = prim.d[0] * 0.5;
	line_from(prim, 1, 0.25, p.l, 3);
	double x0, z0, x1, z1;
	p.l.bounds(x0, z0, x1, z1);
	double reach = p.hw + PATH_SHOULDER;
	p.sample_rect = g.rect_world(x0, z0, x1, z1);
	p.rect = g.rect_world(x0 - reach, z0 - reach, x1 + reach, z1 + reach);
	p.rx = p.l.x;
	p.rz = p.l.z;
}

void solve_path(PathL &p, const Grid &g, const float *H1) {
	int n = p.l.n();
	std::vector<double> v(n);
	for (int k = 0; k < n; k++) {
		v[k] = g.bilinear(H1, p.l.x[k], p.l.z[k]);
	}
	std::vector<double> gs = window_mean(v, 8);
	std::vector<double> pr = grade(gs, PATH_SLOPE * 0.25);
	p.prof.resize(n);
	// Round 3: where the graded bench would cut or fill past PATH_STAIR_AT the path steps, as a few
	// soft ledges (PATH_RISE tall, the riser the upper PATH_RISER share of each), blended in over
	// PATH_STAIR_BLEND so a stair starts without a seam.
	for (int k = 0; k < n; k++) {
		double t = gs[k] / PATH_RISE, fl = std::floor(t);
		double ledges = PATH_RISE * (fl + smoothstep(1.0 - PATH_RISER, 1.0, t - fl));
		double w = smoothstep(PATH_STAIR_AT, PATH_STAIR_AT + PATH_STAIR_BLEND, std::abs(pr[k] - gs[k]));
		p.prof[k] = float(pr[k] + (ledges - pr[k]) * w);
	}
}

void path_rect(const std::vector<PathL> &paths, const Grid &g, const Rect &r, const float *H1, const float *WL,
		float *Hp, uint8_t *PM) {
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	std::vector<std::vector<int>> segs(paths.size());
	for (size_t i = 0; i < paths.size(); i++) {
		if (!paths[i].prof.empty() && !paths[i].rect.inter(r).empty()) {
			segments_near(paths[i].l, paths[i].hw + PATH_SHOULDER, bx0, bz0, bx1, bz1, segs[i]);
		}
	}
	std::vector<std::vector<int>> cand(paths.size());
	std::vector<double> tmp;
	for_blocks(g, r, [&](const Rect &blk, double cx, double cz, double bh) {
	for (size_t pi = 0; pi < paths.size(); pi++) {
		block_candidates(paths[pi].l, segs[pi], cx, cz, bh, paths[pi].hw + PATH_SHOULDER, cand[pi], tmp);
	}
	for (int j = blk.y0; j < blk.y1; j++) {
		for (int i = blk.x0; i < blk.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			double h = H1[o];
			bool wet = WL[o] > H1[o];
			double cov = 0.0;
			for (size_t pi = 0; pi < paths.size(); pi++) {
				if (cand[pi].empty()) {
					continue;
				}
				const PathL &p = paths[pi];
				double d, t = 0.0;
				int k = nearest_seg(p.l, cand[pi], g.wx(i), g.wz(j), d, t);
				if (k < 0 || d >= p.hw + PATH_SHOULDER) {
					continue;
				}
				double target = p.prof[k] + (double(p.prof[k + 1]) - p.prof[k]) * t;
				if (!wet) {
					double b = smoothstep(p.hw, p.hw + PATH_SHOULDER, d);
					h = target * (1.0 - b) + h * b;
				}
				cov = std::max(cov, 1.0 - smoothstep(p.hw - 0.15, p.hw + 0.15, d));
			}
			Hp[o] = float(h);
			PM[o] = unit_u8(cov);
		}
	}
	});
}

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

void paint_rect(const std::vector<const Prim *> &paints, const Grid &g, const Rect &r, uint8_t *PI, float *PW) {
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			PI[o] = 0;
			PW[o] = 0.0f;
		}
	}
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	for (const Prim *p : paints) {
		for (size_t k = 0; k + 4 <= p->d.size(); k += 4) {
			double cx = p->d[k], cz = p->d[k + 1], rad = p->d[k + 2];
			int id = int(p->d[k + 3]);
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
}

} // namespace terra
