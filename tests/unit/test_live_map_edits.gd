extends GutTest

## Live map edits (LiveEditCodec; probe P-live, findings in
## docs/plans/2026-10-09-v0.2-evaluation/probes/live_edits_probe.md, local): the GM's edits
## during play reach every peer as their recorded after states and come out identical. A saved
## authored level (forest, a river leaving both edges with a plank bridge over it, a pond, two
## boulders placed by hand) is loaded twice through MapSourceLoader with props kept apart, as a
## play-side editor needs: the host's copy and a peer's. Each op runs on the host through the
## editor's own code paths; the redo side of every history entry it records crosses as bytes
## (LiveEditCodec.op_of, encode) into the peer's LiveEditCodec.Queue, which applies one op a
## frame once the last one's height work has drained. The host's document is then saved and
## loaded a third time. After every op the three MapFingerprints match exactly (generated rows
## snap to the saved precision, so a reloaded cell and a regenerated one are bit-equal) and so
## do the documents (masks, heights, water, crossings, flow). A sculpt's apply returns with its
## chunks queued and the peer's per-frame step drains them over several frames.
##
## Each op's payload size, decode and apply time, worst frame, the most one frame spent on
## chunks, snapping and the collision, and the settle time are printed on "P-LIVE" lines
## (headless: no GPU upload in any frame; indicative only). Hostile payloads are refused in
## test_live_edit_codec.gd.

const DIR := "user://_p_live_probe/"
const LEVEL := DIR + "map.ttmap"
const FOREST := "temperate_forest_summer_s1"
const BIRCH := "birch_woodland_summer_s1"
const ROAD := "dirt_road_packed"
## 200 ft, the largest map authoring makes.
const MAP_CELLS := 40
const SEED := 4242
## The forest covers the map west of this (map X, metres); the river runs east of it.
const FOREST_EDGE_X := 6.0
const RIVER: Array[Vector2] = [Vector2(12, -34), Vector2(13, 0), Vector2(14, 34)]
const POND := Vector2(-13, 16)
const CRATER := Vector3(-6, 0, 22)
const SETTLE_FRAMES := 900


## One built copy of the level.
class Copy:
	var root: Node3D = null
	var doc: MapDocument = null
	var editor: AuthoringEditor = null
	var history: AuthoringHistory = null


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file_name)
	DirAccess.remove_absolute(DIR.trim_suffix("/"))


# --- the level and its copies --------------------------------------------------------------


func _forest(doc: MapDocument) -> void:
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x < FOREST_EDGE_X:
				slots[doc.sample_index(x, z)] = 1
				density[doc.sample_index(x, z)] = 200
	doc.biome_slots = slots
	doc.biome_density = density


## Builds the level with the editor (forest, river, pond, bridge, boulders) and saves it.
func _make_level() -> void:
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "probe", SEED)
	_forest(doc)
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var setup := Copy.new()
	setup.root = await loader.build_async("", doc)
	setup.doc = doc
	add_child(setup.root)
	_editable(setup)
	var e := setup.editor
	e.water.use_worker = false
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var river := e.water.carve_river(
		PackedVector2Array(RIVER), PackedFloat32Array([1.6]), WaterBody.Depth.WAIST
	)
	assert_gt(river, 0, "the river is carved")
	assert_true(e.water.paint_pond_begin(WaterBody.Depth.WAIST, Vector3(POND.x, 0, POND.y)))
	e.stroke_dab(Vector3(POND.x, 0, POND.y), Vector3(POND.x + 3, 0, POND.y), 3.5, 0.1)
	assert_true(e.end_stroke(), "the pond is painted")
	var bridge := e.crossings.place(Crossing.Kind.PLANK, Vector3(9, 0, 0), Vector3(17, 0, 0))
	assert_gt(bridge, 0, "a plank bridge spans the river")
	var boulder := e.species_rule(FOREST, "boulder")
	for at: Vector3 in [Vector3(21, 0, -12), Vector3(23, 0, 9)]:
		assert_false(e.place_prop(boulder, at, Vector3.UP).is_empty())
	e.commit_prop_edit()
	await _settle(setup)
	doc.scatter = e.scatter.rows_by_asset()
	doc.props = e.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(doc, LEVEL), OK)
	remove_child(setup.root)
	setup.root.free()


