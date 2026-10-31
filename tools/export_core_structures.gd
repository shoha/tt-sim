extends SceneTree

## Headless: writes (or with `--check 1` checks) the `structures/` kind of the core library.
##
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/export_core_structures.gd -- \
##       --out D:/dev/tabletop/core-library [--check 1]
##
## This file only starts the work. A `--script` main script is compiled before the autoloads exist,
## so anything it names that names an autoload (StructureGeometry reaches `Wind` through its
## dependencies) fails to compile and runs with its static initialisers skipped (`textured` read
## false: nine houses and yard_gate pinned at other digests). The implementation is loaded here,
## in _initialize, when the autoloads are in the tree; it holds the documentation of the tool
## (tools/export_core_structures_run.gd).


func _initialize() -> void:
	var run: GDScript = load("res://tools/export_core_structures_run.gd")
	run.new().run(self)
