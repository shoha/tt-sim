class_name AvatarRecipe
extends RefCounted

## Avatar recipes (docs/ASSET_PIPELINE.md section 10 "Recipe"), a port of figurine's
## `recipe.py` `resolve`: a recipe names a part per slot, a colour pick per palette slot (an
## index into that slot's colour set), one face cell per kind, the proportion controls and a
## stance. Resolving it against a kit gives concrete choices, falling back to the first entry
## wherever the kit lacks what the recipe names and noting each fallback, so a recipe from a
## newer client still shows a figure here.
##
## A recipe is the JSON dictionary of the contract:
##   {"format": 1, "kit_version": "...", "parts": {slot: part id}, "colours": {slot: index},
##    "face": {kind: index}, "proportions": {control: 0..1}, "stance": "stance_ready"}
## The resolved form is a dictionary with "parts" (slot -> part id the kit has; `body` and
## `head` always filled), "colours" (every palette slot -> a valid index), "face" (every kind
## -> a valid cell), "proportions" (every control -> 0..1), "stance" and "fallbacks" (the
## notes, in figurine's wording).

const FORMAT := 1
const FACE_KINDS: Array[String] = ["eyes", "brows", "mouths", "marks"]
const REQUIRED_SLOTS: Array[String] = ["body", "head"]


## Resolves `recipe` against a kit: `parts_by_slot` (slot -> part ids in kit order),
## `colour_sets` (kit.json's), `face_counts` (kind -> cells in the sheet), `controls` (kit.json's
## `proportions`) and `stances` (stance names, first is the fallback).
static func resolve(
	recipe: Dictionary,
	parts_by_slot: Dictionary,
	colour_sets: Dictionary,
	face_counts: Dictionary,
	controls: Dictionary,
	stances: Array,
) -> Dictionary:
	var notes := PackedStringArray()
	if int(recipe.get("format", FORMAT)) != FORMAT:
		notes.append(
			"recipe format %s is not %d; reading it anyway" % [recipe.get("format"), FORMAT]
		)
	var wanted_parts: Dictionary = (
		recipe.get("parts", {}) if recipe.get("parts") is Dictionary else {}
	)
	var slots := {}
	for slot in wanted_parts:
		slots[String(slot)] = true
	for slot in REQUIRED_SLOTS:
		slots[slot] = true
	var slot_names := slots.keys()
	slot_names.sort()
	var chosen := {}
	for slot in slot_names:
		var available: Array = parts_by_slot.get(slot, [])
		var wanted: Variant = wanted_parts.get(slot)
		if wanted != null and available.has(String(wanted)):
			chosen[slot] = String(wanted)
		elif not available.is_empty():
			if wanted != null or REQUIRED_SLOTS.has(slot):
				notes.append(
					"part %s for %s not in kit; using '%s'" % [_repr(wanted), slot, available[0]]
				)
			chosen[slot] = String(available[0])
		elif wanted != null:
			notes.append("no %s parts in kit; '%s' dropped" % [slot, wanted])
	var picks: Dictionary = recipe.get("colours", {}) if recipe.get("colours") is Dictionary else {}
	var colours := {}
	for slot in AvatarPalette.SLOTS:
		var index := int(picks.get(slot, 0))
		var size: int = (colour_sets.get(AvatarPalette.SET_FOR_SLOT[slot], []) as Array).size()
		if index < 0 or index >= size:
			notes.append("colour %s=%d outside its set of %d; using 0" % [slot, index, size])
			index = 0
		colours[slot] = index
	var face_picks: Dictionary = recipe.get("face", {}) if recipe.get("face") is Dictionary else {}
	var face := {}
	for kind in FACE_KINDS:
		var index := int(face_picks.get(kind, 0))
		var count := int(face_counts.get(kind, 0))
		if index < 0 or index >= count:
			notes.append("face %s=%d outside the sheet's %d; using 0" % [kind, index, count])
			index = 0
		face[kind] = index
	var values: Dictionary = (
		recipe.get("proportions", {}) if recipe.get("proportions") is Dictionary else {}
	)
	var props := AvatarProportions.control_values(controls, values)
	var stance := String(recipe.get("stance", "stance_ready"))
	if not stances.has(stance) and not stances.is_empty():
		var fallback := String(stances[0])
		notes.append("stance '%s' not in kit; using '%s'" % [stance, fallback])
		stance = fallback
	return {
		"parts": chosen,
		"colours": colours,
		"face": face,
		"proportions": props,
		"stance": stance,
		"fallbacks": notes,
	}


static func _repr(value: Variant) -> String:
	return "None" if value == null else "'%s'" % value
