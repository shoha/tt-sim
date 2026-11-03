class_name VillageFurnishings
extends RefCounted

## Pure rules for touching the furnishings of a dressed village (topic villages4,
## docs/systems/villages.md section 14): which standing piece a pointer is over, what may be swapped
## for it, where a piece may be put, and the record a change leaves. The record's three override
## lists do the saving (Settlement.removed, swapped, pinned; SettlementPlan applies them), so this
## adds no format: a removed piece is a slot name, a swapped one a slot and a prop, a moved, turned
## or re-rolled one a pin (its whole placement, so it survives a re-dress of the same character).
## A piece is a row of AuthoredSettlements.standing: {"item" (a SettlementPlan placement), "y"}.

## The nearest a pointer's reach floor is to a piece, in metres: a barrel is small on screen.
const PICK_FLOOR_M := 0.45
## A pointer within this share of a piece's drawn radius (plus the caller's pixel pad) is over it.
const PICK_SHARE := 0.9
## A turn notch, radians (15 degrees); Shift turns a quarter.
const TURN_STEP := TAU / 24.0
## Two pieces keep at least this share of their radii apart (the plan keeps 0.7 plus 0.2 m).
const CROWD_SHARE := 0.6
## The reasons a piece may not stand at a place (plain words: reason_text).
const WET := &"water"
const STEEP := &"steep"
const BUILDING := &"building"
const REACH := &"reach"
const BRIDGE := &"bridge"
const CROWDED := &"crowded"
const FULL := &"full"
const OUTSIDE := &"outside"

## Kit name -> the rule ids of its plaza.centre slot (is_centre_piece), cached.
static var _centre_rules: Dictionary = {}


## The sentence-case name of prop `prop` ("market_stall" is "Market stall").
static func label_of(prop: String) -> String:
	var words := prop.replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


## A field's own piece (a scarecrow, a haystack, skeps; slot "f<k>:..."): it can be taken away but
## not moved, swapped or turned, since it stands where its field puts it.
static func is_field_piece(slot: String) -> bool:
	var head := slot.get_slice(":", 0)
	return head.length() > 1 and head.begins_with("f") and head.substr(1).is_valid_int()


## The rule id inside a slot name ("w3l:l2/door_barrel/d0r" is "door_barrel"), or "".
static func rule_of(slot: String) -> String:
	var parts := slot.get_slice(":", 1).split("/")
	return parts[1] if parts.size() >= 3 else ""


## The index of the plaza whose piece `slot` is ("w1l:p0/square_stalls/r1" is plaza 0), or -1 for a
## piece of a lot, a junction or a field. A plaza's piece stays inside its plaza.
static func plaza_of(slot: String) -> int:
	var owner := slot.get_slice(":", 1).get_slice("/", 0)
	if owner.length() > 1 and owner.begins_with("p") and owner.substr(1).is_valid_int():
		return int(owner.substr(1))
	return -1


## The plaza's centrepiece (a market's well, rule slot "plaza.centre") is the plaza's own heart: the
## pointer passes through it, so a press there picks, moves and sizes the plaza as before, and the
## piece itself is left to the kit.
static func is_centre_piece(kit_name: String, slot: String) -> bool:
	if not _centre_rules.has(kit_name):
		var ids: Array[String] = []
		for rule: Dictionary in ProcgenSettlement.kit_named(kit_name).get("rules", []):
			if str(rule.get("slot", "")) == "plaza.centre":
				ids.append(str(rule.get("id", "")))
		_centre_rules[kit_name] = ids
	return (_centre_rules[kit_name] as Array).has(rule_of(slot))


## How far from its origin piece `item` is drawn, metres (the clearance radius at the drawn scale).
static func drawn_radius(item: Dictionary) -> float:
	return ProcgenPropStyles.radius_of(str(item["prop"])) * SettlementBake.visual_scale(item)


## The row of `rows` under map point `p`, or {}: the one whose pointer distance, as a share of its
## reach, is least. `pad_m` widens every piece's reach (a few pixels, in metres, from the camera).
static func pick(rows: Array[Dictionary], p: Vector2, pad_m: float = 0.0) -> Dictionary:
	var best := {}
	var best_share := INF
	for row in rows:
		var item: Dictionary = row["item"]
		var reach := maxf(drawn_radius(item) * PICK_SHARE, PICK_FLOOR_M) + pad_m
		var share := p.distance_to(item["position"] as Vector2) / reach
		if share <= 1.0 and share < best_share:
			best_share = share
			best = row
	return best


