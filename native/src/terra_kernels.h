// The compose-stage kernel table (from spike terraform-s2-cpu). A landform tool is one primitive
// type and one kernel here: `bounds` says which world box it can touch (a plane: everything),
// `apply` changes the composed height H (and the smoothing weight SW) for the samples of a rect,
// per sample and in document order, so any rect gives the same bits. Today the table is the one in
// terra_compose.cpp; the kind registry card replaces it with self-registering kind files.
#pragma once

#include "terra_core.h"

namespace terra {

struct ComposeKernel {
	int type;
	/// The world box the primitive can change; false when it covers the whole map.
	bool (*bounds)(const Prim &p, double &x0, double &z0, double &x1, double &z1);
	/// Applies the primitive to H (and SW) over the samples of `r` (already clipped).
	void (*apply)(const Prim &p, const Grid &g, const Rect &r, float *H, float *SW);
};

/// The kernel for a primitive type, or null when the type is not a compose primitive.
const ComposeKernel *compose_kernel(int type);

/// The world box of a dab list with `stride` floats per dab, [cx, cz, radius, ...].
bool dab_bounds(const Prim &p, int stride, double &x0, double &z0, double &x1, double &z1);

} // namespace terra
