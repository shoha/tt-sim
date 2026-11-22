extends GutTest
## The water half of the bridge (TerraWaterBridge, card terraform-p2-bridge-water;
## docs/systems/terraform.md "The bridge"): the derive's water records and falls as today's water
## model. On the corpus: one body per flat reach and one per pond, valid for the map writer; the
## wet set WaterGeometry.levels() makes against the derive's WL > H2 at the document samples (only
## shoreline samples may differ; the count is printed); the falls today's model finds against the
## derive's fall records; ids stable across a reload and a late join; a river drawn past the edge
## keeps its course into the skirt; the caps refused, never truncated; the loaded map's
## AuthoredWater and Painted water field built.

## The corpus at its own 200 ft (40 cells).
const CELLS := Vector2i(40, 40)
const MAX_FRAMES := 600
const FALL_TOLERANCE_M := 0.25
const SCRATCH := "user://_terraform-p2-bridge-water_ids.ttmap"


func after_each() -> void:
	TerraCore.switch_override = null
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## The corpus's map document with the derive's heights and water written (as the bridge's load
## swap does), and the derive. [MapDocument, TerraDerive].
func _bridged() -> Array:
	var c := TerraCorpus.build(CELLS)
	var doc := c.map_doc
	var derive := TerraCache.derive_for(c.terra, doc)
	doc.heights = derive.call("doc_heights")
	var water := TerraBridge.water_of(derive, doc)
	assert_false(water.has("error"), "converted: %s" % water.get("error", ""))
	doc.water_bodies = water.get("bodies", [] as Array[WaterBody])
	doc.pond_mask = water.get("pond_mask", PackedByteArray())
	return [doc, derive]


func test_runs_and_depth_classes() -> void:
	var runs := TerraWaterBridge.level_runs(PackedFloat32Array([3, 3, 3, 2.5, 2.5, 1.0]))
	assert_eq(runs, [Vector2i(0, 2), Vector2i(3, 4), Vector2i(5, 5)] as Array[Vector2i])
	assert_eq(TerraWaterBridge.depth_class(0.3), WaterBody.Depth.ANKLE)
	assert_eq(TerraWaterBridge.depth_class(0.45), WaterBody.Depth.ANKLE)
	assert_eq(TerraWaterBridge.depth_class(0.6), WaterBody.Depth.WAIST, "a tie takes the deeper")
	assert_eq(TerraWaterBridge.depth_class(0.9), WaterBody.Depth.WAIST)
	assert_eq(TerraWaterBridge.depth_class(2.0), WaterBody.Depth.DEEP)


func test_the_corpus_becomes_one_body_per_reach_and_pond() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var got := _bridged()
	var doc: MapDocument = got[0]
	var derive: RefCounted = got[1]
	var records: Dictionary = derive.call("water_records")
	var reaches := 0
	for r: Dictionary in records["rivers"]:
		reaches += TerraWaterBridge.level_runs(r["level"]).size()
	var rivers := 0
	var ids := []
	for body in doc.water_bodies:
		rivers += 1 if body.is_river() else 0
		ids.append(body.id)
	assert_eq(rivers, reaches, "one river body per run of equal levels")
	assert_eq(doc.water_bodies.size() - rivers, (records["ponds"] as Array).size(), "one per pond")
	assert_eq(ids, range(1, doc.water_bodies.size() + 1), "ids in document order from 1")
	assert_eq(MapWaterIO.bodies_problem(doc), "", "the writer takes the bodies")
	assert_eq(MapWaterIO.grids_problem(doc, MapWaterIO.pond_ids(doc)), "", "and the mask")
	var pond := doc.water_bodies[-1]
	assert_false(pond.is_river())
	assert_gt(doc.pond_mask.count(pond.id), 100, "the pond's outline rasterised")
	var first_level := doc.water_bodies[0].level_m
	assert_gt(first_level, doc.water_bodies[reaches - 1].level_m, "reaches run downstream")


