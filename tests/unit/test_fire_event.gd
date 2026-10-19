extends GutTest

## The same along a path (card F6): the burnt biome only where trees stood and the ash the
## whole way, and a path's ground matching a circle's of its radius on its centre line.
##
## A fire (TerrainEvent.Kind.FIRE, the Events pane's Start a fire) end to end without a
## network, on a forest level loaded as the GM's copy and a client's, each with its LiveEdits
## and TerrainEvents (as test_terrain_events does for a collapse and a fall). The event's bytes
## reach the client's service and both boards play the fire; only once it has burnt out does
## the GM's side make the change, one history entry labelled "Start a fire" of two strokes,
## which reach the client as two ops (the burnt biome's mask, then the ash surface; a Clear and
## the peat on a palette without them). The maps then match; an undo restores the forest
## without playing anything, and a late joiner gets only the ops.

const DIR := "user://_fire_event_test/"
const LEVEL := DIR + "map.ttmap"
const FOREST := "temperate_forest_summer_s1"
const MAP_CELLS := 24
const SEED := 91
const FOREST_EDGE_X := 2.0
## The longest a wait may take, in wall time. Not a frame count: the frames scatter regeneration
## takes (WorkerThreadPool jobs) grow with a slower, narrower machine, so a frame cap fails a
## slow CI runner (the measurements are at test_live_map_edits.gd's SETTLE_S).
const SETTLE_S := 45.0
const OLD_CENTRE := Vector2(-9.0, -8.0)
const FIRE_CENTRE := Vector2(-9.0, 8.0)
const RADIUS := 5.0

var _palette_saved := {}


class Copy:
	var root: Node3D = null
	var doc: MapDocument = null
	var edits: LiveEdits = null


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file_name)
	DirAccess.remove_absolute(DIR.trim_suffix("/"))


func after_each() -> void:
	_restore_palette()


## The cached palette swapped for an older one (before v7): no burnt biome, no ash. A new
## dictionary, not the cached one changed, so what caches by the palette (LiveEditReader's
## id tables) sees a different palette. Restored after each test (_restore_palette).
func _old_palette() -> void:
	var palette := PaletteLibrary.get_palette()
	_palette_saved = palette
	var biomes: Array[Dictionary] = []
	for biome: Dictionary in palette.biomes:
		if biome.get("biome", "") != FireSweep.BURNT_BIOME:
			biomes.append(biome)
	var surfaces: Dictionary = (palette.surfaces as Dictionary).duplicate()
	surfaces.erase(FireSweep.ASH)
	var old := palette.duplicate()
	old.biomes = biomes
	old.surfaces = surfaces
	PaletteLibrary._palettes[PaletteLibrary.DEFAULT_ROOT] = old


func _restore_palette() -> void:
	if _palette_saved.is_empty():
		return
	PaletteLibrary._palettes[PaletteLibrary.DEFAULT_ROOT] = _palette_saved
	_palette_saved = {}


## Builds the forest level and saves it once its scatter has landed; false if it never did,
## since a level saved early holds rows its own masks would not grow.
func _make_level() -> bool:
	# Birch's ground (treecube 1c05fb0): a base whose rules and accents the forest shares.
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass_birch", "fire", SEED)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x < FOREST_EDGE_X:
				slots[doc.sample_index(x, z)] = 1
				density[doc.sample_index(x, z)] = 220
	doc.biome_slots = slots
	doc.biome_density = density
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var root := await loader.build_async("", doc)
	add_child(root)
	var scatter := root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(doc)
	var e := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var growing := func() -> bool: return e.scatter.is_regenerating() or e.scatter.is_growing()
	var settled: bool = await _wait(growing, "the level's scatter")
	doc.scatter = e.scatter.rows_by_asset()
	doc.props = e.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(doc, LEVEL), OK)
	remove_child(root)
	root.free()
	return settled


func _load(sends: bool) -> Copy:
	var loader := MapSourceLoader.new(get_tree())
	loader.keep_props_apart = true
	var copy := Copy.new()
	copy.root = await loader.load_async("", LEVEL)
	copy.doc = loader.document
	assert_not_null(copy.root, "the level loads")
	add_child_autofree(copy.root)
	copy.edits = LiveEdits.create(copy.root, copy.doc, sends)
	add_child_autofree(copy.edits)
	return copy


func _busy(copy: Copy) -> bool:
	var e := copy.edits.editor
	return (
		not copy.edits.is_settled()
		or e.scatter.is_regenerating()
		or e.scatter.is_growing()
		or e.props.is_growing()
		or copy.edits.events.active_count() > 0
	)


## Frames until `busy` says no work is left, at most SETTLE_S; false, with `what` failing to
## settle, past it.
func _wait(busy: Callable, what: String) -> bool:
	var begin := Time.get_ticks_msec()
	var frames := 0
	while busy.call() and Time.get_ticks_msec() - begin < SETTLE_S * 1000.0:
		await get_tree().process_frame
		frames += 1
	var settled: bool = not busy.call()
	var took := "%d frames, %d ms" % [frames, Time.get_ticks_msec() - begin]
	assert_true(settled, "%s: settled within %.0f s (%s)" % [what, SETTLE_S, took])
	return settled


