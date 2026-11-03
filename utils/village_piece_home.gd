class_name VillagePieceHome
extends RefCounted

## Pure: where a furnishing of a dressed village belongs, so a moved piece keeps to it (topic
## villages5, docs/systems/villages.md section 14). A plaza's piece stays inside its plaza disc, a
## lot's piece on its own lot, a street's piece on its street; a field's piece cannot be moved, and
## a piece whose home is gone (a pin whose lot was rebuilt away) keeps only the village's reach.
##
## The home is read from the piece's slot name, which is where the plan put it: "w3l:l2/door_barrel/
## d0r" is side "w3l" (street 3, its left side), owner "l2" (that side's lot 2), rule "door_barrel".
## The owner says plaza ("p<k>") or lot ("l<k>"); the rule's slot kind in the kit says whether a
## lot-owned piece is the lot's (a door's barrel, a yard's woodpile, a side gap's stores) or the
## street's (a lamp on the street edge is owned by the lot whose frontage it stands before, but it
## belongs to the street). A pin keeps its slot, so a moved piece keeps its home.
##
## Geometry is the frontage record's (ProcgenFrontage): a point is measured along the facade line
## (arc length `s`, extended straight past either end) and across it (metres towards the street,
## negative behind the facades). A lot is its range of the line, the side gap after it included
## (the frontage gives that gap to the lot before it), from its building's back yard to the kerb.
## A street is every side of it: along each facade line, from the facades across the street to the
## facades opposite, plus a junction's corner round each junction.

const PLAZA := &"plaza"
const LOT := &"lot"
const STREET := &"street"
## No home: the village's reach is the only bound.
const FREE := &""
## The kit slot kinds a lot's own pieces fill, and the street's.
const LOT_KINDS: Array[String] = ["beside_door", "side_gap", "front_yard", "back_yard"]
const STREET_KINDS: Array[String] = ["street_edge", "junction", "village_edge"]
## A lot reaches this far past its own lines (a barrel's foot may stand on the line itself).
const LOT_SLACK_M := 0.5
## A street piece may stand this far behind the facade line (a lamp against a wall), and this far
## past either end of the street (a village's gate stands at the end).
const STREET_BEHIND_M := 0.5
const STREET_END_M := 3.0
## A junction piece (a signpost) stands within this of the junction's point.
const JUNCTION_REACH_M := 5.0
## The home with no bound.
const FREE_HOME := {"kind": FREE}


## The kind of home of piece `slot` in a `kit_name` village: PLAZA, LOT, STREET or FREE.
static func kind_of(kit_name: String, slot: String) -> StringName:
	if VillageFurnishings.is_field_piece(slot):
		return FREE
	if VillageFurnishings.plaza_of(slot) >= 0:
		return PLAZA
	var rule_id := VillageFurnishings.rule_of(slot)
	var kind := ""
	for rule: Dictionary in ProcgenSettlement.kit_named(kit_name).get("rules", []):
		if str(rule.get("id", "")) == rule_id:
			kind = str(rule.get("slot", ""))
	if STREET_KINDS.has(kind):
		return STREET
	if LOT_KINDS.has(kind) and _lot_id(slot) != "":
		return LOT
	return FREE


## The home of piece `slot` of village `held` in `doc`: {"kind"} and what bounds it. PLAZA: "at",
## "radius". LOT: "frontage", "s0", "s1", "front", "back" (the range along and across). STREET:
## "bands" ([{"frontage", "across"}], one per side), "junctions" (points). FREE_HOME when the home
## is gone or the piece has none.
static func of(doc: MapDocument, held: Settlement, slot: String) -> Dictionary:
	if held == null:
		return FREE_HOME
	var kind := kind_of(held.kit, slot)
	if kind == PLAZA:
		var index := VillageFurnishings.plaza_of(slot)
		if index >= held.plazas.size():
			return FREE_HOME
		var disc: Dictionary = held.plazas[index]
		return {"kind": PLAZA, "at": disc["at"], "radius": float(disc["radius"])}
	if kind == FREE:
		return FREE_HOME
	var frontages := SettlementPlan.frontages_of(doc, held)
	if kind == LOT:
		return _lot_home(frontages, slot)
	return _street_home(doc, held, frontages)


