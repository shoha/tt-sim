// TerraDerive: setup, primitives and their seeds, rules, queries and digests (from spike
// terraform-s2-cpu). The stage loop is in terra_derive_stages.cpp. See terra_derive.h and
// docs/systems/terraform.md.
#include "terra_derive.h"

#include <chrono>
#include <cstring>
#include <initializer_list>
#include <unordered_map>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include "terra_kernels.h"
#include "terra_pool.h"

namespace terra {

/// One derive's state: where each array changed (inputs: the pending edits' seeds), each stage's
/// own seeds from its solve, the primitives grouped by stage, and the solves' flags.
struct Pass {
	bool full = false;
	Dirty changed[A_COUNT];
	Dirty own[S_COUNT];
	Dirty hit; // the current solve's per-sample reads' change
	std::vector<const Prim *> compose_p, river_p, pond_p, paint_p;
	std::vector<const ComposeKernel *> compose_k;
	std::vector<Rect> compose_r;
	bool falls_changed = false, walls_changed = false;
	int solved = 0;
};

/// Copies the samples of r (`bytes` each) of a whole-map array into out, row by row.
static void snap_bytes(const uint8_t *a, int bytes, const Grid &g, const Rect &r, std::vector<uint8_t> &out) {
	size_t rw = size_t(r.x1 - r.x0) * bytes;
	out.resize(size_t(r.area()) * bytes);
	for (int j = r.y0; j < r.y1; j++) {
		std::memcpy(&out[size_t(j - r.y0) * rw], &a[(int64_t(j) * g.w + r.x0) * bytes], rw);
	}
}

/// The bounding rect of the samples of r where a differs, bit for bit, from the snapshot.
static Rect diff_bytes(const uint8_t *a, int bytes, const Grid &g, const Rect &r, const std::vector<uint8_t> &old) {
	size_t rw = size_t(r.x1 - r.x0) * bytes;
	Rect c{ 1 << 30, 1 << 30, -(1 << 30), -(1 << 30) };
	for (int j = r.y0; j < r.y1; j++) {
		const uint8_t *row = &a[int64_t(j) * g.w * bytes];
		const uint8_t *orow = &old[size_t(j - r.y0) * rw];
		for (int i = r.x0; i < r.x1; i++) {
			if (std::memcmp(&row[int64_t(i) * bytes], &orow[size_t(i - r.x0) * bytes], bytes) != 0) {
				c.x0 = std::min(c.x0, i);
				c.y0 = std::min(c.y0, j);
				c.x1 = std::max(c.x1, i + 1);
				c.y1 = std::max(c.y1, j + 1);
			}
		}
	}
	return c.empty() ? Rect{} : c;
}

static uint64_t fnv(const void *data, size_t n, uint64_t h = 1469598103934665603ull) {
	const uint8_t *p = static_cast<const uint8_t *>(data);
	for (size_t i = 0; i < n; i++) {
		h ^= p[i];
		h *= 1099511628211ull;
	}
	return h;
}

} // namespace terra

using namespace terra;

namespace godot {

using Clock = std::chrono::steady_clock;

static int64_t us_since(Clock::time_point t) {
	return std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() - t).count();
}

TerraDerive::TerraDerive() {}

TerraDerive::~TerraDerive() {
	if (async_thread.joinable()) {
		async_thread.join();
	}
}

void TerraDerive::derive_async() {
	if (async_running) {
		return;
	}
	async_running = true;
	async_done.store(false);
	async_thread = std::thread([this] {
		async_result = derive();
		async_done.store(true);
	});
}

bool TerraDerive::is_busy() const {
	return async_running && !async_done.load();
}

Dictionary TerraDerive::take_result() {
	if (!async_running || !async_done.load()) {
		return Dictionary();
	}
	async_thread.join();
	async_running = false;
	Dictionary out = async_result;
	async_result = Dictionary();
	return out;
}

Dictionary TerraDerive::tile_collision(int64_t tile, int64_t stride) const {
	int ix = int(tile % g.tx), iy = int(tile / g.tx);
	int i0 = ix * TILE, j0 = iy * TILE, st = int(std::max<int64_t>(stride, 1));
	int nw = (std::min(TILE + 1, g.w - i0) - 1) / st + 1, nd = (std::min(TILE + 1, g.h - j0) - 1) / st + 1;
	PackedFloat32Array hts;
	hts.resize(int64_t(nw) * nd);
	float *dst = hts.ptrw();
	float lo = 1e30f, hi = -1e30f;
	for (int j = 0; j < nd; j++) {
		for (int i = 0; i < nw; i++) {
			float v = H2[int64_t(j0 + j * st) * g.w + i0 + i * st];
			dst[j * nw + i] = v;
			lo = std::min(lo, v);
			hi = std::max(hi, v);
		}
	}
	Dictionary out;
	out["w"] = nw;
	out["d"] = nd;
	out["heights"] = hts;
	out["min"] = lo;
	out["max"] = hi;
	out["step"] = Vector2(real_t(g.sx * st), real_t(g.sz * st));
	return out;
}

String TerraDerive::version() const {
	return "terra 2 stages";
}

Dictionary TerraDerive::grid() const {
	Dictionary out;
	out["w"] = g.w;
	out["h"] = g.h;
	out["step"] = Vector2(real_t(g.sx), real_t(g.sz));
	out["origin"] = Vector2(real_t(g.ox), real_t(g.oz));
	return out;
}

