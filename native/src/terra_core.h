// TerraDerive's shared core (from spike terraform-s2-cpu; production since card
// terraform-p1-native, 2026-11-22; docs/systems/terraform.md): the grid, sample rects, the per-tile
// dirty set, the primitive record and the polyline helpers every stage uses.
//
// The model: the map document is a list of typed primitives; every derived array is a pure
// function of that list, computed by a fixed chain of stages. Each stage is a per-sample function
// with a declared halo, so evaluating it over any rect gives the same bits as evaluating it over the
// whole map. That is what makes "update equals build" hold for dirty tiles. Every transcendental
// goes through terra_math.h, so the bits are also the same on every platform.
#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

#include "terra_math.h"

namespace terra {

constexpr int TILE = 64;
constexpr double PI = 3.14159265358979323846;

/// A half-open rect of samples, [x0, x1) x [y0, y1).
struct Rect {
	int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
	bool empty() const { return x1 <= x0 || y1 <= y0; }
	Rect grow(int n) const { return { x0 - n, y0 - n, x1 + n, y1 + n }; }
	Rect clip(int w, int h) const { return { std::max(x0, 0), std::max(y0, 0), std::min(x1, w), std::min(y1, h) }; }
	Rect inter(const Rect &o) const {
		return { std::max(x0, o.x0), std::max(y0, o.y0), std::min(x1, o.x1), std::min(y1, o.y1) };
	}
	Rect unite(const Rect &o) const {
		if (empty()) {
			return o;
		}
		if (o.empty()) {
			return *this;
		}
		return { std::min(x0, o.x0), std::min(y0, o.y0), std::max(x1, o.x1), std::max(y1, o.y1) };
	}
	int64_t area() const { return empty() ? 0 : int64_t(x1 - x0) * int64_t(y1 - y0); }
};

/// The sample grid, in the map document's frame (corner-aligned and centred): the map spans
/// [-ex / 2, ex / 2] x [-ez / 2, ez / 2] metres and sample (i, j) sits at world (x, z) =
/// (ox + i sx, oz + j sz), so sample (0, 0) is the (-ex / 2, -ez / 2) corner and (w - 1, h - 1)
/// the opposite one. The steps are ex / (w - 1) and ez / (h - 1), so an axis may differ from the
/// other by the document's rounding. TerraCore sizes it at 2 (n - 1) + 1 samples per axis of the
/// document's n: every second derive sample is a document sample. Halos are in samples,
/// constants in metres.
struct Grid {
	int w = 0, h = 0;
	double sx = 0.125, sz = 0.125;
	double ox = 0.0, oz = 0.0;
	int tx = 0, ty = 0;

