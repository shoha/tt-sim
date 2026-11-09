// The load path's rows-to-instance-buffer step (card scatterload, 2026-11-09): one call turns a
// chunk's saved rows into everything AuthoredScatter builds its settled node from, bit for bit
// what the per-instance GDScript path gives (utils/scatter_rows.gd chunk_gdscript, then
// ScatterGlbUtils.build_multimesh; test_scatter_native_chunk compares them, and CI's native
// parity runs it on every platform):
//   keys    ScatterRows.row_keys of every row (the identity from X, Z and scale bits);
//   order   ScatterRows.instance_order of the chosen rows, seeded by the node name's md5 word;
//   buffer  the MultiMesh buffer of those rows in that order: per instance the Transform3D as
//           Godot's TRANSFORM_3D layout stores it (basis rows, each followed by the origin's
//           component), then, when any instance has a grass-mass anchor, the custom data
//           Color(0, dx, dz, 1) (Color(0, 0, 0, 0) for one without), ScatterMass.custom_data's
//           values at set_instance_custom_data's place.
// The transform uses godot-cpp's Quaternion and Basis, ports of the engine's own float maths, so
// it matches ScatterRows.row_transform under -ffp-contract=off (SConstruct). Stateless and
// read-only on its arguments: safe on WorkerThreadPool tasks.
#include "scatter_native.h"

#include <algorithm>
#include <cstring>
#include <vector>

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;

namespace {

// MapDocument.ROW_STRIDE: [lx, ly, lz, qx, qy, qz, qw, sx, sy, sz].
constexpr int64_t ROW_STRIDE = 10;
// ScatterRows._INDEX_BITS: the row index packed under the rank while sorting.
constexpr int INDEX_BITS = 24;
constexpr int64_t INDEX_MASK = (int64_t(1) << INDEX_BITS) - 1;
// Floats per instance: the 3x4 transform, and the custom data Color after it.
constexpr int64_t TRANSFORM_FLOATS = 12;
constexpr int64_t CUSTOM_FLOATS = 4;

// ScatterRows.mix: the 32-bit xorshift-multiply hash.
inline uint32_t mix(uint32_t h) {
	h ^= h >> 16;
	h *= 0x7FEB352Du;
	h ^= h >> 15;
	h *= 0x1B873593u;
	h ^= h >> 16;
	return h;
}

inline uint32_t bits_of(float f) {
	uint32_t u;
	std::memcpy(&u, &f, sizeof(u));
	return u;
}

// ScatterRows.row_keys of one row.
inline int64_t row_key(const float *row) {
	uint32_t x = bits_of(row[0]), z = bits_of(row[2]), s = bits_of(row[7]);
	uint32_t high = mix(x ^ mix(z));
	uint32_t low = mix(z ^ mix(s ^ 0x5BD1E995u) ^ mix(x));
	return (int64_t(high & 0x3FFFFFFFu) << 32) | int64_t(low);
}

// ScatterRows.row_transform's basis (a zero quaternion is no rotation).
inline Basis row_basis(const float *row) {
	Quaternion q(row[3], row[4], row[5], row[6]);
	q = q.length_squared() > 0.0f ? q.normalized() : Quaternion();
	return Basis(q).scaled(Vector3(row[7], row[8], row[9]));
}

} // namespace

Dictionary TTScatterNative::chunk(const PackedFloat32Array &rows, const Variant &indices, int64_t seed, const Dictionary &anchors) const {
	Dictionary out;
	const int64_t count = rows.size() / ROW_STRIDE;
	const float *p = rows.ptr();
	PackedInt64Array keys;
	keys.resize(count);
	int64_t *k = keys.ptrw();
	for (int64_t r = 0; r < count; r++) {
		k[r] = row_key(p + r * ROW_STRIDE);
	}
	// The chosen rows: all of them for null (the load path), else the given indices.
	std::vector<int64_t> packed;
	if (indices.get_type() == Variant::NIL) {
		packed.resize(count);
		for (int64_t r = 0; r < count; r++) {
			packed[r] = r;
		}
	} else if (indices.get_type() == Variant::PACKED_INT32_ARRAY) {
		PackedInt32Array chosen = indices;
		packed.resize(chosen.size());
		const int32_t *c = chosen.ptr();
		for (int64_t i = 0; i < chosen.size(); i++) {
			if (c[i] < 0 || c[i] >= count || c[i] > INDEX_MASK) {
				out["error"] = String("indices");
				return out;
			}
			packed[i] = c[i];
		}
	} else {
		out["error"] = String("indices");
		return out;
	}
	if (count > INDEX_MASK + 1) {
		out["error"] = String("rows");
		return out;
	}
	// ScatterRows.instance_order: sort by (rank << 24 | index), rank = mix(low ^ seed ^ high).
	const uint32_t seed_value = uint32_t(seed);
	for (int64_t &entry : packed) {
		int64_t key = k[entry];
		uint32_t rank = mix(uint32_t(key & 0xFFFFFFFF) ^ seed_value ^ uint32_t(key >> 32));
		entry = (int64_t(rank) << INDEX_BITS) | entry;
	}
	std::sort(packed.begin(), packed.end());
	const int64_t n = (int64_t)packed.size();
	PackedInt32Array order;
	order.resize(n);
	int32_t *o = order.ptrw();
	for (int64_t i = 0; i < n; i++) {
		o[i] = int32_t(packed[i] & INDEX_MASK);
	}
	// ScatterMass.custom_data: the anchored instances' offsets, custom data only if any.
	std::vector<Vector2> offsets;
	std::vector<uint8_t> anchored;
	bool custom = false;
	if (!anchors.is_empty() && n > 0) {
		offsets.resize(n);
		anchored.assign(n, 0);
		for (int64_t i = 0; i < n; i++) {
			const float *row = p + int64_t(o[i]) * ROW_STRIDE;
			Variant v = anchors.get(Vector2(row[0], row[2]), Variant());
			if (v.get_type() == Variant::VECTOR2) {
				offsets[i] = v;
				anchored[i] = 1;
				custom = true;
			}
		}
	}
	const int64_t stride = TRANSFORM_FLOATS + (custom ? CUSTOM_FLOATS : 0);
	PackedFloat32Array buffer;
	buffer.resize(n * stride);
	float *w = buffer.ptrw();
	for (int64_t i = 0; i < n; i++) {
		const float *row = p + int64_t(o[i]) * ROW_STRIDE;
		const Basis b = row_basis(row);
		float *d = w + i * stride;
		d[0] = b.rows[0][0];
		d[1] = b.rows[0][1];
		d[2] = b.rows[0][2];
		d[3] = row[0];
		d[4] = b.rows[1][0];
		d[5] = b.rows[1][1];
		d[6] = b.rows[1][2];
		d[7] = row[1];
		d[8] = b.rows[2][0];
		d[9] = b.rows[2][1];
		d[10] = b.rows[2][2];
		d[11] = row[2];
		if (custom) {
			const bool on = anchored[i] != 0;
			d[12] = 0.0f;
			d[13] = on ? offsets[i].x : 0.0f;
			d[14] = on ? offsets[i].y : 0.0f;
			d[15] = on ? 1.0f : 0.0f;
		}
	}
	out["keys"] = keys;
	out["order"] = order;
	out["buffer"] = buffer;
	out["custom"] = custom;
	return out;
}
