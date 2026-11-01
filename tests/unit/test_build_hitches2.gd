extends GutTest

## Build hitches, round 2 (topic hitches2, docs/PERFORMANCE.md "Build hitches, round 2"): the
## take-back's per-sample walk reads and writes bytes in place instead of building arrays per
## sample, and must give exactly the bytes the array version gave. The reference below is that
## version (SettlementUnpaint before hitches2, over SurfaceEntries.read_sample and write_sample),
## run on the same random samples.

const CHANNELS := MapDocument.SURFACE_CHANNELS
const ENTRIES := MapDocument.SURFACE_ENTRIES
const SAMPLES := 4000


## The array version of SettlementUnpaint._unpaint_sample (hitches round 1), on bare planes.
static func _reference_sample(
	planes: PackedByteArray,
	laid_planes: PackedByteArray,
	real_of: PackedInt32Array,
	i: int,
	count: int
) -> void:
	var laid := SurfaceEntries.read_sample(laid_planes, i, count)
	var laid_index: PackedInt32Array = laid[0]
	if laid_index.is_empty():
		return
	var laid_weight: PackedInt32Array = laid[1]
	var current := SurfaceEntries.read_sample(planes, i, count)
	var index: PackedInt32Array = current[0]
	var weight: PackedInt32Array = current[1]
	var owed := 0
	for k in laid_index.size():
		if real_of[laid_index[k]] >= 0:
			owed += laid_weight[k]
	var before_total := 0
	var removed := 0
	var laid_before := 0
	var laid_after := 0
	var mine := PackedInt32Array()
	for e in index.size():
		before_total += weight[e]
		var found := -1
		for k in laid_index.size():
			if real_of[laid_index[k]] == index[e]:
				found = k
		if found < 0:
			continue
		var left := maxi(weight[e] - laid_weight[found], 0)
		removed += weight[e] - left
		laid_before += weight[e]
		laid_after += left
		weight[e] = left
		mine.append(e)
	if removed == 0:
		return
	var others := before_total - laid_before
	var slack := SettlementUnpaint.FULL_SLACK
	if removed >= owed - slack and others > 0 and before_total >= 255 - slack:
		var room := 255 - laid_after
		var factor := float(room) / float(maxi(255 - laid_before, 1))
		var total := 0
		var largest := -1
		for e in weight.size():
			if mine.has(e):
				continue
			weight[e] = mini(roundi(weight[e] * factor), room)
			total += weight[e]
			if largest < 0 or weight[e] > weight[largest]:
				largest = e
		if total > room and largest >= 0:
			weight[largest] -= total - room
	SurfaceEntries.write_sample(planes, i, count, index, weight)


func test_warmup_runs_once_per_map_and_fills_the_material_cache() -> void:
	StructureRecipes.ensure_served()
	var map := Node3D.new()
	add_child_autofree(map)
	var structures := AuthoredStructures.of_map(map)
	var styles := PackedStringArray(["temperate_forest_summer_s1"])
	var root := PaletteLibrary.DEFAULT_ROOT
	var first := StructureWarmup.warm(structures, styles, root)
	assert_not_null(first, "the first open starts it")
	assert_eq(StructureWarmup.warm(structures, styles, root), first, "one at a time")
	for frame in StructureWarmup.COMBOS.size() + 6:
		await get_tree().process_frame
	assert_false(is_instance_valid(first), "it frees itself when done")
	assert_null(StructureWarmup.warm(structures, styles, root), "never again on this map")
	assert_eq(structures.get_node_or_null(StructureWarmup.NODE_NAME), null)
	var key := "masonry:%s:%s" % [StructureLook.WALL, styles[0]]
	assert_true(structures._materials.has(key), "an install takes the warmed material")
	var made: Material = structures._materials[key]
	var again := structures.shared_material("masonry", StructureLook.WALL, styles[0])
	assert_eq(again, made, "the same object")


func test_held_ground_updates_once_and_leaves_the_same_bytes() -> void:
	var map := Node3D.new()
	add_child_autofree(map)
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	map.add_child(AuthoredTerrain.create(doc))
	var editor := AuthoringEditor.create(doc, map, AuthoringHistory.new())
	var other := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var diffs: Array[Dictionary] = []
	for at in [Vector2(-6, 0), Vector2(5, 2), Vector2(0, -4)]:
		var stroke := SurfaceStroke.begin(other, "cobblestone", false)
		stroke.dab(at, at + Vector2(3, 1), 2.0, 2.0)
		diffs.append(stroke.finish())
	var updates := editor.ground_updates
	editor.hold_ground()
	editor.hold_ground()
	for diff in diffs:
		editor.apply_surface_diff(diff, true)
	assert_eq(editor.release_ground(), Rect2i(), "an inner release waits for the outer")
	assert_eq(editor.ground_updates, updates, "nothing updated while held")
	var rect := editor.release_ground()
	assert_eq(editor.ground_updates, updates + 1, "one update for three diffs")
	for diff in diffs:
		assert_true(rect.encloses(diff.rect), "the update covers every diff")
	assert_eq(doc.surface_weights, other.surface_weights, "the bytes as painted")
	assert_eq(doc.surface_ids, other.surface_ids)
	editor.apply_surface_diff(diffs[0], false)
	assert_eq(editor.ground_updates, updates + 2, "unheld, each diff updates at once")


