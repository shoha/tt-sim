// The paint coat (built-in kind 8; utils/terraform/kinds/paint/; card terraform-p2-paint-path):
// [surface, then per dab ax, az, bx, bz, radius, seconds], one Paint stroke. `surface` indexes the
// document's surface table (TerraDoc.surfaces); PAINT_ERASE (255) is an erase coat, fading every
// painted surface back toward the automatic ground.
//
// The rule is SurfaceStroke.dab's, ported so a coat's planes equal that stroke's bytes at the
// document samples (every second derive sample): four (surface, weight) entries a sample in
// canonical order (strongest first, a weight of 0 with surface 0). Paint: the coat's coverage v at a
// sample starts at its surface's weight there and approaches 1 by each dab's amount (MaskBrush's
// falloff (1 - t^2)^2 through the exposure table of the dab's seconds); the other entries keep their
// weights from before the coat while they fit in 255 - the painted weight and scale down together
// once they do not, and a sample full of four other surfaces drops its weakest. Erase: a remaining
// fraction f (1 before the coat) is multiplied by 1 - amount per dab and every entry is its weight
// before the coat times f. The entries are computed once per sample from the coat's final v (or f)
// and the entries before the coat, which is what the stroke's last dab wrote. The sample positions
// are the document's own (its float32 origin and step, as SurfaceStroke computes them), so the
// even samples see the same distances as the stroke.
//
// Paths enter as coats too (path_coat, terra_kind_path.cpp), in document order among the coats.
#include <cmath>
#include <cstring>

#include "terra_kinds.h"
#include "terra_math.h"
#include "terra_stages.h"

namespace terra {

constexpr int PAINT_HEADER = 1;
constexpr int PAINT_STRIDE = 6;
constexpr int PAINT_ERASE = 255;
constexpr int PAINT_ENTRIES = 4;
// SurfaceStroke.AMOUNT_STEPS, and its rate: MaskBrush.RATE 3 x SURFACE_GAIN 1.5 (x ERASE_GAIN 2).
constexpr int AMOUNT_STEPS = 256;
constexpr double PAINT_RATE = 3.0 * 1.5;
constexpr double ERASE_GAIN = 2.0;

namespace {

// The document's sample frame in float32 (MapDocument.extent_m, sample_step), widened.
struct DocFrame {
	double ox, oz, sx, sz;
};

DocFrame doc_frame(const Grid &g) {
	float ex = float(-2.0 * g.ox), ez = float(-2.0 * g.oz);
	float sx = ex / float((g.w - 1) / 2), sz = ez / float((g.h - 1) / 2);
	return DocFrame{ double(-ex * 0.5f), double(-ez * 0.5f), double(sx), double(sz) };
}

// SurfaceStroke._amount_table: MaskBrush.amount(q / 255, seconds, rate), float32.
void amount_table(double seconds, bool erase, float *out) {
	double rate = PAINT_RATE * (erase ? ERASE_GAIN : 1.0);
	for (int q = 0; q < AMOUNT_STEPS; q++) {
		double w = double(q) / double(AMOUNT_STEPS - 1);
		out[q] = (w <= 0.0 || seconds <= 0.0) ? 0.0f : float(1.0 - det_exp(-rate * w * seconds));
	}
}

int round_half_away(double v) {
	return int(std::round(v));
}

} // namespace

void coat_entries(uint8_t *pi, uint8_t *pw, int mine, bool erase, double v) {
	int out_i[PAINT_ENTRIES] = {}, out_w[PAINT_ENTRIES] = {};
	int n = 0;
	if (erase) {
		for (int e = 0; e < PAINT_ENTRIES; e++) {
			int byte = round_half_away(pw[e] * v);
			if (byte > 0) {
				out_i[n] = pi[e];
				out_w[n] = byte;
				n++;
			}
		}
	} else {
		int painted = std::clamp(round_half_away(v * 255.0), 0, 255);
		bool has_mine = false;
		for (int e = 0; e < PAINT_ENTRIES; e++) {
			if (pw[e] != 0 && pi[e] == mine) {
				has_mine = true;
			}
		}
		int keep = PAINT_ENTRIES;
		if (!has_mine && painted > 0 && pw[PAINT_ENTRIES - 1] != 0) {
			keep = PAINT_ENTRIES - 1;
		}
		int others = 0;
		for (int e = 0; e < keep; e++) {
			if (pi[e] != mine) {
				others += pw[e];
			}
		}
		int room = 255 - painted;
		bool placed = painted == 0;
		for (int e = 0; e < keep; e++) {
			int byte = pw[e];
			if (byte == 0 || pi[e] == mine) {
				continue;
			}
			if (others > room) {
				byte = byte * room / others;
			}
			if (byte == 0) {
				continue;
			}
			if (!placed && painted >= byte) {
				out_i[n] = mine;
				out_w[n] = painted;
				n++;
				placed = true;
			}
			out_i[n] = pi[e];
			out_w[n] = byte;
			n++;
		}
		if (!placed) {
			out_i[n] = mine;
			out_w[n] = painted;
			n++;
		}
	}
	for (int e = 0; e < PAINT_ENTRIES; e++) {
		pi[e] = uint8_t(e < n ? out_i[e] : 0);
		pw[e] = uint8_t(e < n ? out_w[e] : 0);
	}
}

void paint_coat(const Prim &p, const Grid &g, const Rect &r, uint8_t *PI, uint8_t *PW) {
	if (p.d.size() < size_t(PAINT_HEADER + PAINT_STRIDE) || r.empty()) {
		return;
	}
	int mine = int(p.d[0]);
	bool erase = mine == PAINT_ERASE;
	DocFrame f = doc_frame(g);
	int rw = r.x1 - r.x0, rh = r.y1 - r.y0;
	// Per sample of the rect: the stored coverage (float32, as SurfaceStroke keeps it between dabs),
	// the last dab's unrounded value, and whether a dab reached it.
	std::vector<float> val(size_t(rw) * rh, 0.0f);
	std::vector<double> last(size_t(rw) * rh, 0.0);
	std::vector<uint8_t> hit(size_t(rw) * rh, 0);
	float table[AMOUNT_STEPS];
	double table_seconds = -1.0;
	for (size_t k = PAINT_HEADER; k + PAINT_STRIDE <= p.d.size(); k += PAINT_STRIDE) {
		float ax = p.d[k], az = p.d[k + 1], bx = p.d[k + 2], bz = p.d[k + 3];
		double rad = p.d[k + 4], seconds = p.d[k + 5];
		if (rad <= 0.0 || seconds <= 0.0) {
			continue;
		}
		Rect b = g.rect_world(std::min(ax, bx) - rad, std::min(az, bz) - rad, std::max(ax, bx) + rad,
				std::max(az, bz) + rad)
						 .inter(r);
		if (b.empty()) {
			continue;
		}
		if (seconds != table_seconds) {
			amount_table(seconds, erase, table);
			table_seconds = seconds;
		}
		float segx = bx - ax, segz = bz - az;
		float seg_x2 = segx * segx, seg_z2 = segz * segz;
		float length_sq = seg_x2 + seg_z2;
		double radius_sq = rad * rad;
		for (int j = b.y0; j < b.y1; j++) {
			double pz = (f.oz + (j * 0.5) * f.sz) - double(az);
			for (int i = b.x0; i < b.x1; i++) {
				double px = (f.ox + (i * 0.5) * f.sx) - double(ax);
				double along = 0.0;
				if (length_sq > 0.0f) {
					along = std::clamp((px * segx + pz * segz) / double(length_sq), 0.0, 1.0);
				}
				double dx = px - segx * along, dz = pz - segz * along;
				double t_sq = (dx * dx + dz * dz) / radius_sq;
				if (t_sq >= 1.0) {
					continue;
				}
				double a = table[int((1.0 - t_sq) * (1.0 - t_sq) * double(AMOUNT_STEPS - 1))];
				if (a <= 0.0) {
					continue;
				}
				size_t q = size_t(j - r.y0) * rw + (i - r.x0);
				if (!hit[q]) {
					hit[q] = 1;
					const uint8_t *pi = PI + (int64_t(j) * g.w + i) * PAINT_ENTRIES;
					const uint8_t *pw = PW + (int64_t(j) * g.w + i) * PAINT_ENTRIES;
					int own = 0;
					for (int e = 0; e < PAINT_ENTRIES; e++) {
						if (pw[e] != 0 && pi[e] == mine) {
							own = pw[e];
						}
					}
					val[q] = erase ? 1.0f : float(own / 255.0);
				}
				double v = val[q];
				v = erase ? v * (1.0 - a) : v + (1.0 - v) * a;
				val[q] = float(v);
				last[q] = v;
			}
		}
	}
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			size_t q = size_t(j - r.y0) * rw + (i - r.x0);
			if (hit[q]) {
				int64_t o = (int64_t(j) * g.w + i) * PAINT_ENTRIES;
				coat_entries(PI + o, PW + o, mine, erase, last[q]);
			}
		}
	}
}

