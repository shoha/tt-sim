class_name SettlementPlan
extends RefCounted

## Pure: where the furnishings of a Settlement stand. The frontages (SettlementFrontage, or the
## record's frozen ones) go through procgen's ProcgenSettlement.place, then the record's
## overrides apply: `removed` slots drop, `swapped` slots take another prop, `pinned` slots are
## drawn as pinned. Every placement is {"prop", "position" (map XZ), "yaw", "scale", "seed" (the
## variant 0..3), "slot" (unique in the settlement, "<side key>:<procgen slot>" so a slot keeps
## its name when other lots change), "rule", "pinned": bool}. The same record on the same lots
## gives the same list on every peer.


## The frontages that `settlement` dresses in `doc`: its street's, or the frozen ones. [] when
## its street is gone.
static func frontages_of(doc: MapDocument, settlement: Settlement) -> Array[ProcgenFrontage]:
	var out: Array[ProcgenFrontage] = []
	if settlement.source > 0:
		var wall := doc.wall(settlement.source)
		if wall != null and wall.is_row():
			out.assign(SettlementFrontage.of_street(doc, wall))
		return out
	for data in settlement.frozen:
		var frontage := ProcgenFrontage.from_dict(data)
		if frontage.problems().is_empty():
			out.append(frontage)
	return out


## The placements of `settlement` on `frontages`, overrides applied, in rule order per side.
static func place(settlement: Settlement, frontages: Array[ProcgenFrontage]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kit := ProcgenSettlement.kit_named(settlement.kit)
	if kit.is_empty():
		return out
	for frontage in frontages:
		for placement in ProcgenSettlement.place(
			frontage, kit, settlement.seed_value, settlement.wealth, settlement.density
		):
			var slot := "%s:%s" % [frontage.key, placement["slot"]]
			if settlement.removed.has(slot):
				continue
			var item := placement.duplicate()
			item["slot"] = slot
			item["pinned"] = false
			if settlement.swapped.has(slot):
				item["prop"] = String(settlement.swapped[slot])
			if settlement.pinned.has(slot):
				item = _pinned(slot, settlement.pinned[slot])
			out.append(item)
	# A pin whose derived placement is gone (a re-dress, a moved lot) is still drawn.
	var seen := {}
	for item in out:
		seen[item["slot"]] = true
	for slot: Variant in settlement.pinned:
		if not seen.has(slot) and not settlement.removed.has(slot):
			out.append(_pinned(str(slot), settlement.pinned[slot]))
	return out


## place() for the frontages `doc` gives `settlement`.
static func placements(doc: MapDocument, settlement: Settlement) -> Array[Dictionary]:
	return place(settlement, frontages_of(doc, settlement))


## The pin record of placement `item` (a place() item), as Settlement.pinned stores it.
static func pin_of(item: Dictionary) -> Dictionary:
	return {
		"prop": item["prop"],
		"at": item["position"],
		"yaw": item["yaw"],
		"scale": item["scale"],
		"seed": item["seed"],
	}


## One "slot prop x z yaw scale seed" line per placement (centimetres, milliradians, hundredths):
## the text the golden digests hash.
static func lines_of(items: Array[Dictionary]) -> PackedStringArray:
	var lines := PackedStringArray()
	for item in items:
		var at: Vector2 = item["position"]
		(
			lines
			. append(
				(
					"%s %s %d %d %d %d %d"
					% [
						item["slot"],
						item["prop"],
						roundi(at.x * 100.0),
						roundi(at.y * 100.0),
						roundi(float(item["yaw"]) * 1000.0),
						roundi(float(item["scale"]) * 100.0),
						int(item["seed"]),
					]
				)
			)
		)
	return lines


static func digest(items: Array[Dictionary]) -> String:
	return "\n".join(lines_of(items)).md5_text()


static func _pinned(slot: String, pin: Dictionary) -> Dictionary:
	return {
		"prop": pin["prop"],
		"position": pin["at"],
		"yaw": pin["yaw"],
		"scale": pin["scale"],
		"seed": pin["seed"],
		"slot": slot,
		"rule": "pinned",
		"pinned": true,
	}
