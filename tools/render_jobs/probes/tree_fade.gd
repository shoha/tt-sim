extends RefCounted

## Render-job probe (`call` op). Sets occlusion-fade uniforms on every registered tree
## material in-run (step.params: {name: value}), and the brush's canopy fade radius factor
## (step.factor; 0 turns the brush fade off) if given.


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	var fade: OcclusionFadeManager = gm.occlusion_fade as OcclusionFadeManager
	var params: Dictionary = step.get("params", {})
	var n := 0
	for mat in fade._tree_materials:
		for key in params:
			mat.set_shader_parameter(String(key), params[key])
		n += 1
	if step.has("factor"):
		gm.get_brush_tool().fade_radius_factor = float(step.factor)
	return (
		"%d tree materials %s, brush fade factor %.2f"
		% [n, str(params), gm.get_brush_tool().fade_radius_factor]
	)
