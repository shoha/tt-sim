// The stage table (card terraform-p1-stages, 2026-11-22; docs/systems/terraform.md "The stage
// chain"): every stage of the derive in run order, with the arrays it reads and writes and its
// halo. TerraDerive::derive() loops over STAGES[] and takes each stage's region from its row: the
// change in its per-sample reads grown by its halo, plus the change in its input and record reads
// (already in samples), plus the seeds its own solve adds. This is the only place a halo is
// declared; the bodies take their reach from the parameters just above the table, and a
// static_assert proves the order (every read is an input or written by an earlier stage, every
// array written by exactly one stage).
#pragma once

#include <cstdint>

#include "terra_core.h"

namespace terra {

/// Every array the stages read or write: the inputs (the primitive groups and the ground table,
/// whose change is the pending edits' seeds), the per-sample arrays and the solved water record.
enum ArrayId : int {
	A_COMPOSE_PRIMS = 0,
	A_WATER_PRIMS,
	A_PATH_PRIMS,
	A_WALL_PRIMS,
	A_PAINT_PRIMS,
	A_RULE_TABLE,
	A_HRAW,
	A_SW,
	A_H0,
	A_LEVELS,
	A_H1,
	A_WL,
	A_HP,
	A_PM,
	A_H2,
	A_FM,
	A_WM,
	A_SL,
	A_DW,
	A_DP,
	A_DF,
	A_HB,
	A_CV,
	A_PI,
	A_PW,
	A_CT,
	A_COUNT
};

enum ArrayKind : int {
	K_INPUT = 0, // changed where the pending edits seeded it
	K_SAMPLES, // one value a sample; changed where a stage's output differs bit for bit
	K_RECORD, // a solved record; changed over the samples its change can reach
};

struct ArrayDef {
	const char *name;
	int kind;
	int bytes; // per sample, for K_SAMPLES
};

enum StageShape : int {
	SHAPE_RECT = 0, // a per-sample pure function over each dirty tile's rect
	SHAPE_GRAPH, // a solve over whole bodies, read at exact points (reads_hit), no rect
	SHAPE_LINE_RECT, // a solve along each line, then a rect
};

enum StageId : int {
	S_COMPOSE = 0,
	S_SMOOTH,
	S_WATER,
	S_CARVE,
	S_PATHS,
	S_FOOTPRINTS,
	S_SLOPE,
	S_DISTANCES,
	S_LOOK,
	S_PAINT,
	S_RULES,
	S_COUNT
};

/// A graph stage's halo: it reads exact points, not a neighbourhood of samples.
constexpr int HALO_READ_POINTS = -1;

struct StageDef {
	int id;
	const char *name;
	int shape;
	uint32_t reads, writes; // bits of ArrayId
	int halo; // samples the per-sample reads are grown by; HALO_READ_POINTS for a graph stage
	// Metres past a body's half width (a wall's thickness) that a change of its solved line can
	// reach, for the stages whose solve seeds its own region (0: none).
	double reach_m;
};

constexpr uint32_t bit(int a) {
	return 1u << a;
}

// Stage parameters in samples: each body's reach, which its row below makes its halo.
constexpr int SMOOTH_R = 8;
constexpr int SLOPE_R = 1; // central differences
constexpr int DIST_CAP_WATER = 48; // the distance caps (6 m and 3 m at an eighth of a metre)
constexpr int DIST_CAP_PATH = 24;
constexpr int DIST_CAP_FOOT = 24;
// The look field (round 3): HB the height under a (2 LOOK_NARROW + 1) squared box, the band-limited
// form the ground is shaded by; CV the box of (2 LOOK_WIDE + 1) squared minus HB, positive in a
// hollow and negative on a ridge (metres). Round 4: the wide box takes every second tap (15 a
// pass, the same 14-sample reach): the round 3 box cost about 0.26 ms of a held frame.
constexpr int LOOK_NARROW = 3;
constexpr int LOOK_WIDE = 14;
constexpr int LOOK_WIDE_STRIDE = 2;

// Water, path and wall reaches in metres: how far past its half width a river can cut or fill
// (also its influence), and how far a path's bench or a wall's pad can change the ground.
constexpr double BANK_REACH = 5.0;
constexpr double CARVE_REACH_M = BANK_REACH + 0.5;
constexpr double PATH_REACH_M = 1.7;
constexpr double PAD_REACH_M = 2.0;

constexpr int max_of(int a, int b) {
	return a > b ? a : b;
}

inline constexpr ArrayDef ARRAYS[A_COUNT] = {
	{ "compose prims", K_INPUT, 0 },
	{ "water prims", K_INPUT, 0 },
	{ "path prims", K_INPUT, 0 },
	{ "wall prims", K_INPUT, 0 },
	{ "paint prims", K_INPUT, 0 },
	{ "ground table", K_INPUT, 0 },
	{ "Hraw", K_SAMPLES, 4 },
	{ "SW", K_SAMPLES, 4 },
	{ "H0", K_SAMPLES, 4 },
	{ "levels", K_RECORD, 0 },
	{ "H1", K_SAMPLES, 4 },
	{ "WL", K_SAMPLES, 4 },
	{ "Hp", K_SAMPLES, 4 },
	{ "PM", K_SAMPLES, 1 },
	{ "H2", K_SAMPLES, 4 },
	{ "FM", K_SAMPLES, 1 },
	{ "WM", K_SAMPLES, 1 },
	{ "SL", K_SAMPLES, 4 },
	{ "DW", K_SAMPLES, 4 },
	{ "DP", K_SAMPLES, 4 },
	{ "DF", K_SAMPLES, 4 },
	{ "HB", K_SAMPLES, 4 },
	{ "CV", K_SAMPLES, 4 },
	{ "PI", K_SAMPLES, 1 },
	{ "PW", K_SAMPLES, 4 },
	{ "CT", K_SAMPLES, 4 },
};

// clang-format off
inline constexpr StageDef STAGES[S_COUNT] = {
	{ S_COMPOSE, "compose", SHAPE_RECT, bit(A_COMPOSE_PRIMS), bit(A_HRAW) | bit(A_SW), 0, 0.0 },
	{ S_SMOOTH, "smooth", SHAPE_RECT, bit(A_HRAW) | bit(A_SW), bit(A_H0), SMOOTH_R, 0.0 },
	{ S_WATER, "water_solve", SHAPE_GRAPH, bit(A_H0) | bit(A_WATER_PRIMS), bit(A_LEVELS), HALO_READ_POINTS, 0.0 },
	{ S_CARVE, "carve", SHAPE_RECT, bit(A_H0) | bit(A_LEVELS), bit(A_H1) | bit(A_WL), 0, CARVE_REACH_M },
	{ S_PATHS, "paths", SHAPE_LINE_RECT, bit(A_H1) | bit(A_WL) | bit(A_PATH_PRIMS), bit(A_HP) | bit(A_PM), 0,
			PATH_REACH_M },
	{ S_FOOTPRINTS, "pads", SHAPE_LINE_RECT, bit(A_HP) | bit(A_WL) | bit(A_WALL_PRIMS),
			bit(A_H2) | bit(A_FM) | bit(A_WM), 0, PAD_REACH_M },
	{ S_SLOPE, "slope", SHAPE_RECT, bit(A_H2), bit(A_SL), SLOPE_R, 0.0 },
	{ S_DISTANCES, "distance", SHAPE_RECT, bit(A_WM) | bit(A_PM) | bit(A_FM), bit(A_DW) | bit(A_DP) | bit(A_DF),
			max_of(DIST_CAP_WATER, max_of(DIST_CAP_PATH, DIST_CAP_FOOT)), 0.0 },
	{ S_LOOK, "look", SHAPE_RECT, bit(A_H2), bit(A_HB) | bit(A_CV), LOOK_WIDE, 0.0 },
	{ S_PAINT, "paint", SHAPE_RECT, bit(A_PAINT_PRIMS), bit(A_PI) | bit(A_PW), 0, 0.0 },
	{ S_RULES, "rules", SHAPE_RECT,
			bit(A_H2) | bit(A_WL) | bit(A_SL) | bit(A_DW) | bit(A_DP) | bit(A_DF) | bit(A_PW) | bit(A_PM) | bit(A_PI) |
					bit(A_CV) | bit(A_RULE_TABLE),
			bit(A_CT), 0, 0.0 },
};
// clang-format on

/// True when the rows are in id order, every read is an input or written by an earlier stage,
/// every non-input array is written by exactly one stage, no stage writes an input, and a stage
/// is a graph exactly when its halo is HALO_READ_POINTS.
constexpr bool table_ok() {
	uint32_t written = 0;
	for (int s = 0; s < S_COUNT; s++) {
		const StageDef &d = STAGES[s];
		if (d.id != s || (d.shape == SHAPE_GRAPH) != (d.halo == HALO_READ_POINTS)) {
			return false;
		}
		for (int a = 0; a < A_COUNT; a++) {
			bool input = ARRAYS[a].kind == K_INPUT;
			if ((d.reads & bit(a)) && !input && !(written & bit(a))) {
				return false;
			}
			if (d.writes & bit(a)) {
				if (input || (written & bit(a))) {
					return false;
				}
				written |= bit(a);
			}
		}
	}
	for (int a = 0; a < A_COUNT; a++) {
		if (ARRAYS[a].kind != K_INPUT && !(written & bit(a))) {
			return false;
		}
	}
	return true;
}
static_assert(table_ok(), "the stage table reads an array before a stage writes it");
static_assert(A_COUNT <= 32, "the read and write masks are 32 bits");

/// A stage's region: its per-sample reads' change grown by its halo, plus its input and record
/// reads' change (already in samples), plus `own` (the seeds its solve added). Rect stages only.
Dirty stage_region(const StageDef &s, const Dirty *changed, const Dirty &own, const Grid &g);

/// Where a stage's per-sample reads changed, ungrown: what its solve tests its read points against.
Dirty stage_read_change(const StageDef &s, const Dirty *changed, const Grid &g);

} // namespace terra
