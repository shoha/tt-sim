class_name ScatterClumps
extends RefCounted

## Clump parents for ScatterGenerator (moved out of it in ground ship card 4b): which parents of
## a clumped species are kept and which of them reach a child bucket (ScatterGenerator._membership
## and ScatterMass.membership turn them into the child's membership).
## Everything reads and writes only the generator's per-call context (its ctx Dictionary: the
## plan, fields and memos), so worker threads share nothing.
##
## Gathering. A child tests the kept parents whose reach overlaps its bucket. A grass mass's
## swathes reach several metres over parent buckets a fraction of that across, so scanning the
## parent buckets around each child bucket meant hundreds of memo lookups per child bucket, more
## than the rest of a savanna grass candidate's work. Such children are gathered per tile of
## TILE_M instead: the tile lists its kept parents once, in the order the per-bucket scan visits
## them (parent rows, then columns, then bucket order), and each child bucket filters that list
## by its own bucket span and reach test, which yields the same parents in the same order. A clump
## reaching fewer than TILE_MIN_BUCKETS parent buckets keeps the cheaper scan. A species whose
## parents take near relations keeps the scan too: deciding such a parent evaluates other
## species, and those nested evaluations write ctx.edge and ctx.anchor, so they must happen
## exactly where they always have.

## Kept parent record: x, z, radius, long-axis angle (radians), and the angle's cosine and sine,
## found once per parent rather than once per child that tests it (ScatterMass.membership with
## this stride; ground-opt-cpu).
const PARENT_STRIDE := 6
## Listed parent record: the kept parent record, then its parent bucket's column and row.
const _LISTED_STRIDE := PARENT_STRIDE + 2
## The side of a gathering tile, in metres (a whole number of child buckets, at least one).
const TILE_M := 4.0
## A child bucket whose reach spans fewer parent buckets than this scans them directly.
const TILE_MIN_BUCKETS := 16


## Kept clump parents whose reach overlaps one children bucket, as kept parent records
## (memoized per bucket, so each child checks only the few that matter).
static func parents_near_bucket(
	ctx: Dictionary, s: int, bi: int, bj: int
) -> PackedFloat64Array:
	var memo: Dictionary = ctx.parent_lists[s]
	var key := _key(bi, bj)
	var cached: Variant = memo.get(key)
	if cached != null:
		return cached
	var entry: Dictionary = ctx.plan.species[s]
	var clump: Dictionary = entry.rule.clump
	var child_size: float = ctx.fields[entry.field].bucket
	var rect := Rect2(bi * child_size, bj * child_size, child_size, child_size)
	var size: float = ctx.fields[entry.parent_field].bucket
	var transition: float = clump.transition_m
	var root := sqrt(float(entry.mass_stretch))  # an ellipse's long half-axis
	var reach: float = (clump.radius_m * (1.0 + entry.clump_jitter) + transition) * root
	var span := _span(rect, reach, size)
	var out := PackedFloat64Array()
	var left: float = rect.position.x
	var right: float = rect.end.x
	var near_z: float = rect.position.y
	var far_z: float = rect.end.y
	# Parents sit in their own, larger buckets; a child bucket gathers the few whose reach
	# overlaps it, so each child tests two or three parents, not a neighbourhood.
	var buckets := (span[1] - span[0] + 1) * (span[3] - span[2] + 1)
	if buckets < TILE_MIN_BUCKETS or not entry.near.is_empty():
		# The scan reads kept_parents' memo itself (the call only on a miss), a column's key one
		# _BUCKET_SPAN past its left neighbour's: the lookups are most of a scan's work, and every
		# clumped species of every biome scans (ground-opt-cpu).
		var kept_memo: Dictionary = ctx.parent_buckets[s]
		for parent_j in range(span[2], span[3] + 1):
			var bucket_key := _key(span[0], parent_j)
			for parent_i in range(span[0], span[1] + 1):
				var known: Variant = kept_memo.get(bucket_key)
				bucket_key += ScatterGenerator._BUCKET_SPAN
				var kept: PackedFloat64Array = (
					known if known != null else kept_parents(ctx, s, parent_i, parent_j)
				)
				for c in range(0, kept.size(), PARENT_STRIDE):
					var px := kept[c]
					var pz := kept[c + 1]
					var radius := kept[c + 2]
					var dx := maxf(0.0, maxf(left - px, px - right))
					var dz := maxf(0.0, maxf(near_z - pz, pz - far_z))
					var parent_reach := (radius + transition) * root
					if dx * dx + dz * dz > parent_reach * parent_reach:
						continue
					out.append(px)
					out.append(pz)
					out.append(radius)
					out.append(kept[c + 3])
					out.append(kept[c + 4])
					out.append(kept[c + 5])
		memo[key] = out
		return out
	var listed := _tile(ctx, s, bi, bj, reach)
	var first_i := span[0]
	var last_i := span[1]
	var first_j := span[2]
	var last_j := span[3]
	for c in range(0, listed.size(), _LISTED_STRIDE):
		var parent_i := int(listed[c + PARENT_STRIDE])
		var parent_j := int(listed[c + PARENT_STRIDE + 1])
		if parent_i < first_i or parent_i > last_i or parent_j < first_j or parent_j > last_j:
			continue
		var px := listed[c]
		var pz := listed[c + 1]
		var radius := listed[c + 2]
		var dx := maxf(0.0, maxf(left - px, px - right))
		var dz := maxf(0.0, maxf(near_z - pz, pz - far_z))
		var parent_reach := (radius + transition) * root
		if dx * dx + dz * dz > parent_reach * parent_reach:
			continue
		out.append(px)
		out.append(pz)
		out.append(radius)
		out.append(listed[c + 3])
		out.append(listed[c + 4])
		out.append(listed[c + 5])
	memo[key] = out
	return out


