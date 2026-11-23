// TerraDerive: the derived world of a terraforming document, evaluated on the CPU over dirty tiles
// (from spike terraform-s2-cpu; production since card terraform-p1-native, 2026-11-22;
// docs/systems/terraform.md). GDScript sends primitives (set, append dabs, remove); derive() loops
// over the stage table (terra_stage_table.h) over what changed and returns the stage timings and
// the tiles whose data changed. Each stage records which samples of each array it writes actually
// changed, so the next stage's work is that set grown by its declared halo, never a guess.
// GDScript never names the class: utils/terraform/terra_core.gd finds it through ClassDB, so every
// script parses where the library is absent.
#pragma once

#include <atomic>
#include <map>
#include <memory>
#include <set>
#include <thread>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/rect2i.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "terra_stages.h"

namespace terra {
class Pool;
struct Pass;

/// A read-only view of every derived array and record, for C++ stages built on a TerraDerive (the
/// Painted stages): whole-map arrays of g.w * g.h samples, row-major (CT, PI and PW 4 bytes a sample).
struct DerivedView {
	const Grid &g;
	const std::vector<float> &H2, &WL, &SL, &DW, &DP, &DF, &HB, &CV;
	const std::vector<uint8_t> &PM, &FM, &WM, &PI, &PW, &CT;
	const Water &water;
	const std::vector<Wall> &walls;
};
} // namespace terra

namespace godot {

class TerraDerive : public RefCounted {
	GDCLASS(TerraDerive, RefCounted)

	terra::Grid g;
	std::vector<terra::Prim> prims;
	std::vector<terra::Rule> rules;
	std::vector<float> Hraw, SW, H0, H1, WL, Hp, H2, SL, DW, DP, DF, HB, CV;
	std::vector<uint8_t> PM, FM, WM, PI, PW, CT;
	terra::Water water;
	std::vector<terra::PathL> paths;
	std::vector<terra::Wall> walls;
	// Pending change per array: the edits' seeds on the inputs, and debug_set_sample's samples.
	terra::Dirty seeds[terra::A_COUNT];
	bool seed_rules = false;
	std::set<int> changed_ids;
	std::unique_ptr<terra::Pool> pool;
	int threads = 8;
	// A derive on a worker thread (a stroke's release); the caller must not touch this object
	// (edits, queries, tile reads) until take_result() returns the result.
	std::thread async_thread;
	std::atomic<bool> async_done{ false };
	bool async_running = false;
	Dictionary async_result;

	int find(int id) const;
	terra::Rect influence(const terra::Prim &p) const;
	void seed(const terra::Prim &p, const terra::Rect &r);
	void seed_all();
	// The stage bodies: the three solves, the rect body of each rect stage, and the loop's rect run
	// (snapshot the stage's per-sample writes, run the body, diff each write per tile).
	void solve_water(terra::Pass &ps);
	void solve_paths(terra::Pass &ps);
	void solve_walls(terra::Pass &ps);
	void paint_items(terra::Pass &ps);
	void rect_body(int stage, const terra::Rect &r, const terra::Pass &ps);
	int run_rect(const terra::StageDef &s, const terra::Dirty &region, terra::Pass &ps);
	uint8_t *array_data(int a);

protected:
	static void _bind_methods();

public:
	TerraDerive();
	~TerraDerive();

	/// "terra 10 chutes": TerraCore.NATIVE_VERSION must equal it (a stale library fails its tests).
	String version() const;
	/// Allocates a w x h sample grid over a map of `extent` metres, centred on the origin (sample
	/// (0, 0) at -extent / 2), and forgets the document. TerraCore passes 2 (n - 1) + 1 per axis of
	/// the map document's n samples and the document's extent_m().
	void setup(int64_t w, int64_t h, const Vector2 &extent);
	/// Worker threads beside the caller (0: every stage runs on the caller); the bits never depend
	/// on it.
	void set_threads(int64_t n);
	/// Adds or replaces a primitive (document order is insertion order). False, and nothing
	/// changed, when `type` is not a registered kind (kinds()).
	bool set_prim(int64_t id, int64_t type, const PackedFloat32Array &data);
	/// Appends floats (whole dabs) to a primitive; only the new dabs' bounds are dirtied.
	void append_dabs(int64_t id, const PackedFloat32Array &data);
	void remove_prim(int64_t id);
	void clear_prims();
	/// The ground table: rows of [class, term_count, (field, lo, hi, soft) * term_count].
	void set_rules(const Array &rows);
	/// Re-derives what the pending edits dirtied; {"usec": {stage: us}, "tiles_height", ...,
	/// "h2_rect": the Rect2i (derive samples) bounding every H2 sample that changed}.
	Dictionary derive();
	/// Every stage over the whole map (a first load without a cache).
	Dictionary derive_full();
	/// derive() on a worker thread (a stroke's release); poll take_result() each frame.
	void derive_async();
	bool is_busy() const;
	/// The async derive's result once it has finished (joined), else an empty Dictionary.
	Dictionary take_result();
	/// Folds the run `ids` (consecutive compose primitives in document order: strokes, levels,
	/// terraces) into sculpt rasters (kind 9): one per 64-sample tile the run's influence meets and
	/// changed, each the floats of a sculpt primitive. Put in the run's place (one splice), they derive
	/// as the run did. Reads the primitives as set (pending edits included), writes nothing; tiles run
	/// on the pool. Empty when an async derive runs or `ids` is not such a run
	/// (terra_consolidate.cpp).
	Array consolidate(const PackedInt32Array &ids) const;
	/// A tile's collision heights: the derived ground in metres over every `stride`-th sample of
	/// [64 tx, 64 tx + 65) per axis (shared edges, clipped at the map), row-major;
	/// {"w", "d", "heights", "min", "max", "step": Vector2 metres between the heights per axis}.
	Dictionary tile_collision(int64_t tile, int64_t stride) const;