terra::DerivedView TerraDerive::derived() const {
	return terra::DerivedView{ g, H2, WL, SL, DW, DP, DF, PW, HB, CV, PM, FM, WM, PI, CT, water, walls };
}

void TerraDerive::set_threads(int64_t n) {
	threads = int(std::clamp<int64_t>(n, 0, 32));
	pool.reset(new Pool(threads));
}

void TerraDerive::setup(int64_t w, int64_t h, const Vector2 &extent) {
	// The document caps a map at 641 samples per axis, so a derive grid at 1281.
	w = std::clamp<int64_t>(w, 2, 4096);
	h = std::clamp<int64_t>(h, 2, 4096);
	g.init(int(w), int(h), double(extent.x), double(extent.y));
	size_t n = size_t(g.w) * size_t(g.h);
	for (std::vector<float> *a : { &Hraw, &SW, &H0, &H1, &WL, &Hp, &H2, &SL, &DW, &DP, &DF, &PW, &HB, &CV }) {
		a->assign(n, 0.0f);
	}
	for (std::vector<uint8_t> *a : { &PM, &FM, &WM, &PI }) {
		a->assign(n, 0);
	}
	CT.assign(n * 4, 0);
	prims.clear();
	water = Water();
	paths.clear();
	walls.clear();
	for (Dirty &d : seeds) {
		d.init(g);
	}
	changed_ids.clear();
	if (!pool) {
		pool.reset(new Pool(threads));
	}
}

int TerraDerive::find(int id) const {
	for (int i = 0; i < int(prims.size()); i++) {
		if (prims[i].id == id) {
			return i;
		}
	}
	return -1;
}

static void line_box(const std::vector<float> &d, int skip, double grow, double &x0, double &z0, double &x1,
		double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	for (size_t k = skip; k + 1 < d.size(); k += 2) {
		x0 = std::min(x0, double(d[k]) - grow);
		z0 = std::min(z0, double(d[k + 1]) - grow);
		x1 = std::max(x1, double(d[k]) + grow);
		z1 = std::max(z1, double(d[k + 1]) + grow);
	}
}

Rect TerraDerive::influence(const Prim &p) const {
	double x0 = 0, z0 = 0, x1 = 0, z1 = 0;
	if (p.d.empty()) {
		return Rect{};
	}
	switch (p.type) {
		case P_RIVER:
			line_box(p.d, 2, p.d[0] * 0.5 + CARVE_REACH_M, x0, z0, x1, z1);
			break;
		case P_POND:
			line_box(p.d, 1, POND_REACH + 0.5, x0, z0, x1, z1);
			break;
		case P_PATH:
			line_box(p.d, 1, p.d[0] * 0.5 + PATH_REACH_M, x0, z0, x1, z1);
			break;
		case P_WALL:
			line_box(p.d, 2, p.d.size() > 1 ? p.d[1] + PAD_REACH_M : PAD_REACH_M, x0, z0, x1, z1);
			break;
		case P_PAINT:
			dab_bounds(p, 4, x0, z0, x1, z1);
			break;
		default: {
			const ComposeKernel *k = compose_kernel(p.type);
			if (!k) {
				return Rect{};
			}
			if (!k->bounds(p, x0, z0, x1, z1)) {
				return g.all();
			}
		}
	}
	return g.rect_world(x0, z0, x1, z1);
}

void TerraDerive::seed(const Prim &p, const Rect &r) {
	switch (p.type) {
		case P_RIVER:
		case P_POND:
			seeds[A_WATER_PRIMS].add(r, g);
			changed_ids.insert(p.id);
			break;
		case P_PATH:
			seeds[A_PATH_PRIMS].add(r, g);
			changed_ids.insert(p.id);
			break;
		case P_WALL:
			seeds[A_WALL_PRIMS].add(r, g);
			changed_ids.insert(p.id);
			break;
		case P_PAINT:
			seeds[A_PAINT_PRIMS].add(r, g);
			break;
		default:
			seeds[A_COMPOSE_PRIMS].add(r, g);
	}
}

void TerraDerive::set_prim(int64_t id, int64_t type, const PackedFloat32Array &data) {
	Prim np;
	np.id = int(id);
	np.type = int(type);
	np.d.assign(data.ptr(), data.ptr() + data.size());
	int i = find(int(id));
	if (i >= 0) {
		Prim old = prims[i];
		seed(old, influence(old));
		prims[i] = np;
	} else {
		prims.push_back(np);
	}
	seed(np, influence(np));
}

void TerraDerive::append_dabs(int64_t id, const PackedFloat32Array &data) {
	int i = find(int(id));
	if (i < 0) {
		return;
	}
	Prim part;
	part.id = int(id);
	part.type = prims[i].type;
	part.d.assign(data.ptr(), data.ptr() + data.size());
	prims[i].d.insert(prims[i].d.end(), part.d.begin(), part.d.end());
	seed(part, influence(part));
}

void TerraDerive::remove_prim(int64_t id) {
	int i = find(int(id));
	if (i < 0) {
		return;
	}
	seed(prims[i], influence(prims[i]));
	prims.erase(prims.begin() + i);
}

void TerraDerive::clear_prims() {
	while (!prims.empty()) {
		remove_prim(prims.back().id);
	}
}

