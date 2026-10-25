// The native scatter generator's shared pieces: GDScript's maths as the engine runs it, a
// small int64-keyed hash map for the generator's memos, and the plan and grid records one job
// reads (filled once from the job's Dictionary by scatter_load.cpp).
//
// GDScript's float is a double, but Vector2, Vector3, Quaternion, Rect2 and PackedFloat32Array
// hold float32 (real_t). A component read is a double, an expression of components runs in
// double, and the result is rounded to float32 when it goes back into a vector; a vector
// operation runs in float32 with a double scalar rounded first. The port keeps that split by
// using godot-cpp's own Vector2, Vector3, Quaternion, Basis and Rect2 (the engine's formulas)
// and doubles everywhere GDScript has a float. The helpers below copy the GDScript globals
// (maxf, minf, clampf as Godot's MAX/MIN/CLAMP macros, so a zero's sign survives; smoothstep,
// fposmod, snappedf, floori). Built with -ffp-contract=off and no fast-math.
#pragma once

#include <cmath>
#include <cstdint>
#include <cstring>
#include <deque>
#include <string>
#include <vector>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace ttscatter {

using godot::Quaternion;
using godot::Rect2;
using godot::Vector2;
using godot::Vector3;

constexpr double PI_D = 3.1415926535897932384626433833;
constexpr double TAU_D = 6.2831853071795864769252867666;
constexpr int64_t MASK32 = 0xFFFFFFFFLL;

inline double gmax(double a, double b) { return a > b ? a : b; }
inline double gmin(double a, double b) { return a < b ? a : b; }
inline int64_t imax(int64_t a, int64_t b) { return a > b ? a : b; }
inline int64_t imin(int64_t a, int64_t b) { return a < b ? a : b; }
inline double gclamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double glerp(double a, double b, double t) { return a + (b - a) * t; }
inline int64_t floori(double x) { return (int64_t)std::floor(x); }
inline double deg_to_rad(double d) { return d * (PI_D / 180.0); }
inline double rad_to_deg(double r) { return r * (180.0 / PI_D); }

inline bool is_equal_approx(double a, double b) {
	if (a == b) {
		return true;
	}
	double tolerance = 0.00001 * std::fabs(a);
	if (tolerance < 0.00001) {
		tolerance = 0.00001;
	}
	return std::fabs(a - b) < tolerance;
}

