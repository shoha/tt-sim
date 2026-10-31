class_name Settlement
extends RefCounted

## One dressed street or village in a MapDocument (`MapDocument.settlements`): which character
## (a procgen settlement kit) furnishes it, the seed, how rich and how busy it is, and the
## street it dresses. The props themselves (barrels, wells, lamps, stalls ...) are NEVER stored:
## SettlementPlan derives them from this record and the street's lots, on every peer, so a map
## carries tens of bytes per village and moving a house moves only its own frontage's props.
## Summary: docs/systems/settlements.md, design: docs/systems/villages.md.
##
## `source` is the id of the street (a row Wall) the settlement dresses, or 0 once the street was
## split into buildings: then `frozen` holds the frontage records (ProcgenFrontage.to_dict) the
## street had at the split, and the props stay where they were. A settlement whose street is gone
## draws nothing (and returns with the street on undo).
##
## The three override lists name placements by their slot id (SettlementPlan): `removed` slots
## are not drawn, `swapped` maps a slot to another prop, `pinned` maps a slot to a placement that
## is drawn as recorded whatever the rules now say (a pin has to carry its placement, or a
## re-dress would lose it).

## The characters: procgen's settlement kits, in its order (a saved map stores the name).
const KIND_NAMES: Array[String] = ProcgenSettlement.NAMES
const MAX_ID := 32
const MAX_SEED := 1000000000
const MAX_DENSITY := 1.5
const MAX_FROZEN := 2
const MAX_LOTS := 64
const MAX_OVERRIDES := 64
const MAX_TEXT := 64
const WEALTH_STEP := 0.01
const DEFAULT_WEALTH := 0.5
const DEFAULT_DENSITY := 0.6

var id: int = 0
var kit: String = KIND_NAMES[0]
var seed_value: int = 0
var wealth: float = DEFAULT_WEALTH
var density: float = DEFAULT_DENSITY
var source: int = 0
var frozen: Array[Dictionary] = []
var removed: PackedStringArray = PackedStringArray()
var pinned: Dictionary = {}
var swapped: Dictionary = {}


static func make(settlement_id: int, kit_name: String, street: int, seed_number: int) -> Settlement:
	var settlement := Settlement.new()
	settlement.id = settlement_id
	settlement.kit = kit_name
	settlement.source = street
	settlement.seed_value = seed_number
	return settlement


func copy() -> Settlement:
	var out := Settlement.make(id, kit, source, seed_value)
	out.wealth = wealth
	out.density = density
	out.frozen = frozen.duplicate(true)
	out.removed = removed.duplicate()
	out.pinned = pinned.duplicate(true)
	out.swapped = swapped.duplicate()
	return out


func same_as(other: Settlement) -> bool:
	return other != null and fingerprint() == other.fingerprint()


## A short text that changes when any field does (the record's saved form, hashed): the key a
## layer compares to know a settlement needs its props derived again.
func fingerprint() -> String:
	return JSON.stringify(MapSettlementIO.settlement_json(self), "", true, true).md5_text()
