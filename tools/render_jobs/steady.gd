extends RefCounted

## Repeatable captures for driver.gd: the wind frozen and the waits that end on a condition
## instead of a time (REFERENCE.md "State and maps": `wind`, `settle`). Two runs of a job
## with a seeded placement (`place_seed`), the wind frozen and `settle` in place of `wait`
## draw the same pixels, so an A/B of two packages differs only where the packages do.
##
## Wind sway reads the shader clock (TIME) times each material's sway, flutter and gust
## speeds; with those at 0 the plants hold still at their rest offsets, whatever the clock.

## The wind shader include's speed uniforms (shaders/wind_foliage_include.gdshaderinc).
## The gust field follows the global wind clock instead (autoloads/wind.gd): freeze_wind pins
## it at 0 and thaw_wind releases it.
const WIND_SPEEDS: Array[String] = ["sway_speed", "flutter_speed"]


## Sets the wind speeds of every ShaderMaterial under `root` that has them to 0, recording
## each material's own values in `saved` (material -> {uniform: value}) the first time it is
## frozen, so thaw_wind() can put them back (one frozen before is set to 0 again, in case a
## foliage override re-applied its speeds). Returns how many materials it froze for the
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
			has_wind[material.shader] = _has_uniform(material.shader, WIND_SPEEDS[0])
		if not has_wind[material.shader]:
			continue
		if not saved.has(material):
			var values := {}
			for uniform in WIND_SPEEDS:
				values[uniform] = material.get_shader_parameter(uniform)
			saved[material] = values
			frozen += 1
		for uniform in WIND_SPEEDS:
			material.set_shader_parameter(uniform, 0.0)
	return frozen


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
