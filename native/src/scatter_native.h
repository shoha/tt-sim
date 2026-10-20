// TTScatterNative: the GDExtension face of the native scatter generator. One call per job
// (generate): the job's inputs come packed once (utils/scatter_native.gd) and the rows go back
// in the form ScatterGenerator.generate_species_cells returns them. Stateless: every call builds
// its own context, so any number of WorkerThreadPool tasks may call one instance at once.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>

namespace godot {

class TTScatterNative : public RefCounted {
	GDCLASS(TTScatterNative, RefCounted)

protected:
	static void _bind_methods();

public:
	/// A build stamp, to tell which library a run loaded.
	String version() const;
	/// 2 * value + 1: the toolchain smoke test's call.
	int64_t ping(int64_t value) const;
	/// One job (ScatterNative.pack's Dictionary): {"rows": asset id -> PackedFloat32Array,
	/// "anchors": Vector2 -> Vector2, "usec": int}, or {"error": reason} when it cannot run here.
	Dictionary generate(const Dictionary &job) const;
	/// The pattern noise's get_noise_2d at each (x, z) pair of `xz`, set up as
	/// ScatterGenerator._noise sets up its FastNoiseLite: the parity check's call.
	PackedFloat32Array noise_2d(int64_t seed, double frequency, int64_t octaves, const PackedFloat64Array &xz) const;
	/// The window's grids the library computes from a job's "source" (ScatterNative.pack), as
	/// whole-grid arrays keyed as ScatterNative.grids_for keys them, or {"error"}: the grid
	/// parity check's call.
	Dictionary grids(const Dictionary &source) const;
};

} // namespace godot
