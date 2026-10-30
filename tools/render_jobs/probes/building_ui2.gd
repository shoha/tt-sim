extends RefCounted

## Render-job probe (`call` op) for the Building tool's second UI round (topic building_ui2):
## the palette's chips, the hover card, the hint bar's key caps and the ghost's live note.
## step.action:
##   chip {id, on}        switches a filter chip on or off as a click does ("clear" clears all).
##   hover {ref}          the pointer enters the tile of `ref` (the hover card shows after its delay);
##                        with no ref, the pointer leaves.
##   hints {reset}        reports the keys on the hint bar; reset true forgets the gestures done.
##   note                 reports the brush's live note (text and level).
##   small {on}           the palette's small-tiles switch.
## A new unsaved map only. The hint memory is the run's own settings file (the worktree's user
## folder), cleared by `hints` with reset true.


static func run(base: Node, step: Dictionary) -> String:
	var ctrl := base.get("_authoring_controller") as AuthoringController
	if ctrl == null:
		return "no controller"
	var pane := ctrl.panel.tool_pane(StructureTool.ID) as StructureToolPane
	match String(step.get("action", "")):
		"chip":
			if pane == null:
				return "no pane"
			if String(step.get("id", "")) == "clear":
				pane.clear_filters()
			else:
				pane.set_chip(String(step.get("id", "")), bool(step.get("on", true)))
			return "chips %s, %d tiles" % [pane.active_chips(), pane.refs().size()]
		"hover":
			if pane == null:
				return "no pane"
			var ref := String(step.get("ref", ""))
			for field in pane.family_fields:
				if ref != "" and field.tiles.has_tile(StringName(ref)):
					field.tiles.tile_hovered.emit(StringName(ref))
					return "hovering %s" % ref
			pane._hide_card()
			return "pointer left"
		"hints":
			if bool(step.get("reset", false)):
				StructureHints.reset(true)
				ctrl.refresh_tool_hints()
			return "hint rows: %s" % [StructureHints.rows(StructureHints.done(), false)]
		"note":
			var gm := base.get("_game_map") as GameMap
			var mode := StructureTool.of(gm.get_brush_tool())
			return "note %s ghost %s" % [mode.note, mode.ghost_centre]
		"small":
			if pane != null:
				pane.small_tiles_button.button_pressed = bool(step.get("on", true))
			return "small tiles"
	return "unknown action %s" % step.get("action", "")
