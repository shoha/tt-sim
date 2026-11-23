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

size_t dab_count(const Prim &p) {
	return p.d.size() < size_t(PAINT_HEADER) ? 0 : (p.d.size() - PAINT_HEADER) / PAINT_STRIDE;
}

// Where the entries before a coat are read: `stride` samples a row from sample (x0, y0) on.
struct Before {
	const uint8_t *pi, *pw;
	int x0, y0, stride;
	int64_t at(int i, int j) const { return (int64_t(j - y0) * stride + (i - x0)) * PAINT_ENTRIES; }
};

// The coat's dabs [from, to) over the samples of `r`, on its per-sample state over `sr` (which
// holds r; val, last and hit are sr's samples, row-major): the stored coverage (float32, as
// SurfaceStroke keeps it between dabs), the last dab's unrounded value, and whether a dab reached
// the sample. A sample's first hit starts from the entries before the coat (`bf`).
void coat_dabs(const Prim &p, size_t from, size_t to, const Grid &g, const Rect &r, const Rect &sr, const Before &bf,
		float *val, double *last, uint8_t *hit) {
	int mine = int(p.d[0]);
	bool erase = mine == PAINT_ERASE;
	DocFrame f = doc_frame(g);
	int sw = sr.x1 - sr.x0;
	float table[AMOUNT_STEPS];
	double table_seconds = -1.0;
	for (size_t d = from; d < to; d++) {
		size_t k = PAINT_HEADER + d * PAINT_STRIDE;
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
				size_t q = size_t(j - sr.y0) * sw + (i - sr.x0);
				if (!hit[q]) {
					hit[q] = 1;
					const uint8_t *pi = bf.pi + bf.at(i, j);
					const uint8_t *pw = bf.pw + bf.at(i, j);
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
}

// Items [k0, k1) of the paint stage over r, on planes that hold the items before k0 there.
void items_over(const std::vector<const Prim *> &coats, const std::vector<const PathL *> &paths,
		const std::vector<Rect> &bounds, size_t k0, size_t k1, const Grid &g, const Rect &r, uint8_t *PI,
		uint8_t *PW) {
	for (size_t k = k0; k < k1; k++) {
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

void clear_rows(const Grid &g, const Rect &r, uint8_t *PI, uint8_t *PW) {
	for (int j = r.y0; j < r.y1; j++) {
		int64_t o = (int64_t(j) * g.w + r.x0) * PAINT_ENTRIES;
		size_t n = size_t(r.x1 - r.x0) * PAINT_ENTRIES;
		std::memset(PI + o, 0, n);
		std::memset(PW + o, 0, n);
	}
}

// A tile's block: the entries before coat `c` over the whole tile (the items before it run on the
// planes there, which are then put back: outside the stage's rect they hold the last derive's
// bytes) and an empty coat state.
std::unique_ptr<CoatCache::Block> build_block(const std::vector<const Prim *> &coats,
		const std::vector<const PathL *> &paths, const std::vector<Rect> &bounds, size_t c, const Grid &g,
		const Rect &tr, uint8_t *PI, uint8_t *PW) {
	int tw = tr.x1 - tr.x0;
	size_t n = size_t(tr.area());
	size_t row = size_t(tw) * PAINT_ENTRIES;
	std::unique_ptr<CoatCache::Block> b(new CoatCache::Block());
	b->bpi.resize(n * PAINT_ENTRIES);
	b->bpw.resize(n * PAINT_ENTRIES);
	b->val.assign(n, 0.0f);
	b->last.assign(n, 0.0);
	b->hit.assign(n, 0);
	std::vector<uint8_t> keep_i(n * PAINT_ENTRIES), keep_w(n * PAINT_ENTRIES);
	for (int j = tr.y0; j < tr.y1; j++) {
		int64_t o = (int64_t(j) * g.w + tr.x0) * PAINT_ENTRIES;
		size_t q = size_t(j - tr.y0) * row;
		std::memcpy(&keep_i[q], PI + o, row);
		std::memcpy(&keep_w[q], PW + o, row);
	}
	clear_rows(g, tr, PI, PW);
	items_over(coats, paths, bounds, 0, c, g, tr, PI, PW);
	for (int j = tr.y0; j < tr.y1; j++) {
		int64_t o = (int64_t(j) * g.w + tr.x0) * PAINT_ENTRIES;
		size_t q = size_t(j - tr.y0) * row;
		std::memcpy(&b->bpi[q], PI + o, row);
		std::memcpy(&b->bpw[q], PW + o, row);
		std::memcpy(PI + o, &keep_i[q], row);
		std::memcpy(PW + o, &keep_w[q], row);
	}
	return b;
}

} // namespace

int64_t CoatCache::memory_bytes() const {
	int64_t n = int64_t(blocks.capacity()) * int64_t(sizeof(blocks[0]));
	for (const std::unique_ptr<Block> &b : blocks) {
		if (b) {
			n += int64_t(sizeof(Block)) + int64_t(b->bpi.capacity() + b->bpw.capacity() + b->hit.capacity()) +
					int64_t(b->val.capacity()) * 4 + int64_t(b->last.capacity()) * 8;
		}
	}
	return n;
}

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
	int rw = r.x1 - r.x0, rh = r.y1 - r.y0;
	std::vector<float> val(size_t(rw) * rh, 0.0f);
	std::vector<double> last(size_t(rw) * rh, 0.0);
	std::vector<uint8_t> hit(size_t(rw) * rh, 0);
	coat_dabs(p, 0, dab_count(p), g, r, r, Before{ PI, PW, 0, 0, g.w }, val.data(), last.data(), hit.data());
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
		const std::vector<Rect> &bounds, const Grid &g, const Rect &r, uint8_t *PI, uint8_t *PW, CoatCache *cache) {
	clear_rows(g, r, PI, PW);
	// The cached coat's place, when the cache serves this rect: a coat (not a path's surface) at the
	// place the blocks were built for, and r inside one tile.
	size_t c = coats.size();
	int t = -1;
	Rect tr;
	if (cache && cache->id >= 0 && cache->index >= 0 && size_t(cache->index) < coats.size() &&
			int(cache->blocks.size()) == g.ntiles() && !r.empty()) {
		size_t k = size_t(cache->index);
		t = (r.y0 / TILE) * g.tx + r.x0 / TILE;
		tr = g.tile_rect(t);
		bool inside = r.x0 >= tr.x0 && r.y0 >= tr.y0 && r.x1 <= tr.x1 && r.y1 <= tr.y1;
		// Where the coat cannot reach, the plain run skips it: no block for a tile it never touches.
		bool reached = !bounds[k].inter(r).empty();
		if (!paths[k] && coats[k]->id == cache->id && inside && reached &&
				coats[k]->d.size() >= size_t(PAINT_HEADER)) {
			c = k;
		}
	}
	if (c == coats.size()) {
		items_over(coats, paths, bounds, 0, coats.size(), g, r, PI, PW);
		return;
	}
	const Prim &p = *coats[c];
	std::unique_ptr<CoatCache::Block> &slot = cache->blocks[t];
	if (!slot) {
		slot = build_block(coats, paths, bounds, c, g, tr, PI, PW);
	}
	CoatCache::Block &b = *slot;
	int tw = tr.x1 - tr.x0;
	// Only the dabs this tile has not seen yet, over the whole tile, so the block stays one state.
	size_t n = dab_count(p);
	if (size_t(b.n) < n) {
		coat_dabs(p, size_t(b.n), n, g, tr, tr, Before{ b.bpi.data(), b.bpw.data(), tr.x0, tr.y0, tw }, b.val.data(),
				b.last.data(), b.hit.data());
		b.n = int(n);
	}
	int mine = int(p.d[0]);
	bool erase = mine == PAINT_ERASE;
	size_t row = size_t(r.x1 - r.x0) * PAINT_ENTRIES;
	for (int j = r.y0; j < r.y1; j++) {
		int64_t o = (int64_t(j) * g.w + r.x0) * PAINT_ENTRIES;
		size_t q = (size_t(j - tr.y0) * tw + (r.x0 - tr.x0));
		std::memcpy(PI + o, &b.bpi[q * PAINT_ENTRIES], row);
		std::memcpy(PW + o, &b.bpw[q * PAINT_ENTRIES], row);
		for (int i = r.x0; i < r.x1; i++, q++) {
			if (b.hit[q]) {
				int64_t s = (int64_t(j) * g.w + i) * PAINT_ENTRIES;
				coat_entries(PI + s, PW + s, mine, erase, b.last[q]);
			}
		}
	}
	items_over(coats, paths, bounds, c + 1, coats.size(), g, r, PI, PW);
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

TERRA_KIND(KIND_PAINT, "paint", STAGE_PAINT, PAINT_HEADER, PAINT_STRIDE, paint_bounds, paint_apply);

} // namespace terra
