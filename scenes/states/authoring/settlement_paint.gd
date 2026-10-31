class_name SettlementPaint
extends RefCounted

## Writes the strokes SettlementGround planned into the map's painted surfaces, as AuthoringEditor's
## own Paint strokes do (SurfaceStroke): the same slots, the same weights, the same history diffs,
## so the paint undoes, redoes, clears plants under a `built` surface and reaches a live-edit peer
## as the ordinary `surface` op. Each run of strokes on one surface is one SurfaceStroke and one
## history entry; SettlementEditor opens a history group round the lot, so a Dress is one Ctrl+Z.
## Summary: docs/systems/settlements.md "Ground".


## Paints `strokes` (SettlementGround.plan's, in order) into `editor`'s document and records each
## run as a history entry (inside the caller's group). Returns the number of entries recorded. The
## ground, scatter and peers follow through AuthoringEditor.apply_surface_diff, the method the
## entry's redo calls.
static func lay(editor: AuthoringEditor, strokes: Array[Dictionary]) -> int:
	var recorded := 0
	var run: SurfaceStroke = null
	var surface := ""
	for stroke in strokes:
		if run == null or str(stroke["surface"]) != surface:
			recorded += _finish(editor, run, surface)
			surface = str(stroke["surface"])
			run = SurfaceStroke.begin(editor.document, surface, false)
		if run != null:
			run.dab(stroke["from"], stroke["to"], stroke["radius"], stroke["seconds"])
	recorded += _finish(editor, run, surface)
	return recorded


## Ends `run`, applies its diff to the ground and records it. 1 when it changed anything.
static func _finish(editor: AuthoringEditor, run: SurfaceStroke, surface: String) -> int:
	if run == null:
		return 0
	var diff := run.finish()
	if diff.is_empty():
		return 0
	editor.apply_surface_diff(diff, true)
	(
		editor
		. history
		. record(
			{
				"label": "Pave " + AuthoringPanel.surface_label(surface).to_lower(),
				"undo": editor.apply_surface_diff.bind(diff, false),
				"redo": editor.apply_surface_diff.bind(diff, true),
				"bytes": int(diff.bytes),
			}
		)
	)
	return 1