## Frames until every copy has nothing left to do, at most SETTLE_S (_wait).
func _settle(copies: Array, what: String) -> void:
	await _wait(func() -> bool: return copies.any(_busy), what)
	await get_tree().process_frame


func _same(a: Copy, b: Copy, label: String) -> void:
	var diff := MapFingerprint.diff(
		MapFingerprint.of(a.root, a.doc), MapFingerprint.of(b.root, b.doc)
	)
	assert_true(diff.is_empty(), "%s: the maps differ in %s" % [label, str(diff)])


func _advance(copies: Array, seconds: float) -> void:
	for copy: Copy in copies:
		copy.edits.events.advance(seconds)


## The kinds of `copy`'s ops from `first` on ("mask", "surface").
func _kinds(copy: Copy, first: int) -> Array:
	var kinds := []
	for index in range(first, copy.edits.op_log.size()):
		kinds.append(String((bytes_to_var(copy.edits.op_log[index]) as Dictionary).kind))
	return kinds


## The biome that owns the document sample under map point `at`, or "".
func _biome_at(doc: MapDocument, at: Vector2) -> String:
	var sample := doc.world_to_sample(at).round()
	var slot := doc.biome_slots[doc.sample_index(int(sample.x), int(sample.y))]
	return doc.biome_ids[slot - 1] if slot > 0 else ""


## Starts a fire at `centre` on the GM's side, plays it on both boards and checks what each
## sees while it burns; returns the GM's history entry for it.
func _burn(gm: Copy, client: Copy, centre: Vector2, seed_value: int) -> Dictionary:
	var entries := []
	var record := func(entry: Dictionary) -> void: entries.append(entry)
	gm.edits.history.recorded.connect(record)
	var fire := TerrainEvent.fire(centre, RADIUS, seed_value)
	var logged := gm.edits.op_log.size()
	assert_eq(gm.edits.events.start(fire), "", "the GM's side starts the fire")
	assert_eq(client.edits.events.active_count(), 1, "the client plays it too")
	assert_eq(
		gm.edits.events.start(TerrainEvent.fire(centre, RADIUS, 2)),
		TerrainEvents.BUSY,
		"a burning forest does not catch twice"
	)
	_advance([gm, client], 1.0)
	for copy: Copy in [gm, client]:
		var effects := copy.edits.events.effects()
		assert_eq(effects.size(), 1, "every board plays the fire")
		assert_true(effects[0] is FireSweep)
	assert_eq(gm.edits.op_log.size(), logged, "no op while the forest burns")
	_advance([gm, client], fire.duration_s)
	gm.edits.history.recorded.disconnect(record)
	assert_eq(entries.size(), 1, "one history entry")
	var entry: Dictionary = entries[0] if not entries.is_empty() else {}
	assert_eq(entry.get("label"), EventPresets.IGNITE_LABEL, "labelled as its tile")
	assert_eq(entry.get("preset"), TerrainEvent.Kind.FIRE)
	assert_eq((entry.get("parts", []) as Array).size(), 2, "of two strokes")
	await _settle([gm, client], "the fire at %s" % str(centre))
	return entry