## The kept parents of one parent bucket as kept parent records (memoized per bucket; the angle
## is a mass's long axis, ScatterMass.parent_spin).
static func kept_parents(ctx: Dictionary, s: int, bi: int, bj: int) -> PackedFloat64Array:
	var memo: Dictionary = ctx.parent_buckets[s]
	var key := _key(bi, bj)
	var cached: Variant = memo.get(key)
	if cached != null:
		return cached
	var entry: Dictionary = ctx.plan.species[s]
	var radius: float = entry.rule.clump.radius_m
	var mass: bool = entry.mass
	var cands := ScatterGenerator._bucket(ctx.fields[entry.parent_field], bi, bj)
	var out := PackedFloat64Array()
	for c in range(0, cands.size(), ScatterGenerator._STRIDE):
		if _parent_kept(ctx, s, cands, c):
			var h := int(cands[c + 5])
			var jitter := 2.0 * ScatterGenerator._unit(h, ScatterGenerator._SALT_RADIUS) - 1.0
			out.append(cands[c])
			out.append(cands[c + 1])
			out.append(radius * (1.0 + entry.clump_jitter * jitter))
			var angle := 0.0  # parent_spin's angle for a rule that is not a mass
			if mass:
				var turn := 2.0 * ScatterGenerator._unit(h, ScatterGenerator._SALT_ANGLE) - 1.0
				angle = ScatterMass.parent_spin(entry, cands[c], cands[c + 1], turn)
			out.append(angle)
			out.append(cos(angle))
			out.append(sin(angle))
	memo[key] = out
	return out


## A clump parent survives its spacing and the species' near relations (Geoscatter's
## affinity acts on clump parents: a clump whose parent is near its target survives whole).
static func _parent_kept(ctx: Dictionary, s: int, cands: PackedFloat64Array, c: int) -> bool:
	var memo: Dictionary = ctx.parents[s]
	var id := int(cands[c + 4])
	var known: Variant = memo.get(id)
	if known != null:
		return known
	var entry: Dictionary = ctx.plan.species[s]
	var kept := ScatterGenerator._spaced_survives(ctx.fields[entry.parent_field], cands, c)
	if kept and not entry.near.is_empty():
		var keep := 1.0
		for relation in entry.near:
			var near := ScatterGenerator._proximity(ctx, relation, cands[c], cands[c + 1])
			keep *= 1.0 - relation.influence * (1.0 - near)
		kept = ScatterGenerator._unit(int(cands[c + 5]), ScatterGenerator._SALT_ACCEPT) < keep
	# A mass's swathes, by zone (any other rule's zone record is empty: always kept).
	kept = kept and (not entry.mass or ScatterMass.zone_kept(entry, cands, c))
	memo[id] = kept
	return kept


## The parent buckets a child rectangle's reach overlaps: [first column, last column, first row,
## last row].
static func _span(rect: Rect2, reach: float, size: float) -> PackedInt32Array:
	return PackedInt32Array(
		[
			floori((rect.position.x - reach) / size),
			floori((rect.end.x + reach) / size),
			floori((rect.position.y - reach) / size),
			floori((rect.end.y + reach) / size),
		]
	)


## The kept parents of every parent bucket in `span`, rows then columns, as listed records.
static func _listed(ctx: Dictionary, s: int, span: PackedInt32Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for parent_j in range(span[2], span[3] + 1):
		for parent_i in range(span[0], span[1] + 1):
			var kept := kept_parents(ctx, s, parent_i, parent_j)
			for c in range(0, kept.size(), PARENT_STRIDE):
				out.append_array(kept.slice(c, c + PARENT_STRIDE))
				out.append(parent_i)
				out.append(parent_j)
	return out


## The listed parents of the tile holding child bucket (bi, bj) (memoized per tile): every parent
## bucket the reach of any child bucket of the tile overlaps, from the span of its first child
## bucket to that of its last (spans only grow with the bucket index).
static func _tile(ctx: Dictionary, s: int, bi: int, bj: int, reach: float) -> PackedFloat64Array:
	var entry: Dictionary = ctx.plan.species[s]
	var child_size: float = ctx.fields[entry.field].bucket
	var per := maxi(1, floori(TILE_M / child_size))
	var ti := floori(float(bi) / per)
	var tj := floori(float(bj) / per)
	var memo: Dictionary = ctx.parent_tiles[s]
	var key := _key(ti, tj)
	var cached: Variant = memo.get(key)
	if cached != null:
		return cached
	var size: float = ctx.fields[entry.parent_field].bucket
	var first_i := ti * per
	var first_j := tj * per
	var last_i := first_i + per - 1
	var last_j := first_j + per - 1
	var size_v := Vector2(child_size, child_size)
	var first := _span(Rect2(Vector2(first_i * child_size, first_j * child_size), size_v), reach, size)
	var last := _span(Rect2(Vector2(last_i * child_size, last_j * child_size), size_v), reach, size)
	var out := _listed(ctx, s, PackedInt32Array([first[0], last[1], first[2], last[3]]))
	memo[key] = out
	return out


static func _key(bi: int, bj: int) -> int:
	return (
		(bi + ScatterGenerator._BUCKET_OFFSET) * ScatterGenerator._BUCKET_SPAN
		+ (bj + ScatterGenerator._BUCKET_OFFSET)
	)
