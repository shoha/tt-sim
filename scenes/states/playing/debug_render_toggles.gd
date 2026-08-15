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
##
## Surprise finding: "Cheap lighting" alone did NOT recover the framerate on the M1,
## even though "Unshaded (full textures)" -- with identical texture sampling -- did.
## The difference between those two is that unshaded skips Godot's ENTIRE lighting
## pipeline (direct BRDF, shadow-map sampling, and ambient/GI lookups), while cheap
## lighting only swaps the direct BRDF term and still pays for whatever else "shaded"
## costs. "Sun shadows" isolates one specific candidate within that gap: it flips the
## level's DirectionalLight3D's own shadow_enabled (found via _find_directional_light,
## since the sun light is a sibling of map_container under the world SubViewport, not
## a descendant of it) -- unlike "Tree/Grass/Map shadows" above, which control whether
## that geometry CASTS a shadow, this controls whether the light casts one at all
## (and therefore whether every lit fragment pays for a shadow-map lookup). If turning
## this off recovers the framerate with the real (unmodified) foliage shader, the cost
## is shadow-map sampling, not the BRDF math cheap lighting targeted.
##
## It was: disabling "Grass shadows" (grass no longer a shadow CASTER) only recovered
## 2-3 FPS, far short of disabling "Sun shadows" entirely -- ruling out caster instance
## count as the driver. project.godot has
## rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality=5
## (SHADOW_QUALITY_SOFT_ULTRA), the most expensive PCF filter setting, applied
## per-fragment to every shaded pixel regardless of which geometry it belongs to --
## consistent with both of the above results. "Hard sun shadows" tests this directly
## via RenderingServer.directional_soft_shadow_filter_set_quality(), swapping to
## SHADOW_QUALITY_HARD (no filtering) without touching the light's shadow_enabled or
## any material/shader. This is a global renderer setting, not tied to a specific
## node, so unlike the other toggles above it needs no map_container/world_viewport
## lookup -- just a direct RenderingServer call.

## Checkbox keys for the mutually-exclusive foliage debug shader toggles, in panel
## order. Used to uncheck the other two whenever one is turned on. A subset of
## _DEFAULT_OFF_CHECKBOX_KEYS below (that one also includes "hard_sun_shadows", which
## isn't part of this mutual-exclusion group).
const _DEBUG_SHADER_CHECKBOX_KEYS := [
	"trivial_foliage_shader",
	"unshaded_foliage_textured",
	"cheap_lighting_foliage",
]

## Checkbox keys refresh() should default to UNPRESSED (unlike the visibility/shadow
## toggles, which default pressed=on to match current shipped behavior). Derived from
## _DEBUG_SHADER_CHECKBOX_KEYS (all three of those toggles also default off) plus
## "hard_sun_shadows", which isn't part of that mutual-exclusion group but is also
## off-by-default.
const _DEFAULT_OFF_CHECKBOX_KEYS := _DEBUG_SHADER_CHECKBOX_KEYS + ["hard_sun_shadows"]

var _foliage_visible: bool = true
var _tree_shadows: bool = true
var _grass_shadows: bool = true
var _map_shadows: bool = true
var _sun_shadows: bool = true
var _hard_sun_shadows: bool = false

## Which foliage debug shader (if any) is currently swapped in: "", "trivial",
## "unshaded", or "cheap_lighting". A String rather than independent bools because the
## debug shaders are mutually exclusive -- a material can only have one shader at a time.
var _foliage_debug_shader: String = ""

var _map_container: Node3D = null
## Root to search for the level's DirectionalLight3D (see _sun_light) -- the sun light
## is a sibling of map_container under the world SubViewport, not a descendant of it,
## so it needs its own search root distinct from _map_container.
var _world_viewport: SubViewport = null

