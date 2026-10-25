class_name LegacyHabit
extends RefCounted

## The LEGACY habit rule: which species keys and kinds of treecube's palette grow at the water's
## edge, are arid or are charred, from before a palette rule could say so itself. A rule's own
## `habit` ({water: "" | "bank" | "emergent" | "arid", charred: bool}, set by the content library
## through its role, docs/systems/library.md) wins; this table answers only for a rule that has
## none (treecube's palette, plantgen's package, hand-built test rules). It is the one place the
## lists live: ScatterGround.habit_of reads it as the fallback, LibraryContracts.export_json
## publishes it in contract.json (`legacy_habit`) so the plantgen importer derives a rule's
## explicit habit from the same lists. New species name their habit through a role, not here.
## Pure: no files, no scene tree.

## Species keys of the water's edge: the palette's wetland reeds and riparian trees, and ferns.
const EMERGENT_KEYS: Array[String] = ["reeds", "rushes", "cattail", "sedge"]
const BANK_KEYS: Array[String] = ["willow", "poplar", "alder", "fern", "fern_small"]
## Dry-country kinds (cacti) keep out of the whole bank band.
const ARID_KINDS: Array[String] = ["cactus"]
## The burnt forest's charred species, which live on ash.
const CHARRED_KEYS: Array[String] = [
	"snag", "snag_conifer", "high_stump", "stump", "branches", "log", "char_litter"
]


## The habit of a legacy rule by its key and kind: {water: String, charred: bool}. A key in both
## water lists is emergent; an emergent or bank key of an arid kind keeps its water flag (no
## palette rule has both).
static func for_key(key: String, kind: String) -> Dictionary:
	var water := ""
	if key in EMERGENT_KEYS:
		water = "emergent"
	elif key in BANK_KEYS:
		water = "bank"
	elif kind in ARID_KINDS:
		water = "arid"
	return {"water": water, "charred": key in CHARRED_KEYS}


## The lists as plain data, for contract.json.
static func export_table() -> Dictionary:
	return {
		"arid_kinds": ARID_KINDS.duplicate(),
		"bank_keys": BANK_KEYS.duplicate(),
		"charred_keys": CHARRED_KEYS.duplicate(),
		"emergent_keys": EMERGENT_KEYS.duplicate(),
	}