## Up to ENTRIES distinct slots below `slots` with weights summing to at most 255 (exactly 255 when
## `full`), written into sample `i`, canonical (high to low) unless `shuffled`.
func _fill(
	rng: RandomNumberGenerator,
	planes: PackedByteArray,
	i: int,
	count: int,
	slots: int,
	full: bool,
	shuffled: bool
) -> void:
	var n := rng.randi_range(0, ENTRIES)
	var picked := PackedInt32Array()
	while picked.size() < n:
		var slot := rng.randi_range(0, slots - 1)
		if not picked.has(slot):
			picked.append(slot)
	var weights := PackedInt32Array()
	var left := 255
	for k in n:
		var w := rng.randi_range(1, maxi(left - (n - k - 1), 1)) if left > 0 else 0
		if full and k == n - 1:
			w = left
		weights.append(w)
		left -= w
	if shuffled:
		for e in n:
			planes[i * CHANNELS + e] = picked[e]
			planes[count * CHANNELS + i * CHANNELS + e] = weights[e]
	else:
		SurfaceEntries.write_sample(planes, i, count, picked, weights)


## A sample as a Dress leaves it: the dressing's slots at (about) what it laid, the rest of a full
## (sometimes nearly full) sample held by one or two of the author's slots.
func _dressed(
	rng: RandomNumberGenerator,
	planes: PackedByteArray,
	laid: PackedByteArray,
	real_of: PackedInt32Array,
	i: int,
	count: int
) -> void:
	var indices := PackedInt32Array()
	var weights := PackedInt32Array()
	var total := 0
	for e in ENTRIES:
		var lw := laid[count * CHANNELS + i * CHANNELS + e]
		var real := real_of[laid[i * CHANNELS + e]]
		if lw > 0 and real >= 0 and indices.size() < 2:
			var w := clampi(lw + rng.randi_range(-3, 3), 1, 255 - total)
			indices.append(real)
			weights.append(w)
			total += w
	var room := 255 - total - rng.randi_range(0, 6)
	for other in [2, 4]:
		if room <= 0 or indices.has(other):
			continue
		var w := room if other == 4 else rng.randi_range(1, room)
		indices.append(other)
		weights.append(w)
		room -= w
	SurfaceEntries.write_sample(planes, i, count, indices, weights)


func test_inline_walk_matches_the_array_version_byte_for_byte() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261031
	var count := SAMPLES
	var planes := PackedByteArray()
	planes.resize(count * CHANNELS * 2)
	var laid := PackedByteArray()
	laid.resize(count * CHANNELS * 2)
	var real_of := PackedInt32Array([3, -1, 0, 5, 1, 7])
	for i in count:
		_fill(rng, laid, i, count, 6, rng.randf() < 0.5, false)
		if rng.randf() < 0.5:
			_fill(rng, planes, i, count, 8, rng.randf() < 0.6, rng.randf() < 0.2)
		else:
			_dressed(rng, planes, laid, real_of, i, count)
	var original := planes.duplicate()
	var expected := planes.duplicate()
	var work := PackedInt32Array()
	work.resize(SettlementUnpaint.WORK_SIZE)
	for i in count:
		_reference_sample(expected, laid, real_of, i, count)
		SettlementUnpaint._unpaint_sample(planes, laid, real_of, i, count, work)
	var differing := 0
	var unpainted := 0
	var given_back := 0
	for i in count:
		var touched := false
		for e in CHANNELS:
			for p in 2:
				var at := p * count * CHANNELS + i * CHANNELS + e
				if planes[at] != expected[at]:
					differing += 1
				touched = touched or expected[at] != original[at]
		if touched:
			unpainted += 1
		# The author's slot 4 (never laid) grew: the room was given back.
		var now := SurfaceEntries.read_sample(expected, i, count)
		var then := SurfaceEntries.read_sample(original, i, count)
		var k_now := (now[0] as PackedInt32Array).find(4)
		var k_then := (then[0] as PackedInt32Array).find(4)
		if k_now >= 0 and k_then >= 0 and now[1][k_now] > then[1][k_then]:
			given_back += 1
	assert_eq(differing, 0, "every byte as the array version wrote it")
	assert_gt(unpainted, SAMPLES >> 2, "many samples were taken back")
	assert_gt(given_back, SAMPLES >> 5, "many full samples got their room back")