func test_the_wet_set_matches_the_derive_but_at_the_shore() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var got := _bridged()
	var doc: MapDocument = got[0]
	var derive: RefCounted = got[1]
	var wl := (derive.call("array_bytes", "WL") as PackedByteArray).to_float32_array()
	var h2 := (derive.call("array_bytes", "H2") as PackedByteArray).to_float32_array()
	var levels := WaterGeometry.levels(doc)
	var nx := doc.samples_x()
	var nz := doc.samples_z()
	var w := 2 * (nx - 1) + 1
	var core := PackedByteArray()
	var today := PackedByteArray()
	core.resize(doc.sample_count())
	today.resize(doc.sample_count())
	var wet := 0
	for b in nz:
		for a in nx:
			var o := 2 * b * w + 2 * a
			var k := b * nx + a
			core[k] = 1 if wl[o] > h2[o] else 0
			today[k] = 1 if doc.heights[k] < levels[k] else 0
			wet += core[k]
	var differ := 0
	var inland := 0
	for b in nz:
		for a in nx:
			var k := b * nx + a
			if core[k] == today[k]:
				continue
			differ += 1
			inland += 0 if _on_shore(core, today, nx, nz, a, b) else 1
	var said := "wet set: %d derive-wet samples, %d differ, %d of them off the shore"
	gut.p(said % [wet, differ, inland])
	assert_gt(wet, 1000, "the corpus has water")
	assert_eq(inland, 0, "only shoreline samples differ")
	assert_lt(differ, wet / 10, "a thin band")


func test_falls_match_the_derives_records() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var got := _bridged()
	var doc: MapDocument = got[0]
	var derive: RefCounted = got[1]
	var records: PackedFloat32Array = derive.call("falls")
	var falls := WaterFalls.falls(doc)
	assert_gt(records.size(), 0, "the corpus has a fall")
	assert_eq(falls.size(), records.size() / 7, "one fall today per fall record")
	for k in range(0, records.size() - 6, 7):
		var at := Vector2(records[k], records[k + 1])
		var best := INF
		var nearest: Dictionary = {}
		for fall in falls:
			var d := (fall.lip as Vector2).distance_to(at)
			if d < best:
				best = d
				nearest = fall
		assert_lt(best, FALL_TOLERANCE_M, "the lip at the record")
		if not nearest.is_empty():
			gut.p(
				(
					"fall: lip %.4f m from the record, top %+.4f, bottom %+.4f"
					% [best, float(nearest.top) - records[k + 4], float(nearest.bottom) - records[k + 5]]
				)
			)
			assert_almost_eq(float(nearest.top), records[k + 4], FALL_TOLERANCE_M, "top")
			assert_almost_eq(float(nearest.bottom), records[k + 5], FALL_TOLERANCE_M, "bottom")


