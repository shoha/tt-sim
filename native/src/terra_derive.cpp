// TerraDerive: the stage chain over dirty tiles (from spike terraform-s2-cpu). See terra_derive.h
// and docs/systems/terraform.md.
#include "terra_derive.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <functional>
#include <mutex>
#include <thread>
#include <unordered_map>

#include <godot_cpp/core/class_db.hpp>

#include "terra_kernels.h"

namespace terra {

/// A fixed set of worker threads that run one indexed job at a time; the caller joins in.
class Pool {
public:
	explicit Pool(int n) {
		for (int i = 0; i < n; i++) {
			workers.emplace_back([this] { loop(); });
		}
	}
	~Pool() {
		{
			std::lock_guard<std::mutex> lk(m);
			quit = true;
		}
		cv.notify_all();
		for (std::thread &t : workers) {
			t.join();
		}
	}
	void run(int count, const std::function<void(int)> &fn) {
		if (count <= 0) {
			return;
		}
		if (workers.empty() || count == 1) {
			for (int i = 0; i < count; i++) {
				fn(i);
			}
			return;
		}
		{
			std::lock_guard<std::mutex> lk(m);
			job = &fn;
			total = count;
			next.store(0);
			pending = int(workers.size());
			gen++;
		}
		cv.notify_all();
		work();
		std::unique_lock<std::mutex> lk(m);
		done.wait(lk, [&] { return pending == 0; });
		job = nullptr;
	}

private:
	void work() {
		int i;
		while ((i = next.fetch_add(1)) < total) {
			(*job)(i);
		}
	}
	void loop() {
		uint64_t seen = 0;
		while (true) {
			{
				std::unique_lock<std::mutex> lk(m);
				cv.wait(lk, [&] { return quit || gen != seen; });
				if (quit) {
					return;
				}
				seen = gen;
			}
			work();
			std::lock_guard<std::mutex> lk(m);
			if (--pending == 0) {
				done.notify_one();
			}
		}
	}
	std::vector<std::thread> workers;
	std::mutex m;
	std::condition_variable cv, done;
	const std::function<void(int)> *job = nullptr;
	std::atomic<int> next{ 0 };
	int total = 0;
	int pending = 0;
	uint64_t gen = 0;
	bool quit = false;
};

template <typename T>
static void snap(const std::vector<T> &a, const Grid &g, const Rect &r, std::vector<T> &out) {
	int rw = r.x1 - r.x0;
	out.resize(size_t(r.area()));
	for (int j = r.y0; j < r.y1; j++) {
		std::memcpy(&out[size_t(j - r.y0) * rw], &a[int64_t(j) * g.w + r.x0], sizeof(T) * rw);
	}
}

/// The bounding rect of the samples of r where a differs, bit for bit, from the snapshot.
template <typename T>
static Rect diff(const std::vector<T> &a, const Grid &g, const Rect &r, const std::vector<T> &old) {
	int rw = r.x1 - r.x0;
	Rect c{ 1 << 30, 1 << 30, -(1 << 30), -(1 << 30) };
	for (int j = r.y0; j < r.y1; j++) {
		const T *row = &a[int64_t(j) * g.w];
		const T *orow = &old[size_t(j - r.y0) * rw];
		for (int i = r.x0; i < r.x1; i++) {
			if (std::memcmp(&row[i], &orow[i - r.x0], sizeof(T)) != 0) {
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

constexpr int SMOOTH_R = 8;

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
	return "terra 1 core";
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
	for (Dirty *d : { &seed_c, &seed_w, &seed_p, &seed_f, &seed_paint }) {
		d->init(g);
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
			line_box(p.d, 2, p.d[0] * 0.5 + BANK_REACH + 0.5, x0, z0, x1, z1);
			break;
		case P_POND:
			line_box(p.d, 1, POND_REACH + 0.5, x0, z0, x1, z1);
			break;
		case P_PATH:
			line_box(p.d, 1, p.d[0] * 0.5 + 1.7, x0, z0, x1, z1);
			break;
		case P_WALL:
			line_box(p.d, 2, p.d.size() > 1 ? p.d[1] + 2.0 : 2.0, x0, z0, x1, z1);
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
			seed_w.add(r, g);
			changed_ids.insert(p.id);
			break;
		case P_PATH:
			seed_p.add(r, g);
			changed_ids.insert(p.id);
			break;
		case P_WALL:
			seed_f.add(r, g);
			changed_ids.insert(p.id);
			break;
		case P_PAINT:
			seed_paint.add(r, g);
			break;
		default:
			seed_c.add(r, g);
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
	for (Dirty *d : { &seed_c, &seed_w, &seed_p, &seed_f, &seed_paint }) {
		d->add(g.all(), g);
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

Dictionary TerraDerive::derive() {
	Clock::time_point t_all = Clock::now();
	bool full = seed_rules && seed_c.samples() == int64_t(g.w) * g.h;
	Dirty all;
	all.init(g);
	all.add(g.all(), g);
	Dictionary usec, work;
	auto run = [&](const Dirty &d, const std::function<Rect(const Rect &)> &fn, Dirty *changed) {
		std::vector<int> tiles = d.tiles();
		if (changed) {
			changed->init(g);
		}
		pool->run(int(tiles.size()), [&](int k) {
			int t = tiles[k];
			Rect c = fn(d.t[t]);
			if (changed) {
				changed->t[t] = c;
			}
		});
		return int(tiles.size());
	};

	// 1. compose
	Clock::time_point t0 = Clock::now();
	struct CP {
		const Prim *p;
		const ComposeKernel *k;
		Rect r;
	};
	std::vector<CP> cps;
	std::vector<const Prim *> river_p, pond_p, paint_p;
	for (const Prim &p : prims) {
		if (p.type == P_RIVER) {
			river_p.push_back(&p);
		} else if (p.type == P_POND) {
			pond_p.push_back(&p);
		} else if (p.type == P_PAINT) {
			paint_p.push_back(&p);
		} else if (const ComposeKernel *k = compose_kernel(p.type)) {
			cps.push_back({ &p, k, influence(p) });
		}
	}
	Dirty chg1;
	int n_comp = run(full ? all : seed_c, [&](const Rect &r) {
		std::vector<float> oh, os;
		snap(Hraw, g, r, oh);
		snap(SW, g, r, os);
		for (int j = r.y0; j < r.y1; j++) {
			for (int i = r.x0; i < r.x1; i++) {
				Hraw[int64_t(j) * g.w + i] = 0.0f;
				SW[int64_t(j) * g.w + i] = 0.0f;
			}
		}
		for (const CP &cp : cps) {
			Rect b = cp.r.inter(r);
			if (!b.empty()) {
				cp.k->apply(*cp.p, g, b, Hraw.data(), SW.data());
			}
		}
		return diff(Hraw, g, r, oh).unite(diff(SW, g, r, os));
	}, &chg1);
	usec["compose"] = us_since(t0);
	work["compose"] = n_comp;

	// 1b. smooth (halo SMOOTH_R)
	t0 = Clock::now();
	Dirty chg2;
	int n_sm = run(full ? all : chg1.dilate(SMOOTH_R, g), [&](const Rect &r) {
		std::vector<float> old;
		snap(H0, g, r, old);
		for (int j = r.y0; j < r.y1; j++) {
			for (int i = r.x0; i < r.x1; i++) {
				int64_t o = int64_t(j) * g.w + i;
				float sw = SW[o];
				if (sw <= 0.0f) {
					H0[o] = Hraw[o];
					continue;
				}
				int ja = std::max(0, j - SMOOTH_R), jb = std::min(g.h - 1, j + SMOOTH_R);
				int ia = std::max(0, i - SMOOTH_R), ib = std::min(g.w - 1, i + SMOOTH_R);
				double s = 0.0;
				for (int y = ja; y <= jb; y++) {
					for (int x = ia; x <= ib; x++) {
						s += Hraw[int64_t(y) * g.w + x];
					}
				}
				double mean = s / double((jb - ja + 1) * (ib - ia + 1));
				double w = std::min(double(sw), 1.0);
				H0[o] = float(Hraw[o] + (mean - Hraw[o]) * w);
			}
		}
		return diff(H0, g, r, old);
	}, &chg2);
	usec["smooth"] = us_since(t0);
	work["smooth"] = n_sm;

	// 2. water solve
	t0 = Clock::now();
	Water old = std::move(water);
	water = Water();
	water_geometry(water, river_p, pond_p, g);
	water_topology(water, g, H0.data());
	std::unordered_map<int, int> old_pond, old_river;
	for (int i = 0; i < int(old.ponds.size()); i++) {
		old_pond[old.ponds[i].id] = i;
	}
	for (int i = 0; i < int(old.rivers.size()); i++) {
		old_river[old.rivers[i].id] = i;
	}
	bool falls_changed = old.rivers.size() != water.rivers.size();
	int solved = 0;
	std::vector<char> pond_moved(water.ponds.size(), 0), river_moved(water.rivers.size(), 0);
	for (int i = 0; i < int(water.ponds.size()); i++) {
		Pond &p = water.ponds[i];
		auto it = old_pond.find(p.id);
		bool need = full || it == old_pond.end() || changed_ids.count(p.id) || chg2.hits(p.sample_rect);
		if (need) {
			solve_pond(p, g, H0.data());
			solved++;
		} else {
			p.level = old.ponds[it->second].level;
		}
		if (it == old_pond.end() || std::memcmp(&p.level, &old.ponds[it->second].level, sizeof(float)) != 0) {
			pond_moved[i] = 1;
			seed_w.add(p.rect, g);
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
				recv_moved || reads_hit(chg2, g, r.rx, r.rz);
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
			seed_w.add(r.rect, g);
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
			double reach = r.hw + BANK_REACH + 0.5;
			seed_w.add(g.rect_world(x0 - reach, z0 - reach, x1 + reach, z1 + reach), g);
		}
		if (r.falls.size() != o->falls.size() || !std::equal(r.falls.begin(), r.falls.end(), o->falls.begin())) {
			falls_changed = true;
		}
	}
	usec["water_solve"] = us_since(t0);
	work["water_solved"] = solved;

	// 3. carve (no halo)
	t0 = Clock::now();
	Dirty reg3 = chg2;
	reg3.merge(seed_w, g);
	Dirty chg3;
	int n_carve = run(full ? all : reg3, [&](const Rect &r) {
		std::vector<float> oh, ow;
		snap(H1, g, r, oh);
		snap(WL, g, r, ow);
		carve_rect(water, g, r, H0.data(), H1.data(), WL.data());
		return diff(H1, g, r, oh).unite(diff(WL, g, r, ow));
	}, &chg3);
	usec["carve"] = us_since(t0);
	work["carve"] = n_carve;

	// 3b. paths
	t0 = Clock::now();
	std::vector<PathL> old_paths = std::move(paths);
	paths.clear();
	std::vector<Wall> old_walls = std::move(walls);
	walls.clear();
	for (const Prim &p : prims) {
		if (p.type == P_PATH && p.d.size() >= 5) {
			PathL pl;
			path_geometry(pl, p, g);
			if (pl.l.n() >= 2) {
				paths.push_back(pl);
			}
		} else if (p.type == P_WALL && p.d.size() >= 6) {
			Wall wl;
			wall_geometry(wl, p, g);
			if (wl.l.n() >= 2) {
				walls.push_back(wl);
			}
		}
	}
	auto line_change = [&](const Line &l, const std::vector<float> &a, const std::vector<float> &b, double reach,
							   Dirty &into) {
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
	};
	for (PathL &p : paths) {
		const PathL *o = nullptr;
		for (const PathL &q : old_paths) {
			if (q.id == p.id) {
				o = &q;
			}
		}
		bool same = o && o->l.x == p.l.x && o->l.z == p.l.z && o->hw == p.hw;
		if (full || !same || changed_ids.count(p.id) || reads_hit(chg3, g, p.rx, p.rz)) {
			solve_path(p, g, H1.data());
		} else {
			p.prof = o->prof;
		}
		if (same) {
			line_change(p.l, p.prof, o->prof, p.hw + 1.7, seed_p);
		}
	}
	Dirty reg4 = chg3;
	reg4.merge(seed_p, g);
	Dirty chg4, chgPM;
	chgPM.init(g);
	int n_path = run(full ? all : reg4, [&](const Rect &r) {
		std::vector<float> oh;
		std::vector<uint8_t> om;
		snap(Hp, g, r, oh);
		snap(PM, g, r, om);
		path_rect(paths, g, r, H1.data(), WL.data(), Hp.data(), PM.data());
		Rect cm = diff(PM, g, r, om);
		int t = (r.y0 / TILE) * g.tx + r.x0 / TILE;
		chgPM.t[t] = cm;
		return diff(Hp, g, r, oh).unite(cm);
	}, &chg4);
	usec["paths"] = us_since(t0);
	work["paths"] = n_path;

	// 4. footprints
	t0 = Clock::now();
	Dirty wall_in = chg4;
	wall_in.merge(chg3, g);
	bool walls_changed = old_walls.size() != walls.size();
	for (Wall &w : walls) {
		const Wall *o = nullptr;
		for (const Wall &q : old_walls) {
			if (q.id == w.id) {
				o = &q;
			}
		}
		bool same = o && o->l.x == w.l.x && o->l.z == w.l.z && o->thick == w.thick && o->height == w.height;
		if (full || !same || changed_ids.count(w.id) || reads_hit(wall_in, g, w.rx, w.rz)) {
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
		bool moved = line_change(w.l, w.pad, o->pad, w.thick + 2.0, seed_f);
		moved = line_change(w.l, sa, sb, w.thick + 2.0, seed_f) || moved;
		walls_changed = walls_changed || moved;
	}
	Dirty reg5 = wall_in;
	reg5.merge(seed_f, g);
	Dirty chg5, chgM;
	chgM.init(g);
	int n_pad = run(full ? all : reg5, [&](const Rect &r) {
		std::vector<float> oh;
		std::vector<uint8_t> of, ow;
		snap(H2, g, r, oh);
		snap(FM, g, r, of);
		snap(WM, g, r, ow);
		pad_rect(walls, g, r, Hp.data(), WL.data(), H2.data(), FM.data(), WM.data());
		int t = (r.y0 / TILE) * g.tx + r.x0 / TILE;
		chgM.t[t] = diff(FM, g, r, of).unite(diff(WM, g, r, ow));
		return diff(H2, g, r, oh);
	}, &chg5);
	usec["pads"] = us_since(t0);
	work["pads"] = n_pad;

	// 5. fields: slope (halo 1), distances (halo = cap)
	t0 = Clock::now();
	Dirty chgS;
	int n_slope = run(full ? all : chg5.dilate(1, g), [&](const Rect &r) {
		std::vector<float> old;
		snap(SL, g, r, old);
		slope_rect(g, r, H2.data(), SL.data());
		return diff(SL, g, r, old);
	}, &chgS);
	Dirty masks = chgM;
	masks.merge(chgPM, g);
	Dirty chgD;
	int n_edt = run(full ? all : masks.dilate(DIST_HALO, g), [&](const Rect &r) {
		std::vector<float> a, b, c;
		snap(DW, g, r, a);
		snap(DP, g, r, b);
		snap(DF, g, r, c);
		edt_rect(g, r, WM.data(), DIST_CAP_WATER, DW.data());
		edt_rect(g, r, PM.data(), DIST_CAP_PATH, DP.data());
		edt_rect(g, r, FM.data(), DIST_CAP_FOOT, DF.data());
		return diff(DW, g, r, a).unite(diff(DP, g, r, b)).unite(diff(DF, g, r, c));
	}, &chgD);
	// 5c. the look field (round 3): band-limited height and convexity (halo LOOK_WIDE)
	Dirty chgL;
	int n_look = run(full ? all : chg5.dilate(LOOK_WIDE, g), [&](const Rect &r) {
		std::vector<float> a, b;
		snap(HB, g, r, a);
		snap(CV, g, r, b);
		look_rect(g, r, H2.data(), HB.data(), CV.data());
		return diff(HB, g, r, a).unite(diff(CV, g, r, b));
	}, &chgL);
	usec["fields"] = us_since(t0);
	work["slope"] = n_slope;
	work["distance"] = n_edt;
	work["look"] = n_look;

	// 5b. paint coats (no halo)
	t0 = Clock::now();
	Dirty chgP;
	run(full ? all : seed_paint, [&](const Rect &r) {
		std::vector<float> ow;
		std::vector<uint8_t> oi;
		snap(PW, g, r, ow);
		snap(PI, g, r, oi);
		paint_rect(paint_p, g, r, PI.data(), PW.data());
		return diff(PW, g, r, ow).unite(diff(PI, g, r, oi));
	}, &chgP);

	// 6. ground rules (no halo)
	Dirty reg7 = chgS;
	for (const Dirty *d : { &chgD, &chg5, &chg3, &chgP, &chgPM, &chgL }) {
		reg7.merge(*d, g);
	}
	FieldInputs in{ H2.data(), WL.data(), SL.data(), DW.data(), DP.data(), DF.data(), PW.data(), PM.data(), PI.data(),
		CV.data() };
	Dirty chgCT;
	int n_rules = run(full || seed_rules ? all : reg7, [&](const Rect &r) {
		std::vector<uint8_t> old;
		int rw = r.x1 - r.x0;
		old.resize(size_t(r.area()) * 4);
		for (int j = r.y0; j < r.y1; j++) {
			std::memcpy(&old[size_t(j - r.y0) * rw * 4], &CT[(int64_t(j) * g.w + r.x0) * 4], size_t(rw) * 4);
		}
		rules_rect(rules, g, r, in, CT.data());
		for (int j = r.y0; j < r.y1; j++) {
			if (std::memcmp(&old[size_t(j - r.y0) * rw * 4], &CT[(int64_t(j) * g.w + r.x0) * 4], size_t(rw) * 4) != 0) {
				return r;
			}
		}
		return Rect{};
	}, &chgCT);
	usec["rules"] = us_since(t0);
	work["rules"] = n_rules;

	auto tiles_of = [&](Dirty d) {
		Dirty grown = d.dilate(1, g);
		std::vector<int> t = grown.tiles();
		PackedInt32Array out;
		for (int v : t) {
			out.push_back(v);
		}
		return out;
	};
	Dirty hz = chg5;
	hz.merge(chg3, g);
	Dirty fz = chgS;
	fz.merge(chgD, g);
	Dictionary out;
	out["tiles_height"] = tiles_of(hz);
	out["tiles_control"] = tiles_of(chgCT);
	out["tiles_fields"] = tiles_of(fz);
	out["tiles_look"] = tiles_of(chgL);
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
	out["falls_changed"] = falls_changed || full;
	out["walls_changed"] = walls_changed || full;
	out["changed_samples"] = hz.samples();
	usec["total"] = us_since(t_all);
	out["usec"] = usec;
	out["work"] = work;

	for (Dirty *d : { &seed_c, &seed_w, &seed_p, &seed_f, &seed_paint }) {
		d->clear();
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
}

} // namespace godot
