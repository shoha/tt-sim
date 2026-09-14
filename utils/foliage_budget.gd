class_name FoliageBudget
extends RefCounted

## Arithmetic for how many scattered-foliage primitives a map keeps under a budget, and how
## an over-budget species gets thinned proportionally. Pure statics only -- no node access
## and no side effects, so the whole allocator is unit-testable without a scene tree or a
## renderer. Applied at runtime by FoliageDensityController.apply() (see
## scenes/states/playing/foliage_density_controller.gd) against a full, unthinned instance
## set that ScatterGlbUtils.process_scatter_instances() builds at import.
##
## Why a cap is needed at all: a MultiMeshInstance3D is frustum-culled as a SINGLE AABB,
## and foliage is built as one MultiMesh per species spanning the whole map. If any part
## of a species is on screen, every one of its instances is vertex-processed. Measured on
## a dense forest map, visible-pass primitives read an identical 19,361,510 at every
## camera pose tried, and panning changed nothing. Total instance count per map -- not
## density per unit area, and not what happens to be in frame -- is the cost driver.
## Superseded by spatial chunking (ScatterChunker, see docs/PERFORMANCE.md's "Spatial
## foliage chunking" section): true for every map before chunking landed, now only the
## worst case, reached at full zoom-out. The budget itself is unaffected -- it still
## bounds total instance count, which chunking does not change.
## See docs/PERFORMANCE.md for the full attribution.

## Default total foliage primitives (triangles) across all scatter species in one map, for
## the per-user `graphics/foliage_budget` setting stored in `user://settings.cfg`. Applied
## at runtime by FoliageDensityController (see
## scenes/states/playing/foliage_density_controller.gd) via MultiMesh.visible_instance_count
## -- not enforced at import. ScatterGlbUtils.process_scatter_instances() now builds every
## instance, and the player's Settings > Graphics slider (2,000,000 to 24,000,000) dials how
## many of them are visible, live, with no map reload.
##
## Derived from one scene on one GPU: on a dense forest map an RTX 3080 spent ~11 ms of a
## 14.5 ms frame on 16.3M foliage primitives (the in-game debug toggle's definition of
## "foliage", which excludes rock scatter), and hiding foliage entirely took the frame to
## 3.5 ms. The real total this budget actually caps -- foliage plus rock scatter --
## measured 19.17M primitives on that same map, so 8M is 41.7% of the real load, not
## "roughly half" as earlier estimated from the narrower toggle figure. Whether this default
## suits hardware weaker than the RTX 3080 it was measured on is resolved not by further
## validation here but by the setting itself -- each player raises or lowers it in Settings
## > Graphics to fit their own machine. Still deliberately NOT overridable per level: a map
## cannot opt out of the cap, only the player's own setting moves it, the same way for every
## map.
const PRIMITIVE_BUDGET: int = 8_000_000

# FNV-1a 32-bit parameters. GDScript ints are 64-bit, so every step masks back to 32.
const _FNV_OFFSET_BASIS: int = 0x811c9dc5
const _FNV_PRIME: int = 16777619
const _UINT32_MASK: int = 0xffffffff


