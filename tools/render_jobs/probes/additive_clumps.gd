extends RefCounted

## Render-job probe (`call` op). Sets the static ScatterPlan.additive_clumps switch
## (step.additive, default true). Call it before any painting: it only affects scatter
## generated afterwards.


static func run(_base: Node, step: Dictionary) -> String:
	ScatterPlan.additive_clumps = bool(step.get("additive", true))
	return "additive_clumps %s" % str(ScatterPlan.additive_clumps)