func test_a_fire_burns_the_forest_on_every_board_then_changes_the_map() -> void:
	var made: bool = await _make_level()
	if not made:
		return
	var gm := await _load(true)
	var client := await _load(false)
	await _settle([gm, client], "the loads")
	var key := gm.edits.table_key
	gm.edits.op_logged.connect(
		func(index: int, bytes: PackedByteArray) -> void: client.edits.receive_op(key, index, bytes)
	)
	gm.edits.events.started.connect(client.edits.events.receive)
	client.edits.receive_log(key, 0)
	var told := []
	client.edits.events.announced.connect(
		func(event: TerrainEvent) -> void: told.append(event.kind)
	)
	var scatter := gm.edits.editor.scatter
	var standing := FireSweep.burnable(scatter, FIRE_CENTRE, RADIUS)
	assert_gt(standing.size(), 2, "a forest stands where the fire starts")
	assert_gt(FireSweep.burnable(scatter, OLD_CENTRE, RADIUS).size(), 2)
	# Off the forest nothing burns.
	var meadow := TerrainEvent.fire(Vector2(12.0, 0.0), 3.0, 1)
	assert_eq(gm.edits.events.start(meadow), TerrainEvents.NO_FOREST, "only a forest burns")

	# A palette from before the fire (no ash, no burnt biome): a Clear and the peat.
	_old_palette()
	await _burn(gm, client, OLD_CENTRE, 5)
	assert_eq(_kinds(gm, 0), ["mask", "surface"], "a Clear, then the peat")
	assert_eq(client.edits.op_log.size(), 2, "the client has both")
	for copy: Copy in [gm, client]:
		assert_true(copy.doc.surface_ids.has(FireSweep.ASH_FALLBACK), "peat laid")
		assert_eq(_biome_at(copy.doc, OLD_CENTRE), "", "the forest cleared")
		assert_eq(FireSweep.burnable(copy.edits.editor.scatter, OLD_CENTRE, RADIUS * 0.7).size(), 0)
	_same(gm, client, "after a fire on an older palette")
	_restore_palette()

	# The palette's burnt forest and ash.
	var burnt := FireSweep.burnt_biome()
	assert_ne(burnt, "", "this palette has the burnt forest")
	var entry := await _burn(gm, client, FIRE_CENTRE, 9)
	assert_eq(told, [TerrainEvent.Kind.FIRE, TerrainEvent.Kind.FIRE], "a player is told each time")
	assert_eq(_kinds(gm, 2), ["mask", "surface"], "the burnt biome, then the ash")
	assert_eq(client.edits.op_log.size(), 4)
	for copy: Copy in [gm, client]:
		assert_true(copy.doc.surface_ids.has(FireSweep.ASH), "ash laid")
		assert_eq(_biome_at(copy.doc, FIRE_CENTRE), burnt, "the burnt forest stands there")
		var left := FireSweep.burnable(copy.edits.editor.scatter, FIRE_CENTRE, RADIUS * 0.7)
		assert_eq(left.size(), 0, "no green tree stands where it burned")
	_same(gm, client, "after the fire")
	assert_eq(client.edits.events.active_count(), 0, "every effect is gone")
	# The burnt forest does not burn again.
	var again := TerrainEvent.fire(FIRE_CENTRE, RADIUS * 0.5, 3)
	assert_eq(gm.edits.events.start(again), TerrainEvents.NO_FOREST, "ash does not burn")

	# Undo: one step takes both strokes back, and nothing plays.
	assert_true(gm.edits.history.is_newest(entry))
	assert_eq(gm.edits.history.undo(), EventPresets.IGNITE_LABEL)
	assert_eq(gm.edits.events.active_count(), 0, "an undo plays no effect")
	await _settle([gm, client], "the undo")
	assert_eq(_kinds(gm, 4), ["surface", "mask"], "the ash first, then the forest")
	assert_eq(_biome_at(gm.doc, FIRE_CENTRE), FOREST, "the forest is back")
	var back := FireSweep.burnable(gm.edits.editor.scatter, FIRE_CENTRE, RADIUS)
	assert_eq(back.size(), standing.size(), "every tree stands again")
	_same(gm, client, "after the undo")

	# A late joiner gets only the ops.
	var joiner := await _load(false)
	await _settle([joiner], "the late joiner's load")
	joiner.edits.receive_log(key, gm.edits.op_log.size())
	for index in gm.edits.op_log.size():
		joiner.edits.receive_op(key, index, gm.edits.op_log[index])
	assert_eq(joiner.edits.events.active_count(), 0, "the late joiner sees no motion")
	await _settle([gm, joiner], "the late joiner's catch-up")
	_same(gm, joiner, "late joiner")
	# The forest, the birch base and the burnt forest with its ash draw every accent on every
	# board (the index ground, G3; the eight-slot table dropped the burnt forest's dirt here).
	assert_engine_error(0, "no accent dropped")


## The level, built once for the run (_make_level); false if its scatter never landed.
func _level_ready() -> bool:
	if FileAccess.file_exists(LEVEL):
		return true
	return await _make_level()


## `drawn` (map XZ) as IgniteMode makes a path of it: smoothed, resampled.
func _fire_line(drawn: Array) -> PackedVector2Array:
	var line := PackedVector2Array()
	for p: Vector2 in drawn:
		line.append(p)
	return StrokePath.resample(
		StrokePath.smooth_line(line), StrokePath.MAX_POINTS, StrokePath.MIN_SPACING_M
	)


## `doc`'s ash weight and the burnt biome's density at map point `at` (0 where another biome
## or none holds the sample), 0..255.
func _after_at(doc: MapDocument, at: Vector2, burnt: String) -> Vector2i:
	var sample := doc.world_to_sample(at).round()
	var i := doc.sample_index(int(sample.x), int(sample.y))
	var ash := doc.surface_ids.find(FireSweep.ASH)
	var weight := doc.surface_weight(i, ash) if ash >= 0 else 0
	var slot := doc.biome_slots[i] if not doc.biome_slots.is_empty() else 0
	var density := doc.biome_density[i] if slot > 0 and doc.biome_ids[slot - 1] == burnt else 0
	return Vector2i(weight, density)


