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
## A dragged plaza's centre is held to this step.
const MOVE_STEP_M := 0.1
## The paving disc is this much wider than the plaza (SettlementGround).
const PAVING_FACTOR := 1.12
## The match of a stroke to a plaza (both are held to a hundredth).
const STROKE_TOLERANCE_M := 0.02
## The smallest plaza the tool makes, the record's own floor.
const MIN_RADIUS_M := Settlement.PLAZA_MIN_RADIUS_M
## A kit whose edge furnishings crowd a small plaza out of sight has a larger floor in the tool (the
## record still takes anything): the market town's stalls line a plaza's edge every 7 m, and at
## 5 m they hide the cobble while at 6 m it reads paved (villagetool2, capture j_market_5_6_7).
## A click lays the larger of DEFAULT_RADIUS_M and this.
const KIT_MIN_RADIUS_M := {"market_town": 6.0}
## The four handle dots on a plaza's rim sit at these turns from +X (a quarter apart).
const HANDLE_ANGLE := 0.4

const PART_RIM := &"rim"
const PART_INSIDE := &"inside"

## Each kit's ground block, read once (the kit file is parsed on a miss).
static var _grounds: Dictionary = {}


## The smallest plaza the tool makes for kit `kit` ("" for any kit: the record's floor).
static func min_radius(kit: String = "") -> float:
	return float(KIT_MIN_RADIUS_M.get(kit, MIN_RADIUS_M))


## `radius` held to the plaza range of kit `kit`, in tenths of a metre.
static func clamp_radius(radius: float, kit: String = "") -> float:
	return clampf(snappedf(radius, 0.1), min_radius(kit), Settlement.PLAZA_MAX_RADIUS_M)


## The four handle dots of a plaza at `at` of `radius`, on its rim.
static func handle_points(at: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 4:
		out.append(at + Vector2.from_angle(TAU * k / 4.0 + HANDLE_ANGLE) * radius)
	return out


## The radius a drag from `centre` to `to` makes for kit `kit`: a click or a short drag is
## DEFAULT_RADIUS_M (or the kit's floor, min_radius, when that is larger).
static func radius_for_drag(centre: Vector2, to: Vector2, kit: String = "") -> float:
	var reach := centre.distance_to(to)
	return clamp_radius(DEFAULT_RADIUS_M if reach < DRAG_MIN_M else reach, kit)


## The radius a drag on the rim of a plaza of `start_radius` makes, the pointer having been
## `grabbed_at` metres from the centre when it grabbed and being `now_at` now (so the rim follows
## the pointer without jumping where it was grabbed), held at `floor_m` or above.
static func radius_for_rim_drag(
	start_radius: float, grabbed_at: float, now_at: float, floor_m: float = MIN_RADIUS_M
) -> float:
	var radius := snappedf(start_radius + now_at - grabbed_at, 0.1)
	return clampf(radius, floor_m, Settlement.PLAZA_MAX_RADIUS_M)


## The plaza under map point `p` among the plazas of `settlements`, as
## `{"settlement": id, "index": plaza index, "part": PART_RIM or PART_INSIDE}`, or {}. The rim band
## (`rim_m` each side of the edge) wins over the inside; among several the nearest rim, or the
## smallest disc, wins. Within `handle_m` of one of a plaza's handle dots (handle_points) is on
## its rim too: the dots are the larger target the author aims at. `group` names the record's
## disc list read (&"plazas", or &"fields" for VillageFields.pick_any).
static func pick(
	settlements: Array[Settlement],
	p: Vector2,
	rim_m: float,
	handle_m: float = 0.0,
	group: StringName = &"plazas"
) -> Dictionary:
	var best := {}
	var best_score := INF
	for settlement in settlements:
		var discs: Array[Dictionary] = settlement.get(group)
		for index in discs.size():
			var plaza := discs[index]
			var reach := p.distance_to(plaza["at"] as Vector2)
			var radius := float(plaza["radius"])
			var score := absf(reach - radius)
			for dot in handle_points(plaza["at"], radius):
				if p.distance_to(dot) <= handle_m:
					score = minf(score, 0.0)
			if (score <= rim_m or score == 0.0) and score < best_score:
				best_score = score
				best = {"settlement": settlement.id, "index": index, "part": PART_RIM}
	if not best.is_empty():
		return best
	best_score = INF
	for settlement in settlements:
		var discs: Array[Dictionary] = settlement.get(group)
		for index in discs.size():
			var plaza := discs[index]
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


## Where `settlement`'s number is shown on the board: the middle of its first line (the street),
## else its first plaza's centre, else Vector2.INF.
static func anchor_of(doc: MapDocument, settlement: Settlement) -> Vector2:
	var found := lines(doc, settlement)
	if not found.is_empty():
		var line: PackedVector2Array = found[0]
		var half := 0.0
		for k in line.size() - 1:
			half += line[k].distance_to(line[k + 1])
		half *= 0.5
		for k in line.size() - 1:
			var step := line[k].distance_to(line[k + 1])
			if half <= step:
				return line[k].lerp(line[k + 1], half / maxf(step, 0.0001))
			half -= step
		return line[line.size() - 1]
	if not settlement.plazas.is_empty():
		return settlement.plazas[0]["at"]
	return Vector2.INF


## The author-facing name of village `id`, the one word the pane, the board and the hint share.
static func village_name(id: int) -> String:
	return "Village %d" % id


## How far map point `p` is from `settlement`: from its street line or the edge of one of its
## plazas, whichever is nearer (0 on a plaza); INF for a settlement with neither.
static func distance_to(doc: MapDocument, settlement: Settlement, p: Vector2) -> float:
	var best := INF
	for line in lines(doc, settlement):
		for k in line.size() - 1:
			var near := Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])
			best = minf(best, p.distance_to(near))
	for plaza in settlement.plazas + settlement.fields:
		best = minf(best, maxf(p.distance_to(plaza["at"] as Vector2) - float(plaza["radius"]), 0.0))
	return best


