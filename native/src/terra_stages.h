// The stages after compose (spike terraform-s2-cpu): water solve and carve, paths, footprint pads,
// fields and the ground rule table. Each rect function is a per-sample pure function of whole-map
// inputs; each solve is a 1D pass along one primitive's line. Halos and the reaches in samples
// are declared in terra_stage_table.h, nowhere else.
#pragma once

#include "terra_core.h"
#include "terra_stage_table.h"

namespace terra {

// Water rules, in metres (the opinionated constants of the slice).
constexpr double RIVER_DS = 0.25; // arc spacing of a river's level profile
constexpr double RIVER_FREEBOARD = 0.15; // level under the drawn ground
constexpr double FALL_MIN = 0.75; // a step of at least this between reaches is a fall record
// Card terraform-p2-bridge: river levels are flat reaches, today's conditioner rule
// (WaterConditioner.fit_levels: QUANTUM_M, DEAD_BAND_M, MIN_REACH_M), so every reach converts to
// one flat WaterBody exactly. The level lattice; a step under the dead band drops onto the level
// below it; a reach shorter than MIN_REACH_M merges into the neighbour it differs from least.
// The spike's sloped rapids (round 3) can return once the water field reads WL (phase 3).
constexpr double LEVEL_QUANTUM_M = 0.05;
constexpr double REACH_DEAD_BAND_M = 0.25;
constexpr double MIN_REACH_M = 2.0;
// A fall is a drop of FALL_MIN within FALL_RUN of arc (a sharp step), pinned as one step before
// the conditioner runs (which never touches a fall-sized step); after a fall the next one waits
// FALL_GAP of arc, so a hillside gets one or two confident falls with riffles between, not a stair
// of locks.
constexpr double FALL_RUN = 1.5;
constexpr double FALL_GAP = 6.0;
// The bank: its slope at the water (plus noise) and how fast it steepens with distance (1/m), and
// the smooth minimum's width where the cut meets the ground (m).
constexpr double BANK_SLOPE = 0.28;
constexpr double BANK_NOISE = 0.22;
constexpr double BANK_CURVE = 0.16;
constexpr double BANK_SOFT = 0.45;
constexpr double POND_REACH = 6.0;
constexpr double POND_FREEBOARD = 0.1;

/// A fall record: where, which way, the two levels and the width. The renderer draws a curtain.
struct Fall {
	double x = 0, z = 0, tx = 0, tz = 0, top = 0, bottom = 0, width = 0;
	bool operator==(const Fall &o) const {
		return x == o.x && z == o.z && tx == o.tx && tz == o.tz && top == o.top && bottom == o.bottom &&
				width == o.width;
	}
};

struct River {
	int id = 0;
	Line drawn; // the author's line, resampled, as drawn
	Line l; // the line downstream (flipped when drawn uphill)
	double hw = 1.0, depth = 0.5;
	std::vector<float> level; // per point of l
	std::vector<Fall> falls;
	int recv_river = -1, recv_pond = -1; // the body its end flows into (indices)
	Rect rect; // samples it can change
	Rect sample_rect; // samples its solve reads
	std::vector<double> rx, rz; // the points its solve reads bilinearly (the exact hit test)
};

struct Pond {
	int id = 0;
	std::vector<double> ox, oz; // outline
	double depth = 0.6;
	float level = 0.0f;
	Rect rect, sample_rect;
};

struct Water {
	std::vector<Pond> ponds;
	std::vector<River> rivers;
	std::vector<int> order; // river solve order, receivers first
};

/// Builds the bodies' geometry (lines, receivers, rects) from the primitives; no heights read.
void water_geometry(Water &w, const std::vector<const Prim *> &rivers, const std::vector<const Prim *> &ponds,
		const Grid &g);
/// Flips rivers drawn uphill (from H0 at their ends), finds receivers and the solve order.
void water_topology(Water &w, const Grid &g, const float *H0);
void solve_pond(Pond &p, const Grid &g, const float *H0);
/// Levels as flat reaches monotone downstream (the conditioner's rule, above), steps of FALL_MIN
/// or more as fall records, a join at the receiver's level (recv_level, or NAN for a free end).
void solve_river(River &r, const Grid &g, const float *H0, double recv_level);
/// The level of a river at the arc point nearest (x, z).
double river_level_at(const River &r, double x, double z);
/// Stage 3 carve over a rect: H1 = H0 cut by every body's channel or basin, banks
/// filled to hold the level; WL = the controlling body's level where wet or on ground above it,
/// else H1 - 1.
void carve_rect(const Water &w, const Grid &g, const Rect &r, const float *H0, float *H1, float *WL);

struct PathL {
	int id = 0;
	Line l;
	double hw = 0.75;
	std::vector<float> prof;
	Rect rect, sample_rect;
	std::vector<double> rx, rz;
};

struct Wall {
	int id = 0;
	Line l;
	double height = 1.2, thick = 0.5;
	std::vector<float> pad;
	std::vector<uint8_t> solid;
	Rect rect, sample_rect;
	std::vector<double> rx, rz;
};

// The line kinds' shared maths (terra_paths.cpp).
/// A primitive's points after `skip` header floats, Chaikin-rounded `rounding` times and
/// resampled every `ds` metres.
void line_from(const Prim &prim, int skip, double ds, Line &out, int rounding = 0);
/// The window mean of v over +-half samples (fixed order, clamped at the ends).
std::vector<double> window_mean(const std::vector<double> &v, int half);
/// The mean of the largest and smallest m-Lipschitz profiles under and over v: graded to m.
std::vector<double> grade(const std::vector<double> &v, double m);
/// The segment of `segs` nearest (x, z), its distance d and parameter t; -1 when segs is empty.
int nearest_seg(const Line &l, const std::vector<int> &segs, double x, double z, double &d, double &t);

// The path and wall kinds' stage bodies (src/kinds/terra_kind_path.cpp, terra_kind_wall.cpp).
void path_geometry(PathL &p, const Prim &prim, const Grid &g);
/// Grades a path to its maximum slope (stairs where a bench would cut or fill too much).
void solve_path(PathL &p, const Grid &g, const float *H1);
/// Paths over a rect: Hp = H1 benched under each path, PM = path coverage 0..255.
void path_rect(const std::vector<PathL> &paths, const Grid &g, const Rect &r, const float *H1, const float *WL,
		float *Hp, uint8_t *PM);

void wall_geometry(Wall &w, const Prim &prim, const Grid &g);
void solve_wall(Wall &w, const Grid &g, const float *Hp, const float *WL);
/// Footprint pads over a rect: H2 = Hp padded under solid wall runs, FM = foot mask,
/// WM = wet mask (WL above H2).
void pad_rect(const std::vector<Wall> &walls, const Grid &g, const Rect &r, const float *Hp, const float *WL,
		float *H2, uint8_t *FM, uint8_t *WM);

/// A stamp stage over a rect (compose into Hraw and SW, paint into PI and PW): its outputs zeroed,
/// then each of its primitives whose influence meets the rect applied by its kind, in document
/// order (`kinds` beside `prims`, `bounds` their influence rects).
struct KindDef;
struct StampOut;
void stamp_rect(const std::vector<const Prim *> &prims, const std::vector<const KindDef *> &kinds,
		const std::vector<Rect> &bounds, const Grid &g, const Rect &r, const StampOut &out);
/// HeightBrush SMOOTH's approach rate (per second of exposure at full weight).
constexpr double SMOOTH_RATE = 4.0;
/// Smooths Hraw into H0 over a rect: each sample moves toward its (2 SMOOTH_R + 1) squared box mean
/// by 1 - exp(-SMOOTH_RATE * SW), SW being the smooth dabs' summed exposure (seconds at full
/// weight), as HeightBrush's approach; a sample of weight 0 copies Hraw.
void smooth_rect(const Grid &g, const Rect &r, const float *Hraw, const float *SW, float *H0);

/// Slope in degrees over a rect (reach SLOPE_R).
void slope_rect(const Grid &g, const Rect &r, const float *H2, float *SL);
/// Distance in metres to the nearest sample with mask != 0, capped (reach = cap): an exact
/// two-pass transform over the rect grown by the cap.
void edt_rect(const Grid &g, const Rect &r, const uint8_t *mask, int cap, float *dist);

/// The look field over a rect (reach LOOK_WIDE): each output a fixed-order sum, clamped at the map.
void look_rect(const Grid &g, const Rect &r, const float *H2, float *HB, float *CV);

/// Field indices a rule term reads.
enum Field { F_DEPTH = 0, F_SLOPE, F_DWATER, F_DPATH, F_DFOOT, F_WET, F_PAINT, F_HEIGHT, F_PATHCOV, F_CURV, F_COUNT };

struct Term {
	int field = 0;
	float lo = -1e9f, hi = 1e9f, soft = 0.0f;
};

/// One row of the ground table: a surface class (or -1: the painted surface) and its terms.
struct Rule {
	int cls = 0;
	std::vector<Term> terms;
};

struct FieldInputs {
	const float *H2, *WL, *SL, *DW, *DP, *DF, *PW;
	const uint8_t *PM, *PI;
	const float *CV;
};

/// Stage 6 over a rect: the packed control map, 4 bytes per sample (base class,
/// overlay class, blend, wetness), from the rule table over the fields; later rows paint over.
void rules_rect(const std::vector<Rule> &rules, const Grid &g, const Rect &r, const FieldInputs &in, uint8_t *CT);

} // namespace terra