void TerraDerive::set_rules(const Array &rows) {
	rules.clear();
	for (int64_t r = 0; r < rows.size(); r++) {
		PackedFloat32Array row = rows[r];
		if (row.size() < 2) {
			continue;
		}
		Rule rule;
		rule.cls = int(row[0]);
		int n = int(row[1]);
		for (int k = 0; k < n && 2 + 4 * k + 3 < row.size(); k++) {
			Term t;
			t.field = std::clamp(int(row[2 + 4 * k]), 0, int(F_COUNT) - 1);
			t.lo = row[2 + 4 * k + 1];
			t.hi = row[2 + 4 * k + 2];
			t.soft = row[2 + 4 * k + 3];
			rule.terms.push_back(t);
		}
		rules.push_back(rule);
	}
	seed_rules = true;
}

void TerraDerive::seed_all() {
	for (int a = 0; a < A_COUNT; a++) {
		if (ARRAYS[a].kind == K_INPUT) {
			seeds[a].add(g.all(), g);
		}
	}
	seed_rules = true;
	for (const Prim &p : prims) {
		changed_ids.insert(p.id);
	}
	water = Water();
	paths.clear();
	walls.clear();
}

Dictionary TerraDerive::derive_full() {
	seed_all();
	return derive();
}

// Stage 2, the water solve: rebuilds the bodies, re-solves each body whose read points the change
// in H0 hits (or that an edit, a new shape or its receiver moved), keeps the others' levels, and
// marks where the levels record changed (a moved level range: its arc bbox grown by the carve's
// reach), on top of the edits' own seeds.
void TerraDerive::solve_water(Pass &ps) {
	const Dirty &hit = ps.hit;
	Dirty &moved = ps.changed[A_LEVELS];
	const bool full = ps.full;
	Water old = std::move(water);
	water = Water();
	water_geometry(water, ps.river_p, ps.pond_p, g);
	water_topology(water, g, H0.data());
	std::unordered_map<int, int> old_pond, old_river;
	for (int i = 0; i < int(old.ponds.size()); i++) {
		old_pond[old.ponds[i].id] = i;
	}
	for (int i = 0; i < int(old.rivers.size()); i++) {
		old_river[old.rivers[i].id] = i;
	}
	bool &falls_changed = ps.falls_changed;
	falls_changed = old.rivers.size() != water.rivers.size();
	int &solved = ps.solved;
	std::vector<char> pond_moved(water.ponds.size(), 0), river_moved(water.rivers.size(), 0);
	for (int i = 0; i < int(water.ponds.size()); i++) {
		Pond &p = water.ponds[i];
		auto it = old_pond.find(p.id);
		bool need = full || it == old_pond.end() || changed_ids.count(p.id) || hit.hits(p.sample_rect);
		if (need) {
			solve_pond(p, g, H0.data());
			solved++;
		} else {
			p.level = old.ponds[it->second].level;
		}
		if (it == old_pond.end() || std::memcmp(&p.level, &old.ponds[it->second].level, sizeof(float)) != 0) {
			pond_moved[i] = 1;
			moved.add(p.rect, g);
		}
	}
	auto recv_key = [](const Water &w, const River &r) {
		if (r.recv_pond >= 0) {
			return -1 - w.ponds[r.recv_pond].id;
		}
		return r.recv_river >= 0 ? w.rivers[r.recv_river].id : -(1 << 30);
	};
	for (int ri : water.order) {
		River &r = water.rivers[ri];
		auto it = old_river.find(r.id);
		const River *o = it == old_river.end() ? nullptr : &old.rivers[it->second];
		bool flipped = r.l.x[0] != r.drawn.x[0] || r.l.z[0] != r.drawn.z[0];
		bool same_shape = o && o->l.n() == r.l.n() && o->l.x == r.l.x && o->l.z == r.l.z;
		bool recv_moved = (r.recv_pond >= 0 && pond_moved[r.recv_pond]) ||
				(r.recv_river >= 0 && river_moved[r.recv_river]);
		bool need = full || !o || changed_ids.count(r.id) || !same_shape || recv_key(water, r) != recv_key(old, *o) ||
				recv_moved || reads_hit(hit, g, r.rx, r.rz);
		(void)flipped;
		if (need) {
			double recv = NAN;
			if (r.recv_pond >= 0) {
				recv = water.ponds[r.recv_pond].level;
			} else if (r.recv_river >= 0) {
				recv = river_level_at(water.rivers[r.recv_river], r.l.x.back(), r.l.z.back());
			}
			solve_river(r, g, H0.data(), recv);
			solved++;
		} else {
			r.level = o->level;
			r.falls = o->falls;
		}
		if (!o || !same_shape) {
			river_moved[ri] = 1;
			moved.add(r.rect, g);
			falls_changed = true;
			continue;
		}
		int k0 = -1, k1 = -1;
		for (int k = 0; k < r.l.n(); k++) {
			if (std::memcmp(&r.level[k], &o->level[k], sizeof(float)) != 0) {
				k0 = k0 < 0 ? k : k0;
				k1 = k;
			}
		}
		if (k0 >= 0) {
			river_moved[ri] = 1;
			double x0 = 1e30, z0 = 1e30, x1 = -1e30, z1 = -1e30;
			for (int k = std::max(0, k0 - 1); k <= std::min(r.l.n() - 1, k1 + 1); k++) {
				x0 = std::min(x0, r.l.x[k]);
				x1 = std::max(x1, r.l.x[k]);
				z0 = std::min(z0, r.l.z[k]);
				z1 = std::max(z1, r.l.z[k]);
			}
			double reach = r.hw + STAGES[S_CARVE].reach_m;
			moved.add(g.rect_world(x0 - reach, z0 - reach, x1 + reach, z1 + reach), g);
		}
		if (r.falls.size() != o->falls.size() || !std::equal(r.falls.begin(), r.falls.end(), o->falls.begin())) {
			falls_changed = true;
		}
	}
}

