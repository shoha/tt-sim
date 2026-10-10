extends GutHookScript

## GUT's post-run hook, named by every tests/.gutconfig*.json: deletes the test data root the
## run used. A GUT command-line run has its own (Paths.gut_data_root, user://_test_roots/
## gut_<process id>/), so no test writes the real user's levels, settings, asset cache or
## packs; this removes what the tests wrote there once the run is over. It deletes only the
## root the engine arguments name, never the one DATA_ROOT holds when the run ends.


func run() -> void:
	var root := Paths.gut_data_root(OS.get_cmdline_args(), OS.get_process_id())
	if root == "":
		return
	if not Paths.remove_test_data_root(root):
		gut.logger.error("Could not delete the GUT test data root %s" % root)
