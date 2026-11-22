extends GutTest
## The derive's stage table (docs/systems/terraform.md "The stage chain"): the order of the stages,
## and that every declared halo is honest.
##
## Order: each stage reads only inputs or arrays an earlier stage wrote, and every array has one
## writer. Halo honesty: one sample of a built map is set outside the chain, then every stage
## downstream of it re-runs over the whole map. Each array may change only within the reach the
## table declares for it (the sum of the halos along the way from the set array), and an
## incremental derive that grows the one sample by the declared halos gives the same bytes, so the
## halos are both wide enough and the ones the loop uses.

## Graph stages read at exact points: anything downstream of one has no sample bound.
const UNBOUNDED := 1 << 30


func _derive() -> RefCounted:
	var n := TerraCorpus.build().make_derive()
	n.call("derive_full")
	return n


func _sample_arrays(n: RefCounted) -> Dictionary:
	var out := {}
	for a: Dictionary in n.call("arrays"):
		if a["kind"] == "samples":
			out[a["name"]] = a["bytes"]
	return out


func _snapshot(n: RefCounted, names: Dictionary) -> Dictionary:
	var out := {}
	for name: String in names:
		out[name] = n.call("array_bytes", name)
	return out


## The declared reach of every array from a change in `from` (samples; UNBOUNDED past a graph
## stage); arrays the change cannot reach are absent.
func _reach(stages: Array, from: String) -> Dictionary:
	var reach := {from: 0}
	for s: Dictionary in stages:
		var r := -1
		for name: String in s["reads"]:
			if reach.has(name):
				r = maxi(r, reach[name])
		if r < 0:
			continue
		var halo: int = s["halo"]
		var w: int = UNBOUNDED if halo < 0 or r >= UNBOUNDED else r + halo
		for name: String in s["writes"]:
			reach[name] = maxi(reach.get(name, 0), w)
	return reach


## The largest Chebyshev distance from (ci, cj) of a sample where a and b differ, or -1.
func _spread(a: PackedByteArray, b: PackedByteArray, bytes: int, w: int, ci: int, cj: int) -> int:
	if a == b:
		return -1
	var row := w * bytes
	var far := -1
	for j in a.size() / row:
		var o := j * row
		if a.slice(o, o + row) == b.slice(o, o + row):
			continue
		for i in w:
			var p := o + i * bytes
			if a.slice(p, p + bytes) != b.slice(p, p + bytes):
				far = maxi(far, maxi(absi(i - ci), absi(j - cj)))
	return far


## Sets `name` at (i, j) to `value` on two built maps, one marking the whole array changed and one
## only the sample, derives both, and checks every array against the declared reach.
func _check_honest(name: String, i: int, j: int, value: float) -> void:
	var full := _derive()
	var inc := _derive()
	var names := _sample_arrays(full)
	var before := _snapshot(full, names)
	var w: int = full.call("grid")["w"]
	var reach := _reach(full.call("stages"), name)
	full.call("debug_set_sample", name, i, j, value, true)
	full.call("derive")
	inc.call("debug_set_sample", name, i, j, value, false)
	inc.call("derive")
	var after_full := _snapshot(full, names)
	var after_inc := _snapshot(inc, names)
	var moved := 0
	for a: String in names:
		var spread := _spread(before[a], after_full[a], names[a], w, i, j)
		if a == name:
			continue
		if not reach.has(a):
			assert_eq(spread, -1, "%s from %s: unreachable, unchanged" % [a, name])
			continue
		if spread >= 0:
			moved += 1
		assert_lte(spread, int(reach[a]), "%s changes within its declared reach from %s" % [a, name])
		assert_true(after_inc[a] == after_full[a], "%s: the incremental derive equals the full one" % a)
	assert_gt(moved, 0, "setting %s moved something downstream" % name)


func test_each_read_is_an_input_or_written_earlier() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var n: RefCounted = ClassDB.instantiate(TerraCore.CLASS_NAME)
	var kinds := {}
	for a: Dictionary in n.call("arrays"):
		kinds[a["name"]] = a["kind"]
	var written := {}
	var stages: Array = n.call("stages")
	assert_eq(stages.size(), 11, "eleven stages")
	for s: Dictionary in stages:
		for r: String in s["reads"]:
			assert_true(kinds.has(r), "%s reads a known array %s" % [s["name"], r])
			var ok: bool = kinds.get(r) == "input" or written.has(r)
			assert_true(ok, "%s reads %s, an input or an earlier stage's write" % [s["name"], r])
		for wr: String in s["writes"]:
			assert_ne(kinds.get(wr), "input", "%s writes no input" % s["name"])
			assert_false(written.has(wr), "%s is written once (%s)" % [wr, s["name"]])
			written[wr] = s["name"]
		var graph: bool = s["shape"] == "graph"
		assert_eq(int(s["halo"]) < 0, graph, "%s: only a graph stage has no sample halo" % s["name"])
	for name: String in kinds:
		if kinds[name] != "input":
			assert_true(written.has(name), "%s has a writer" % name)


func test_halos_from_the_ground() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var g: Dictionary = _derive().call("grid")
	var i: int = g["w"] / 2
	var j: int = g["h"] / 3
	var h2: PackedByteArray = _derive().call("array_bytes", "H2")
	_check_honest("H2", i, j, h2.decode_float((j * int(g["w"]) + i) * 4) + 1.0)


func test_halos_from_a_footprint() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var g: Dictionary = _derive().call("grid")
	_check_honest("FM", int(g["w"]) / 4, int(g["h"]) / 4, 255.0)