/// Adds to `into` the world bbox, grown by `reach` metres, of the points of `l` where the
/// per-point values a and b differ (and one point either side); false when none differ.
static bool line_change(const Grid &g, const Line &l, const std::vector<float> &a, const std::vector<float> &b,
		double reach, Dirty &into) {
	int k0 = -1, k1 = -1;
	for (int k = 0; k < l.n(); k++) {
		if (std::memcmp(&a[k], &b[k], sizeof(float)) != 0) {
			k0 = k0 < 0 ? k : k0;
			k1 = k;
		}
	}
	if (k0 < 0) {
		return false;
	}
	double x0 = 1e30, z0 = 1e30, x1 = -1e30, z1 = -1e30;
	for (int k = std::max(0, k0 - 1); k <= std::min(l.n() - 1, k1 + 1); k++) {
		x0 = std::min(x0, l.x[k]);
		x1 = std::max(x1, l.x[k]);
		z0 = std::min(z0, l.z[k]);
		z1 = std::max(z1, l.z[k]);
	}
	into.add(g.rect_world(x0 - reach, z0 - reach, x1 + reach, z1 + reach), g);
	return true;
}

// Stage 3b's line solve: rebuilds the paths, re-grades each one whose read points the change in
// H1 or WL hits (or that an edit or a new shape touched), and seeds the stage's own region where a
// profile moved (its arc bbox grown by the half width and the stage's reach).
void TerraDerive::solve_paths(Pass &ps) {
	const Dirty &hit = ps.hit;
	Dirty &own = ps.own[S_PATHS];
	const double reach = STAGES[S_PATHS].reach_m;
	std::vector<PathL> old_paths = std::move(paths);
	paths.clear();
	for (const Prim &p : prims) {
		if (p.type == P_PATH && p.d.size() >= 5) {
			PathL pl;
			path_geometry(pl, p, g);
			if (pl.l.n() >= 2) {
				paths.push_back(pl);
			}
		}
	}
	for (PathL &p : paths) {
		const PathL *o = nullptr;
		for (const PathL &q : old_paths) {
			if (q.id == p.id) {
				o = &q;
			}
		}
		bool same = o && o->l.x == p.l.x && o->l.z == p.l.z && o->hw == p.hw;
		if (ps.full || !same || changed_ids.count(p.id) || reads_hit(hit, g, p.rx, p.rz)) {
			solve_path(p, g, H1.data());
		} else {
			p.prof = o->prof;
		}
		if (same) {
			line_change(g, p.l, p.prof, o->prof, p.hw + reach, own);
		}
	}
}

// Stage 4's line solve: rebuilds the walls, re-solves each pad whose read points the change in Hp
// or WL hits (or that an edit or a new shape touched), and seeds the stage's own region where a
// pad or its solid runs moved (grown by the thickness and the stage's reach).
void TerraDerive::solve_walls(Pass &ps) {
	const Dirty &hit = ps.hit;
	Dirty &own = ps.own[S_FOOTPRINTS];
	const double reach = STAGES[S_FOOTPRINTS].reach_m;
	const bool full = ps.full;
	std::vector<Wall> old_walls = std::move(walls);
	walls.clear();
	for (const Prim &p : prims) {
		if (p.type == P_WALL && p.d.size() >= 6) {
			Wall wl;
			wall_geometry(wl, p, g);
			if (wl.l.n() >= 2) {
				walls.push_back(wl);
			}
		}
	}
	bool &walls_changed = ps.walls_changed;
	walls_changed = old_walls.size() != walls.size();
	for (Wall &w : walls) {
		const Wall *o = nullptr;
		for (const Wall &q : old_walls) {
			if (q.id == w.id) {
				o = &q;
			}
		}
		bool same = o && o->l.x == w.l.x && o->l.z == w.l.z && o->thick == w.thick && o->height == w.height;
		if (full || !same || changed_ids.count(w.id) || reads_hit(hit, g, w.rx, w.rz)) {
			solve_wall(w, g, Hp.data(), WL.data());
		} else {
			w.pad = o->pad;
			w.solid = o->solid;
		}
		if (!same) {
			walls_changed = true;
			continue;
		}
		std::vector<float> sa(w.solid.begin(), w.solid.end()), sb(o->solid.begin(), o->solid.end());
		bool moved = line_change(g, w.l, w.pad, o->pad, w.thick + reach, own);
		moved = line_change(g, w.l, sa, sb, w.thick + reach, own) || moved;
		walls_changed = walls_changed || moved;
	}
}
uint8_t *TerraDerive::array_data(int a) {
	switch (a) {
		case A_HRAW:
			return reinterpret_cast<uint8_t *>(Hraw.data());
		case A_SW:
			return reinterpret_cast<uint8_t *>(SW.data());
		case A_H0:
			return reinterpret_cast<uint8_t *>(H0.data());
		case A_H1:
			return reinterpret_cast<uint8_t *>(H1.data());
		case A_WL:
			return reinterpret_cast<uint8_t *>(WL.data());
		case A_HP:
			return reinterpret_cast<uint8_t *>(Hp.data());
		case A_PM:
			return PM.data();
		case A_H2:
			return reinterpret_cast<uint8_t *>(H2.data());
		case A_FM:
			return FM.data();
		case A_WM:
			return WM.data();
		case A_SL:
			return reinterpret_cast<uint8_t *>(SL.data());
		case A_DW:
			return reinterpret_cast<uint8_t *>(DW.data());
		case A_DP:
			return reinterpret_cast<uint8_t *>(DP.data());
		case A_DF:
			return reinterpret_cast<uint8_t *>(DF.data());
		case A_HB:
			return reinterpret_cast<uint8_t *>(HB.data());
		case A_CV:
			return reinterpret_cast<uint8_t *>(CV.data());
		case A_PI:
			return PI.data();
		case A_PW:
			return reinterpret_cast<uint8_t *>(PW.data());
		case A_CT:
			return CT.data();
		default:
			return nullptr;
	}
}

