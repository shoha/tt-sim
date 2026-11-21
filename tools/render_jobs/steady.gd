extends RefCounted

## Repeatable captures for driver.gd: the wind frozen and the waits that end on a condition
## instead of a time (REFERENCE.md "State and maps": `wind`, `settle`). Two runs of a job
## with a seeded placement (`place_seed`), the wind frozen and `settle` in place of `wait`
## draw the same pixels, so an A/B of two packages differs only where the packages do.
##
## Wind sway reads the shader clock (TIME) times each material's sway, flutter and gust
## speeds; with those at 0 the plants hold still at their rest offsets, whatever the clock.
## The painted trees (painter/shaders/painter_tree.gdshaderinc) have no speeds: their motion is
## TIME times the global wind times `wind_strength` (wind_amp), so `wind_strength` 0 holds them
## still. Before that, two frames of one state differed by 200k px along every painted crown edge
## (card painter-perf-cull: the "sliver" at tokens_20 was this sway, not the per-tree cull).

## The wind uniforms freeze_wind() zeroes where a material's shader has them: the wind shader
## include's speeds (shaders/wind_foliage_include.gdshaderinc) and the painted trees' strength.
## The gust field follows the global wind clock instead (autoloads/wind.gd): freeze_wind pins
## it at 0 and thaw_wind releases it.
const WIND_SPEEDS: Array[String] = ["sway_speed", "flutter_speed", "wind_strength"]
## Frames in a row the camera must stand still after a framing step placed it (framed()).
const VIEW_REST_FRAMES := 3
## How long (seconds) each of framed()'s waits lasts before the step carries on and logs it.
const VIEW_HOLD_S := 10.0


## Sets the wind uniforms (WIND_SPEEDS) of every ShaderMaterial under `root` that has them to 0,
## recording each material's own values in `saved` (material -> {uniform: value}) the first
## time it is frozen, so thaw_wind() can put them back (one frozen before is set to 0 again, in
## case a foliage override re-applied its speeds). Returns how many materials it froze for the
## first time.
static func freeze_wind(root: Node, saved: Dictionary) -> int:
	var frozen := 0
	if not Wind.is_clock_pinned():
		Wind.set_clock_override(0.0)
	var has_wind := {}
	for material: ShaderMaterial in _shader_materials(root):
		if material.shader == null:
			continue
		if not has_wind.has(material.shader):
			has_wind[material.shader] = _wind_uniforms(material.shader)
		var present: Array = has_wind[material.shader]
		if present.is_empty():
			continue
		if not saved.has(material):
			var values := {}
			for uniform: String in present:
				values[uniform] = material.get_shader_parameter(uniform)
			saved[material] = values
			frozen += 1
		for uniform: String in present:
			material.set_shader_parameter(uniform, 0.0)
	return frozen


## The WIND_SPEEDS names `shader` declares.
static func _wind_uniforms(shader: Shader) -> Array:
	var present := []
	for uniform in WIND_SPEEDS:
		if _has_uniform(shader, uniform):
			present.append(uniform)
	return present


## Puts back the speeds freeze_wind() saved and empties `saved`. Returns how many.
static func thaw_wind(saved: Dictionary) -> int:
	var count := 0
	Wind.clear_clock_override()
	for material: Variant in saved:
		if not is_instance_valid(material):
			continue
		var values: Dictionary = saved[material]
		for uniform: String in values:
			(material as ShaderMaterial).set_shader_parameter(uniform, values[uniform])
		count += 1
	saved.clear()
	return count


## What still moves on its own in the open map, or "" when it is all at rest: a level
## loading, the camera easing (CameraController.is_at_rest), the scatter regenerating or
## growing in, placed props growing in, or height work (snapping, collision) under way.
static func busy(map: GameMap, ctrl: AuthoringController) -> String:
	if map == null or not is_instance_valid(map):
		return "no map"
	if map.call("_is_level_loading"):
		return "loading"
	if not map.get_camera_controller().is_at_rest():
		return "camera"
	if ctrl == null:
		return ""
	if not ctrl.get("_is_open"):
		return "authoring opening"
	for scatter: AuthoredScatter in [ctrl.scatter, ctrl.editor.props if ctrl.editor else null]:
		if is_instance_valid(scatter) and (scatter.is_regenerating() or scatter.is_growing()):
			return "scatter" if scatter == ctrl.scatter else "props"
	if ctrl.editor != null and ctrl.editor.has_height_work():
		return "height work"
	return ""


## Whether a `call` step frames the view: its probe has a static `frames_view(step) -> bool` that
## says so (water.gd's `look`, a card's named-view probe). driver.gd runs such a step through
## framed().
static func frames_view(script: GDScript, step: Dictionary) -> bool:
	var has := script.get_script_method_list().any(
		func(m: Dictionary) -> bool: return m.name == "frames_view"
	)
	return has and bool(script.call("frames_view", step))