	/// The grid: {"w", "h", "step": Vector2, "origin": Vector2 (sample 0's world x, z)}.
	Dictionary grid() const;
	int64_t tiles_x() const;
	int64_t tiles_y() const;
	/// One tile layer, (64 + 2) squared with a one-sample apron: kind 0 RGF heights (ground,
	/// water), 1 RGBA8 control, 2 RGBA8 fields (water, path, foot distances, slope), 3 RGF look
	/// (band-limited height, convexity).
	PackedByteArray tile_bytes(int64_t tile, int64_t kind) const;
	bool tile_has_water(int64_t tile) const;
	double height_at(double x, double z) const;
	double water_at(double x, double z) const;
	/// The first ground hit along a ray: {"hit": bool, "pos": Vector3}.
	Dictionary raycast(const Vector3 &from, const Vector3 &dir, double max_dist) const;
	/// Fall records, 7 floats each: x, z, tx, tz, top, bottom, width.
	PackedFloat32Array falls() const;
	/// Per wall {"id", "height", "thick", "pts": [x, z, pad, solid] * n}.
	Array walls_out() const;
	/// The water bodies as solved: {"rivers": [{"id", "level" (per point of "pts", downstream),
	/// "pts", "hw", "falls" (count), "recv_river", "recv_pond" (ids, -1 none)}], "ponds": [{"id",
	/// "level"}]}.
	Dictionary water_records() const;
	/// FNV-1a digests of every derived array and record list, for update-equals-build and the
	/// golden fixture and the derived record's load check (TerraCache). The arrays hash in parallel
	/// on the pool, one FNV chain each, unless an async derive holds it.
	Dictionary digests() const;
	int64_t memory_bytes() const;
	/// The stage table in run order: per stage {"name", "shape" ("rect", "graph", "line_rect"),
	/// "reads", "writes" (array names), "halo" (samples; -1 for a graph stage's exact read points),
	/// "reach_m" (metres a solved line's change reaches past its half width)}.
	Array stages() const;
	/// Every array the stages name: {"name", "kind" ("input", "samples", "record"), "bytes" a sample}.
	Array arrays() const;
	/// The kind registry (terra_kinds.h), sorted by id: per kind {"id", "name", "stage" (a stage's
	/// name), "shape" ("stamp", "line", "water"), "header", "stride"}.
	Array kinds() const;
	/// Ids registered twice when the library loaded (0 in a sound build).
	int64_t kind_conflicts() const;
	/// The world box (x, z) a primitive of `kind` with `data` can change, reaches included; an
	/// empty Rect2 for the whole map, an unknown kind or no data.
	Rect2 kind_bounds(int64_t kind, const PackedFloat32Array &data) const;
	/// Tests only: the table the registry's insert builds from its own kinds taken in `order`
	/// (indices into kinds()), as kinds() gives it; equal to kinds() for every order.
	Array debug_kinds_in_order(const PackedInt32Array &order) const;
	/// A per-sample array's whole-map bytes, row-major (empty for an input, a record or a bad name).
	PackedByteArray array_bytes(const String &name);
	/// Tests only (halo honesty): sets one sample of a per-sample array outside the chain and marks
	/// it changed for the next derive() (or the whole array, with dirty_all), as if its writer had.
	void debug_set_sample(const String &name, int64_t i, int64_t j, double value, bool dirty_all);

	/// The bridge (terra_bridge.cpp): H2 at the map document's samples (derive sample (2a, 2b) is
	/// document sample (a, b)), the whole array, row-major (empty before a derive).
	PackedFloat32Array doc_heights() const;
	/// H2 at the document's samples over document rect `rect` (clipped), compared bit for bit with
	/// `heights` (the document's, `doc_w` samples a row): {"rect": the tight Rect2i of samples that
	/// differ (empty when equal), "values": H2 over that rect, row-major}; plus "error" when the
	/// heights are not this grid's.
	Dictionary doc_heights_diff(const PackedFloat32Array &heights, int64_t doc_w, const Rect2i &rect) const;
	/// The paint planes at the document's samples over document rect `rect` (clipped; an empty
	/// rect for the whole map) in SurfaceStroke.read_block's form: the rect's index rows (4 bytes a
	/// sample), then its weight rows. Over the whole map that is MapDocument.surface_weights.
	PackedByteArray doc_surfaces(const Rect2i &rect) const;

	/// C++ only: every derived array and record, for stages built on this derive.
	terra::DerivedView derived() const;
};

} // namespace godot