## Whether map point `at` is inside `home` (FREE_HOME holds everything).
static func holds(home: Dictionary, at: Vector2) -> bool:
	match home.get("kind", FREE):
		PLAZA:
			return at.distance_to(home["at"] as Vector2) <= float(home["radius"])
		LOT:
			var fr: ProcgenFrontage = home["frontage"]
			var where := locate(fr, at)
			return (
				where.x >= float(home["s0"])
				and where.x <= float(home["s1"])
				and where.y >= -float(home["back"])
				and where.y <= float(home["front"])
			)
		STREET:
			for band: Dictionary in home["bands"]:
				var fr: ProcgenFrontage = band["frontage"]
				var where := locate(fr, at)
				if (
					where.x >= -STREET_END_M
					and where.x <= fr.length() + STREET_END_M
					and where.y >= -STREET_BEHIND_M
					and where.y <= float(band["across"])
				):
					return true
			for point: Vector2 in home["junctions"]:
				if at.distance_to(point) <= JUNCTION_REACH_M:
					return true
			return false
	return true


## The refusal (a VillageFurnishings reason) for putting a piece of `home` at `at`, or &"".
static func refusal(home: Dictionary, at: Vector2) -> StringName:
	if holds(home, at):
		return &""
	match home.get("kind", FREE):
		PLAZA:
			return VillageFurnishings.OUTSIDE
		LOT:
			return VillageFurnishings.OFF_LOT
		STREET:
			return VillageFurnishings.OFF_STREET
	return &""


## Point `p` measured on frontage `fr`: x the arc length along its facade line of the nearest point
## (the first and last segments run on straight past the ends, so a point beyond an end has an
## arc length below 0 or above the length), y the distance across, positive towards the street.
static func locate(fr: ProcgenFrontage, p: Vector2) -> Vector2:
	var line := fr.line
	var best := INF
	var out := Vector2(0.0, 0.0)
	var run := 0.0
	var last := line.size() - 2
	for i in line.size() - 1:
		var a := line[i]
		var seg := line[i + 1] - a
		var span := seg.length()
		if span < 1e-6:
			continue
		var t := (p - a).dot(seg) / (span * span)
		t = clampf(t, -INF if i == 0 else 0.0, INF if i == last else 1.0)
		var foot := a + seg * t
		var gap := p.distance_to(foot)
		if gap < best:
			best = gap
			var dir := seg / span
			var normal := Vector2(-dir.y, dir.x) * float(fr.street_side)
			out = Vector2(run + t * span, (p - foot).dot(normal))
		run += span
	return out


static func _lot_id(slot: String) -> String:
	var owner := slot.get_slice(":", 1).get_slice("/", 0)
	if owner.length() > 1 and owner.begins_with("l") and owner.substr(1).is_valid_int():
		return owner
	return ""


static func _lot_home(frontages: Array[ProcgenFrontage], slot: String) -> Dictionary:
	var side := slot.get_slice(":", 0)
	var lot_id := _lot_id(slot)
	for fr in frontages:
		if fr.key != side:
			continue
		for i in fr.lots.size():
			var lot: Dictionary = fr.lots[i]
			if str(lot["id"]) != lot_id:
				continue
			# The side gap after a lot is the lot's (ProcgenFrontage), so its range runs on to the
			# next lot's start.
			var end := float(lot["s1"])
			if i + 1 < fr.lots.size():
				end = maxf(end, float(fr.lots[i + 1]["s0"]))
			return {
				"kind": LOT,
				"frontage": fr,
				"s0": float(lot["s0"]) - LOT_SLACK_M,
				"s1": end + LOT_SLACK_M,
				"front": fr.gap_m + LOT_SLACK_M,
				"back": float(lot["depth_m"]) + float(lot.get("yard_m", 0.0)) + LOT_SLACK_M,
			}
	return FREE_HOME


## Every side of the village's street. Across a live street a side reaches the facades opposite
## (twice the street's setback); a frozen village keeps no street, so a side reaches over its own
## strip and the narrowest road.
static func _street_home(
	doc: MapDocument, held: Settlement, frontages: Array[ProcgenFrontage]
) -> Dictionary:
	if frontages.is_empty():
		return FREE_HOME
	var wall := doc.wall(held.source) if held.source > 0 else null
	var bands: Array[Dictionary] = []
	var junctions: Array[Vector2] = []
	for fr in frontages:
		var across := fr.gap_m + 2.0 * StreetProfile.ROAD_HALF_MIN_M
		if wall != null:
			across = maxf(across, 2.0 * wall.height_m)
		bands.append({"frontage": fr, "across": across + STREET_BEHIND_M})
		for junction: Dictionary in fr.junctions:
			junctions.append(junction["at"])
	return {"kind": STREET, "bands": bands, "junctions": junctions}
