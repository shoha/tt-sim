extends GutTest

## Live map edits (probe P-live; findings in
## docs/plans/2026-10-09-v0.2-evaluation/probes/live_edits_probe.md, local): the GM's edits
## during play reach every peer as their recorded after states and come out identical. A saved
## authored level (forest, a river leaving both edges with a plank bridge over it, a pond, two
## boulders placed by hand) is loaded twice through MapSourceLoader with props kept apart, as a
## play-side editor needs: the host's copy and a peer's. Each op runs on the host through the
## editor's own code paths; the redo side of every history entry it records crosses as bytes
## (live_edit_codec.gd) and the peer applies it through the same redo method. The host's
## document is then saved and loaded a third time. After every op the three MapFingerprints
## and the documents (masks, heights, water, crossings, flow) match. The decoder's refusals of
## hostile payloads are checked apart on a small document.
##
## Each op's payload size, decode-and-apply time, worst frame and settle time are printed on
## "P-LIVE" lines (headless: no GPU upload in any frame; indicative only).

const Codec := preload("res://tests/unit/live_edit_codec.gd")
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
## Scatter rows of two copies may differ by this much (metres, or quaternion and scale units).
## The saved rows carry 6 decimals, so a row loaded from the file and the same row generated
## again differ by up to about 1e-6; a moved or different instance differs by far more.
const ROW_TOLERANCE := 1e-5


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
## driver would. `started` (usec): when the op began on this frame. {"frames", "worst_usec"
## (the longest frame, the op's own included), "worst_parts" (what that frame spent on the
## editor's step, scatter cells applied and the water surface's swap), "wall_usec"}.
func _settle(copy: Copy, started: int = -1) -> Dictionary:
	var begin := Time.get_ticks_usec() if started < 0 else started
	var last := begin
	var worst := 0
	var worst_parts := ""
	var frames := 0
	var scatter := copy.editor.scatter
	var applied := [0]
	var on_applied := func(_cells: Array) -> void: applied[0] += scatter.last_apply_usec
	scatter.cells_applied.connect(on_applied)
	while frames < SETTLE_FRAMES and _busy(copy):
		var water := copy.root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
		var version := water.version if water != null else 0
		var step_started := Time.get_ticks_usec()
		copy.editor.step_height_work()
		var step := Time.get_ticks_usec() - step_started
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if now - last > worst:
			worst = now - last
			var swapped := water != null and water.version != version
			worst_parts = (
				"step %.1f, cells %.1f, water swap %.1f %s"
				% [
					step / 1000.0,
					applied[0] / 1000.0,
					water.last_swap_usec / 1000.0 if swapped else 0.0,
					str(water.last_swap_parts) if swapped else "",
				]
			)
		applied[0] = 0
		last = now
		frames += 1
	scatter.cells_applied.disconnect(on_applied)
	assert_false(_busy(copy), "settled within %d frames" % SETTLE_FRAMES)
	# Freed nodes (a removed crossing's, shrunk-out instances) leave at the end of a frame.
	await get_tree().process_frame
	return {
		"frames": frames, "worst_usec": worst, "worst_parts": worst_parts, "wall_usec": last - begin
	}


## The host's document saved with its scatter and props rows (as authoring saves) and loaded a
## third time: {"fp", "doc"}.
func _reloaded(host: Copy) -> Dictionary:
	host.doc.scatter = host.editor.scatter.rows_by_asset()
	host.doc.props = host.editor.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(host.doc, LEVEL), OK)
	var third := await _load()
	var out := {
		"fp": MapFingerprint.of(third.root, third.doc),
		"doc": _digest(third.doc),
		"rows": _rows_diff(host.root, third.root),
	}
	third.root.free()
	return out