	void init(int p_w, int p_h, double p_ex, double p_ez) {
		w = std::max(p_w, 2);
		h = std::max(p_h, 2);
		sx = p_ex / double(w - 1);
		sz = p_ez / double(h - 1);
		ox = -0.5 * p_ex;
		oz = -0.5 * p_ez;
		tx = (w + TILE - 1) / TILE;
		ty = (h + TILE - 1) / TILE;
	}
	int ntiles() const { return tx * ty; }
	Rect tile_rect(int t) const {
		int ix = t % tx, iy = t / tx;
		return Rect{ ix * TILE, iy * TILE, ix * TILE + TILE, iy * TILE + TILE }.clip(w, h);
	}
	Rect all() const { return { 0, 0, w, h }; }
	double wx(int i) const { return ox + double(i) * sx; }
	double wz(int j) const { return oz + double(j) * sz; }
	/// A world x or z as a continuous sample coordinate (not clamped).
	double fx(double x) const { return (x - ox) / sx; }
	double fz(double z) const { return (z - oz) / sz; }
	/// The smaller step: the metres a sample halo is at least.
	double step_min() const { return std::min(sx, sz); }
	/// The samples whose positions fall inside a world box, one sample of margin, clipped.
	Rect rect_world(double minx, double minz, double maxx, double maxz) const {
		Rect r{ int(std::floor(fx(minx))) - 1, int(std::floor(fz(minz))) - 1, int(std::floor(fx(maxx))) + 2,
			int(std::floor(fz(maxz))) + 2 };
		return r.clip(w, h);
	}
	/// Bilinear read of a whole-map array at a world point (clamped to the grid).
	float bilinear(const float *a, double x, double z) const {
		double cx = std::clamp(fx(x), 0.0, double(w - 1));
		double cz = std::clamp(fz(z), 0.0, double(h - 1));
		int i0 = std::min(int(cx), w - 2 < 0 ? 0 : w - 2);
		int j0 = std::min(int(cz), h - 2 < 0 ? 0 : h - 2);
		double u = cx - i0, v = cz - j0;
		const float *r0 = a + int64_t(j0) * w + i0;
		const float *r1 = r0 + w;
		double top = r0[0] + (r0[1] - double(r0[0])) * u;
		double bot = r1[0] + (r1[1] - double(r1[0])) * u;
		return float(top + (bot - top) * v);
	}
	/// The rect of samples a bilinear read at (x, z) touches.
	Rect bilinear_rect(double x, double z) const {
		double cx = std::clamp(fx(x), 0.0, double(w - 1));
		double cz = std::clamp(fz(z), 0.0, double(h - 1));
		int i0 = std::min(int(cx), std::max(w - 2, 0));
		int j0 = std::min(int(cz), std::max(h - 2, 0));
		return { i0, j0, i0 + 2, j0 + 2 };
	}
};

/// Which samples of each tile a stage must (re)compute or which changed: one sub-rect per tile.
struct Dirty {
	std::vector<Rect> t;

