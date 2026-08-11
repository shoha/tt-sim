class_name DebugRenderToggles
extends Node

## Discoverable, clickable performance-diagnostic toggles shown alongside the F3
## PerformanceOverlay -- deliberately not raw hotkeys, replacing the old
## undiscoverable F4 foliage-visibility keycode outright. See
## docs/superpowers/specs/2026-08-10-performance-debug-toggles-design.md.
##
## The four visibility/shadow toggles reset to their default (current shipped
## behavior, pressed=on) on every map reload -- state is never persisted across a map
## switch. Foliage antialiasing used to be a fifth toggle here but is now a real,
## persisted graphics setting -- see VisualEffectsController.set_foliage_antialiasing_level()
## and docs/superpowers/specs/2026-08-10-foliage-antialiasing-setting-design.md.
##
## "Trivial foliage shader", "Unshaded foliage (full textures)", and "Cheap lighting
## foliage" are three further, differently-defaulted (pressed=off), mutually exclusive
## toggles that each swap every wind-foliage material to a debug shader:
## - Trivial: albedo texture only, unshaded, no ORM/normal sampling, no lighting.
##   If this alone recovers the framerate, the cost is somewhere in the real
##   shader's fragment stage generally (either texture traffic or lighting).
## - Unshaded (full textures): samples the exact same textures as the real shader
##   (albedo, ORM, optional normal) but still skips Godot's lighting pass. If this
##   ALSO recovers the framerate, the cost is the lighting/BRDF evaluation, not the
##   texture reads; if it stays slow like the real shader, the cost is the texture
##   reads themselves.
## Both of the above confirmed the cost is the lighting/BRDF evaluation (Godot's
## diffuse_burley + specular_schlick_ggx), not texture bandwidth -- see an M1 Xcode/
## Instruments GPU capture, which also showed the fragment stage dominating by ~10x
## any other stage.
## - Cheap lighting: a candidate real fix, not another isolation shader -- identical
##   PBR texture sampling, wind sway, and occlusion fade to the real shader, but
##   diffuse_lambert + specular_disabled instead of diffuse_burley +
##   specular_schlick_ggx. Exists as a toggle rather than the shipped default so the
##   visual difference can be judged in-game before committing to it.
## See WindFoliage.get_shader_debug_trivial()/get_shader_debug_unshaded()/
## get_shader_debug_cheap_lighting() and shaders/wind_foliage_debug_trivial.gdshader /
## wind_foliage_debug_unshaded.gdshader / wind_foliage_debug_cheap_lighting.gdshader.

## Checkbox keys for the mutually-exclusive foliage debug shader toggles, in panel
## order. Used to uncheck the other two whenever one is turned on, and to identify
## which checkboxes refresh() should default to unpressed (unlike the four
## visibility/shadow toggles above, which default pressed=on).
const _DEBUG_SHADER_CHECKBOX_KEYS := [
	"trivial_foliage_shader",
	"unshaded_foliage_textured",
	"cheap_lighting_foliage",
]

var _foliage_visible: bool = true
var _tree_shadows: bool = true
var _grass_shadows: bool = true
var _map_shadows: bool = true

## Which foliage debug shader (if any) is currently swapped in: "", "trivial",
## "unshaded", or "cheap_lighting". A String rather than independent bools because the
## debug shaders are mutually exclusive -- a material can only have one shader at a time.
var _foliage_debug_shader: String = ""

var _map_container: Node3D = null

var _tree_multimeshes: Array[MultiMeshInstance3D] = []
var _grass_multimeshes: Array[MultiMeshInstance3D] = []
var _map_meshes: Array[MeshInstance3D] = []

## Shaders each foliage ShaderMaterial had before being swapped to a debug shader, so
## restoring (toggling both off) puts back exactly what was active (which may itself
## be either the antialiased or plain-cutout variant, depending on the player's
## Antialiasing setting) rather than assuming which one to restore to.
var _original_foliage_shaders: Dictionary = {}  # ShaderMaterial -> Shader

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
		"toggle_trivial_foliage_shader": _foliage_debug_shader == "trivial",
		"toggle_unshaded_foliage_textured": _foliage_debug_shader == "unshaded",
		"toggle_cheap_lighting_foliage": _foliage_debug_shader == "cheap_lighting",
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
	# Not restored via _original_foliage_shaders: the previous map's materials are
	# already queue_freed by the time this runs (see this function's own docstring),
	# so there is nothing left to restore -- just drop the stale references.
	_foliage_debug_shader = ""
	_original_foliage_shaders.clear()
	for key in _checkboxes:
		_checkboxes[key].set_pressed_no_signal(key not in _DEBUG_SHADER_CHECKBOX_KEYS)


func _collect_nodes() -> void:
	if not _map_container:
		return
	_collect_multimeshes_by_category(_map_container, "tree", _tree_multimeshes)
	_collect_multimeshes_by_category(_map_container, "grass", _grass_multimeshes)
	_collect_mesh_instances(_map_container, _map_meshes)


