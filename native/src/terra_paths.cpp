// The line kinds' shared maths (spike terraform-s2-cpu): a primitive's points smoothed and
// resampled into a line, the window mean and the grading a profile is solved with, and the nearest
// segment a rect sample reads. The path and wall kernels that use them are in src/kinds/.
#include "terra_stages.h"

namespace terra {

void line_from(const Prim &prim, int skip, double ds, Line &out, int rounding) {
	int count = int((prim.d.size() - skip) / 2);
	std::vector<float> pts = chaikin(prim.d.data() + skip, count, rounding);
	out = resample(pts.data(), int(pts.size() / 2), ds);
}

std::vector<double> window_mean(const std::vector<double> &v, int half) {
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

std::vector<double> grade(const std::vector<double> &v, double m) {
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

int nearest_seg(const Line &l, const std::vector<int> &segs, double x, double z, double &d, double &t) {
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

} // namespace terra
