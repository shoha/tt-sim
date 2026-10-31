class_name VillagePlazas
extends RefCounted

## The pure half of the Village tool (VillageBrush, docs/systems/villages.md section 10): which
## plaza disc a point is on, which village a press belongs to, how big a drag makes a plaza, which
## paint stroke of a record is a given plaza's paving, and the state the tool's pane shows. No
## scene tree, no editor: it reads a MapDocument and its Settlement records and returns values.
##
## A plaza is `{"at": Vector2 (map XZ), "radius": metres}` in `Settlement.plazas`; its paving is the
## one disc stroke SettlementGround lays (`from == to == at`, radius 1.12 times the plaza's), which
## is how a resize or a removal finds exactly that stroke in the record's `ground` list.

## A click (or a drag shorter than this) lays a plaza this wide; a longer drag sizes it.
const DEFAULT_RADIUS_M := 5.0
const DRAG_MIN_M := 1.5
## One bracket key or Shift+wheel notch on a plaza.
const RADIUS_STEP_M := 1.0
## The band round a plaza's rim where a press grabs the edge, at least (the brush widens it to the
## pixels the author sees).
const RIM_BAND_M := 0.9
## A press this far from a village's street or plazas does not belong to it.
const VILLAGE_REACH_M := 60.0
## The picked village keeps a press that is this much nearer to another village.
const PICKED_SLACK_M := 6.0
## The paving disc is this much wider than the plaza (SettlementGround).
const PAVING_FACTOR := 1.12
## The match of a stroke to a plaza (both are held to a hundredth).
const STROKE_TOLERANCE_M := 0.02

const PART_RIM := &"rim"
const PART_INSIDE := &"inside"

## Each kit's ground block, read once (the kit file is parsed on a miss).
static var _grounds: Dictionary = {}


## `radius` held to the plaza range, in tenths of a metre.
static func clamp_radius(radius: float) -> float:
	return clampf(
		snappedf(radius, 0.1), Settlement.PLAZA_MIN_RADIUS_M, Settlement.PLAZA_MAX_RADIUS_M
	)


## The radius a drag from `centre` to `to` makes: a click or a short drag is DEFAULT_RADIUS_M.
static func radius_for_drag(centre: Vector2, to: Vector2) -> float:
	var reach := centre.distance_to(to)
	return DEFAULT_RADIUS_M if reach < DRAG_MIN_M else clamp_radius(reach)


## The radius a drag on the rim of a plaza of `start_radius` makes, the pointer having been
## `grabbed_at` metres from the centre when it grabbed and being `now_at` now (so the rim follows
## the pointer without jumping where it was grabbed).
static func radius_for_rim_drag(start_radius: float, grabbed_at: float, now_at: float) -> float:
	return clamp_radius(start_radius + now_at - grabbed_at)


## The plaza under map point `p` among the plazas of `settlements`, as
## `{"settlement": id, "index": plaza index, "part": PART_RIM or PART_INSIDE}`, or {}. The rim band
## (`rim_m` each side of the edge) wins over the inside; among several the nearest rim, or the
## smallest disc, wins.
static func pick(settlements: Array[Settlement], p: Vector2, rim_m: float) -> Dictionary:
	var best := {}
	var best_score := INF
	for settlement in settlements:
		for index in settlement.plazas.size():
			var plaza := settlement.plazas[index]
			var reach := p.distance_to(plaza["at"] as Vector2)
			var radius := float(plaza["radius"])
			if absf(reach - radius) <= rim_m and absf(reach - radius) < best_score:
				best_score = absf(reach - radius)
				best = {"settlement": settlement.id, "index": index, "part": PART_RIM}
	if not best.is_empty():
		return best
	best_score = INF
	for settlement in settlements:
		for index in settlement.plazas.size():
			var plaza := settlement.plazas[index]
			var radius := float(plaza["radius"])
			if p.distance_to(plaza["at"] as Vector2) < radius and radius < best_score:
				best_score = radius
				best = {"settlement": settlement.id, "index": index, "part": PART_INSIDE}
	return best


## The lines that locate `settlement`: its street's centre line, or the lines of its frozen
## frontages once the street was split.
static func lines(doc: MapDocument, settlement: Settlement) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var wall := doc.wall(settlement.source) if settlement.source > 0 else null
	if wall != null:
		out.append(wall.points)
	for frontage in settlement.frozen:
		var line := PackedVector2Array()
		for pair in frontage.get("line", []):
			line.append(Vector2(float(pair[0]), float(pair[1])))
		if line.size() >= 2:
			out.append(line)
	return out


