class_name CrossingCache
extends RefCounted

## Which crossings of a document need their geometry built again (P4d-5b). A crossing's
## geometry (CrossingGeometry.build_one) is a pure function of the crossing's fields, the
## document's seed and sample grid, the ground within CrossingGeometry.clear_bounds(crossing)
## (bilinear, so one sample past the bounds' rectangle on every side) and the water there
## (WaterGeometry.level_at and CrossingFord.flow_at: the rivers whose course comes within their
## widest half-width plus the bank of the bounds, the pond mask over the bounds and the ponds
## marked in it). key_of() hashes exactly that, so AuthoredCrossings.refresh() keeps the node of
## every crossing whose key is the one its geometry was built with and rebuilds the rest: a
## placement builds one crossing, a sculpt stroke rebuilds the crossings whose ground it
## touched, a water edit the crossings over the bodies it changed. Before the cache every edit
## rebuilt every crossing on the main thread (PERFORMANCE.md "Phase 4d (arch and ford)": 5.6 ms
## per crossing, 33.8 ms with six). A key is a 32-bit hash: two inputs that collide would keep
## a stale crossing, about one edit in four billion. Pure; safe on any thread. Summary:
## docs/systems/crossings.md.

## The ground read for a crossing reaches this many samples past its bounds' rectangle on every
## side (ground_at() is bilinear between the four samples around a point).
const GROUND_MARGIN := 1


## The keys of `doc`'s crossings against `keys` (crossing id -> key, from the last refresh;
## {} at first): {"keys": id -> key for every crossing now in `doc`, "stale": the ids whose key
## is new or differs (their geometry must be built)}. Ids in `keys` but not in `doc` are left
## out of "keys" (their nodes go). Pure.
static func plan(doc: MapDocument, keys: Dictionary) -> Dictionary:
	var next := {}
	var stale := PackedInt32Array()
	for crossing in doc.crossings:
		var key := key_of(doc, crossing)
		next[crossing.id] = key
		if not keys.has(crossing.id) or int(keys[crossing.id]) != key:
			stale.append(crossing.id)
	return {"keys": next, "stale": stale}


## key_of() for every crossing of `doc` (id -> key): what a node made from a worker's parts
## holds (AuthoredCrossings.create seeds its cache with them).
static func keys_of(doc: MapDocument) -> Dictionary:
	var keys := {}
	for crossing in doc.crossings:
		keys[crossing.id] = key_of(doc, crossing)
	return keys


## A hash of everything CrossingGeometry.build_one(doc, crossing) reads (see the header).
static func key_of(doc: MapDocument, crossing: Crossing) -> int:
	var bounds := CrossingGeometry.clear_bounds(crossing)
	var rect := sample_rect(doc, bounds)
	return hash(
		[
			crossing.id,
			crossing.kind,
			crossing.start,
			crossing.end,
			crossing.levels,
			crossing.width_m,
			crossing.style,
			doc.map_seed,
			doc.cell_size_m,
			doc.sample_spacing_m,
			doc.samples_x(),
			doc.samples_z(),
			ground_hash(doc, rect),
			water_hash(doc, bounds, rect),
		]
	)


## The samples of `doc` a crossing with map bounds `bounds` reads: the sample rectangle
## covering `bounds` grown by GROUND_MARGIN, clamped to the grid (end exclusive; empty when
## the bounds lie off the map).
static func sample_rect(doc: MapDocument, bounds: Rect2) -> Rect2i:
	var first := (
		Vector2i(doc.world_to_sample(bounds.position).floor()) - Vector2i.ONE * GROUND_MARGIN
	)
	var last := Vector2i(doc.world_to_sample(bounds.end).ceil()) + Vector2i.ONE * GROUND_MARGIN
	var limit := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	first = first.clamp(Vector2i.ZERO, limit)
	last = last.clamp(Vector2i.ZERO, limit)
	var size := last - first + Vector2i.ONE
	if size.x <= 0 or size.y <= 0:
		return Rect2i()
	return Rect2i(first, size)


## A hash of `doc.heights` over sample rectangle `rect` (0 without heights or an empty rect).
static func ground_hash(doc: MapDocument, rect: Rect2i) -> int:
	if not rect.has_area() or doc.heights.size() != doc.sample_count():
		return 0
	return hash(_slice_f32(doc.heights, doc.samples_x(), rect))


## A hash of the water a crossing with map bounds `bounds` (sample rectangle `rect`) reads:
## each river near the bounds (river_near) by id, level, course points and half-widths; where
## a pond is marked in `rect`, the pond mask over it and each pond marked there by id and
## level (an unmarked rectangle hashes as no mask at all, so the first pond painted elsewhere
## makes no key change). Water elsewhere is not in it, so an edit there leaves the crossing's
## key alone.
static func water_hash(doc: MapDocument, bounds: Rect2, rect: Rect2i) -> int:
	var parts: Array = []
	var mask := PackedByteArray()
	if rect.has_area() and doc.pond_mask.size() == doc.sample_count():
		mask = _slice_bytes(doc.pond_mask, doc.samples_x(), rect)
		if mask.count(0) == mask.size():
			mask = PackedByteArray()
	for body in doc.water_bodies:
		if body.is_river():
			if river_near(body, bounds):
				parts.append([body.id, body.level_m, body.points, body.half_widths])
		elif mask.count(body.id) > 0:
			parts.append([body.id, body.level_m])
	parts.append(mask)
	return hash(parts)


## True when river `body`'s area (its smoothed course within its widest half-width plus
## WaterGeometry.RIVER_BANK_M) can reach map rectangle `bounds`. Decided on the control line:
## the Chaikin course lies in the triangles of three consecutive control points, so the box of
## each such triple grown by the reach covers it. Conservative, never false when the river's
## area touches the bounds.
static func river_near(body: WaterBody, bounds: Rect2) -> bool:
	var points := body.points
	if points.size() < 2:
		return false
	var widest := 0.0
	for w in body.half_widths:
		widest = maxf(widest, w)
	var reach := widest + WaterGeometry.RIVER_BANK_M
	var grown := bounds.grow(reach)
	for i in points.size() - 1:
		var box := Rect2(points[maxi(i - 1, 0)], Vector2.ZERO).expand(points[i]).expand(
			points[i + 1]
		)
		if box.intersects(grown, true):
			return true
	return false


static func _slice_f32(values: PackedFloat32Array, width: int, rect: Rect2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for z in range(rect.position.y, rect.end.y):
		var start := z * width + rect.position.x
		out.append_array(values.slice(start, start + rect.size.x))
	return out


static func _slice_bytes(values: PackedByteArray, width: int, rect: Rect2i) -> PackedByteArray:
	var out := PackedByteArray()
	for z in range(rect.position.y, rect.end.y):
		var start := z * width + rect.position.x
		out.append_array(values.slice(start, start + rect.size.x))
	return out
