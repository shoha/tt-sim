class_name StructureEdit
extends RefCounted

## The rules for editing a standing structure by direct gestures (the Structure tool's selection:
## StructureBrush, docs/systems/structures.md "Editing a building"). Pure functions of a plan, a
## recipe row and the document, so the handles, the tests and the editor agree. Frames: document
## (map XZ metres).
##
## Handles. A plan has a CORNER handle at each point and an EDGE handle (a tab just outside) at
## each edge's middle (`handles`, `pick_handle`). A corner drag resizes the plan and an edge drag
## pushes that side out or in (`drag`). A plan whose sides all run along or across its front
## edge (a rectangle, an L, a T, a U: `is_rectilinear`, in the frame of edge 0, so a turned house
## counts) keeps its square
## corners, as structgen's plan editor does (`StructPlan.move_point` with keep_axes): dragging a
## corner takes its two neighbours along. With `single` (Shift) one point moves alone and the plan
## may leave the square.
##
## Clamps, never errors. A drag asks for a plan; what comes back is the nearest plan the rules
## take: a rectangle's sides clamp to the recipe row's `min_side_m`, `max_side_m` and `max_area_m2`
## (`StructurePlacement.clamp_size`, per axis, so a side held at its largest still lets the other
## one move), a corner never crosses its opposite corner, and a plan ProcgenPlan refuses or that
## would reach water, a steep bank or another building is walked back along the drag to the last
## plan that stands (`clamped` says the pointer is asking for more than it gets, so the tool can
## show the stop gently, without words).
##
## Moves and turns. `move_legal` carries a whole plan by a wanted offset and, when that spot is
## not legal, settles on the nearest legal one in rings (as StructurePlacement.nearest_legal does
## for a new lot) rather than refusing; `turned` rotates a plan about its middle.
##
## The door. Edge 0 carries it (`front_to` rotates the point order so the chosen edge is edge 0;
## the plan, and so the building, is otherwise unchanged).

## What a handle is.
const CORNER := &"corner"
const EDGE := &"edge"
## Sizes dragged by a handle snap to this (metres).
const SIZE_SNAP_M := 0.5
## A whole-plan move snaps to this (metres).
const MOVE_SNAP_M := 0.25
## A side is axis-aligned in the plan's frame within this (metres across it).
const AXIS_EPS_M := 0.03
## Bisections a walked-back drag takes.
const BISECT_STEPS := 10
## An edge handle is a tab this far outside its side (metres), clear of the door mark on the
## front.
const EDGE_OUT_M := 0.8
## A corner handle is picked in preference to an edge handle this much farther away.
const CORNER_BIAS := 0.8
## Seats a duplicate may take beside its original (metres between).
const COPY_GAP_M := 0.6
## Stepped recipe parameters: how far one press of the stepper moves each.
const PARAM_STEPS := {"floors": 1.0, "roof_pitch": 5.0, "chimneys": 1.0, "ridge": 1.0}

# ============================================================================
# Handles
# ============================================================================


