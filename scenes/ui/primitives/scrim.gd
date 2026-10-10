class_name Scrim
extends ColorRect

## The one stop-play scrim (docs/UI_TASTE.md C4) behind every paper sheet: settings, the
## new-map dialog, confirmations, pause, the pickers and the avatar builder. It blurs what
## is behind it and lays ThemeColors.SCRIM (#2B2140 at 0.30) over the blur
## (shaders/ui_scrim.gdshader), so the sky and the table step back without going dark.
##
## A scene's full-rect ColorRect takes this script; the node keeps its name, its mouse
## filter and its modulate fade. Every scrim shares one material. Scrims join GROUP, so a
## screen under a sheet can tell one is up (the title's Host steps down from its persimmon
## fill while a sheet holds the screen's one primary, C5).

const GROUP := &"ui_scrim"
const SHADER := preload("res://shaders/ui_scrim.gdshader")

static var _shared: ShaderMaterial


func _init() -> void:
	add_to_group(GROUP)
	material = shared_material()


## The material every scrim draws with, its tint read from ThemeColors.SCRIM.
static func shared_material() -> ShaderMaterial:
	if _shared == null:
		_shared = ShaderMaterial.new()
		_shared.shader = SHADER
		_shared.set_shader_parameter(&"tint", ThemeColors.SCRIM)
	return _shared


## Whether any scrim in `tree` is shown.
static func any_shown(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			return true
	return false