## The saved level loaded as a play map with props kept apart (not in the tree).
func _load() -> Copy:
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var copy := Copy.new()
	copy.root = await loader.load_async("", LEVEL)
	copy.doc = loader.document
	assert_not_null(copy.root, "the level loads")
	return copy


## `copy` with a play-side editor (no UI) over it, as authoring makes one.
func _editable(copy: Copy) -> Copy:
	if not copy.root.is_inside_tree():
		add_child_autofree(copy.root)
	copy.history = AuthoringHistory.new()
	var scatter := copy.root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(copy.doc)
	copy.editor = AuthoringEditor.create(copy.doc, copy.root, copy.history)
	copy.editor.water.use_worker = true
	return copy


func _busy(copy: Copy) -> bool:
	var e := copy.editor
	var water := copy.root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	return (
		e.has_height_work()
		or e.scatter.is_regenerating()
		or e.scatter.is_growing()
		or e.props.is_growing()
		or (water != null and water.is_refreshing())
	)


## Frames until `copy` has no work left (height work, a water edit's landing, regeneration,
## grow-in, the water surface's refresh), driving the editor's per-frame step as a play-side
## driver would, or `queue` (a peer's LiveEditCodec.Queue), which also applies its ops.
## `started` (usec): when the op began on this frame. {"frames", "worst_usec" (the longest
## frame, the op's own included), "worst_parts" (what that frame spent on the step, scatter
## cells applied and the water surface's swap), "wall_usec", "apply_usec" (the longest step
## that applied an op), "queued" (an applied op left terrain chunks queued), "height_frames"
## (frames that updated chunks), "chunks" and "chunks_max" (chunks updated in all, and in one
## frame), "terrain_usec", "snap_usec", "collision_usec" (the most one frame spent on each),
## "trace" (a line per frame of height work)}.
func _settle(copy: Copy, started: int = -1, queue: LiveEditCodec.Queue = null) -> Dictionary:
	var begin := Time.get_ticks_usec() if started < 0 else started
	var last := begin
	var out := {
		"frames": 0,
		"worst_usec": 0,
		"worst_parts": "",
		"apply_usec": 0,
		"queued": false,
		"height_frames": 0,
		"terrain_usec": 0,
		"snap_usec": 0,
		"collision_usec": 0,
		"chunks": 0,
		"chunks_max": 0,
		"trace": [],
	}
	var e := copy.editor
	var heights := e.heights
	var applied := [0]
	var on_applied := func(_cells: Array) -> void: applied[0] += e.scatter.last_apply_usec
	e.scatter.cells_applied.connect(on_applied)
	while out.frames < SETTLE_FRAMES and (_busy(copy) or (queue != null and queue.size() > 0)):
		var water := copy.root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
		var version := water.version if water != null else 0
		heights.last_terrain_usec = 0
		heights.last_snap_usec = 0
		heights.last_collision_usec = 0
		heights.last_snap_rows = 0
		e.terrain.last_heights_chunks = 0
		var step_started := Time.get_ticks_usec()
		var did_apply := false
		if queue != null:
			did_apply = queue.step()
		else:
			e.step_height_work()
		var step := Time.get_ticks_usec() - step_started
		if did_apply:
			out.apply_usec = maxi(out.apply_usec, step)
			out.queued = out.queued or e.terrain.has_height_work()
		else:
			var chunks := e.terrain.last_heights_chunks
			out.terrain_usec = maxi(out.terrain_usec, heights.last_terrain_usec)
			out.snap_usec = maxi(out.snap_usec, heights.last_snap_usec)
			out.collision_usec = maxi(out.collision_usec, heights.last_collision_usec)
			out.height_frames += 1 if chunks > 0 else 0
			out.chunks += chunks
			out.chunks_max = maxi(out.chunks_max, chunks)
			if chunks > 0 or heights.last_snap_rows > 0 or heights.last_collision_usec > 100:
				(out.trace as Array).append(
					(
						"%d: %d chunks %.1f, %d rows %.1f, collision %.1f"
						% [
							out.frames,
							chunks,
							heights.last_terrain_usec / 1000.0,
							heights.last_snap_rows,
							heights.last_snap_usec / 1000.0,
							heights.last_collision_usec / 1000.0,
						]
					)
				)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if now - last > out.worst_usec:
			out.worst_usec = now - last
			var swapped := water != null and water.version != version
			out.worst_parts = (
				"%s %.1f, cells %.1f, water swap %.1f %s"
				% [
					"apply" if did_apply else "step",
					step / 1000.0,
					applied[0] / 1000.0,
					water.last_swap_usec / 1000.0 if swapped else 0.0,
					str(water.last_swap_parts) if swapped else "",
				]
			)
		applied[0] = 0
		last = now
		out.frames += 1
	e.scatter.cells_applied.disconnect(on_applied)
	assert_false(_busy(copy), "settled within %d frames" % SETTLE_FRAMES)
	# Freed nodes (a removed crossing's, shrunk-out instances) leave at the end of a frame.
	await get_tree().process_frame
	out["wall_usec"] = last - begin
	return out


