// TerrainRules.sample_fields (utils/terrain_rules.gd) in C++ (card terrainrules, 2026-11-08): the
// authored terrain's rule fields, curvature and steepness nearby, over a rectangle of the height
// grid. AuthoredTerrain.settle_heights runs it at every sculpt stroke end, carve and undo over the
// edit grown by the curvature radius (4.4-4.8 ms in GDScript at every map size), and the load and
// the scatter's GDScript fallbacks run it over whole grids and windows; the native scatter job's
// window grids (scatter_grids.cpp) call it too. Ported line for line from the GDScript, so the
// values are the same bit for bit: every sum and quotient in double, every stored value rounded to
// float, expressions grouped as GDScript groups them (test_terrain_fields_native checks it on
// random maps and rects, test_scatter_native's grid parity through the scatter window).
#pragma once

#include <cstdint>

#include <godot_cpp/variant/rect2i.hpp>

namespace ttscatter {

/// The grid and the rule constants sample_fields reads (TerrainRules.radius_samples,
/// cliff_start_cos, cliff_end_cos come from the GDScript, so the constants live in one place).
struct FieldsInput {
	const float *heights = nullptr;
	int64_t columns = 0;
	int64_t rows = 0;
	double step_x = 0.0;
	double step_y = 0.0;
	int64_t r = 1;
	double start_cos = 0.0;
	double end_cos = 0.0;
};

/// Curvature and steepness for the samples of `out` (already clipped to the grid and with an
/// area), written row-major over `out` into `curvature` and `steep` (each out.size.x *
/// out.size.y long).
void rule_fields(const FieldsInput &in, godot::Rect2i out, float *curvature, float *steep);

} // namespace ttscatter
