extends RefCounted

## Render-job probe (`call` op). Turns the procgen plank bridge switch on or off
## (step.enabled, a bool): crossings built after this call use the module's plank bridge
## (ProcgenCrossing.enabled, docs/systems/procgen.md). Existing crossings keep their meshes
## until they are rebuilt (a reload, an edit near them).


static func run(_base: Node, step: Dictionary) -> String:
	ProcgenCrossing.enabled = bool(step.get("enabled", false))
	return "procgen planks %s" % ("on" if ProcgenCrossing.enabled else "off")
