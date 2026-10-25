// The native generator's classes: the job as loaded (Job), the CPU noises the grass masses
// read (ZonesRecord: GroundZones; Accents: GroundAccents and ScatterMass's bare openings), the
// document_fields samplers over the job's grids (Ground: ScatterGround.sampler and the
// terrain's height and normal), and the per-call context (Ctx: ScatterGenerator, ScatterClumps
// and ScatterMass), each line for line with its GDScript. One Ctx per call, nothing static
// that changes, so concurrent calls share nothing.
#pragma once

#include <array>
#include <memory>

#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include "scatter_core.h"

#include <FastNoiseLite.h>

namespace ttscatter {

using Hash4 = std::array<double, 4>;

/// A GroundZones record (GroundZones.record) and its lattice-hash memo.
struct ZonesRecord {
	double scale_m[3] = {}, angle_k[3] = {}, stretch_k[3] = {}, cover[3] = {}, edge[3] = {};
	double angle = 0, stretch = 1, warp = 0, nest = 0, rag = 0, rag_m = 1, stroke_edge = 1;
	double edge_vary = 0, edge_vary_m = 1, stroke = 0, stroke_m = 1, stroke_len = 1;
	double stroke_soft_lo = 0, stroke_soft_hi = 0, stroke_soft_m = 1;
	Vector2 seed;
	double shape_scale[3] = {}, shape_angle[3] = {}, shape_stretch[3] = {};
	Vector2 shape_offset[3];
	const Consts *c = nullptr;
	I64Map<Hash4> hashes;

	void zone_weights(double x, double z, double *w);
	bool share_reaches(double x, double z, const int *families, int family, double share);
	double zone_flow(double x, double z);
	static double family_share(const double *w, const int *families, int family);

private:
	double zone_mask(Vector2 p, int k);
	double stroke_pick(Vector2 p, double m, int k);
	double edge_at(Vector2 xz, double edge, double k);
	Vector2 zone_slope(Vector2 p, int k);
	double zone_shape(Vector2 xz, int k, bool rag, double bare_lo, double bare_hi);
	double noise(Vector2 p);
	static double hash(Vector2 p);
};

/// GroundAccents' octave lattice and ScatterMass's bare openings (bare_keep, _accent_noise).
class Accents {
	const Consts &c;
	I64Map<Hash4> memo;

	double accent_noise(Vector2 xz, const BareRecord &record, double below, double above);
	double octave(Vector2 p, int channel) const;
	double value_noise_memo(Vector2 p, int64_t seed);

public:
	explicit Accents(const Consts &consts) :
			c(consts) {}
	double bare_keep(const std::vector<BareRecord> &bare, double x, double z);
};

/// TerrainRules.pcg2d_x.
int64_t pcg2d_x(int64_t x, int64_t y);

/// The document_fields Callables over the job's grids (ScatterGenerator.document_fields with
/// ScatterGround.sampler): painted surfaces, the path fringe, the rule noise on steep ground,
/// wet dressing (WaterDressing.sample, wet_factor) and crossings (CrossingGeometry.clearance).
class Ground {
	const Grids &g;
	const Consts &c;

	Vector3 ground_at(Vector2 p, int role) const;
	Vector2 weights(double normal_y, Vector2 fields, Vector2 xz, double y) const;
	double value_noise(Vector2 p) const;
	double rule_noise(Vector2 xz, double y, Vector2 offset) const;
	double cliff_from(double normal_y, double curvature, double noise) const;
	double scree_from(double curvature, double steep, double cliff, double noise, double breakup) const;
	double ease_ramp(double m) const;
	double shape_painted(double total, Vector2 xz) const;
	Vector2 painted_lookup(Vector2 xz) const;
	bool scorches(int role) const;
	double plain_at(Vector2 p) const;
	double wet_factor(int role, Vector3 water) const;
	double clearance(Vector2 p, double extra) const;

public:
	Ground(const Grids &grids, const Consts &consts) :
			g(grids), c(consts) {}
	double species_density_at(Vector2 p, int role) const;
	double density_ceiling_at(Vector2 p, int role) const;
	double height_at(Vector2 p) const;
	Vector3 normal_at(Vector2 p) const;
	/// WaterDressing.sample at sample coordinates `s` (bed, shore, depth), bilinear over the
	/// whole-document field; the caller checks `g.wet`.
	Vector3 water_at(Vector2 s) const;
	/// ScatterTerrain.wet_sampler: the shore weight (channel G) at the map position `p`, 0 on a
	/// document with no wet dressing.
	double wet_at(Vector2 p) const;
	/// ScatterTerrain.water_dist_sampler: metres to the nearest water at the map position `p`,
	/// bilinear on the job's distance grid; WATER_DIST_MAX_M without one.
	double water_dist_at(Vector2 p) const;

