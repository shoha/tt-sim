class_name AvatarRecipe
extends RefCounted

## Avatar recipes (docs/ASSET_PIPELINE.md section 10 "Recipe"), a port of figurine's
## `recipe.py` `resolve`: a recipe names a part per slot, a colour pick per palette slot (an
## index into that slot's colour set), one face cell per kind, the proportion controls and a
## stance. Resolving it against a kit gives concrete choices, falling back to the first entry
## wherever the kit lacks what the recipe names and noting each fallback, so a recipe from a
## newer client still shows a figure here. Optional slots (hat, cloak, gear) fall back to none
## instead, and a recipe may name null there.
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
## Slots every figure has, whatever the recipe says.
const REQUIRED_SLOTS: Array[String] = ["body", "head"]
## Slots a figure may leave empty (section 10 "Slots"), for a kit whose kit.json has no
## `slots` block; a kit's own block wins (optional_slots).
const OPTIONAL_SLOTS: Array[String] = ["hat", "cloak", "gear"]


## The optional slots of a kit manifest: those its `slots` block marks optional, or
## OPTIONAL_SLOTS for a kit from before the block.
static func optional_slots(manifest: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if not manifest.get("slots") is Dictionary:
		out.assign(OPTIONAL_SLOTS)
		return out
	var slots: Dictionary = manifest.slots
	for slot in slots:
		if slots[slot] is Dictionary and bool((slots[slot] as Dictionary).get("optional", false)):
			out.append(String(slot))
	out.sort()
	return out


## Resolves `recipe` against a kit: `parts_by_slot` (slot -> part ids in kit order),
## `colour_sets` (kit.json's), `face_counts` (kind -> cells in the sheet), `controls` (kit.json's
## `proportions`), `stances` (stance names, first is the fallback) and `optional` (the kit's
## optional slots). A required slot the kit has parts for is always filled: a recipe that
## omits it, names null or names a part the kit lacks gets the slot's first part (noted). An
## optional slot holds a part only when the recipe names one the kit has: omitted or null
## means none, and a part the kit lacks means none (noted).
static func resolve(
	recipe: Dictionary,
	parts_by_slot: Dictionary,
	colour_sets: Dictionary,
	face_counts: Dictionary,
	controls: Dictionary,
	stances: Array,
	optional: Array = OPTIONAL_SLOTS,
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
	for slot in parts_by_slot:
		slots[String(slot)] = true
	var slot_names := slots.keys()
	slot_names.sort()
	var chosen := {}
	for slot in slot_names:
		var available: Array = parts_by_slot.get(slot, [])
		var wanted: Variant = wanted_parts.get(slot)
		if wanted != null and available.has(String(wanted)):
			chosen[slot] = String(wanted)
		elif optional.has(slot):
			if wanted != null:
				notes.append("part '%s' for %s not in kit; left empty" % [wanted, slot])
		elif not available.is_empty():
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


## A deep copy of `recipe` with its numbers typed as the contract has them: `format` and
## every colour and face pick an int, every proportion a float. A recipe read back from JSON
## (a level file) carries floats everywhere, so two copies of one recipe compare equal only
## after this. Keys the recipe has that this client does not know are kept as they are.
static func normalized(recipe: Dictionary) -> Dictionary:
	var out := recipe.duplicate(true)
	if out.has("format"):
		out["format"] = int(out["format"])
	for key in ["colours", "face"]:
		if out.get(key) is Dictionary:
			var picks: Dictionary = out[key]
			for slot in picks:
				picks[slot] = int(picks[slot])
	if out.get("proportions") is Dictionary:
		var values: Dictionary = out["proportions"]
		for control in values:
			values[control] = float(values[control])
	return out


static func _repr(value: Variant) -> String:
	return "None" if value == null else "'%s'" % value