	void init(const Grid &g) { t.assign(g.ntiles(), Rect{}); }
	void clear() { std::fill(t.begin(), t.end(), Rect{}); }
	void add(const Rect &r, const Grid &g) {
		Rect c = r.clip(g.w, g.h);
		if (c.empty()) {
			return;
		}
		int tx0 = c.x0 / TILE, tx1 = (c.x1 - 1) / TILE, ty0 = c.y0 / TILE, ty1 = (c.y1 - 1) / TILE;
		for (int y = ty0; y <= ty1; y++) {
			for (int x = tx0; x <= tx1; x++) {
				int ti = y * g.tx + x;
				t[ti] = t[ti].unite(c.inter(g.tile_rect(ti)));
			}
		}
	}
	void merge(const Dirty &o, const Grid &g) {
		for (const Rect &r : o.t) {
			add(r, g);
		}
	}
	Dirty dilate(int n, const Grid &g) const {
		Dirty d;
		d.init(g);
		for (const Rect &r : t) {
			if (!r.empty()) {
				d.add(r.grow(n), g);
			}
		}
		return d;
	}
	bool any() const {
		for (const Rect &r : t) {
			if (!r.empty()) {
				return true;
			}
		}
		return false;
	}
	bool hits(const Rect &q) const {
		for (const Rect &r : t) {
			if (!r.empty() && !r.inter(q).empty()) {
				return true;
			}
		}
		return false;
	}
	std::vector<int> tiles() const {
		std::vector<int> out;
		for (int i = 0; i < int(t.size()); i++) {
			if (!t[i].empty()) {
				out.push_back(i);
			}
		}
		return out;
	}
	int64_t samples() const {
		int64_t n = 0;
		for (const Rect &r : t) {
			n += r.area();
		}
		return n;
	}
};

/// One primitive of the document, as sent from GDScript: an id, a type (a kind id of the registry,
/// terra_kinds.h; each kind's file documents its float layout) and its floats.
struct Prim {
	int id = 0;
	int type = 0;
	std::vector<float> d;
};

inline double smoothstep(double e0, double e1, double x) {
	double t = std::clamp((x - e0) / (e1 - e0), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

/// Deterministic hash noise in [0, 1) of an integer.
inline double hash01(int64_t n) {
	uint64_t x = uint64_t(n) * 0x9E3779B97F4A7C15ull;
	x ^= x >> 31;
	x *= 0xBF58476D1CE4E5B9ull;
	x ^= x >> 27;
	return double(x >> 11) * (1.0 / 9007199254740992.0);
}

/// A polyline resampled at a fixed arc spacing: points, their arc length, and per-segment bounds.
struct Line {
	std::vector<double> x, z, s;
	int n() const { return int(x.size()); }
	void bounds(double &x0, double &z0, double &x1, double &z1) const {
		x0 = z0 = 1e30;
		x1 = z1 = -1e30;
		for (int i = 0; i < n(); i++) {
			x0 = std::min(x0, x[i]);
			x1 = std::max(x1, x[i]);
			z0 = std::min(z0, z[i]);
			z1 = std::max(z1, z[i]);
		}
	}
};

/// Resamples the points pts[2k], pts[2k + 1] (count pairs) at spacing ds, keeping both ends.
inline Line resample(const float *pts, int count, double ds) {
	Line out;
	if (count < 1) {
		return out;
	}
	out.x.push_back(pts[0]);
	out.z.push_back(pts[1]);
	out.s.push_back(0.0);
	double carry = 0.0, total = 0.0;
	for (int k = 1; k < count; k++) {
		double ax = pts[2 * k - 2], az = pts[2 * k - 1], bx = pts[2 * k], bz = pts[2 * k + 1];
		double len = std::sqrt((bx - ax) * (bx - ax) + (bz - az) * (bz - az));
		if (len <= 1e-9) {
			continue;
		}
		double t = ds - carry;
		while (t <= len) {
			double f = t / len;
			out.x.push_back(ax + (bx - ax) * f);
			out.z.push_back(az + (bz - az) * f);
			out.s.push_back(total + t);
			t += ds;
		}
		carry = len - (t - ds);
		total += len;
	}
	if (out.s.back() < total - 1e-6) {
		out.x.push_back(pts[2 * count - 2]);
		out.z.push_back(pts[2 * count - 1]);
		out.s.push_back(total);
	}
	return out;
}

/// The author's points rounded by Chaikin corner cutting (`iters` passes, ends kept): the line's
/// conditioning. Each pass moves a point by at most a quarter of its segments, so it stays the
/// author's stroke.
inline std::vector<float> chaikin(const float *pts, int count, int iters) {
	std::vector<float> a(pts, pts + count * 2);
	for (int it = 0; it < iters && a.size() >= 6; it++) {
		int n = int(a.size() / 2);
		std::vector<float> b{ a[0], a[1] };
		for (int k = 0; k + 1 < n; k++) {
			float ax = a[2 * k], az = a[2 * k + 1], bx = a[2 * k + 2], bz = a[2 * k + 3];
			if (k > 0) {
				b.push_back(0.75f * ax + 0.25f * bx);
				b.push_back(0.75f * az + 0.25f * bz);
			}
			if (k + 2 < n) {
				b.push_back(0.25f * ax + 0.75f * bx);
				b.push_back(0.25f * az + 0.75f * bz);
			}
		}
		b.push_back(a[2 * n - 2]);
		b.push_back(a[2 * n - 1]);
		a.swap(b);
	}
	return a;
}

/// Nearest point on segment k of the line to (px, pz): squared distance and the parameter t.
inline double seg_d2(const Line &l, int k, double px, double pz, double &t) {
	double ax = l.x[k], az = l.z[k], bx = l.x[k + 1], bz = l.z[k + 1];
	double dx = bx - ax, dz = bz - az;
	double len2 = dx * dx + dz * dz;
	t = len2 > 0.0 ? std::clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0.0, 1.0) : 0.0;
	double qx = ax + dx * t - px, qz = az + dz * t - pz;
	return qx * qx + qz * qz;
}

/// The segments of a line whose bounds grown by `reach` meet a world box, in order.
inline void segments_near(const Line &l, double reach, double x0, double z0, double x1, double z1,
		std::vector<int> &out) {
	out.clear();
	for (int k = 0; k + 1 < l.n(); k++) {
		double sx0 = std::min(l.x[k], l.x[k + 1]) - reach, sx1 = std::max(l.x[k], l.x[k + 1]) + reach;
		double sz0 = std::min(l.z[k], l.z[k + 1]) - reach, sz1 = std::max(l.z[k], l.z[k + 1]) + reach;
		if (sx1 >= x0 && sx0 <= x1 && sz1 >= z0 && sz0 <= z1) {
			out.push_back(k);
		}
	}
}

/// A unit value in [0, 1] as a byte, rounded half up (round 2: std::lround is a library call
/// under llvm-mingw and cost 87 us per fields layer).
inline uint8_t unit_u8(double v) {
	return uint8_t(std::clamp(v, 0.0, 1.0) * 255.0 + 0.5);
}

/// Exact pruning of a nearest-segment search for a block of samples (round 2): of `in`, keeps in
/// order the segments that can be the nearest for some point within `h` of (cx, cz). By the
/// triangle inequality a segment farther than dc + 2h from the centre (dc: the nearest one's
/// distance) is strictly farther than the nearest for every point of the block, so the argmin,
/// its tie-break and its value are those of the full search. `out` is empty when every point of
/// the block is farther than `reach` from all of `in` (dc - h > reach).
inline void block_candidates(const Line &l, const std::vector<int> &in, double cx, double cz, double h, double reach,
		std::vector<int> &out, std::vector<double> &tmp) {
	out.clear();
	if (in.empty()) {
		return;
	}
	tmp.resize(in.size());
	double dc = 1e30;
	for (size_t q = 0; q < in.size(); q++) {
		double t;
		tmp[q] = std::sqrt(seg_d2(l, in[q], cx, cz, t));
		dc = std::min(dc, tmp[q]);
	}
	constexpr double EPS = 1e-6;
	if (dc - h > reach + EPS) {
		return;
	}
	double lim = dc + 2.0 * h + EPS;
	for (size_t q = 0; q < in.size(); q++) {
		if (tmp[q] <= lim) {
			out.push_back(in[q]);
		}
	}
}

/// The 8 x 8 sample blocks of a rect, each with its world centre and the distance from that
/// centre to its farthest sample: fn(block, cx, cz, h).
constexpr int BLOCK = 8;
template <typename F>
inline void for_blocks(const Grid &g, const Rect &r, F &&fn) {
	for (int by = r.y0; by < r.y1; by += BLOCK) {
		for (int bx = r.x0; bx < r.x1; bx += BLOCK) {
			Rect b{ bx, by, std::min(bx + BLOCK, r.x1), std::min(by + BLOCK, r.y1) };
			double ax = g.wx(b.x0), az = g.wz(b.y0), ex = g.wx(b.x1 - 1), ez = g.wz(b.y1 - 1);
			double hx = (ex - ax) * 0.5, hz = (ez - az) * 0.5;
			fn(b, (ax + ex) * 0.5, (az + ez) * 0.5, std::sqrt(hx * hx + hz * hz) + 1e-9);
		}
	}
}

/// Whether any bilinear read at the points (xs[k], zs[k]) touches a sample the dirty set marks:
/// the exact hit test of a 1D solve against what changed (round 2; bboxes were too coarse).
inline bool reads_hit(const Dirty &d, const Grid &g, const std::vector<double> &xs, const std::vector<double> &zs) {
	for (size_t k = 0; k < xs.size(); k++) {
		Rect q = g.bilinear_rect(xs[k], zs[k]);
		for (int y = q.y0 / TILE; y <= (q.y1 - 1) / TILE; y++) {
			for (int x = q.x0 / TILE; x <= (q.x1 - 1) / TILE; x++) {
				const Rect &c = d.t[y * g.tx + x];
				if (!c.empty() && !c.inter(q).empty()) {
					return true;
				}
			}
		}
	}
	return false;
}

/// The world box of a sample rect.
inline void rect_world_box(const Grid &g, const Rect &r, double &x0, double &z0, double &x1, double &z1) {
	x0 = g.wx(r.x0);
	z0 = g.wz(r.y0);
	x1 = g.wx(r.x1 - 1);
	z1 = g.wz(r.y1 - 1);
}

} // namespace terra