## The host's document saved with its scatter and props rows (as authoring saves) and loaded a
## third time: {"fp", "doc"}.
func _reloaded(host: Copy) -> Dictionary:
	host.doc.scatter = host.editor.scatter.rows_by_asset()
	host.doc.props = host.editor.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(host.doc, LEVEL), OK)
	var third := await _load()
	var out := {"fp": MapFingerprint.of(third.root, third.doc), "doc": _digest(third.doc)}
	third.root.free()
	return out


## The document's fields, hashed: masks, heights and flow exactly; water and crossings in
## their saved forms rounded to 0.1 mm (the reload reads them back from JSON).
func _digest(doc: MapDocument) -> Dictionary:
	var out := {
		"biome_ids": ",".join(doc.biome_ids),
		"surface_ids": ",".join(doc.surface_ids),
		"flow_size": str(doc.water_flow_size),
	}
	for field in [
		"heights",
		"biome_slots",
		"biome_density",
		"surface_weights",
		"pond_mask",
		"erase_mask",
		"water_flow"
	]:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(var_to_bytes(doc.get(field)))
		out[field] = ctx.finish().hex_encode().left(16)
	var water: Array = []
	for body in doc.water_bodies:
		water.append(MapWaterIO.body_json(body))
	var crossings: Array = []
	for crossing in doc.crossings:
		crossings.append(MapCrossingIO.crossing_json(crossing))
	out["water"] = JSON.stringify(_rounded(water))
	out["crossings"] = JSON.stringify(_rounded(crossings))
	return out


func _rounded(value: Variant) -> Variant:
	if value is float:
		return snappedf(value, 0.0001)
	if value is Array:
		return (value as Array).map(_rounded)
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _rounded(value[key])
		return out
	return value


# --- the ops, on the host --------------------------------------------------------------------


func _dabs(e: AuthoringEditor, points: Array, radius: float, seconds: float) -> void:
	var last: Vector3 = points[0]
	for p: Vector3 in points:
		e.stroke_dab(last, p, radius, seconds)
		e.flush()
		last = p
	assert_true(e.end_stroke(), "the stroke changed the map")