func _create_panel(overlay_parent: GameMap) -> void:
	var labels: PackedStringArray = [
		"Foliage visible",
		"Tree shadows",
		"Grass shadows",
		"Map shadows",
		"Trivial foliage shader",
		"Unshaded foliage (full textures)",
		"Cheap lighting foliage",
	]
	var result: Dictionary = MapOverlayUtils.create_checkbox_panel(labels)
	_panel = result.panel
	var checkboxes: Array[CheckBox] = result.checkboxes
	_checkboxes = {
		"foliage_visible": checkboxes[0],
		"tree_shadows": checkboxes[1],
		"grass_shadows": checkboxes[2],
		"map_shadows": checkboxes[3],
		"trivial_foliage_shader": checkboxes[4],
		"unshaded_foliage_textured": checkboxes[5],
		"cheap_lighting_foliage": checkboxes[6],
	}
	# Stacked below PerformanceOverlay's metrics panel inside GameMap's shared perf
	# overlay VBoxContainer (see GameMap.get_perf_overlay_container()) -- the container
	# flows both panels automatically, so no hardcoded Y offset to keep in sync here.
	overlay_parent.get_perf_overlay_container().add_child(_panel)

	_checkboxes["foliage_visible"].toggled.connect(_on_foliage_visible_toggled)
	_checkboxes["tree_shadows"].toggled.connect(_on_tree_shadows_toggled)
	_checkboxes["grass_shadows"].toggled.connect(_on_grass_shadows_toggled)
	_checkboxes["map_shadows"].toggled.connect(_on_map_shadows_toggled)
	_checkboxes["trivial_foliage_shader"].toggled.connect(_on_trivial_foliage_shader_toggled)
	_checkboxes["unshaded_foliage_textured"].toggled.connect(_on_unshaded_foliage_textured_toggled)
	_checkboxes["cheap_lighting_foliage"].toggled.connect(_on_cheap_lighting_foliage_toggled)


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


func _on_trivial_foliage_shader_toggled(pressed: bool) -> void:
	if pressed:
		_uncheck_other_debug_shader_checkboxes("trivial_foliage_shader")
		_set_foliage_debug_shader("trivial")
	elif _foliage_debug_shader == "trivial":
		_set_foliage_debug_shader("")


func _on_unshaded_foliage_textured_toggled(pressed: bool) -> void:
	if pressed:
		_uncheck_other_debug_shader_checkboxes("unshaded_foliage_textured")
		_set_foliage_debug_shader("unshaded")
	elif _foliage_debug_shader == "unshaded":
		_set_foliage_debug_shader("")


func _on_cheap_lighting_foliage_toggled(pressed: bool) -> void:
	if pressed:
		_uncheck_other_debug_shader_checkboxes("cheap_lighting_foliage")
		_set_foliage_debug_shader("cheap_lighting")
	elif _foliage_debug_shader == "cheap_lighting":
		_set_foliage_debug_shader("")


## Uncheck every _DEBUG_SHADER_CHECKBOX_KEYS entry except [param except_key], keeping
## the panel's visual state in sync with the mutual-exclusion enforced by
## _set_foliage_debug_shader. Checked against the dict via has() (not indexed
## directly) so tests that invoke a toggle handler on a bare instance -- with no
## panel/checkboxes ever created -- don't hit a null dereference. Uses
## set_pressed_no_signal so unchecking a checkbox here never re-enters that
## checkbox's own toggled handler.
func _uncheck_other_debug_shader_checkboxes(except_key: String) -> void:
	for key in _DEBUG_SHADER_CHECKBOX_KEYS:
		if key != except_key and _checkboxes.has(key):
			_checkboxes[key].set_pressed_no_signal(false)


## Swap every wind-foliage material (tree and grass) to [param mode]'s debug shader
## ("trivial", "unshaded", or "cheap_lighting"), or restore each to whatever shader it
## had before when [param mode] is "" (see _original_foliage_shaders' docstring). Uses
## WindFoliage.collect_foliage_shader_materials rather than this class's own cached
## _tree_multimeshes/_grass_multimeshes so it also reaches materials currently hidden
## by the "Foliage visible" toggle above. No-op if [param mode] is already active.
## Switching directly between debug modes (without passing through "") is safe:
## _original_foliage_shaders is only populated when a material doesn't already have an
## entry, so a mid-switch material's debug shader is never mistaken for its real
## original.
func _set_foliage_debug_shader(mode: String) -> void:
	if mode == _foliage_debug_shader:
		return
	var materials := WindFoliage.collect_foliage_shader_materials(_map_container)
	if mode == "":
		for mat in materials:
			if is_instance_valid(mat) and _original_foliage_shaders.has(mat):
				mat.shader = _original_foliage_shaders[mat]
		_original_foliage_shaders.clear()
	else:
		var debug_shader := _get_debug_shader_for_mode(mode)
		for mat in materials:
			if not _original_foliage_shaders.has(mat):
				_original_foliage_shaders[mat] = mat.shader
			mat.shader = debug_shader
	_foliage_debug_shader = mode


static func _get_debug_shader_for_mode(mode: String) -> Shader:
	match mode:
		"trivial":
			return WindFoliage.get_shader_debug_trivial()
		"unshaded":
			return WindFoliage.get_shader_debug_unshaded()
		"cheap_lighting":
			return WindFoliage.get_shader_debug_cheap_lighting()
	return null


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