void TerraDerive::rect_body(int stage, const Rect &r, const Pass &ps) {
	switch (stage) {
		case S_COMPOSE:
			compose_rect(ps.compose_p, ps.compose_k, ps.compose_r, g, r, Hraw.data(), SW.data());
			break;
		case S_SMOOTH:
			smooth_rect(g, r, Hraw.data(), SW.data(), H0.data());
			break;
		case S_CARVE:
			carve_rect(water, g, r, H0.data(), H1.data(), WL.data());
			break;
		case S_PATHS:
			path_rect(paths, g, r, H1.data(), WL.data(), Hp.data(), PM.data());
			break;
		case S_FOOTPRINTS:
			pad_rect(walls, g, r, Hp.data(), WL.data(), H2.data(), FM.data(), WM.data());
			break;
		case S_SLOPE:
			slope_rect(g, r, H2.data(), SL.data());
			break;
		case S_DISTANCES:
			edt_rect(g, r, WM.data(), DIST_CAP_WATER, DW.data());
			edt_rect(g, r, PM.data(), DIST_CAP_PATH, DP.data());
			edt_rect(g, r, FM.data(), DIST_CAP_FOOT, DF.data());
			break;
		case S_LOOK:
			look_rect(g, r, H2.data(), HB.data(), CV.data());
			break;
		case S_PAINT:
			paint_rect(ps.paint_p, g, r, PI.data(), PW.data());
			break;
		case S_RULES: {
			FieldInputs in{ H2.data(), WL.data(), SL.data(), DW.data(), DP.data(), DF.data(), PW.data(), PM.data(),
				PI.data(), CV.data() };
			rules_rect(rules, g, r, in, CT.data());
			break;
		}
		default:
			break;
	}
}

int TerraDerive::run_rect(const StageDef &s, const Dirty &region, Pass &ps) {
	std::vector<int> outs;
	for (int a = 0; a < A_COUNT; a++) {
		if ((s.writes & bit(a)) && ARRAYS[a].kind == K_SAMPLES) {
			outs.push_back(a);
			ps.changed[a].init(g);
		}
	}
	std::vector<int> tiles = region.tiles();
	pool->run(int(tiles.size()), [&](int k) {
		int t = tiles[k];
		const Rect &r = region.t[t];
		std::vector<std::vector<uint8_t>> old(outs.size());
		for (size_t q = 0; q < outs.size(); q++) {
			snap_bytes(array_data(outs[q]), ARRAYS[outs[q]].bytes, g, r, old[q]);
		}
		rect_body(s.id, r, ps);
		for (size_t q = 0; q < outs.size(); q++) {
			ps.changed[outs[q]].t[t] = diff_bytes(array_data(outs[q]), ARRAYS[outs[q]].bytes, g, r, old[q]);
		}
	});
	return int(tiles.size());
}

