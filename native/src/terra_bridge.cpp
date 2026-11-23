// The bridge's native half (card terraform-p2-bridge; docs/systems/terraform.md "The bridge"): the
// derived ground H2 read at the map document's samples, which are every second derive sample
// (i = 2a, j = 2b). TerraBridge (utils/terraform/terra_bridge.gd) writes the result into
// MapDocument.heights, so today's chunks, collision, skirt and scatter build from the derive. A
// packed array handed in is copy on write, so the document is only read here, never written.
#include <cstring>

#include "terra_derive.h"

namespace godot {

using namespace terra;

/// The document's sample count per axis for the derive's grid (2 (n - 1) + 1 derive samples).
static int doc_samples(int derive_samples) {
	return (derive_samples - 1) / 2 + 1;
}

PackedFloat32Array TerraDerive::doc_heights() const {
	const int dw = doc_samples(g.w), dh = doc_samples(g.h);
	PackedFloat32Array out;
	if (H2.empty()) {
		return out;
	}
	out.resize(int64_t(dw) * dh);
	float *o = out.ptrw();
	for (int b = 0; b < dh; b++) {
		const float *row = H2.data() + int64_t(2 * b) * g.w;
		for (int a = 0; a < dw; a++) {
			o[int64_t(b) * dw + a] = row[2 * a];
		}
	}
	return out;
}

Dictionary TerraDerive::doc_heights_diff(const PackedFloat32Array &heights, int64_t doc_w, const Rect2i &rect) const {
	const int dw = doc_samples(g.w), dh = doc_samples(g.h);
	Dictionary out;
	out["rect"] = Rect2i();
	out["values"] = PackedFloat32Array();
	if (H2.empty() || doc_w != dw || heights.size() != int64_t(dw) * dh) {
		out["error"] = "the heights are not this derive's document grid";
		return out;
	}
	const int a0 = std::max(rect.position.x, 0), b0 = std::max(rect.position.y, 0);
	const int a1 = std::min(rect.position.x + rect.size.x, dw), b1 = std::min(rect.position.y + rect.size.y, dh);
	const float *doc = heights.ptr();
	// The tight rect of samples whose bits differ (memcmp: -0 and +0 differ, as the stages' diff).
	int x0 = a1, y0 = b1, x1 = a0, y1 = b0;
	for (int b = b0; b < b1; b++) {
		const float *row = H2.data() + int64_t(2 * b) * g.w;
		const float *drow = doc + int64_t(b) * dw;
		for (int a = a0; a < a1; a++) {
			if (std::memcmp(&row[2 * a], &drow[a], sizeof(float)) != 0) {
				x0 = std::min(x0, a);
				x1 = std::max(x1, a + 1);
				y0 = std::min(y0, b);
				y1 = std::max(y1, b + 1);
			}
		}
	}
	if (x1 <= x0 || y1 <= y0) {
		return out;
	}
	PackedFloat32Array values;
	values.resize(int64_t(x1 - x0) * (y1 - y0));
	float *v = values.ptrw();
	for (int b = y0; b < y1; b++) {
		const float *row = H2.data() + int64_t(2 * b) * g.w;
		for (int a = x0; a < x1; a++) {
			*v++ = row[2 * a];
		}
	}
	out["rect"] = Rect2i(x0, y0, x1 - x0, y1 - y0);
	out["values"] = values;
	return out;
}

PackedByteArray TerraDerive::doc_surfaces(const Rect2i &rect) const {
	const int dw = doc_samples(g.w), dh = doc_samples(g.h);
	PackedByteArray out;
	if (PI.empty()) {
		return out;
	}
	int a0 = 0, b0 = 0, a1 = dw, b1 = dh;
	if (rect.size.x > 0 && rect.size.y > 0) {
		a0 = std::max(rect.position.x, 0);
		b0 = std::max(rect.position.y, 0);
		a1 = std::min(rect.position.x + rect.size.x, dw);
		b1 = std::min(rect.position.y + rect.size.y, dh);
	}
	if (a1 <= a0 || b1 <= b0) {
		return out;
	}
	const int64_t n = int64_t(a1 - a0) * (b1 - b0) * 4;
	out.resize(n * 2);
	uint8_t *o = out.ptrw();
	for (int p = 0; p < 2; p++) {
		const uint8_t *plane = p == 0 ? PI.data() : PW.data();
		for (int b = b0; b < b1; b++) {
			const uint8_t *row = plane + int64_t(2 * b) * g.w * 4;
			for (int a = a0; a < a1; a++) {
				std::memcpy(o, row + int64_t(2 * a) * 4, 4);
				o += 4;
			}
		}
	}
	return out;
}

} // namespace godot