## Start a fire along a path from the forest into the meadow (design 3d, card F6): every board
## plays it, the GM's side makes one entry of two strokes once it has burnt out, the burnt
## biome only where trees stood and the ash the whole way, the client and a late joiner end
## alike, and one undo puts the map back as it was.
func test_a_fire_along_a_path_burns_the_forest_and_ashes_the_meadow() -> void:
	var made: bool = await _level_ready()
	if not made:
		return
	var gm := await _load(true)
	var client := await _load(false)
	await _settle([gm, client], "the loads")
	var key := gm.edits.table_key
	gm.edits.op_logged.connect(
		func(index: int, bytes: PackedByteArray) -> void: client.edits.receive_op(key, index, bytes)
	)
	gm.edits.events.started.connect(client.edits.events.receive)
	client.edits.receive_log(key, 0)
	var half := 2.0
	var line := _fire_line([Vector2(-14, -1), Vector2(-6, 1), Vector2(2, -1), Vector2(14, 0)])
	var scatter := gm.edits.editor.scatter
	var root := PaletteLibrary.DEFAULT_ROOT
	var standing := FireSweep.burnable_along(scatter, line, half, root, FirePath.ALL_TREES)
	assert_gt(standing.size(), 4, "a forest stands along the path's first half")
	for tree in standing:
		assert_lte(float(tree.distance), half, "within the half-width")
		assert_lt((tree.base as Transform3D).origin.x, FOREST_EDGE_X + 1.0, "only in the forest")
	var meadow := TerrainEvent.fire_path(_fire_line([Vector2(6, 0), Vector2(14, 0)]), half, 1)
	assert_eq(gm.edits.events.start(meadow), TerrainEvents.NO_FOREST_PATH, "a meadow path: none")
	var before := MapFingerprint.of(gm.root, gm.doc)
	var entries := []
	var record := func(entry: Dictionary) -> void: entries.append(entry)
	gm.edits.history.recorded.connect(record)
	var fire := TerrainEvent.fire_path(line, half, 13)
	var logged := gm.edits.op_log.size()
	assert_eq(gm.edits.events.start(fire), "", "the GM's side starts the path")
	assert_eq(client.edits.events.active_count(), 1, "the client plays it too")
	var on_it := TerrainEvent.fire(line[line.size() / 4], 3.0, 2)
	assert_eq(gm.edits.events.start(on_it), TerrainEvents.BUSY, "not over a burning path")
	var across := TerrainEvent.fire_path(_fire_line([Vector2(-8, -6), Vector2(-8, 6)]), 1.5, 3)
	assert_eq(gm.edits.events.start(across), TerrainEvents.BUSY, "nor a path across it")
	_advance([gm, client], 1.0)
	var animated := []
	for copy: Copy in [gm, client]:
		var effects := copy.edits.events.effects()
		assert_eq(effects.size(), 1, "every board plays the path")
		if effects.size() == 1 and effects[0] is FireSweep:
			animated.append((effects[0].get("_trees") as Array).size())
	assert_eq(animated.size(), 2)
	if animated.size() == 2:
		assert_eq(animated[0], animated[1], "both boards burn the same trees")
		assert_eq(animated[0], mini(standing.size(), FirePath.MAX_TREES))
	assert_eq(gm.edits.op_log.size(), logged, "no op while it burns")
	_advance([gm, client], fire.duration_s)
	gm.edits.history.recorded.disconnect(record)
	assert_eq(entries.size(), 1, "one history entry")
	var entry: Dictionary = entries[0] if not entries.is_empty() else {}
	assert_eq(entry.get("label"), EventPresets.IGNITE_LABEL, "labelled as its tile")
	assert_eq(entry.get("preset"), TerrainEvent.Kind.FIRE)
	assert_eq((entry.get("parts", []) as Array).size(), 2, "of two strokes")
	await _settle([gm, client], "the path fire")
	assert_eq(_kinds(gm, logged), ["mask", "surface"], "the burnt biome, then the ash")
	assert_eq(client.edits.op_log.size(), 2, "the client has both")
	var burnt := FireSweep.burnt_biome()
	for copy: Copy in [gm, client]:
		var forest_at := _on_line(line, -8.0)
		var meadow_at := _on_line(line, 10.0)
		assert_eq(_biome_at(copy.doc, forest_at), burnt, "snags where the forest stood")
		assert_ne(_biome_at(copy.doc, meadow_at), burnt, "no snags in the meadow")
		assert_gt(_after_at(copy.doc, forest_at, burnt).x, 200, "ash in the forest")
		assert_gt(_after_at(copy.doc, meadow_at, burnt).x, 200, "and in the meadow")
		var left := FireSweep.burnable_along(copy.edits.editor.scatter, line, half * 0.7, root)
		assert_eq(left.size(), 0, "no green tree stands on the path")
	_same(gm, client, "after the path fire")
	assert_eq(client.edits.events.active_count(), 0, "every effect is gone")

	# A late joiner gets only the two ops.
	var joiner := await _load(false)
	await _settle([joiner], "the late joiner's load")
	joiner.edits.receive_log(key, gm.edits.op_log.size())
	for index in gm.edits.op_log.size():
		joiner.edits.receive_op(key, index, gm.edits.op_log[index])
	assert_eq(joiner.edits.op_log.size(), 2, "two ops")
	assert_eq(joiner.edits.events.active_count(), 0, "the late joiner sees no motion")
	await _settle([gm, joiner], "the late joiner's catch-up")
	_same(gm, joiner, "late joiner")

	# Undo: one step, nothing plays, the map as it was.
	assert_eq(gm.edits.history.undo(), EventPresets.IGNITE_LABEL)
	assert_eq(gm.edits.events.active_count(), 0, "an undo plays no effect")
	await _settle([gm, client], "the undo")
	var diff := MapFingerprint.diff(before, MapFingerprint.of(gm.root, gm.doc))
	assert_true(diff.is_empty(), "the undo restores the map: %s" % str(diff))
	_same(gm, client, "after the undo")


## The point of `line` at map x `x` (it runs west to east).
func _on_line(line: PackedVector2Array, x: float) -> Vector2:
	for i in line.size() - 1:
		if line[i].x <= x and line[i + 1].x >= x:
			return line[i].lerp(line[i + 1], (x - line[i].x) / maxf(line[i + 1].x - line[i].x, 1e-4))
	return line[-1]