var _tree_multimeshes: Array[MultiMeshInstance3D] = []
var _grass_multimeshes: Array[MultiMeshInstance3D] = []
var _map_meshes: Array[MeshInstance3D] = []
## Every wind-foliage ShaderMaterial in the current map, cached once per map
## load (see _collect_nodes()) so _set_foliage_debug_shader() doesn't re-walk
## the whole map_container subtree on every debug-shader checkbox click.
## Deliberately NOT filtered by node visibility (see
## WindFoliage.collect_foliage_shader_materials()), unlike
## _tree_multimeshes/_grass_multimeshes above, so materials on foliage
## currently hidden by the "Foliage visible" toggle are still reachable.
var _foliage_shader_materials: Array[ShaderMaterial] = []
## The level's sun light, if any -- re-found on every refresh() since
## LevelEnvironmentManager may recreate it per map load. See "Sun shadows" in this
## class's docstring.
var _sun_light: DirectionalLight3D = null

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
		"toggle_sun_shadows": _sun_shadows,
		"toggle_hard_sun_shadows": _hard_sun_shadows,
		"toggle_trivial_foliage_shader": _foliage_debug_shader == "trivial",
		"toggle_unshaded_foliage_textured": _foliage_debug_shader == "unshaded",
		"toggle_cheap_lighting_foliage": _foliage_debug_shader == "cheap_lighting",
	}


func setup(game_map: GameMap) -> void:
	_map_container = game_map.map_container
	_world_viewport = game_map.world_viewport
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
	_sun_shadows = true
	# Global renderer setting, not tied to the previous map's nodes -- must be
	# explicitly restored here (unlike _original_foliage_shaders below) since it
	# doesn't get reset just because the map's scene tree was torn down. Reads the
	# player's persisted choice fresh via _get_configured_shadow_quality() rather than
	# a value snapshotted once at startup.
	_hard_sun_shadows = false
	RenderingServer.directional_soft_shadow_filter_set_quality(_get_configured_shadow_quality())
	# Not restored via _original_foliage_shaders: the previous map's materials are
	# already queue_freed by the time this runs (see this function's own docstring),
	# so there is nothing left to restore -- just drop the stale references.
	_foliage_debug_shader = ""
	_original_foliage_shaders.clear()
	for key in _checkboxes:
		_checkboxes[key].set_pressed_no_signal(key not in _DEFAULT_OFF_CHECKBOX_KEYS)


func _collect_nodes() -> void:
	if _world_viewport:
		_sun_light = _find_directional_light(_world_viewport)
	if not _map_container:
		return
	_collect_multimeshes_by_category(_map_container, "tree", _tree_multimeshes)
	_collect_multimeshes_by_category(_map_container, "grass", _grass_multimeshes)
	_collect_mesh_instances(_map_container, _map_meshes)
	_foliage_shader_materials = WindFoliage.collect_foliage_shader_materials(_map_container)


func _create_panel(overlay_parent: GameMap) -> void:
	var labels: PackedStringArray = [
		"Foliage visible",
		"Tree shadows",
		"Grass shadows",
		"Map shadows",
		"Sun shadows",
		"Hard sun shadows",
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
		"sun_shadows": checkboxes[4],
		"hard_sun_shadows": checkboxes[5],
		"trivial_foliage_shader": checkboxes[6],
		"unshaded_foliage_textured": checkboxes[7],
		"cheap_lighting_foliage": checkboxes[8],
	}
	# Stacked below PerformanceOverlay's metrics panel inside GameMap's shared perf
	# overlay VBoxContainer (see GameMap.get_perf_overlay_container()) -- the container
	# flows both panels automatically, so no hardcoded Y offset to keep in sync here.
	overlay_parent.get_perf_overlay_container().add_child(_panel)

	_checkboxes["foliage_visible"].toggled.connect(_on_foliage_visible_toggled)
	_checkboxes["tree_shadows"].toggled.connect(_on_tree_shadows_toggled)
	_checkboxes["grass_shadows"].toggled.connect(_on_grass_shadows_toggled)
	_checkboxes["map_shadows"].toggled.connect(_on_map_shadows_toggled)
	_checkboxes["sun_shadows"].toggled.connect(_on_sun_shadows_toggled)
	_checkboxes["hard_sun_shadows"].toggled.connect(_on_hard_sun_shadows_toggled)
	_checkboxes["trivial_foliage_shader"].toggled.connect(
		_on_debug_shader_checkbox_toggled.bind("trivial_foliage_shader", "trivial")
	)
	_checkboxes["unshaded_foliage_textured"].toggled.connect(
		_on_debug_shader_checkbox_toggled.bind("unshaded_foliage_textured", "unshaded")
	)
	_checkboxes["cheap_lighting_foliage"].toggled.connect(
		_on_debug_shader_checkbox_toggled.bind("cheap_lighting_foliage", "cheap_lighting")
	)


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


