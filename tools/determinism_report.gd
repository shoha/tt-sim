extends SceneTree

## Cross-platform determinism report for the structure pipeline (card S9, the "Determinism"
## workflow .github/workflows/determinism.yml; docs/systems/structures.md "Determinism").
##
##   godot --headless --path <project> --script res://tools/determinism_report.gd
##
## This file only starts the work: the implementation (tools/determinism_report_run.gd, which holds
## the documentation of the report) is loaded in _initialize, when the autoloads are in the tree. A
## `--script` main script is compiled before them, and the game classes it names would fail to
## compile and run with their static initialisers skipped (see tools/export_core_structures.gd).


func _initialize() -> void:
	var run: GDScript = load("res://tools/determinism_report_run.gd")
	run.new().run(self)
