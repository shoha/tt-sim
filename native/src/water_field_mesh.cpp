// WaterFieldMesh.build and PainterWaterField._upload_textures' packing in C++: see water_field.h.
// The comments name the GDScript's passes; every value is the one GDScript computes (doubles for
// its floats, float32 for its Vector2 and Vector3 and packed arrays).
#include "water_field.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;

namespace ttscatter {

namespace {

constexpr float DRY = -INFINITY;

struct Args {
	const Dictionary &d;
	Variant operator[](const char *key) const {
		return d[String(key)];
	}
};

inline double maxd(double a, double b) {
	return a > b ? a : b;
}

} // namespace

Dictionary water_mesh(const Dictionary &args) {
	const Args a{ args };
	const Vector2i size = a["size"];
	const Vector2 origin = a["origin"];
	const double step_x = (double)((Vector2)a["step"]).x;
	const double step_y = (double)((Vector2)a["step"]).y;
	const PackedFloat32Array w_a = a["w"];
	const PackedFloat32Array ew_a = a["ew"];
	const PackedFloat32Array depth_a = a["depth"];
	const PackedFloat32Array ground_a = a["ground"];
	const PackedFloat32Array energy_a = a["energy"];
	const PackedFloat32Array shore_a = a["shore"];
	const PackedFloat32Array steep_a = a["steep"];
	const PackedFloat32Array river_a = a["river"];
	const PackedFloat32Array foot_a = a["foot"];
	const PackedByteArray spill_a = a["spill"];
	const PackedByteArray calm_a = a["calm"];
	const int spill_pond = (int)(int64_t)a["spill_pond"];
	const int spill_bank = (int)(int64_t)a["spill_bank"];
	const double pond_mark = a["pond_mark"];
	const double bank_mark = a["bank_mark"];
	const double film_mark = a["film_mark"];
	const double field_flag = a["field_flag"];
	const double no_foot = a["no_foot"];
	const int nx = size.x;
	const int nz = size.y;
	const float *w = w_a.ptr();
	const float *ew = ew_a.ptr();
	const float *depth = depth_a.ptr();
	const float *ground = ground_a.ptr();
	const float *energy = energy_a.ptr();
	const float *shore = shore_a.ptr();
	const float *steep = steep_a.ptr();
	const float *river = river_a.ptr();
	const float *foot = foot_a.ptr();
	const uint8_t *spill = spill_a.ptr();
	const uint8_t *calm = calm_a.ptr();

	const int cx = nx - 1 > 0 ? nx - 1 : 0;
	const int cz = nz - 1 > 0 ? nz - 1 : 0;
	std::vector<uint8_t> cells((size_t)cx * cz, 0);
	for (int z = 0; z < cz; z++) {
		for (int x = 0; x < cx; x++) {
			const int64_t i = (int64_t)z * nx + x;
			if (depth[i] > 0.0f || depth[i + 1] > 0.0f || depth[i + nx] > 0.0f) {
				cells[(size_t)z * cx + x] = 1;
			} else if (depth[i + nx + 1] > 0.0f) {
				cells[(size_t)z * cx + x] = 1;
			}
		}
	}
	std::vector<uint8_t> ring = cells;
	for (int z = 0; z < cz; z++) {
		for (int x = 0; x < cx; x++) {
			if (cells[(size_t)z * cx + x] != 1) {
				continue;
			}
			for (int dz = -1; dz <= 1; dz++) {
				for (int dx = -1; dx <= 1; dx++) {
					const int xx = x + dx;
					const int zz = z + dz;
					if (xx < 0 || zz < 0 || xx >= cx || zz >= cz) {
						continue;
					}
					const size_t c = (size_t)zz * cx + xx;
					if (ring[c] != 0) {
						continue;
					}
					// _defined: all four corners have a surface height.
					const int64_t i = (int64_t)zz * nx + xx;
					if (w[i] != DRY && w[i + 1] != DRY && w[i + nx] != DRY && w[i + nx + 1] != DRY) {
						ring[c] = 2;
					}
				}
			}
		}
	}
	std::vector<int32_t> index_of((size_t)nx * nz, -1);
	std::vector<Vector3> verts;
	std::vector<Vector3> normals;
	std::vector<Vector2> uvs;
	std::vector<float> c0, c1;
	std::vector<int32_t> indices;
	Vector3 lo(INFINITY, INFINITY, INFINITY);
	Vector3 hi(-INFINITY, -INFINITY, -INFINITY);
	const int ox[4] = { 0, 1, 0, 1 };
	const int oz[4] = { 0, 0, 1, 1 };
	for (int z = 0; z < cz; z++) {
		for (int x = 0; x < cx; x++) {
			if (ring[(size_t)z * cx + x] == 0) {
				continue;
			}
			int32_t corner[4];
			for (int k = 0; k < 4; k++) {
				const int xx = x + ox[k];
				const int zz = z + oz[k];
				const int64_t s = (int64_t)zz * nx + xx;
				if (index_of[s] < 0) {
					index_of[s] = (int32_t)verts.size();
					const bool wet = w[s] != DRY;
					const double y = wet ? (double)ew[s] : (double)w[s];
					const double d = wet ? (double)ew[s] - (double)ground[s] : (double)depth[s];
					const Vector3 p((float)((double)origin.x + (double)xx * step_x), (float)y,
							(float)((double)origin.y + (double)zz * step_y));
					verts.push_back(p);
					lo = lo.min(p);
					hi = hi.max(p);
					// _normal
					const double h = (double)w[s];
					const double l = (xx > 0 && w[s - 1] != DRY) ? (double)w[s - 1] : h;
					const double r = (xx < nx - 1 && w[s + 1] != DRY) ? (double)w[s + 1] : h;
					const double dn = (zz > 0 && w[s - nx] != DRY) ? (double)w[s - nx] : h;
					const double up = (zz < nz - 1 && w[s + nx] != DRY) ? (double)w[s + nx] : h;
					normals.push_back(Vector3((float)((l - r) / (2.0 * step_x)), 1.0f, (float)((dn - up) / (2.0 * step_y))).normalized());
					uvs.push_back(Vector2((float)((double)xx / (double)(nx - 1)), (float)((double)zz / (double)(nz - 1))));
					c0.push_back((float)maxd(d, -1.0));
					c0.push_back(energy[s]);
					c0.push_back(shore[s]);
					c0.push_back(steep[s]);
					double mark = 0.0;
					if (spill[s] == spill_pond) {
						mark = pond_mark;
					} else if (spill[s] == spill_bank) {
						mark = bank_mark;
					} else if (calm[s] != 0) {
						mark = film_mark;
					}
					const double near_foot = (double)foot[s] < no_foot * 0.5 ? 1.0 : 0.0;
					c1.push_back(river[s]);
					c1.push_back((float)field_flag);
					c1.push_back((float)near_foot);
					c1.push_back((float)mark);
				}
				corner[k] = index_of[s];
			}
			indices.push_back(corner[0]);
			indices.push_back(corner[1]);
			indices.push_back(corner[2]);
			indices.push_back(corner[1]);
			indices.push_back(corner[3]);
			indices.push_back(corner[2]);
		}
	}
	Dictionary out;
	PackedVector3Array pv;
	PackedVector3Array pn;
	PackedVector2Array pu;
	PackedFloat32Array p0, p1;
	PackedInt32Array pi;
	pv.resize((int64_t)verts.size());
	pn.resize((int64_t)verts.size());
	pu.resize((int64_t)verts.size());
	if (!verts.empty()) {
		std::memcpy((void *)pv.ptrw(), verts.data(), verts.size() * sizeof(Vector3));
		std::memcpy((void *)pn.ptrw(), normals.data(), normals.size() * sizeof(Vector3));
		std::memcpy((void *)pu.ptrw(), uvs.data(), uvs.size() * sizeof(Vector2));
	}
	p0.resize((int64_t)c0.size());
	p1.resize((int64_t)c1.size());
	pi.resize((int64_t)indices.size());
	if (!c0.empty()) {
		std::memcpy(p0.ptrw(), c0.data(), c0.size() * sizeof(float));
		std::memcpy(p1.ptrw(), c1.data(), c1.size() * sizeof(float));
		std::memcpy(pi.ptrw(), indices.data(), indices.size() * sizeof(int32_t));
	}
	out["vertices"] = pv;
	out["normals"] = pn;
	out["uvs"] = pu;
	out["c0"] = p0;
	out["c1"] = p1;
	out["indices"] = pi;
	out["aabb"] = verts.empty() ? AABB() : AABB(lo, hi - lo);
	return out;
}

Dictionary water_textures(const Dictionary &args) {
	const Args a{ args };
	const PackedFloat32Array w_a = a["w"];
	const PackedFloat32Array ew_a = a["ew"];
	const PackedFloat32Array depth_a = a["depth"];
	const PackedFloat32Array ground_a = a["ground"];
	const PackedFloat32Array energy_a = a["energy"];
	const PackedFloat32Array shore_a = a["shore"];
	const PackedFloat32Array steep_a = a["steep"];
	const PackedFloat32Array flow_a = a["flow_u"];
	const PackedFloat32Array foot_a = a["foot"];
	const int64_t n = (int64_t)a["count"];
	const double depth_floor = a["depth_floor"];
	const double no_flow_u = a["no_flow_u"];
	const double no_foot = a["no_foot"];
	const float *w = w_a.ptr();
	const float *ew = ew_a.ptr();
	const float *depth = depth_a.ptr();
	const float *ground = ground_a.ptr();
	const float *energy = energy_a.ptr();
	const float *shore = shore_a.ptr();
	const float *steep = steep_a.ptr();
	const float *flow = flow_a.ptr();
	const float *foot = foot_a.ptr();
	PackedFloat32Array ta, tb;
	ta.resize(n * 4);
	tb.resize(n * 4);
	float *pa = ta.ptrw();
	float *pb = tb.ptrw();
	for (int64_t i = 0; i < n; i++) {
		double d = (double)depth[i];
		if (w[i] != DRY) {
			d = (double)ew[i] - (double)ground[i];
		}
		pa[i * 4] = (float)maxd(d, depth_floor);
		pa[i * 4 + 1] = energy[i];
		pa[i * 4 + 2] = shore[i];
		pa[i * 4 + 3] = steep[i];
		pb[i * 4] = 0.0f;
		pb[i * 4 + 1] = 0.0f;
		pb[i * 4 + 2] = 0.0f;
		pb[i * 4 + 3] = 0.0f;
		const double u = (double)flow[i];
		if (u > no_flow_u * 0.5) {
			pb[i * 4] = flow[i];
			pb[i * 4 + 1] = 1.0f;
		}
		if ((double)foot[i] < no_foot * 0.5) {
			pb[i * 4 + 2] = foot[i];
			pb[i * 4 + 3] = 1.0f;
		}
	}
	Dictionary out;
	out["a"] = ta;
	out["b"] = tb;
	return out;
}

} // namespace ttscatter
