extends GutTest

## The wet landform recipes' whole maps (the hilltop, the lakeshore and the gorge, each with its
## water) through the native scatter equal GDScript's, every job of the build
## (scatter_native_landform_parity.gd; the dry recipes are in test_scatter_native_landforms_dry.gd).
## Pending, with the reason, where the library is not built.

const Parity := preload("res://tests/unit/scatter_native_landform_parity.gd")


func after_each() -> void:
	ScatterNative.force_gdscript = false


func test_hilltop_equals_gdscript() -> void:
	Parity.check(self, "hilltop")


func test_lakeshore_equals_gdscript() -> void:
	Parity.check(self, "lakeshore")


func test_gorge_equals_gdscript() -> void:
	Parity.check(self, "gorge")
