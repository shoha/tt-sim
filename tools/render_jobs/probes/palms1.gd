extends RefCounted

## Render-job probe (`call` op) for the palms and ferns looks pass (treecube
## docs/looks/palms_ferns.md), on the open authoring map:
## - `action: "hide_scatter"` (default): hide every scatter MultiMeshInstance3D under the
##   authoring scatter (`AuthoredScatter`), keeping placed props, so a type sheet shows only the
##   props a job placed on the biome's own ground; `visible: true` shows them again.
## - `action: "only"`, `prefixes` ([String]): show only the scatter nodes whose name starts with
##   one of the prefixes (the asset node stems, e.g. "Palm_", "Fern_").


static func run(root: Node, step: Dictionary) -> String:
	var ctrl := root.get("_authoring_controller") as AuthoringController
	if ctrl == null or ctrl.scatter == null:
		return "no authoring map"
	var action := String(step.get("action", "hide_scatter"))
	var prefixes: Array = step.get("prefixes", [])
	var shown := 0
	var hidden := 0
	for node in ctrl.scatter.find_children("*", "MultiMeshInstance3D", true, false):
		var keep := false
		if action == "hide_scatter":
			keep = bool(step.get("visible", false))
		else:
			for prefix in prefixes:
				if String(node.name).begins_with(String(prefix)):
					keep = true
		(node as Node3D).visible = keep
		if keep:
			shown += 1
		else:
			hidden += 1
	return "%s: %d scatter nodes shown, %d hidden" % [action, shown, hidden]
