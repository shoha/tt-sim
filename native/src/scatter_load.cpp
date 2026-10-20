// Reads one job's Dictionary (utils/scatter_native.gd's pack) into the port's records: the
// constants, the ScatterPlan's species entries and fields as GDScript built them, each species'
// pattern noise settings, the window's grids (held, not copied), the cells and the blockers.
// Read once per call, before generation, on the calling worker thread.
#include "scatter_gen.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

using godot::Array;
using godot::Dictionary;
using godot::String;
using godot::Variant;

namespace ttscatter {

static Variant at(const Dictionary &d, const char *k) {
	return d.get(String(k), Variant());
}

static double num(const Dictionary &d, const char *k, double fallback = 0.0) {
	Variant v = at(d, k);
	if (v.get_type() == Variant::FLOAT || v.get_type() == Variant::INT || v.get_type() == Variant::BOOL) {
		return (double)v;
	}
	return fallback;
}

static int64_t inum(const Dictionary &d, const char *k, int64_t fallback = 0) {
	Variant v = at(d, k);
	if (v.get_type() == Variant::INT || v.get_type() == Variant::FLOAT || v.get_type() == Variant::BOOL) {
		return (int64_t)v;
	}
	return fallback;
}

static bool flag(const Dictionary &d, const char *k) {
	Variant v = at(d, k);
	return v.get_type() == Variant::BOOL ? (bool)v : false;
}

static Vector2 vec2(const Dictionary &d, const char *k) {
	Variant v = at(d, k);
	return v.get_type() == Variant::VECTOR2 ? (Vector2)v : Vector2();
}

static std::string text(const Variant &v) {
	return std::string(String(v).utf8().get_data());
}

/// Any numeric array Variant (packed or plain) as doubles.
static std::vector<double> doubles(const Variant &v) {
	std::vector<double> out;
	switch (v.get_type()) {
		case Variant::PACKED_FLOAT64_ARRAY: {
			godot::PackedFloat64Array a = v;
			out.assign(a.ptr(), a.ptr() + a.size());
		} break;
		case Variant::PACKED_FLOAT32_ARRAY: {
			godot::PackedFloat32Array a = v;
			for (int64_t i = 0; i < a.size(); i++) {
				out.push_back(a[i]);
			}
		} break;
		case Variant::PACKED_INT32_ARRAY: {
			godot::PackedInt32Array a = v;
			for (int64_t i = 0; i < a.size(); i++) {
				out.push_back(a[i]);
			}
		} break;
		case Variant::PACKED_INT64_ARRAY: {
			godot::PackedInt64Array a = v;
			for (int64_t i = 0; i < a.size(); i++) {
				out.push_back((double)a[i]);
			}
		} break;
		case Variant::ARRAY: {
			Array a = v;
			for (int64_t i = 0; i < a.size(); i++) {
				out.push_back((double)a[i]);
			}
		} break;
		default:
			break;
	}
	return out;
}

static void load_consts(const Dictionary &d, Consts &c) {
	c.candidates_per_bucket = (int)inum(d, "candidates_per_bucket", 4);
	c.clump_saturation = num(d, "clump_saturation");
	c.row_step = num(d, "row_step");
	c.anchor_step = num(d, "anchor_step");
	c.tile_m = num(d, "tile_m");
	c.tile_min_buckets = (int)inum(d, "tile_min_buckets");
	c.additive_clumps = flag(d, "additive_clumps");
	c.footing_directions = (int)inum(d, "footing_directions");
	c.footing_sag_m = num(d, "footing_sag_m");
	c.footing_slope_tan = num(d, "footing_slope_tan");
	c.bound_slack = num(d, "bound_slack");
	c.flow_step = num(d, "flow_step");
	godot::PackedByteArray lattice = at(d, "lattice");
	c.lattice.assign(lattice.ptr(), lattice.ptr() + lattice.size());
	c.noise_cells = (int)inum(d, "noise_cells");
	c.accent_edge = num(d, "accent_edge");
	c.detail = num(d, "detail");
	c.detail_scale = num(d, "detail_scale");
	c.fine = num(d, "fine");
	c.fine_scale = num(d, "fine_scale");
	c.detail_offset = vec2(d, "detail_offset");
	c.fine_offset = vec2(d, "fine_offset");
	c.rotation = vec2(d, "rotation");
	c.inv_uint_max = num(d, "inv_uint_max");
	c.cliff_start_cos = num(d, "cliff_start_cos");
	c.cliff_end_cos = num(d, "cliff_end_cos");
	c.cliff_edge_noise = num(d, "cliff_edge_noise");
	c.lip_curvature_start = num(d, "lip_curvature_start");
	c.lip_curvature_end = num(d, "lip_curvature_end");
	c.lip_strength = num(d, "lip_strength");
	c.lip_sheer_tail = num(d, "lip_sheer_tail");
	c.ramp_low = num(d, "ramp_low");
	c.ramp_high = num(d, "ramp_high");
	c.scree_curvature_start = num(d, "scree_curvature_start");
	c.scree_curvature_end = num(d, "scree_curvature_end");
	c.scree_near_start = num(d, "scree_near_start");
	c.scree_near_end = num(d, "scree_near_end");
	c.scree_edge_noise = num(d, "scree_edge_noise");
	c.scree_breakup_scale_m = num(d, "scree_breakup_scale_m");
	c.scree_fan = num(d, "scree_fan");
	c.scree_breakup_low = num(d, "scree_breakup_low");
	c.scree_breakup_high = num(d, "scree_breakup_high");
	c.rule_noise_scale_m = num(d, "rule_noise_scale_m");
	c.rule_noise_shear = num(d, "rule_noise_shear");
	c.paint_edge_warp_m = num(d, "paint_edge_warp_m");
	c.paint_edge_scale_m = num(d, "paint_edge_scale_m");
	c.paint_edge_noise = num(d, "paint_edge_noise");
	c.paint_cliff_yield = num(d, "paint_cliff_yield");
	c.paint_water_yield = num(d, "paint_water_yield");
	c.paint_ford_start_m = num(d, "paint_ford_start_m");
	c.paint_ford_end_m = num(d, "paint_ford_end_m");
	c.cliff_noise_offset = vec2(d, "cliff_noise_offset");
	c.scree_noise_offset = vec2(d, "scree_noise_offset");
	c.scree_breakup_offset = vec2(d, "scree_breakup_offset");
	c.paint_warp_offset_a = vec2(d, "paint_warp_offset_a");
	c.paint_warp_offset_b = vec2(d, "paint_warp_offset_b");
	c.paint_noise_offset = vec2(d, "paint_noise_offset");
	c.role_cover = (int)inum(d, "role_cover");
	c.role_rock = (int)inum(d, "role_rock");
	c.role_tree = (int)inum(d, "role_tree");
	c.role_shrub = (int)inum(d, "role_shrub");
	c.role_tall_cover = (int)inum(d, "role_tall_cover");
	c.role_bits = (int)inum(d, "role_bits");
	c.edge_bank = (int)inum(d, "edge_bank");
	c.edge_emergent = (int)inum(d, "edge_emergent");
	c.flower_bit = (int)inum(d, "flower_bit");
	c.charred_bit = (int)inum(d, "charred_bit");
	c.scree_thin = num(d, "scree_thin");
	c.scree_rock_boost = num(d, "scree_rock_boost");
	c.flower_verge_fill = num(d, "flower_verge_fill");
	c.flower_verge_gather = num(d, "flower_verge_gather");
	c.edge_boost = num(d, "edge_boost");
	c.paved_clear_start = num(d, "paved_clear_start");
	c.paved_clear_full = num(d, "paved_clear_full");
	c.tree_face_start = num(d, "tree_face_start");
	c.tree_face_full = num(d, "tree_face_full");
	c.shrub_face_start = num(d, "shrub_face_start");
	c.shrub_face_full = num(d, "shrub_face_full");
	c.fringe_start = num(d, "fringe_start");
	c.fringe_full = num(d, "fringe_full");
	c.arid_bit = (int)inum(d, "arid_bit");
	c.depth_scale = num(d, "depth_scale", 1.0);
	c.wet_clear_start = num(d, "wet_clear_start");
	c.wet_clear_full = num(d, "wet_clear_full");
	c.emergent_depth_start_m = num(d, "emergent_depth_start_m");
	c.emergent_depth_full_m = num(d, "emergent_depth_full_m");
	c.tree_shore_start = num(d, "tree_shore_start");
	c.tree_shore_full = num(d, "tree_shore_full");
	c.shrub_shore_start = num(d, "shrub_shore_start");
	c.shrub_shore_full = num(d, "shrub_shore_full");
	c.shrub_shore_keep = num(d, "shrub_shore_keep");
	c.tall_shore_start = num(d, "tall_shore_start");
	c.tall_shore_full = num(d, "tall_shore_full");
	c.flower_shore_thin = num(d, "flower_shore_thin");
	c.arid_shore_start = num(d, "arid_shore_start");
	c.arid_shore_full = num(d, "arid_shore_full");
	c.clear_margin_m = num(d, "clear_margin_m");
	c.clear_anchor_m = num(d, "clear_anchor_m");
	c.clear_soft_m = num(d, "clear_soft_m");
	c.clear_tree_m = num(d, "clear_tree_m");
	c.clear_shrub_m = num(d, "clear_shrub_m");
}

static std::vector<Relation> relations(const Variant &v) {
	std::vector<Relation> out;
	if (v.get_type() != Variant::ARRAY) {
		return out;
	}
	Array list = v;
	for (int64_t i = 0; i < list.size(); i++) {
		Dictionary r = list[i];
		Relation relation;
		relation.target = (int)inum(r, "target");
		relation.distance = num(r, "distance");
		relation.transition = num(r, "transition");
		relation.influence = num(r, "influence");
		out.push_back(relation);
	}
	return out;
}

static void load_zones(const Dictionary &z, ZonesRecord &zones, const Consts *c) {
	zones.c = c;
	std::vector<double> scale_m = doubles(at(z, "scale_m")), angle_k = doubles(at(z, "angle_k"));
	std::vector<double> stretch_k = doubles(at(z, "stretch_k")), cover = doubles(at(z, "cover"));
	std::vector<double> edge = doubles(at(z, "edge"));
	for (int k = 0; k < 3; k++) {
		zones.scale_m[k] = k < (int)scale_m.size() ? scale_m[k] : 0.0;
		zones.angle_k[k] = k < (int)angle_k.size() ? angle_k[k] : 0.0;
		zones.stretch_k[k] = k < (int)stretch_k.size() ? stretch_k[k] : 0.0;
		zones.cover[k] = k < (int)cover.size() ? cover[k] : 0.0;
		zones.edge[k] = k < (int)edge.size() ? edge[k] : 0.0;
	}
	zones.angle = num(z, "angle");
	zones.stretch = num(z, "stretch");
	zones.warp = num(z, "warp");
	zones.nest = num(z, "nest");
	zones.rag = num(z, "rag");
	zones.rag_m = num(z, "rag_m");
	zones.stroke_edge = num(z, "stroke_edge");
	zones.edge_vary = num(z, "edge_vary");
	zones.edge_vary_m = num(z, "edge_vary_m");
	zones.stroke = num(z, "stroke");
	zones.stroke_m = num(z, "stroke_m");
	zones.stroke_len = num(z, "stroke_len");
	zones.stroke_soft_lo = num(z, "stroke_soft_lo");
	zones.stroke_soft_hi = num(z, "stroke_soft_hi");
	zones.stroke_soft_m = num(z, "stroke_soft_m");
	zones.seed = vec2(z, "seed");
	Array shapes = at(z, "shapes");
	for (int k = 0; k < 3 && k < shapes.size(); k++) {
		Array shape = shapes[k];
		zones.shape_scale[k] = (double)shape[0];
		zones.shape_offset[k] = (Vector2)shape[1];
		zones.shape_angle[k] = (double)shape[2];
		zones.shape_stretch[k] = (double)shape[3];
	}
}

static std::vector<BareRecord> bare_records(const Array &list) {
	std::vector<BareRecord> out;
	for (int64_t i = 0; i < list.size(); i++) {
		Array r = list[i];
		BareRecord record;
		record.threshold = (double)r[0];
		record.scale_m = (double)r[1];
		record.offset = (Vector2)r[2];
		record.margin = (double)r[3];
		record.stretch = (double)r[4];
		record.angle = (double)r[5];
		record.brk = (double)r[6];
		record.seed = (int64_t)r[7];
		record.cos_a = (double)r[8];
		record.sin_a = (double)r[9];
		out.push_back(record);
	}
	return out;
}

bool Job::load(const Dictionary &d) {
	load_consts(at(d, "consts"), consts);
	Dictionary plan = at(d, "plan");
	Array plan_fields = at(plan, "fields");
	for (int64_t f = 0; f < plan_fields.size(); f++) {
		Dictionary pf = plan_fields[f];
		FieldPlan field;
		field.seed = inum(pf, "seed");
		field.bucket = num(pf, "bucket", 1.0);
		field.spacing = num(pf, "spacing");
		for (double o : doubles(at(pf, "owners"))) {
			field.owners.push_back((int)o);
		}
		field.cdf = doubles(at(pf, "cdf"));
		field.empty = flag(pf, "empty");
		fields.push_back(field);
	}
	Array noise = at(d, "noise");
	Array plan_species = at(plan, "species");
	std::vector<Dictionary> zone_dicts;
	std::vector<ZonesRecord *> zone_loaded;
	species.resize(plan_species.size());
	for (int64_t s = 0; s < plan_species.size(); s++) {
		Dictionary e = plan_species[s];
		Dictionary rule = at(e, "rule");
		Entry &entry = species[s];
		entry.key = text(at(e, "key"));
		Array assets = at(rule, "assets");
		for (int64_t a = 0; a < assets.size(); a++) {
			entry.assets.push_back(text(assets[a]));
		}
		entry.index = (int)inum(e, "index");
		entry.field = (int)inum(e, "field", -1);
		entry.parent_field = (int)inum(e, "parent_field", -1);
		entry.clumped = flag(e, "clumped");
		entry.mass = flag(e, "mass");
		entry.referenced = flag(e, "referenced");
		entry.align_normal = flag(e, "align_normal");
		entry.clump_scale = flag(e, "clump_scale");
		entry.mass_follow = flag(e, "mass_follow");
		entry.spacing = num(e, "spacing");
		entry.clearance_m = num(e, "clearance_m");
		entry.slope_max = num(e, "slope_max");
		entry.slope_cos = num(e, "slope_cos", -2.0);
		entry.influence = num(e, "influence");
		entry.scale_influence = num(e, "scale_influence");
		entry.ground_role = (int)inum(e, "ground_role");
		entry.footing_m = num(e, "footing_m");
		entry.yaw_range = num(e, "yaw_range");
		entry.scale_spread = num(e, "scale_spread");
		entry.scale_floor = num(e, "scale_floor", -1.0);
		entry.asset_count = (int)inum(e, "asset_count", 1);
		entry.response_lead = num(e, "response_lead", 1.0);
		entry.response_lag = num(e, "response_lag", 1.0);
		entry.mass_stretch = num(e, "mass_stretch", 1.0);
		entry.mass_core = num(e, "mass_core", 1.0);
		entry.mass_core_y = num(e, "mass_core_y", 1.0);
		entry.mass_core_y_max = num(e, "mass_core_y_max");
		entry.mass_core_hold = num(e, "mass_core_hold");
		entry.clump_jitter = num(e, "clump_jitter");
		entry.clump_shrink = num(e, "clump_shrink");
		entry.near = relations(at(e, "near"));
		entry.avoid = relations(at(e, "avoid"));
		for (double f : doubles(at(e, "clearance"))) {
			entry.clearance.push_back((int)f);
		}
		Variant clump = at(rule, "clump");
		if (clump.get_type() == Variant::DICTIONARY && entry.clumped) {
			Dictionary cd = clump;
			entry.clump_radius = num(cd, "radius_m");
			entry.clump_transition = num(cd, "transition_m");
			entry.clump_angle_deg = num(cd, "angle_deg", 0.0);
			entry.clump_angle_jitter_deg = num(cd, "angle_jitter_deg", 0.0);
		}
		Dictionary zone = at(e, "mass_zone");
		if (!zone.is_empty()) {
			entry.has_zone = true;
			std::vector<double> keep = doubles(at(zone, "keep")), family = doubles(at(zone, "family"));
			for (int k = 0; k < 4; k++) {
				entry.zone.keep[k] = k < (int)keep.size() ? (float)keep[k] : 1.0f;
				entry.zone.family[k] = k < (int)family.size() ? (int)family[k] : k;
			}
			entry.zone.shoulder = num(zone, "shoulder");
			entry.zone.core = num(zone, "core");
			entry.zone.share = num(zone, "share");
			entry.zone.fill = num(zone, "fill");
		}
		Dictionary zones = at(e, "mass_zones");
		if (!zones.is_empty()) {
			// One record per plan in GDScript (_plan_masses shares it); equal records share here.
			for (size_t z = 0; z < zone_dicts.size() && entry.zones == nullptr; z++) {
				if (zone_dicts[z] == zones) {
					entry.zones = zone_loaded[z];
				}
			}
			if (entry.zones == nullptr) {
				zones_records.emplace_back();
				load_zones(zones, zones_records.back(), &consts);
				entry.zones = &zones_records.back();
				zone_dicts.push_back(zones);
				zone_loaded.push_back(entry.zones);
			}
		}
		Variant bare = at(e, "mass_bare");
		if (bare.get_type() == Variant::ARRAY && Array(bare).size() > 0) {
			bare_records.push_back(ttscatter::bare_records(bare));
			entry.bare = &bare_records.back();
		}
		Variant settings = s < noise.size() ? noise[s] : Variant();
		if (settings.get_type() == Variant::ARRAY) {
			Array n = settings;
			entry.has_noise = true;
			entry.noise_seed = (int)(int64_t)n[0];
			entry.noise_frequency = (float)(double)n[1];
			entry.noise_octaves = (int)(int64_t)n[2];
			entry.noise_contrast = (double)n[3];
		}
		entry.blocked_by_rocks = entry.ground_role == (int)inum(at(d, "consts"), "role_rock") || entry.footing_m > 0.0;
	}
	// The grids come computed here from the document's arrays ("source", ScatterNative.pack) or,
	// for the parity checks, as GDScript built them ("grids", ScatterNative.grids_for).
	Dictionary g = at(d, "source");
	if (!g.is_empty()) {
		if (!build_grids(g, grids)) {
			error = "grids";
			return false;
		}
	} else {
		g = at(d, "grids");
		grids.columns = (int)inum(g, "columns");
		grids.rows = (int)inum(g, "rows");
		grids.step = vec2(g, "step");
		grids.half = vec2(g, "half");
		grids.seed_value = inum(g, "seed_value");
		grids.density.take(at(g, "density"));
		grids.heights.take(at(g, "heights"));
		grids.curvature.take(at(g, "curvature"));
		grids.steep.take(at(g, "steep"));
		grids.near_face.take(at(g, "near_face"));
		grids.paint_total.take(at(g, "paint_total"));
		grids.paint_built.take(at(g, "paint_built"));
		grids.paint_rock.take(at(g, "paint_rock"));
		grids.paint_ash.take(at(g, "paint_ash"));
		grids.fringe.take(at(g, "fringe"));
	}
	grids.paints = !grids.paint_total.empty();
	grids.fringed = !grids.fringe.empty();
	int64_t count = (int64_t)grids.columns * grids.rows;
	grids.water_hold = at(g, "water");
	grids.wet = grids.water_hold.size() == count * 4;
	grids.water = grids.wet ? grids.water_hold.ptr() : nullptr;
	godot::PackedFloat64Array crossings_in = at(g, "crossings");
	for (int64_t i = 0; i + 4 < crossings_in.size(); i += 5) {
		CrossingSpan span;
		span.start = v2(crossings_in[i], crossings_in[i + 1]);
		span.end = v2(crossings_in[i + 2], crossings_in[i + 3]);
		span.width_m = crossings_in[i + 4];
		grids.crossings.push_back(span);
	}
	if (grids.columns < 2 || grids.rows < 2 || grids.density.size() != count || grids.heights.size() != count ||
			grids.curvature.size() != count || grids.steep.size() != count || grids.near_face.size() != count) {
		error = "grids";
		return false;
	}
	bounds = (Rect2)at(d, "bounds");
	Array cells = at(d, "cells_by_species");
	cells_by_species.resize(species.size());
	for (int64_t s = 0; s < cells.size() && s < (int64_t)species.size(); s++) {
		if (cells[s].get_type() != Variant::ARRAY) {
			continue;
		}
		Array list = cells[s];
		for (int64_t i = 0; i < list.size(); i++) {
			cells_by_species[s].push_back((godot::Vector2i)list[i]);
		}
	}
	godot::PackedFloat32Array blockers_in = at(d, "blockers");
	blockers.assign(blockers_in.ptr(), blockers_in.ptr() + blockers_in.size());
	return true;
}

} // namespace ttscatter
