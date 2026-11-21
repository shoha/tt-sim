// WaterField's hot passes in C++ (card painter-water-latency, 2026-11-20): the spill relaxation
// (_spill_pass), the buried rings, depth, slope and energy pass (_derive), the exact distance to
// the waterline with its distance transform and marching-triangles contour (_shore), and the
// course raster of RiverProfile.field. Ported line for line from utils/water_field.gd and
// utils/river_profile.gd, so every output array is the same bit for bit: every intermediate in
// the type GDScript holds it in (a float is a double, a Vector2 component a float32), every stored
// value rounded to float (test_water_field_native checks a full build and edits against the
// GDScript). Each call takes the field's arrays by name in one Dictionary and returns the arrays it
// changed (the packed arrays are copy-on-write, so the caller's own stay as they were until it
// assigns the results).
#pragma once

#include <godot_cpp/variant/dictionary.hpp>

namespace ttscatter {

/// WaterField._spill_pass: {"base", "bounds"} from "rect", "size", "raw", "spill", "was", "ground",
/// "base", "step", "diag" and the spill constants (see the .cpp for the keys).
godot::Dictionary water_spill(const godot::Dictionary &args);

/// WaterField._derive over "inner": {"w", "ew", "depth", "steep", "energy"}.
godot::Dictionary water_derive(const godot::Dictionary &args);

/// WaterField._shore over "outer": {"shore"}.
godot::Dictionary water_shore(const godot::Dictionary &args);

/// RiverProfile.field's segment raster over "rect": {"distance", "along", "half_width"}.
godot::Dictionary water_raster(const godot::Dictionary &args);

/// WaterFieldStroke.foot_seams over "region": {"foot"} from "size", "raw", "out", "areas",
/// "cleared", "no_foot" and "jump" (card painter-water-editcost).
godot::Dictionary water_foot_seams(const godot::Dictionary &args);

/// WaterFieldMesh.build's cells, vertices and indices (water_field_mesh.cpp): {"vertices", "normals",
/// "uvs", "c0", "c1", "c2", "indices", "aabb"}; c2 carries the marks ("film", "bank").
godot::Dictionary water_mesh(const godot::Dictionary &args);

/// The two RGBAF textures PainterWaterField._upload_textures packs from the field: {"a", "b"}.
godot::Dictionary water_textures(const godot::Dictionary &args);

} // namespace ttscatter
