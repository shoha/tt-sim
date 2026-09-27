extends RefCounted

## Render-job probe (`call` op). step.warm: set AuthoredScatter.warm_pipelines;
## step.use_biome: make that biome the brush's biome; step.tool (any value): select the biome
## tool; step.select: both, as clicking a biome tile does, without painting. Always logs the
## mesh and surface pipeline compilation counts.


static func run(base: Node, step: Dictionary) -> String:
	var c: AuthoringController = base.get("_authoring_controller")
	var out := ""
	if step.has("warm"):
		c.scatter.warm_pipelines = bool(step.warm)
		out += "warm %s " % str(c.scatter.warm_pipelines)
	if step.has("use_biome"):
		c.call("_use_biome", String(step.use_biome))
		out += "use_biome %s " % String(step.use_biome)
	if step.has("tool"):
		c.call("_select_tool", AuthoringPanel.TOOL_BIOME)
		out += "tool biome "
	if step.has("select"):
		c.call("_use_biome", String(step.select))
		c.call("_select_tool", AuthoringPanel.TOOL_BIOME)
		out += "selected %s " % String(step.select)
	out += (
		"pipelines mesh %d surface %d"
		% [
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH),
			Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)
		]
	)
	return out
