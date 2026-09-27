extends GutTest

## Gameplay on relief (phase 3, P3-3b): the drag target's ground re-resolve after the grid
## snap, the grid overlay's terrain height texture and fade centre, and the drag ruler's
## elevation label.

const GRASS := "grass"
const TIER := 1.524
const CELL := 1.524
const EPSILON := 1e-4

## Where the plateau starts (world X).
const EDGE_X := 0.5


## Ground at 0 for x < EDGE_X and one tier up beyond, like a plateau edge along Z.
func _two_tiers(point: Vector3) -> Vector3:
	return Vector3(point.x, TIER if point.x >= EDGE_X else 0.0, point.z)


func _miss(_point: Vector3) -> Vector3:
	return Vector3.INF


func _flat_doc(cells: int = 10) -> MapDocument:
	return MapDocument.create_flat(Vector2i(cells, cells), GRASS, "test", 5)


# --- DragAndDrop3D.resolve_target_ground ---------------------------------------------


func test_snapped_cell_across_a_tier_edge_takes_the_tier_height() -> void:
	# The cursor hits the low ground just short of the edge; the cell centre it snaps to is
	# on the plateau.
	var hit := Vector3(0.4, 0.0, 0.3)
	var target := DragAndDrop3D.resolve_target_ground(hit, true, CELL, Vector2.ZERO, _two_tiers)
	assert_almost_eq(target.x, CELL * 0.5, EPSILON, "snapped to the cell centre")
	assert_almost_eq(target.z, CELL * 0.5, EPSILON)
	assert_almost_eq(target.y, TIER, EPSILON, "on the tier the cell is on")


func test_snapped_cell_off_a_tier_drops_to_the_low_ground() -> void:
	# The cursor hits the plateau's rim; the cell centre (x = 0 with this origin) is below it.
	var hit := Vector3(0.6, TIER, 0.3)
	var target := DragAndDrop3D.resolve_target_ground(
		hit, true, CELL, Vector2(-CELL * 0.5, 0.0), _two_tiers
	)
	assert_almost_eq(target.x, 0.0, EPSILON, "the cell centre is on the low side")
	assert_almost_eq(target.y, 0.0, EPSILON)


func test_free_move_keeps_the_hit_xz_and_still_resolves_the_height() -> void:
	var hit := Vector3(0.6, 0.3, -2.0)
	var target := DragAndDrop3D.resolve_target_ground(hit, false, CELL, Vector2.ZERO, _two_tiers)
	assert_eq(Vector2(target.x, target.z), Vector2(0.6, -2.0))
	assert_almost_eq(target.y, TIER, EPSILON)


func test_without_a_resolver_the_snap_keeps_the_hit_height() -> void:
	# Blender maps: no resolver, exactly ScaleUtils.snap_to_grid as before.
	var hit := Vector3(-0.1, 0.37, 0.3)
	var target := DragAndDrop3D.resolve_target_ground(hit, true, CELL, Vector2.ZERO, Callable())
	assert_eq(target, ScaleUtils.snap_to_grid(hit, CELL, Vector2.ZERO))
	assert_eq(DragAndDrop3D.resolve_target_ground(hit, false, CELL, Vector2.ZERO, Callable()), hit)


func test_a_resolver_miss_keeps_the_hit_height() -> void:
	var hit := Vector3(-0.1, 0.37, 0.3)
	var target := DragAndDrop3D.resolve_target_ground(hit, true, CELL, Vector2.ZERO, _miss)
	assert_almost_eq(target.y, 0.37, EPSILON)
	assert_almost_eq(target.x, -CELL * 0.5, EPSILON)


# --- GridOverlay.look_center -------------------------------------------------------------


func test_look_center_without_terrain_is_the_floor_plane_hit() -> void:
	var origin := Vector3(10.0, 20.0, 10.0)
	var direction := Vector3(-0.5, -1.0, -0.5).normalized()
	var center := GridOverlay.look_center(origin, direction, 0.0)
	assert_almost_eq(center.y, 0.0, EPSILON)
	assert_almost_eq(center.x, 0.0, EPSILON)
	assert_almost_eq(center.z, 0.0, EPSILON)


func test_look_center_lands_on_raised_ground() -> void:
	var origin := Vector3(10.0, 20.0, 10.0)
	var direction := Vector3(-0.5, -1.0, -0.5).normalized()
	var plateau := func(_xz: Vector2) -> float: return 3.0
	var center := GridOverlay.look_center(origin, direction, 0.0, plateau)
	assert_almost_eq(center.y, 3.0, EPSILON, "on the plateau, not the Y = 0 plane")
	var along := (center - origin).normalized()
	assert_almost_eq(along.dot(direction), 1.0, EPSILON, "still on the view ray")


