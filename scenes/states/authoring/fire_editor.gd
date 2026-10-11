class_name FireEditor
extends RefCounted

## AuthoringEditor's fire edits (the Fire tool, FireBrush, calls them through
## `AuthoringEditor.begin_fire_stroke` and the editor's stroke entry points): laying and
## putting out persistent ground fire (MapDocument.fire_mask). Part of the editor, split out
## to keep one class a readable size; it reaches into the editor for the history, the other
## strokes and the fire field. Frames: world in, document inside, as the editor. Design:
## docs/plans/2026-10-11-fire-features/design.md section 2; summary docs/systems/authoring.md.
##
## A lay stroke is a MaskStroke in MaskBrush.FIRE mode writing fire_mask alone, its intensity
## approaching the pane's target. It records its dabs (world from, to, radius, seconds), and at
## its end replays them as two more strokes inside one AuthoringHistory group, so one undo
## takes all three back ("Lay fire"):
##   1. the fire itself (the mask diff);
##   2. the palette's burnt forest biome (FireSweep.plan_for) painted only where forest stood
##      (a MaskStroke with only_slots: biomes whose trees reach FOREST_TREES_PER_M2), so trees
##      under the fire burn to snags as Start a fire leaves them and a meadow stays a meadow;
##   3. ash (else its stand-in, plan_for) painted at ASH_REACH times the radius, a charred rim
##      just past the flames. Ash is a separate layer, so putting fire out leaves it.
## A part with nothing to change (no forest, ash refused because every paint slot holds
## paint) is left out; the fire is laid regardless. An erase stroke (Ctrl) is one plain entry
## "Put out fire" with the mask part only: ash and snags stay.
##
## Why the burnt biome and ash land at release, not while painting: the editor runs one stroke
## at a time, and the flames hide the ground under them while painting.

const LAY_LABEL := "Lay fire"
const PUT_OUT_LABEL := "Put out fire"
## The ash's reach beyond the fire's brush, and the burnt biome's.
const ASH_REACH := 1.1
const BURN_REACH := 1.0
## A biome whose tree species together reach this density is a forest (palette v7: the
## woodlands and forests reach 0.05 to 0.08 trees per square metre, meadows and savanna stay
## under 0.035).
const FOREST_TREES_PER_M2 := 0.04

## The fire stroke in progress, or null.
var _stroke: MaskStroke = null
var _erase: bool = false
## Its dabs: [from: Vector3, to: Vector3, radius: float, seconds: float] each, world space.
var _dabs: Array = []
## The editor (weak: it owns this object).
var _owner: WeakRef = null


static func create(editor: AuthoringEditor) -> FireEditor:
	var fire := FireEditor.new()
	fire._owner = weakref(editor)
	return fire


func _editor() -> AuthoringEditor:
	return _owner.get_ref() as AuthoringEditor


## True while a fire stroke is in progress.
func is_stroking() -> bool:
	return _stroke != null


## Starts a fire stroke laying fire toward `target` (0..1 of the mask's 255), or with `erase`
## putting it out. False when the map's ground is not the document's.
func begin(target: float, erase: bool) -> bool:
	var editor := _editor()
	if not editor.can_paint():
		return false
	_stroke = MaskStroke.begin(editor.document, MaskBrush.FIRE)
	_stroke.target = 0.0 if erase else clampf(target, 0.0, 1.0)
	_erase = erase
	_dabs = []
	return true


## One dab of the stroke (world space), recorded for the lay's replay.
func dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	var editor := _editor()
	var scale := editor.map_scale()
	_stroke.dab(editor.to_map_xz(from), editor.to_map_xz(to), radius / scale, seconds)
	_dabs.append([from, to, radius, seconds])


## Draws this frame's change.
func flush() -> void:
	if _stroke != null:
		_editor().refresh_fire(_stroke.take_pending())


## Ends the stroke and records it (see the header). True when the fire changed.
func end() -> bool:
	var editor := _editor()
	var stroke := _stroke
	_stroke = null
	editor.refresh_fire(stroke.take_pending())
	var diff := stroke.finish()
	if diff.is_empty():
		return false
	var part := {
		"label": PUT_OUT_LABEL if _erase else LAY_LABEL,
		"undo": editor.apply_fire_diff.bind(diff, false),
		"redo": editor.apply_fire_diff.bind(diff, true),
		"bytes": int(diff.bytes),
	}
	if _erase:
		editor.history.record(part)
		editor.edited.emit()
		return true
	editor.history.begin_group()
	editor.history.record(part)
	var root := editor.palette_root
	var plan := FireSweep.plan_for(PaletteLibrary.biomes(root), PaletteLibrary.surfaces(root))
	_burn_forest(String(plan.biome))
	_lay_ash(String(plan.surface))
	editor.history.end_group(LAY_LABEL)
	editor.edited.emit()
	return true


## Abandons the stroke, putting every sample back.
func cancel() -> void:
	if _stroke == null:
		return
	var rect := _stroke.revert()
	_stroke = null
	_editor().refresh_fire(rect)


## Part 2: the burnt biome over the stroke's dabs, only on forest (see the header).
func _burn_forest(burnt: String) -> void:
	var editor := _editor()
	var doc := editor.document
	if burnt == "" or doc.biome_slots.size() != doc.sample_count():
		return
	var allowed := forest_slots(doc.biome_ids, PaletteLibrary.biomes(editor.palette_root))
	if allowed.count(1) == 0:
		return
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, burnt)
	if stroke == null:
		return
	stroke.only_slots = allowed
	var scale := editor.map_scale()
	for d: Array in _dabs:
		var radius: float = d[2] * BURN_REACH / scale
		stroke.dab(editor.to_map_xz(d[0]), editor.to_map_xz(d[1]), radius, d[3])
	var diff := stroke.finish()
	if diff.is_empty():
		return
	editor.apply_mask_diff(diff, true)
	(
		editor
		. history
		. record(
			{
				"label": "Burn forest",
				"undo": editor.apply_mask_diff.bind(diff, false),
				"redo": editor.apply_mask_diff.bind(diff, true),
				"bytes": int(diff.bytes),
			}
		)
	)


## Part 3: ash over the stroke's dabs at ASH_REACH, through the editor's Paint stroke.
func _lay_ash(surface: String) -> void:
	var editor := _editor()
	if surface == "" or editor.surface_refusal(surface) != "":
		return
	if not editor.begin_surface_stroke(surface, false):
		return
	for d: Array in _dabs:
		editor.stroke_dab(d[0], d[1], float(d[2]) * ASH_REACH, d[3])
	editor.end_stroke()


## One byte per slot value (index 0 = no biome, s = biome_ids[s - 1]): 1 where the slot's
## biome is a forest of `biomes` (PaletteLibrary.biomes; tree density at least
## FOREST_TREES_PER_M2, the burnt biome itself never). Size MAX_BIOMES + 1. Pure.
static func forest_slots(biome_ids: PackedStringArray, biomes: Array) -> PackedByteArray:
	var forests := {}
	for entry: Dictionary in biomes:
		if String(entry.get("biome", "")) == FireSweep.BURNT_BIOME:
			continue
		var trees := 0.0
		for species: Dictionary in entry.get("species", []):
			if String(species.get("kind", "")) == "tree":
				trees += float(species.get("density_per_m2", 0.0))
		if trees >= FOREST_TREES_PER_M2:
			forests[String(entry.get("id", ""))] = true
	var out := PackedByteArray()
	out.resize(MapDocument.MAX_BIOMES + 1)
	for s in biome_ids.size():
		if forests.has(biome_ids[s]):
			out[s + 1] = 1
	return out
