// Registers the native scatter generator with Godot (the extension's one class, TTScatterNative).
// GDScript never names the class as an identifier: utils/scatter_native.gd finds it through
// ClassDB, so every script still parses where this library is absent.
#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "scatter_native.h"

using namespace godot;

static void initialize_ttscatter(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(TTScatterNative);
}

static void uninitialize_ttscatter(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT ttscatter_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_ttscatter);
	init_obj.register_terminator(uninitialize_ttscatter);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