Dictionary TerraDerive::derive() {
	Clock::time_point t_all = Clock::now();
	Pass ps;
	ps.full = seed_rules && seeds[A_COMPOSE_PRIMS].samples() == int64_t(g.w) * g.h;
	if (seed_rules) {
		seeds[A_RULE_TABLE].add(g.all(), g);
	}
	for (int a = 0; a < A_COUNT; a++) {
		ps.changed[a].init(g);
		if (ARRAYS[a].kind == K_INPUT) {
			ps.changed[a] = seeds[a];
		}
	}
	for (Dirty &d : ps.own) {
		d.init(g);
	}
	for (const Prim &p : prims) {
		if (p.type == P_RIVER) {
			ps.river_p.push_back(&p);
		} else if (p.type == P_POND) {
			ps.pond_p.push_back(&p);
		} else if (p.type == P_PAINT) {
			ps.paint_p.push_back(&p);
		} else if (const ComposeKernel *k = compose_kernel(p.type)) {
			ps.compose_p.push_back(&p);
			ps.compose_k.push_back(k);
			ps.compose_r.push_back(influence(p));
		}
	}
	Dirty all;
	all.init(g);
	all.add(g.all(), g);
	Dictionary usec, work;
	for (const StageDef &s : STAGES) {
		Clock::time_point t0 = Clock::now();
		if (s.shape != SHAPE_RECT) {
			ps.hit = stage_read_change(s, ps.changed, g);
		}
		switch (s.id) {
			case S_WATER:
				// The record changed where the edits touched a body, and where the solve moves a level.
				ps.changed[A_LEVELS] = ps.changed[A_WATER_PRIMS];
				solve_water(ps);
				work["water_solved"] = ps.solved;
				break;
			case S_PATHS:
				solve_paths(ps);
				break;
			case S_FOOTPRINTS:
				solve_walls(ps);
				break;
			default:
				break;
		}
		if (s.shape != SHAPE_GRAPH) {
			work[s.name] = run_rect(s, ps.full ? all : stage_region(s, ps.changed, ps.own[s.id], g), ps);
		}
		// A sample set from outside the chain (debug_set_sample) counts as changed by its writer.
		for (int a = 0; a < A_COUNT; a++) {
			if ((s.writes & bit(a)) && ARRAYS[a].kind == K_SAMPLES) {
				ps.changed[a].merge(seeds[a], g);
			}
		}
		usec[s.name] = us_since(t0);
	}

	auto tiles_of = [&](Dirty d) {
		Dirty grown = d.dilate(1, g);
		std::vector<int> t = grown.tiles();
		PackedInt32Array out;
		for (int v : t) {
			out.push_back(v);
		}
		return out;
	};
	auto changed_in = [&](std::initializer_list<int> arrays) {
		Dirty d;
		d.init(g);
		for (int a : arrays) {
			d.merge(ps.changed[a], g);
		}
		return d;
	};
	const Dirty &chg5 = ps.changed[A_H2];
	Dirty hz = changed_in({ A_H2, A_H1, A_WL });
	Dictionary out;
	out["tiles_height"] = tiles_of(hz);
	out["tiles_control"] = tiles_of(ps.changed[A_CT]);
	out["tiles_fields"] = tiles_of(changed_in({ A_SL, A_DW, A_DP, A_DF }));
	out["tiles_look"] = tiles_of(changed_in({ A_HB, A_CV }));
	// Collision tiles hold samples [64 t, 64 t + 65): a changed ground sample is in its own tile,
	// and in the tile before it on an axis where it is that tile's shared last row or column.
	{
		std::vector<char> mark(g.ntiles(), 0);
		for (int t = 0; t < g.ntiles(); t++) {
			const Rect &c = chg5.t[t];
			if (c.empty()) {
				continue;
			}
			int ix = t % g.tx, iy = t / g.tx;
			bool left = ix > 0 && c.x0 == ix * TILE, up = iy > 0 && c.y0 == iy * TILE;
			mark[t] = 1;
			mark[t - (left ? 1 : 0)] = 1;
			mark[t - (up ? g.tx : 0)] = 1;
			mark[t - (left ? 1 : 0) - (up ? g.tx : 0)] = 1;
		}
		PackedInt32Array tc;
		for (int t = 0; t < g.ntiles(); t++) {
			if (mark[t]) {
				tc.push_back(t);
			}
		}
		out["tiles_collision"] = tc;
	}
	out["falls_changed"] = ps.falls_changed || ps.full;
	out["walls_changed"] = ps.walls_changed || ps.full;
	out["changed_samples"] = hz.samples();
	usec["total"] = us_since(t_all);
	out["usec"] = usec;
	out["work"] = work;

	for (Dirty &d : seeds) {
		d.clear();
	}
	seed_rules = false;
	changed_ids.clear();
	return out;
}

int64_t TerraDerive::tiles_x() const {
	return g.tx;
}

int64_t TerraDerive::tiles_y() const {
	return g.ty;
}

PackedByteArray TerraDerive::tile_bytes(int64_t tile, int64_t kind) const {
	constexpr int L = TILE + 2;
	PackedByteArray out;
	if (tile < 0 || tile >= g.ntiles()) {
		return out;
	}
	int bpp = kind == 0 || kind == 3 ? 8 : 4;
	out.resize(L * L * bpp);
	uint8_t *w = out.ptrw();
	int ox = int(tile % g.tx) * TILE - 1, oy = int(tile / g.tx) * TILE - 1;
	for (int ly = 0; ly < L; ly++) {
		int y = std::clamp(oy + ly, 0, g.h - 1);
		for (int lx = 0; lx < L; lx++) {
			int x = std::clamp(ox + lx, 0, g.w - 1);
			int64_t o = int64_t(y) * g.w + x;
			uint8_t *p = w + (ly * L + lx) * bpp;
			if (kind == 0) {
				std::memcpy(p, &H2[o], 4);
				std::memcpy(p + 4, &WL[o], 4);
			} else if (kind == 1) {
				std::memcpy(p, &CT[o * 4], 4);
			} else if (kind == 3) {
				std::memcpy(p, &HB[o], 4);
				std::memcpy(p + 4, &CV[o], 4);
			} else {
				p[0] = unit_u8(DW[o] / 6.0);
				p[1] = unit_u8(DP[o] / 3.0);
				p[2] = unit_u8(DF[o] / 3.0);
				p[3] = unit_u8(SL[o] / 90.0);
			}
		}
	}
	return out;
}

bool TerraDerive::tile_has_water(int64_t tile) const {
	if (tile < 0 || tile >= g.ntiles()) {
		return false;
	}
	Rect r = g.tile_rect(int(tile)).grow(1).clip(g.w, g.h);
	for (int j = r.y0; j < r.y1; j++) {
		for (int i = r.x0; i < r.x1; i++) {
			if (WM[int64_t(j) * g.w + i]) {
				return true;
			}
		}
	}
	return false;
}

double TerraDerive::height_at(double x, double z) const {
	return g.w > 1 ? g.bilinear(H2.data(), x, z) : 0.0;
}

