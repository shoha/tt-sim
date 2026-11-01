class_name VillageFields
extends RefCounted

## The pure rules of a village's fields (villages phase 3, first slice, topic fields;
## docs/systems/villages.md section 11). A field is a disc in `Settlement.fields`
## ({"at": Vector2, "radius", "kind"}) that the Village tool lays round a village's edge, as it lays
## a plaza. Three kinds, each a few bold painted shapes and a few confident furnishings rather than
## fine detail:
##
## - crops: a disc of tilled earth with broad crop rows painted across it (green or gold, the seed's
##   pick), and a scarecrow standing in it; a haystack by the rim on some fields.
## - orchard: a disc of warm meadow grass with fruit trees in a loose grid turned by the seed, and
##   bee skeps by the rim on some.
## - garden: a small disc of meadow grass with two or three earth beds, flowers along the beds and
##   a flowering shrub or two at the rim.
##
## Everything here is a function of the record and the settlement's seed: the strokes
## (`strokes_of`), the props drawn by AuthoredSettlements (`props_of`) and the plants drawn by
## AuthoredFieldPlants (`plants_of`). The same record gives the same list on every peer; a re-dress
## (the next seed) turns the rows and moves the trees. Because the strokes follow from the record,
## a resize or a removal finds exactly a field's own paint in the record's `ground` list
## (`stroke_indices`). A kit decides which kinds its villages keep (KIT_KINDS: a harbour town keeps
## none), and its first kind is the default. No scene tree, no editor.

const GROUP_PLAZAS := &"plazas"
const GROUP_FIELDS := &"fields"
## The kinds each character offers, its default first. A kit not listed keeps no fields.
const KIT_KINDS := {
	"farming_hamlet": ["crops", "orchard", "garden"],
	"market_town": ["garden", "orchard"],
	"hill_fort_village": ["garden", "crops"],
	"harbour_town": [],
}
const KIND_LABELS := {"crops": "Crops", "orchard": "Orchard", "garden": "Garden"}
const KIND_TIPS := {
	"crops": "Tilled earth in broad rows, with a scarecrow",
	"orchard": "Fruit trees in a loose grid on warm grass",
	"garden": "Flower beds and a few shrubs: a small plot",
}
## The tint a field's ring is previewed in (the Village tool's ghost and drag): tilled ochre,
## orchard green, garden rose.
const KIND_TINTS := {
	"crops": Color(0.86, 0.62, 0.34),
	"orchard": Color(0.56, 0.8, 0.38),
	"garden": Color(0.93, 0.6, 0.74),
}
## A click lays a field this wide; the tool's floor and ceiling per kind.
const DEFAULT_RADIUS_M := {"crops": 8.0, "orchard": 8.0, "garden": 4.5}
const MIN_RADIUS_M := {"crops": 4.0, "orchard": 4.0, "garden": 2.5}
const MAX_RADIUS_M := {"crops": 18.0, "orchard": 16.0, "garden": 8.0}

## The surfaces each kind paints (palette ids): the ground disc, and the rows or beds over it.
const EARTH := "dirt"
const MEADOW := "grass_meadow"
## Crop rows: green (greens, beans) or gold (wheat), the seed's pick per field.
const CROP_ROWS: Array[String] = ["grass_alpine", "grass_savanna"]
## The ground disc is this much wider than the field (its soft edge is the rest).
const DISC_FACTOR := 1.05
## Rows: this far apart, this brush radius (about 1 m of full cover, 0.6 m of earth between), and
## they stop this share of the disc's half chord short of the rim.
const ROW_PITCH_M := 2.5
const ROW_RADIUS_M := 0.8
const ROW_REACH := 0.84
const BED_PITCH_M := 2.2
const BED_RADIUS_M := 0.75
const SECONDS := 1.2
## Orchard trees (core library ids): this far apart, nudged by up to this, at this scale.
## Palette ids of the core library's grassland meadow biome (every one served by the default
## palette root; probed 2026-10-31).
const ORCHARD_TREES: Array[String] = [
	"grassland_meadow_summer_s1/Tree_Broadleaf_v0",
	"grassland_meadow_summer_s1/Tree_Oak_v0",
	"grassland_meadow_summer_s1/Tree_Oak_v1",
]
const TREE_PITCH_M := 4.6
const TREE_JITTER_M := 0.7
const TREE_SCALE := Vector2(0.42, 0.55)
const TREE_RIM_M := 1.6
const GARDEN_FLOWERS: Array[String] = [
	"grassland_meadow_summer_s1/Flower_LavenderMound_v0",
	"grassland_meadow_summer_s1/Flower_LavenderMound_v1",
	"grassland_meadow_summer_s1/Flower_BloomMound_v0_grassland_meadow",
	"grassland_meadow_summer_s1/Flower_BloomMound_v1_grassland_meadow",
]
const GARDEN_SHRUBS: Array[String] = [
	"grassland_meadow_summer_s1/Bush_FloweringBush_v0",
	"grassland_meadow_summer_s1/Bush_BerryBush_v0_grassland_meadow",
]
const FLOWER_STEP_M := 1.0


