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
##
## `plazas` are up to MAX_PLAZAS discs {"at": Vector2 (map XZ, 1 cm), "radius": metres (0.1)} the
## street opens into: the kit's plaza rules furnish them (the first frontage carries them to
## ProcgenSettlement) and the Dress paves them with the kit's plaza surface. Discs only for now
## (polygons wait for the Village tool). They are saved with the record and round trip byte for
## byte; the paint itself is the map's (SettlementGround).
##
## `ground` lists the paint strokes the last Dress laid for this settlement (SettlementGroundIO:
## up to MAX_STROKES capsules in paint order, held to a hundredth). It is how Clear and a re-dress
## take back exactly that paint (SettlementUnpaint) and nothing the author painted by hand. Saved
## with the record, left out when empty.
##
## `fields` are up to MAX_FIELDS discs {"at": Vector2 (map XZ, 1 cm), "radius": metres (1 cm),
## "kind": a FIELD_KINDS entry} laid round the village's edge with the Village tool (villages
## phase 3, topic fields): crop rows, an orchard or a garden. Their paint goes into `ground` like a
## plaza's; their furnishings (a scarecrow, fruit trees, shrubs) are derived by VillageFields, never
## stored. Saved like plazas, left out when empty.
##
## `bridges` are the ids of the crossings (MapDocument.crossings) the last Dress laid where the
## street crosses water (VillageBridges; topic bridges): ordinary Crossing records, so they draw,
## follow sculpts and reach peers as any bridge does, and this list is how Clear and a re-dress
## take back exactly those and never a bridge the author placed by hand. Up to MAX_BRIDGES ids in
## 1..Crossing.MAX_ID, saved as a list, left out when empty.

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
const MAX_PLAZAS := 4
const PLAZA_MIN_RADIUS_M := 2.0
const PLAZA_MAX_RADIUS_M := 16.0
const PLAZA_STEP_M := 0.01
## A plaza's centre stays within this of the map's middle (a map is at most 640 m a side).
const PLAZA_MAX_REACH_M := 1000.0
const MAX_FIELDS := 4
const FIELD_MIN_RADIUS_M := 2.5
const FIELD_MAX_RADIUS_M := 18.0
## The kinds of field, in the pane's order.
const FIELD_KINDS: Array[String] = ["crops", "orchard", "garden"]
## Bridges one Dress lays at most (one per wet run of its street).
const MAX_BRIDGES := 8

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
var plazas: Array[Dictionary] = []
var ground: Array[Dictionary] = []
var fields: Array[Dictionary] = []
var bridges: PackedInt32Array = PackedInt32Array()


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
	out.plazas = plazas.duplicate(true)
	out.ground = ground.duplicate(true)
	out.fields = fields.duplicate(true)
	out.bridges = bridges.duplicate()
	return out


func same_as(other: Settlement) -> bool:
	return other != null and fingerprint() == other.fingerprint()


## A short text that changes when any field does (the record's saved form, hashed): the key a
## layer compares to know a settlement needs its props derived again.
func fingerprint() -> String:
	return JSON.stringify(MapSettlementIO.settlement_json(self), "", true, true).md5_text()
