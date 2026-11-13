extends GutTest
## The painted trees' generator and species table (painter/trees/, docs/systems/painter.md
## "Trees"): every core tree asset maps as the table says, a row's species, age, openness and
## seed are pure in the row, the port grows the spike's own trees bit for bit, and a golden digest
## per species, seed and age guards the masses against unintended change.

const SPIKE := "res://tests/fixtures/painter_tree_spike.json"
## The golden digests. Delete the file and run this script to write it again (deliberately: a
## generator change that moves the trees).
const GOLDEN := "res://tests/fixtures/painter_tree_digests.json"
const CORE_LIBRARY := "res://libraries/core/library.json"
const SEEDS: Array[int] = [11, 90210]
const AGES: Array[float] = [0.3, 0.6, 0.9]
## Packed values are snapped to this before hashing (a tenth of a millimetre; the mass layout's
## flags, counts and seeds are whole numbers), so a last-bit float difference does not move it.
const SNAP := 1e-4


func _grow(species: String, age: float, openness: float, seed_v: int) -> Dictionary:
	var masses := PainterTreeGrowth.tree(
		PainterTreeSpecies.architecture(species),
		{"age": age, "openness": openness},
		seed_v,
		PainterTreeSpecies.is_conifer(species)
	)
	return PainterTreePack.pack(masses, seed_v, 3.0, PainterTreeSpecies.wide())


static func _snapped_digest(d: Dictionary) -> String:
	var data: PackedFloat32Array = d["data"]
	var snapped := PackedFloat32Array()
	snapped.resize(data.size())
	for i in data.size():
		snapped[i] = snappedf(data[i], SNAP)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(snapped.to_byte_array())
	var counts := PackedInt32Array(
		[d["texels"], d["n_ell"], d["n_seg"], d["n_slots"], d["n_shadow"], d["n_seg_painted"]]
	)
	ctx.update(counts.to_byte_array())
	return ctx.finish().hex_encode()


func test_every_core_tree_asset_maps_as_the_table_says() -> void:
	var text := FileAccess.get_file_as_string(CORE_LIBRARY)
	# (The ids show in the library's thumbnail paths, assets/thumbs/<id>.png.)
	var found := RegEx.create_from_string("thumbs/(Tree_[A-Za-z0-9_]+)\\.png")
	var ids := {}
	for m in found.search_all(text):
		ids[m.get_string(1)] = true
	assert_gt(ids.size(), 40, "the core library's tree ids")
	var want := {
		"Tree_Oak": "oak",
		"Tree_Birch": "birch",
		"Tree_Broadleaf": "lime",
		"Tree_Poplar": "poplar",
		"Tree_Spruce": "spruce",
		"Tree_Pine": "spruce",
		"Tree_Willow": "willow",
		"Tree_Sapling": "rowan",
	}
	var glb := ["Tree_Acacia", "Tree_Cactus", "Tree_Palm", "Tree_DeadTree"]
	for id: String in ids:
		var group := "_".join(id.split("_").slice(0, 2))
		var got := PainterTreeSpecies.species_for(id)
		if want.has(group):
			assert_eq(got, want[group], id)
			assert_true(PainterTreeSpecies.names().has(got), id + ": species has data")
		else:
			assert_true(glb.has(group), id + ": a group the table should know")
			assert_eq(got, "", id + " stays GLB")


func test_a_rows_age_openness_and_seed_are_pure_in_the_row() -> void:
	var p := Vector3(12.5, 0.75, -3.0009765625)
	var key := PainterTreeSpecies.key_of(p)
	assert_eq(key, Vector3i(1250, 75, -300))
	assert_eq(PainterTreeSpecies.seed_of(key), PainterTreeSpecies.seed_of(Vector3i(1250, 75, -300)))
	assert_ne(PainterTreeSpecies.seed_of(key), PainterTreeSpecies.seed_of(key + Vector3i(1, 0, 0)))
	assert_almost_eq(PainterTreeSpecies.age_of("Tree_Oak_v0", 1.0), 0.6, 1e-6)
	assert_almost_eq(PainterTreeSpecies.age_of("Tree_Oak_v0", 3.0), 0.95, 1e-6, "clamped")
	assert_lt(PainterTreeSpecies.age_of("Tree_Sapling_v1_savanna", 1.0), 0.45, "saplings young")
	var open_a := PainterTreeSpecies.openness_at(p, 0.8)
	assert_eq(PainterTreeSpecies.openness_at(p, 0.8), open_a, "the same point, the same openness")
	assert_lt(open_a, PainterTreeSpecies.openness_at(p, 0.0), "a dense biome grows closed trees")
	for x in 40:
		var o := PainterTreeSpecies.openness_at(Vector3(x * 3.7, 0.0, x * -2.3), 0.5)
		assert_between(o, 0.1, 0.9)


func test_the_port_grows_the_spikes_own_trees() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPIKE))
	var trees: Dictionary = fixture["trees"]
	assert_eq(trees.size(), 24, "eight species at three ages")
	for label: String in trees:
		var parts := label.rsplit("_", true, 1)
		var d := _grow(parts[0], float(parts[1]), fixture["openness"], int(fixture["seed"]))
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update((d["data"] as PackedFloat32Array).to_byte_array())
		assert_eq(int(d["texels"]), int(trees[label]["texels"]), label + " texels")
		assert_eq(ctx.finish().hex_encode(), str(trees[label]["sha"]), label + " bytes")


func test_golden_digests_per_species_seed_and_age() -> void:
	var got := {}
	for species in PainterTreeSpecies.names():
		for seed_v in SEEDS:
			for age in AGES:
				var d := _grow(species, age, 0.4, seed_v)
				got["%s %d %.1f" % [species, seed_v, age]] = _snapped_digest(d)
	if not FileAccess.file_exists(GOLDEN):
		var f := FileAccess.open(GOLDEN, FileAccess.WRITE)
		f.store_string(JSON.stringify(got, "\t", true) + "\n")
		f.close()
		fail_test("golden digests written to %s: check them in and run again" % GOLDEN)
		return
	var want: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	assert_eq(got.size(), want.size(), "cases")
	for label: String in want:
		assert_eq(got.get(label, ""), want[label], label)


func test_growing_on_a_worker_thread_gives_the_same_tree() -> void:
	PainterTreeSpecies.architecture("oak")
	var here := _snapped_digest(_grow("oak", 0.6, 0.5, 77))
	var out := []
	out.resize(1)
	var task := WorkerThreadPool.add_task(
		func() -> void: out[0] = _snapped_digest(_grow("oak", 0.6, 0.5, 77))
	)
	WorkerThreadPool.wait_for_task_completion(task)
	assert_eq(out[0], here)
