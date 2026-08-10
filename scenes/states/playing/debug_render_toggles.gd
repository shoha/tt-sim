class_name DebugRenderToggles
extends Node

## Discoverable, clickable performance-diagnostic toggles shown alongside the F3
## PerformanceOverlay -- deliberately not raw hotkeys, replacing the old
## undiscoverable F4 foliage-visibility keycode outright. See
## docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
##
## All four toggles reset to their default (current shipped behavior) on every map
## reload -- state is never persisted across a map switch. Foliage antialiasing used
## to be a fifth toggle here but is now a real, persisted graphics setting -- see
## VisualEffectsController.set_foliage_antialiasing_level() and
## docs/superpowers/specs/2026-08-10-foliage-antialiasing-setting-design.md.

var _foliage_visible: bool = true
var _tree_shadows: bool = true
var _grass_shadows: bool = true
var _map_shadows: bool = true

var _map_container: Node3D = null

var _tree_multimeshes: Array[MultiMeshInstance3D] = []
var _grass_multimeshes: Array[MultiMeshInstance3D] = []
var _map_meshes: Array[MeshInstance3D] = []

var _canvas_layer: CanvasLayer
var _panel: PanelContainer
var _checkboxes: Dictionary = {}  # String -> CheckBox


## Current state of every toggle, keyed by the exact CSV column name
## PerformanceLogFormatter uses for each -- PerformanceOverlay reads this directly
## when writing a log row.
func get_toggle_states() -> Dictionary:
	return {
		"toggle_foliage_visible": _foliage_visible,
		"toggle_tree_shadows": _tree_shadows,
		"toggle_grass_shadows": _grass_shadows,
		"toggle_map_shadows": _map_shadows,
	}


func setup(game_map: GameMap) -> void:
	_map_container = game_map.map_container
	_create_panel(game_map)
	refresh()


func set_panel_visible(should_be_visible: bool) -> void:
	if _panel:
		_panel.visible = should_be_visible


## Re-collect node references against the currently loaded map and reset every
## toggle to its default (on) state. Called once from setup() and again from
## GameMap.notify_map_loaded() whenever a new map finishes loading -- map_container's
## previous children have been queue_freed and, because map loading awaits across a
## frame, are out of the tree by then, and no toggle persists across a map switch
## (design spec, "Toggles (v1)"). Without this, the cached node lists from the first
## map would go stale (pointing at freed nodes) and the newly loaded map's foliage
## would never be collected at all.
func refresh() -> void:
	_tree_multimeshes.clear()
	_grass_multimeshes.clear()
	_map_meshes.clear()
	_collect_nodes()
	_foliage_visible = true
	_tree_shadows = true
	_grass_shadows = true
	_map_shadows = true
	for key in _checkboxes:
		_checkboxes[key].set_pressed_no_signal(true)


func _collect_nodes() -> void:
	if not _map_container:
		return
	_collect_multimeshes_by_category(_map_container, "tree", _tree_multimeshes)
	_collect_multimeshes_by_category(_map_container, "grass", _grass_multimeshes)
	_collect_mesh_instances(_map_container, _map_meshes)


func _create_panel(overlay_parent: Node) -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = Constants.LAYER_PERF_OVERLAY
	overlay_parent.add_child(_canvas_layer)

	var labels: PackedStringArray = [
		"Foliage visible",
		"Tree shadows",
		"Grass shadows",
		"Map shadows",
	]
	var result: Dictionary = MapOverlayUtils.create_checkbox_panel(labels)
	_panel = result.panel
	var checkboxes: Array[CheckBox] = result.checkboxes
	_checkboxes = {
		"foliage_visible": checkboxes[0],
		"tree_shadows": checkboxes[1],
		"grass_shadows": checkboxes[2],
		"map_shadows": checkboxes[3],
	}
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Positioned below PerformanceOverlay's metrics panel (which starts at y=16).
	# The metrics panel gained an "Antialiasing" line in this change -- re-verify via
	# manual smoke test (F3 in a live level) that y=320 still clears it, and adjust
	# again if not.
	_panel.position = Vector2(16, 320)
	_canvas_layer.add_child(_panel)

	_checkboxes["foliage_visible"].toggled.connect(_on_foliage_visible_toggled)
	_checkboxes["tree_shadows"].toggled.connect(_on_tree_shadows_toggled)
	_checkboxes["grass_shadows"].toggled.connect(_on_grass_shadows_toggled)
	_checkboxes["map_shadows"].toggled.connect(_on_map_shadows_toggled)


func _on_foliage_visible_toggled(pressed: bool) -> void:
	_foliage_visible = pressed
	for mm_inst in _tree_multimeshes:
		if is_instance_valid(mm_inst):
			mm_inst.visible = pressed
	for mm_inst in _grass_multimeshes:
		if is_instance_valid(mm_inst):
			mm_inst.visible = pressed


func _on_tree_shadows_toggled(pressed: bool) -> void:
	_tree_shadows = pressed
	_apply_shadow_setting(_tree_multimeshes, pressed)


func _on_grass_shadows_toggled(pressed: bool) -> void:
	_grass_shadows = pressed
	_apply_shadow_setting(_grass_multimeshes, pressed)


func _on_map_shadows_toggled(pressed: bool) -> void:
	_map_shadows = pressed
	_apply_shadow_setting(_map_meshes, pressed)


## Recursively collect visible MultiMeshInstance3D nodes tagged with the given
## wind_foliage_category (set by GlbUtils._build_multimesh_from_transforms, see
## WindFoliage.classify_category). Mirrors
## OcclusionFadeManager._collect_tree_multimeshes, generalized to any category since
## tree and grass shadows are toggled independently here.
static func _collect_multimeshes_by_category(
	node: Node, category: String, result: Array[MultiMeshInstance3D]
) -> void:
	for child in node.get_children():
		if (
			child is MultiMeshInstance3D
			and child.visible
			and child.get_meta("wind_foliage_category", "") == category
		):
			result.append(child as MultiMeshInstance3D)
		_collect_multimeshes_by_category(child, category, result)


## Recursively collect all visible MeshInstance3D nodes with geometry -- mirrors
## OcclusionFadeManager._collect_mesh_instances. Foliage is MultiMeshInstance3D, a
## different node type, so it is never included here.
static func _collect_mesh_instances(node: Node, result: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.visible:
			var mesh_inst := child as MeshInstance3D
			if mesh_inst.mesh:
				result.append(mesh_inst)
		_collect_mesh_instances(child, result)


## Set cast_shadow on every node in [param nodes] (MeshInstance3D or
## MultiMeshInstance3D, both GeometryInstance3D subclasses).
static func _apply_shadow_setting(nodes: Array, should_cast: bool) -> void:
	var setting := (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if should_cast
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for node in nodes:
		if is_instance_valid(node):
			node.cast_shadow = setting