## The handles of `plan`: {"kind" (CORNER or EDGE), "index" (the point, or the edge), "at" (map
## XZ)}, corners first. Pure.
static func handles(plan: PackedVector2Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in plan.size():
		out.append({"kind": CORNER, "index": k, "at": plan[k]})
	for k in plan.size():
		var tab := ProcgenPlan.edge_middle(plan, k) + ProcgenPlan.outward(plan, k) * EDGE_OUT_M
		out.append({"kind": EDGE, "index": k, "at": tab})
	return out


## The handle of `plan` nearest `at` within `radius` metres, or {}. A corner wins over an edge
## handle that is not clearly nearer (CORNER_BIAS), so the corners of a small house stay reachable.
static func pick_handle(plan: PackedVector2Array, at: Vector2, radius: float) -> Dictionary:
	var found := handles(plan)
	var positions := PackedVector2Array()
	for handle in found:
		positions.append(handle["at"])
	return pick_among(found, positions, at, radius)


## The handle of `found` whose position (`positions`, parallel to it, in any one space: map metres,
## or screen pixels) is nearest `at` within `radius`, corners favoured (CORNER_BIAS), or {}. The
## tool picks in screen pixels, since a handle is a dot on the screen and a house in front of it
## hides the ground behind.
static func pick_among(
	found: Array[Dictionary], positions: PackedVector2Array, at: Vector2, radius: float
) -> Dictionary:
	var best: Dictionary = {}
	var best_score := INF
	for k in found.size():
		var distance := at.distance_to(positions[k])
		if distance > radius:
			continue
		var score := distance * (CORNER_BIAS if found[k]["kind"] == CORNER else 1.0)
		if score < best_score:
			best = found[k]
			best_score = score
	return best


# ============================================================================
# Frames and shapes
# ============================================================================


## The frame of `plan`: x along edge 0, y out of it. Identity for a degenerate plan.
static func frame_of(plan: PackedVector2Array) -> Transform2D:
	if plan.size() < 3 or ProcgenPlan.edge_length(plan, 0) < 1e-6:
		return Transform2D.IDENTITY
	var u := (ProcgenPlan.edge_end(plan, 0) - ProcgenPlan.edge_start(plan, 0)).normalized()
	return Transform2D(u, ProcgenPlan.outward(plan, 0), ProcgenPlan.edge_start(plan, 0))


## Whether every side of `plan` runs along or across its front edge (within AXIS_EPS_M).
static func is_rectilinear(plan: PackedVector2Array) -> bool:
	if plan.size() < 4:
		return false
	var inverse := frame_of(plan).affine_inverse()
	for k in plan.size():
		var d: Vector2 = inverse * plan[(k + 1) % plan.size()] - inverse * plan[k]
		if absf(d.x) > AXIS_EPS_M and absf(d.y) > AXIS_EPS_M:
			return false
	return true


## Whether `plan` is a rectangle (four points, rectilinear).
static func is_rect(plan: PackedVector2Array) -> bool:
	return plan.size() == 4 and is_rectilinear(plan)


## The sides of `plan`'s bounding box in its own frame (x along the front).
static func extent_of(plan: PackedVector2Array) -> Vector2:
	if plan.is_empty():
		return Vector2.ZERO
	var inverse := frame_of(plan).affine_inverse()
	var first: Vector2 = inverse * plan[0]
	var box := Rect2(first, Vector2.ZERO)
	for p in plan:
		box = box.expand(inverse * p)
	return box.size


## The middle of `plan`'s bounding rectangle.
static func centre_of(plan: PackedVector2Array) -> Vector2:
	var box := Rect2(plan[0], Vector2.ZERO)
	for p in plan:
		box = box.expand(p)
	return box.get_center()


## `plan` moved by `delta`, each point snapped to Structure.FOOTPRINT_STEP_M.
static func translated(plan: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in plan:
		out.append(ProcgenPlan.snap(p + delta, Structure.FOOTPRINT_STEP_M))
	return out


## `plan` turned `radians` about its middle (positive turns toward +Z from +X, the way yaw does).
static func turned(plan: PackedVector2Array, radians: float) -> PackedVector2Array:
	var middle := centre_of(plan)
	var out := PackedVector2Array()
	for p in plan:
		out.append(
			ProcgenPlan.snap(middle + (p - middle).rotated(radians), Structure.FOOTPRINT_STEP_M)
		)
	return out


## `plan` with edge `edge` made the front: the point order rotated so that edge is edge 0 (the
## door side follows it; the plan is the same shape in the same place). Out of range: `plan`.
static func front_to(plan: PackedVector2Array, edge: int) -> PackedVector2Array:
	var n := plan.size()
	if n == 0 or edge <= 0 or edge >= n:
		return plan
	var out := PackedVector2Array()
	for k in n:
		out.append(plan[(k + edge) % n])
	return out


# ============================================================================
# Dragging a handle
# ============================================================================


## The plan a drag of `handle` (from pick_handle) to map point `target` gives: {"plan", "clamped"}.
## `row` is the recipe's palette row in document metres (StructureBrush.scaled_row). With `doc` the
## plan must also stand on legal ground (StructurePlacement.lot_problem, the structure `except_id`
## itself not counting as in the way) unless it did not when the drag began. `single` moves one
## point alone (Shift). Never errors: what the rules refuse is walked back along the drag.
static func drag(
	plan: PackedVector2Array,
	handle: Dictionary,
	target: Vector2,
	row: Dictionary,
	doc: MapDocument = null,
	except_id: int = -1,
	single: bool = false
) -> Dictionary:
	var check_ground := doc != null and _ground(doc, plan, except_id) == ""
	var full := _attempt(plan, handle, target, row, single)
	if _accepts(full["plan"], row, doc if check_ground else null, except_id):
		return full
	var start: Vector2 = handle["at"]
	var low := 0.0
	var high := 1.0
	var best := {"plan": plan, "clamped": true}
	for _k in BISECT_STEPS:
		var mid := (low + high) * 0.5
		var tried := _attempt(plan, handle, start.lerp(target, mid), row, single)
		if _accepts(tried["plan"], row, doc if check_ground else null, except_id):
			best = tried
			low = mid
		else:
			high = mid
	best["clamped"] = true
	return best


## The plan the rules ask for with the handle at `target`, before any walk-back.
static func _attempt(
	plan: PackedVector2Array, handle: Dictionary, target: Vector2, row: Dictionary, single: bool
) -> Dictionary:
	var index: int = handle["index"]
	if StructurePlacement.is_round(row):
		return _round_scaled(plan, handle, target, row)
	if handle["kind"] == EDGE:
		# The pointer holds the tab, which sits EDGE_OUT_M outside its side.
		var normal := ProcgenPlan.outward(plan, index)
		var wanted := target - normal * EDGE_OUT_M
		if is_rect(plan) and not single:
			return _rect_edge(plan, index, wanted, row)
		var push := snappedf(
			(wanted - ProcgenPlan.edge_middle(plan, index)).dot(normal), SIZE_SNAP_M
		)
		return {"plan": _pushed(plan, index, normal * push), "clamped": false}
	if is_rect(plan) and not single:
		return _rect_corner(plan, index, target, row)
	return {"plan": _corner_moved(plan, index, target, single), "clamped": false}


## The circle of a regular polygon `plan`: {"centre", "radius" (the circumradius), "yaw" (the turn
## that StructurePlacement.round_plan was given: the front, edge 0, faces +Z at 0)}.
static func round_of(plan: PackedVector2Array) -> Dictionary:
	var centre := Vector2.ZERO
	for p in plan:
		centre += p
	centre /= maxf(plan.size(), 1)
	var radius := 0.0
	for p in plan:
		radius += p.distance_to(centre)
	radius /= maxf(plan.size(), 1)
	var yaw := 0.0
	if plan.size() >= 3 and ProcgenPlan.edge_length(plan, 0) > 1e-6:
		yaw = wrapf(ProcgenPlan.outward(plan, 0).angle() - PI * 0.5, -PI, PI)
	return {"centre": centre, "radius": radius, "yaw": yaw}


## A round plan scaled by a handle drag: a corner or a side tab both set the radius from the
## pointer's distance to the middle (a side tab by its own distance, along its normal), so the
## polygon stays regular and keeps its turn and its middle; Shift does not break it. The diameter
## snaps to SIZE_SNAP_M and clamps to the row (`clamped` says the pointer asks for more).
static func _round_scaled(
	plan: PackedVector2Array, handle: Dictionary, target: Vector2, row: Dictionary
) -> Dictionary:
	var around := round_of(plan)
	var centre: Vector2 = around["centre"]
	var radius := 0.0
	if handle["kind"] == EDGE:
		var normal := ProcgenPlan.outward(plan, int(handle["index"]))
		var apothem := maxf((target - normal * EDGE_OUT_M - centre).dot(normal), 0.0)
		radius = apothem / cos(PI / plan.size())
	else:
		radius = target.distance_to(centre)
	var wanted := snappedf(radius * 2.0, SIZE_SNAP_M)
	var diameter := StructurePlacement.clamp_size(Vector2(wanted, wanted), row).x
	return {
		"plan":
		StructurePlacement.round_plan(centre, diameter * 0.5, float(around["yaw"]), plan.size()),
		"clamped": not is_equal_approx(diameter, wanted)
	}


## A rectangle with corner `index` dragged to `target`: the opposite corner stays, the sides
## clamp to the row (per axis) and never fold over it.
static func _rect_corner(
	plan: PackedVector2Array, index: int, target: Vector2, row: Dictionary
) -> Dictionary:
	var frame := frame_of(plan)
	var inverse := frame.affine_inverse()
	var q := PackedVector2Array()
	for p in plan:
		q.append(inverse * p)
	var o := q[(index + 2) % 4]
	var c := q[index]
	var sx := 1.0 if c.x >= o.x else -1.0
	var sy := 1.0 if c.y >= o.y else -1.0
	var wanted: Vector2 = inverse * target
	var raw := Vector2(maxf((wanted.x - o.x) * sx, 0.0), maxf((wanted.y - o.y) * sy, 0.0))
	var snapped_raw := Vector2(snappedf(raw.x, SIZE_SNAP_M), snappedf(raw.y, SIZE_SNAP_M))
	var size := StructurePlacement.clamp_size(snapped_raw, row)
	var corner := Vector2(o.x + sx * size.x, o.y + sy * size.y)
	var out := PackedVector2Array()
	for k in 4:
		var x := o.x if absf(q[k].x - o.x) < absf(q[k].x - c.x) else corner.x
		var y := o.y if absf(q[k].y - o.y) < absf(q[k].y - c.y) else corner.y
		out.append(ProcgenPlan.snap(frame * Vector2(x, y), Structure.FOOTPRINT_STEP_M))
	return {"plan": out, "clamped": not size.is_equal_approx(snapped_raw)}


## A rectangle with side `index` pushed to `target` (across its own direction only): the opposite
## side stays, the depth clamps to the row and never folds over it.
static func _rect_edge(
	plan: PackedVector2Array, index: int, target: Vector2, row: Dictionary
) -> Dictionary:
	var frame := frame_of(plan)
	var inverse := frame.affine_inverse()
	var q := PackedVector2Array()
	for p in plan:
		q.append(inverse * p)
	var next := (index + 1) % 4
	var far := (index + 2) % 4
	# Side `index` is across the frame's y when it runs along x, else across x.
	var axis := 1 if absf(q[next].y - q[index].y) <= AXIS_EPS_M else 0
	var other := 1 - axis
	var here: float = q[index][axis]
	var there: float = q[far][axis]
	var sign_out := 1.0 if here >= there else -1.0
	var wanted: Vector2 = inverse * target
	var raw := snappedf(maxf((wanted[axis] - there) * sign_out, 0.0), SIZE_SNAP_M)
	var held := absf(q[next][other] - q[index][other])
	var low := float(row.get("min_side_m", LibraryStructures.DEFAULT_MIN_SIDE_M))
	var high := float(row.get("max_side_m", LibraryStructures.DEFAULT_MAX_SIDE_M))
	var area := float(row.get("max_area_m2", LibraryStructures.DEFAULT_MAX_AREA_M2))
	var depth := clampf(raw, low, maxf(low, minf(high, area / maxf(held, 0.01))))
	var moved := there + sign_out * depth
	var out := PackedVector2Array()
	for k in 4:
		var point := q[k]
		if k == index or k == next:
			point[axis] = moved
		out.append(ProcgenPlan.snap(frame * point, Structure.FOOTPRINT_STEP_M))
	return {"plan": out, "clamped": not is_equal_approx(depth, raw)}


## `plan` with both ends of edge `index` carried by `offset`: the square corners of a rectilinear
## plan are kept, the neighbouring sides just grow or shrink.
static func _pushed(plan: PackedVector2Array, index: int, offset: Vector2) -> PackedVector2Array:
	var out := plan.duplicate()
	var next := (index + 1) % plan.size()
	out[index] = ProcgenPlan.snap(plan[index] + offset, Structure.FOOTPRINT_STEP_M)
	out[next] = ProcgenPlan.snap(plan[next] + offset, Structure.FOOTPRINT_STEP_M)
	return out


## `plan` with corner `index` at `target`. A rectilinear plan carries a neighbour joined by a side
## along an axis of the plan's frame (structgen's keep_axes), unless `single`; a point between two
## sides on one line (a bump) moves alone.
static func _corner_moved(
	plan: PackedVector2Array, index: int, target: Vector2, single: bool
) -> PackedVector2Array:
	var n := plan.size()
	var out := plan.duplicate()
	if is_rectilinear(plan) and not single:
		var frame := frame_of(plan)
		var inverse := frame.affine_inverse()
		var here: Vector2 = inverse * plan[index]
		var goal: Vector2 = inverse * target
		var prev := (index + n - 1) % n
		var next := (index + 1) % n
		var a: Vector2 = inverse * plan[prev]
		var b: Vector2 = inverse * plan[next]
		var flat_prev := absf(a.y - here.y) <= AXIS_EPS_M
		var flat_next := absf(b.y - here.y) <= AXIS_EPS_M
		var tall_prev := absf(a.x - here.x) <= AXIS_EPS_M
		var tall_next := absf(b.x - here.x) <= AXIS_EPS_M
		var straight := (flat_prev and flat_next) or (tall_prev and tall_next)
		if not straight:
			for j in [prev, next]:
				var q: Vector2 = inverse * plan[j]
				if absf(q.y - here.y) <= AXIS_EPS_M:
					out[j] = ProcgenPlan.snap(
						frame * Vector2(q.x, goal.y), Structure.FOOTPRINT_STEP_M
					)
				elif absf(q.x - here.x) <= AXIS_EPS_M:
					out[j] = ProcgenPlan.snap(
						frame * Vector2(goal.x, q.y), Structure.FOOTPRINT_STEP_M
					)
	out[index] = ProcgenPlan.snap(target, Structure.FOOTPRINT_STEP_M)
	return out


## Whether a plan from a drag is one the tool takes: ProcgenPlan's rules, the row's sizes (the
## bounding box in the plan's frame within the sides, the area under its limit) and, with `doc`,
## legal ground.
static func _accepts(
	plan: PackedVector2Array, row: Dictionary, doc: MapDocument, except_id: int
) -> bool:
	if not ProcgenPlan.problems(plan).is_empty():
		return false
	if not fits_row(plan, row):
		return false
	return doc == null or _ground(doc, plan, except_id) == ""


## Whether `plan`'s bounding box in its frame keeps to the row's side range and its area to the
## row's limit.
static func fits_row(plan: PackedVector2Array, row: Dictionary) -> bool:
	var low := float(row.get("min_side_m", LibraryStructures.DEFAULT_MIN_SIDE_M))
	var high := float(row.get("max_side_m", LibraryStructures.DEFAULT_MAX_SIDE_M))
	var area := float(row.get("max_area_m2", LibraryStructures.DEFAULT_MAX_AREA_M2))
	if StructurePlacement.is_round(row):
		var diameter: float = round_of(plan)["radius"] * 2.0
		return (
			diameter >= low - 0.02
			and diameter <= high + 0.02
			and absf(ProcgenPlan.area(plan)) <= area + 0.05
		)
	var box := extent_of(plan)
	return (
		box.x >= low - 0.01
		and box.y >= low - 0.01
		and box.x <= high + 0.01
		and box.y <= high + 0.01
		and absf(ProcgenPlan.area(plan)) <= area + 0.05
	)


static func _ground(doc: MapDocument, plan: PackedVector2Array, except_id: int) -> String:
	return StructurePlacement.lot_problem(doc, plan, {}, except_id)


# ============================================================================
# Moving
# ============================================================================


## `plan` carried by `want` (snapped to MOVE_SNAP_M), or, when that spot is not legal, by the
## nearest offset that is (rings of StructurePlacement.RING_STEP_M out to REACH_M): {"plan", "delta"
## (the offset applied), "moved" (it is not what was asked for), "problem" ("" when a legal spot
## was found; else why `want` is not legal, and `plan` is the plan unmoved)}. The structure
## `except_id` itself is not in the way.
static func move_legal(
	doc: MapDocument, plan: PackedVector2Array, want: Vector2, except_id: int
) -> Dictionary:
	var asked := Vector2(snappedf(want.x, MOVE_SNAP_M), snappedf(want.y, MOVE_SNAP_M))
	var area := Rect2(centre_of(plan) + asked, Vector2.ZERO).grow(
		StructurePlacement.REACH_M + maxf(extent_of(plan).x, extent_of(plan).y)
	)
	var courses := WaterGeometry.river_courses(doc, area) if not doc.water_bodies.is_empty() else {}
	var first := translated(plan, asked)
	var problem := StructurePlacement.lot_problem(doc, first, courses, except_id)
	if problem == "":
		return {"plan": first, "delta": asked, "moved": false, "problem": ""}
	var ring := StructurePlacement.RING_STEP_M
	while ring <= StructurePlacement.REACH_M:
		var best := Vector2.INF
		var best_distance := INF
		var spots := maxi(8, ceili(TAU * ring / StructurePlacement.RING_STEP_M))
		for k in spots:
			var offset := asked + Vector2.from_angle(TAU * k / spots) * ring
			offset = Vector2(snappedf(offset.x, MOVE_SNAP_M), snappedf(offset.y, MOVE_SNAP_M))
			if (
				offset.distance_to(asked) < best_distance
				and (
					StructurePlacement.lot_problem(
						doc, translated(plan, offset), courses, except_id
					)
					== ""
				)
			):
				best = offset
				best_distance = offset.distance_to(asked)
		if best != Vector2.INF:
			return {"plan": translated(plan, best), "delta": best, "moved": true, "problem": ""}
		ring += StructurePlacement.RING_STEP_M
	return {"plan": plan, "delta": Vector2.ZERO, "moved": false, "problem": problem}


## The plan of a copy of structure `source`, set beside it: shifted along its front edge by its
## width and a gap, settling on legal ground; empty when there is nowhere within reach.
static func beside(doc: MapDocument, source: Structure) -> PackedVector2Array:
	var frame := frame_of(source.footprint)
	var width := extent_of(source.footprint).x
	var found := move_legal(doc, source.footprint, frame.x * (width + COPY_GAP_M), -1)
	return found["plan"] if found["problem"] == "" else PackedVector2Array()


## `plan` with its sides brought back inside `row`'s range about its middle (a rectangle; any
## other plan is returned as it is). Used when a structure takes another recipe's limits.
static func refit(plan: PackedVector2Array, row: Dictionary) -> PackedVector2Array:
	if StructurePlacement.is_round(row) and plan.size() >= 3:
		var around := round_of(plan)
		var diameter := float(around["radius"]) * 2.0
		var fitted_round := StructurePlacement.clamp_size(Vector2(diameter, diameter), row).x
		if is_equal_approx(fitted_round, diameter):
			return plan
		return StructurePlacement.round_plan(
			around["centre"], fitted_round * 0.5, float(around["yaw"]), plan.size()
		)
	if not is_rect(plan):
		return plan
	var size := extent_of(plan)
	var fitted := StructurePlacement.clamp_size(size, row)
	if fitted.is_equal_approx(size):
		return plan
	var frame := frame_of(plan)
	var inverse := frame.affine_inverse()
	var middle: Vector2 = inverse * centre_of(plan)
	var out := PackedVector2Array()
	for p in plan:
		var q: Vector2 = inverse * p
		var scaled := Vector2(
			middle.x + signf(q.x - middle.x) * fitted.x * 0.5,
			middle.y + signf(q.y - middle.y) * fitted.y * 0.5
		)
		out.append(ProcgenPlan.snap(frame * scaled, Structure.FOOTPRINT_STEP_M))
	return out


# ============================================================================
# Recipe parameters and variants
# ============================================================================


## The interface entry of parameter `param` ({} when the recipe does not declare it).
static func param_spec(interface: Array, param: String) -> Dictionary:
	for item: Variant in interface:
		if item is Dictionary and String((item as Dictionary).get("name", "")) == param:
			return item
	return {}


## The value of `param` in `params`, or its default when it is not overridden.
static func param_value(params: Dictionary, interface: Array, param: String) -> float:
	var spec := param_spec(interface, param)
	var fallback := float(spec.get("default", 0.0))
	return float(params.get(param, fallback))


## `params` with `param` stepped one PARAM_STEPS notch in `direction` (1 or -1), within the
## interface's range; a value equal to the default is dropped, since only overrides are stored.
## A parameter the recipe does not declare leaves `params` as it is.
static func stepped_params(
	params: Dictionary, interface: Array, param: String, direction: int
) -> Dictionary:
	var spec := param_spec(interface, param)
	if spec.is_empty():
		return params
	var step := float(PARAM_STEPS.get(param, 1.0))
	var value := clampf(
		param_value(params, interface, param) + signi(direction) * step,
		float(spec.get("min", -INF)),
		float(spec.get("max", INF))
	)
	var out := params.duplicate()
	if is_equal_approx(value, float(spec.get("default", 0.0))):
		out.erase(param)
	else:
		out[param] = Structure.round_param(value)
	return out


## `params` without the names `interface` does not declare (the parameters a variant keeps).
static func kept_params(params: Dictionary, interface: Array) -> Dictionary:
	var out := {}
	for key: String in params:
		if not param_spec(interface, key).is_empty():
			out[key] = params[key]
	return out


## The other structures of `ref`'s family in its library (the variants a swap offers), as palette
## rows, `ref` itself included, in the store's order; empty when it has none.
static func variants_of(ref: String) -> Array[Dictionary]:
	var row := LibraryStructureStore.structure(ref)
	var out: Array[Dictionary] = []
	if row.is_empty():
		return out
	for other in LibraryStructureStore.structures(String(row["library"])):
		if String(other["family"]) == String(row["family"]):
			out.append(other)
	return out if out.size() > 1 else ([] as Array[Dictionary])
