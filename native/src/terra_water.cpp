// Stages 2 and 3, water (spike terraform-s2-cpu): the solve (pond levels from their rims, river
// levels as flat reaches downstream, steps of a fall's height as fall records, a join at the
// receiving body's level) and the carve (one composed bed: every body's cut, the lowest wins, and a
// bank fill so a level is always held; the controlling body's level is the water surface, one
// level per reach).
#include <algorithm>
#include <cmath>
#include <set>
#include <utility>
#include <vector>

#include "terra_kinds.h"
#include "terra_stages.h"

namespace terra {

static double pond_sd(const Pond &p, double x, double z) {
	int n = int(p.ox.size());
	double best = 1e30;
	bool inside = false;
	for (int a = 0, b = n - 1; a < n; b = a++) {
		double ax = p.ox[b], az = p.oz[b], bx = p.ox[a], bz = p.oz[a];
		double dx = bx - ax, dz = bz - az, len2 = dx * dx + dz * dz;
		double t = len2 > 0.0 ? std::clamp(((x - ax) * dx + (z - az) * dz) / len2, 0.0, 1.0) : 0.0;
		double qx = ax + dx * t - x, qz = az + dz * t - z;
		best = std::min(best, qx * qx + qz * qz);
		if ((az > z) != (bz > z) && x < ax + (z - az) * dx / dz) {
			inside = !inside;
		}
	}
	double d = std::sqrt(best);
	return inside ? -d : d;
}

static void pond_box(const Pond &p, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	for (size_t k = 0; k < p.ox.size(); k++) {
		x0 = std::min(x0, p.ox[k]);
		x1 = std::max(x1, p.ox[k]);
		z0 = std::min(z0, p.oz[k]);
		z1 = std::max(z1, p.oz[k]);
	}
}

void water_geometry(Water &w, const std::vector<const Prim *> &rivers, const std::vector<const Prim *> &ponds,
		const Grid &g) {
	w.ponds.clear();
	w.rivers.clear();
	for (const Prim *pr : ponds) {
		if (pr->d.size() < 7) {
			continue;
		}
		Pond p;
		p.id = pr->id;
		p.depth = pr->d[0];
		// The outline rounded as a closed loop (Chaikin, 3 passes), so no corner shows in the basin.
		std::vector<float> loop(pr->d.begin() + 1, pr->d.end());
		for (int it = 0; it < 3; it++) {
			int n = int(loop.size() / 2);
			std::vector<float> next;
			for (int k = 0; k < n; k++) {
				int q = (k + 1) % n;
				next.push_back(0.75f * loop[2 * k] + 0.25f * loop[2 * q]);
				next.push_back(0.75f * loop[2 * k + 1] + 0.25f * loop[2 * q + 1]);
				next.push_back(0.25f * loop[2 * k] + 0.75f * loop[2 * q]);
				next.push_back(0.25f * loop[2 * k + 1] + 0.75f * loop[2 * q + 1]);
			}
			loop.swap(next);
		}
		std::vector<float> closed(loop);
		closed.push_back(loop[0]);
		closed.push_back(loop[1]);
		Line o = resample(closed.data(), int(closed.size() / 2), 0.5);
		p.ox.assign(o.x.begin(), o.x.end() - 1);
		p.oz.assign(o.z.begin(), o.z.end() - 1);
		double x0, z0, x1, z1;
		pond_box(p, x0, z0, x1, z1);
		p.sample_rect = g.rect_world(x0, z0, x1, z1);
		p.rect = g.rect_world(x0 - POND_REACH, z0 - POND_REACH, x1 + POND_REACH, z1 + POND_REACH);
		w.ponds.push_back(p);
	}
	for (const Prim *pr : rivers) {
		if (pr->d.size() < 6) {
			continue;
		}
		River r;
		r.id = pr->id;
		r.hw = pr->d[0] * 0.5;
		r.depth = pr->d[1];
		std::vector<float> smooth = chaikin(pr->d.data() + 2, int((pr->d.size() - 2) / 2), 3);
		r.drawn = resample(smooth.data(), int(smooth.size() / 2), RIVER_DS);
		if (r.drawn.n() < 2) {
			continue;
		}
		double x0, z0, x1, z1;
		r.drawn.bounds(x0, z0, x1, z1);
		double reach = r.hw + BANK_REACH;
		r.sample_rect = g.rect_world(x0, z0, x1, z1);
		r.rect = g.rect_world(x0 - reach, z0 - reach, x1 + reach, z1 + reach);
		r.l = r.drawn;
		r.rx = r.drawn.x; // the topology and the solve read H0 at the line's points only
		r.rz = r.drawn.z;
		w.rivers.push_back(r);
	}
}

/// Flips each river drawn uphill, finds every receiver and the solve order (receivers first).
void water_topology(Water &w, const Grid &g, const float *H0) {
	for (River &r : w.rivers) {
		const Line &d = r.drawn;
		float a = g.bilinear(H0, d.x[0], d.z[0]);
		float b = g.bilinear(H0, d.x[d.n() - 1], d.z[d.n() - 1]);
		r.l = d;
		if (b > a) {
			std::reverse(r.l.x.begin(), r.l.x.end());
			std::reverse(r.l.z.begin(), r.l.z.end());
			double total = d.s.back();
			for (int k = 0; k < r.l.n(); k++) {
				r.l.s[k] = total - d.s[d.n() - 1 - k];
			}
		}
		r.recv_river = -1;
		r.recv_pond = -1;
	}
	for (int i = 0; i < int(w.rivers.size()); i++) {
		River &r = w.rivers[i];
		double ex = r.l.x.back(), ez = r.l.z.back();
		for (int p = 0; p < int(w.ponds.size()); p++) {
			if (pond_sd(w.ponds[p], ex, ez) < 0.0) {
				r.recv_pond = p;
				break;
			}
		}
		if (r.recv_pond >= 0) {
			continue;
		}
		for (int j = 0; j < int(w.rivers.size()); j++) {
			if (j == i) {
				continue;
			}
			const River &o = w.rivers[j];
			double best = 1e30, t;
			for (int k = 0; k + 1 < o.l.n(); k++) {
				best = std::min(best, seg_d2(o.l, k, ex, ez, t));
			}
			if (best < o.hw * o.hw) {
				r.recv_river = j;
				break;
			}
		}
	}
	// Order: a river after its receiver; a cycle is cut where it closes.
	int n = int(w.rivers.size());
	std::vector<int> state(n, 0);
	w.order.clear();
	for (int i = 0; i < n; i++) {
		std::vector<int> chain;
		int c = i;
		while (c >= 0 && state[c] == 0) {
			state[c] = 1;
			chain.push_back(c);
			c = w.rivers[c].recv_river;
		}
		if (c >= 0 && state[c] == 1) {
			w.rivers[chain.back()].recv_river = -1; // the cycle closes here
		}
		for (int k = int(chain.size()) - 1; k >= 0; k--) {
			state[chain[k]] = 2;
			w.order.push_back(chain[k]);
		}
	}
}

void solve_pond(Pond &p, const Grid &g, const float *H0) {
	double lo = 1e30;
	std::vector<float> closed;
	for (size_t k = 0; k < p.ox.size(); k++) {
		closed.push_back(float(p.ox[k]));
		closed.push_back(float(p.oz[k]));
	}
	closed.push_back(float(p.ox[0]));
	closed.push_back(float(p.oz[0]));
	Line o = resample(closed.data(), int(closed.size() / 2), 0.25);
	for (int k = 0; k < o.n(); k++) {
		lo = std::min(lo, double(g.bilinear(H0, o.x[k], o.z[k])));
	}
	p.level = float(lo - POND_FREEBOARD);
}

// The conditioner's comparisons, as WaterConditioner (_EPS, and dead band and fall drop each
// less it).
static constexpr double LEVEL_EPS = 1e-9;

/// The nearest lattice level at or under x (WaterConditioner._lattice).
static double level_lattice(double x) {
	return std::floor(x / LEVEL_QUANTUM_M + 1e-6) * LEVEL_QUANTUM_M;
}

/// The sections of a level profile (card terraform-p2-reaches): `cut[i]` marks a fall-sized step
/// from point i to i + 1 (a pinned fall, a sharp drop of the running minimum, the join), which
/// bounds a section; `dead[i]` is the dead band of point i's section, its mean slope (the levels'
/// drop over its arc, the bounding steps left out) times REACH_TARGET_M within the band's limits.
static void section_bands(const std::vector<double> &lv, const std::vector<double> &s, std::vector<double> &dead,
		std::vector<char> &cut) {
	const int n = int(lv.size());
	dead.assign(n, REACH_DEAD_BAND_M);
	cut.assign(n, 0);
	int a = 0;
	for (int i = 0; i < n; i++) {
		bool bound = i + 1 < n && lv[i] - lv[i + 1] >= FALL_MIN - LEVEL_EPS;
		if (!bound && i + 1 < n) {
			continue;
		}
		cut[i] = bound ? 1 : 0;
		double arc = s[i] - s[a];
		double slope = arc > 0.0 ? (lv[a] - lv[i]) / arc : 0.0;
		double band = std::clamp(slope * REACH_TARGET_M, REACH_DEAD_BAND_M, REACH_DEAD_BAND_MAX_M);
		for (int q = a; q <= i; q++) {
			dead[q] = band;
		}
		a = i + 1;
	}
}

/// The dead band swept from the outlet upstream (WaterConditioner._sweep): a level within its
/// section's dead band above the final level below it drops onto it, never across a section's
/// bound, and not so as to make a fall of the step above out of a smaller one (the band is under
/// FALL_MIN, so the sweep makes riffles only).
static void sweep_levels(std::vector<double> &lv, const std::vector<double> &dead, const std::vector<char> &cut) {
	const double fall = FALL_MIN - LEVEL_EPS;
	for (int i = int(lv.size()) - 2; i >= 0; i--) {
		double gap = lv[i] - lv[i + 1];
		if (cut[i] || gap <= LEVEL_EPS || gap >= dead[i] - LEVEL_EPS) {
			continue;
		}
		double above = i > 0 ? lv[i - 1] - lv[i] : 0.0;
		if (i > 0 && above < fall && above + gap >= fall) {
			continue;
		}
		lv[i] = lv[i + 1];
	}
}

/// Every reach shorter than MIN_REACH_M merged into the neighbour it differs from least, the
/// upper dropping onto the lower, never across a section's bound, then the dead band swept again
/// (WaterConditioner._merge_short, without cuts). A merge may make a fall out of riffles or a
/// taller fall out of two, so where the slope steepens the steps group into fewer, taller ones.
static void merge_short_reaches(std::vector<double> &lv, const std::vector<double> &len,
		const std::vector<double> &dead, const std::vector<char> &cut) {
	const int n = int(lv.size());
	std::set<int> stuck;
	for (;;) {
		std::vector<std::pair<int, int>> spans;
		int first = 0;
		for (int i = 0; i < n; i++) {
			if (i == n - 1 || lv[i + 1] != lv[i]) {
				spans.push_back({ first, i });
				first = i + 1;
			}
		}
		int pick = -1;
		double shortest = 1e300;
		for (int j = 0; j < int(spans.size()); j++) {
			double length = 0.0;
			for (int i = spans[j].first; i <= spans[j].second; i++) {
				length += len[i];
			}
			if (spans.size() > 1 && length < MIN_REACH_M && length < shortest && !stuck.count(spans[j].first)) {
				pick = j;
				shortest = length;
			}
		}
		if (pick < 0) {
			return;
		}
		int best = -1;
		double best_step = 1e300;
		for (int nb : { pick + 1, pick - 1 }) {
			if (nb < 0 || nb >= int(spans.size())) {
				continue;
			}
			double step = std::abs(lv[spans[pick].first] - lv[spans[nb].first]);
			if (cut[spans[std::min(pick, nb)].second]) {
				continue;
			}
			if (step < best_step) {
				best = nb;
				best_step = step;
			}
		}
		if (best < 0) {
			stuck.insert(spans[pick].first);
			continue;
		}
		const std::pair<int, int> &upper = spans[std::min(pick, best)];
		const double to = lv[spans[std::max(pick, best)].first];
		for (int i = upper.first; i <= upper.second; i++) {
			lv[i] = to;
		}
		sweep_levels(lv, dead, cut);
		stuck.clear();
	}
}

void solve_river(River &r, const Grid &g, const float *H0, double recv_level) {
	const Line &l = r.l;
	int n = l.n();
	std::vector<double> m(n);
	for (int k = 0; k < n; k++) {
		double t = level_lattice(g.bilinear(H0, l.x[k], l.z[k]) - RIVER_FREEBOARD);
		m[k] = k == 0 ? t : std::min(m[k - 1], t);
	}
	bool join = !std::isnan(recv_level);
	if (join) {
		for (int k = 0; k < n; k++) {
			m[k] = std::max(m[k], recv_level);
		}
	}
	r.level.assign(n, 0.0f);
	r.falls.clear();
	auto add_fall = [&](int k, double top, double bottom) {
		int a = std::max(k - 1, 0), b = std::min(k, n - 1);
		if (a == b) {
			a = std::max(b - 1, 0);
		}
		double tx = l.x[b] - l.x[a], tz = l.z[b] - l.z[a];
		double len = std::sqrt(tx * tx + tz * tz);
		len = len > 0.0 ? len : 1.0;
		Fall f;
		f.x = (l.x[a] + l.x[b]) * 0.5;
		f.z = (l.z[a] + l.z[b]) * 0.5;
		f.tx = tx / len;
		f.tz = tz / len;
		f.top = top;
		f.bottom = bottom;
		f.width = r.hw * 2.0;
		r.falls.push_back(f);
	};
	// Flat reaches (card terraform-p2-bridge, from WaterConditioner.fit_levels' rule; card
	// terraform-p2-reaches scaled it with the slope): the running minimum on the lattice (m, above),
	// the falls pinned, then per section the dead band swept from the outlet up, then short reaches
	// merged. Every step is then 0, a riffle or a fall, and water is only ever lowered, never raised
	// over its banks.
	std::vector<double> lv(m);
	if (join) {
		lv[n - 1] = recv_level;
	}
	// The falls first (FALL_RUN, FALL_GAP): a sharp drop's points take the level at its foot, so
	// the whole drop is one step, which the conditioner below never moves. A fall runs on down the
	// cliff while each further FALL_CLIFF_RUN of arc still drops at FALL_CLIFF_SLOPE or more, so a
	// riser is one tall fall at its lip, not a stair of small ones down its face.
	double last_fall_s = -1e30;
	for (int k = 1; k < n;) {
		if (lv[k] < lv[k - 1]) {
			int j = k;
			while (j + 1 < n && l.s[j + 1] - l.s[k - 1] <= FALL_RUN && lv[j + 1] < lv[j]) {
				j++;
			}
			if (lv[k - 1] - lv[j] >= FALL_MIN - LEVEL_EPS && l.s[k] - last_fall_s >= FALL_GAP) {
				for (;;) {
					int q = j;
					while (q + 1 < n && l.s[q + 1] - l.s[j] <= FALL_CLIFF_RUN) {
						q++;
					}
					if (q == j || lv[j] - lv[q] < FALL_CLIFF_SLOPE * (l.s[q] - l.s[j]) - LEVEL_EPS) {
						break;
					}
					j = q;
				}
				for (int q = k; q < j; q++) {
					lv[q] = lv[j];
				}
				last_fall_s = l.s[j];
				k = j + 1;
				continue;
			}
		}
		k++;
	}
	std::vector<double> len(n);
	for (int i = 0; i < n; i++) {
		len[i] = (l.s[std::min(i + 1, n - 1)] - l.s[std::max(i - 1, 0)]) * 0.5;
	}
	std::vector<double> dead;
	std::vector<char> cut;
	section_bands(lv, l.s, dead, cut);
	sweep_levels(lv, dead, cut);
	merge_short_reaches(lv, len, dead, cut);
	for (int i = 0; i < n; i++) {
		r.level[i] = float(lv[i]);
	}
	for (int i = 1; i < n; i++) {
		if (lv[i - 1] - lv[i] >= FALL_MIN - LEVEL_EPS) {
			add_fall(i, lv[i - 1], lv[i]);
		}
	}
}

double river_level_at(const River &r, double x, double z) {
	double best = 1e30, bt = 0.0;
	int bk = 0;
	for (int k = 0; k + 1 < r.l.n(); k++) {
		double t;
		double d2 = seg_d2(r.l, k, x, z, t);
		if (d2 < best) {
			best = d2;
			bk = k;
			bt = t;
		}
	}
	return r.level[bk] + (double(r.level[bk + 1]) - r.level[bk]) * bt;
}

/// Smooth value noise along a river's length, in [0, 1): the bank's unevenness.
static double bank_noise(int id, double s) {
	double c = s / 3.0;
	int64_t i = int64_t(std::floor(c));
	double f = c - double(i), u = f * f * (3.0 - 2.0 * f);
	double a = hash01(i * 7919 + id * 104729), b = hash01((i + 1) * 7919 + id * 104729);
	return a + (b - a) * u;
}

void carve_rect(const Water &w, const Grid &g, const Rect &r, const float *H0, float *H1, float *WL) {
	double bx0, bz0, bx1, bz1;
	rect_world_box(g, r, bx0, bz0, bx1, bz1);
	std::vector<std::vector<int>> segs(w.rivers.size());
	std::vector<int> near_rivers, near_ponds;
	for (int i = 0; i < int(w.rivers.size()); i++) {
		const River &rv = w.rivers[i];
		if (rv.level.empty() || rv.rect.inter(r).empty()) {
			continue;
		}
		segments_near(rv.l, rv.hw + BANK_REACH, bx0, bz0, bx1, bz1, segs[i]);
		if (!segs[i].empty()) {
			near_rivers.push_back(i);
		}
	}
	for (int i = 0; i < int(w.ponds.size()); i++) {
		if (!w.ponds[i].rect.inter(r).empty()) {
			near_ponds.push_back(i);
		}
	}
	// Round 2: per 8 x 8 block, only the segments that can be nearest for some sample of it (exact,
	// see block_candidates); a river out of reach of the whole block is skipped.
	std::vector<std::vector<int>> cand(w.rivers.size());
	std::vector<double> tmp;
	for_blocks(g, r, [&](const Rect &blk, double cx, double cz, double bh) {
	for (int ri : near_rivers) {
		const River &rv = w.rivers[ri];
		block_candidates(rv.l, segs[ri], cx, cz, bh, rv.hw + BANK_REACH, cand[ri], tmp);
	}
	for (int j = blk.y0; j < blk.y1; j++) {
		for (int i = blk.x0; i < blk.x1; i++) {
			int64_t o = int64_t(j) * g.w + i;
			double x = g.wx(i), z = g.wz(j);
			double h = H0[o];
			double cut = 1e30, fill = -1e30, ctrl_c = 1e30, ctrl_l = 0.0;
			bool ctrl = false, ctrl_zone = false;
			for (int ri : near_rivers) {
				const River &rv = w.rivers[ri];
				double best = 1e30, bt = 0.0;
				int bk = -1;
				for (int k : cand[ri]) {
					double t;
					double d2 = seg_d2(rv.l, k, x, z, t);
					if (d2 < best) {
						best = d2;
						bk = k;
						bt = t;
					}
				}
				double d = std::sqrt(best);
				if (bk < 0 || d > rv.hw + BANK_REACH) {
					continue;
				}
				// The bed eases across a step over its one segment; the water stands at the
				// nearer point's reach, so WL holds one level per reach (the bridge's bodies).
				double L = rv.level[bk] + (double(rv.level[bk + 1]) - rv.level[bk]) * bt;
				double Lw = bt < 0.5 ? rv.level[bk] : rv.level[bk + 1];
				double s = rv.l.s[bk] + (rv.l.s[bk + 1] - rv.l.s[bk]) * bt;
				double c, f = -1e30;
				if (d < rv.hw) {
					double u = d / rv.hw;
					c = L - rv.depth * (1.0 - u * u);
				} else {
					// Round 3: a bank that eases out of the water and steepens with distance (a
					// valley side, never a trench wall at the reach).
					double x = d - rv.hw;
					double bs = BANK_SLOPE + BANK_NOISE * bank_noise(rv.id, s);
					c = L + x * bs + x * x * BANK_CURVE;
					f = std::min(c, L + 0.08 - std::max(0.0, x - 0.25) * 0.7);
				}
				cut = std::min(cut, c);
				fill = std::max(fill, f);
				if (c < ctrl_c) {
					ctrl_c = c;
					ctrl_l = Lw;
					ctrl = true;
					ctrl_zone = d < rv.hw;
				}
			}
			for (int pi : near_ponds) {
				const Pond &p = w.ponds[pi];
				double sd = pond_sd(p, x, z);
				if (sd > POND_REACH) {
					continue;
				}
				double L = p.level, c, f = -1e30;
				if (sd < 0.0) {
					c = L - p.depth * smoothstep(0.0, 2.5, -sd);
				} else {
					c = L + (sd < 2.0 ? 0.12 * sd : 0.24 + 0.5 * (sd - 2.0));
					f = std::min(c, L + 0.06 - std::max(0.0, sd - 0.3) * 0.7);
				}
				cut = std::min(cut, c);
				fill = std::max(fill, f);
				if (c < ctrl_c) {
					ctrl_c = c;
					ctrl_l = L;
					ctrl = true;
					ctrl_zone = sd < 0.0;
				}
			}
			double hf = std::max(h, fill);
			double hh = std::min(hf, cut);
			// Round 3: where the cut meets higher ground, a smooth minimum (no crease), only up
			// the bank (k is 0 within 0.1 m of the level, so the waterline is never moved).
			if (ctrl && cut < 1e29) {
				double k = BANK_SOFT * smoothstep(0.1, 0.6, cut - ctrl_l);
				double e = std::max(k - std::abs(hf - cut), 0.0);
				hh -= k > 0.0 ? e * e / (4.0 * k) : 0.0;
			}
			float out = float(hh);
			H1[o] = out;
			if (ctrl && ((ctrl_zone && out < float(ctrl_l)) || out >= float(ctrl_l))) {
				WL[o] = float(ctrl_l);
			} else {
				WL[o] = out - 1.0f;
			}
		}
	}
	});
}

// The water kinds: one graph stage solves every body together, so they are registered here rather
// than in src/kinds/ (a new water kind is an edit of this file; terra_kinds.h).
static bool river_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return line_bounds(p, 2, p.d[0] * 0.5 + CARVE_REACH_M, x0, z0, x1, z1);
}

static bool pond_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	return line_bounds(p, 1, POND_REACH + 0.5, x0, z0, x1, z1);
}

TERRA_KIND(KIND_RIVER, "river", STAGE_WATER, 2, 2, river_bounds, nullptr);
TERRA_KIND(KIND_POND, "pond", STAGE_WATER, 1, 2, pond_bounds, nullptr);

} // namespace terra