double TerraDerive::water_at(double x, double z) const {
	return g.w > 1 ? g.bilinear(WL.data(), x, z) : 0.0;
}

Dictionary TerraDerive::raycast(const Vector3 &from, const Vector3 &dir, double max_dist) const {
	Dictionary out;
	out["hit"] = false;
	Vector3 d = dir.normalized();
	double step = 0.1, prev = 0.0;
	for (double t = 0.0; t <= max_dist; t += step) {
		Vector3 p = from + d * t;
		if (p.y <= height_at(p.x, p.z)) {
			double a = prev, b = t;
			for (int k = 0; k < 16; k++) {
				double m = (a + b) * 0.5;
				Vector3 q = from + d * m;
				if (q.y <= height_at(q.x, q.z)) {
					b = m;
				} else {
					a = m;
				}
			}
			Vector3 hit = from + d * b;
			out["hit"] = true;
			out["pos"] = Vector3(hit.x, height_at(hit.x, hit.z), hit.z);
			return out;
		}
		prev = t;
	}
	return out;
}

PackedFloat32Array TerraDerive::falls() const {
	PackedFloat32Array out;
	for (const River &r : water.rivers) {
		for (const Fall &f : r.falls) {
			for (double v : { f.x, f.z, f.tx, f.tz, f.top, f.bottom, f.width }) {
				out.push_back(float(v));
			}
		}
	}
	return out;
}

Array TerraDerive::walls_out() const {
	Array out;
	for (const Wall &w : walls) {
		Dictionary d;
		d["id"] = w.id;
		d["height"] = w.height;
		d["thick"] = w.thick;
		PackedFloat32Array pts;
		for (int k = 0; k < w.l.n(); k++) {
			pts.push_back(float(w.l.x[k]));
			pts.push_back(float(w.l.z[k]));
			pts.push_back(k < int(w.pad.size()) ? w.pad[k] : 0.0f);
			pts.push_back(k < int(w.solid.size()) ? float(w.solid[k]) : 1.0f);
		}
		d["pts"] = pts;
		out.push_back(d);
	}
	return out;
}

static PackedStringArray array_names(uint32_t mask) {
	PackedStringArray out;
	for (int a = 0; a < A_COUNT; a++) {
		if (mask & bit(a)) {
			out.push_back(ARRAYS[a].name);
		}
	}
	return out;
}

static int array_id(const String &name) {
	for (int a = 0; a < A_COUNT; a++) {
		if (name == ARRAYS[a].name) {
			return a;
		}
	}
	return -1;
}

Array TerraDerive::stages() const {
	static const char *SHAPES[] = { "rect", "graph", "line_rect" };
	Array out;
	for (const StageDef &s : STAGES) {
		Dictionary d;
		d["name"] = s.name;
		d["shape"] = SHAPES[s.shape];
		d["reads"] = array_names(s.reads);
		d["writes"] = array_names(s.writes);
		d["halo"] = s.halo;
		d["reach_m"] = s.reach_m;
		out.push_back(d);
	}
	return out;
}

Array TerraDerive::arrays() const {
	static const char *KINDS[] = { "input", "samples", "record" };
	Array out;
	for (const ArrayDef &a : ARRAYS) {
		Dictionary d;
		d["name"] = a.name;
		d["kind"] = KINDS[a.kind];
		d["bytes"] = a.bytes;
		out.push_back(d);
	}
	return out;
}

PackedByteArray TerraDerive::array_bytes(const String &name) {
	PackedByteArray out;
	int a = array_id(name);
	if (a < 0 || ARRAYS[a].kind != K_SAMPLES || g.w <= 0) {
		return out;
	}
	int64_t n = int64_t(g.w) * g.h * ARRAYS[a].bytes;
	out.resize(n);
	std::memcpy(out.ptrw(), array_data(a), size_t(n));
	return out;
}

void TerraDerive::debug_set_sample(const String &name, int64_t i, int64_t j, double value, bool dirty_all) {
	int a = array_id(name);
	if (a < 0 || ARRAYS[a].kind != K_SAMPLES || a == A_CT || i < 0 || j < 0 || i >= g.w || j >= g.h) {
		return;
	}
	int64_t o = j * g.w + i;
	if (ARRAYS[a].bytes == 4) {
		reinterpret_cast<float *>(array_data(a))[o] = float(value);
	} else {
		array_data(a)[o] = uint8_t(std::clamp(value, 0.0, 255.0));
	}
	seeds[a].add(dirty_all ? g.all() : Rect{ int(i), int(j), int(i) + 1, int(j) + 1 }, g);
}

Dictionary TerraDerive::digests() const {
	Dictionary out;
	auto put = [&](const char *name, const auto &v) {
		out[name] = int64_t(fnv(v.data(), v.size() * sizeof(v[0])));
	};
	put("Hraw", Hraw);
	put("SW", SW);
	put("H0", H0);
	put("H1", H1);
	put("WL", WL);
	put("Hp", Hp);
	put("H2", H2);
	put("SL", SL);
	put("DW", DW);
	put("DP", DP);
	put("DF", DF);
	put("PW", PW);
	put("HB", HB);
	put("CV", CV);
	put("PM", PM);
	put("FM", FM);
	put("WM", WM);
	put("PI", PI);
	put("CT", CT);
	PackedFloat32Array f = falls();
	out["falls"] = int64_t(fnv(f.ptr(), size_t(f.size()) * 4));
	uint64_t wh = 1469598103934665603ull;
	for (const Wall &w : walls) {
		wh = fnv(w.pad.data(), w.pad.size() * 4, wh);
		wh = fnv(w.solid.data(), w.solid.size(), wh);
	}
	out["walls"] = int64_t(wh);
	return out;
}