## A path and a circle of one radius on twin copies of the forest leave the same ground: the
## same burnt-biome density and ash weight (within 2 of 255) at the path's centre line as at
## the circle's centre, the rim falling off alike, and one undo restores each copy.
func test_a_path_and_a_circle_leave_the_same_ground() -> void:
	var made: bool = await _level_ready()
	if not made:
		return
	var circle := await _load(true)
	var path := await _load(true)
	await _settle([circle, path], "the twins' loads")
	var radius := 3.0
	var line := _fire_line([FIRE_CENTRE + Vector2(-6, 0), FIRE_CENTRE + Vector2(6, 0)])
	var copies: Array = [circle, path]
	var events := [TerrainEvent.fire(FIRE_CENTRE, radius, 4), TerrainEvent.fire_path(line, radius, 4)]
	var before := []
	for k in 2:
		var copy: Copy = copies[k]
		before.append(MapFingerprint.of(copy.root, copy.doc))
		copy.edits.events.call("_apply", events[k])
	await _settle(copies, "both burns")
	var burnt := FireSweep.burnt_biome()
	# Out to the half-width the two fall off alike; past it (where a line of capsules' u^2.5
	# and a dab's u^2 part, FirePath.capsule_seconds) both are nearly gone.
	for d: float in [0.0, 0.5, 1.0, 1.2]:
		var at := FIRE_CENTRE + Vector2(0.0, d * radius)
		var round_one := _after_at(circle.doc, at, burnt)
		var long_one := _after_at(path.doc, at, burnt)
		var where := "%.1f radii out: circle %s, path %s" % [d, round_one, long_one]
		gut.p(where)
		if d > 1.0:
			assert_lt(maxi(long_one.x, round_one.x), 64, "ash nearly gone " + where)
			continue
		var within := 2 if d == 0.0 else 16
		assert_almost_eq(long_one.x, round_one.x, within, "ash alike " + where)
		assert_almost_eq(long_one.y, round_one.y, within, "burnt forest alike " + where)
	assert_gt(_after_at(circle.doc, FIRE_CENTRE, burnt).y, 240, "the centre is burnt through")
	for k in 2:
		var copy: Copy = copies[k]
		assert_eq(copy.edits.history.undo(), EventPresets.IGNITE_LABEL)
	await _settle(copies, "both undos")
	for k in 2:
		var copy: Copy = copies[k]
		var diff := MapFingerprint.diff(before[k], MapFingerprint.of(copy.root, copy.doc))
		assert_true(diff.is_empty(), "copy %d restored: %s" % [k, str(diff)])


func test_the_fire_plan_follows_the_palette() -> void:
	assert_eq(FireSweep.plan_for([], {}), {"biome": "", "surface": ""}, "nothing to lay: a Clear")
	var old := FireSweep.plan_for([{"id": FOREST, "biome": "temperate_forest"}], {"dirt_peat": {}})
	assert_eq(old, {"biome": "", "surface": FireSweep.ASH_FALLBACK}, "an older palette's peat")
	var now := FireSweep.plan_for(PaletteLibrary.biomes(), PaletteLibrary.surfaces())
	assert_eq(now.biome, "burnt_forest_summer_s1", "the burnt forest (ASSET_PIPELINE.md Fire)")
	assert_eq(now.surface, FireSweep.ASH)


func test_a_history_group_is_one_entry() -> void:
	var history := AuthoringHistory.new()
	var calls := []
	var heard := []
	history.recorded.connect(func(entry: Dictionary) -> void: heard.append(entry.label))
	history.begin_group()
	for part in ["a", "b"]:
		history.record(
			{
				"label": part,
				"undo": func() -> void: calls.append("undo " + part),
				"redo": func() -> void: calls.append(part),
			}
		)
	var entry := history.end_group("Both")
	assert_eq(history.undo_count(), 1, "one entry")
	assert_eq(heard, ["Both"], "heard once, as the group")
	assert_eq((entry.parts as Array).size(), 2)
	assert_eq(history.undo(), "Both")
	assert_eq(calls, ["undo b", "undo a"], "undone in reverse")
	assert_eq(history.redo(), "Both")
	assert_eq(calls, ["undo b", "undo a", "a", "b"], "redone in order")
	history.begin_group()
	assert_eq(history.end_group("Nothing"), {}, "an empty group records nothing")
	assert_eq(history.undo_count(), 1)


