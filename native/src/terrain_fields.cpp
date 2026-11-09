// TerrainRules.sample_fields: see terrain_fields.h. The comments name the GDScript's passes.
#include "terrain_fields.h"

#include <cmath>
#include <vector>

namespace ttscatter {

namespace {

inline int64_t clamp_i(int64_t v, int64_t lo, int64_t hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

inline double clamp_d(double v, double lo, double hi) {
	return v < lo ? lo : (v > hi ? hi : v);
}

} // namespace

void rule_fields(const FieldsInput &in, godot::Rect2i out, float *curvature, float *steep) {
	const int64_t columns = in.columns, rows = in.rows;
	const float *heights = in.heights;
	const int64_t r = in.r;
	// Input window: the rect grown by r (clamped reads beyond the grid replicate the edge).
	const int64_t x_lo = out.position.x - r;
	const int64_t x_hi = out.position.x + out.size.x - 1 + r;
	const int64_t z_lo = out.position.y - r;
	const int64_t z_hi = out.position.y + out.size.y - 1 + r;
	const int64_t in_rows = z_hi - z_lo + 1;
	const int64_t width = out.size.x;
	const int64_t in_cols = x_hi - x_lo + 1;
	// Normal y over the rows and columns of the window.
	std::vector<float> ny_window((size_t)(in_rows * in_cols));
	const double start_cos = in.start_cos;
	const double inv_span = 1.0 / (in.end_cos - start_cos);
	for (int64_t wz = 0; wz < in_rows; wz++) {
		const int64_t sz = clamp_i(z_lo + wz, 0, rows - 1);
		const int64_t z0 = sz - 1 > 0 ? sz - 1 : 0;
		const int64_t z1 = sz + 1 < rows - 1 ? sz + 1 : rows - 1;
		const double inv_dz = 1.0 / ((double)(z1 - z0) * in.step_y);
		const int64_t here = sz * columns;
		for (int64_t wx = 0; wx < in_cols; wx++) {
			const int64_t sx = clamp_i(x_lo + wx, 0, columns - 1);
			const int64_t x0 = sx - 1 > 0 ? sx - 1 : 0;
			const int64_t x1 = sx + 1 < columns - 1 ? sx + 1 : columns - 1;
			const double slope_x = ((double)heights[here + x1] - (double)heights[here + x0]) / ((double)(x1 - x0) * in.step_x);
			const double slope_z = ((double)heights[z1 * columns + sx] - (double)heights[z0 * columns + sx]) * inv_dz;
			ny_window[wz * in_cols + wx] = (float)(1.0 / std::sqrt(1.0 + slope_x * slope_x + slope_z * slope_z));
		}
	}
	auto tail = [&](int64_t i) -> double {
		return clamp_d(((double)ny_window[i] - start_cos) * inv_span, 0.0, 1.0);
	};
	// Horizontal pass: per window row, box sums of h and of the slope tail per output column.
	std::vector<float> h_rows((size_t)(in_rows * width)), t_rows((size_t)(in_rows * width));
	for (int64_t wz = 0; wz < in_rows; wz++) {
		const int64_t sz = clamp_i(z_lo + wz, 0, rows - 1);
		const int64_t here = sz * columns;
		const int64_t base = wz * in_cols;
		double sum_h = 0.0, sum_t = 0.0;
		for (int64_t k = 0; k < 2 * r + 1; k++) {
			sum_h += (double)heights[here + clamp_i(x_lo + k, 0, columns - 1)];
			sum_t += tail(base + k);
		}
		for (int64_t ox = 0; ox < width; ox++) {
			h_rows[wz * width + ox] = (float)sum_h;
			t_rows[wz * width + ox] = (float)sum_t;
			if (ox + 1 < width) {
				const int64_t drop = ox;
				const int64_t add = ox + 2 * r + 1;
				sum_h += ((double)heights[here + clamp_i(x_lo + add, 0, columns - 1)] -
						(double)heights[here + clamp_i(x_lo + drop, 0, columns - 1)]);
				sum_t += (tail(base + add) - tail(base + drop));
			}
		}
	}
	// Vertical pass, row-major over the rect.
	const double inv_area = 1.0 / (double)((2 * r + 1) * (2 * r + 1));
	for (int64_t ox = 0; ox < width; ox++) {
		double sum_h = 0.0, sum_t = 0.0;
		for (int64_t k = 0; k < 2 * r + 1; k++) {
			sum_h += (double)h_rows[k * width + ox];
			sum_t += (double)t_rows[k * width + ox];
		}
		for (int64_t oz = 0; oz < out.size.y; oz++) {
			const int64_t wz = oz + r;
			const int64_t sx = out.position.x + ox;
			const int64_t sz = out.position.y + oz;
			const double ny = (double)ny_window[wz * in_cols + (sx - x_lo)];
			const int64_t i = oz * width + ox;
			curvature[i] = (float)(((double)heights[sz * columns + sx] - sum_h * inv_area) * ny);
			steep[i] = (float)(sum_t * inv_area);
			if (oz + 1 < out.size.y) {
				sum_h += (double)h_rows[(oz + 2 * r + 1) * width + ox] - (double)h_rows[oz * width + ox];
				sum_t += (double)t_rows[(oz + 2 * r + 1) * width + ox] - (double)t_rows[oz * width + ox];
			}
		}
	}
}

} // namespace ttscatter