func test_look_center_follows_a_gentle_slope() -> void:
	var origin := Vector3(0.0, 30.0, 30.0)
	var direction := Vector3(0.0, -1.0, -1.0).normalized()
	var slope := func(xz: Vector2) -> float: return 1.0 + 0.1 * xz.y
	var center := GridOverlay.look_center(origin, direction, 0.0, slope)
	assert_gt(center.y, 1.0, "above the Y = 0 plane")
	assert_almost_eq(center.y, 1.0 + 0.1 * center.z, 0.02, "within a few cm of the ground under it")


func test_look_center_behind_the_camera_returns_the_origin() -> void:
	var origin := Vector3(0.0, -5.0, 0.0)
	var center := GridOverlay.look_center(origin, Vector3.DOWN, 0.0)
	assert_eq(center, origin)


# --- AuthoredTerrain height texture ------------------------------------------------------


func test_height_image_is_one_float_texel_per_sample() -> void:
	var doc := _flat_doc()
	doc.heights[doc.sample_index(3, 5)] = 2.75
	var image := TerrainMeshBuilder.height_image(doc)
	assert_eq(image.get_format(), Image.FORMAT_RF)
	assert_eq(image.get_size(), Vector2i(doc.samples_x(), doc.samples_z()))
	assert_almost_eq(image.get_pixel(3, 5).r, 2.75, EPSILON, "texel (x, z) is sample (x, z)")
	assert_almost_eq(image.get_pixel(5, 3).r, 0.0, EPSILON)


func test_height_texture_refreshes_when_a_height_edit_settles() -> void:
	var doc := _flat_doc()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var texture := terrain.get_height_texture()
	assert_eq(Vector2i(texture.get_size()), Vector2i(doc.samples_x(), doc.samples_z()))
	assert_false(terrain._height_texture_stale)
	# (The headless renderer keeps no texel data after an update, so the upload itself is
	# checked through the pure height_image above; here only when it happens.)
	doc.heights[doc.sample_index(4, 4)] = 1.5
	terrain.queue_heights(Rect2i(4, 4, 1, 1))
	terrain.process_heights()
	assert_true(terrain._height_texture_stale, "mid-stroke: still the heights of the last settle")
	terrain.settle_heights()
	assert_false(terrain._height_texture_stale, "refreshed when the edit settles")
	assert_same(terrain.get_height_texture(), texture, "updated in place, same texture")


func test_world_ground_height_applies_the_map_transform() -> void:
	var doc := _flat_doc()
	for z in doc.samples_z():
		for x in doc.samples_x():
			doc.heights[doc.sample_index(x, z)] = (
				TIER if doc.sample_to_world(Vector2(x, z)).x > 0.0 else 0.0
			)
	var identity := Transform3D.IDENTITY
	assert_almost_eq(
		TerrainMeshBuilder.world_ground_height(doc, identity, Vector2(3.0, 1.0)), TIER, EPSILON
	)
	assert_almost_eq(
		TerrainMeshBuilder.world_ground_height(doc, identity, Vector2(-3.0, 1.0)), 0.0, EPSILON
	)
	var placed := Transform3D(Basis.from_scale(Vector3(2.0, 2.0, 2.0)), Vector3(0.0, 0.5, 0.0))
	assert_almost_eq(
		TerrainMeshBuilder.world_ground_height(doc, placed, Vector2(6.0, 2.0)),
		0.5 + 2.0 * TIER,
		EPSILON,
		"the level's map scale and offset"
	)


# --- DragRuler.ruler_text ----------------------------------------------------------------


func test_ruler_text_on_flat_ground_is_the_distance_only() -> void:
	assert_eq(DragRuler.ruler_text(3.0 * CELL, 0.05, CELL, 5.0, "ft", false), "15 ft")
	assert_eq(DragRuler.ruler_text(3.0 * CELL, 0.0, CELL, 5.0, "ft", true), "3 cells / 15 ft")


func test_ruler_text_shows_the_elevation_like_the_measure_tool() -> void:
	var text := DragRuler.ruler_text(3.0 * CELL, TIER, CELL, 5.0, "ft", true)
	assert_eq(text, "3 cells / 15 ft  |  +5 ft elev  |  16 ft direct")
	var down := DragRuler.ruler_text(4.0 * CELL, -2.0 * TIER, CELL, 5.0, "ft", false)
	assert_eq(down, "20 ft  |  -10 ft elev  |  22 ft direct")
