extends RefCounted

## Render-job probe for card verify1: one line reporting the Villages tool's piece buttons
## (VillagePieceButtons): whether the strip is visible and, per pill, its visibility and screen rect.
##   {action: "pills", tag}   the line, prefixed with `tag`


static func run(base: Node, step: Dictionary) -> String:
	var tag := String(step.get("tag", ""))
	if String(step.get("action", "")) == "list":
		var ctrl: AuthoringController = base.get("_authoring_controller")
		var counts := {}
		for settlement in ctrl.editor.document.settlements:
			for row in VillageProps.rows_of(ctrl.editor, settlement.id):
				var slot := str(row["item"]["slot"])
				var key := (
					"s%d %s %s"
					% [
						settlement.id,
						str(VillagePieceHome.kind_of(settlement.kit, slot)),
						VillageFurnishings.rule_of(slot)
					]
				)
				counts[key] = int(counts.get(key, 0)) + 1
		return "pieces by settlement, home kind, rule: %s" % str(counts)
	var found := base.get_tree().root.find_children("VillagePieceButtons", "", true, false)
	if found.is_empty():
		return "%s: no VillagePieceButtons node" % tag
	var strip := found[0] as Control
	var parts: Array[String] = []
	for pill_name in ["PieceSwap", "PieceBack", "PieceRemove"]:
		var pill := strip.find_child(pill_name, true, false) as Control
		if pill == null:
			parts.append("%s missing" % pill_name)
			continue
		var shown := pill.is_visible_in_tree()
		parts.append(
			(
				"%s %s rect %s"
				% [pill_name, "SHOWN" if shown else "hidden", str(pill.get_global_rect())]
			)
		)
	return "%s: strip visible=%s | %s" % [tag, str(strip.is_visible_in_tree()), " | ".join(parts)]
