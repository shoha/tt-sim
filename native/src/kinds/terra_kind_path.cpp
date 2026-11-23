// The path (built-in kind 6; utils/terraform/kinds/path/): [width, surface, x0, z0, ...], a line kind
// of the paths stage. Its line is benched against the carved ground, graded to a maximum slope, with
// stairs where a bench would cut or fill too far and a ford where it meets water (from spike
// terraform-s2-cpu). Its surface (an index of TerraDoc.surfaces, 255 for none) is a coat of the
// paint stage, at the path's place in document order (path_coat; card terraform-p2-paint-path).
#include "terra_kinds.h"
#include "terra_stages.h"

namespace terra {

constexpr int PATH_HEADER = 2;
constexpr double PATH_SLOPE = 0.18;
constexpr double PATH_SHOULDER = 1.2;
constexpr double PATH_STAIR_AT = 0.3;
constexpr double PATH_STAIR_BLEND = 0.3;
constexpr double PATH_RISE = 0.45;
constexpr double PATH_RISER = 0.45;

void path_geometry(PathL &p, const Prim &prim, const Grid &g) {
	p.id = prim.id;
	p.hw = prim.d[0] * 0.5;
	line_from(prim, PATH_HEADER, 0.25, p.l, 3);
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

// Switchbacks (card terraform-p2-path-seam): where a path bends back on itself, a sample can lie in
// reach of two or more of its stretches at different grades. Each stretch is a local minimum of the
// distance from the sample along the line (the segments' distances in line order, capped at
// reach + PATH_ARM_PROM; a segment out of the block's list and both ends of the line read as the
// cap). A minimum counts by its prominence (how far the line climbs, on its lower side, before it
// comes nearer again), smoothed in over PATH_ARM_PROM, so a stretch fades in where the line's
// distance first dips rather than popping in. With one stretch in reach the nearest-stretch rule
// stands byte for byte; with more, their targets blend by distance from each tread's edge (path_bank:
// each tread stays flat, the ground between is one soft bank), held over the ground by the union of
// their shoulder influences.
constexpr double PATH_ARM_PROM = 0.5;
constexpr double PATH_BANK_FADE = 0.4;
constexpr double PATH_BANK_EPS = 1e-3;

/// A stretch in reach: its distance, its profile's height there, its prominence weight g and its
/// influence a (g times the shoulder's hold).
struct PathArm {
	double d, target, g, a;
};

/// The stretches of `p` in reach of (x, z) with a non-zero influence, from `ext` (the segments
/// within reach + PATH_ARM_PROM of the sample's block, in line order). dk and tk are scratch.
static void path_arms(const PathL &p, const std::vector<int> &ext, double x, double z, std::vector<double> &dk,
		std::vector<double> &tk, std::vector<PathArm> &arms) {
	arms.clear();
	const double reach = p.hw + PATH_SHOULDER, cap = reach + PATH_ARM_PROM;
	int n = int(ext.size());
	dk.resize(n);
	tk.resize(n);
	for (int q = 0; q < n; q++) {
		double t;
		dk[q] = std::min(std::sqrt(seg_d2(p.l, ext[q], x, z, t)), cap);
		tk[q] = t;
	}
	// The capped distance one step from q in direction s (+1 or -1): the cap past a gap or an end.
	auto next = [&](int q, int s) -> double {
		int r = q + s;
		if (r < 0 || r >= n || ext[r] != ext[q] + s) {
			return cap;
		}
		return dk[r];
	};
	for (int q = 0; q < n; q++) {
		double v = dk[q];
		if (v >= reach || next(q, -1) <= v) {
			continue;
		}
		// The plateau's far end, then whether the line climbs after it.
		int e = q;
		while (e + 1 < n && ext[e + 1] == ext[e] + 1 && dk[e + 1] == v) {
			e++;
		}
		if (next(e, 1) <= v) {
			continue;
		}
		double side[2];
		for (int s = 0; s < 2; s++) {
			int dir = s == 0 ? -1 : 1, r = s == 0 ? q : e;
			double top = v;
			while (true) {
				int m = r + dir;
				if (m < 0 || m >= n || ext[m] != ext[r] + dir) {
					top = cap;
					break;
				}
				if (dk[m] < v) {
					break;
				}
				top = std::max(top, dk[m]);
				r = m;
			}
			side[s] = top;
		}
		double g = smoothstep(0.0, PATH_ARM_PROM, std::min(side[0], side[1]) - v);
		double a = g * (1.0 - smoothstep(p.hw, reach, v));
		if (a > 0.0) {
			int k = ext[q];
			double target = p.prof[k] + (double(p.prof[k + 1]) - p.prof[k]) * tk[q];
			arms.push_back(PathArm{ v, target, g, a });
		}
	}
}

/// The height over ground h where two or more stretches of `p` are in reach: each stretch's share is
/// its inverse distance from its tread's edge (faded out over the last PATH_BANK_FADE of its reach),
/// normalised and eased by a smoothstep; each stretch's own result is its tread eased onto the ground
/// by its shoulder, and the shares blend those. Between two treads the bank runs from one tread's
/// edge to the other's, flat at both, and where the gap is wider than two shoulders the ground
/// shows between them.
static double path_bank(const PathL &p, const std::vector<PathArm> &arms, double h) {
	const double reach = p.hw + PATH_SHOULDER;
	double ws[8];
	int n = int(std::min<size_t>(arms.size(), 8));
	double sw = 0.0;
	for (int q = 0; q < n; q++) {
		const PathArm &arm = arms[q];
		double fade = arm.g * (1.0 - smoothstep(reach - PATH_BANK_FADE, reach, arm.d));
		ws[q] = fade / (std::max(arm.d - p.hw, 0.0) + PATH_BANK_EPS);
		sw += ws[q];
	}
	double se = 0.0, sh = 0.0;
	for (int q = 0; q < n; q++) {
		double f = smoothstep(0.0, 1.0, ws[q] / sw);
		double b = smoothstep(p.hw, reach, arms[q].d);
		se += f;
		sh += f * (arms[q].target * (1.0 - b) + h * b);
	}
	return sh / se;
}

void path_rect(const std::vector<PathL> &paths, const Grid &g, const Rect &r, const float *H1, const float *WL,
		float *Hp, uint8_t *PM) {
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	std::vector<std::vector<int>> segs(paths.size()), wide(paths.size());
	for (size_t i = 0; i < paths.size(); i++) {
		if (!paths[i].prof.empty() && !paths[i].rect.inter(r).empty()) {
			segments_near(paths[i].l, paths[i].hw + PATH_SHOULDER, bx0, bz0, bx1, bz1, segs[i]);
			segments_near(paths[i].l, paths[i].hw + PATH_SHOULDER + PATH_ARM_PROM, bx0, bz0, bx1, bz1, wide[i]);
		}
	}
	std::vector<std::vector<int>> cand(paths.size()), ext(paths.size());
	std::vector<double> tmp, dk, tk;
	std::vector<PathArm> arms;
	for_blocks(g, r, [&](const Rect &blk, double cx, double cz, double bh) {
	for (size_t pi = 0; pi < paths.size(); pi++) {
		const PathL &p = paths[pi];
		block_candidates(p.l, segs[pi], cx, cz, bh, p.hw + PATH_SHOULDER, cand[pi], tmp);
		ext[pi].clear();
		if (cand[pi].empty()) {
			continue;
		}
		double lim = p.hw + PATH_SHOULDER + PATH_ARM_PROM + bh + 1e-6;
		for (int k : wide[pi]) {
			double t;
			if (seg_d2(p.l, k, cx, cz, t) <= lim * lim) {
				ext[pi].push_back(k);
			}
		}
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
				if (!wet) {
					path_arms(p, ext[pi], g.wx(i), g.wz(j), dk, tk, arms);
					if (arms.size() <= 1) {
						double target = p.prof[k] + (double(p.prof[k + 1]) - p.prof[k]) * t;
						double b = smoothstep(p.hw, p.hw + PATH_SHOULDER, d);
						h = target * (1.0 - b) + h * b;
					} else {
						h = path_bank(p, arms, h);
					}
				}
				cov = std::max(cov, 1.0 - smoothstep(p.hw - 0.15, p.hw + 0.15, d));
			}
			Hp[o] = float(h);
			PM[o] = unit_u8(cov);
		}
	}
	});
}

