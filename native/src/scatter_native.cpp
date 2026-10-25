#include "scatter_native.h"

#include <chrono>
#include <cstring>

#include <godot_cpp/core/class_db.hpp>

#include "scatter_gen.h"

using namespace godot;

void TTScatterNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("version"), &TTScatterNative::version);
	ClassDB::bind_method(D_METHOD("ping", "value"), &TTScatterNative::ping);
	ClassDB::bind_method(D_METHOD("generate", "job"), &TTScatterNative::generate);
	ClassDB::bind_method(D_METHOD("noise_2d", "seed", "frequency", "octaves", "xz"), &TTScatterNative::noise_2d);
	ClassDB::bind_method(D_METHOD("grids", "source"), &TTScatterNative::grids);
}

String TTScatterNative::version() const {
	return String("ttscatter 5 curves water");
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
