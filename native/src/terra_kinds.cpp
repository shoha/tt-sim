// The kind registry's table (terra_kinds.h). It is filled while the library loads, by each kind
// file's static registrar, before any TerraDerive exists, and only read afterwards.
#include "terra_kinds.h"

#include <cstring>

namespace terra {

// Function-local statics: a registrar in another file may run before this file's own statics.
static std::vector<KindDef> &table() {
	static std::vector<KindDef> t;
	return t;
}

static int &conflicts() {
	static int n = 0;
	return n;
}

int KindDef::shape() const {
	switch (STAGES[stage].shape) {
		case SHAPE_GRAPH:
			return KIND_WATER;
		case SHAPE_LINE_RECT:
			return KIND_LINE;
		default:
			return KIND_STAMP;
	}
}

int KindDef::input() const {
	// The paint stage also reads the path primitives (a path's surface is a coat), but its own
	// kind's edits seed the paint primitives.
	if (stage == S_PAINT) {
		return A_PAINT_PRIMS;
	}
	for (int a = 0; a < A_COUNT; a++) {
		if ((STAGES[stage].reads & bit(a)) && ARRAYS[a].kind == K_INPUT) {
			return a;
		}
	}
	return A_COMPOSE_PRIMS;
}

bool insert_kind(std::vector<KindDef> &t, const KindDef &k) {
	size_t at = 0;
	while (at < t.size() && t[at].id < k.id) {
		at++;
	}
	if (at < t.size() && t[at].id == k.id) {
		if (std::strcmp(k.name, t[at].name) < 0) {
			t[at] = k;
		}
		return false;
	}
	t.insert(t.begin() + at, k);
	return true;
}

bool register_kind(const KindDef &k) {
	if (k.stage < 0 || k.stage >= S_COUNT || !insert_kind(table(), k)) {
		conflicts()++;
	}
	return true;
}

const KindDef *kind_def(int id) {
	const std::vector<KindDef> &t = table();
	size_t lo = 0, hi = t.size();
	while (lo < hi) {
		size_t mid = (lo + hi) / 2;
		if (t[mid].id < id) {
			lo = mid + 1;
		} else {
			hi = mid;
		}
	}
	return lo < t.size() && t[lo].id == id ? &t[lo] : nullptr;
}

const std::vector<KindDef> &kind_defs() {
	return table();
}

int kind_conflicts() {
	return conflicts();
}

bool dab_bounds(const Prim &p, int stride, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	for (size_t k = 0; k + stride <= p.d.size(); k += stride) {
		double r = p.d[k + 2];
		x0 = std::min(x0, p.d[k] - r);
		z0 = std::min(z0, p.d[k + 1] - r);
		x1 = std::max(x1, p.d[k] + r);
		z1 = std::max(z1, p.d[k + 1] + r);
	}
	return true;
}

bool line_bounds(const Prim &p, int skip, double grow, double &x0, double &z0, double &x1, double &z1) {
	x0 = z0 = 1e30;
	x1 = z1 = -1e30;
	for (size_t k = skip; k + 1 < p.d.size(); k += 2) {
		x0 = std::min(x0, double(p.d[k]) - grow);
		z0 = std::min(z0, double(p.d[k + 1]) - grow);
		x1 = std::max(x1, double(p.d[k]) + grow);
		z1 = std::max(z1, double(p.d[k + 1]) + grow);
	}
	return true;
}

} // namespace terra