## One frame of a framing step (driver.gd's `look_at`, a `call` whose probe frames_view): "hold"
## while it waits, "" once done, or a line for the job log when it gave up waiting. It ends the
## zoom ease on its target, waits for any other camera motion (a home tween, a pan) to stop, calls
## `place` once, then holds until the camera has stood still, the holder, the camera's transform and its
## size unchanged, for VIEW_REST_FRAMES frames in a row. Each wait gives up at VIEW_HOLD_S seconds
## and says so in the returned line ("" when nothing gave up).
## Why: a view placed while the zoom still eases moves with the ease's zoom toward the cursor
## afterwards, so a capture after it showed the requested view only when the view before it had
## the same zoom (2026-11-20, painter-rocks-forms: f1_o after `wide` came out metres off).
## `state` is the step's own (driver._state: `t` seconds in the step, `phase` from 0).
static func framed(map: GameMap, state: Dictionary, place: Callable) -> String:
	var cc := map.get_camera_controller()
	if int(state.phase) == 0:
		cc.finish_zoom()
		if not cc.is_at_rest():
			if float(state.t) < VIEW_HOLD_S:
				return "hold"
			state.note = "view placed with the camera still moving after %.0f s" % VIEW_HOLD_S
		place.call()
		state.phase = 1
		state.t = 0.0
		state.rest = 0
		state.pose = camera_pose(map)
		return "hold"
	var pose := camera_pose(map)
	var still: bool = cc.is_at_rest() and pose == state.pose
	state.pose = pose
	state.rest = int(state.rest) + 1 if still else 0
	if int(state.rest) >= VIEW_REST_FRAMES:
		return String(state.get("note", ""))
	if float(state.t) >= VIEW_HOLD_S:
		return "view still moving %.0f s after it was placed" % VIEW_HOLD_S
	return "hold"


## The camera's pose as framed() compares it frame to frame: the holder's position, the camera's
## global transform and its orthographic size.
static func camera_pose(map: GameMap) -> Array:
	return [
		map.cameraholder_node.global_position,
		map.camera_node.global_transform,
		map.camera_node.size,
	]


## What driver.gd's `wait_ready` still waits on, one entry per condition that holds (empty when
## none does): the level loading, authoring not yet open, the authored scatter regenerating or
## growing in, and height work, the last two with the parts that hold them, so a wait that does
## not end says why in the job log (2026-11-20: a `new_map` sat in `wait_ready` 11 minutes,
## silent). The parts are read by name, so a field a later change renames reads as -1.
static func holds(map: GameMap, ctrl: AuthoringController) -> PackedStringArray:
	var out := PackedStringArray()
	if map.call("_is_level_loading"):
		out.append("level loading")
	if ctrl == null or not out.is_empty():
		return out
	if not ctrl.get("_is_open"):
		# The recovery prompt holds the open until someone answers it (2026-11-20: a job run
		# against a user folder with an autosave never opened its map; the driver now points
		# the autosave at its own empty slot, so this names a slot something else filled).
		var prompt: Variant = ctrl.get("_recovery_prompt")
		if prompt is Object and is_instance_valid(prompt):
			out.append(
				(
					"authoring not open: the 'Recover an unsaved map?' prompt is up (an autosave in %s)"
					% AuthoringAutosave.directory
				)
			)
		else:
			out.append("authoring not open")
	var scatter: AuthoredScatter = ctrl.scatter if is_instance_valid(ctrl.scatter) else null
	if scatter != null and (scatter.is_regenerating() or scatter.is_growing()):
		var regen: Variant = scatter.get("_regen")
		out.append(
			(
				"scatter (jobs %d, finished %d, regen pending %s, growing %d)"
				% [
					_size(scatter, "_jobs"),
					_size(scatter, "_finished"),
					regen != null and regen.has_pending(),
					_size(scatter, "_growing"),
				]
			)
		)
	if ctrl.editor != null and ctrl.editor.has_height_work():
		out.append("height work (%s)" % ", ".join(_height_parts(ctrl.editor)))
	return out


## The parts of AuthoringEditor.has_height_work (HeightEditor.has_work) that hold, by name.
static func _height_parts(editor: Object) -> PackedStringArray:
	var parts := PackedStringArray()
	var heights: Variant = editor.get("heights")
	if heights == null:
		return parts
	if _size(heights, "_snap_windows") != 0:
		parts.append("snap windows %d" % _size(heights, "_snap_windows"))
	if heights.get("_collision_dirty") and heights.get("_stroke") == null:
		parts.append("collision")
	var terrain: Variant = editor.get("terrain")
	if is_instance_valid(terrain) and terrain.has_height_work():
		parts.append(
			(
				"terrain (dirty %d, skirt %s, settling %d)"
				% [
					_size(terrain, "_dirty_heights"),
					terrain.get("_skirt_dirty"),
					_size(terrain, "_settling")
				]
			)
		)
	var rocks: Variant = editor.get("rock_keeper")
	if rocks != null and rocks.is_running():
		parts.append("rocks")
	var water: Variant = editor.get("water")
	if water != null and water.is_working():
		parts.append("water (job %d)" % _size(water, "_job"))
	var landing: Variant = heights.get("_landing")
	if landing is Callable and (landing as Callable).is_valid():
		parts.append("landing")
	return parts


## The size of the container `object` holds in `field`, or -1 when it holds none.
static func _size(object: Object, field: String) -> int:
	var value: Variant = object.get(field)
	if value is Array or value is Dictionary:
		return value.size()
	return -1


## Every ShaderMaterial a node under `root` draws with: material overrides, surface
## overrides and the surface materials of its mesh or MultiMesh mesh.
static func _shader_materials(root: Node) -> Array:
	var seen := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var materials: Array = []
		var mesh: Mesh = null
		if node is GeometryInstance3D:
			materials.append((node as GeometryInstance3D).material_override)
		if node is MeshInstance3D:
			var instance := node as MeshInstance3D
			mesh = instance.mesh
			for s in instance.get_surface_override_material_count():
				materials.append(instance.get_surface_override_material(s))
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			mesh = (node as MultiMeshInstance3D).multimesh.mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				materials.append(mesh.surface_get_material(s))
		for material: Variant in materials:
			if material is ShaderMaterial:
				seen[material] = true
	return seen.keys()


static func _has_uniform(shader: Shader, uniform: String) -> bool:
	for entry: Dictionary in shader.get_shader_uniform_list():
		if String(entry.get("name", "")) == uniform:
			return true
	return false
