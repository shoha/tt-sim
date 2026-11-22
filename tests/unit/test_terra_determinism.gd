extends GutTest
## Determinism of the derive (docs/systems/terraform.md): the same document gives the same bits on
## a second run of one instance, with every stage on the caller against eight worker threads, and
## in two instances deriving at the same time on their own threads.


func _full(threads: int) -> Dictionary:
	var n := TerraCorpus.build().make_derive()
	n.call("set_threads", threads)
	n.call("derive_full")
	return n.call("digests")


func test_two_runs_of_one_instance() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var n := TerraCorpus.build().make_derive()
	n.call("derive_full")
	var first: Dictionary = n.call("digests")
	n.call("derive_full")
	assert_eq(n.call("digests"), first, "a second full derive gives the same bits")
	n.call("derive")
	assert_eq(n.call("digests"), first, "a derive with nothing pending changes nothing")


func test_serial_against_eight_threads() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var serial := _full(0)
	assert_eq(_full(1), serial, "one worker beside the caller")
	assert_eq(_full(8), serial, "eight workers beside the caller")


func test_two_instances_at_once() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var a := TerraCorpus.build().make_derive()
	var b := TerraCorpus.build().make_derive()
	a.call("derive_async")
	b.call("derive_async")
	var done := 0
	var waited := 0
	while done < 2 and waited < 20000:
		OS.delay_usec(500)
		waited += 1
		done = int(not a.call("is_busy")) + int(not b.call("is_busy"))
	assert_false(a.call("take_result").is_empty(), "the first derive finished")
	assert_false(b.call("take_result").is_empty(), "the second derive finished")
	var da: Dictionary = a.call("digests")
	assert_eq(b.call("digests"), da, "two instances agree")
	assert_eq(_full(8), da, "and agree with a derive on the caller's thread")
