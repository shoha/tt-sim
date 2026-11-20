// WaterField's hot passes: see water_field.h. The comments name the GDScript's functions.
#include "water_field.h"

#include <cmath>
#include <cstdint>
#include <vector>

#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using namespace godot;

namespace ttscatter {

namespace {

constexpr float DRY = -INFINITY;
constexpr double FAR_SQ = 1e20; // DistanceField.FAR

// WaterField._NEIGHBOURS, in its order.
constexpr int NX[8] = { -1, 0, 1, -1, 1, -1, 0, 1 };
constexpr int NZ[8] = { -1, -1, -1, 0, 0, 1, 1, 1 };

inline double minf(double a, double b) {
	return a < b ? a : b;
}

inline double maxf(double a, double b) {
	return a > b ? a : b;
}

inline double clampd(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

inline bool in_rect(const Rect2i &r, int x, int z) {
	return x >= r.position.x && z >= r.position.y && x < r.position.x + r.size.x && z < r.position.y + r.size.y;
}

// WaterField._clip.
inline Rect2i clip_to(const Rect2i &r, int w, int h) {
	return r.intersection(Rect2i(0, 0, w, h));
}

// A call's arguments by name.
struct Args {
	const Dictionary &d;
	Variant operator[](const char *key) const {
		return d[String(key)];
	}
};

} // namespace

// ---------------------------------------------------------------------------------------------
// _spill_pass
// ---------------------------------------------------------------------------------------------

Dictionary water_spill(const Dictionary &args) {
	const Args a{ args };
	const Vector2i size = a["size"];
	const Rect2i rect = a["rect"];
	const PackedFloat32Array raw_a = a["raw"];
	const PackedByteArray spill_a = a["spill"];
	const PackedByteArray was_a = a["was"];
	const PackedFloat32Array ground_a = a["ground"];
	PackedFloat32Array base_a = a["base"];
	const double step_x = a["step_x"];
	const double step_y = a["step_y"];
	const double diag = a["diag"];
	const double inflow = a["inflow_slope"];
	const double bank_slope = a["bank_slope"];
	const int bank_flag = (int)(int64_t)a["spill_bank"];
	const double tuck = a["tuck"];
	const int width = size.x;
	const int height = size.y;
	const int64_t n = (int64_t)width * height;
	const float *raw = raw_a.ptr();
	const uint8_t *spill = spill_a.ptr();
	const uint8_t *was = was_a.ptr();
	const float *ground = ground_a.ptr();
	float *base = base_a.ptrw();
	for (int z = rect.position.y; z < rect.position.y + rect.size.y; z++) {
		const int64_t row = (int64_t)z * width;
		for (int64_t i = row + rect.position.x; i < row + rect.position.x + rect.size.x; i++) {
			base[i] = raw[i];
		}
	}
	std::vector<uint8_t> seen((size_t)n, 0);
	std::vector<int32_t> closure;
	const Rect2i ring = clip_to(rect.grow(1), width, height);
	for (int z = ring.position.y; z < ring.position.y + ring.size.y; z++) {
		const int64_t row = (int64_t)z * width;
		for (int64_t i = row + ring.position.x; i < row + ring.position.x + ring.size.x; i++) {
			if ((spill[i] != 0 || was[i] != 0) && seen[i] == 0) {
				seen[i] = 1;
				closure.push_back((int32_t)i);
			}
		}
	}
	int lo_x = rect.position.x, lo_z = rect.position.y;
	int hi_x = rect.position.x + rect.size.x - 1, hi_z = rect.position.y + rect.size.y - 1;
	size_t head = 0;
	while (head < closure.size()) {
		const int32_t i = closure[head++];
		const int x = i % width;
		const int z = i / width;
		lo_x = x < lo_x ? x : lo_x;
		lo_z = z < lo_z ? z : lo_z;
		hi_x = x > hi_x ? x : hi_x;
		hi_z = z > hi_z ? z : hi_z;
		for (int k = 0; k < 8; k++) {
			const int xx = x + NX[k];
			const int zz = z + NZ[k];
			if (xx < 0 || zz < 0 || xx >= width || zz >= height) {
				continue;
			}
			const int32_t j = zz * width + xx;
			if (seen[j] == 0 && (spill[j] != 0 || was[j] != 0)) {
				seen[j] = 1;
				closure.push_back(j);
			}
		}
	}
	std::vector<int32_t> queue;
	for (int32_t i : closure) {
		base[i] = raw[i];
		if (spill[i] != 0) {
			queue.push_back(i);
		}
	}
	std::vector<uint8_t> queued((size_t)n, 0);
	for (int32_t i : queue) {
		queued[i] = 1;
	}
	size_t qh = 0;
	while (qh < queue.size()) {
		const int32_t i = queue[qh++];
		queued[i] = 0;
		const int x = i % width;
		const int z = i / width;
		const double slope = spill[i] == bank_flag ? bank_slope : inflow;
		double cap = (double)base[i];
		for (int k = 0; k < 8; k++) {
			const int xx = x + NX[k];
			const int zz = z + NZ[k];
			if (xx < 0 || zz < 0 || xx >= width || zz >= height) {
				continue;
			}
			const int32_t j = zz * width + xx;
			double h = (double)base[j];
			if (base[j] == DRY) {
				h = (double)ground[j] - tuck;
			}
			const double run = (NX[k] != 0 && NZ[k] != 0) ? diag : (NX[k] != 0 ? step_x : step_y);
			cap = minf(cap, h + slope * run);
		}
		const double old = (double)base[i];
		base[i] = (float)cap;
		if ((double)base[i] < old) {
			for (int k = 0; k < 8; k++) {
				const int xx = x + NX[k];
				const int zz = z + NZ[k];
				if (xx < 0 || zz < 0 || xx >= width || zz >= height) {
					continue;
				}
				const int32_t j = zz * width + xx;
				if (spill[j] != 0 && queued[j] == 0) {
					queued[j] = 1;
					queue.push_back(j);
				}
			}
		}
	}
	Dictionary out;
	out["base"] = base_a;
	out["bounds"] = Rect2i(lo_x, lo_z, hi_x - lo_x + 1, hi_z - lo_z + 1);
	return out;
}

// ---------------------------------------------------------------------------------------------
// _derive
// ---------------------------------------------------------------------------------------------

namespace {

// WaterField._ring: `src` (over `sr`) restricted to `dr`, each dry sample there next to a wet one
// standing at the highest neighbour's surface, but under its ground by `tuck`.
void ring_of(const std::vector<float> &src, const Rect2i &sr, const Rect2i &dr, const float *ground, int width,
		double tuck, std::vector<float> &out) {
	const int sw = sr.size.x;
	const int dw = dr.size.x;
	out.assign((size_t)dw * dr.size.y, 0.0f);
	for (int z = 0; z < dr.size.y; z++) {
		const int64_t from = (int64_t)(z + dr.position.y - sr.position.y) * sw + dr.position.x - sr.position.x;
		for (int x = 0; x < dw; x++) {
			out[(size_t)z * dw + x] = src[(size_t)(from + x)];
		}
	}
	std::vector<int32_t> touched;
	for (int z = 0; z < sr.size.y; z++) {
		for (int x = 0; x < sw; x++) {
			const float v = src[(size_t)z * sw + x];
			if (v == DRY) {
				continue;
			}
			for (int k = 0; k < 8; k++) {
				const int px = x + sr.position.x + NX[k];
				const int pz = z + sr.position.y + NZ[k];
				if (!in_rect(dr, px, pz)) {
					continue;
				}
				if (src[(size_t)(pz - sr.position.y) * sw + px - sr.position.x] != DRY) {
					continue;
				}
				const int32_t li = (pz - dr.position.y) * dw + px - dr.position.x;
				if (out[li] == DRY) {
					touched.push_back(li);
				}
				out[li] = (float)maxf((double)out[li], (double)v);
			}
		}
	}
	for (int32_t li : touched) {
		const int64_t gi = (int64_t)(li / dw + dr.position.y) * width + li % dw + dr.position.x;
		out[li] = (float)minf((double)out[li], (double)ground[gi] - tuck);
	}
}

} // namespace

Dictionary water_derive(const Dictionary &args) {
	const Args a{ args };
	const Vector2i size = a["size"];
	const Rect2i inner = a["inner"];
	const PackedFloat32Array base_a = a["base"];
	const PackedFloat32Array ground_a = a["ground"];
	const PackedByteArray spill_a = a["spill"];
	const PackedByteArray calm_a = a["calm"];
	const PackedFloat32Array stroke_energy_a = a["stroke_energy"];
	PackedFloat32Array w_a = a["w"];
	PackedFloat32Array ew_a = a["ew"];
	PackedFloat32Array depth_a = a["depth"];
	PackedFloat32Array steep_a = a["steep"];
	PackedFloat32Array energy_a = a["energy"];
	const bool exact = (bool)a["exact"];
	const double tuck = a["tuck"];
	const double edge_min = a["edge_min"];
	const double step_x = a["step_x"];
	const double step_y = a["step_y"];
	const double steep_lo = a["steep_lo"];
	const double steep_hi = a["steep_hi"];
	const double white_lo = a["white_lo"];
	const double white_hi = a["white_hi"];
	const double ramp_keep = a["ramp_keep"];
	const double ramp_flat = a["ramp_flat"];
	const int spill_pond = (int)(int64_t)a["spill_pond"];
	const int width = size.x;
	const int height = size.y;
	const float *base = base_a.ptr();
	const float *ground = ground_a.ptr();
	const uint8_t *spill = spill_a.ptr();
	const uint8_t *calm = calm_a.ptr();
	const float *stroke_energy = stroke_energy_a.ptr();
	float *w = w_a.ptrw();
	float *ew = ew_a.ptrw();
	float *depth = depth_a.ptrw();
	float *steep = steep_a.ptrw();
	float *energy = energy_a.ptrw();

	const Rect2i reach = clip_to(inner.grow(1), width, height);
	const Rect2i wide = clip_to(reach.grow(1), width, height);
	std::vector<float> cut((size_t)wide.size.x * wide.size.y);
	for (int z = 0; z < wide.size.y; z++) {
		const int64_t row = (int64_t)(wide.position.y + z) * width + wide.position.x;
		for (int x = 0; x < wide.size.x; x++) {
			cut[(size_t)z * wide.size.x + x] = base[row + x];
		}
	}
	std::vector<float> first, second;
	ring_of(cut, wide, reach, ground, width, tuck, first);
	ring_of(first, reach, inner, ground, width, tuck, second);
	const int iw = inner.size.x;
	for (int z = 0; z < inner.size.y; z++) {
		const int64_t row = (int64_t)(inner.position.y + z) * width + inner.position.x;
		for (int x = 0; x < iw; x++) {
			const int64_t i = row + x;
			const float v = second[(size_t)z * iw + x];
			w[i] = v;
			depth[i] = v != DRY ? (float)((double)v - (double)ground[i]) : -INFINITY;
			steep[i] = 0.0f;
			energy[i] = stroke_energy[i];
			// _edge_surface
			float e = v;
			if (exact && v != DRY && base[i] == DRY) {
				const int gx = inner.position.x + x;
				const int gz = inner.position.y + z;
				double top = -INFINITY;
				for (int k = 0; k < 8; k++) {
					const int xx = gx + NX[k];
					const int zz = gz + NZ[k];
					if (xx < 0 || zz < 0 || xx >= width || zz >= height) {
						continue;
					}
					const float h = base[(int64_t)zz * width + xx];
					if (h != DRY) {
						top = maxf(top, (double)h);
					}
				}
				if (top != -INFINITY) {
					e = (float)minf(top, (double)ground[i] - edge_min);
				}
			}
			ew[i] = e;
		}
	}
	// _slope_axis: half the central difference of w along one axis among wet neighbours.
	auto slope_axis = [&](int64_t i, int c, int stride, int count) -> double {
		const int64_t lo = (c > 0 && depth[i - stride] > 0.0f) ? i - stride : i;
		const int64_t hi = (c < count - 1 && depth[i + stride] > 0.0f) ? i + stride : i;
		if (lo == hi) {
			return 0.0;
		}
		const double span = (lo != i && hi != i) ? 2.0 : 1.0;
		return ((double)w[hi] - (double)w[lo]) / span;
	};
	// _spill_near: any spill sample (of `kind`, any when 0) within `r` of (x, z).
	auto spill_near = [&](int x, int z, int r, int kind) -> bool {
		for (int dz = -r; dz <= r; dz++) {
			const int zz = z + dz;
			if (zz < 0 || zz >= height) {
				continue;
			}
			for (int dx = -r; dx <= r; dx++) {
				const int xx = x + dx;
				if (xx < 0 || xx >= width) {
					continue;
				}
				const int s = spill[(int64_t)zz * width + xx];
				if (s != 0 && (kind == 0 || s == kind)) {
					return true;
				}
			}
		}
		return false;
	};
	for (int z = inner.position.y; z < inner.position.y + inner.size.y; z++) {
		for (int x = inner.position.x; x < inner.position.x + inner.size.x; x++) {
			const int64_t i = (int64_t)z * width + x;
			if (!(depth[i] > 0.0f)) {
				continue;
			}
			const double gx = slope_axis(i, x, 1, width) / step_x;
			const double gz = slope_axis(i, z, width, height) / step_y;
			const double sl = std::sqrt(gx * gx + gz * gz);
			steep[i] = (float)Math::smoothstep(steep_lo, steep_hi, sl);
			if (calm[i] == 0) {
				energy[i] = (float)maxf((double)energy[i], Math::smoothstep(white_lo, white_hi, sl) * 0.6);
			}
			if (spill_near(x, z, 2, spill_pond)) {
				energy[i] = (float)((double)energy[i] * ramp_keep);
			}
			if (spill[i] != 0 || ((double)depth[i] < ramp_flat && spill_near(x, z, 1, 0))) {
				steep[i] = 0.0f;
			}
		}
	}
	Dictionary out;
	out["w"] = w_a;
	out["ew"] = ew_a;
	out["depth"] = depth_a;
	out["steep"] = steep_a;
	out["energy"] = energy_a;
	return out;
}

// ---------------------------------------------------------------------------------------------
// _shore
// ---------------------------------------------------------------------------------------------

namespace {

// DistanceField._envelope over the first `n` entries of `f` (parabolas scaled by `scale`).
void envelope(const std::vector<double> &f, int n, double scale, std::vector<double> &out, std::vector<int32_t> &arg,
		std::vector<int32_t> &v, std::vector<double> &z) {
	int k = -1;
	for (int q = 0; q < n; q++) {
		if (f[q] >= FAR_SQ * 0.5) {
			continue;
		}
		const double fq = f[q] / scale + (double)(q * q);
		if (k < 0) {
			k = 0;
			v[0] = q;
			z[0] = -INFINITY;
			z[1] = INFINITY;
			continue;
		}
		double s = (fq - (f[v[k]] / scale + (double)(v[k] * v[k]))) / (2.0 * (double)(q - v[k]));
		while (s <= z[k]) {
			k -= 1;
			s = (fq - (f[v[k]] / scale + (double)(v[k] * v[k]))) / (2.0 * (double)(q - v[k]));
		}
		k += 1;
		v[k] = q;
		z[k] = s;
		z[k + 1] = INFINITY;
	}
	if (k < 0) {
		for (int q = 0; q < n; q++) {
			out[q] = FAR_SQ;
			arg[q] = -1;
		}
		return;
	}
	int j = 0;
	for (int q = 0; q < n; q++) {
		while (z[j + 1] < (double)q) {
			j += 1;
		}
		const int d = q - v[j];
		out[q] = (double)(d * d) * scale + f[v[j]];
		arg[q] = v[j];
	}
}

// DistanceField.transform's "nearest" over a `width` x `height` grid with `feature` set cells.
std::vector<int32_t> nearest_feature(const std::vector<uint8_t> &feature, int width, int height, double sx, double sz) {
	const int64_t count = (int64_t)width * height;
	std::vector<int32_t> nearest((size_t)count, -1);
	const int longest = width > height ? width : height;
	std::vector<double> row_distance((size_t)count);
	std::vector<int32_t> row_column((size_t)count);
	std::vector<double> f((size_t)longest), out((size_t)longest), zz((size_t)longest + 1);
	std::vector<int32_t> arg((size_t)longest), vv((size_t)longest);
	for (int z = 0; z < height; z++) {
		const int64_t row = (int64_t)z * width;
		for (int x = 0; x < width; x++) {
			f[x] = feature[row + x] != 0 ? 0.0 : FAR_SQ;
		}
		envelope(f, width, sx, out, arg, vv, zz);
		for (int x = 0; x < width; x++) {
			row_distance[row + x] = out[x];
			row_column[row + x] = arg[x];
		}
	}
	for (int x = 0; x < width; x++) {
		for (int z = 0; z < height; z++) {
			f[z] = row_distance[(int64_t)z * width + x];
		}
		envelope(f, height, sz, out, arg, vv, zz);
		for (int z = 0; z < height; z++) {
			const int64_t i = (int64_t)z * width + x;
			const double d = out[z];
			if (d >= FAR_SQ * 0.5) {
				continue;
			}
			const int from_row = arg[z];
			nearest[i] = (int32_t)((int64_t)from_row * width + row_column[(int64_t)from_row * width + x]);
		}
	}
	return nearest;
}

// WaterFieldContour._segment: the segment where the plane through three corners crosses zero.
void contour_segment(float *seg, uint8_t *ok, int64_t slot, const Vector2 p[3], const float v[3]) {
	Vector2 pts[3];
	int count = 0;
	for (int k = 0; k < 3; k++) {
		const int j = (k + 1) % 3;
		const double va = (double)v[k];
		const double vb = (double)v[j];
		if ((va > 0.0) != (vb > 0.0)) {
			pts[count < 3 ? count : 2] = p[k].lerp(p[j], (float)(va / (va - vb)));
			count++;
		}
	}
	if (count != 2) {
		return;
	}
	ok[slot] = 1;
	seg[slot * 4] = pts[0].x;
	seg[slot * 4 + 1] = pts[0].y;
	seg[slot * 4 + 2] = pts[1].x;
	seg[slot * 4 + 3] = pts[1].y;
}

// WaterFieldContour.distance: the distance from `q` to the segments of the cells on grid edge `edge`.
double contour_distance(const Vector2 &q, const std::vector<float> &seg, const std::vector<uint8_t> &ok, int edge, int ww) {
	const int start = edge >> 1;
	const int other = (edge & 1) == 0 ? start - ww : start - 1;
	double best = INFINITY;
	const int cells[2] = { start, other };
	for (int c : cells) {
		if (c < 0) {
			continue;
		}
		for (int t = 0; t < 2; t++) {
			const int64_t slot = (int64_t)c * 2 + t;
			if (ok[slot] == 0) {
				continue;
			}
			const Vector2 a(seg[slot * 4], seg[slot * 4 + 1]);
			const Vector2 b(seg[slot * 4 + 2], seg[slot * 4 + 3]);
			const Vector2 ab = b - a;
			const double l2 = (double)ab.length_squared();
			double d = (double)q.distance_to(a);
			if (l2 > 1e-12) {
				const double u = clampd((double)(q - a).dot(ab) / l2, 0.0, 1.0);
				d = (double)q.distance_to(a + ab * (float)u);
			}
			best = minf(best, d);
		}
	}
	return best;
}

} // namespace

Dictionary water_shore(const Dictionary &args) {
	const Args a{ args };
	const Vector2i size = a["size"];
	const Rect2i outer = a["outer"];
	const PackedFloat32Array w_a = a["w"];
	const PackedFloat32Array depth_a = a["depth"];
	const PackedFloat32Array ew_a = a["ew"];
	const PackedFloat32Array ground_a = a["ground"];
	PackedFloat32Array shore_a = a["shore"];
	const bool exact = (bool)a["exact"];
	const Vector2 origin = a["origin"];
	const Vector2 step = a["step"];
	const int margin = (int)(int64_t)a["margin"];
	const double shore_far = a["shore_far"];
	const double exact_m = a["exact_m"];
	const int width = size.x;
	const int height = size.y;
	const float *w = w_a.ptr();
	const float *depth = depth_a.ptr();
	const float *ew = ew_a.ptr();
	const float *ground = ground_a.ptr();
	float *shore = shore_a.ptrw();

	const Rect2i win = clip_to(outer.grow(margin), width, height);
	const int ww = win.size.x;
	const int wh = win.size.y;
	const int64_t count = (int64_t)ww * wh;
	std::vector<Vector2> seeds((size_t)count);
	std::vector<uint8_t> has((size_t)count, 0);
	std::vector<float> best((size_t)count, INFINITY);
	std::vector<int32_t> sedge((size_t)count, 0);
	std::vector<float> ed((size_t)count);
	// _edge_depth
	for (int z = win.position.y; z < win.position.y + wh; z++) {
		const int64_t lrow = (int64_t)(z - win.position.y) * ww - win.position.x;
		for (int x = win.position.x; x < win.position.x + ww; x++) {
			const int64_t i = (int64_t)z * width + x;
			ed[lrow + x] = (!exact || w[i] == DRY) ? depth[i] : (float)((double)ew[i] - (double)ground[i]);
		}
	}
	for (int z = win.position.y; z < win.position.y + wh; z++) {
		for (int x = win.position.x; x < win.position.x + ww; x++) {
			const double da = (double)ed[(int64_t)(z - win.position.y) * ww + x - win.position.x];
			if (da == -INFINITY) {
				continue;
			}
			for (int k = 0; k < 2; k++) {
				const int dx = 1 - k;
				const int dz = k;
				const int xx = x + dx;
				const int zz = z + dz;
				if (xx >= win.position.x + ww || zz >= win.position.y + wh) {
					continue;
				}
				const int64_t li = (int64_t)(z - win.position.y) * ww + x - win.position.x;
				const int64_t lj = li + dx + (int64_t)dz * ww;
				const double db = (double)ed[lj];
				if (db == -INFINITY || (da > 0.0) == (db > 0.0)) {
					continue;
				}
				const double t = da / (da - db);
				const Vector2 p = origin + Vector2((float)((double)x + (double)dx * t), (float)((double)z + (double)dz * t)) * step;
				double dd = (double)(origin + Vector2((float)x, (float)z) * step).distance_to(p);
				if (dd < (double)best[li]) {
					best[li] = (float)dd;
					seeds[li] = p;
					sedge[li] = (int32_t)(li * 2 + k);
					has[li] = 1;
				}
				dd = (double)(origin + Vector2((float)xx, (float)zz) * step).distance_to(p);
				if (dd < (double)best[lj]) {
					best[lj] = (float)dd;
					seeds[lj] = p;
					sedge[lj] = (int32_t)(li * 2 + k);
					has[lj] = 1;
				}
			}
		}
	}
	const std::vector<int32_t> near_ = nearest_feature(has, ww, wh, (double)step.x * (double)step.x, (double)step.y * (double)step.y);
	std::vector<float> seg;
	std::vector<uint8_t> ok;
	if (exact) {
		// WaterFieldContour.table
		seg.assign((size_t)count * 8, 0.0f);
		ok.assign((size_t)count * 2, 0);
		for (int z = 0; z < wh - 1; z++) {
			for (int x = 0; x < ww - 1; x++) {
				const int64_t c = (int64_t)z * ww + x;
				if (has[c] == 0 && has[c + 1] == 0 && has[c + ww] == 0 && has[c + ww + 1] == 0) {
					continue;
				}
				const float v00 = ed[c];
				const float v10 = ed[c + 1];
				const float v01 = ed[c + ww];
				const float v11 = ed[c + ww + 1];
				const Vector2 p00 = origin + Vector2((float)(win.position.x + x), (float)(win.position.y + z)) * step;
				const Vector2 p10 = p00 + Vector2(step.x, 0.0f);
				const Vector2 p01 = p00 + Vector2(0.0f, step.y);
				const Vector2 p11 = p00 + step;
				if (v00 != -INFINITY && v10 != -INFINITY && v01 != -INFINITY) {
					const Vector2 p[3] = { p00, p10, p01 };
					const float v[3] = { v00, v10, v01 };
					contour_segment(seg.data(), ok.data(), c * 2, p, v);
				}
				if (v10 != -INFINITY && v11 != -INFINITY && v01 != -INFINITY) {
					const Vector2 p[3] = { p10, p11, p01 };
					const float v[3] = { v10, v11, v01 };
					contour_segment(seg.data(), ok.data(), c * 2 + 1, p, v);
				}
			}
		}
	}
	for (int z = outer.position.y; z < outer.position.y + outer.size.y; z++) {
		for (int x = outer.position.x; x < outer.position.x + outer.size.x; x++) {
			const int64_t i = (int64_t)z * width + x;
			const int64_t li = (int64_t)(z - win.position.y) * ww + x - win.position.x;
			const Vector2 q = origin + Vector2((float)x, (float)z) * step;
			double dd = shore_far;
			if (has[li] != 0) {
				dd = minf(dd, (double)q.distance_to(seeds[li]));
			}
			const int32_t nn = near_[li];
			if (nn >= 0 && nn != li) {
				dd = minf(dd, (double)q.distance_to(seeds[nn]));
			}
			if (exact && dd < exact_m + 0.12) {
				if (has[li] != 0) {
					dd = minf(dd, contour_distance(q, seg, ok, sedge[li], ww));
				}
				if (nn >= 0 && nn != li) {
					dd = minf(dd, contour_distance(q, seg, ok, sedge[nn], ww));
				}
			}
			shore[i] = (float)(ed[li] > 0.0f ? dd : -dd);
		}
	}
	Dictionary out;
	out["shore"] = shore_a;
	return out;
}

// ---------------------------------------------------------------------------------------------
// RiverProfile.field
// ---------------------------------------------------------------------------------------------

namespace {

// RiverProfile._cells_in.
Rect2i cells_in(const Rect2 &box, const Vector2 &origin, const Vector2 &step, const Vector2i &size) {
	const Vector2 low = ((box.position - origin) / step).ceil();
	const Vector2 high = ((box.get_end() - origin) / step).floor();
	const Vector2i first(MAX(0, (int)low.x), MAX(0, (int)low.y));
	const Vector2i last(MIN(size.x - 1, (int)high.x), MIN(size.y - 1, (int)high.y));
	if (last.x < first.x || last.y < first.y) {
		return Rect2i(first, Vector2i());
	}
	return Rect2i(first, last - first + Vector2i(1, 1));
}

} // namespace

Dictionary water_raster(const Dictionary &args) {
	const Args a{ args };
	const PackedVector2Array points = a["points"];
	const PackedFloat32Array widths = a["widths"];
	const PackedFloat32Array arc = a["arc"];
	const Rect2i rect = a["rect"];
	const Vector2 origin = a["origin"];
	const Vector2 step = a["step"];
	const Vector2i grid = a["grid"];
	const double reach = a["reach"];
	const double total = a["total"];
	const Vector2i run_off = a["run_off"];
	const int64_t count = (int64_t)rect.size.x * rect.size.y;
	PackedFloat32Array distance_a;
	PackedFloat32Array along_a;
	PackedFloat32Array half_a;
	distance_a.resize(count);
	along_a.resize(count);
	half_a.resize(count);
	float *distance = distance_a.ptrw();
	float *along = along_a.ptrw();
	float *half_width = half_a.ptrw();
	for (int64_t k = 0; k < count; k++) {
		distance[k] = INFINITY;
		along[k] = 0.0f;
		half_width[k] = 0.0f;
	}
	const int64_t segments = points.size() - 1;
	for (int64_t s = 0; s < segments; s++) {
		const Vector2 pa = points[s];
		const Vector2 segment = points[s + 1] - pa;
		const double length_sq = (double)segment.length_squared();
		if (length_sq <= 1e-12) {
			continue;
		}
		const double length = std::sqrt(length_sq);
		const Rect2 box = Rect2(pa, Vector2()).expand(points[s + 1]).grow((real_t)reach);
		const Rect2i cells = cells_in(box, origin, step, grid).intersection(rect);
		const double lo = (s == 0 && run_off.x != 0) ? -INFINITY : 0.0;
		const double hi = (s == segments - 1 && run_off.y != 0) ? INFINITY : 1.0;
		for (int j = cells.position.y; j < cells.position.y + cells.size.y; j++) {
			const double z = (double)origin.y + (double)j * (double)step.y;
			const int64_t row = (int64_t)(j - rect.position.y) * rect.size.x - rect.position.x;
			for (int i = cells.position.x; i < cells.position.x + cells.size.x; i++) {
				const Vector2 p((float)((double)origin.x + (double)i * (double)step.x), (float)z);
				const double t = clampd((double)(p - pa).dot(segment) / length_sq, lo, hi);
				const double d = (double)p.distance_to(pa + segment * (float)t);
				const int64_t k = row + i;
				if (d < (double)distance[k]) {
					distance[k] = (float)d;
					along[k] = (float)clampd((double)arc[s] + t * length, 0.0, total);
					const double tw = clampd(t, 0.0, 1.0);
					half_width[k] = (float)((double)widths[s] + ((double)widths[s + 1] - (double)widths[s]) * tw);
				}
			}
		}
	}
	Dictionary out;
	out["distance"] = distance_a;
	out["along"] = along_a;
	out["half_width"] = half_a;
	return out;
}

} // namespace ttscatter
