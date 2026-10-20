#include "scatter_native.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void TTScatterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &TTScatterNative::version);
	ClassDB::bind_method(D_METHOD("ping", "value"), &TTScatterNative::ping);
}

String TTScatterNative::version() const {
	return String("ttscatter 1");
}

int64_t TTScatterNative::ping(int64_t value) const {
	return 2 * value + 1;
}
