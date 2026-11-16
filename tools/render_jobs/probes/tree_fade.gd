extends RefCounted

## Render-job probe (`call` op). Sets the brush's canopy fade radius factor (step.factor; 0 turns
## the brush fade off). (It also set the per-token occlusion fade's uniforms on the tree materials
## until that fade was removed, 2026-11-15; step.params is now ignored.)


static func run(base: Node, step: Dictionary) -> String:
	var gm: GameMap = base.get("_game_map")
	if step.has("factor"):
		gm.get_brush_tool().fade_radius_factor = float(step.factor)
	return "brush fade factor %.2f" % gm.get_brush_tool().fade_radius_factor