void paint_rect(const std::vector<const Prim *> &coats, const std::vector<const PathL *> &paths,
		const std::vector<Rect> &bounds, const Grid &g, const Rect &r, uint8_t *PI, uint8_t *PW) {
	for (int j = r.y0; j < r.y1; j++) {
		int64_t o = (int64_t(j) * g.w + r.x0) * PAINT_ENTRIES;
		size_t n = size_t(r.x1 - r.x0) * PAINT_ENTRIES;
		std::memset(PI + o, 0, n);
		std::memset(PW + o, 0, n);
	}
	for (size_t k = 0; k < coats.size(); k++) {
		Rect b = bounds[k].inter(r);
		if (b.empty()) {
			continue;
		}
		if (paths[k]) {
			int surface = int(coats[k]->d[1]);
			if (surface >= 0 && surface < PAINT_ERASE) {
				path_coat(*paths[k], surface, g, b, PI, PW);
			}
		} else {
			paint_coat(*coats[k], g, b, PI, PW);
		}
	}
}

static bool paint_bounds(const Prim &p, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	bool any = false;
	for (size_t k = PAINT_HEADER; k + PAINT_STRIDE <= p.d.size(); k += PAINT_STRIDE) {
		double rad = p.d[k + 4];
		x0 = std::min(x0, std::min(double(p.d[k]), double(p.d[k + 2])) - rad);
		z0 = std::min(z0, std::min(double(p.d[k + 1]), double(p.d[k + 3])) - rad);
		x1 = std::max(x1, std::max(double(p.d[k]), double(p.d[k + 2])) + rad);
		z1 = std::max(z1, std::max(double(p.d[k + 1]), double(p.d[k + 3])) + rad);
		any = true;
	}
	if (!any) {
		x0 = z0 = x1 = z1 = 0.0;
	}
	return true;
}

static void paint_apply(const Prim &p, const Grid &g, const Rect &r, const StampOut &out) {
	paint_coat(p, g, r, out.PI, out.PW);
}

TERRA_KIND(8, "paint", STAGE_PAINT, PAINT_HEADER, PAINT_STRIDE, paint_bounds, paint_apply);

} // namespace terra