## How far map point `p` is from `settlement`: from its street line or the edge of one of its
## plazas, whichever is nearer (0 on a plaza); INF for a settlement with neither.
static func distance_to(doc: MapDocument, settlement: Settlement, p: Vector2) -> float:
	var best := INF
	for line in lines(doc, settlement):
		for k in line.size() - 1:
			var near := Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])
			best = minf(best, p.distance_to(near))
	for plaza in settlement.plazas:
		best = minf(best, maxf(p.distance_to(plaza["at"] as Vector2) - float(plaza["radius"]), 0.0))
	return best


## The id of the village a press at map point `p` belongs to: the nearest village within `reach`,
## except that the picked one (`preferred`) keeps the press while it is no more than
## PICKED_SLACK_M farther than the nearest. -1 when no village is within `reach`.
static func village_for(
	doc: MapDocument, p: Vector2, preferred: int, reach: float = VILLAGE_REACH_M
) -> int:
	var best := -1
	var best_distance := reach
	for settlement in doc.settlements:
		var away := distance_to(doc, settlement, p)
		if away <= best_distance:
			best_distance = away
			best = settlement.id
	var held := doc.settlement(preferred) if preferred > 0 else null
	if held != null and best >= 0 and distance_to(doc, held, p) <= best_distance + PICKED_SLACK_M:
		return preferred
	return best


## The index in `ground` (a record's paint strokes) of the disc stroke that paves `plaza`, or -1
## when there is none (a plaza added with paving off, one refused for wet or steep ground, or a
## record from before the paving was listed).
static func stroke_index(ground: Array[Dictionary], plaza: Dictionary) -> int:
	var at: Vector2 = plaza["at"]
	var radius := snappedf(float(plaza["radius"]) * PAVING_FACTOR, SettlementGroundIO.STEP)
	for index in range(ground.size() - 1, -1, -1):
		var stroke := ground[index]
		var from: Vector2 = stroke["from"]
		var to: Vector2 = stroke["to"]
		if (
			from.distance_to(to) < STROKE_TOLERANCE_M
			and from.distance_to(at) < STROKE_TOLERANCE_M
			and absf(float(stroke["radius"]) - radius) < STROKE_TOLERANCE_M
		):
			return index
	return -1


## What the pane shows for the picked village and plaza (either -1 for none), from `doc`:
## `villages` ([{id, kit, label}] in id order), `village` (the picked id), `kit`, `plazas` (how
## many the village holds), `plaza` (the picked index), `radius`, `road` and `plaza_ground` (the
## kit's surfaces named for the author) and `full` (the village holds as many plazas as it may).
static func state_of(doc: MapDocument, village: int, plaza: int) -> Dictionary:
	var villages: Array[Dictionary] = []
	for settlement in doc.settlements:
		villages.append(
			{"id": settlement.id, "kit": settlement.kit, "label": kit_label(settlement.kit)}
		)
	var state := {
		"villages": villages,
		"village": -1,
		"kit": "",
		"plazas": 0,
		"plaza": -1,
		"radius": 0.0,
		"road": "",
		"plaza_ground": "",
		"full": false,
	}
	var held := doc.settlement(village) if village > 0 else null
	if held == null:
		return state
	state["village"] = held.id
	state["kit"] = held.kit
	state["plazas"] = held.plazas.size()
	state["full"] = held.plazas.size() >= Settlement.MAX_PLAZAS
	var ground := ground_of(held.kit)
	state["road"] = surface_name(str(ground.get("road", "")))
	state["plaza_ground"] = surface_name(str(ground.get("plaza", "")))
	if plaza >= 0 and plaza < held.plazas.size():
		state["plaza"] = plaza
		state["radius"] = float(held.plazas[plaza]["radius"])
	return state


## The ground block of kit `kit` ({"road", "door_path", "plaza"}: palette surface ids), cached.
static func ground_of(kit: String) -> Dictionary:
	if not _grounds.has(kit):
		_grounds[kit] = ProcgenSettlement.ground_of(ProcgenSettlement.kit_named(kit))
	return _grounds[kit]


## The author-facing name of kit `kit` ("Market town"), or the kit id spelled out.
static func kit_label(kit: String) -> String:
	for item in SettlementSection.CHIPS:
		if item["kit"] == kit:
			return String(item["label"])
	return kit.capitalize()


## The author-facing name of palette surface `surface` ("" for none).
static func surface_name(surface: String) -> String:
	return "" if surface == "" else AuthoringPanel.surface_label(surface)