func test_a_fire_fits_its_pools() -> void:
	# Every puff of a fire at its most trees at once, so none is overwritten.
	var flames := FireSweep.FLAMES_PER_TREE * FireSweep.MAX_TREES + FireSweep.FRONT_TONGUES
	assert_lte(flames, FireSweep.FLAME_POOL, "every crown's flames and the ground's tongues")
	assert_gte(FireSweep.FLAMES_PER_TREE, FireSweep.CROWN_TONGUES + 1, "a crown's tongues, a spark")
	# A crown tongue rises once the burn has reached its height, the high ones later, and is
	# gone soon after its crown has burnt.
	var low := FireSweep.tongue_at(FireSweep.TONGUE_FOOT.x, 0.0)
	var high := FireSweep.tongue_at(FireSweep.TONGUE_FOOT.y, 1.0)
	assert_gt(FireSweep.burn_progress(low, 1.0), FireSweep.CATCH_HEIGHT * FireSweep.TONGUE_FOOT.x)
	assert_lt(low, high, "low tongues first")
	assert_lte(high + FireSweep.TONGUE_LIFE.y, 1.2, "a tongue gone soon after its crown has burnt")
	# None stands in the crown's top (its tip held under TONGUE_TOP), and the cap leaves the
	# widest tongue room above the lowest foot.
	assert_lte(FireSweep.TONGUE_TOP, 0.86, "no tongue against the sky at a crown's top")
	var tallest := FireSweep.TONGUE_BOUNDS.y * 1.15 * FireSweep.TONGUE_TALL
	assert_lt(FireSweep.TONGUE_FOOT.x + tallest, FireSweep.TONGUE_TOP)
	assert_lte(FireSweep.MAX_TREES + FireSweep.COLUMN_AT.size(), FireSweep.SMOKE_POOL)
	assert_lte(
		TerrainEvent.DURATIONS[TerrainEvent.Kind.FIRE], TerrainEvent.MAX_DURATION_S, "in bounds"
	)
	# The front reaches the last tree, and it burns out, within the event.
	var last := FireSweep.SPREAD_S + FireSweep.SPREAD_JITTER + FireSweep.BURN_S.y
	assert_lte(last, TerrainEvent.DURATIONS[TerrainEvent.Kind.FIRE])
	# The pool plays each fire kind out and empties.
	var puffs := EventPuffs.new(8, EventPuffs.RENDER_PRIORITY + 2)
	add_child_autofree(puffs)
	assert_eq(puffs.capacity, 8)
	puffs.emit_flame(Vector3.ZERO, Vector3.UP, 1.0, 2.0, 0.8, FireSweep.FLAME)
	puffs.emit_ember(Vector3.ZERO, Vector3(0.2, 1.5, 0.0), 0.3, 1.2, FireSweep.EMBER)
	puffs.emit_crown_flame(Vector3.UP, Vector3.UP * 0.1, 0.4, 0.5, 0.6, FireSweep.FLAME_LATE)
	puffs.band_flames(true)
	puffs.step(0.3)
	assert_false(puffs.is_idle())
	puffs.step(1.5)
	assert_true(puffs.is_idle(), "every puff spent")
	# A tree's burn: untouched until it catches, every patch burnt through by the end of it.
	assert_eq(FireSweep.burn_progress(-0.5, 1.2), 0.0, "waiting for the front")
	assert_gt(FireSweep.burn_progress(0.3, 1.2), 0.0, "caught")
	assert_gte(FireSweep.burn_progress(1.2, 1.2), 1.55, "burnt through")
	# The charred snags stand, then shrink away about their feet by the end of the event.
	var base := Transform3D(Basis.IDENTITY, Vector3(3.0, 1.0, -2.0))
	assert_eq(FireSweep.snag_transform(base, 1.0, 4.0), base, "standing while it burns")
	var going := FireSweep.snag_transform(base, 4.0 - FireSweep.SNAG_GO_S * 0.5, 4.0)
	assert_lt(going.basis.y.length(), 1.0, "shrinking")
	assert_eq(going.origin, base.origin, "about its foot")
	assert_almost_eq(FireSweep.snag_transform(base, 4.0, 4.0).basis.y.length(), 0.0, 0.001, "gone")
	# They and the char hold past the end until the change has landed, then go (card F6b).
	var sweep := FireSweep.new()
	add_child_autofree(sweep)
	sweep.duration = 4.0
	assert_eq(sweep.end_at(1.0), 4.0, "never before the event's end")
	for t: float in [4.0, 5.0, 9.0]:
		var end := sweep.end_at(t)
		assert_eq(FireSweep.snag_transform(base, t, end), base, "a snag stands at %.1f s" % t)
		assert_eq(GroundBurn.char_at(t, end), 1.0, "the char holds at %.1f s" % t)
	sweep.set("_landed_at", 6.0)
	var landed := sweep.end_at(9.0)
	assert_almost_eq(landed, 6.0 + FireSweep.SNAG_GO_S, 0.001, "going once it landed")
	assert_lt(FireSweep.snag_transform(base, 6.3, landed).basis.y.length(), 1.0, "shrinking")
	assert_eq(GroundBurn.char_at(6.0, landed), 1.0, "the char whole as the ash lands")
	assert_eq(GroundBurn.char_at(landed + 1.0, landed), 0.0, "then under the ash")


