class_name VillageDryGround
extends RefCounted

## Keeps a village's houses and props on dry ground and off its bridges (villages phase 3, topic
## bridges round 2; docs/systems/villages.md section 12). Pure: the document in, filtered lists out.
##
## The model. A street's lots come from procgen's row plan (`ProcgenRow.plan`, through
## `WallGeometry.row_plan`), which knows nothing of water, so a street drawn over a river put houses
## in the river and over its bridge. The lots stay derived, never stored: after the plan, a lot is
## dropped when any sample of its footprint (a grid over the building's rectangle grown by
## LOT_MARGIN_M, and over its yard's plot when it has one) is wet (`WaterGeometry.level_at` above
## the ground), or when a sample of its building stands in a crossing corridor of the street (a
## yard's front reaches the road's edge all along a street, so it is not asked;
## `street_corridors`: each wet run of `VillageBridges.wet_runs`, the bridge's width plus
## CORRIDOR_SIDE_M a side, reaching CORRIDOR_END_M past each bank). Filtering after the plan
## changes no draw: the same seed gives the same houses minus the dropped ones, and a dropped lot
## leaves a gap, never a reshuffle. A map with no water body takes none of this (the lots come
## back as the plan made them).
##
## The street's built geometry is the recipe's, which builds every lot of the plan, so
## `without_lots` takes the dropped lots' triangles out by their provenance paths ("left/lot3"),
## and their collision faces by where they stand.
##
## Props (`AuthoredSettlements._stand`) use `prop_ring` (the water under a prop's whole footprint)
## and `crossing_corridors` (every crossing of the document, a hand-placed one too) so a crate or a
## cart never stands in a stream or on a bridge's landing.

## How far a lot's building rectangle is grown before it is tested (metres): its eaves and a strip
## of bank, so a house never rises straight out of the water and the stream reads as one ribbon.
const LOT_MARGIN_M := 1.0
## A lot's footprint is tested on a grid at most this far apart (metres): a 3 m stream under a
## house always meets a sample.
const LOT_STEP_M := 1.0
## A corridor is the bridge's width plus this on each side (metres).
const CORRIDOR_SIDE_M := 0.5
## A corridor reaches this far past each end of the wet stretch or the crossing (metres): its
## landings.
const CORRIDOR_END_M := 2.0
## A prop keeps further off a crossing than a house front does (metres, each side and past each
## anchor): a crate stack beside a landing still crowded the deck's end at CORRIDOR_SIDE_M and
## CORRIDOR_END_M (bridges_look2 f_town_open).
const PROP_SIDE_M := 1.0
const PROP_END_M := 3.0
## A prop is tested for water at its centre and a ring of points this far past its drawn radius
## (metres): a strip of bank between a log pile and the stream.
const PROP_BANK_M := 0.5
## The points prop_ring() gives: the centre and eight round it.
const PROP_RING_POINTS := 9


## The lots of `lots` (a plan of street `wall`) that stand on dry ground of `doc` and outside the
## street's crossing corridors, in their order. `lots` itself when the map has no water.
static func dry_lots(doc: MapDocument, wall: Wall, lots: Array[Dictionary]) -> Array[Dictionary]:
	if lots.is_empty() or not has_water(doc):
		return lots
	var samples := PackedVector2Array()
	var counts := PackedInt32Array()
	var built := PackedInt32Array()
	for lot in lots:
		var own := lot_samples(lot)
		samples.append_array(own)
		counts.append(own.size())
		built.append(building_samples(lot))
	var wet := wet_flags(doc, samples, WallGeometry.clear_bounds(wall))
	return kept_lots(lots, samples, counts, wet, street_corridors(doc, wall), built)


## True when `doc` holds water a lot or prop could stand in (a body and a grid of heights).
static func has_water(doc: MapDocument) -> bool:
	return not doc.water_bodies.is_empty() and doc.heights.size() == doc.sample_count()


