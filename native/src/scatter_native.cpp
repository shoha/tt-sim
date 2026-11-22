#include "scatter_native.h"

#include <chrono>
#include <cstring>

#include <godot_cpp/core/class_db.hpp>

#include "scatter_gen.h"
#include "terrain_fields.h"
#include "water_field.h"

using namespace godot;

void TTScatterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("water_spill", "args"), &TTScatterNative::water_spill);
	ClassDB::bind_method(D_METHOD("water_derive", "args"), &TTScatterNative::water_derive);
	ClassDB::bind_method(D_METHOD("water_shore", "args"), &TTScatterNative::water_shore);
	ClassDB::bind_method(D_METHOD("water_raster", "args"), &TTScatterNative::water_raster);
	ClassDB::bind_method(D_METHOD("water_foot_seams", "args"), &TTScatterNative::water_foot_seams);
	ClassDB::bind_method(D_METHOD("water_mesh", "args"), &TTScatterNative::water_mesh);
	ClassDB::bind_method(D_METHOD("water_textures", "args"), &TTScatterNative::water_textures);
	ClassDB::bind_method(D_METHOD("version"), &TTScatterNative::version);
	ClassDB::bind_method(D_METHOD("ping", "value"), &TTScatterNative::ping);
	ClassDB::bind_method(D_METHOD("generate", "job"), &TTScatterNative::generate);
	ClassDB::bind_method(D_METHOD("noise_2d", "seed", "frequency", "octaves", "xz"), &TTScatterNative::noise_2d);
	ClassDB::bind_method(D_METHOD("grids", "source"), &TTScatterNative::grids);
	ClassDB::bind_method(D_METHOD("chunk", "rows", "indices", "seed", "anchors"), &TTScatterNative::chunk);
	ClassDB::bind_method(D_METHOD("rule_fields", "heights", "columns", "rows", "step", "rect", "radius", "start_cos", "end_cos"),
			&TTScatterNative::rule_fields);
}

String TTScatterNative::version() const {
	// `terra`: the library also holds TerraDerive (docs/systems/terraform.md), so a stale build
	// without it fails test_scatter_native.
	return String("ttscatter 10 curves water chunk fields wfield2 terra");
}

Dictionary TTScatterNative::water_spill(const Dictionary &args) const {
	return ttscatter::water_spill(args);
}

Dictionary TTScatterNative::water_derive(const Dictionary &args) const {
	return ttscatter::water_derive(args);
}

Dictionary TTScatterNative::water_shore(const Dictionary &args) const {
	return ttscatter::water_shore(args);
}

Dictionary TTScatterNative::water_raster(const Dictionary &args) const {
	return ttscatter::water_raster(args);
}

Dictionary TTScatterNative::water_foot_seams(const Dictionary &args) const {
	return ttscatter::water_foot_seams(args);
}

Dictionary TTScatterNative::water_mesh(const Dictionary &args) const {
	return ttscatter::water_mesh(args);
}

Dictionary TTScatterNative::water_textures(const Dictionary &args) const {
	return ttscatter::water_textures(args);
}

int64_t TTScatterNative::ping(int64_t value) const {
	return 2 * value + 1;
}

Dictionary TTScatterNative::generate(const Dictionary &job_dict) const {
	auto started = std::chrono::steady_clock::now();
	ttscatter::Job job;
	Dictionary out;
	if (!job.load(job_dict)) {
		out["error"] = String(job.error.c_str());
		return out;
	}
	ttscatter::Ctx ctx(job);
	ctx.generate();
	out["rows"] = ctx.result;
	out["anchors"] = ctx.anchors_out;
	auto elapsed = std::chrono::steady_clock::now() - started;
	out["usec"] = (int64_t)std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count();
	return out;
}

static PackedFloat32Array packed(const ttscatter::Grid &grid) {
	PackedFloat32Array out;
	out.resize(grid.size());
	if (grid.size() > 0) {
		std::memcpy(out.ptrw(), grid.p, (size_t)grid.size() * sizeof(float));
	}
	return out;
}

Dictionary TTScatterNative::grids(const Dictionary &source) const {
	ttscatter::Grids grids;
	Dictionary out;
	if (!ttscatter::build_grids(source, grids)) {
		out["error"] = String("grids");
		return out;
	}
	out["density"] = packed(grids.density);
	out["heights"] = packed(grids.heights);
	out["curvature"] = packed(grids.curvature);
	out["steep"] = packed(grids.steep);
	out["near_face"] = packed(grids.near_face);
	out["paint_total"] = packed(grids.paint_total);
	out["paint_built"] = packed(grids.paint_built);
	out["paint_rock"] = packed(grids.paint_rock);
	out["paint_ash"] = packed(grids.paint_ash);
	out["fringe"] = packed(grids.fringe);
	return out;
}

Dictionary TTScatterNative::rule_fields(const PackedFloat32Array &heights, int64_t columns, int64_t rows, const Vector2 &step,
		const Rect2i &rect, int64_t radius, double start_cos, double end_cos) const {
	Rect2i out = rect.intersection(Rect2i(0, 0, (int32_t)columns, (int32_t)rows));
	PackedFloat32Array curvature;
	PackedFloat32Array steep;
	if (out.has_area() && columns > 0 && rows > 0 && heights.size() >= columns * rows) {
		const int64_t count = (int64_t)out.size.x * (int64_t)out.size.y;
		curvature.resize(count);
		steep.resize(count);
		ttscatter::FieldsInput in;
		in.heights = heights.ptr();
		in.columns = columns;
		in.rows = rows;
		in.step_x = (double)step.x;
		in.step_y = (double)step.y;
		in.r = radius;
		in.start_cos = start_cos;
		in.end_cos = end_cos;
		ttscatter::rule_fields(in, out, curvature.ptrw(), steep.ptrw());
	}
	Dictionary result;
	result["rect"] = out;
	result["curvature"] = curvature;
	result["steep"] = steep;
	return result;
}

PackedFloat32Array TTScatterNative::noise_2d(int64_t seed, double frequency, int64_t octaves, const PackedFloat64Array &xz) const {
	fastnoiselite::FastNoiseLite noise;
	ttscatter::setup_pattern_noise(noise, (int)seed, (float)frequency, (int)octaves);
	PackedFloat32Array out;
	out.resize(xz.size() / 2);
	float *w = out.ptrw();
	const double *p = xz.ptr();
	for (int64_t i = 0; i < out.size(); i++) {
		w[i] = noise.GetNoise((float)p[i * 2], (float)p[i * 2 + 1]);
	}
	return out;
}