## The id of the village a press at map point `p` belongs to: the nearest village within `reach`,
## except that the picked one (`preferred`) keeps the press while it is no more than
## PICKED_SLACK_M farther than the nearest. -1 when no village is within `reach`.
static func village_for(
	doc: MapDocument, p: Vector2, preferred: int, reach: float = VILLAGE_REACH_M
) -> int:
	return _choose(doc, doc.settlements, p, preferred, reach)


static func _choose(
	doc: MapDocument, settlements: Array[Settlement], p: Vector2, preferred: int, reach: float
) -> int:
	var best := -1
	var best_distance := reach
	var held: Settlement = null
	for settlement in settlements:
		var away := distance_to(doc, settlement, p)
		if away <= best_distance:
			best_distance = away
			best = settlement.id
		if settlement.id == preferred:
			held = settlement
	if held != null and best >= 0 and distance_to(doc, held, p) <= best_distance + PICKED_SLACK_M:
		return preferred
	return best


## Whether a disc of `radius` at map point `at` would cross a plaza or field that stands in any
## village of `doc` (the ghost is not drawn across one).
static func overlaps_any(doc: MapDocument, at: Vector2, radius: float) -> bool:
	for settlement in doc.settlements:
		for disc in settlement.plazas + settlement.fields:
			if at.distance_to(disc["at"] as Vector2) < radius + float(disc["radius"]):
				return true
	return false


# --- moving a plaza ----------------------------------------------------------------------------


## True once a press that landed at `pressed_at` has been dragged to `now`: a plaza the press was
## inside moves from here on (a shorter press is a click that picks it).
static func is_move(pressed_at: Vector2, now: Vector2) -> bool:
	return pressed_at.distance_to(now) >= DRAG_MIN_M


## Where a plaza's centre is from the pointer when it is grabbed: held through the drag, so the
## disc follows the pointer without jumping to it.
static func grab_offset(centre: Vector2, pointer: Vector2) -> Vector2:
	return centre - pointer


## The centre a dragged plaza takes with the pointer at `pointer` and the grab offset `offset`,
## in tenths of a metre (like a drag's radius; the record then holds it to its own step).
static func moved_to(pointer: Vector2, offset: Vector2) -> Vector2:
	var at := pointer + offset
	return Vector2(snappedf(at.x, MOVE_STEP_M), snappedf(at.y, MOVE_STEP_M))


## The village plaza `index` of village `from` belongs to once it stands at `at`: the nearest
## village in reach by village_for's rule (the plaza's own keeps it while it is at most
## PICKED_SLACK_M farther), measured with the plaza itself taken out of its village, since its old
## place says nothing about the new one. -1 when no village is in reach.
static func destination_village(
	doc: MapDocument, from: int, index: int, at: Vector2, reach: float = VILLAGE_REACH_M
) -> int:
	var without: Array[Settlement] = []
	for settlement in doc.settlements:
		if settlement.id == from and index >= 0 and index < settlement.plazas.size():
			var trimmed := settlement.copy()
			trimmed.plazas.remove_at(index)
			without.append(trimmed)
		else:
			without.append(settlement)
	return _choose(doc, without, at, from, reach)


