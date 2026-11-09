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
## The biome designer's way in from the title: the picker (BiomeDesignerPicker) and the draft it
## prepares (BiomeDesignerEntry).
const BIOME_DESIGNER_PICKER := "res://scenes/ui/biome_designer/designer_picker.gd"
const BIOME_DESIGNER_ENTRY := "res://scenes/states/authoring/designer/biome_designer_entry.gd"
## The new-map dialog (NewMapDialog) and the first-launch graphics warm-up (GraphicsWarmupScreen).
const NEW_MAP_DIALOG := "res://scenes/states/authoring/new_map_dialog.tscn"
const GRAPHICS_WARMUP_SCREEN := "res://scenes/states/warmup/graphics_warmup_screen.tscn"


## BiomeDesignerHost.attach(): puts the biome designer into the open authoring session and
## returns the host node, already in the tree.
static func attach_biome_designer(authoring: Node, game_map: Node, config: Dictionary) -> Node:
	var host_script: Variant = load(BIOME_DESIGNER_HOST)
	return host_script.attach(authoring, game_map, config)


## LibraryManager.open(): opens the collections manager over `parent` and returns it.
static func open_library_manager(parent: Node) -> Node:
	var manager_script: Variant = load(LIBRARY_MANAGER)
	return manager_script.open(parent)


## BiomeDesignerPicker.show_over(): the picker of the biome to design, over `parent`.
static func show_biome_designer_picker(parent: Node) -> void:
	var picker: Variant = load(BIOME_DESIGNER_PICKER)
	picker.show_over(parent)


## BiomeDesignerEntry.prepare(): {"ok", "error", "request"} for designing `biome_id` of
## `library_id` (the draft compiled and laid over the palette).
static func prepare_biome_designer(library_id: String, biome_id: String) -> Dictionary:
	var entry: Variant = load(BIOME_DESIGNER_ENTRY)
	return entry.prepare(library_id, biome_id)


## A new NewMapDialog with `preset` (the New map card's size and seed); `on_chosen` gets its
## map_chosen spec. Not yet in the tree.
static func new_map_dialog(preset: Dictionary, on_chosen: Callable) -> Node:
	var dialog: Variant = (load(NEW_MAP_DIALOG) as PackedScene).instantiate()
	dialog.preset = preset
	dialog.map_chosen.connect(on_chosen)
	return dialog


## A new GraphicsWarmupScreen; `on_finished` runs once when it is done. Not yet in the tree.
static func graphics_warmup_screen(on_finished: Callable) -> Node:
	var screen: Variant = (load(GRAPHICS_WARMUP_SCREEN) as PackedScene).instantiate()
	screen.finished.connect(on_finished, CONNECT_ONE_SHOT)
	return screen