## Triangles in one instance of `mesh`, summed over its triangle surfaces.
##
## Two paths because the cheap one does not exist on every Mesh: surface_get_array_*()
## and surface_get_primitive_type() are ArrayMesh methods, and calling them on a
## PrimitiveMesh fails outright. Imported glTF meshes are ArrayMesh, where reading the
## index length avoids copying any vertex data; BoxMesh and friends fall back to
## get_faces(), which materialises the whole face array but only ever runs on small
## fixtures. A mesh whose primitive count cannot be determined counts as 0 and is
## therefore never thinned -- an unknown mesh type must not cause silent content loss.
static func primitives_per_instance(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return mesh.get_faces().size() / 3
	var total := 0
	for surface in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var index_length := array_mesh.surface_get_array_index_len(surface)
		if index_length > 0:
			total += index_length / 3
		else:
			total += array_mesh.surface_get_array_len(surface) / 3
	return total


## A deterministic shuffled ordering of `count` instance indices.
##
## This IS the order instances are written into a chunk's MultiMesh, which makes any
## PREFIX of it a spatially even sample of that chunk -- the property
## MultiMesh.visible_instance_count depends on to act as a density dial. Ordering them by
## position instead would make a prefix carve a bald patch out of one side of the cell.
##
## Deterministic by construction: the seed comes only from `seed_source`, never from time
## or engine RNG state, so a map looks the same across loads on one machine and instances
## appear and disappear predictably as the density slider moves rather than reshuffling.
## Peers may differ in density, which is intended -- density is a per-user setting.
##
## WARNING: changing the seeding or the shuffle changes which instances a user sees at any
## density below 100%, in every map. A Godot RNG change on an engine upgrade has exactly
## the same effect as a deliberate edit here; test_shuffled_order_pins_the_current_algorithm
## is what catches either case.
static func shuffled_order(count: int, seed_source: String) -> PackedInt32Array:
	if count <= 0:
		return PackedInt32Array()
	var order := PackedInt32Array()
	order.resize(count)
	for i in count:
		order[i] = i
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_hash(seed_source)
	# Full Fisher-Yates: every slot is settled, because any prefix length may be drawn.
	for i in count - 1:
		var j := rng.randi_range(i, count - 1)
		var swapped := order[i]
		order[i] = order[j]
		order[j] = swapped
	return order


## FNV-1a over `text`'s UTF-8 bytes. Deliberately not Godot's built-in hash(): this value
## decides which instances survive in every imported map, so it has to stay identical
## across engine versions and platforms, and hash() is an engine implementation detail
## under no such guarantee.
static func _stable_hash(text: String) -> int:
	var hash_value := _FNV_OFFSET_BASIS
	for byte in text.to_utf8_buffer():
		hash_value = (hash_value ^ byte) & _UINT32_MASK
		hash_value = (hash_value * _FNV_PRIME) & _UINT32_MASK
	return hash_value


## Decides how many instances of each scatter species to keep.
##
## `species` maps a species name to {"count": int, "primitives_per_instance": int}.
## Returns {"kept": {name: int}, "thinned": bool, "total_before": int, "total_after": int,
## "instances_before": int, "instances_after": int}, where "kept" always names every
## species given, thinned or not.
##
## Allocation keeps an equal INSTANCE FRACTION per species -- not equal visual weight.
## Per-instance visual importance correlates with per-instance cost, so charging by
## primitives makes high-cost landmark species absorb the largest visible share of the
## loss. Measured on Sandy Clearing at this budget: 132 of 225 trees (59%) are removed
## while the grass reduction is essentially imperceptible. Weighting allocation by visual
## importance instead would need per-species authoring metadata that does not exist, so
## it was considered and rejected rather than overlooked -- see docs/PERFORMANCE.md.
##
## `budget` is a parameter so both tests and production callers can supply their own value.
## Production is FoliageDensityController.apply(), which reads the player's configured
## budget via FoliageDensityController.budget_from_settings() and falls back to
## PRIMITIVE_BUDGET only when no setting has been saved yet; the default parameter here
## exists so tests that don't care about the setting can omit it.
##
## A species with at least one instance always keeps at least one, even when its
## proportional share rounds down to zero. That is not a one-instance-per-species
## overshoot: the bound is in primitives, not instances -- it is the sum of
## primitives_per_instance over every species the floor rescues, and a single rescued
## instance can itself be tens of thousands of primitives.
static func plan(species: Dictionary, budget: int = PRIMITIVE_BUDGET) -> Dictionary:
	var kept := {}
	var total_before := 0
	var instances_before := 0
	for species_name in species.keys():
		var entry: Dictionary = species[species_name]
		var count: int = entry.get("count", 0)
		kept[species_name] = count
		instances_before += count
		total_before += count * int(entry.get("primitives_per_instance", 0))

	var report := {
		"kept": kept,
		"thinned": false,
		"total_before": total_before,
		"total_after": total_before,
		"instances_before": instances_before,
		"instances_after": instances_before,
	}
	if total_before <= budget or total_before <= 0:
		return report

	var ratio := float(budget) / float(total_before)
	var total_after := 0
	var instances_after := 0
	for species_name in species.keys():
		var entry: Dictionary = species[species_name]
		var count: int = entry.get("count", 0)
		var per_instance: int = entry.get("primitives_per_instance", 0)
		if per_instance <= 0:
			# Cost unknown, so thinning buys nothing measurable. Keep all of it.
			instances_after += count
			continue
		# plan()'s own contract: never allocate zero to a species that has instances -- see
		# ScatterGlbUtils.process_scatter_instances for what a zero allocation would do to
		# a caller (an empty kept_transforms means bucket_by_cell returns no occupied
		# cells, so no MultiMesh is built at all and the species vanishes). Costs at most
		# one instance per species against the cap; the mini(..., count) clamp keeps that
		# floor-to-1 from inventing an instance for a species that has none.
		var allowed := mini(maxi(int(floor(count * ratio)), 1), count)
		kept[species_name] = allowed
		total_after += allowed * per_instance
		instances_after += allowed

	# Every non-empty species floors to at least 1, so if every species' share already
	# floored to 1 anyway, nothing was actually removed. Equality with instances_before is
	# exactly that case -- allocations only ever decrease, never increase.
	report.thinned = instances_after < instances_before
	report.total_after = total_after
	report.instances_after = instances_after
	return report


## One-line explanation of a thinning, for the toast the player sees. Pure so the wording
## is unit-testable; FoliageDensityController.apply() returns the report and level_loader.gd
## shows it, because nothing in utils/ may reference an autoload.
##
## Present tense and names the setting, not the map, as the cause: this is a live dial the
## player can raise back up with no reload, not a one-time, irreversible thing done to the
## map, and the sentence level_loader.gd appends immediately tells the player to go change
## that setting -- past tense would contradict it. Expressed as a density percentage rather
## than raw instance counts, because the slider the player is being sent to is denominated
## in millions of triangles, and a percentage is the only one of the two units that relates
## to it at all.
static func describe(report: Dictionary) -> String:
	var before: int = report.get("instances_before", 0)
	var after: int = report.get("instances_after", 0)
	var percent := 100 if before <= 0 else int(round(100.0 * after / before))
	return "Foliage shown at %d%% -- this map exceeds your Foliage Density setting." % percent


## 1234567 -> "1,234,567". String.num_int64() has no grouping option and %d does not group.
static func _with_thousands_separators(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for offset in digits.length():
		if offset > 0 and offset % 3 == 0:
			grouped = "," + grouped
		grouped = digits[digits.length() - 1 - offset] + grouped
	return "-" + grouped if value < 0 else grouped


## Splits a species' allocation across its chunks, proportionally to each chunk's size.
##
## `chunk_counts` maps a chunk key to how many instances that chunk holds; `kept` is what
## FoliageBudget.plan() allocated the species; `total` is the species' full instance count.
## Returns the same keys mapped to how many instances each chunk should draw. Keys may be
## any hashable value: this function only ever hashes and returns them, never dereferences
## them, so it stays pure regardless of what a caller uses -- the production caller
## (FoliageDensityController.apply()) keys by the MultiMeshInstance3D node itself, while the
## tests key by Vector2i.
##
## Post-condition: sum(visible.values()) == min(kept, total) exactly, every value is clamped
## between 0 and its own chunk's count, and no value is negative.
##
## Uses largest-remainder (Hamilton) apportionment rather than rounding each chunk
## independently. Independent rounding is the obvious approach here, and it is broken: the
## sum of independently rounded shares is not `kept`, and the error scales with the NUMBER
## of chunks, not with rounding noise. Two failure modes that motivated this rewrite, both on
## real maps: a species spread across many small chunks can round every chunk down to zero
## and vanish entirely even though `kept` was positive (round(3 * 0.09) = 0 on 24 chunks of
## 3), and a species spread across many single-instance chunks can round every chunk up to 1
## and double the allocation, blowing the budget the user set (round(1 * 0.5) = 1 on 100
## chunks of 1). It also silently defeated plan()'s floor-of-one guarantee for any species
## occupying more than two cells.
##
## Hamilton apportionment: give each chunk floor(exact share) clamped to its own count, then
## hand out the shortfall between that sum and the target one instance at a time to the
## chunks with the largest fractional remainders, skipping any chunk already at its ceiling.
## Remainders are computed by iterating chunk_counts in its own insertion order (GDScript
## Dictionaries preserve insertion order, and _collect() inserts in scene-tree order, which
## is stable across loads on one machine) and ties are broken by that same order, so which
## instances appear and disappear as the density slider moves is deterministic rather than
## reshuffling.
static func visible_counts_for_chunks(
	chunk_counts: Dictionary, kept: int, total: int
) -> Dictionary:
	var visible := {}
	if total <= 0:
		for key in chunk_counts.keys():
			visible[key] = 0
		return visible

	var target := clampi(kept, 0, total)
	var assigned := 0
	var remainders: Array[Dictionary] = []
	var insertion_index := 0
	for key in chunk_counts.keys():
		var count: int = chunk_counts[key]
		var exact_share := float(count) * float(target) / float(total)
		var floor_share := clampi(int(floor(exact_share)), 0, count)
		visible[key] = floor_share
		assigned += floor_share
		(
			remainders
			. append(
				{
					"key": key,
					"count": count,
					"remainder": exact_share - floor(exact_share),
					"insertion_index": insertion_index,
				}
			)
		)
		insertion_index += 1

	var shortfall := target - assigned
	if shortfall > 0:
		remainders.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				if a["remainder"] != b["remainder"]:
					return a["remainder"] > b["remainder"]
				# Equal remainders: fall back to insertion order so ties are deterministic
				# regardless of whether sort_custom's underlying sort is stable.
				return a["insertion_index"] < b["insertion_index"]
		)
		for entry in remainders:
			if shortfall <= 0:
				break
			var key = entry["key"]
			var count: int = entry["count"]
			if visible[key] < count:
				visible[key] += 1
				shortfall -= 1
	return visible