## A path's geometry (FirePath) and its motion's bounds: arcs and projection along the line,
## the trees thinned evenly, the forest spans widened and merged, the runs covering the line,
## the pools fitting its most trees, and its front within the event.
func test_a_path_fits_its_pools_and_spans() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 3)])
	var along := FirePath.arcs(line)
	assert_eq(along, PackedFloat32Array([0.0, 4.0, 7.0]))
	assert_almost_eq(FirePath.project(line, along, Vector2(2, 1)).x, 2.0, 0.001, "its arc")
	assert_almost_eq(FirePath.project(line, along, Vector2(2, 1)).y, 1.0, 0.001, "off the line")
	assert_almost_eq(FirePath.project(line, along, Vector2(6, 1.5)).x, 5.5, 0.001)
	var at := FirePath.frame_at(line, along, 5.0)
	assert_true(Vector2(at.x, at.y).is_equal_approx(Vector2(4, 1)), "a point along it")
	assert_true(Vector2(at.z, at.w).is_equal_approx(Vector2(0, 1)), "and its way")
	var part := FirePath.span_line(line, along, 2.0, 5.0)
	assert_eq(part, PackedVector2Array([Vector2(2, 0), Vector2(4, 0), Vector2(4, 1)]))
	var found: Array[Dictionary] = []
	for i in 200:
		found.append({"arc": float(i)})
	var kept := FirePath.thin(found, FirePath.MAX_TREES)
	assert_eq(kept.size(), FirePath.MAX_TREES)
	assert_eq(kept[0].arc, 0.0, "the first kept")
	assert_eq(kept[-1].arc, 199.0, "and the last")
	assert_almost_eq(float(kept[48].arc), 100.5, 1.5, "evenly between")
	var spans := FirePath.forest_spans(PackedFloat32Array([3.0, 5.0, 20.0]), 1.0, 22.0)
	assert_eq(spans, PackedVector2Array([Vector2(1, 7), Vector2(18, 22)]), "widened, merged, cut")
	var runs := FirePath.runs(spans, 30.0)
	var expected := [
		[0.0, 1.0, false], [1.0, 7.0, true], [7.0, 18.0, false], [18.0, 22.0, true], [22.0, 30.0, false]
	]
	assert_eq(runs, expected, "forest and open stretches in order, covering the path")
	assert_eq(FirePath.runs(PackedVector2Array(), 5.0), [[0.0, 5.0, false]], "no forest: all open")
	# A line of capsules gathers about 1 + 16 r / 15 L dabs on its centre line.
	assert_almost_eq(FirePath.capsule_seconds(3.0, 1.0, 3.0), 3.0 / 4.2, 0.001)
	assert_eq(FirePath.capsule_seconds(3.0, 0.0, 3.0), 3.0, "a point is a dab")
	# Pools: every puff of the path's most trees at once; its front and burn within the event.
	var flames := FireSweep.FLAMES_PER_TREE * FirePath.MAX_TREES + FireSweep.PATH_FRONT_TONGUES
	assert_lte(flames, FireSweep.PATH_FLAME_POOL)
	assert_lte(FirePath.MAX_TREES + FireSweep.COLUMN_AT.size(), FireSweep.PATH_SMOKE_POOL)
	var longest := TerrainEvent.path_spread(TerrainEvent.MAX_PATH_LENGTH_M)
	var last := longest + FireSweep.SPREAD_JITTER + FireSweep.BURN_S.y
	assert_lte(last, longest + TerrainEvent.PATH_TAIL_S, "the last tree burns out in time")
	assert_lt(longest + TerrainEvent.PATH_TAIL_S, TerrainEvent.MAX_PATH_DURATION_S, "under 6 s")
	# The ground's front along a path is timed by the same lobed arc the shader draws.
	var reach := GroundBurn.path_reach(Vector2(3, 0), 3.0, 2.0, 7)
	assert_between(reach, 3.0 - GroundBurn.lobe_m(2.0) * 0.5, 3.0 + GroundBurn.lobe_m(2.0) * 0.5)
	var code := (GroundBurn.SHADER as Shader).code
	assert_true(code.contains("path_points[64]"), "the shader takes the longest path")
	assert_eq(TerrainEvent.MAX_PATH_POINTS, 64)


func test_the_smoke_pool() -> void:
	# A fixed pool: a billow is born no larger than the crown it rises from and spreads to at
	# most about twice that while it shows (its erosion is done by 0.8 of its life), the pool
	# plays it out and empties, and a full pool overwrites its oldest rather than growing.
	assert_almost_eq(SmokePuffs.billow_size(0.0), SmokePuffs.START, 0.001, "born at START")
	assert_lte(SmokePuffs.billow_size(0.0), 1.0, "no larger than its crown at first")
	assert_lte(SmokePuffs.billow_size(0.8), 2.0 * SmokePuffs.START, "at most twice by 0.8")
	assert_gt(SmokePuffs.billow_size(1.0), 1.0, "still spreading at its end")
	assert_gt(SmokePuffs.billow_size(0.6), SmokePuffs.billow_size(0.3), "growing all its life")
	var smoke := SmokePuffs.new(2)
	add_child_autofree(smoke)
	assert_eq(smoke.multimesh.instance_count, 2)
	assert_eq(smoke.multimesh.mesh, SmokePuffs.crown_mesh(), "every pool shares one crown")
	for i in 3:
		smoke.emit(Vector3.ZERO, Vector3(0.0, 0.6, 0.0), 2.0, 1.0, Color.WHITE)
	assert_eq(smoke.live_count(), 2, "the oldest overwritten, the pool kept to its size")
	assert_eq(smoke.multimesh.instance_count, 2)
	smoke.step(0.5)
	assert_false(smoke.is_idle())
	smoke.step(0.6)
	assert_true(smoke.is_idle(), "every billow spent")