## Whether plaza `index` of village `from` may stand at map point `at`, and where it would belong:
## `{"village": id or -1, "reason": SettlementEditor.REFUSED_* or &""}`. Refused: no village in
## reach (REFUSED_REACH), the village it would join holds four plazas (REFUSED_FULL), its centre or
## a quarter of its rim in water (REFUSED_WATER), ground too steep across it (REFUSED_STEEP), or
## its disc over a building (REFUSED_BUILDING). `world` is SettlementGround.world_of and `plans`
## VillageFieldGround.footprints, built once by a caller that asks every frame.
static func move_problem(
	doc: MapDocument,
	from: int,
	index: int,
	at: Vector2,
	world: RefCounted,
	plans: Array[PackedVector2Array]
) -> Dictionary:
	var held := doc.settlement(from) if from > 0 else null
	# The refusal ids are SettlementEditor's, read by path so the authoring code stays off the
	# start-up graph (perf audit boot2).
	var editor: Variant = load("res://scenes/states/authoring/settlement_editor.gd")
	if held == null or index < 0 or index >= held.plazas.size():
		return {"village": -1, "reason": editor.REFUSED_STREET}
	var target := destination_village(doc, from, index, at)
	var out := {"village": target, "reason": &""}
	if target < 0:
		out["reason"] = editor.REFUSED_REACH
		return out
	if target != from and doc.settlement(target).plazas.size() >= Settlement.MAX_PLAZAS:
		out["reason"] = editor.REFUSED_FULL
		return out
	var radius := float(held.plazas[index]["radius"])
	match SettlementGround.plaza_problem(world, at, radius):
		"water":
			out["reason"] = editor.REFUSED_WATER
		"slope":
			out["reason"] = editor.REFUSED_STEEP
		"building":
			out["reason"] = editor.REFUSED_BUILDING
	if out["reason"] == &"" and VillageFieldGround.covers_building(plans, at, radius):
		out["reason"] = editor.REFUSED_BUILDING
	return out


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
## kit's surfaces named for the author), `full` (the village holds as many plazas as it may), and
## the boundary: `boundary` (the record's kind), `boundary_manual` (the author chose it) and
## `boundary_auto` (what the character and seed would draw: the Automatic choice's meaning).
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
		"sizing": false,
		"boundary": "",
		"boundary_manual": false,
		"boundary_auto": "",
	}
	var held := doc.settlement(village) if village > 0 else null
	if held == null:
		return state
	state["village"] = held.id
	state["kit"] = held.kit
	state["boundary"] = held.boundary
	state["boundary_manual"] = held.boundary_manual
	state["boundary_auto"] = VillageBoundary.kind_for(held.kit, held.seed_value)
	state["plazas"] = held.plazas.size()
	state["full"] = held.plazas.size() >= Settlement.MAX_PLAZAS
	var ground := ground_of(held.kit)
	state["road"] = surface_name(str(ground.get("road", "")))
	state["plaza_ground"] = surface_name(str(ground.get("plaza", "")))
	if plaza >= 0 and plaza < held.plazas.size():
		state["plaza"] = plaza
		state["radius"] = float(held.plazas[plaza]["radius"])
	return state


## `state` (state_of) while a drag is sizing a plaza to `radius` metres: the pane's size reads
## the drag live (`sizing` true, `radius` the preview) before anything is laid.
static func with_preview(state: Dictionary, radius: float) -> Dictionary:
	var out := state.duplicate()
	out["sizing"] = true
	out["radius"] = radius
	return out


## The ground block of kit `kit` ({"road", "door_path", "plaza"}: palette surface ids), cached.
static func ground_of(kit: String) -> Dictionary:
	if not _grounds.has(kit):
		var settlement: Variant = StructureProcgen.settlement()
		_grounds[kit] = settlement.ground_of(settlement.kit_named(kit))
	return _grounds[kit]


## The author-facing name of kit `kit` ("Market town"), or the kit id spelled out.
static func kit_label(kit: String) -> String:
	var section: Variant = load("res://scenes/states/authoring/settlement_section.gd")
	for item in section.CHIPS:
		if item["kit"] == kit:
			return String(item["label"])
	return kit.capitalize()


## The author-facing name of palette surface `surface` ("" for none).
static func surface_name(surface: String) -> String:
	if surface == "":
		return ""
	var panel: Variant = load("res://scenes/states/authoring/authoring_panel.gd")
	return panel.surface_label(surface)
