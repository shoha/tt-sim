extends RefCounted

## Render-job probe (`call` op) for the Building tool's third UI round (topic polish3).
## step.action:
##   browse {on}              the "Place another" strip's button (on true opens the palette).
##   decorate {kinds}         switches the Decorate chips of `kinds` on, as clicks would.
##   report                   the strip's and the chips' state.
## A new unsaved map only.


static func run(base: Node, step: Dictionary) -> String:
	var ctrl := base.get("_authoring_controller") as AuthoringController
	if ctrl == null:
		return "no controller"
	var pane := ctrl.panel.tool_pane(StructureTool.ID) as StructureToolPane
	if pane == null:
		return "no pane"
	match String(step.get("action", "")):
		"browse":
			pane.set_browsing(bool(step.get("on", true)))
			return "browsing %s" % pane.is_browsing()
		"decorate":
			for kind: Variant in step.get("kinds", []):
				var chip: Button = pane.ornaments_section.chips.get(String(kind))
				if chip != null and not chip.disabled:
					chip.button_pressed = true
			return "decorate sent"
		"report":
			return (
				"strip %s name '%s' button '%s' browsing %s selection %s palette fields %d"
				% [
					pane.place_strip.visible,
					pane.place_name.text,
					pane.place_button.text,
					pane.is_browsing(),
					pane.selection_box.visible,
					pane.family_fields.size(),
				]
			)
	return "unknown action %s" % step.get("action", "")
