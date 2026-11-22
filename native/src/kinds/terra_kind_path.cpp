// The path (built-in kind 6; utils/terraform/kinds/path/): [width, x0, z0, ...], a line kind of the
// paths stage. Its line is benched against the carved ground, graded to a maximum slope, with
// stairs where a bench would cut or fill too far and a ford where it meets water (from spike
// terraform-s2-cpu).
#include "terra_kinds.h"
#include "terra_stages.h"

namespace terra {

constexpr double PATH_SLOPE = 0.18;
constexpr double PATH_SHOULDER = 1.2;
constexpr double PATH_STAIR_AT = 0.3;
constexpr double PATH_STAIR_BLEND = 0.3;
constexpr double PATH_RISE = 0.45;
constexpr double PATH_RISER = 0.45;

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

static bool path_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return line_bounds(p, 1, p.d[0] * 0.5 + PATH_REACH_M, x0, z0, x1, z1);
}

TERRA_KIND(6, "path", STAGE_PATHS, 1, 2, path_bounds, nullptr);

} // namespace terra