int64_t TerraDerive::memory_bytes() const {
	int64_t n = 0;
	for (const std::vector<float> *a : { &Hraw, &SW, &H0, &H1, &WL, &Hp, &H2, &SL, &DW, &DP, &DF, &PW, &HB, &CV }) {
		n += int64_t(a->capacity()) * 4;
	}
	for (const std::vector<uint8_t> *a : { &PM, &FM, &WM, &PI, &CT }) {
		n += int64_t(a->capacity());
	}
	for (const Prim &p : prims) {
		n += int64_t(p.d.capacity()) * 4 + int64_t(sizeof(Prim));
	}
	return n;
}

Dictionary TerraDerive::water_records() const {
	Dictionary out;
	Array rivers;
	for (const River &r : water.rivers) {
		Dictionary d;
		d["id"] = r.id;
		PackedFloat32Array lv;
		for (float v : r.level) {
			lv.push_back(v);
		}
		d["level"] = lv;
		d["falls"] = int64_t(r.falls.size());
		// The downstream line the levels belong to, and the half width.
		PackedFloat32Array pts;
		for (int k = 0; k < r.l.n(); k++) {
			pts.push_back(float(r.l.x[k]));
			pts.push_back(float(r.l.z[k]));
		}
		d["pts"] = pts;
		d["hw"] = r.hw;
		d["recv_river"] = r.recv_river >= 0 ? water.rivers[r.recv_river].id : -1;
		d["recv_pond"] = r.recv_pond >= 0 ? water.ponds[r.recv_pond].id : -1;
		rivers.push_back(d);
	}
	out["rivers"] = rivers;
	Array ponds;
	for (const Pond &p : water.ponds) {
		Dictionary d;
		d["id"] = p.id;
		d["level"] = p.level;
		ponds.push_back(d);
	}
	out["ponds"] = ponds;
	return out;
}

void TerraDerive::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &TerraDerive::version);
	ClassDB::bind_method(D_METHOD("setup", "w", "h", "extent"), &TerraDerive::setup);
	ClassDB::bind_method(D_METHOD("set_threads", "n"), &TerraDerive::set_threads);
	ClassDB::bind_method(D_METHOD("set_prim", "id", "type", "data"), &TerraDerive::set_prim);
	ClassDB::bind_method(D_METHOD("append_dabs", "id", "data"), &TerraDerive::append_dabs);
	ClassDB::bind_method(D_METHOD("remove_prim", "id"), &TerraDerive::remove_prim);
	ClassDB::bind_method(D_METHOD("clear_prims"), &TerraDerive::clear_prims);
	ClassDB::bind_method(D_METHOD("set_rules", "rows"), &TerraDerive::set_rules);
	ClassDB::bind_method(D_METHOD("derive"), &TerraDerive::derive);
	ClassDB::bind_method(D_METHOD("derive_full"), &TerraDerive::derive_full);
	ClassDB::bind_method(D_METHOD("derive_async"), &TerraDerive::derive_async);
	ClassDB::bind_method(D_METHOD("is_busy"), &TerraDerive::is_busy);
	ClassDB::bind_method(D_METHOD("take_result"), &TerraDerive::take_result);
	ClassDB::bind_method(D_METHOD("tile_collision", "tile", "stride"), &TerraDerive::tile_collision);
	ClassDB::bind_method(D_METHOD("tiles_x"), &TerraDerive::tiles_x);
	ClassDB::bind_method(D_METHOD("tiles_y"), &TerraDerive::tiles_y);
	ClassDB::bind_method(D_METHOD("tile_bytes", "tile", "kind"), &TerraDerive::tile_bytes);
	ClassDB::bind_method(D_METHOD("tile_has_water", "tile"), &TerraDerive::tile_has_water);
	ClassDB::bind_method(D_METHOD("height_at", "x", "z"), &TerraDerive::height_at);
	ClassDB::bind_method(D_METHOD("water_at", "x", "z"), &TerraDerive::water_at);
	ClassDB::bind_method(D_METHOD("raycast", "from", "dir", "max_dist"), &TerraDerive::raycast);
	ClassDB::bind_method(D_METHOD("falls"), &TerraDerive::falls);
	ClassDB::bind_method(D_METHOD("walls"), &TerraDerive::walls_out);
	ClassDB::bind_method(D_METHOD("digests"), &TerraDerive::digests);
	ClassDB::bind_method(D_METHOD("memory_bytes"), &TerraDerive::memory_bytes);
	ClassDB::bind_method(D_METHOD("water_records"), &TerraDerive::water_records);
	ClassDB::bind_method(D_METHOD("grid"), &TerraDerive::grid);
	ClassDB::bind_method(D_METHOD("stages"), &TerraDerive::stages);
	ClassDB::bind_method(D_METHOD("arrays"), &TerraDerive::arrays);
	ClassDB::bind_method(D_METHOD("array_bytes", "name"), &TerraDerive::array_bytes);
	ClassDB::bind_method(
			D_METHOD("debug_set_sample", "name", "i", "j", "value", "dirty_all"), &TerraDerive::debug_set_sample);
}

} // namespace godot