## Unlike the three _apply_shadow_setting-based toggles above (which control whether
## a given category of geometry CASTS a shadow), this controls whether the sun light
## casts one AT ALL -- and therefore whether every lit fragment anywhere on the map
## pays for a shadow-map lookup. See this class's own docstring for why this toggle
## exists.
func _on_sun_shadows_toggled(pressed: bool) -> void:
	_sun_shadows = pressed
	if is_instance_valid(_sun_light):
		_sun_light.shadow_enabled = pressed


## Global renderer setting, not tied to _sun_light or any material -- swaps between
## SHADOW_QUALITY_HARD (no PCF filtering) and _get_configured_shadow_quality() (the
## player's persisted Shadow Quality setting) to isolate filter-quality cost
## specifically, independent of "Sun shadows" above (which removes shadows entirely)
## or any foliage shader.
func _on_hard_sun_shadows_toggled(pressed: bool) -> void:
	_hard_sun_shadows = pressed
	var quality := (
		RenderingServer.SHADOW_QUALITY_HARD if pressed else _get_configured_shadow_quality()
	)
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)


## Read the player's persisted Shadow Quality choice (Settings > Graphics)
## from user://settings.cfg -- the same source SettingsMenu._load_settings()
## and apply_startup_graphics_settings() read from -- so "Hard sun shadows"
## and refresh() restore the player's actual setting instead of a value
## snapshotted once at startup, which would go stale the moment the player
## changes Shadow Quality mid-session. Falls back to SHADOW_QUALITY_SOFT_ULTRA,
## matching every other read site's fallback, when settings.cfg has no saved
## value yet.
static func _get_configured_shadow_quality() -> int:
	var config := ConfigFile.new()
	config.load(Paths.SETTINGS_PATH)
	return config.get_value("graphics", "shadow_quality", RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)


func _on_debug_shader_checkbox_toggled(pressed: bool, checkbox_key: String, mode: String) -> void:
	if pressed:
		_uncheck_other_debug_shader_checkboxes(checkbox_key)
		_set_foliage_debug_shader(mode)
	elif _foliage_debug_shader == mode:
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
## the cached _foliage_shader_materials list (populated once per map load in
## _collect_nodes()) rather than re-walking map_container on every debug-shader
## checkbox click, while still reaching materials currently hidden by the "Foliage
## visible" toggle above, since _foliage_shader_materials isn't visibility-filtered.
## No-op if [param mode] is already active. Switching directly between debug modes
## (without passing through "") is safe: _original_foliage_shaders is only populated
## when a material doesn't already have an entry, so a mid-switch material's debug
## shader is never mistaken for its real original.
func _set_foliage_debug_shader(mode: String) -> void:
	if mode == _foliage_debug_shader:
		return
	if mode == "":
		for mat in _foliage_shader_materials:
			if is_instance_valid(mat) and _original_foliage_shaders.has(mat):
				mat.shader = _original_foliage_shaders[mat]
		_original_foliage_shaders.clear()
	else:
		var debug_shader := _get_debug_shader_for_mode(mode)
		for mat in _foliage_shader_materials:
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


## Recursively find the first DirectionalLight3D under [param node] -- the level's sun
## light (LevelEnvironmentManager._sun_light), which lives as a sibling of
## map_container under the world SubViewport rather than inside map_container itself,
## so it needs its own search separate from the MultiMesh/MeshInstance3D collectors
## above. Returns the first match; a level is expected to have at most one sun light.
static func _find_directional_light(node: Node) -> DirectionalLight3D:
	for child in node.get_children():
		if child is DirectionalLight3D:
			return child as DirectionalLight3D
		var found := _find_directional_light(child)
		if found:
			return found
	return null


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