void path_coat(const PathL &p, int surface, const Grid &g, const Rect &r, uint8_t *PI, uint8_t *PW) {
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	const double reach = p.hw + 0.15;
	std::vector<int> segs, cand;
	std::vector<double> tmp;
	segments_near(p.l, reach, bx0, bz0, bx1, bz1, segs);
	if (segs.empty()) {
		return;
	}
	for_blocks(g, r, [&](const Rect &blk, double cx, double cz, double bh) {
		block_candidates(p.l, segs, cx, cz, bh, reach, cand, tmp);
		if (cand.empty()) {
			return;
		}
		for (int j = blk.y0; j < blk.y1; j++) {
			for (int i = blk.x0; i < blk.x1; i++) {
				double d, t = 0.0;
				if (nearest_seg(p.l, cand, g.wx(i), g.wz(j), d, t) < 0 || d >= reach) {
					continue;
				}
				double cov = 1.0 - smoothstep(p.hw - 0.15, p.hw + 0.15, d);
				if (cov <= 0.0) {
					continue;
				}
				int64_t o = (int64_t(j) * g.w + i) * 4;
				int own = 0;
				for (int e = 0; e < 4; e++) {
					if (PW[o + e] != 0 && PI[o + e] == surface) {
						own = PW[o + e];
					}
				}
				double v = own / 255.0;
				coat_entries(PI + o, PW + o, surface, false, v + (1.0 - v) * cov);
			}
		}
	});
}

static bool path_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return line_bounds(p, PATH_HEADER, p.d[0] * 0.5 + PATH_REACH_M, x0, z0, x1, z1);
}

TERRA_KIND(6, "path", STAGE_PATHS, PATH_HEADER, 2, path_bounds, nullptr);

} // namespace terra
