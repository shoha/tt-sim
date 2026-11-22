// The kind registry (card terraform-p1-kinds, 2026-11-22; docs/systems/terraform.md "Kinds"): every
// primitive kind the derive knows, one KindDef each. A kind's kernel file (src/kinds/
// terra_kind_<name>.cpp) ends in one TERRA_KIND(...) line, a static registrar: SCons links every
// object file into the library, so the kernel registers when the library loads and no table here
// names it. The GDScript twin is utils/terraform/terra_kinds.gd; test_terra_kinds fails when the two
// disagree on an id, name, stage, shape, header or stride.
//
// A kind belongs to one stage, and its shape follows from that stage's row: a stamp (a rect stage:
// compose, paint) is applied per sample in document order by `apply`; a line (a line stage: paths,
// pads) is built and solved by its stage's solve; water (the graph stage) is the built-in river
// and pond, solved together in terra_water.cpp. `bounds` gives the world box an edit of the kind
// can change (its influence), reaches included, so a stage's seeds never guess.
//
// Lookups go by id over a table kept sorted by id, so nothing depends on the order the linker ran
// the registrars in; a repeated id keeps the def whose name sorts first and counts a conflict.
#pragma once

#include <vector>

#include "terra_core.h"
#include "terra_stage_table.h"

namespace terra {

// The stages a kind can belong to, by the names a TERRA_KIND line uses.
constexpr int STAGE_COMPOSE = S_COMPOSE;
constexpr int STAGE_WATER = S_WATER;
constexpr int STAGE_PATHS = S_PATHS;
constexpr int STAGE_PADS = S_FOOTPRINTS;
constexpr int STAGE_PAINT = S_PAINT;

// The two water kinds' ids: the water stage tells them apart (river and pond solve differently).
constexpr int KIND_RIVER = 4;
constexpr int KIND_POND = 5;

enum KindShape : int {
	KIND_STAMP = 0, // per sample, in document order (a rect stage)
	KIND_LINE, // a line built and solved by its stage, then a rect (a line stage)
	KIND_WATER, // a body of the water graph (the graph stage)
};

/// What a stamp writes over a rect: its stage's arrays (compose: H, the composed height, and SW, the
/// smoothing weight; paint: PI, the coat's surface id, and PW, its weight). Whole-map arrays.
struct StampOut {
	float *H = nullptr;
	float *SW = nullptr;
	uint8_t *PI = nullptr;
	float *PW = nullptr;
};

struct KindDef {
	int id; // stable, never reused: 0 to 8 built in, 9 to 15 reserved, 16 up new
	const char *name; // stable; the map document's kind table writes it
	int stage; // a StageId
	int header; // floats before the items
	int stride; // floats an item (0: the header only)
	/// The world box a primitive of this kind can change, reaches included; false for the whole map.
	bool (*bounds)(const Prim &p, double &x0, double &z0, double &x1, double &z1);
	/// A stamp's kernel over the samples of `r` (already clipped to its bounds); null for the others.
	void (*apply)(const Prim &p, const Grid &g, const Rect &r, const StampOut &out);

	/// The shape, from the stage's row.
	int shape() const;
	/// The stage input an edit of this kind seeds (the stage's one input array).
	int input() const;
};

/// Adds a kind to the table (TERRA_KIND calls it at load). Always true, so it can initialise a
/// static; a repeated id counts a conflict (kind_conflicts) and keeps the def whose name sorts first.
bool register_kind(const KindDef &k);
/// The kind with `id`, or null.
const KindDef *kind_def(int id);
/// Every kind, sorted by id.
const std::vector<KindDef> &kind_defs();
/// Ids registered twice (none in a sound build).
int kind_conflicts();
/// Inserts `k` into a table sorted by id, as register_kind does: the result never depends on the
/// order of the inserts. False on a repeated id.
bool insert_kind(std::vector<KindDef> &table, const KindDef &k);

/// The world box of a dab list with `stride` floats a dab, [cx, cz, radius, ...].
bool dab_bounds(const Prim &p, int stride, double &x0, double &z0, double &x1, double &z1);
/// The world box of the points after `skip` header floats, (x, z) pairs, grown by `grow` metres.
bool line_bounds(const Prim &p, int skip, double grow, double &x0, double &z0, double &x1, double &z1);

} // namespace terra

#define TERRA_KIND_CAT2(a, b) a##b
#define TERRA_KIND_CAT(a, b) TERRA_KIND_CAT2(a, b)
/// Registers a kind when the library loads: TERRA_KIND(id, "name", STAGE_X, header, stride,
/// bounds, apply). One line at the end of the kind's file; `apply` is nullptr for a line or water
/// kind.
#define TERRA_KIND(id, name, stage, header, stride, bounds, apply)                              \
	[[maybe_unused]] static const bool TERRA_KIND_CAT(terra_kind_registered_, __LINE__) = \
			::terra::register_kind(::terra::KindDef{ id, name, stage, header, stride, bounds, apply })