## The lots of `lots` kept: lot k owns `counts[k]` consecutive samples of `samples` (lot_samples),
## `wet[i]` says whether sample i is wet; a lot with a wet sample, or one of its first `built[k]`
## samples (its building's; all of them when `built` is empty) in one of `corridors` (corridor()),
## is dropped. A yard's front reaches the road's edge all along a street, so only the building is
## kept off a bridge's landings. Pure.
static func kept_lots(
	lots: Array[Dictionary],
	samples: PackedVector2Array,
	counts: PackedInt32Array,
	wet: PackedByteArray,
	corridors: Array[Dictionary],
	built: PackedInt32Array = PackedInt32Array()
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := 0
	for k in lots.size():
		var keep := true
		var building := built[k] if k < built.size() else counts[k]
		for i in range(at, at + counts[k]):
			if wet[i] != 0 or (i - at < building and in_corridors(samples[i], corridors)):
				keep = false
				break
		at += counts[k]
		if keep:
			out.append(lots[k])
	return out


## The points a lot is tested at (map XZ): a grid over its building rectangle (`points`, four
## corners, the first side the front) grown by `margin`, at most `step` apart, and the corners and
## middle of its yard's `plot` when it has one. Pure.
static func lot_samples(
	lot: Dictionary, margin: float = LOT_MARGIN_M, step: float = LOT_STEP_M
) -> PackedVector2Array:
	var out := _grid(lot.get("points", PackedVector3Array()), margin, step)
	var plot: PackedVector3Array = lot.get("plot", PackedVector3Array())
	if plot.size() == 4:
		out.append_array(_grid(plot, 0.0, step))
	return out


## How many of lot_samples(lot)'s points are its building's (the first ones; the rest its plot's).
static func building_samples(
	lot: Dictionary, margin: float = LOT_MARGIN_M, step: float = LOT_STEP_M
) -> int:
	return _grid(lot.get("points", PackedVector3Array()), margin, step).size()


## The crossing corridors of street `wall` on `doc`: one per wet run (VillageBridges.wet_runs)
## along the street, as wide as its bridge would be (VillageBridges.width_for, planks) plus
## CORRIDOR_SIDE_M a side, from CORRIDOR_END_M before the last dry sample to CORRIDOR_END_M past
## the first after.
static func street_corridors(doc: MapDocument, wall: Wall) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has_water(doc) or wall == null or wall.points.size() < 2:
		return out
	var courses := WaterGeometry.river_courses(doc, wall.bounds().grow(1.0))
	var is_wet := func(p: Vector2) -> bool: return WaterGeometry.is_wet_at(doc, p, -1, courses)
	var half := VillageBridges.width_for(Crossing.Kind.PLANK, wall.height_m, wall.preset) * 0.5
	for run in VillageBridges.wet_runs(wall.points, is_wet):
		out.append(corridor(run["from"], run["to"], half + CORRIDOR_SIDE_M))
	return out


## One corridor for every crossing of `doc` (a village's or a hand-placed one), the one props keep
## out of: its anchors, its half width plus PROP_SIDE_M, reaching PROP_END_M past each anchor.
static func crossing_corridors(doc: MapDocument) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for crossing in doc.crossings:
		out.append(
			corridor(crossing.start, crossing.end, crossing.width_m * 0.5 + PROP_SIDE_M, PROP_END_M)
		)
	return out


## The PROP_RING_POINTS points a prop at `at` whose ground is read `reach` out
## (AuthoredSettlements.footprint_reach, 0.8 of its drawn radius) is tested for water at: `at`, and
## eight points round it at its drawn radius plus PROP_BANK_M. Pure.
static func prop_ring(at: Vector2, reach: float) -> PackedVector2Array:
	var out := PackedVector2Array([at])
	var radius := reach / 0.8 + PROP_BANK_M
	for k in PROP_RING_POINTS - 1:
		out.append(at + Vector2.from_angle(TAU * k / (PROP_RING_POINTS - 1)) * radius)
	return out


## A corridor from `from` to `to` (map XZ) `half` wide each side, each end reaching `reach`
## further: {"from", "to", "half"}. Pure.
static func corridor(
	from: Vector2, to: Vector2, half: float, reach: float = CORRIDOR_END_M
) -> Dictionary:
	var along := (to - from).normalized()
	return {"from": from - along * reach, "to": to + along * reach, "half": half}


## True when `p` lies within `grow` plus the half width of one of `corridors`. Pure.
static func in_corridors(p: Vector2, corridors: Array[Dictionary], grow: float = 0.0) -> bool:
	for c in corridors:
		var nearest := Geometry2D.get_closest_point_to_segment(p, c["from"], c["to"])
		if nearest.distance_to(p) <= float(c["half"]) + grow:
			return true
	return false


## One byte per point of `points`: 1 where it is under water of `doc` (as WaterGeometry.is_wet_at),
## else 0; `near` bounds every point (the rivers are cut to it).
static func wet_flags(doc: MapDocument, points: PackedVector2Array, near: Rect2) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(points.size())
	if points.is_empty() or not has_water(doc):
		return out
	var courses := WaterGeometry.river_courses(doc, near)
	var levels := WaterGeometry.levels_along(doc, points, courses)
	var grounds := WaterGeometry.grounds_at(doc, points)
	for i in points.size():
		if levels[i] != WaterGeometry.DRY and grounds[i] < levels[i]:
			out[i] = 1
	return out


## The provenance paths ("left/lot3", ProcgenRow.lot_path) of the lots of `plan` not in `kept`
## (path -> the lot's footprint, its plot when it has one, as a PackedVector2Array). Pure.
static func dropped(plan: Array[Dictionary], kept: Array[Dictionary]) -> Dictionary:
	var keep := {}
	for lot in kept:
		keep[StructureProcgen.row_lot_path(lot)] = true
	var out := {}
	for lot in plan:
		var path := StructureProcgen.row_lot_path(lot)
		if keep.has(path):
			continue
		var plot: PackedVector3Array = lot.get("plot", PackedVector3Array())
		var q: PackedVector3Array = plot if plot.size() == 4 else lot.points
		var ring := PackedVector2Array()
		for p in q:
			ring.append(Vector2(p.x, p.z))
		out[path] = ring
	return out


## `geometry` (a street's, every lot of its plan built) without the lots of `gone` (dropped()):
## their triangles, found by provenance path, compacted out of each surface; their collision faces,
## found by their middle within LOT_MARGIN_M of the lot's ring; their anchors; `top` taken again
## from what is left. `geometry` itself when `gone` is empty. Never modifies `geometry`.
static func without_lots(geometry: PlantGeometry, gone: Dictionary) -> PlantGeometry:
	if gone.is_empty():
		return geometry
	var drop_tag := PackedByteArray()
	drop_tag.resize(geometry.tag_table.size())
	for id in geometry.tag_table.size():
		if gone.has(StructureLook.lot_of_tag_path(geometry.tag_table[id])):
			drop_tag[id] = 1
	var out := PlantGeometry.new()
	out.tag_table = geometry.tag_table.duplicate()
	out.openings = geometry.openings
	var top := -INF
	for surface in geometry.surfaces:
		var kept := _kept_surface(surface, drop_tag)
		out.surfaces.append(kept)
		for v in kept.vertices:
			top = maxf(top, v.y)
	for record in geometry.anchors:
		var any_gone := false
		for tag: Variant in record.get("tags", []):
			any_gone = any_gone or gone.has(StructureLook.lot_of_tag_path(str(tag)))
		if not any_gone:
			out.anchors.append(record)
	for f in range(0, geometry.collision.size() - 2, 3):
		var a := geometry.collision[f]
		var b := geometry.collision[f + 1]
		var c := geometry.collision[f + 2]
		var middle := (a + b + c) / 3.0
		if _in_any_ring(Vector2(middle.x, middle.z), gone):
			continue
		out.collision.append_array(PackedVector3Array([a, b, c]))
	out.top = minf(top, geometry.top) if top > -INF else -INF
	return out


## `surface` with the triangles whose first vertex carries a tag marked in `drop_tag` taken out and
## the vertices no kept triangle uses compacted away.
static func _kept_surface(surface: PlantSurface, drop_tag: PackedByteArray) -> PlantSurface:
	var out := PlantSurface.new(surface.kind)
	var remap := PackedInt32Array()
	remap.resize(surface.vertex_count())
	remap.fill(-1)
	var tagged := not surface.tags.is_empty()
	var indices := surface.indices
	for t in range(0, indices.size() - 2, 3):
		var tag := surface.tag_of(indices[t])
		if tag >= 0 and tag < drop_tag.size() and drop_tag[tag] != 0:
			continue
		for corner in 3:
			var v := indices[t + corner]
			if remap[v] < 0:
				remap[v] = out.vertices.size()
				out.vertices.append(surface.vertices[v])
				out.normals.append(surface.normals[v])
				out.uvs.append(surface.uvs[v])
				out.colors.append(surface.colors[v])
				if tagged:
					out.tags.append(surface.tag_of(v))
			out.indices.append(remap[v])
	return out


static func _in_any_ring(p: Vector2, rings: Dictionary) -> bool:
	for path: String in rings:
		var ring: PackedVector2Array = rings[path]
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
		for k in ring.size():
			var nearest := Geometry2D.get_closest_point_to_segment(
				p, ring[k], ring[(k + 1) % ring.size()]
			)
			if nearest.distance_to(p) <= LOT_MARGIN_M:
				return true
	return false


## A grid over quad `q` (map XZ in x and z, corners in order) grown by `margin`, at most `step`
## apart along each side, its edges and corners included.
static func _grid(q: PackedVector3Array, margin: float, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if q.size() != 4:
		return out
	var a := Vector2(q[0].x, q[0].z)
	var b := Vector2(q[1].x, q[1].z)
	var d := Vector2(q[3].x, q[3].z)
	var u := (b - a).normalized()
	var w := (d - a).normalized()
	var origin := a - u * margin - w * margin
	var long_u := a.distance_to(b) + margin * 2.0
	var long_w := a.distance_to(d) + margin * 2.0
	var nu := maxi(1, ceili(long_u / step))
	var nw := maxi(1, ceili(long_w / step))
	for i in nu + 1:
		for j in nw + 1:
			out.append(origin + u * (long_u * i / nu) + w * (long_w * j / nw))
	return out
