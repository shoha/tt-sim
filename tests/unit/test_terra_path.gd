extends GutTest
## The path kind (6) with its surface (card terraform-p2-paint-path): it grades itself to its
## maximum slope, steps where a bench would cut too deep, paints its surface along its line and into
## the water as a ford, and the Path release through the editor is one entry with exact undo.

const PathKind := preload("res://utils/terraform/kinds/path/path_kind.gd")
## The kind's grade (terra_kind_path.cpp PATH_SLOPE) and the slack of a resampled, smoothed profile.
const MAX_SLOPE := 0.18
const SLACK := 0.03

var _rigs: Array[TerraRig] = []


func after_each() -> void:
	TerraCore.switch_override = null
	for rig in _rigs:
		if is_instance_valid(rig.root):
			rig.root.free()
	_rigs.clear()


## A document of one plane rising `slope` along z and a path straight up it, derived.
func _slope(c: TerraCorpus, slope: float) -> RefCounted:
	var t := TerraDoc.new()
	t.surfaces = PackedStringArray(["dirt_road_packed"])
	t.add(TerraCore.PLANE, PackedFloat32Array([2.0, 0.0, slope]))
	var line := PackedVector2Array([Vector2(3, -20), Vector2(3, 20)])
	t.add(TerraCore.PATH, PathKind.make(1.6, 0, line))
	return TerraCache.derive_for(t, c.map_doc)


## The slope along the path's centre between z and z + dz.
func _rise(derive: RefCounted, z: float, dz: float) -> float:
	return (
		(float(derive.call("height_at", 3.0, z + dz)) - float(derive.call("height_at", 3.0, z)))
		/ dz
	)


func test_a_path_grades_to_its_maximum_slope() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build(Vector2i(TerraCorpus.CELLS, TerraCorpus.CELLS), false)
	var gentle := _slope(c, 0.1)
	for k in 30:
		var z := -15.0 + k
		assert_lte(_rise(gentle, z, 1.0), MAX_SLOPE + SLACK, "gentle: graded at z %.0f" % z)
		var ground := 2.0 + 0.1 * z
		assert_almost_eq(float(gentle.call("height_at", 3.0, z)), ground, 0.35, "on the ground")


func test_a_steep_path_steps() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build(Vector2i(TerraCorpus.CELLS, TerraCorpus.CELLS), false)
	var steep := _slope(c, 0.5)
	var treads := 0
	var risers := 0
	for k in 120:
		var r := _rise(steep, -14.0 + k * 0.25, 0.25)
		if r < MAX_SLOPE + SLACK:
			treads += 1
		elif r > 0.7:
			risers += 1
	assert_gt(treads, 10, "the steep path has treads")
	assert_gt(risers, 3, "and risers between them")


func test_a_path_paints_into_the_water_as_a_ford() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build(Vector2i(TerraCorpus.CELLS, TerraCorpus.CELLS), false)
	c.terra.surfaces = PackedStringArray(["gravel"])
	# Across the corpus river (layout x 28 to 34 near z 30).
	var line := PackedVector2Array([c.at(22, 30), c.at(40, 30)])
	c.add(TerraCore.PATH, PathKind.make(1.6, 0, line))
	var derive := TerraCache.derive_for(c.terra, c.map_doc)
	var doc := c.map_doc
	var planes: PackedByteArray = derive.call("doc_surfaces", Rect2i())
	var plane := doc.sample_count() * MapDocument.SURFACE_CHANNELS
	var wet_painted := 0
	for k in 72:
		var p: Vector2 = line[0].lerp(line[1], k / 71.0)
		if float(derive.call("water_at", p.x, p.y)) <= float(derive.call("height_at", p.x, p.y)):
			continue
		var s := Vector2i(doc.world_to_sample(p).round())
		if planes[plane + (s.y * doc.samples_x() + s.x) * 4] > 200:
			wet_painted += 1
	assert_gt(wet_painted, 0, "the path's surface runs into the water (the ford)")


func test_the_path_release_is_one_entry_with_exact_undo() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var rig := await TerraRig.build(self)
	_rigs.append(rig)
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the load settles")
	var digest_before := (rig.doc.terra as TerraDoc).digest_for(rig.doc)
	var heights_before := rig.doc.heights.duplicate()
	var line := PackedVector2Array([rig.corpus.at(12, 20), rig.corpus.at(22, 26)])
	var id := rig.editor.terra.paint.add_path(line, 1.6, "gravel")
	assert_gt(id, 0, "the release adds a path")
	assert_true(await TerraRig.settle(get_tree(), [rig]), "settles")
	assert_ne(rig.doc.heights, heights_before, "the path benched the ground")
	assert_true(rig.doc.surface_ids.has("gravel"), "and painted its surface")
	rig.history.undo()
	assert_true(await TerraRig.settle(get_tree(), [rig]), "the undo settles")
	assert_eq((rig.doc.terra as TerraDoc).digest_for(rig.doc), digest_before, "undo: the digest")
	assert_true(rig.doc.heights == heights_before, "undo: the heights")