func test_the_smoke_crown() -> void:
	# A billow is a crown of small puff cards in a low dome: four corners a card, each card's
	# centre inside the dome, its half-size between the rim's and the middle's, its erosion rank
	# 0..1; the shader has eaten every card by 0.8 of the billow's life.
	var mesh := SmokePuffs.crown_mesh()
	var arrays := mesh.surface_get_arrays(0)
	var centres: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cards: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(centres.size(), SmokePuffs.CARDS * 4)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), SmokePuffs.CARDS * 6)
	for i in centres.size():
		var c := centres[i] / SmokePuffs.CROWN
		assert_lte(c.length(), 1.001, "card %d inside the dome" % i)
		assert_between(cards[i].x, SmokePuffs.CARD_HALF.y * 0.84, SmokePuffs.CARD_HALF.x * 1.16)
		assert_between(cards[i].y, 0.0, 1.0)
	var code := (load("res://shaders/fire_smoke.gdshader") as Shader).code
	var done := RegEx.create_from_string("ERODE_DONE = ([0-9.]+);").search(code)
	assert_not_null(done)
	if done != null:
		assert_lte(float(done.get_string(1)), 0.8, "no billow lingers past 0.8 of its life")


func test_the_ground_fire() -> void:
	# The ring runs out with the front: the nearest tree's distance at once, the rim at
	# SPREAD_S, held there.
	var near := 1.0
	var rim := 7.0
	var spread := FireSweep.SPREAD_S
	assert_almost_eq(GroundBurn.front_radius(0.0, near, rim, spread), near, 0.001)
	assert_almost_eq(GroundBurn.front_radius(spread, near, rim, spread), rim, 0.001)
	assert_lte(GroundBurn.front_radius(spread * 3.0, near, rim, spread), rim * 1.06, "held")
	# The ground's tongues rise where the ring is: when it reaches a distance is the inverse.
	var at := FireSweep.front_reaches(4.0, near, rim)
	assert_almost_eq(GroundBurn.front_radius(at, near, rim, spread), 4.0, 0.001)
	assert_eq(FireSweep.front_reaches(rim + 2.0, near, rim), spread, "never past the front's end")
	# Its glow comes in at once, holds while the front runs and dies soon after it reaches the
	# rim; the char stays until the ash lands at the event's end, then goes.
	var duration: float = TerrainEvent.DURATIONS[TerrainEvent.Kind.FIRE]
	assert_almost_eq(GroundBurn.glow_at(spread * 0.5, spread), 1.0, 0.001, "burning")
	assert_almost_eq(GroundBurn.glow_at(spread + 1.5, spread), 0.0, 0.001, "out")
	var glow_out := spread + GroundBurn.GLOW_HOLD_S + GroundBurn.GLOW_OUT_S
	assert_lte(glow_out, duration, "the glow is out before the ash lands")
	assert_almost_eq(GroundBurn.char_at(duration - 0.5, duration), 1.0, 0.001, "charred")
	assert_almost_eq(GroundBurn.char_at(duration + 1.0, duration), 0.0, 0.001, "under the ash")
	# The front is lobed: a point's reach is its distance moved by the lobe field, never by
	# more than half the lobe reach, and the field varies round the ring (lobes and bays).
	var lobe := GroundBurn.lobe_m(rim)
	var reaches: Array[float] = []
	for i in 24:
		var p := Vector2.from_angle(TAU * i / 24.0) * 5.0
		var r := GroundBurn.reach(p, rim, 7)
		assert_between(r, 5.0 - lobe * 0.5, 5.0 + lobe * 0.5)
		reaches.append(r)
	assert_gt(reaches.max() - reaches.min(), lobe * 0.2, "lobes and bays, not a circle")
	# The field wraps (its lattice is periodic, so the texture tiles without a seam).
	var here := GroundBurn.lobe_at(Vector2(0.3, 0.7))
	assert_almost_eq(here, GroundBurn.lobe_at(Vector2(1.3, -0.3)), 0.001)
	assert_between(here, 0.0, 1.0)


func test_the_painted_flame() -> void:
	var image := FlameAtlas.paint()
	assert_eq(image.get_size(), Vector2i(FlameAtlas.SIZE.x * FlameAtlas.FRAMES, FlameAtlas.SIZE.y))
	for frame in FlameAtlas.FRAMES:
		var x0 := frame * FlameAtlas.SIZE.x
		var middle := x0 + int(FlameAtlas.SIZE.x * 0.5)
		# The foot of the middle tongue is covered and hot; the frame's corners are bare.
		var foot := image.get_pixel(middle, FlameAtlas.SIZE.y - int(FlameAtlas.SIZE.y / 6.0))
		assert_gt(foot.g, 0.9, "the flame covers its foot (frame %d)" % frame)
		assert_gt(foot.r, 0.9, "its core burns there")
		assert_lt(image.get_pixel(x0, 0).g, 0.05, "the top corner is bare")
		assert_lt(image.get_pixel(x0, FlameAtlas.SIZE.y - 1).g, 0.05, "the foot's corner is bare")
		# Three bands: near the rim's edge the heat is the rim's alone.
		var edge_heat := image.get_pixel(middle, 4).r
		assert_lt(edge_heat, 0.6, "a tip burns at the rim's or amber's heat, not the core's")
