// The window's grids from the document's own arrays (card native-cover, 2026-10-20): what
// utils/scatter_native.gd's grids_for builds in GDScript with document_fields' and the sampler's
// calls, ported line for line so the values are the same bit for bit. The density decode,
// TerrainRules.sample_fields with store_fields, ScatterGround.face_proximity with
// HeightBrush.box_mean, ScatterGround._painted_fields and _built_fringe. GDScript keeps its
// scalars in double and rounds to float32 where a value goes into a PackedFloat32Array, so the
// port does the same: every sum and quotient in double, every stored value cast to float, and the
// expressions grouped as GDScript groups them (a sliding sum adds the difference, not two terms).
// GDScript computed these in about 24 ms of a 44 ms job on the probe cell; here they cost well
// under a millisecond.
#include "scatter_core.h"

#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2i.hpp>

using godot::Dictionary;
using godot::Rect2i;
using godot::String;
using godot::Variant;
using godot::Vector2i;

namespace ttscatter {

namespace {

Variant at(const Dictionary &d, const char *k) {
	return d.get(String(k), Variant());
}

int64_t inum(const Dictionary &d, const char *k) {
	Variant v = at(d, k);
	return v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT ? (int64_t)v : 0;
}

double dnum(const Dictionary &d, const char *k) {
	Variant v = at(d, k);
	return v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT ? (double)v : 0.0;
}

inline int64_t clampi(int64_t v, int64_t lo, int64_t hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

/// The inputs every grid reads.
struct Doc {
	int64_t columns = 0, rows = 0;
	Vector2 step;
	const float *heights = nullptr;
	int r = 1;
	double start_cos = 0.0, end_cos = 0.0;
};

/// TerrainRules.sample_fields: curvature and steepness over `rect` (row-major over its
/// intersection with the grid), written into the whole-grid arrays as store_fields does. Either
/// output may be null.
void sample_fields(const Doc &doc, Rect2i rect, std::vector<float> *curvature_grid, std::vector<float> *steep_grid) {
	const int64_t columns = doc.columns, rows = doc.rows;
	const float *heights = doc.heights;
	Rect2i out = rect.intersection(Rect2i(0, 0, (int32_t)columns, (int32_t)rows));
	if (!out.has_area()) {
		return;
	}
	const int64_t r = doc.r;
	const int64_t x_lo = out.position.x - r;
	const int64_t x_hi = out.position.x + out.size.x - 1 + r;
	const int64_t z_lo = out.position.y - r;
	const int64_t z_hi = out.position.y + out.size.y - 1 + r;
	const int64_t in_rows = z_hi - z_lo + 1;
	const int64_t width = out.size.x;
	const int64_t in_cols = x_hi - x_lo + 1;
	std::vector<float> ny_window((size_t)(in_rows * in_cols));
	const double start_cos = doc.start_cos;
	const double inv_span = 1.0 / (doc.end_cos - start_cos);
	const double step_x = doc.step.x, step_y = doc.step.y;
	for (int64_t wz = 0; wz < in_rows; wz++) {
		int64_t sz = clampi(z_lo + wz, 0, rows - 1);
		int64_t z0 = imax(sz - 1, 0);
		int64_t z1 = imin(sz + 1, rows - 1);
		double inv_dz = 1.0 / ((double)(z1 - z0) * step_y);
		int64_t here = sz * columns;
		for (int64_t wx = 0; wx < in_cols; wx++) {
			int64_t sx = clampi(x_lo + wx, 0, columns - 1);
			int64_t x0 = imax(sx - 1, 0);
			int64_t x1 = imin(sx + 1, columns - 1);
			double slope_x = ((double)heights[here + x1] - (double)heights[here + x0]) / ((double)(x1 - x0) * step_x);
			double slope_z = ((double)heights[z1 * columns + sx] - (double)heights[z0 * columns + sx]) * inv_dz;
			ny_window[wz * in_cols + wx] = (float)(1.0 / std::sqrt(1.0 + slope_x * slope_x + slope_z * slope_z));
		}
	}
	auto tail = [&](int64_t i) -> double {
		return gclamp(((double)ny_window[i] - start_cos) * inv_span, 0.0, 1.0);
	};
	// Horizontal pass: per window row, box sums of h and of the slope tail per output column.
	std::vector<float> h_rows((size_t)(in_rows * width)), t_rows((size_t)(in_rows * width));
	for (int64_t wz = 0; wz < in_rows; wz++) {
		int64_t sz = clampi(z_lo + wz, 0, rows - 1);
		int64_t here = sz * columns;
		int64_t base = wz * in_cols;
		double sum_h = 0.0, sum_t = 0.0;
		for (int64_t k = 0; k < 2 * r + 1; k++) {
			sum_h += (double)heights[here + clampi(x_lo + k, 0, columns - 1)];
			sum_t += tail(base + k);
		}
		for (int64_t ox = 0; ox < width; ox++) {
			h_rows[wz * width + ox] = (float)sum_h;
			t_rows[wz * width + ox] = (float)sum_t;
			if (ox + 1 < width) {
				int64_t drop = ox;
				int64_t add = ox + 2 * r + 1;
				sum_h += ((double)heights[here + clampi(x_lo + add, 0, columns - 1)] -
						(double)heights[here + clampi(x_lo + drop, 0, columns - 1)]);
				sum_t += (tail(base + add) - tail(base + drop));
			}
		}
	}
	// Vertical pass, stored into the whole grid (store_fields).
	const double inv_area = 1.0 / (double)((2 * r + 1) * (2 * r + 1));
	for (int64_t ox = 0; ox < width; ox++) {
		double sum_h = 0.0, sum_t = 0.0;
		for (int64_t k = 0; k < 2 * r + 1; k++) {
			sum_h += (double)h_rows[k * width + ox];
			sum_t += (double)t_rows[k * width + ox];
		}
		for (int64_t oz = 0; oz < out.size.y; oz++) {
			int64_t wz = oz + r;
			int64_t sx = out.position.x + ox;
			int64_t sz = out.position.y + oz;
			double ny = (double)ny_window[wz * in_cols + (sx - x_lo)];
			int64_t g = sz * columns + sx;
			if (curvature_grid != nullptr) {
				(*curvature_grid)[g] = (float)(((double)heights[g] - sum_h * inv_area) * ny);
			}
			if (steep_grid != nullptr) {
				(*steep_grid)[g] = (float)(sum_t * inv_area);
			}
			if (oz + 1 < out.size.y) {
				sum_h += (double)h_rows[(oz + 2 * r + 1) * width + ox] - (double)h_rows[oz * width + ox];
				sum_t += (double)t_rows[(oz + 2 * r + 1) * width + ox] - (double)t_rows[oz * width + ox];
			}
		}
	}
}

/// HeightBrush.box_mean over `rect` of the whole-grid `values` with window radius `k`, edges
/// replicated, written into the whole-grid `out` at `rect` (face_proximity's and the fringe's
/// copy loop).
void box_mean_into(const std::vector<float> &values, int64_t width, int64_t depth, Rect2i rect, int64_t k, std::vector<float> &out) {
	if (!rect.has_area()) {
		return;
	}
	const int64_t rows_low = rect.position.y - k;
	const int64_t rows_high = rect.position.y + rect.size.y - 1 + k;
	const int64_t band_rows = rows_high - rows_low + 1;
	const int64_t columns = rect.size.x;
	const double inv = 1.0 / (double)(2 * k + 1);
	std::vector<float> horizontal((size_t)(band_rows * columns));
	for (int64_t r = 0; r < band_rows; r++) {
		int64_t z = clampi(rows_low + r, 0, depth - 1);
		int64_t row = z * width;
		double sum = 0.0;
		for (int64_t dx = -k; dx < k + 1; dx++) {
			sum += (double)values[row + clampi(rect.position.x + dx, 0, width - 1)];
		}
		horizontal[r * columns] = (float)(sum * inv);
		for (int64_t c = 1; c < columns; c++) {
			int64_t x = rect.position.x + c;
			sum += (double)values[row + clampi(x + k, 0, width - 1)];
			sum -= (double)values[row + clampi(x - k - 1, 0, width - 1)];
			horizontal[r * columns + c] = (float)(sum * inv);
		}
	}
	for (int64_t c = 0; c < columns; c++) {
		double sum = 0.0;
		for (int64_t r = 0; r < 2 * k + 1; r++) {
			sum += (double)horizontal[r * columns + c];
		}
		int64_t g = rect.position.y * width + rect.position.x + c;
		out[g] = (float)(sum * inv);
		for (int64_t z = 1; z < rect.size.y; z++) {
			sum += (double)horizontal[(z + 2 * k) * columns + c];
			sum -= (double)horizontal[(z - 1) * columns + c];
			out[(rect.position.y + z) * width + rect.position.x + c] = (float)(sum * inv);
		}
	}
}

/// The surface planes ScatterGround._painted_fields reads.
struct Surfaces {
	const uint8_t *weights = nullptr;
	const uint8_t *kinds = nullptr;
	int64_t kinds_size = 0, used = 0, entries = 0, channels = 0, plane = 0;
};

/// ScatterGround._painted_fields over `rect`: the painted total, built, rock and ash weights into
/// whole-grid arrays (any output may be null). Built is kind 1, rock 2 and ash 3 (`kinds`).
void painted_fields(const Surfaces &s, int64_t columns, Rect2i rect, std::vector<float> *total_out, std::vector<float> *built_out,
		std::vector<float> *rock_out, std::vector<float> *ash_out) {
	for (int64_t z = rect.position.y; z < rect.position.y + rect.size.y; z++) {
		for (int64_t x = rect.position.x; x < rect.position.x + rect.size.x; x++) {
			int64_t i = z * columns + x;
			int64_t at_i = i * s.channels;
			if (s.weights[s.plane + at_i] == 0) {
				continue;
			}
			int64_t total = 0, b = 0, r = 0, a = 0;
			for (int64_t e = 0; e < s.entries; e++) {
				int64_t weight = s.weights[s.plane + at_i + e];
				if (weight == 0) {
					break;
				}
				int64_t slot = s.weights[at_i + e];
				if (slot >= s.used) {
					continue;
				}
				total += weight;
				uint8_t kind = slot < s.kinds_size ? s.kinds[slot] : 0;
				if (kind == 1) {
					b += weight;
				} else if (kind == 2) {
					r += weight;
				} else if (kind == 3) {
					a += weight;
				}
			}
			if (total == 0) {
				continue;
			}
			if (total_out != nullptr) {
				(*total_out)[i] = (float)((double)total / 255.0);
			}
			if (built_out != nullptr) {
				(*built_out)[i] = (float)((double)b / 255.0);
			}
			if (rock_out != nullptr) {
				(*rock_out)[i] = (float)((double)r / 255.0);
			}
			if (ash_out != nullptr) {
				(*ash_out)[i] = (float)((double)a / 255.0);
			}
		}
	}
}

} // namespace

bool build_grids(const Dictionary &source, Grids &grids) {
	Doc doc;
	doc.columns = inum(source, "columns");
	doc.rows = inum(source, "rows");
	const int64_t columns = doc.columns, rows = doc.rows;
	const int64_t count = columns * rows;
	if (columns < 2 || rows < 2) {
		return false;
	}
	Variant step_v = at(source, "step");
	Variant half_v = at(source, "half");
	if (step_v.get_type() != Variant::VECTOR2 || half_v.get_type() != Variant::VECTOR2) {
		return false;
	}
	doc.step = (Vector2)step_v;
	grids.columns = (int)columns;
	grids.rows = (int)rows;
	grids.step = doc.step;
	grids.half = (Vector2)half_v;
	grids.seed_value = inum(source, "seed_value");
	doc.r = (int)inum(source, "curvature_radius");
	doc.start_cos = dnum(source, "start_cos");
	doc.end_cos = dnum(source, "end_cos");
	const int64_t face_k = inum(source, "face_radius");
	const int64_t fringe_k = inum(source, "fringe_radius");
	const int64_t slot = inum(source, "slot");
	Vector2i low = (Vector2i)at(source, "low");
	Vector2i high = (Vector2i)at(source, "high");
	Rect2i rect = (Rect2i)at(source, "rect");
	const Rect2i grid(0, 0, (int32_t)columns, (int32_t)rows);
	godot::PackedByteArray slots = at(source, "biome_slots");
	godot::PackedByteArray density_in = at(source, "biome_density");
	if (slots.size() != count || density_in.size() != count || doc.r < 1 || face_k < 1 || fringe_k < 1) {
		return false;
	}
	// The density decode (grids_for): the biome's painted density inside the window, else 0.
	std::vector<float> density((size_t)count, 0.0f);
	const uint8_t *sp = slots.ptr();
	const uint8_t *dp = density_in.ptr();
	for (int64_t z = low.y; z < high.y + 1; z++) {
		for (int64_t i = z * columns + low.x; i < z * columns + high.x + 1; i++) {
			if (sp[i] == slot) {
				density[i] = (float)((double)dp[i] / 255.0);
			}
		}
	}
	grids.density.adopt(std::move(density));
	// Heights: a document without them reads as flat ground.
	godot::PackedFloat32Array heights_in = at(source, "heights");
	if (heights_in.size() == count) {
		grids.heights.take(heights_in);
	} else {
		grids.heights.adopt(std::vector<float>((size_t)count, 0.0f));
	}
	doc.heights = grids.heights.p;
	std::vector<float> curvature((size_t)count, 0.0f), steep((size_t)count, 0.0f);
	sample_fields(doc, rect, &curvature, &steep);
	grids.curvature.adopt(std::move(curvature));
	grids.steep.adopt(std::move(steep));
	// face_proximity: the steepness over the rect grown by its window, box-averaged again.
	std::vector<float> near_face((size_t)count, 0.0f);
	Rect2i inner = rect.intersection(grid);
	if (inner.has_area()) {
		std::vector<float> wide((size_t)count, 0.0f);
		sample_fields(doc, inner.grow((int32_t)face_k).intersection(grid), nullptr, &wide);
		box_mean_into(wide, columns, rows, inner, face_k, near_face);
	}
	grids.near_face.adopt(std::move(near_face));
	// Painted surfaces and the path fringe, only when the document lists surface entries.
	godot::PackedByteArray weights = at(source, "surface_weights");
	godot::PackedByteArray kinds = at(source, "kinds");
	if (inum(source, "surfaces") != 0) {
		Surfaces s;
		s.channels = inum(source, "channels");
		s.entries = inum(source, "entries");
		s.used = inum(source, "used");
		s.plane = count * s.channels;
		if (weights.size() < 2 * s.plane || s.entries > s.channels) {
			return false;
		}
		s.weights = weights.ptr();
		s.kinds = kinds.ptr();
		s.kinds_size = kinds.size();
		std::vector<float> total((size_t)count, 0.0f), built((size_t)count, 0.0f), rock((size_t)count, 0.0f),
				ash((size_t)count, 0.0f);
		painted_fields(s, columns, rect, &total, &built, &rock, &ash);
		grids.paint_total.adopt(std::move(total));
		grids.paint_built.adopt(std::move(built));
		grids.paint_rock.adopt(std::move(rock));
		grids.paint_ash.adopt(std::move(ash));
		// _built_fringe: the built weight over the rect grown by the fringe radius, box-averaged.
		std::vector<float> wide_built((size_t)count, 0.0f), fringe((size_t)count, 0.0f);
		painted_fields(s, columns, rect.grow((int32_t)fringe_k).intersection(grid), nullptr, &wide_built, nullptr, nullptr);
		box_mean_into(wide_built, columns, rows, rect, fringe_k, fringe);
		grids.fringe.adopt(std::move(fringe));
	}
	return true;
}

} // namespace ttscatter
