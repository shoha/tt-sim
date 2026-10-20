// ScatterGenerator's per-cell path (utils/scatter_generator.gd), line for line: hashed candidate
// buckets, _evaluate's thinning, Matern III spacing on an explicit stack, relations, clearance,
// rock blockers and rows. See scatter_gen.h for the context.
#include "scatter_gen.h"

#include <algorithm>

#include <godot_cpp/variant/string.hpp>

namespace ttscatter {

static constexpr int64_t SALT_X = 0x68E31DA4, SALT_Z = 0x3C6EF372, SALT_PRIORITY = 0x1B56C4E9;
static constexpr int64_t SALT_OWNER = 0x5BD1E995, SALT_ACCEPT = 0x27D4EB2F, SALT_ASSET = 0x165667B1;
static constexpr int64_t SALT_YAW = 0x61C88647, SALT_SCALE = 0x2545F491, SALT_TILT = 0x4F1BBCDC;
static constexpr int64_t SALT_TILT_DIRECTION = 0x7A4D3B1F, SALT_CANDIDATE = 0x632BE5AB;
static constexpr double CEILING_SLACK = 1e-9;
static constexpr double SLOPE_FALLOFF_DEG = 10.0;
static constexpr double NORMAL_TILT_MAX_RAD = 0.12;
static constexpr double CHUNK = 10.0;
static constexpr int ROW_STRIDE = 10;

int64_t Ctx::mix(int64_t value) {
	int64_t h = value & MASK32;
	h ^= h >> 16;
	h = (h * 0x7FEB352D) & MASK32;
	h ^= h >> 15;
	h = (h * 0x1B873593) & MASK32;
	h ^= h >> 16;
	return h;
}

double Ctx::respond(double density, double lead, double lag) {
	double d = gclamp(density, 0.0, 1.0);
	if (lead != 1.0) {
		d = 1.0 - std::pow(1.0 - d, lead);
	}
	if (lag != 1.0) {
		d = std::pow(d, lag);
	}
	return d;
}

Ctx::Ctx(Job &p_job) :
		job(p_job), c(p_job.consts), species(p_job.species), ground(p_job.grids, p_job.consts), accents(p_job.consts), bounds(p_job.bounds) {
	fields.resize(job.fields.size());
	for (size_t f = 0; f < job.fields.size(); f++) {
		fields[f].plan = &job.fields[f];
	}
	size_t n = species.size();
	finals.resize(n);
	parents.resize(n);
	parent_buckets.resize(n);
	parent_lists.resize(n);
	parent_tiles.resize(n);
	noises.resize(n);
	for (size_t s = 0; s < n; s++) {
		const Entry &entry = species[s];
		if (entry.has_noise) {
			noises[s] = std::make_unique<fastnoiselite::FastNoiseLite>();
			setup_pattern_noise(*noises[s], entry.noise_seed, entry.noise_frequency, entry.noise_octaves);
		}
	}
}

void Ctx::generate() {
	for (size_t s = 0; s < species.size(); s++) {
		if (s < job.cells_by_species.size() && !job.cells_by_species[s].empty()) {
			generate_species((int)s);
		}
	}
}

bool Ctx::blocked(const Entry &entry, Vector2 p) const {
	if (!entry.blocked_by_rocks) {
		return false;
	}
	const std::vector<float> &b = job.blockers;
	for (size_t i = 0; i + 2 < b.size(); i += 3) {
		double r = b[i + 2];
		if ((double)p.distance_squared_to(Vector2(b[i], b[i + 1])) < r * r) {
			return true;
		}
	}
	return false;
}

void Ctx::generate_species(int s) {
	const Entry &entry = species[s];
	if (entry.field < 0) {
		return;
	}
	LiveField &field = fields[entry.field];
	if (field.plan->empty) {
		return;
	}
	bool referenced = entry.referenced;
	bool edge_needed = entry.clump_scale;
	bool single_owner = field.plan->owners.size() == 1;
	double size = field.plan->bucket;
	godot::PackedFloat32Array rows;
	std::vector<int> assets;
	bool mass = entry.mass;
	std::vector<float> anchors;
	for (const godot::Vector2i &cell : job.cells_by_species[s]) {
		Rect2 area = Rect2(Vector2((float)cell.x, (float)cell.y) * (float)CHUNK, Vector2((float)CHUNK, (float)CHUNK)).intersection(bounds);
		if (area.size.x <= 0.0f || area.size.y <= 0.0f) {
			continue;
		}
		int64_t bj1 = floori(area.position.y / size), bi1 = floori((area.position.x + area.size.x) / size);
		int64_t bj_end = floori((area.position.y + area.size.y) / size);
		int64_t bi0 = floori(area.position.x / size);
		for (int64_t bj = bj1; bj <= bj_end; bj++) {
			for (int64_t bi = bi0; bi <= bi1; bi++) {
				const List &cands = *bucket(field, bi, bj);
				for (int c_ = 0; c_ < (int)cands.size(); c_ += STRIDE) {
					if (!single_owner && (int)cands[c_ + 3] != s) {
						continue;
					}
					double x = cands[c_];
					double z = cands[c_ + 1];
					if (floori(x / CHUNK) != cell.x || floori(z / CHUNK) != cell.y) {
						continue;
					}
					bool placed = referenced ? is_final(s, cands, c_) : evaluate(entry, cands, c_);
					if (!placed || blocked(entry, v2(x, z))) {
						continue;
					}
					double edge_value = edge;
					if ((edge_needed || mass) && referenced) {
						edge_value = membership(s, x, z, false).y;
					}
					assets.push_back(append_row(entry, cands, c_, edge_value, rows));
					if (mass) {
						anchors.push_back(anchor.x);
						anchors.push_back(anchor.y);
					}
				}
			}
		}
	}
	split_rows(entry, rows, assets);
	if (mass) {
		collect_anchors(rows, anchors);
	}
}

void Ctx::split_rows(const Entry &entry, godot::PackedFloat32Array &rows, const std::vector<int> &assets) {
	if (rows.is_empty()) {
		return;
	}
	float *w = rows.ptrw();
	int64_t count = rows.size();
	for (int64_t i = 0; i < count; i++) {
		w[i] = (float)snapped(w[i], c.row_step);
	}
	if (entry.assets.size() == 1) {
		result[godot::String::utf8(entry.assets[0].c_str())] = rows;
		return;
	}
	std::vector<godot::PackedFloat32Array> per_asset(entry.assets.size());
	const float *r = rows.ptr();
	for (size_t i = 0; i < assets.size(); i++) {
		godot::PackedFloat32Array &out = per_asset[assets[i]];
		int64_t at = out.size();
		out.resize(at + ROW_STRIDE);
		float *o = out.ptrw();
		for (int k = 0; k < ROW_STRIDE; k++) {
			o[at + k] = r[i * ROW_STRIDE + k];
		}
	}
	for (size_t a = 0; a < entry.assets.size(); a++) {
		if (!per_asset[a].is_empty()) {
			result[godot::String::utf8(entry.assets[a].c_str())] = per_asset[a];
		}
	}
}

void Ctx::collect_anchors(const godot::PackedFloat32Array &rows, const std::vector<float> &anchors) {
	const float *r = rows.ptr();
	for (size_t i = 0; i < anchors.size() / 2; i++) {
		float x = (float)snapped(r[i * ROW_STRIDE], c.row_step);
		float z = (float)snapped(r[i * ROW_STRIDE + 2], c.row_step);
		Vector2 offset = v2(snapped((double)anchors[i * 2] - x, c.anchor_step), snapped((double)anchors[i * 2 + 1] - z, c.anchor_step));
		anchors_out[Vector2(x, z)] = offset;
	}
}

const List *Ctx::bucket(LiveField &field, int64_t bi, int64_t bj) {
	int64_t k = key(bi, bj);
	const List *const *known = field.buckets.find(k);
	if (known) {
		return *known;
	}
	int per_bucket = c.candidates_per_bucket;
	const FieldPlan &f = *field.plan;
	double size = f.bucket;
	int64_t base = mix(mix(f.seed ^ (bi & MASK32)) ^ (bj & MASK32));
	List out(per_bucket * STRIDE);
	for (int i = 0; i < per_bucket; i++) {
		int64_t h = mix(base + (int64_t)(i + 1) * SALT_CANDIDATE);
		int o = i * STRIDE;
		out[o] = (bi + unit(h, SALT_X)) * size;
		out[o + 1] = (bj + unit(h, SALT_Z)) * size;
		out[o + 2] = (double)mix(h ^ SALT_PRIORITY);
		int owner = f.owners[0];
		if (f.owners.size() > 1) {
			double pick = unit(h, SALT_OWNER);
			owner = f.owners.back();
			for (size_t m = 0; m < f.cdf.size(); m++) {
				if (pick < f.cdf[m]) {
					owner = f.owners[m];
					break;
				}
			}
		}
		out[o + 3] = owner;
		out[o + 4] = (double)(k * per_bucket + i);
		out[o + 5] = (double)h;
	}
	const List *stored = store.add(std::move(out));
	field.buckets.set(k, stored);
	return stored;
}

bool Ctx::is_final(int s, const List &cands, int c_) {
	I64Map<uint8_t> &memo = finals[s];
	int64_t id = (int64_t)cands[c_ + 4];
	const uint8_t *known = memo.find(id);
	if (known) {
		return *known != 0;
	}
	bool placed = evaluate(species[s], cands, c_);
	memo.set(id, placed ? 1 : 0);
	return placed;
}

double Ctx::pattern_value(const Entry &entry, double x, double z) const {
	float n = noises[entry.index]->GetNoise((float)x, (float)z);
	return gclamp(0.5 + 0.5 * entry.noise_contrast * n, 0.0, 1.0);
}

bool Ctx::evaluate(const Entry &entry, const List &cands, int c_) {
	double x = cands[c_];
	double z = cands[c_ + 1];
	Vector2 p = v2(x, z);
	if (!bounds.has_point(p)) {
		return false;
	}
	double u = unit((int64_t)cands[c_ + 5], SALT_ACCEPT);
	double most = ground.density_ceiling_at(p, entry.ground_role);
	if (u >= respond(most, entry.response_lead, entry.response_lag) + CEILING_SLACK) {
		return false;
	}
	double painted = ground.species_density_at(p, entry.ground_role);
	double keep = respond(painted, entry.response_lead, entry.response_lag);
	if (u >= keep) {
		return false;
	}
	int s = entry.index;
	double influence = entry.influence;
	double shade = 1.0;
	if (influence > 0.0) {
		shade = 1.0 - influence * (1.0 - pattern_value(entry, x, z));
	}
	if (entry.bare && !entry.bare->empty()) {
		keep = off_bare(*entry.bare, keep, x, z, u, shade);
		if (u >= keep) {
			return false;
		}
	}
	if (influence > 0.0) {
		keep *= shade;
		if (u >= keep) {
			return false;
		}
	}
	if (entry.slope_cos > -1.5) {
		Vector3 normal = ground.normal_at(p);
		if (normal.y < entry.slope_cos) {
			double a = rad_to_deg(std::acos(gclamp(normal.y, -1.0, 1.0)));
			keep *= gclamp(1.0 - (a - entry.slope_max) / SLOPE_FALLOFF_DEG, 0.0, 1.0);
			if (u >= keep) {
				return false;
			}
		}
	}
	if (unfooted(p, entry.footing_m)) {
		return false;
	}
	bool spaced = entry.spacing <= 0.0;
	if (entry.clumped) {
		Vector2 m = membership(s, x, z, false);
		edge = m.y;
		double bank = gclamp(painted - 1.0, 0.0, 1.0);
		if (entry.mass) {
			if (u >= keep * gmax(m.x, bank)) {
				return false;
			}
			if (!spaced && !spaced_survives(fields[entry.field], cands, c_)) {
				return false;
			}
			spaced = true;
			m = refined(entry, m, x, z);
		}
		keep *= gmax(m.x, bank);
		if (u >= keep) {
			return false;
		}
	}
	if (!spaced && !spaced_survives(fields[entry.field], cands, c_)) {
		return false;
	}
	for (const Relation &relation : entry.avoid) {
		keep *= 1.0 - relation.influence * proximity(relation, x, z);
		if (u >= keep) {
			return false;
		}
	}
	if (!entry.clumped) {
		for (const Relation &relation : entry.near) {
			keep *= 1.0 - relation.influence * (1.0 - proximity(relation, x, z));
			if (u >= keep) {
				return false;
			}
		}
	}
	for (int field_index : entry.clearance) {
		if (occupied(field_index, x, z, entry.clearance_m)) {
			return false;
		}
	}
	return true;
}

bool Ctx::unfooted(Vector2 p, double radius) const {
	if (!(radius > 0.0)) {
		return false;
	}
	double h = ground.height_at(p);
	double sag = 0.0;
	double allowance = radius * c.footing_slope_tan;
	int directions = c.footing_directions;
	for (int k = 0; k < directions; k++) {
		float a = (float)(PI_D * k / directions);
		Vector2 d = Vector2(godot::Math::cos(a), godot::Math::sin(a)) * (float)radius;
		double ha = ground.height_at(p + d);
		double hb = ground.height_at(p - d);
		sag = gmax(sag, gmax(h - (ha + hb) * 0.5, h - gmin(ha, hb) - allowance));
	}
	return sag > c.footing_sag_m;
}

bool Ctx::spaced_survives(LiveField &field, const List &cands, int c_) {
	I64Map<uint8_t> &memo = field.spaced;
	int64_t id = (int64_t)cands[c_ + 4];
	const uint8_t *known = memo.find(id);
	if (known) {
		return *known != 0;
	}
	List first = higher_neighbours(field, cands[c_], cands[c_ + 1], cands[c_ + 2], id);
	if (first.empty()) {
		memo.set(id, 1);
		return true;
	}
	const uint8_t *first_known = memo.find((int64_t)first[3]);
	if (first_known && *first_known) {
		memo.set(id, 0);
		return false;
	}
	std::vector<int64_t> ids{ id };
	std::vector<List> lists;
	lists.push_back(std::move(first));
	std::vector<size_t> positions{ 0 };
	while (!ids.empty()) {
		size_t top = ids.size() - 1;
		size_t pos = positions[top];
		bool survives = true;
		bool pushed = false;
		while (pos < lists[top].size()) {
			const List &list = lists[top];
			int64_t neighbour = (int64_t)list[pos + 3];
			const uint8_t *decided = memo.find(neighbour);
			if (!decided) {
				positions[top] = pos;
				List next = higher_neighbours(field, list[pos], list[pos + 1], list[pos + 2], neighbour);
				ids.push_back(neighbour);
				lists.push_back(std::move(next));
				positions.push_back(0);
				pushed = true;
				break;
			}
			if (*decided) {
				survives = false;
				break;
			}
			pos += 4;
		}
		if (pushed) {
			continue;
		}
		memo.set(ids[top], survives ? 1 : 0);
		ids.pop_back();
		lists.pop_back();
		positions.pop_back();
	}
	return *memo.find(id) != 0;
}

List Ctx::higher_neighbours(LiveField &field, double x, double z, double priority, int64_t id) {
	double spacing = field.plan->spacing;
	double reach = spacing * spacing;
	double size = field.plan->bucket;
	List found;
	std::vector<int64_t> keys;
	int64_t bj1 = floori((z + spacing) / size), bi1 = floori((x + spacing) / size);
	for (int64_t bj = floori((z - spacing) / size); bj <= bj1; bj++) {
		for (int64_t bi = floori((x - spacing) / size); bi <= bi1; bi++) {
			const List &cands = *bucket(field, bi, bj);
			for (size_t i = 0; i < cands.size(); i += STRIDE) {
				double other = cands[i + 2];
				if (other < priority || (other == priority && (int64_t)cands[i + 4] <= id)) {
					continue;
				}
				double dx = cands[i] - x;
				double dz = cands[i + 1] - z;
				if (dx * dx + dz * dz >= reach) {
					continue;
				}
				keys.push_back((int64_t)other * 1048576 + (int64_t)keys.size());
				found.push_back(cands[i]);
				found.push_back(cands[i + 1]);
				found.push_back(other);
				found.push_back(cands[i + 4]);
			}
		}
	}
	if (keys.size() < 2) {
		return found;
	}
	std::sort(keys.begin(), keys.end());
	List ordered(found.size());
	for (size_t i = 0; i < keys.size(); i++) {
		size_t from = (size_t)(keys[keys.size() - 1 - i] & 0xFFFFF) * 4;
		for (int j = 0; j < 4; j++) {
			ordered[i * 4 + j] = found[from + j];
		}
	}
	return ordered;
}

Vector2 Ctx::membership(int s, double x, double z, bool refine) {
	const Entry &entry = species[s];
	double size = fields[entry.field].plan->bucket;
	int64_t bi = floori(x / size);
	int64_t bj = floori(z / size);
	const List *const *known = parent_lists[s].find(key(bi, bj));
	const List *list = known ? *known : parents_near_bucket(s, bi, bj);
	return mass_membership(entry, *list, x, z, refine);
}

double Ctx::proximity(const Relation &relation, double x, double z) {
	int target = relation.target;
	int field_index = species[target].field;
	if (field_index < 0) {
		return 0.0;
	}
	LiveField &field = fields[field_index];
	double distance = relation.distance;
	double transition = relation.transition;
	double reach = distance + transition;
	double size = field.plan->bucket;
	double best = 0.0;
	int64_t bj1 = floori((z + reach) / size), bi1 = floori((x + reach) / size);
	for (int64_t bj = floori((z - reach) / size); bj <= bj1; bj++) {
		for (int64_t bi = floori((x - reach) / size); bi <= bi1; bi++) {
			const List &cands = *bucket(field, bi, bj);
			for (int i = 0; i < (int)cands.size(); i += STRIDE) {
				if ((int)cands[i + 3] != target) {
					continue;
				}
				double dx = cands[i] - x;
				double dz = cands[i + 1] - z;
				double d2 = dx * dx + dz * dz;
				if (d2 >= reach * reach) {
					continue;
				}
				double d = std::sqrt(d2);
				double near = d <= distance ? 1.0 : 1.0 - (d - distance) / transition;
				if (near <= best || !is_final(target, cands, i)) {
					continue;
				}
				best = near;
				if (best >= 1.0) {
					return best;
				}
			}
		}
	}
	return best;
}

bool Ctx::occupied(int field_index, double x, double z, double clearance) {
	LiveField &field = fields[field_index];
	double size = field.plan->bucket;
	int64_t bj1 = floori((z + clearance) / size), bi1 = floori((x + clearance) / size);
	for (int64_t bj = floori((z - clearance) / size); bj <= bj1; bj++) {
		for (int64_t bi = floori((x - clearance) / size); bi <= bi1; bi++) {
			const List &cands = *bucket(field, bi, bj);
			for (int i = 0; i < (int)cands.size(); i += STRIDE) {
				double dx = cands[i] - x;
				double dz = cands[i + 1] - z;
				if (dx * dx + dz * dz >= clearance * clearance) {
					continue;
				}
				if (is_final((int)cands[i + 3], cands, i)) {
					return true;
				}
			}
		}
	}
	return false;
}

int Ctx::append_row(const Entry &entry, const List &cands, int c_, double edge_value, godot::PackedFloat32Array &rows) {
	double x = cands[c_];
	double z = cands[c_ + 1];
	int64_t h = (int64_t)cands[c_ + 5];
	Vector2 p = v2(x, z);
	Vector3 up(0.0f, 1.0f, 0.0f);
	if (entry.align_normal) {
		Vector3 normal = ground.normal_at(p);
		double tilt = unit(h, SALT_TILT) * NORMAL_TILT_MAX_RAD;
		up = tilted(normal, tilt, unit(h, SALT_TILT_DIRECTION) * TAU_D);
	}
	double yaw = (unit(h, SALT_YAW) - 0.5) * entry.yaw_range;
	Quaternion rotation = Quaternion(Vector3(0.0f, 1.0f, 0.0f), up) * Quaternion(Vector3(0.0f, 1.0f, 0.0f), (float)yaw);
	double scale = 1.0 + entry.scale_spread * (2.0 * unit(h, SALT_SCALE) - 1.0);
	if (entry.scale_influence > 0.0) {
		double pattern = pattern_value(entry, x, z);
		scale *= 1.0 - entry.scale_influence * (1.0 - pattern);
	}
	if (entry.clump_scale) {
		scale *= 1.0 - entry.clump_shrink * edge_value;
	}
	scale = gmax(scale, entry.scale_floor);
	int asset_count = entry.asset_count;
	int asset = (int)imin(floori(unit(h, SALT_ASSET) * asset_count), asset_count - 1);
	rows.push_back((float)x);
	rows.push_back((float)ground.height_at(p));
	rows.push_back((float)z);
	rows.push_back(rotation.x);
	rows.push_back(rotation.y);
	rows.push_back(rotation.z);
	rows.push_back(rotation.w);
	if (entry.mass) {
		append_scale(rows, scale, entry, edge_value);
	} else {
		rows.push_back((float)scale);
		rows.push_back((float)scale);
		rows.push_back((float)scale);
	}
	return asset;
}

Vector3 Ctx::tilted(Vector3 normal, double angle, double azimuth) {
	if (angle <= 0.0) {
		return normal;
	}
	Vector3 helper = std::fabs((double)normal.x) < 0.9 ? Vector3(1.0f, 0.0f, 0.0f) : Vector3(0.0f, 0.0f, -1.0f);
	Vector3 tangent = normal.cross(helper).normalized();
	Vector3 bitangent = normal.cross(tangent);
	Vector3 axis = tangent * (float)std::cos(azimuth) + bitangent * (float)std::sin(azimuth);
	return normal.rotated(axis, (float)angle).normalized();
}

} // namespace ttscatter
