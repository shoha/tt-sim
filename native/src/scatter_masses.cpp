// Clump parents (ScatterClumps) and grass masses (ScatterMass) on the generator context, line
// for line with utils/scatter_clumps.gd and utils/scatter_mass.gd.
#include "scatter_gen.h"

namespace ttscatter {

static constexpr int PARENT_STRIDE = 6;
static constexpr int LISTED_STRIDE = PARENT_STRIDE + 2;
static constexpr int64_t SALT_ACCEPT = 0x27D4EB2F, SALT_RADIUS = 0x0B4E0EF3, SALT_ANGLE = 0x3A8F05C5;
static constexpr int64_t SALT_ZONE = 0x4C957F2D;
static const double FILL_RINGS[3] = { 0.0, 0.45, 0.85 };
static constexpr int FILL_SPOKES = 8;
static constexpr double FILL_CORE_RING = 0.5;
static constexpr double SHOULDER_LO = 0.5, SHOULDER_HI = 0.9;

static void span_of(const Rect2 &rect, double reach, double size, int64_t *out) {
	out[0] = floori((rect.position.x - reach) / size);
	out[1] = floori((rect.position.x + rect.size.x + reach) / size);
	out[2] = floori((rect.position.y - reach) / size);
	out[3] = floori((rect.position.y + rect.size.y + reach) / size);
}

// ---- ScatterClumps --------------------------------------------------------------------------------

const List *Ctx::parents_near_bucket(int s, int64_t bi, int64_t bj) {
	I64Map<const List *> &memo = parent_lists[s];
	int64_t k = key(bi, bj);
	const List *const *cached = memo.find(k);
	if (cached) {
		return *cached;
	}
	const Entry &entry = species[s];
	double child_size = fields[entry.field].plan->bucket;
	Rect2 rect(v2(bi * child_size, bj * child_size), v2(child_size, child_size));
	double size = fields[entry.parent_field].plan->bucket;
	double transition = entry.clump_transition;
	double root = std::sqrt(entry.mass_stretch);
	double reach = (entry.clump_radius * (1.0 + entry.clump_jitter) + transition) * root;
	int64_t span[4];
	span_of(rect, reach, size, span);
	List out;
	int64_t buckets = (span[1] - span[0] + 1) * (span[3] - span[2] + 1);
	double left = rect.position.x, right = rect.position.x + rect.size.x;
	double near_z = rect.position.y, far_z = rect.position.y + rect.size.y;
	if (buckets < c.tile_min_buckets || !entry.near.empty()) {
		I64Map<const List *> &kept_memo = parent_buckets[s];
		for (int64_t parent_j = span[2]; parent_j <= span[3]; parent_j++) {
			int64_t bucket_key = key(span[0], parent_j);
			for (int64_t parent_i = span[0]; parent_i <= span[1]; parent_i++) {
				const List *const *known = kept_memo.find(bucket_key);
				bucket_key += BUCKET_SPAN;
				const List &kept = known ? **known : *kept_parents(s, parent_i, parent_j);
				for (size_t i = 0; i < kept.size(); i += PARENT_STRIDE) {
					double px = kept[i], pz = kept[i + 1], radius = kept[i + 2];
					double dx = gmax(0.0, gmax(left - px, px - right));
					double dz = gmax(0.0, gmax(near_z - pz, pz - far_z));
					double parent_reach = (radius + transition) * root;
					if (dx * dx + dz * dz > parent_reach * parent_reach) {
						continue;
					}
					out.insert(out.end(), kept.begin() + i, kept.begin() + i + PARENT_STRIDE);
				}
			}
		}
		const List *scanned = store.add(std::move(out));
		memo.set(k, scanned);
		return scanned;
	}
	const List &listed_parents = *tile(s, bi, bj, reach);
	for (size_t i = 0; i < listed_parents.size(); i += LISTED_STRIDE) {
		int64_t parent_i = (int64_t)listed_parents[i + PARENT_STRIDE];
		int64_t parent_j = (int64_t)listed_parents[i + PARENT_STRIDE + 1];
		if (parent_i < span[0] || parent_i > span[1] || parent_j < span[2] || parent_j > span[3]) {
			continue;
		}
		double px = listed_parents[i], pz = listed_parents[i + 1], radius = listed_parents[i + 2];
		double dx = gmax(0.0, gmax(left - px, px - right));
		double dz = gmax(0.0, gmax(near_z - pz, pz - far_z));
		double parent_reach = (radius + transition) * root;
		if (dx * dx + dz * dz > parent_reach * parent_reach) {
			continue;
		}
		out.insert(out.end(), listed_parents.begin() + i, listed_parents.begin() + i + PARENT_STRIDE);
	}
	const List *tiled = store.add(std::move(out));
	memo.set(k, tiled);
	return tiled;
}

const List *Ctx::kept_parents(int s, int64_t bi, int64_t bj) {
	I64Map<const List *> &memo = parent_buckets[s];
	int64_t k = key(bi, bj);
	const List *const *cached = memo.find(k);
	if (cached) {
		return *cached;
	}
	const Entry &entry = species[s];
	double radius = entry.clump_radius;
	const List &cands = *bucket(fields[entry.parent_field], bi, bj);
	List out;
	for (int i = 0; i < (int)cands.size(); i += STRIDE) {
		if (!parent_kept(s, cands, i)) {
			continue;
		}
		int64_t h = (int64_t)cands[i + 5];
		double jitter = 2.0 * unit(h, SALT_RADIUS) - 1.0;
		out.push_back(cands[i]);
		out.push_back(cands[i + 1]);
		out.push_back(radius * (1.0 + entry.clump_jitter * jitter));
		double a = 0.0;
		if (entry.mass) {
			double turn = 2.0 * unit(h, SALT_ANGLE) - 1.0;
			a = parent_spin(entry, cands[i], cands[i + 1], turn);
		}
		out.push_back(a);
		out.push_back(std::cos(a));
		out.push_back(std::sin(a));
	}
	const List *kept = store.add(std::move(out));
	memo.set(k, kept);
	return kept;
}

bool Ctx::parent_kept(int s, const List &cands, int i) {
	I64Map<uint8_t> &memo = parents[s];
	int64_t id = (int64_t)cands[i + 4];
	const uint8_t *known = memo.find(id);
	if (known) {
		return *known != 0;
	}
	const Entry &entry = species[s];
	bool kept = spaced_survives(fields[entry.parent_field], cands, i);
	if (kept && !entry.near.empty()) {
		double keep = 1.0;
		for (const Relation &relation : entry.near) {
			double near = proximity(relation, cands[i], cands[i + 1]);
			keep *= 1.0 - relation.influence * (1.0 - near);
		}
		kept = unit((int64_t)cands[i + 5], SALT_ACCEPT) < keep;
	}
	kept = kept && (!entry.mass || zone_kept(entry, cands, i));
	memo.set(id, kept ? 1 : 0);
	return kept;
}

List Ctx::listed(int s, const int64_t *span) {
	List out;
	for (int64_t parent_j = span[2]; parent_j <= span[3]; parent_j++) {
		for (int64_t parent_i = span[0]; parent_i <= span[1]; parent_i++) {
			const List &kept = *kept_parents(s, parent_i, parent_j);
			for (size_t i = 0; i < kept.size(); i += PARENT_STRIDE) {
				out.insert(out.end(), kept.begin() + i, kept.begin() + i + PARENT_STRIDE);
				out.push_back((double)parent_i);
				out.push_back((double)parent_j);
			}
		}
	}
	return out;
}

const List *Ctx::tile(int s, int64_t bi, int64_t bj, double reach) {
	const Entry &entry = species[s];
	double child_size = fields[entry.field].plan->bucket;
	int64_t per = imax(1, floori(c.tile_m / child_size));
	int64_t ti = floori((double)bi / per);
	int64_t tj = floori((double)bj / per);
	I64Map<const List *> &memo = parent_tiles[s];
	int64_t k = key(ti, tj);
	const List *const *cached = memo.find(k);
	if (cached) {
		return *cached;
	}
	double size = fields[entry.parent_field].plan->bucket;
	int64_t first_i = ti * per, first_j = tj * per;
	int64_t last_i = first_i + per - 1, last_j = first_j + per - 1;
	Vector2 size_v = v2(child_size, child_size);
	int64_t first[4], last[4];
	span_of(Rect2(v2(first_i * child_size, first_j * child_size), size_v), reach, size, first);
	span_of(Rect2(v2(last_i * child_size, last_j * child_size), size_v), reach, size, last);
	int64_t span[4] = { first[0], last[1], first[2], last[3] };
	const List *out = store.add(listed(s, span));
	memo.set(k, out);
	return out;
}

// ---- ScatterMass ------------------------------------------------------------------------------------

Vector2 Ctx::mass_membership(const Entry &entry, const List &parents_list, double x, double z, bool refine) {
	double transition = entry.clump_transition;
	float best_x = 0.0f, best_y = 1.0f;
	double stretch = entry.mass_stretch;
	double root = std::sqrt(stretch);
	bool mass = entry.mass;
	bool additive = c.additive_clumps && !mass;
	double total = 0.0;
	int chosen = -1;
	for (int i = 0; i < (int)parents_list.size(); i += PARENT_STRIDE) {
		double dx = parents_list[i] - x;
		double dz = parents_list[i + 1] - z;
		if (stretch > 1.0) {
			double ca = parents_list[i + 4];
			double sa = parents_list[i + 5];
			double along = (dx * ca + dz * sa) / root;
			dz = (dz * ca - dx * sa) * root;
			dx = along;
		}
		double radius = parents_list[i + 2];
		double d = std::sqrt(dx * dx + dz * dz);
		double inside = 1.0;
		if (d > radius) {
			if (transition <= 0.0 || d >= radius + transition) {
				continue;
			}
			inside = 1.0 - smoothstep(radius, radius + transition, d);
		}
		double edge_d = d / (radius + transition);
		total += inside;
		if (additive) {
			if (edge_d < best_y) {
				best_y = (float)edge_d;
				chosen = i;
			}
		} else if (inside > best_x || (inside == best_x && edge_d < best_y)) {
			best_x = (float)inside;
			best_y = (float)edge_d;
			chosen = i;
		}
	}
	if (chosen >= 0) {
		anchor = v2(parents_list[chosen], parents_list[chosen + 1]);
	}
	Vector2 best(best_x, best_y);
	if (additive) {
		best = Vector2((float)gmin(1.0, total / c.clump_saturation), best.y);
	} else if (mass) {
		best = Vector2(best.x, (float)held_edge(entry, best.y));
		if (refine) {
			best = refined(entry, best, x, z);
		}
	}
	return best;
}

Vector2 Ctx::refined(const Entry &entry, Vector2 best, double x, double z) {
	if (!entry.mass) {
		return best;
	}
	if (best.x > 0.0f) {
		best = Vector2((float)(best.x * zone_share_keep(entry, x, z)), best.y);
	}
	if (best.x > 0.0f) {
		best = Vector2((float)(best.x * shoulder_keep(entry, x, z)), best.y);
	}
	return best;
}

double Ctx::held_edge(const Entry &entry, double edge_value) {
	double hold = entry.mass_core_hold;
	if (hold <= 0.0) {
		return edge_value;
	}
	return gclamp((edge_value - hold) / (1.0 - hold), 0.0, 1.0);
}

double Ctx::shoulder_keep(const Entry &entry, double x, double z) {
	double reach = entry.has_zone ? entry.zone.shoulder : 0.0;
	if (reach <= 0.0) {
		return 1.0;
	}
	Vector2 at = v2(x, z);
	int role = entry.ground_role;
	double own = ground.species_density_at(at, role);
	if (own <= 0.0) {
		return 1.0;
	}
	static const Vector2 dirs[4] = { Vector2(1.0f, 0.0f), Vector2(-1.0f, 0.0f), Vector2(0.0f, 1.0f), Vector2(0.0f, -1.0f) };
	double least = 1.0;
	for (const Vector2 &dir : dirs) {
		least = gmin(least, ground.species_density_at(at + dir * (float)reach, role) / own);
	}
	return smoothstep(SHOULDER_LO, SHOULDER_HI, least);
}

bool Ctx::zone_kept(const Entry &entry, const List &cands, int i) {
	if (!entry.has_zone || entry.zones == nullptr) {
		return true;
	}
	const ZoneRule &rule = entry.zone;
	ZonesRecord &zones = *entry.zones;
	double u = unit((int64_t)cands[i + 5], SALT_ZONE);
	zones.zone_weights(cands[i], cands[i + 1], w4);
	int zone = strongest(w4);
	int family = rule.family[zone];
	if (u >= rule.keep[zone] || ZonesRecord::family_share(w4, rule.family, family) < rule.core) {
		return false;
	}
	return filled(entry, family, cands[i], cands[i + 1]);
}

double Ctx::zone_share_keep(const Entry &entry, double x, double z) {
	double share = entry.has_zone ? entry.zone.share : 0.0;
	if (share <= 0.0 || entry.zones == nullptr) {
		return 1.0;
	}
	ZonesRecord &zones = *entry.zones;
	const int *family = entry.zone.family;
	int64_t k = key_of(anchor);
	const int *known = anchor_family.find(k);
	int home;
	if (known) {
		home = *known;
	} else {
		zones.zone_weights(anchor.x, anchor.y, w4);
		home = family[strongest(w4)];
		anchor_family.set(k, home);
	}
	return zones.share_reaches(x, z, family, home, share) ? 1.0 : 0.0;
}

bool Ctx::filled(const Entry &entry, int family, double x, double z) {
	double fill = entry.has_zone ? entry.zone.fill : 0.0;
	if (fill <= 0.0) {
		return true;
	}
	ZonesRecord &zones = *entry.zones;
	double radius = entry.clump_radius;
	double root = std::sqrt(gmax(entry.mass_stretch, 1.0));
	double a = parent_angle(entry, x, z, deg_to_rad(entry.clump_angle_deg));
	Vector2 along = v2(std::cos(a), std::sin(a)) * (float)radius * (float)root;
	Vector2 across = v2(-std::sin(a), std::cos(a)) * (float)radius / (float)root;
	int hits = 0, total = 0;
	static const std::vector<BareRecord> no_bare;
	const std::vector<BareRecord> &bare = entry.bare ? *entry.bare : no_bare;
	for (double ring : FILL_RINGS) {
		int spokes = ring <= 0.0 ? 1 : FILL_SPOKES;
		for (int i = 0; i < spokes; i++) {
			double t = TAU_D * i / FILL_SPOKES;
			Vector2 p = v2(x, z) + (along * (float)std::cos(t) + across * (float)std::sin(t)) * (float)ring;
			total += 1;
			if (accents.bare_keep(bare, p.x, p.y) < 0.5) {
				if (ring < FILL_CORE_RING) {
					return false;
				}
				continue;
			}
			if (zones.share_reaches(p.x, p.y, entry.zone.family, family, entry.zone.share)) {
				hits += 1;
			}
		}
	}
	return hits >= fill * total;
}

int Ctx::strongest(const double *w) {
	int best = 0;
	for (int k = 1; k < 4; k++) {
		if (w[k] > w[best]) {
			best = k;
		}
	}
	return best;
}

double Ctx::parent_spin(const Entry &entry, double x, double z, double turn) {
	if (!entry.mass) {
		return 0.0;
	}
	double a = deg_to_rad(entry.clump_angle_deg);
	a += deg_to_rad(entry.clump_angle_jitter_deg) * turn;
	return parent_angle(entry, x, z, a);
}

double Ctx::parent_angle(const Entry &entry, double x, double z, double a) {
	if (!entry.mass_follow || entry.zones == nullptr) {
		return a;
	}
	return entry.zones->zone_flow(x, z) + a;
}

double Ctx::off_bare(const std::vector<BareRecord> &bare, double keep, double x, double z, double u, double shade) {
	double bound = keep * shade;
	if (u >= bound) {
		return bound;
	}
	return keep * accents.bare_keep(bare, x, z);
}

void Ctx::append_scale(godot::PackedFloat32Array &rows, double scale, const Entry &entry, double edge_value) {
	double core = entry.mass_core;
	double core_y = entry.mass_core_y;
	if (!entry.mass || (core == 1.0 && core_y == 1.0)) {
		rows.push_back((float)scale);
		rows.push_back((float)scale);
		rows.push_back((float)scale);
		return;
	}
	double e = gclamp(edge_value, 0.0, 1.0);
	double dome = 1.0 - e * e;
	double width = scale * (1.0 + (core - 1.0) * dome);
	double height = scale * (1.0 + (core_y - 1.0) * dome);
	double cap = entry.mass_core_y_max;
	if (cap > 0.0) {
		height = gmin(height, gmax(cap, scale));
	}
	rows.push_back((float)width);
	rows.push_back((float)height);
	rows.push_back((float)width);
}

} // namespace ttscatter