## The props piece `item` of a `kit` village may be swapped for: every prop another rule of the
## same slot kind of the kit draws (a door's barrel may become a crate or a bench), in the kit's own
## order, the piece's own prop included so a caller can cycle. [] for a field's piece or an unknown
## kit; a one-entry list means nothing else belongs there.
static func swap_choices(kit_name: String, item: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var slot := str(item["slot"])
	var kit := ProcgenSettlement.kit_named(kit_name)
	if kit.is_empty() or is_field_piece(slot):
		return out
	var rule_id := rule_of(slot)
	var kind := ""
	for rule: Dictionary in kit.get("rules", []):
		if str(rule.get("id", "")) == rule_id:
			kind = str(rule.get("slot", ""))
	if kind == "":
		return out
	for rule: Dictionary in kit.get("rules", []):
		if str(rule.get("slot", "")) != kind:
			continue
		for entry: Dictionary in rule.get("pick", []):
			var prop := str(entry.get("prop", ""))
			if ProcgenProps.NAMES.has(prop) and not out.has(prop):
				out.append(prop)
	var own := str(item["prop"])
	if not out.has(own):
		out.append(own)
	return out


## The prop after `current` in `choices` (wrapping), starting the search at the next one and giving
## the first for which `fits` (a Callable taking a prop name) is true; "" when none but `current`
## fits.
static func next_choice(choices: Array[String], current: String, fits: Callable) -> String:
	var start := choices.find(current)
	for step in range(1, choices.size()):
		var prop := choices[(start + step) % choices.size()]
		if fits.call(prop):
			return prop
	return ""


# --- where a piece may stand ------------------------------------------------------------------


## Why a piece of prop `prop` drawn at scale `scale` (the plan's, before the visual factor) may not
## stand at map point `at` of village `village`, as one of the reason names above, or &"". `rows`
## are the village's standing pieces; the one named `slot` is the piece itself and ignored. `plans`
## is VillageFieldGround.footprints(doc), made once by the caller. Water, ground steeper than the
## furnishings layer's own limit, a house, a bridge's deck and landings, too far from every
## street or plaza of the village and another piece's clearance each refuse; the layer would
## have skipped the piece on the first three anyway.
static func problem(
	doc: MapDocument,
	village: int,
	rows: Array[Dictionary],
	slot: String,
	prop: String,
	scale: float,
	at: Vector2,
	plans: Array[PackedVector2Array]
) -> StringName:
	var held := doc.settlement(village)
	if held == null or VillagePlazas.distance_to(doc, held, at) > VillagePlazas.VILLAGE_REACH_M:
		return REACH
	var plaza := plaza_of(slot)
	if plaza >= 0 and plaza < held.plazas.size():
		var disc: Dictionary = held.plazas[plaza]
		if at.distance_to(disc["at"] as Vector2) > float(disc["radius"]):
			return OUTSIDE
	var probe := {"prop": prop, "scale": scale, "slot": slot}
	var radius := drawn_radius(probe)
	var reach := AuthoredSettlements.footprint_reach(prop, SettlementBake.visual_scale(probe))
	if VillageFieldGround.covers_building(plans, at, radius):
		return BUILDING
	if VillageDryGround.in_corridors(at, VillageDryGround.crossing_corridors(doc), reach):
		return BRIDGE
	for row in rows:
		var other: Dictionary = row["item"]
		if str(other["slot"]) == slot:
			continue
		var gap := at.distance_to(other["position"] as Vector2)
		if gap < (radius + drawn_radius(other)) * CROWD_SHARE:
			return CROWDED
	var east := Vector2(reach, 0.0)
	var south := Vector2(0.0, reach)
	var five := PackedVector2Array([at, at + east, at - east, at + south, at - south])
	var heights := WaterGeometry.grounds_at(doc, five)
	var rise := maxf(absf(heights[1] - heights[2]), absf(heights[3] - heights[4]))
	if rise / (reach * 2.0) > AuthoredSettlements.SLOPE_LIMIT:
		return STEEP
	if VillageDryGround.has_water(doc):
		var ring := VillageDryGround.prop_ring(at, reach)
		var near := Rect2(ring[0], Vector2.ZERO)
		for point in ring:
			near = near.expand(point)
		var wet := VillageDryGround.wet_flags(doc, ring, near.grow(1.0))
		for flag in wet:
			if flag != 0:
				return WET
	return &""


## The words for a refusal, as a toast.
static func reason_text(reason: StringName) -> String:
	match reason:
		WET:
			return "That piece cannot stand in water: put it on dry ground."
		STEEP:
			return "That piece needs level ground: that slope is too steep."
		BUILDING:
			return "That piece cannot stand inside a building: put it on open ground."
		REACH:
			return "That is too far from the village: a piece stays near its street."
		BRIDGE:
			return "That piece would block a bridge: keep the crossing clear."
		CROWDED:
			return "That is too close to another piece."
		OUTSIDE:
			return "Keep it inside the plaza: that piece belongs to the square."
		FULL:
			return "A village keeps at most %d hand-placed or swapped pieces." % Settlement.MAX_OVERRIDES
	return "That piece cannot go there."


## The few words on the pill over a refused place.
static func short_reason(reason: StringName) -> String:
	match reason:
		WET:
			return "Too wet: needs dry ground"
		STEEP:
			return "Too steep: needs level ground"
		BUILDING:
			return "Over a building: put it on open ground"
		REACH:
			return "Too far from the village"
		BRIDGE:
			return "On the bridge: keep it clear"
		CROWDED:
			return "Too close to another piece"
		OUTSIDE:
			return "Keep it inside the plaza"
	return "A piece cannot go there"


# --- the record a change leaves (copies; the editor puts them in one history entry) -------------


## `held` with the piece `slot` taken away (its swap and pin forgotten with it). Null when the
## village is already at the override cap or the piece is already removed.
static func with_removed(held: Settlement, slot: String) -> Settlement:
	if held.removed.has(slot):
		return null
	var changed := held.copy()
	if changed.removed.size() >= Settlement.MAX_OVERRIDES:
		return null
	changed.removed.append(slot)
	changed.swapped.erase(slot)
	changed.pinned.erase(slot)
	return changed


## `held` with piece `slot` pinned as `pin` (SettlementPlan.pin_of's shape). Null at the cap.
static func with_pin(held: Settlement, slot: String, pin: Dictionary) -> Settlement:
	var changed := held.copy()
	if not changed.pinned.has(slot) and changed.pinned.size() >= Settlement.MAX_OVERRIDES:
		return null
	var stored := pin.duplicate()
	var at: Vector2 = pin["at"]
	stored["at"] = Vector2(snappedf(at.x, 0.01), snappedf(at.y, 0.01))
	stored["yaw"] = snappedf(wrapf(float(pin["yaw"]), -PI, PI), 0.001)
	stored["scale"] = clampf(snappedf(float(pin["scale"]), 0.01), 0.3, 3.0)
	changed.pinned[slot] = stored
	return changed


## `held` with piece `slot` swapped for `prop`: a pinned piece changes the prop of its pin, any
## other takes a `swapped` entry. Null at the cap.
static func with_swapped(held: Settlement, slot: String, prop: String) -> Settlement:
	if held.pinned.has(slot):
		var pin: Dictionary = (held.pinned[slot] as Dictionary).duplicate()
		pin["prop"] = prop
		return with_pin(held, slot, pin)
	var changed := held.copy()
	if not changed.swapped.has(slot) and changed.swapped.size() >= Settlement.MAX_OVERRIDES:
		return null
	changed.swapped[slot] = prop
	return changed


## `held` with piece `slot` back where its rule puts it (no pin). Null when it was not pinned.
static func with_unpinned(held: Settlement, slot: String) -> Settlement:
	if not held.pinned.has(slot):
		return null
	var changed := held.copy()
	changed.pinned.erase(slot)
	return changed


## `held` with the removed piece `slot` back. Null when it was not removed.
static func with_restored_one(held: Settlement, slot: String) -> Settlement:
	var at := held.removed.find(slot)
	if at < 0:
		return null
	var changed := held.copy()
	changed.removed.remove_at(at)
	return changed


## `held` with every removed piece back. Null when none was removed.
static func with_restored(held: Settlement) -> Settlement:
	if held.removed.is_empty():
		return null
	var changed := held.copy()
	changed.removed = PackedStringArray()
	return changed
