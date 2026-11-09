extends GutTest

## What the ground clipmap rebakes after a change (card clipmap4): a restamp of the look's grass
## masses announces the rectangle of the masses that changed (a sun change still bakes whole), a
## Paint stroke's closing re-plan emits no edit, and the clipmap patches those rectangles, draws a
## strip in parts and frees its strip viewports when idle.

const BIOME := "grassland_meadow_summer_s1"
const MASS := {
	"shade": 0.3, "lift": 0.1, "shade_size": 1.0, "shade_push": 0.2, "lift_size": 1.2, "lift_push": 0.3
}

var _edits: Array[Rect2i] = []
var _restamped: Array[Rect2] = []


## The moments of `n` tufts about `at` with a 0.5 m spread (GroundMassStamps.collect's form).
func _moments(at: Vector2, n: float = 8.0) -> PackedFloat64Array:
	return PackedFloat64Array(
		[n, n * at.x, n * at.y, n * (at.x * at.x + 0.25), n * (at.y * at.y + 0.25), n * at.x * at.y]
	)


func _looked_terrain() -> AuthoredTerrain:
	var biome := PaletteLibrary.biome(BIOME)
	var doc := MapDocument.create_flat(Vector2i(16, 16), String(biome.ground_surface), "", 1234)
	doc.biome_ids = PackedStringArray([BIOME])
	var level := Node3D.new()
	add_child_autofree(level)
	var terrain := AuthoredTerrain.create(doc)
	level.add_child(terrain)
	return terrain


func _grass(anchor: Vector2, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = count
	for i in count:
		var at := anchor + Vector2.from_angle(TAU * i / count) * (0.2 + 0.05 * i)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(at.x, 0.0, at.y)))
		mm.set_instance_custom_data(i, Color(0.0, anchor.x - at.x, anchor.y - at.y, 1.0))
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	return node


func test_the_changed_rect_bounds_only_the_masses_that_changed() -> void:
	var a := Vector2i(1, 1)
	var b := Vector2i(2, 2)
	var before := {a: _moments(Vector2(-6.0, -6.0)), b: _moments(Vector2(5.0, 5.0))}
	assert_false(
		GroundMassStamps.changed_rect(before, before.duplicate(true), [MASS]).has_area(),
		"nothing changed: no rectangle"
	)
	var after := {a: _moments(Vector2(-6.0, -6.0)), b: _moments(Vector2(5.5, 5.0))}
	var moved := GroundMassStamps.changed_rect(before, after, [MASS])
	assert_true(moved.has_point(Vector2(5.0, 5.0)), "the old place")
	assert_true(moved.has_point(Vector2(5.5, 5.0)), "and the new")
	assert_false(moved.has_point(Vector2(-6.0, -6.0)), "the unchanged mass is left out")
	# Its stamp: an ellipse of 2 sd (1 m) times the size, pushed up to its extent; corners in.
	assert_true(moved.has_point(Vector2(5.0 + 1.6, 5.0)), "the stamp's reach is inside")
	var gone := GroundMassStamps.changed_rect(before, {a: before[a]}, [MASS])
	assert_true(gone.has_point(Vector2(5.0, 5.0)), "a mass that went")
	var thin := {a: before[a], b: before[b], Vector2i(9, 9): _moments(Vector2(0.0, 0.0), 3.0)}
	assert_false(
		GroundMassStamps.changed_rect(before, thin, [MASS]).has_area(),
		"a group under MIN_TUFTS draws no stamp, so adding one changes nothing"
	)


func test_a_restamp_announces_its_masses_and_a_sun_change_bakes_whole() -> void:
	var terrain := _looked_terrain()
	var bake := terrain.ground_look()
	assert_not_null(bake, "the meadow makes a bake")
	bake.masses_restamped.connect(func(r: Rect2) -> void: _restamped.append(r))
	_restamped.clear()
	terrain.get_parent().add_child(_grass(Vector2(3.0, 3.0), 8))
	var bakes := bake.bakes
	bake._restamp()
	assert_eq(_restamped.size(), 1, "a new mass: announced")
	# (Headless MultiMeshes read their transforms back as zero, so the mass sits at the origin
	# here; where a rectangle lands is checked above on moments.)
	assert_true(_restamped[0].has_area(), str(_restamped[0]))
	assert_lt(_restamped[0].get_area(), 25.0, "about the mass, not the map")
	assert_eq(bake.bakes, bakes, "not a whole bake")
	assert_eq(bake.restamps, 1)
	bake._restamp()
	assert_eq(_restamped.size(), 1, "nothing changed since: nothing announced")
	bake._stamped_sun = Vector2(1.0, 0.0)  # as if the sun had moved since the last draw
	bake._restamp()
	assert_eq(bake.bakes, bakes + 1, "a sun change moves every stamp: a whole bake")
	assert_eq(_restamped.size(), 1)


func test_an_empty_replan_emits_no_edit() -> void:
	var terrain := _looked_terrain()
	terrain.ground_edited.connect(func(r: Rect2i) -> void: _edits.append(r))
	_edits.clear()
	terrain.update_ground_region(Rect2i())
	assert_true(_edits.is_empty(), "a re-plan that redrew no sample (a Paint stroke's end)")
	terrain.update_ground_region(Rect2i(2, 3, 4, 5))
	assert_eq(_edits, [Rect2i(2, 3, 4, 5)] as Array[Rect2i], "a refreshed rectangle is emitted")


func test_the_clipmap_patches_a_restamp_and_bakes_whole_past_half_the_map() -> void:
	var terrain := _looked_terrain()
	var cm := GroundClipmap.new()
	cm.terrain = terrain
	terrain.add_child(cm)
	cm._process(0.016)  # connects the look
	terrain.ground_look().masses_restamped.emit(Rect2(1.0, 1.0, 2.0, 2.0))
	assert_true(cm._has_dirty, "the hole opens over the masses")
	assert_true(cm._dirty.encloses(Rect2(1.0, 1.0, 2.0, 2.0)))
	assert_lt(cm._dirty.get_area(), 7.0, "grown by a texel and the pad only")
	cm._signature = [1]
	var ext := terrain.document.extent_m()
	terrain.ground_look().masses_restamped.emit(Rect2(-ext * 0.5, ext))
	assert_eq(cm._signature, [], "a restamp over most of the map rebakes whole")


func test_a_strip_draws_in_parts_and_its_viewports_go_when_idle() -> void:
	var terrain := _looked_terrain()
	var cm := GroundClipmap.new()
	cm.terrain = terrain
	terrain.add_child(cm)
	cm._levels[2] = cm._make_level(2)
	var job := GroundClipmapPlan.next_job(Rect2i(), Rect2i(-4, -4, 8, 8))
	assert_true(cm._begin_job(2, job), "the strips are made for the job")
	assert_eq(cm.strip_viewport_count(), 4)
	assert_eq(cm._parts.size(), 2, "a whole strip is two parts")
	assert_eq(cm.texels_baked, GroundClipmapPlan.PART_TEXELS, "one part drawn")
	cm._stage = 0
	cm._job = {}
	cm._release_idle(1.0)
	assert_eq(cm.strip_viewport_count(), 4, "kept while recently busy")
	cm._release_idle(GroundClipmap.STRIPS_IDLE_S)
	assert_eq(cm.strip_viewport_count(), 0, "freed once idle")
	assert_true(cm._begin_job(2, job), "and made again on demand")
	assert_eq(cm.strip_viewport_count(), 4)