func _paint_birch(e: AuthoringEditor) -> void:
	assert_true(e.begin_stroke(MaskBrush.PAINT, BIRCH))
	var line := [Vector3(20, 0, -22), Vector3(22, 0, -8), Vector3(24, 0, 6), Vector3(24, 0, 20)]
	_dabs(e, line, 4.0, 0.6)


func _raise(e: AuthoringEditor) -> void:
	assert_true(e.begin_height_stroke(HeightBrush.RAISE))
	_dabs(e, [Vector3(-20, 0, -20), Vector3(-17, 0, -18), Vector3(-14, 0, -16)], 4.0, 0.5)


func _lower(e: AuthoringEditor) -> void:
	assert_true(e.begin_height_stroke(HeightBrush.LOWER))
	_dabs(e, [Vector3(8, 0, -14), Vector3(8.5, 0, -11), Vector3(9, 0, -8)], 3.0, 0.4)


func _road(e: AuthoringEditor) -> void:
	assert_true(e.begin_surface_stroke(ROAD, false))
	var line: Array = []
	for k in 17:
		line.append(Vector3(-26 + 2 * k, 0, 4 - 0.1 * k))
	_dabs(e, line, 1.5, 0.5)


func _clear(e: AuthoringEditor) -> void:
	assert_true(e.begin_stroke(MaskBrush.CLEAR))
	_dabs(e, [Vector3(-24, 0, -6), Vector3(-16, 0, -7), Vector3(-8, 0, -8)], 4.0, 0.6)


func _remove_bridge(e: AuthoringEditor) -> void:
	assert_eq(e.document.crossings.size(), 1)
	assert_true(e.crossings.remove(e.document.crossings[0].id))


## The pond erased whole (a drained lake); the river and its wet dressing stay.
func _drain_pond(e: AuthoringEditor) -> void:
	assert_true(e.water.erase_water_begin())
	e.stroke_dab(Vector3(POND.x, 0, POND.y), Vector3(POND.x + 3, 0, POND.y), 6.0, 0.1)
	assert_true(e.end_stroke(), "the pond is erased")


## One touch on the river erases it whole, both edge exits with it.
func _drain_river(e: AuthoringEditor) -> void:
	assert_true(e.water.erase_water_begin())
	e.stroke_dab(Vector3(13, 0, -20), Vector3(13, 0, -20), 1.0, 0.1)
	assert_true(e.end_stroke(), "the river is erased")


## A height stamp (one lower dab) and three boulders on its rim, placed once the stamp's own
## work has landed, as an event preset would.
func _crater(e: AuthoringEditor) -> void:
	assert_true(e.begin_height_stroke(HeightBrush.LOWER))
	_dabs(e, [CRATER], 2.5, 1.2)
	e.finish_height_work()
	var boulder := e.species_rule(FOREST, "boulder")
	for k in 3:
		var at := CRATER + Vector3(cos(TAU * k / 3.0), 0, sin(TAU * k / 3.0)) * 3.0
		at.y = e.ground_height_at(at)
		assert_false(e.place_prop(boulder, at, Vector3.UP).is_empty())
	e.commit_prop_edit()


func _ops() -> Array:
	return [
		["biome paint", _paint_birch],
		["sculpt raise", _raise],
		["sculpt lower", _lower],
		["ground surface", _road],
		["forest clear", _clear],
		["bridge removal", _remove_bridge],
		["pond erase", _drain_pond],
		["river erase", _drain_river],
		["crater", _crater],
	]


# --- tests -----------------------------------------------------------------------------------