func test_a_river_past_the_edge_keeps_its_course_and_caps_are_refused() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var doc := MapDocument.create_flat(Vector2i(24, 24), "grass", "v", 3)
	var half := doc.extent_m().x * 0.5
	var terra := TerraDoc.new()
	# Falling toward +x, so the water flows out of the map there.
	terra.add(TerraCore.PLANE, PackedFloat32Array([4.0, -0.03, 0.0]))
	var line := [2.0, 0.9, -8.0, 0.0, half - 4.0, 0.0, half + 9.0, 1.0]
	terra.add(TerraCore.RIVER, PackedFloat32Array(line))
	doc.terra = terra
	var derive := TerraCache.derive_for(terra, doc)
	doc.heights = derive.call("doc_heights")
	var water := TerraBridge.water_of(derive, doc)
	assert_false(water.has("error"))
	doc.water_bodies = water.get("bodies", [] as Array[WaterBody])
	assert_gt(doc.water_bodies.size(), 0, "a river")
	assert_eq(MapWaterIO.bodies_problem(doc), "", "every point on the map")
	if doc.water_bodies.is_empty():
		return
	var last := doc.water_bodies[-1]
	assert_gt(last.beyond.size(), 0, "the drawn course past the edge")
	assert_eq(doc.water_bodies[0].depth, WaterBody.Depth.WAIST)
	var drawn := 0
	for exit: Dictionary in RiverExits.exits(doc):
		drawn += 1 if exit.drawn else 0
	assert_eq(drawn, 1, "one drawn exit")
	# Past the river cap: 33 short rivers on the flat, one reach each.
	var full := TerraDoc.new()
	full.add(TerraCore.PLANE, PackedFloat32Array([4.0, 0.0, 0.0]))
	for k in MapDocument.MAX_RIVERS + 1:
		var z := -half + 1.0 + k * (2.0 * half - 2.0) / MapDocument.MAX_RIVERS
		full.add(TerraCore.RIVER, PackedFloat32Array([0.6, 0.3, -6.0, z, -2.0, z]))
	doc.terra = full
	var capped := TerraBridge.water_of(TerraCache.derive_for(full, doc), doc)
	assert_true(capped.has("error"), "refused")
	assert_false(capped.has("bodies"), "not truncated")


func test_ids_are_stable_across_a_reload_and_a_late_join() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	doc.terra = TerraCorpus.build(CELLS).terra
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	var host: Array[WaterBody] = doc.water_bodies
	assert_gt(host.size(), 10, "the load wrote the derived water")
	add_child(root)
	await _built(root, doc)
	root.free()
	assert_eq(MapDocumentIO.write(doc, SCRATCH), OK)
	var reread: MapDocument = MapDocumentIO.read(SCRATCH)["document"]
	var entries: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	var joined: MapDocument = MapDocumentIO.parse(entries)["document"]
	for other: MapDocument in [reread, joined]:
		assert_not_null(other)
		if other == null:
			continue
		# The joiner's own derive decides: what arrived is dropped first.
		other.water_bodies = [] as Array[WaterBody]
		other.pond_mask = PackedByteArray()
		var again := await MapSourceLoader.new(get_tree()).build_async("", other)
		assert_eq(other.water_bodies.size(), host.size(), "as many bodies")
		var off := 0
		for k in mini(host.size(), other.water_bodies.size()):
			var a := host[k]
			var b := other.water_bodies[k]
			off += 0 if a.id == b.id and TerraWaterBridge.same(a, b) else 1
		assert_eq(off, 0, "the same bodies under the same ids")
		assert_eq(other.pond_mask, doc.pond_mask, "the same pond mask")
		again.free()


## The loaded map's water: AuthoredWater swapped in with geometry, and the Painted water field
## attached over it.
func _built(root: Node3D, doc: MapDocument) -> void:
	var water := root.get_node_or_null(NodePath(AuthoredWater.NODE_NAME)) as AuthoredWater
	assert_not_null(water, "AuthoredWater built")
	if water != null:
		water.finish_refresh()
		assert_gt(water.get_child_count(), 0, "with its surface")
	assert_gt(doc.water_flow.size(), 0, "the flow baked for the derived bodies")
	var field := PainterWaterField.new()
	var material := ShaderMaterial.new()
	material.shader = load(PainterWater.SHADER) as Shader
	assert_true(field.attach(root, material), "the Painted water field attached")
	for i in 3:
		await get_tree().process_frame
	field.finish_update()
	field.detach()


## True when sample (a, b) lies on the shoreline of either wet set: an 8-neighbour of it is in the
## other state in that set.
func _on_shore(
	core: PackedByteArray, today: PackedByteArray, nx: int, nz: int, a: int, b: int
) -> bool:
	var k := b * nx + a
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var x: int = a + dx
			var z: int = b + dz
			if x < 0 or z < 0 or x >= nx or z >= nz:
				continue
			var j := z * nx + x
			if core[j] != core[k] or today[j] != today[k]:
				return true
	return false
