extends GutTest

## The procgen submodule (procgen/, shared with plantgen) inside this project: its own
## self-check (a graph built in code evaluates, repeats exactly, and builds the same mesh on
## worker threads) and the pinned sample digest, so this project and plantgen agree on the mesh.


func test_the_module_passes_its_self_check_in_this_project() -> void:
	var pinned := ProcgenSelfCheck.pinned_digest()
	assert_ne(pinned, "", "procgen/tests/expected_digest.txt is present (submodule initialised)")
	assert_eq(ProcgenSelfCheck.run(pinned), PackedStringArray(), "no self-check failures")


func test_the_module_adds_no_global_class_clash() -> void:
	# A duplicate class_name would stop either script from loading; resolving the names proves
	# both projects' classes coexist.
	for cls_name: String in [
		"PlantGraphDocument", "PlantGraphEvaluator", "ProcgenRegistry", "ProcgenOutputNode"
	]:
		var found := false
		for entry: Dictionary in ProjectSettings.get_global_class_list():
			if entry["class"] == cls_name:
				found = true
		assert_true(found, "%s is a registered global class" % cls_name)