## The kinds `kit` offers, its default first ([] when its villages keep no fields).
static func kinds_of(kit: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(KIT_KINDS.get(kit, []))
	return out


## The kind a press lays in a village of `kit` when the author asked for `wanted` ("" for the
## kit's default): `wanted` when the kit offers it, else the kit's default, else "".
static func kind_for(kit: String, wanted: String) -> String:
	var offered := kinds_of(kit)
	if offered.has(wanted):
		return wanted
	return offered[0] if not offered.is_empty() else ""


## `radius` held to the tool's range for `kind`, in tenths of a metre.
static func clamp_radius(radius: float, kind: String) -> float:
	return clampf(
		snappedf(radius, 0.1),
		float(MIN_RADIUS_M.get(kind, Settlement.FIELD_MIN_RADIUS_M)),
		float(MAX_RADIUS_M.get(kind, Settlement.FIELD_MAX_RADIUS_M))
	)


## The radius a drag from `centre` to `to` makes for `kind`: a click is the kind's default.
static func radius_for_drag(centre: Vector2, to: Vector2, kind: String) -> float:
	var reach := centre.distance_to(to)
	var click := float(DEFAULT_RADIUS_M.get(kind, 6.0))
	return clamp_radius(click if reach < VillagePlazas.DRAG_MIN_M else reach, kind)


## The disc under map point `p` among the plazas and fields of `settlements`, as VillagePlazas.pick
## gives it plus "group" (GROUP_PLAZAS or GROUP_FIELDS), or {}. A rim of either wins over an
## inside; between a plaza and a field both under the point the plaza wins (it is the smaller).
static func pick_any(
	settlements: Array[Settlement], p: Vector2, rim_m: float, handle_m: float = 0.0
) -> Dictionary:
	var plaza := VillagePlazas.pick(settlements, p, rim_m, handle_m, GROUP_PLAZAS)
	var field := VillagePlazas.pick(settlements, p, rim_m, handle_m, GROUP_FIELDS)
	plaza["group"] = GROUP_PLAZAS
	field["group"] = GROUP_FIELDS
	if plaza.size() > 1 and plaza["part"] == VillagePlazas.PART_RIM:
		return plaza
	if field.size() > 1 and field["part"] == VillagePlazas.PART_RIM:
		return field
	if plaza.size() > 1:
		return plaza
	return field if field.size() > 1 else {}


## The angle of `field`'s rows or grid (radians), from the settlement's seed and the field's place.
static func angle_of(field: Dictionary, seed_value: int) -> float:
	var at: Vector2 = field["at"]
	return float(_hash(seed_value, at, "angle") % 6283) / 1000.0


## The paint strokes of `field` with seed `seed_value`, in paint order: capsules {"surface",
## "from", "to", "radius", "seconds"} held to a hundredth (SettlementGroundIO.snapped_stroke).
static func strokes_of(field: Dictionary, seed_value: int) -> Array[Dictionary]:
	var at: Vector2 = field["at"]
	var radius := float(field["radius"])
	var kind := str(field["kind"])
	var out: Array[Dictionary] = []
	var ground := EARTH if kind == "crops" else MEADOW
	out.append(_stroke(ground, at, at, radius * DISC_FACTOR))
	var along := Vector2.from_angle(angle_of(field, seed_value))
	var across := Vector2(-along.y, along.x)
	if kind == "crops":
		var rows := CROP_ROWS[_hash(seed_value, at, "rows") % CROP_ROWS.size()]
		for offset in _offsets(radius * ROW_REACH, ROW_PITCH_M):
			var half := sqrt(maxf(radius * radius - offset * offset, 0.0)) * ROW_REACH - ROW_RADIUS_M
			if half > 0.5:
				var mid := at + across * offset
				out.append(_stroke(rows, mid - along * half, mid + along * half, ROW_RADIUS_M))
	elif kind == "garden":
		for offset in _offsets(radius * 0.62, BED_PITCH_M):
			var half := sqrt(maxf(radius * radius - offset * offset, 0.0)) * 0.6 - BED_RADIUS_M
			if half > 0.3:
				var mid := at + across * offset
				out.append(_stroke(EARTH, mid - along * half, mid + along * half, BED_RADIUS_M))
	return out


## The surfaces `field` paints, in paint order.
static func surfaces_of(field: Dictionary, seed_value: int) -> Array[String]:
	var out: Array[String] = []
	for stroke in strokes_of(field, seed_value):
		if not out.has(str(stroke["surface"])):
			out.append(str(stroke["surface"]))
	return out


## The indices in `ground` (a record's strokes) of the strokes `field` laid with seed
## `seed_value`, newest first: what a resize or a removal takes back. A stroke refused or never
## laid is simply not found.
static func stroke_indices(
	ground: Array[Dictionary], field: Dictionary, seed_value: int
) -> PackedInt32Array:
	var out := PackedInt32Array()
	for wanted in strokes_of(field, seed_value):
		for index in range(ground.size() - 1, -1, -1):
			if not out.has(index) and _same_stroke(ground[index], wanted):
				out.append(index)
				break
	out.sort()
	out.reverse()
	return out


## The props (ProcgenProps names) of `settlement`'s fields as SettlementPlan placements: a
## scarecrow in each crop field, a haystack by the rim of some, bee skeps by some orchards.
static func props_of(settlement: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in settlement.fields.size():
		var field := settlement.fields[k]
		var at: Vector2 = field["at"]
		var radius := float(field["radius"])
		var turn := angle_of(field, settlement.seed_value)
		var kind := str(field["kind"])
		var roll := _hash(settlement.seed_value, at, "props")
		if kind == "crops":
			var spot := at + Vector2.from_angle(turn + 1.3) * radius * 0.28
			out.append(_prop("scarecrow", spot, turn + 0.6, 1.15, roll, "f%d:scarecrow" % k))
			if roll % 3 != 0:
				var rim := at + Vector2.from_angle(turn + 2.6 + float(roll % 7) * 0.2) * radius * 1.08
				out.append(_prop("haystack", rim, turn, 1.0, roll >> 3, "f%d:haystack" % k))
		elif kind == "orchard" and roll % 2 == 0:
			var rim := at + Vector2.from_angle(turn - 0.9) * (radius + 0.6)
			out.append(_prop("beehive_skeps", rim, turn + PI, 1.0, roll >> 2, "f%d:skeps" % k))
	return out


## The plants of `settlement`'s fields: [{"asset" (a palette id), "at": Vector2, "yaw", "scale"}],
## orchard trees and garden flowers and shrubs, in field order.
static func plants_of(settlement: Settlement) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for field in settlement.fields:
		match str(field["kind"]):
			"orchard":
				out.append_array(_orchard(field, settlement.seed_value))
			"garden":
				out.append_array(_garden(field, settlement.seed_value))
	return out


## What the pane shows about fields, added to VillagePlazas.state_of's `state` for picked village
## `village`, the picked disc's `group` and `index`, and the kind the author asked for (`wanted`,
## "" for the kit's default): `fields` (how many), `kinds` (offered), `field_kind` (what a press
## lays), `group` and, for a picked field, its `radius` and `picked_kind`.
static func with_fields(
	state: Dictionary, doc: MapDocument, village: int, group: StringName, index: int, wanted: String
) -> Dictionary:
	var out := state.duplicate()
	out["fields"] = 0
	out["kinds"] = [] as Array[String]
	out["field_kind"] = ""
	out["group"] = group
	out["picked_kind"] = ""
	var held := doc.settlement(village) if village > 0 else null
	if held == null:
		return out
	out["fields"] = held.fields.size()
	out["kinds"] = kinds_of(held.kit)
	out["field_kind"] = kind_for(held.kit, wanted)
	if group == GROUP_FIELDS:
		out["plaza"] = -1
		out["radius"] = 0.0
		if index >= 0 and index < held.fields.size():
			out["plaza"] = index
			out["radius"] = float(held.fields[index]["radius"])
			out["picked_kind"] = str(held.fields[index]["kind"])
	return out


# --- helpers -----------------------------------------------------------------------------------


static func _orchard(field: Dictionary, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at: Vector2 = field["at"]
	var radius := float(field["radius"])
	var turn := angle_of(field, seed_value)
	var along := Vector2.from_angle(turn)
	var across := Vector2(-along.y, along.x)
	var reach := radius - TREE_RIM_M
	var steps := floori(reach / TREE_PITCH_M)
	# The grid is offset half a pitch on alternate rows: a loose quincunx, not a parade.
	for row in range(-steps, steps + 1):
		for col in range(-steps - 1, steps + 2):
			var shift := 0.5 * TREE_PITCH_M if absi(row) % 2 == 1 else 0.0
			var local := along * (col * TREE_PITCH_M + shift) + across * (row * TREE_PITCH_M * 0.9)
			var h := _hash(seed_value, at + local, "tree")
			var nudge := Vector2(float(h % 1001) / 500.0 - 1.0, float((h >> 10) % 1001) / 500.0 - 1.0)
			var spot := at + local + nudge * TREE_JITTER_M
			if spot.distance_to(at) > reach:
				continue
			out.append(
				{
					"asset": ORCHARD_TREES[(h >> 20) % ORCHARD_TREES.size()],
					"at": spot,
					"yaw": float((h >> 4) % 6283) / 1000.0,
					"scale": lerpf(TREE_SCALE.x, TREE_SCALE.y, float((h >> 14) % 101) / 100.0),
				}
			)
	return out


static func _garden(field: Dictionary, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at: Vector2 = field["at"]
	var radius := float(field["radius"])
	var turn := angle_of(field, seed_value)
	var along := Vector2.from_angle(turn)
	var across := Vector2(-along.y, along.x)
	var bed := 0
	for offset in _offsets(radius * 0.62, BED_PITCH_M):
		var half := sqrt(maxf(radius * radius - offset * offset, 0.0)) * 0.6 - BED_RADIUS_M
		if half <= 0.3:
			continue
		# One flower per bed, so each bed reads as one colour.
		var flower := GARDEN_FLOWERS[(_hash(seed_value, at, "bed%d" % bed)) % GARDEN_FLOWERS.size()]
		bed += 1
		var count := maxi(floori(2.0 * half / FLOWER_STEP_M), 1)
		for n in count + 1:
			var spot := at + across * offset + along * lerpf(-half, half, float(n) / maxf(count, 1))
			var h := _hash(seed_value, spot, "flower")
			out.append(
				{
					"asset": flower,
					"at": spot,
					"yaw": float(h % 6283) / 1000.0,
					"scale": 0.9 + float((h >> 12) % 31) / 100.0,
				}
			)
	var shrubs := 1 + _hash(seed_value, at, "shrubs") % 2
	for k in shrubs:
		var spot := at + Vector2.from_angle(turn + PI * 0.5 + k * 2.4) * radius * 0.95
		var h := _hash(seed_value, spot, "shrub")
		out.append(
			{
				"asset": GARDEN_SHRUBS[h % GARDEN_SHRUBS.size()],
				"at": spot,
				"yaw": float((h >> 4) % 6283) / 1000.0,
				"scale": 1.0,
			}
		)
	return out


## Offsets -reach..reach `pitch` apart, centred on 0 when the count is odd.
static func _offsets(reach: float, pitch: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var count := floori(2.0 * reach / pitch) + 1
	var start := -0.5 * pitch * (count - 1)
	for n in count:
		out.append(start + n * pitch)
	return out


static func _stroke(surface: String, from: Vector2, to: Vector2, radius: float) -> Dictionary:
	return SettlementGroundIO.snapped_stroke(
		{"surface": surface, "from": from, "to": to, "radius": radius, "seconds": SECONDS}
	)


static func _same_stroke(a: Dictionary, b: Dictionary) -> bool:
	var tolerance := VillagePlazas.STROKE_TOLERANCE_M
	return (
		str(a["surface"]) == str(b["surface"])
		and (a["from"] as Vector2).distance_to(b["from"]) < tolerance
		and (a["to"] as Vector2).distance_to(b["to"]) < tolerance
		and absf(float(a["radius"]) - float(b["radius"])) < tolerance
	)


static func _prop(
	prop: String, at: Vector2, yaw: float, scale: float, roll: int, slot: String
) -> Dictionary:
	return {
		"prop": prop,
		"position": Vector2(snappedf(at.x, 0.01), snappedf(at.y, 0.01)),
		"yaw": snappedf(wrapf(yaw, -PI, PI), 0.001),
		"scale": scale,
		"seed": absi(roll) % ProcgenSettlement.VARIANTS,
		"slot": slot,
		"rule": "field",
		"pinned": false,
	}


## A non-negative integer hash of the seed, a place held to a centimetre and a salt.
static func _hash(seed_value: int, at: Vector2, salt: String) -> int:
	return absi(hash([seed_value, roundi(at.x * 100.0), roundi(at.y * 100.0), salt]))
