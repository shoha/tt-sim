// TTScatterNative: the GDExtension face of the native scatter generator. One call per job
// (generate): the job's inputs come packed once and the rows go back in the form
// ScatterGenerator.generate_species_cells returns them. Stateless: every call builds its own
// context, so any number of WorkerThreadPool tasks may call one instance at once.
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
};

} // namespace godot
