extends GutTest

## The dry landform recipes' whole maps (the valley, with a crossing, and the terraces) through
## the native scatter equal GDScript's, every job of the build (scatter_native_landform_parity.gd;
## the wet recipes are in test_scatter_native_landforms_wet.gd). Pending, with the reason, where
## the library is not built.

const Parity := preload("res://tests/unit/scatter_native_landform_parity.gd")


func after_each() -> void:
	ScatterNative.force_gdscript = false


func test_valley_with_a_crossing_equals_gdscript() -> void:
	Parity.check(self, "valley")


func test_terraces_equal_gdscript() -> void:
	Parity.check(self, "terraces")