## How the scatter and props rows of two map roots differ, compared in order per node and
## asset: {"max": the largest component difference, "problems": a line per asset whose row
## count differs or whose rows differ by more than ROW_TOLERANCE}.
func _rows_diff(a: Node, b: Node) -> Dictionary:
	var problems := PackedStringArray()
	var largest := 0.0
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var ra: Dictionary = (a.get_node(node_name) as AuthoredScatter).rows_by_asset()
		var rb: Dictionary = (b.get_node(node_name) as AuthoredScatter).rows_by_asset()
		var ids := ra.keys()
		for id in rb.keys():
			if not ids.has(id):
				ids.append(id)
		for id in ids:
			var fa: PackedFloat32Array = ra.get(id, PackedFloat32Array())
			var fb: PackedFloat32Array = rb.get(id, PackedFloat32Array())
			if fa.size() != fb.size():
				problems.append("%s %s: %d vs %d floats" % [node_name, id, fa.size(), fb.size()])
				continue
			var worst := 0.0
			var at := -1
			for i in fa.size():
				if absf(fa[i] - fb[i]) > worst:
					worst = absf(fa[i] - fb[i])
					at = i
			largest = maxf(largest, worst)
			if worst > ROW_TOLERANCE:
				problems.append(
					(
						"%s %s: row %d differs by %.6f (%.6f vs %.6f)"
						% [node_name, id, floori(at / 10.0), worst, fa[at], fb[at]]
					)
				)
	return {"max": largest, "problems": problems}


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
		water.append(MapWaterIO._body_json(body))
	var crossings: Array = []
	for crossing in doc.crossings:
		crossings.append(MapCrossingIO._crossing_json(crossing))
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
	assert_eq(_rows_diff(host.root, peer.root).problems, PackedStringArray(), "two loads agree")
	var report := PackedStringArray(
		[
			(
				"op | entries | payload B | record B (both sides) | decode ms | apply ms (terrain"
				+ " / collision / snap) | worst frame ms (its parts) | frames | settle ms | rows um"
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
			var op := Codec.op_of(entry)
			assert_false(op.is_empty(), "%s: a redo the codec knows (%s)" % [label, entry.label])
			payloads.append(Codec.encode(op))
			sizes += payloads[-1].size()
			record_bytes += int(entry.get("bytes", 0))
			assert_lt(payloads[-1].size(), Codec.MAX_BYTES, label + ": under 256 KB")
		var e := peer.editor
		e.last_terrain_usec = 0
		e.last_collision_usec = 0
		e.last_snap_usec = 0
		var started := Time.get_ticks_usec()
		var decoded_usec := 0
		for bytes in payloads:
			var decode_started := Time.get_ticks_usec()
			var decoded := Codec.decode(bytes, peer.doc)
			decoded_usec += Time.get_ticks_usec() - decode_started
			assert_eq(decoded.problem, "", label + ": the payload reads back")
			if decoded.problem == "":
				Codec.apply(decoded.op, e)
		var applied := Time.get_ticks_usec() - started
		var parts := [e.last_terrain_usec, e.last_collision_usec, e.last_snap_usec]
		var settled := await _settle(peer, started)
		var reload := await _reloaded(host)
		var host_fp := MapFingerprint.of(host.root, host.doc)
		assert_eq(_fp_diff(host_fp, MapFingerprint.of(peer.root, peer.doc)), [], label)
		assert_eq(_fp_diff(host_fp, reload.fp), [], label + ": against the reload")
		var rows := _rows_diff(host.root, peer.root)
		assert_eq(rows.problems, PackedStringArray(), label + ": the peer's rows")
		assert_eq(reload.rows.problems, PackedStringArray(), label + ": the reloaded rows")
		var host_doc := _digest(host.doc)
		assert_eq(_digest(peer.doc), host_doc, label + ": the peer's document")
		assert_eq(reload.doc, host_doc, label + ": the reloaded document")
		report.append(
			(
				"%s | %d | %d | %d | %.1f | %.1f (%.1f / %.1f / %.1f) | %.1f (%s) | %d | %.0f | %.1f"
				% [
					label,
					entries.size(),
					sizes,
					record_bytes,
					decoded_usec / 1000.0,
					(applied - decoded_usec) / 1000.0,
					parts[0] / 1000.0,
					parts[1] / 1000.0,
					parts[2] / 1000.0,
					maxi(applied, settled.worst_usec) / 1000.0,
					settled.worst_parts,
					settled.frames,
					settled.wall_usec / 1000.0,
					rows.max * 1e6,
				]
			)
		)
	for line in report:
		print("P-LIVE " + line)


## MapFingerprint.diff without scatter_hash: its 1 mm rounding flips where a row loaded from
## the file (6 decimals) and the same row generated again straddle a rounding boundary, so the
## rows are compared within ROW_TOLERANCE instead (_rows_diff).
func _fp_diff(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for key in MapFingerprint.diff(a, b):
		if key != "scatter_hash":
			out.append(key)
	return out


## A valid mask op on a small document, the op it reads back as, and that document.
func _small_mask_op() -> Array:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 1)
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, FOREST)
	stroke.dab(Vector2(-1, 0), Vector2(1, 0), 1.0, 0.5)
	var op := Codec._op("mask", [Codec._diff_after(stroke.finish())])
	return [op, MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 1)]


func _tamper(op: Dictionary, why: String) -> void:
	var diff: Dictionary = op.args[0]
	var block: Dictionary = diff.blocks[0]
	match why:
		"an unknown kind":
			op.kind = "terraform"
		"a rectangle off the grid":
			block.rect = Rect2i(10, 10, 40, 40)
		"a property that is not a mask":
			block.after = {&"heights": block.after[&"biome_slots"]}
		"a block short of its rectangle":
			block.after[&"biome_density"] = PackedByteArray([1, 2, 3]).compress(Codec.COMPRESSION)
		"a slot past the biome list":
			diff.ids_after = PackedStringArray()
		"an unknown biome":
			diff.ids_after = PackedStringArray(["no_such_biome"])


func test_the_decoder_refuses_hostile_payloads() -> void:
	var made := _small_mask_op()
	var good: Dictionary = made[0]
	var doc: MapDocument = made[1]
	assert_eq(Codec.decode(Codec.encode(good), doc).problem, "", "a real stroke reads back")
	for why in [
		"an unknown kind",
		"a rectangle off the grid",
		"a property that is not a mask",
		"a block short of its rectangle",
		"a slot past the biome list",
		"an unknown biome",
	]:
		var op := good.duplicate(true)
		_tamper(op, why)
		assert_ne(Codec.decode(Codec.encode(op), doc).problem, "", why)
	var oversized := PackedByteArray()
	oversized.resize(Codec.MAX_BYTES + 1)
	assert_ne(Codec.decode(oversized, doc).problem, "", "over the byte cap, never decoded")
	var plank := {
		"id": 1,
		"kind": "plank",
		"start": [-1.5, 0.0],
		"end": [1.5, 0.0],
		"levels": [0.1, 0.15, 0.1],
		"width_m": 1.5,
		"style": "",
	}
	var crossing := Codec._op("crossings", [[plank], Rect2()])
	assert_eq(Codec.decode(Codec.encode(crossing), doc).problem, "", "a plank bridge")
	plank.id = 0
	crossing = Codec._op("crossings", [[plank], Rect2()])
	assert_ne(Codec.decode(Codec.encode(crossing), doc).problem, "", "a crossing with id 0")
	var asset: String = PaletteLibrary.species(FOREST)[0].assets[0]
	var row := PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	var props := Codec._op("props", [Vector2i.ZERO, {asset: row}])
	assert_eq(Codec.decode(Codec.encode(props), doc).problem, "", "a prop in its cell")
	props = Codec._op("props", [Vector2i(1, 0), {asset: row}])
	assert_ne(Codec.decode(Codec.encode(props), doc).problem, "", "a prop filed in another cell")
	props = Codec._op("props", [Vector2i.ZERO, {"x/no_such_asset": row}])
	assert_ne(Codec.decode(Codec.encode(props), doc).problem, "", "an asset the palette lacks")