	static double triangle_height(const Grid &grid, int columns, int rows, Vector2 at);
	static Vector3 triangle_normal(const Grid &grid, int columns, int rows, Vector2 at, Vector2 step);
	static Vector3 vertex_normal(const Grid &grid, int columns, int rows, int64_t x, int64_t z, Vector2 step);
	static double bilinear(const Grid &grid, int columns, int rows, Vector2 at);
	static Vector2 field_at(const Grid &curvature, const Grid &steep, int columns, int rows, Vector2 at);
	static double raw_tail(double v, double start, double end);
};

/// One job as read from its Dictionary (scatter_load.cpp).
struct Job {
	Consts consts;
	Grids grids;
	std::vector<FieldPlan> fields;
	std::vector<Entry> species;
	std::deque<ZonesRecord> zones_records;
	std::deque<std::vector<BareRecord>> bare_records;
	Rect2 bounds;
	std::vector<std::vector<godot::Vector2i>> cells_by_species;
	std::vector<float> blockers;
	/// Why the job cannot run natively (empty when it can).
	std::string error;

	bool load(const godot::Dictionary &job);
};

struct LiveField {
	const FieldPlan *plan = nullptr;
	I64Map<const List *> buckets;
	I64Map<uint8_t> spaced;
};

/// ScatterGenerator._context as a class: the same memos (bucket, spacing, final, parent bucket,
/// list and tile, anchor family) and the same two shared slots (edge, anchor) that nested
/// evaluations overwrite, so the rows follow GDScript's order of effects exactly.
class Ctx {
	Job &job;
	const Consts &c;
	std::vector<Entry> &species;
	std::vector<LiveField> fields;
	std::vector<I64Map<uint8_t>> finals, parents;
	std::vector<I64Map<const List *>> parent_buckets, parent_lists, parent_tiles;
	std::vector<std::unique_ptr<fastnoiselite::FastNoiseLite>> noises;
	ListStore store;
	Ground ground;
	Accents accents;
	Rect2 bounds;
	double edge = 1.0;
	Vector2 anchor;
	I64Map<int> anchor_family;
	double w4[4] = {};

	void generate_species(int s);
	void split_rows(const Entry &entry, godot::PackedFloat32Array &rows, const std::vector<int> &assets);
	void collect_anchors(const godot::PackedFloat32Array &rows, const std::vector<float> &anchors);
	const List *bucket(LiveField &field, int64_t bi, int64_t bj);
	bool is_final(int s, const List &cands, int c);
	double pattern_value(const Entry &entry, double x, double z) const;
	bool evaluate(const Entry &entry, const List &cands, int c);
	bool unfooted(Vector2 p, double radius) const;
	bool spaced_survives(LiveField &field, const List &cands, int c);
	List higher_neighbours(LiveField &field, double x, double z, double priority, int64_t id);
	Vector2 membership(int s, double x, double z, bool refine);
	double proximity(const Relation &relation, double x, double z);
	bool occupied(int field_index, double x, double z, double clearance);
	int append_row(const Entry &entry, const List &cands, int c, double edge_value, godot::PackedFloat32Array &rows);
	static Vector3 tilted(Vector3 normal, double angle, double azimuth);
	bool blocked(const Entry &entry, Vector2 p) const;

	// ScatterClumps and ScatterMass (scatter_masses.cpp)
	const List *parents_near_bucket(int s, int64_t bi, int64_t bj);
	const List *kept_parents(int s, int64_t bi, int64_t bj);
	bool parent_kept(int s, const List &cands, int c);
	List listed(int s, const int64_t *span);
	const List *tile(int s, int64_t bi, int64_t bj, double reach);
	Vector2 mass_membership(const Entry &entry, const List &parents, double x, double z, bool refine);
	Vector2 refined(const Entry &entry, Vector2 best, double x, double z);
	double shoulder_keep(const Entry &entry, double x, double z);
	bool zone_kept(const Entry &entry, const List &cands, int c);
	double zone_share_keep(const Entry &entry, double x, double z);
	bool filled(const Entry &entry, int family, double x, double z);
	double parent_spin(const Entry &entry, double x, double z, double turn);
	double off_bare(const std::vector<BareRecord> &bare, double keep, double x, double z, double u, double shade);
	static double parent_angle(const Entry &entry, double x, double z, double angle);
	static double held_edge(const Entry &entry, double edge_value);
	static int strongest(const double *w);
	static void append_scale(godot::PackedFloat32Array &rows, double scale, const Entry &entry, double edge_value);

public:
	explicit Ctx(Job &p_job);
	/// generate_species_cells over the job's cells, into result and anchors_out.
	void generate();
	godot::Dictionary result;
	godot::Dictionary anchors_out;

	// ScatterGenerator's hashing
	static constexpr int64_t BUCKET_OFFSET = 1LL << 20;
	static constexpr int64_t BUCKET_SPAN = 1LL << 21;
	static constexpr int STRIDE = 6;
	static int64_t mix(int64_t value);
	static double unit(int64_t h, int64_t salt) { return mix(h ^ salt) / 4294967296.0; }
	static int64_t key(int64_t bi, int64_t bj) { return (bi + BUCKET_OFFSET) * BUCKET_SPAN + (bj + BUCKET_OFFSET); }
	static double respond(double density, double lead, double lag);
};

/// A FastNoiseLite set up as Godot's FastNoiseLite resource sets up the generator's pattern
/// noise (modules/noise/fastnoise_lite.cpp; ScatterGenerator._noise's settings).
void setup_pattern_noise(fastnoiselite::FastNoiseLite &noise, int seed, float frequency, int octaves);

} // namespace ttscatter
