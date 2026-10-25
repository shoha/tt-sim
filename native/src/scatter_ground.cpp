// The document_fields Callables (ScatterGenerator.document_fields) as plain methods over the
// job's grids: the painted density, its ceiling, the ground sampler (ScatterGround.sampler) that
// species_density_at multiplies in, and the terrain's height and normal; with TerrainRules'
// weights (the cliff and scree rules with their edge noise) and the painted-surface shaping.
// Line for line with utils/scatter_generator.gd, utils/scatter_ground.gd and
// utils/terrain_rules.gd, with WaterDressing.sample, ScatterGround.wet_factor and
// CrossingGeometry.clearance.
#include "scatter_gen.h"

namespace ttscatter {

double Ground::plain_at(Vector2 p) const {
	Vector2 at = (p + g.half) / g.step;
	if (at.x < 0.0 || at.y < 0.0 || at.x > g.columns - 1 || at.y > g.rows - 1) {
		return 0.0;
	}
	return bilinear(g.density, g.columns, g.rows, at);
}

double Ground::species_density_at(Vector2 p, int role) const {
	double d = plain_at(p);
	if (!(d > 0.0)) {
		return d;
	}
	Vector3 gv = ground_at(p, role);
	if (role == c.role_rock) {
		return gmin(d * (1.0 + c.scree_rock_boost * gv.z), 1.0) * gv.x;
	}
	if ((role & c.edge_bank) != 0) {
		return gmax(d * gv.x * (1.0 - c.scree_thin * gv.z), 0.0);
	}
	if ((role & c.flower_bit) != 0) {
		return gclamp(d * gv.x * (1.0 - c.scree_thin * gv.z), 0.0, 1.0 + c.flower_verge_fill);
	}
	return gmin(d * gv.x * (1.0 - c.scree_thin * gv.z), 1.0);
}

double Ground::density_ceiling_at(Vector2 p, int role) const {
	double d = plain_at(p);
	if (!(d > 0.0)) {
		return d;
	}
	double most = 1.0;
	if (g.fringed && (role & c.flower_bit) != 0) {
		most *= 1.0 + c.flower_verge_gather;
	}
	if (g.wet && (role & (c.edge_emergent | c.edge_bank)) != 0) {
		most *= 1.0 + c.edge_boost;
	}
	if (role == c.role_rock) {
		return gmin(d * (1.0 + c.scree_rock_boost), 1.0) * most;
	}
	return d * most;
}

double Ground::height_at(Vector2 p) const {
	return triangle_height(g.heights, g.columns, g.rows, (p + g.half) / g.step);
}

Vector3 Ground::normal_at(Vector2 p) const {
	return triangle_normal(g.heights, g.columns, g.rows, (p + g.half) / g.step, g.step);
}

// ---- ScatterGround.sampler -------------------------------------------------------------------

bool Ground::scorches(int role) const {
	if ((role & c.charred_bit) != 0) {
		return false;
	}
	int base = role & c.role_bits;
	return base == c.role_cover || base == c.role_tall_cover || base == c.role_shrub;
}

Vector3 Ground::ground_at(Vector2 p, int role) const {
	int base = role & c.role_bits;
	Vector2 s = (p + g.half) / g.step;
	Vector3 n = triangle_normal(g.heights, g.columns, g.rows, s, g.step);
	Vector2 fields = field_at(g.curvature, g.steep, g.columns, g.rows, s);
	double y = triangle_height(g.heights, g.columns, g.rows, s);
	Vector2 rule = weights(n.y, fields, p, y);
	double built_weight = 0.0;
	double ash_weight = 0.0;
	double held = 0.0;
	double yielding = 0.0;
	if (g.paints) {
		Vector2 lookup = (painted_lookup(p) + g.half) / g.step;
		double total = bilinear(g.paint_total, g.columns, g.rows, lookup);
		if (total > 0.0) {
			double shaped = shape_painted(total, p);
			double scale = shaped / total;
			built_weight = bilinear(g.paint_built, g.columns, g.rows, lookup) * scale;
			if (scorches(role)) {
				ash_weight = bilinear(g.paint_ash, g.columns, g.rows, lookup) * scale;
			}
			held = bilinear(g.paint_rock, g.columns, g.rows, lookup) * scale;
			yielding = gmax(shaped - held, 0.0);
		}
	}
	Vector3 water = g.wet ? water_at(s) : Vector3();
	// TerrainRules.compose_water(yielding, held, rule, Vector2(water.x, water.y), water.z) as a
	// PackedFloat32Array: [keep, cliff, scree, paint_scale, bed, shore], each rounded to float32.
	double unpainted = gclamp(1.0 - yielding - held, 0.0, 1.0);
	double cliff_scale = 1.0 - c.paint_cliff_yield * rule.x;
	double fording = smoothstep(c.paint_ford_start_m, c.paint_ford_end_m, water.z);
	double ford = c.paint_water_yield * water.x * fording;
	float share_scale = (float)(cliff_scale * (1.0 - ford));
	float share_cliff = (float)(unpainted * rule.x + yielding * (1.0 - cliff_scale));
	float share_scree = (float)(unpainted * rule.y * (1.0 - water.x));
	double paved = (built_weight + ash_weight) * share_scale + held;
	double open = 1.0 - share_cliff - smoothstep(c.paved_clear_start, c.paved_clear_full, paved);
	if (base == c.role_tree || base == c.role_shrub) {
		double face = bilinear(g.near_face, g.columns, g.rows, s);
		if (base == c.role_tree) {
			open *= 1.0 - smoothstep(c.tree_face_start, c.tree_face_full, face);
		} else {
			open *= 1.0 - smoothstep(c.shrub_face_start, c.shrub_face_full, face);
		}
	}
	bool flower = (role & c.flower_bit) != 0;
	if ((base == c.role_tall_cover || base == c.role_shrub || flower) && !g.fringe.empty()) {
		double beside = bilinear(g.fringe, g.columns, g.rows, s);
		double verge = smoothstep(c.fringe_start, c.fringe_full, beside);
		open *= flower ? 1.0 + c.flower_verge_gather * verge : 1.0 - verge;
	}
	if (water != Vector3()) {
		open *= wet_factor(role, water);
	}
	if (!g.crossings.empty()) {
		double extra = 0.0;
		if (base == c.role_tree) {
			extra = c.clear_tree_m;
		} else if (base == c.role_shrub || base == c.role_rock) {
			extra = c.clear_shrub_m;
		}
		open *= clearance(p, extra);
	}
	return Vector3((float)gmax(open, 0.0), share_cliff, share_scree);
}

Vector3 Ground::water_at(Vector2 s) const {
	const int channels = 4;
	int columns = g.columns;
	double fx = gclamp(s.x, 0.0, columns - 1);
	double fz = gclamp(s.y, 0.0, g.rows - 1);
	int64_t x0 = imin(floori(fx), columns - 2);
	int64_t z0 = imin(floori(fz), g.rows - 2);
	double tx = fx - x0;
	double tz = fz - z0;
	int64_t a = (z0 * columns + x0) * channels;
	int64_t b = a + channels;
	int64_t cc = a + (int64_t)columns * channels;
	int64_t d = cc + channels;
	float out[3];
	for (int ch = 0; ch < 3; ch++) {
		double top = glerp(g.water[a + ch], g.water[b + ch], tx);
		double bottom = glerp(g.water[cc + ch], g.water[d + ch], tx);
		out[ch] = (float)glerp(top, bottom, tz);
	}
	return Vector3((float)(out[0] / 255.0), (float)(out[1] / 255.0), (float)(out[2] / c.depth_scale));
}

double Ground::wet_at(Vector2 p) const {
	if (!g.wet) {
		return 0.0;
	}
	return water_at((p + g.half) / g.step).y;
}

double Ground::water_dist_at(Vector2 p) const {
	if (!g.water_dist_ok) {
		return c.water_dist_max_m;
	}
	// ScatterTerrain.sample_grid: WaterDressing.sample's corners and weights over one float grid.
	Vector2 s = (p + g.half) / g.step;
	int columns = g.columns;
	double fx = gclamp(s.x, 0.0, columns - 1);
	double fz = gclamp(s.y, 0.0, g.rows - 1);
	int64_t x0 = imin(floori(fx), columns - 2);
	int64_t z0 = imin(floori(fz), g.rows - 2);
	double tx = fx - x0;
	double tz = fz - z0;
	int64_t a = z0 * columns + x0;
	int64_t cc = a + columns;
	double top = glerp(g.water_dist[a], g.water_dist[a + 1], tx);
	double bottom = glerp(g.water_dist[cc], g.water_dist[cc + 1], tx);
	return glerp(top, bottom, tz);
}

double Ground::wet_factor(int role, Vector3 water) const {
	double bed = water.x;
	double shore = water.y;
	if ((role & c.edge_emergent) != 0) {
		double f = 1.0 - smoothstep(c.emergent_depth_start_m, c.emergent_depth_full_m, water.z);
		f *= 1.0 - smoothstep(0.5, 0.9, bed) * (1.0 - smoothstep(0.0, 0.05, water.z));
		return f * (1.0 + c.edge_boost * gmax(shore, bed));
	}
	double dry = 1.0 - smoothstep(c.wet_clear_start, c.wet_clear_full, bed);
	if ((role & c.edge_bank) != 0) {
		return dry * (1.0 + c.edge_boost * shore);
	}
	if ((role & c.arid_bit) != 0) {
		return dry * (1.0 - smoothstep(c.arid_shore_start, c.arid_shore_full, shore));
	}
	int base = role & c.role_bits;
	if (base == c.role_tree) {
		return dry * (1.0 - smoothstep(c.tree_shore_start, c.tree_shore_full, shore));
	}
	if (base == c.role_shrub) {
		double thin = smoothstep(c.shrub_shore_start, c.shrub_shore_full, shore);
		return dry * (1.0 - (1.0 - c.shrub_shore_keep) * thin);
	}
	if (base == c.role_tall_cover) {
		return dry * (1.0 - smoothstep(c.tall_shore_start, c.tall_shore_full, shore));
	}
	if ((role & c.flower_bit) != 0) {
		return dry * (1.0 - c.flower_shore_thin * shore);
	}
	return dry;
}

double Ground::clearance(Vector2 p, double extra) const {
	double keep = 1.0;
	double anchor_m = c.clear_anchor_m + extra;
	for (const CrossingSpan &crossing : g.crossings) {
		double span = crossing.start.distance_to(crossing.end);
		if (span <= 0.0) {
			continue;
		}
		Vector2 dv = crossing.end - crossing.start;
		Vector2 dir = dv.length() > 0.0f ? dv / dv.length() : Vector2();
		Vector2 rel = p - crossing.start;
		Vector2 uv(rel.dot(dir), rel.dot(Vector2(-dir.y, dir.x)));
		double half = crossing.width_m * 0.5 + c.clear_margin_m + extra;
		double du = gmax(gmax(-anchor_m - uv.x, uv.x - span - anchor_m), 0.0);
		double dvv = gmax(std::fabs((double)uv.y) - half, 0.0);
		keep = gmin(keep, smoothstep(0.0, c.clear_soft_m, v2(du, dvv).length()));
	}
	return keep;
}

// ---- TerrainRules ----------------------------------------------------------------------------

double Ground::raw_tail(double v, double start, double end) {
	if (is_equal_approx(start, end)) {
		return v >= end ? 1.0 : 0.0;
	}
	return (v - start) / (end - start);
}

double Ground::ease_ramp(double m) const {
	double t = gclamp((m - c.ramp_low) / (c.ramp_high - c.ramp_low), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

double Ground::value_noise(Vector2 p) const {
	int64_t ix = floori(p.x);
	int64_t iz = floori(p.y);
	Vector2 u = v2((double)p.x - ix, (double)p.y - iz);
	u = u * u * (Vector2(3.0f, 3.0f) - u * 2.0f);
	int64_t seed = g.seed_value;
	int64_t cx = (ix + seed) & MASK32;
	int64_t cz = (iz + ((seed * 7919) & MASK32)) & MASK32;
	double a = (double)pcg2d_x(cx, cz);
	double b = (double)pcg2d_x((cx + 1) & MASK32, cz);
	double d = (double)pcg2d_x(cx, (cz + 1) & MASK32);
	double e = (double)pcg2d_x((cx + 1) & MASK32, (cz + 1) & MASK32);
	return glerp(glerp(a, b, u.x), glerp(d, e, u.x), u.y) * c.inv_uint_max;
}

double Ground::rule_noise(Vector2 xz, double y, Vector2 offset) const {
	Vector2 p = (xz + v2(y * c.rule_noise_shear, -y * c.rule_noise_shear)) / (float)c.rule_noise_scale_m;
	p += offset;
	return value_noise(p) * 0.65 + value_noise(p * 2.3f + Vector2(5.2f, -1.7f)) * 0.35;
}

double Ground::cliff_from(double normal_y, double curvature, double noise) const {
	double raw = raw_tail(normal_y, c.cliff_start_cos, c.cliff_end_cos);
	double m = gclamp(raw + glerp(-c.cliff_edge_noise, c.cliff_edge_noise, noise), 0.0, 1.0);
	double lip = gclamp(raw_tail(curvature, c.lip_curvature_start, c.lip_curvature_end), 0.0, 1.0);
	lip *= gclamp(c.lip_sheer_tail - raw, 0.0, 1.0);
	m *= 1.0 - c.lip_strength * lip;
	return ease_ramp(m);
}

double Ground::scree_from(double curvature, double steep, double cliff, double noise, double breakup) const {
	double near = gclamp(raw_tail(steep, c.scree_near_start, c.scree_near_end), 0.0, 1.0);
	if (near <= 0.0) {
		return 0.0;
	}
	double concave = raw_tail(-curvature, c.scree_curvature_start, c.scree_curvature_end);
	concave += glerp(-c.scree_edge_noise, c.scree_edge_noise, noise) + (breakup - 0.5) * c.scree_fan;
	concave = gclamp(concave, 0.0, 1.0);
	double gaps = smoothstep(c.scree_breakup_low, c.scree_breakup_high, breakup);
	return ease_ramp(concave * near) * gaps * (1.0 - cliff);
}

Vector2 Ground::weights(double normal_y, Vector2 fields, Vector2 xz, double y) const {
	double cliff = 0.0;
	if (raw_tail(normal_y, c.cliff_start_cos, c.cliff_end_cos) > -c.cliff_edge_noise) {
		cliff = cliff_from(normal_y, fields.x, rule_noise(xz, y, c.cliff_noise_offset));
	}
	double scree = 0.0;
	double concave = raw_tail(-(double)fields.x, c.scree_curvature_start, c.scree_curvature_end);
	if (fields.y > c.scree_near_start && concave > -c.scree_edge_noise - 0.5 * c.scree_fan) {
		double breakup = value_noise(xz / (float)c.scree_breakup_scale_m + c.scree_breakup_offset);
		scree = scree_from(fields.x, fields.y, cliff, rule_noise(xz, y, c.scree_noise_offset), breakup);
	}
	return v2(cliff, scree);
}

double Ground::shape_painted(double total, Vector2 xz) const {
	if (total <= 0.0) {
		return 0.0;
	}
	Vector2 p = xz / (float)c.paint_edge_scale_m;
	double n = value_noise(p * 2.9f + c.paint_noise_offset);
	double bump = 4.0 * total * (1.0 - total);
	return gclamp(total + (n - 0.5) * 2.0 * c.paint_edge_noise * bump, 0.0, 1.0);
}

Vector2 Ground::painted_lookup(Vector2 xz) const {
	Vector2 p = xz / (float)c.paint_edge_scale_m;
	Vector2 warp = v2(value_noise(p + c.paint_warp_offset_a), value_noise(p + c.paint_warp_offset_b));
	return xz + (warp * 2.0f - Vector2(1.0f, 1.0f)) * (float)c.paint_edge_warp_m;
}

// ---- terrain helpers (ScatterGenerator, TerrainRules) -----------------------------------------

double Ground::triangle_height(const Grid &grid, int columns, int rows, Vector2 at) {
	double fx = gclamp(at.x, 0.0, columns - 1);
	double fz = gclamp(at.y, 0.0, rows - 1);
	int64_t x0 = imin(floori(fx), columns - 2);
	int64_t z0 = imin(floori(fz), rows - 2);
	double tx = fx - x0;
	double tz = fz - z0;
	int64_t i = z0 * columns + x0;
	if (tx + tz <= 1.0) {
		return grid[i] + ((double)grid[i + 1] - grid[i]) * tx + ((double)grid[i + columns] - grid[i]) * tz;
	}
	double h11 = grid[i + columns + 1];
	return h11 + (grid[i + columns] - h11) * (1.0 - tx) + (grid[i + 1] - h11) * (1.0 - tz);
}

Vector3 Ground::triangle_normal(const Grid &grid, int columns, int rows, Vector2 at, Vector2 step) {
	double fx = gclamp(at.x, 0.0, columns - 1);
	double fz = gclamp(at.y, 0.0, rows - 1);
	int64_t x0 = imin(floori(fx), columns - 2);
	int64_t z0 = imin(floori(fz), rows - 2);
	double tx = fx - x0;
	double tz = fz - z0;
	Vector3 n10 = vertex_normal(grid, columns, rows, x0 + 1, z0, step);
	Vector3 n01 = vertex_normal(grid, columns, rows, x0, z0 + 1, step);
	Vector3 n;
	if (tx + tz <= 1.0) {
		Vector3 n00 = vertex_normal(grid, columns, rows, x0, z0, step);
		n = n00 * (float)(1.0 - tx - tz) + n10 * (float)tx + n01 * (float)tz;
	} else {
		Vector3 n11 = vertex_normal(grid, columns, rows, x0 + 1, z0 + 1, step);
		n = n11 * (float)(tx + tz - 1.0) + n01 * (float)(1.0 - tx) + n10 * (float)(1.0 - tz);
	}
	return n.normalized();
}

Vector3 Ground::vertex_normal(const Grid &grid, int columns, int rows, int64_t x, int64_t z, Vector2 step) {
	int64_t x0 = imax(x - 1, 0);
	int64_t x1 = imin(x + 1, (int64_t)columns - 1);
	int64_t z0 = imax(z - 1, 0);
	int64_t z1 = imin(z + 1, (int64_t)rows - 1);
	int64_t row = z * columns;
	double slope_x = ((double)grid[row + x1] - grid[row + x0]) / ((x1 - x0) * (double)step.x);
	double slope_z = ((double)grid[z1 * columns + x] - grid[z0 * columns + x]) / ((z1 - z0) * (double)step.y);
	return Vector3((float)-slope_x, 1.0f, (float)-slope_z).normalized();
}

double Ground::bilinear(const Grid &grid, int columns, int rows, Vector2 at) {
	double fx = gclamp(at.x, 0.0, columns - 1);
	double fz = gclamp(at.y, 0.0, rows - 1);
	int64_t x0 = imin(floori(fx), columns - 2);
	int64_t z0 = imin(floori(fz), rows - 2);
	double tx = fx - x0;
	double tz = fz - z0;
	int64_t i = z0 * columns + x0;
	double top = glerp(grid[i], grid[i + 1], tx);
	double bottom = glerp(grid[i + columns], grid[i + columns + 1], tx);
	return glerp(top, bottom, tz);
}

Vector2 Ground::field_at(const Grid &curvature, const Grid &steep, int columns, int rows, Vector2 at) {
	double fx = gclamp(at.x, 0.0, columns - 1);
	double fz = gclamp(at.y, 0.0, rows - 1);
	int64_t x0 = imin(floori(fx), columns - 2);
	int64_t z0 = imin(floori(fz), rows - 2);
	double tx = fx - x0;
	double tz = fz - z0;
	int64_t i = z0 * columns + x0;
	if (tx + tz <= 1.0) {
		double w0 = 1.0 - tx - tz;
		return v2(curvature[i] * w0 + curvature[i + 1] * tx + curvature[i + columns] * tz,
				steep[i] * w0 + steep[i + 1] * tx + steep[i + columns] * tz);
	}
	double w11 = tx + tz - 1.0;
	int64_t j = i + columns + 1;
	return v2(curvature[j] * w11 + curvature[i + columns] * (1.0 - tx) + curvature[i + 1] * (1.0 - tz),
			steep[j] * w11 + steep[i + columns] * (1.0 - tx) + steep[i + 1] * (1.0 - tz));
}

} // namespace ttscatter