inline double smoothstep(double from, double to, double s) {
	if (is_equal_approx(from, to)) {
		if (from <= to) {
			return s <= from ? 0.0 : 1.0;
		}
		return s <= to ? 1.0 : 0.0;
	}
	double x = gclamp((s - from) / (to - from), 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

inline double fposmod(double x, double y) {
	double value = std::fmod(x, y);
	if ((value < 0 && y > 0) || (value > 0 && y < 0)) {
		value += y;
	}
	value += 0.0;
	return value;
}

inline int64_t posmod(int64_t x, int64_t y) {
	int64_t value = x % y;
	if ((value < 0 && y > 0) || (value > 0 && y < 0)) {
		value += y;
	}
	return value;
}

inline double snapped(double value, double step) {
	return step != 0 ? std::floor(value / step + 0.5) * step : value;
}

/// A Vector2 from two doubles, each rounded to float32 (GDScript's Vector2(x, z)).
inline Vector2 v2(double x, double y) { return Vector2((float)x, (float)y); }

/// A memo key for a Vector2 (the float32 pair's bits).
inline int64_t key_of(const Vector2 &v) {
	uint32_t bx, by;
	std::memcpy(&bx, &v.x, 4);
	std::memcpy(&by, &v.y, 4);
	return (int64_t)(((uint64_t)bx << 32) | by);
}

/// An open-addressing int64 -> V map (linear probing), for the generator's memos: GDScript's
/// int-keyed Dictionaries without the Variant boxing.
template <typename V>
class I64Map {
	static constexpr int64_t EMPTY = INT64_MIN;
	std::vector<int64_t> keys;
	std::vector<V> values;
	size_t count = 0;
	size_t mask = 0;

	static size_t hash(int64_t k) {
		uint64_t z = (uint64_t)k + 0x9E3779B97F4A7C15ULL;
		z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
		z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
		return (size_t)(z ^ (z >> 31));
	}

	void grow() {
		std::vector<int64_t> old_keys;
		std::vector<V> old_values;
		old_keys.swap(keys);
		old_values.swap(values);
		size_t capacity = old_keys.empty() ? 64 : old_keys.size() * 2;
		keys.assign(capacity, EMPTY);
		values.assign(capacity, V());
		mask = capacity - 1;
		count = 0;
		for (size_t i = 0; i < old_keys.size(); i++) {
			if (old_keys[i] != EMPTY) {
				set(old_keys[i], old_values[i]);
			}
		}
	}

public:
	/// The value's slot, or null.
	const V *find(int64_t key) const {
		if (keys.empty() || key == EMPTY) {
			return nullptr;
		}
		size_t i = hash(key) & mask;
		while (true) {
			int64_t k = keys[i];
			if (k == key) {
				return &values[i];
			}
			if (k == EMPTY) {
				return nullptr;
			}
			i = (i + 1) & mask;
		}
	}

	void set(int64_t key, const V &value) {
		if (key == EMPTY) {
			return; // never a generator key; a memo miss costs only time
		}
		if ((count + 1) * 2 > keys.size()) {
			grow();
		}
		size_t i = hash(key) & mask;
		while (true) {
			int64_t k = keys[i];
			if (k == key) {
				values[i] = value;
				return;
			}
			if (k == EMPTY) {
				keys[i] = key;
				values[i] = value;
				count++;
				return;
			}
			i = (i + 1) & mask;
		}
	}
};

/// A list of doubles that stays where it is while more are made (memoized buckets and parent
/// lists are read while nested evaluations add others).
using List = std::vector<double>;

class ListStore {
	std::deque<List> lists;

public:
	const List *add(List &&list) {
		lists.push_back(std::move(list));
		return &lists.back();
	}
};

// ---- the plan and the job's grids -------------------------------------------------------------

struct Relation {
	int target = 0;
	double distance = 0.0, transition = 0.0, influence = 0.0;
};

/// A mass rule's zone fields (ScatterMass.zone_rule).
struct ZoneRule {
	float keep[4] = { 1, 1, 1, 1 };
	int family[4] = { 0, 1, 2, 3 };
	double shoulder = 0.0, core = 0.0, share = 0.0, fill = 0.0;
};

/// A bare_params record: [threshold, scale_m, offset, margin, stretch, angle, break, seed, cos, sin].
struct BareRecord {
	double threshold = 0.0, scale_m = 1.0, margin = 0.0, stretch = 1.0, angle = 0.0, brk = 0.0;
	double cos_a = 1.0, sin_a = 0.0;
	Vector2 offset;
	int64_t seed = 0;
};

struct ZonesRecord;

struct Entry {
	std::string key;
	std::vector<std::string> assets;
	int index = 0, ground_role = 0, field = -1, parent_field = -1, asset_count = 1;
	bool clumped = false, mass = false, referenced = false, align_normal = false;
	bool clump_scale = false, mass_follow = false, has_noise = false;
	double spacing = 0.0, clearance_m = 0.0, slope_max = 0.0, slope_cos = -2.0;
	double influence = 0.0, scale_influence = 0.0, footing_m = 0.0;
	double yaw_range = 0.0, scale_spread = 0.0, scale_floor = 0.0;
	double response_lead = 1.0, response_lag = 1.0;
	/// Terrain response (S12b; ScatterTerrain.keep): the slope minimum in degrees and its cosine
	/// (-2 = off) and the flattened [x0, y0, x1, y1, ...] curves on the slope, height, wet and
	/// water_dist (S12c) axes (empty = none). `has_response` gates the whole block, so legacy
	/// rules skip it.
	double slope_min = 0.0, slope_min_cos = -2.0;
	std::vector<double> curve_slope, curve_height, curve_wet, curve_water_dist;
	bool has_response = false;
	double mass_stretch = 1.0, mass_core = 1.0, mass_core_y = 1.0, mass_core_y_max = 0.0;
	double mass_core_hold = 0.0, clump_jitter = 0.0, clump_shrink = 0.0;
	double clump_radius = 0.0, clump_transition = 0.0, clump_angle_deg = 0.0, clump_angle_jitter_deg = 0.0;
	std::vector<Relation> near, avoid;
	std::vector<int> clearance;
	bool has_zone = false;
	ZoneRule zone;
	ZonesRecord *zones = nullptr;
	std::vector<BareRecord> *bare = nullptr;
	/// Pattern noise (ScatterGenerator._noise): FastNoiseLite settings and contrast.
	int noise_seed = 0, noise_octaves = 1;
	float noise_frequency = 0.0f;
	double noise_contrast = 0.0;
	/// Whether RockKeep.blockers_for gives this species the job's blockers.
	bool blocked_by_rocks = false;
};

struct FieldPlan {
	int64_t seed = 0;
	double bucket = 1.0, spacing = 0.0;
	std::vector<int> owners;
	std::vector<double> cdf;
	bool empty = true;
};

/// The constants the port shares with GDScript (ScatterNative.consts(), read once per job).
struct Consts {
	int candidates_per_bucket = 4;
	double clump_saturation = 3.0, row_step = 1e-6, anchor_step = 1e-4, tile_m = 4.0;
	int tile_min_buckets = 16;
	bool additive_clumps = true;
	// GroundSnap
	int footing_directions = 4;
	double footing_sag_m = 0.06, footing_slope_tan = 1.19;
	// GroundZones
	double bound_slack = 1e-6, flow_step = 1.0;
	// GroundAccents
	std::vector<uint8_t> lattice;
	int noise_cells = 32;
	double accent_edge = 0.0, detail = 0.0, detail_scale = 1.0, fine = 0.0, fine_scale = 1.0;
	Vector2 detail_offset, fine_offset, rotation;
	// TerrainRules
	double inv_uint_max = 1.0 / 4294967295.0;
	double cliff_start_cos = 0.0, cliff_end_cos = 0.0, cliff_edge_noise = 0.0;
	double lip_curvature_start = 0.0, lip_curvature_end = 0.0, lip_strength = 0.0, lip_sheer_tail = 0.0;
	double ramp_low = 0.0, ramp_high = 1.0;
	double scree_curvature_start = 0.0, scree_curvature_end = 0.0, scree_near_start = 0.0;
	double scree_near_end = 0.0, scree_edge_noise = 0.0, scree_breakup_scale_m = 1.0, scree_fan = 0.0;
	double scree_breakup_low = 0.0, scree_breakup_high = 1.0;
	double rule_noise_scale_m = 1.0, rule_noise_shear = 0.0;
	double paint_edge_warp_m = 0.0, paint_edge_scale_m = 1.0, paint_edge_noise = 0.0;
	double paint_cliff_yield = 1.0, paint_water_yield = 1.0, paint_ford_start_m = 0.0, paint_ford_end_m = 1.0;
	Vector2 cliff_noise_offset, scree_noise_offset, scree_breakup_offset;
	Vector2 paint_warp_offset_a, paint_warp_offset_b, paint_noise_offset;
	// ScatterGround
	int role_cover = 0, role_rock = 1, role_tree = 2, role_shrub = 3, role_tall_cover = 4, role_bits = 7;
	int edge_bank = 8, edge_emergent = 16, flower_bit = 32, charred_bit = 128;
	double scree_thin = 0.5, scree_rock_boost = 0.8, flower_verge_fill = 0.0, flower_verge_gather = 0.0;
	double edge_boost = 0.0, paved_clear_start = 0.0, paved_clear_full = 1.0;
	double tree_face_start = 0.0, tree_face_full = 1.0, shrub_face_start = 0.0, shrub_face_full = 1.0;
	double fringe_start = 0.0, fringe_full = 1.0;
	// ScatterGround's wet factor and WaterDressing
	int arid_bit = 64;
	double depth_scale = 1.0, wet_clear_start = 0.0, wet_clear_full = 1.0;
	/// ScatterTerrain.WATER_DIST_MAX_M: the water_dist axis' cap and the value without a grid.
	double water_dist_max_m = 64.0;
	double emergent_depth_start_m = 0.0, emergent_depth_full_m = 1.0;
	double tree_shore_start = 0.0, tree_shore_full = 1.0, shrub_shore_start = 0.0, shrub_shore_full = 1.0;
	double shrub_shore_keep = 0.0, tall_shore_start = 0.0, tall_shore_full = 1.0, flower_shore_thin = 0.0;
	double arid_shore_start = 0.0, arid_shore_full = 1.0;
	// CrossingGeometry.clearance
	double clear_margin_m = 0.0, clear_anchor_m = 0.0, clear_soft_m = 1.0, clear_tree_m = 0.0, clear_shrub_m = 0.0;
};

/// A crossing as CrossingGeometry.clearance reads it.
struct CrossingSpan {
	Vector2 start, end;
	double width_m = 0.0;
};

/// One whole-grid float32 array of the job, read through its pointer: either held from the job's
/// Dictionary (not copied) or computed here from the document (scatter_grids.cpp) and owned.
struct Grid {
	godot::PackedFloat32Array hold;
	std::vector<float> own;
	const float *p = nullptr;
	int64_t n = 0;

	void take(const godot::PackedFloat32Array &a) {
		hold = a;
		p = hold.is_empty() ? nullptr : hold.ptr();
		n = hold.size();
	}
	void adopt(std::vector<float> &&v) {
		own = std::move(v);
		p = own.empty() ? nullptr : own.data();
		n = (int64_t)own.size();
	}
	bool empty() const { return p == nullptr; }
	int64_t size() const { return n; }
	float operator[](int64_t i) const { return p[i]; }
};

/// The window's grids (document_fields and ScatterGround.sampler's arrays), whole-grid sized.
struct Grids {
	int columns = 0, rows = 0;
	Vector2 step, half;
	int64_t seed_value = 0;
	Grid density, heights, curvature, steep, near_face;
	Grid paint_total, paint_built, paint_rock, paint_ash, fringe;
	/// WaterDressing's field (CHANNELS bytes per sample) when `wet`.
	godot::PackedByteArray water_hold;
	const uint8_t *water = nullptr;
	/// ScatterTerrain.water_distance_grid (one float per sample, metres to the nearest water,
	/// capped at WATER_DIST_MAX_M) when `water_dist_ok`; otherwise the cap is read everywhere.
	godot::PackedFloat32Array water_dist_hold;
	const float *water_dist = nullptr;
	bool water_dist_ok = false;
	std::vector<CrossingSpan> crossings;
	bool paints = false, fringed = false, wet = false;
};

/// ScatterNative.grids_for in C++ (scatter_grids.cpp): the window's density, curvature, steepness,
/// face proximity, painted fields and fringe from the document's own arrays in `source`
/// (ScatterNative.pack's "source"), the same values bit for bit. Fills every Grid of `grids` and
/// its sizes; water and crossings are left to the loader. False when `source` is malformed.
bool build_grids(const godot::Dictionary &source, Grids &grids);

} // namespace ttscatter
