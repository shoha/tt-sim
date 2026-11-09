class_name OnDemand
extends RefCounted

## Parts of the game the start-up does not compile (perf audit boot, 2026-11-09).
##
## GDScript compiles every script a script names (a class_name anywhere in its code, type hints
## included, or a preload) before that script can run, and the autoloads name, through each other,
## about 800 of the project's 1065 scripts: compiling them is nearly all of the time before the
## first frame (docs/plans/handoffs/boot.md). A script that only a rarely opened screen needs is
## loaded here by path on first use instead, so it and everything only it names leave the
## start-up. The calls into it are dynamic (no static type check), so each part keeps one entry
## point and its callers name its class in a comment. tools/boot_graph.gd shows what a cut saves
## and what the start-up still compiles.

## The biome designer (BiomeDesignerHost and its session, model and screen: 38 scripts).
const BIOME_DESIGNER_HOST := "res://scenes/states/authoring/designer/biome_designer_host.gd"
## The collections manager (LibraryManager and its rows, detail and sections: 7 scripts).
const LIBRARY_MANAGER := "res://scenes/ui/library_manager/library_manager.gd"


## BiomeDesignerHost.attach(): puts the biome designer into the open authoring session and
## returns the host node, already in the tree.
static func attach_biome_designer(authoring: Node, game_map: Node, config: Dictionary) -> Node:
	var host_script: Variant = load(BIOME_DESIGNER_HOST)
	return host_script.attach(authoring, game_map, config)


## LibraryManager.open(): opens the collections manager over `parent` and returns it.
static func open_library_manager(parent: Node) -> Node:
	var manager_script: Variant = load(LIBRARY_MANAGER)
	return manager_script.open(parent)
