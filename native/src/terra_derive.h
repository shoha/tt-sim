// TerraDerive: the derived world of a terraforming document, evaluated on the CPU over dirty tiles
// (from spike terraform-s2-cpu; production since card terraform-p1-native, 2026-11-22;
// docs/systems/terraform.md). GDScript sends primitives (set, append dabs, remove); derive() runs
// the fixed stage chain over what changed and returns the stage timings and the tiles whose data
// changed. Each stage records which samples actually changed, so the next stage's work is that set
// grown by its halo, never a guess. GDScript never names the class: utils/terraform/terra_core.gd
// finds it through ClassDB, so every script parses where the library is absent.
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
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "terra_stages.h"

namespace terra {
class Pool;

/// A read-only view of every derived array and record, for C++ stages built on a TerraDerive (the
/// Painted stages): whole-map arrays of g.w * g.h samples, row-major (CT 4 bytes a sample).
struct DerivedView {
	const Grid &g;
	const std::vector<float> &H2, &WL, &SL, &DW, &DP, &DF, &PW, &HB, &CV;
	const std::vector<uint8_t> &PM, &FM, &WM, &PI, &CT;
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
	std::vector<float> Hraw, SW, H0, H1, WL, Hp, H2, SL, DW, DP, DF, PW, HB, CV;
	std::vector<uint8_t> PM, FM, WM, PI, CT;
	terra::Water water;
	std::vector<terra::PathL> paths;
	std::vector<terra::Wall> walls;
	terra::Dirty seed_c, seed_w, seed_p, seed_f, seed_paint;
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

protected:
	static void _bind_methods();

public:
	TerraDerive();
	~TerraDerive();

	/// "terra 1 core": TerraCore.NATIVE_VERSION must equal it (a stale library fails its tests).
	String version() const;
	/// Allocates a w x h sample grid over a map of `extent` metres, centred on the origin (sample
	/// (0, 0) at -extent / 2), and forgets the document. TerraCore passes 2 (n - 1) + 1 per axis of
	/// the map document's n samples and the document's extent_m().
	void setup(int64_t w, int64_t h, const Vector2 &extent);
	/// Worker threads beside the caller (0: every stage runs on the caller); the bits never depend
	/// on it.
	void set_threads(int64_t n);
	/// Adds or replaces a primitive (document order is insertion order).
	void set_prim(int64_t id, int64_t type, const PackedFloat32Array &data);
	/// Appends floats (whole dabs) to a primitive; only the new dabs' bounds are dirtied.
	void append_dabs(int64_t id, const PackedFloat32Array &data);
	void remove_prim(int64_t id);
	void clear_prims();
	/// The ground table: rows of [class, term_count, (field, lo, hi, soft) * term_count].
	void set_rules(const Array &rows);
	/// Re-derives what the pending edits dirtied; {"usec": {stage: us}, "tiles_height", ...}.
	Dictionary derive();
	/// Every stage over the whole map (a first load without a cache).
	Dictionary derive_full();
	/// derive() on a worker thread (a stroke's release); poll take_result() each frame.
	void derive_async();
	bool is_busy() const;
	/// The async derive's result once it has finished (joined), else an empty Dictionary.
	Dictionary take_result();
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
	/// golden fixture.
	Dictionary digests() const;
	int64_t memory_bytes() const;

	/// C++ only: every derived array and record, for stages built on this derive.
	terra::DerivedView derived() const;
};

} // namespace godot