func test_live_ops_reach_a_peer_identical_to_the_host_and_a_reload() -> void:
	await _make_level()
	var host := _editable(await _load())
	var peer := _editable(await _load())
	await _settle(host)
	await _settle(peer)
	var host_loaded := MapFingerprint.of(host.root, host.doc)
	var loads := MapFingerprint.diff(host_loaded, MapFingerprint.of(peer.root, peer.doc))
	assert_true(loads.is_empty(), "two loads agree: %s" % str(loads))
	var queue := LiveEditCodec.Queue.new(peer.editor)
	var report := PackedStringArray(
		[
			(
				"op | entries | payload B | record B (both sides) | decode ms | apply ms | worst"
				+ " frame ms (its parts) | most per frame ms (terrain / snap / collision) | chunk"
				+ " frames | frames | settle ms"
			)
		]
	)
	for step: Array in _ops():
		var label: String = step[0]
		var count := host.history.undo_count()
		(step[1] as Callable).call(host.editor)
		await _settle(host)
		var entries: Array = (host.history.get("_undo") as Array).slice(count)
		assert_false(entries.is_empty(), label + ": recorded")
		var payloads: Array[PackedByteArray] = []
		var sizes := 0
		var record_bytes := 0
		for entry: Dictionary in entries:
			var op := LiveEditCodec.op_of(entry, host.editor)
			assert_false(op.is_empty(), "%s: a redo the codec knows (%s)" % [label, entry.label])
			payloads.append(LiveEditCodec.encode(op))
			sizes += payloads[-1].size()
			record_bytes += int(entry.get("bytes", 0))
			assert_lt(payloads[-1].size(), LiveEditCodec.MAX_BYTES, label + ": under 256 KB")
		var started := Time.get_ticks_usec()
		var decoded_usec := 0
		for bytes in payloads:
			var decode_started := Time.get_ticks_usec()
			var problem := queue.push(bytes)
			decoded_usec += Time.get_ticks_usec() - decode_started
			assert_eq(problem, "", label + ": the payload reads back")
		var settled := await _settle(peer, started, queue)
		if label.begins_with("sculpt"):
			assert_true(settled.queued, label + ": the apply returned with its chunks queued")
			var spread := "chunks, the collision and the settling on frames of their own"
			assert_gt(settled.trace.size(), 2, "%s: %s" % [label, spread])
			assert_lt(settled.chunks_max, settled.chunks, label + ": no frame took every chunk")
			# Indicative (headless, a shared machine): a budget lets one chunk or cell finish
			# past it; all at once, this raise spent 17 ms on chunks and 15 on snapping.
			var budgets := "%s: per-frame parts near the budgets" % label
			assert_lt(settled.terrain_usec, HeightEditor.TERRAIN_BUDGET_USEC * 3, budgets)
			assert_lt(settled.snap_usec, HeightEditor.SNAP_BUDGET_USEC * 3, budgets)
			for line in settled.trace:
				print("P-LIVE-FRAMES %s %s" % [label, line])
		var reload := await _reloaded(host)
		var host_fp := MapFingerprint.of(host.root, host.doc)
		var to_peer := MapFingerprint.diff(host_fp, MapFingerprint.of(peer.root, peer.doc))
		assert_true(to_peer.is_empty(), "%s: the peer differs in %s" % [label, str(to_peer)])
		var to_reload := MapFingerprint.diff(host_fp, reload.fp)
		assert_true(to_reload.is_empty(), "%s: the reload differs in %s" % [label, str(to_reload)])
		var host_doc := _digest(host.doc)
		assert_eq(_digest(peer.doc), host_doc, label + ": the peer's document")
		assert_eq(reload.doc, host_doc, label + ": the reloaded document")
		report.append(
			(
				"%s | %d | %d | %d | %.1f | %.1f | %.1f (%s) | %.1f / %.1f / %.1f | %d | %d | %.0f"
				% [
					label,
					entries.size(),
					sizes,
					record_bytes,
					decoded_usec / 1000.0,
					settled.apply_usec / 1000.0,
					settled.worst_usec / 1000.0,
					settled.worst_parts,
					settled.terrain_usec / 1000.0,
					settled.snap_usec / 1000.0,
					settled.collision_usec / 1000.0,
					settled.height_frames,
					settled.frames,
					settled.wall_usec / 1000.0,
				]
			)
		)
	for line in report:
		print("P-LIVE " + line)
