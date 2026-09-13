class_name FoliageBudget
extends RefCounted

## Fixed global cap on how many scattered-foliage primitives an imported map may render,
## with the arithmetic for thinning one that exceeds it. Pure statics only -- no node
## access and no side effects, so the whole allocator is unit-testable without a scene
## tree or a renderer. Applied by ScatterGlbUtils.process_scatter_instances().
##
## Why a cap is needed at all: a MultiMeshInstance3D is frustum-culled as a SINGLE AABB,
## and foliage is built as one MultiMesh per species spanning the whole map. If any part
## of a species is on screen, every one of its instances is vertex-processed. Measured on
## a dense forest map, visible-pass primitives read an identical 19,361,510 at every
## camera pose tried, and panning changed nothing. Total instance count per map -- not
## density per unit area, and not what happens to be in frame -- is the cost driver.
## See docs/PERFORMANCE.md for the full attribution.

## Maximum total foliage primitives (triangles) across all scatter species in one map.
##
## PROVISIONAL. Derived from one scene on one GPU: on a dense forest map an RTX 3080
## spent ~11 ms of a 14.5 ms frame on 16.3M foliage primitives (the in-game debug toggle's
## definition of "foliage", which excludes rock scatter), and hiding foliage entirely took
## the frame to 3.5 ms. The real total this budget actually caps -- foliage plus rock
## scatter -- measured 19.17M primitives on that same map, so 8M is 41.7% of the real
## load, not "roughly half" as earlier estimated from the narrower toggle figure. This
## needs validating on slower hardware before release -- the mechanism is the deliverable,
## the threshold is a tunable. Deliberately NOT overridable per level: a budget a map can
## opt out of does not bound anything.
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


## Which `keep` of `count` instances survive, as ascending indices.
##
## Seeded shuffle then truncate, rather than a suffix drop or a fixed stride. Scatter
## transform arrays come out of the authoring tool in brush-stroke or row order, so
## dropping the tail would carve a bald patch out of the map and a fixed stride could
## beat against a planted grid into visible stripes. A shuffle is unbiased with respect
## to whatever ordering the exporter happened to use.
##
## Deterministic by construction: the seed comes only from `seed_source` (the species
## name), never from time or engine RNG state, so a map thins identically on every load
## and on every machine -- which a host and its clients both depend on.
##
## WARNING: changing the seeding or the shuffle here changes which instances survive in
## every map that already exists. So does a Godot engine upgrade that changes
## RandomNumberGenerator's own behavior (documented as PCG32, but with no cross-version
## compatibility guarantee) -- it has exactly the same effect as a deliberate edit to this
## function. test_pins_the_current_selection_algorithm's golden index arrays are what
## catch either case; a failure there after an engine bump means the engine changed, not
## that you broke something.
static func select_indices(count: int, keep: int, seed_source: String) -> PackedInt32Array:
	if count <= 0 or keep <= 0:
		return PackedInt32Array()
	var order := PackedInt32Array()
	order.resize(count)
	for i in count:
		order[i] = i
	if keep >= count:
		return order
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_hash(seed_source)
	# Partial Fisher-Yates: only the first `keep` slots need to be settled.
	for i in keep:
		var j := rng.randi_range(i, count - 1)
		var swapped := order[i]
		order[i] = order[j]
		order[j] = swapped
	var picked := order.slice(0, keep)
	# Ascending so the surviving instances keep their original relative order.
	picked.sort()
	return picked


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
## while the grass reduction is essentially imperceptible.
##
## `budget` is a parameter only so tests can drive thinning at counts a test can build;
## production always takes the PRIMITIVE_BUDGET default. Nothing user-facing sets it, and
## nothing should: the budget is fixed by design.
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
		# ScatterGlbUtils._build_multimesh_from_transforms for what a zero allocation would
		# do to a caller. Costs at most one instance per species against the cap; the
		# mini(..., count) clamp keeps that floor-to-1 from inventing an instance for a
		# species that has none.
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
## is unit-testable; ScatterGlbUtils stashes the report and a scenes/ script shows it,
## because nothing in utils/ may reference an autoload.
static func describe(report: Dictionary) -> String:
	var before: int = report.get("instances_before", 0)
	var after: int = report.get("instances_after", 0)
	return (
		"This map's foliage was thinned for performance: %s of %s scattered instances kept."
		% [_with_thousands_separators(after), _with_thousands_separators(before)]
	)


## 1234567 -> "1,234,567". String.num_int64() has no grouping option and %d does not group.
static func _with_thousands_separators(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""
	for offset in digits.length():
		if offset > 0 and offset % 3 == 0:
			grouped = "," + grouped
		grouped = digits[digits.length() - 1 - offset] + grouped
	return "-" + grouped if value < 0 else grouped
