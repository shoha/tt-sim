extends GutTest

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
const SETTLE_FRAMES := 900
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


func _make_level() -> void:
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "fire", SEED)
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
	var frames := 0
	while frames < SETTLE_FRAMES and (e.scatter.is_regenerating() or e.scatter.is_growing()):
		await get_tree().process_frame
		frames += 1
	doc.scatter = e.scatter.rows_by_asset()
	doc.props = e.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(doc, LEVEL), OK)
	remove_child(root)
	root.free()


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


func _settle(copies: Array) -> void:
	var frames := 0
	while frames < SETTLE_FRAMES and copies.any(_busy):
		await get_tree().process_frame
		frames += 1
	assert_lt(frames, SETTLE_FRAMES, "settled within %d frames" % SETTLE_FRAMES)
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
	await _settle([gm, client])
	return entry


func test_a_fire_burns_the_forest_on_every_board_then_changes_the_map() -> void:
	await _make_level()
	var gm := await _load(true)
	var client := await _load(false)
	await _settle([gm, client])
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
	await _settle([gm, client])
	assert_eq(_kinds(gm, 4), ["surface", "mask"], "the ash first, then the forest")
	assert_eq(_biome_at(gm.doc, FIRE_CENTRE), FOREST, "the forest is back")
	var back := FireSweep.burnable(gm.edits.editor.scatter, FIRE_CENTRE, RADIUS)
	assert_eq(back.size(), standing.size(), "every tree stands again")
	_same(gm, client, "after the undo")

	# A late joiner gets only the ops.
	var joiner := await _load(false)
	await _settle([joiner])
	joiner.edits.receive_log(key, gm.edits.op_log.size())
	for index in gm.edits.op_log.size():
		joiner.edits.receive_op(key, index, gm.edits.op_log[index])
	assert_eq(joiner.edits.events.active_count(), 0, "the late joiner sees no motion")
	await _settle([gm, joiner])
	_same(gm, joiner, "late joiner")


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
	# Its paint: the front's bands glow, the ground inside is charred, outside is bare.
	# (the painted front wanders out to about 0.92 of the texture's half size at angle 0)
	var front := GroundBurn.ring_paint(Vector2(0.92, 0.0), 0.5)
	var inside := GroundBurn.ring_paint(Vector2(0.2, 0.1), 0.5)
	var outside := GroundBurn.ring_paint(Vector2(0.99, 0.0), 0.5)
	assert_gt(front[1].r + front[1].g, 0.5, "the front glows")
	assert_gt(inside[0].a, 0.5, "the ground inside is charred")
	assert_eq(inside[1].r, 0.0, "and cold")
	assert_eq(outside[0].a, 0.0, "the ground outside is untouched")


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
