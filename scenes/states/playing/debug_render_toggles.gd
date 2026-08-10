class_name DebugRenderToggles
extends Node

## Discoverable, clickable performance-diagnostic toggles shown alongside the F3
## PerformanceOverlay -- deliberately not raw hotkeys, replacing the old
## undiscoverable F4 foliage-visibility keycode outright. See
## docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
##
## This file covers node-collection helpers and toggle-state defaults only. The
## checkbox panel, signal wiring, and per-toggle apply logic are added in a later
## pass (see the design spec's Architecture section).
##
## All five toggles reset to their default (current shipped behavior) on every map
## reload -- state is never persisted across a map switch.

var _foliage_visible: bool = true
var _foliage_aa: bool = true
var _tree_shadows: bool = true
var _grass_shadows: bool = true
var _map_shadows: bool = true


## Current state of every toggle, keyed by the exact CSV column name
## PerformanceLogFormatter uses for each -- PerformanceOverlay reads this directly
## when writing a log row.
func get_toggle_states() -> Dictionary:
	return {
		"toggle_foliage_visible": _foliage_visible,
		"toggle_foliage_aa": _foliage_aa,
		"toggle_tree_shadows": _tree_shadows,
		"toggle_grass_shadows": _grass_shadows,
		"toggle_map_shadows": _map_shadows,
	}


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


## Collect every ShaderMaterial used by a foliage MultiMeshInstance3D's surfaces
## (built by WindFoliage.apply_material at map-load time).
static func _collect_foliage_materials(
	mm_inst: MultiMeshInstance3D, result: Array[ShaderMaterial]
) -> void:
	if not mm_inst.multimesh or not mm_inst.multimesh.mesh:
		return
	var mesh := mm_inst.multimesh.mesh
	for surface_idx in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(surface_idx)
		if mat is ShaderMaterial and mat not in result:
			result.append(mat as ShaderMaterial)


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
