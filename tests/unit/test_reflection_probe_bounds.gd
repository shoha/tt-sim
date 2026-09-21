extends GutTest

## A ReflectionProbe gives map geometry environmental reflection and ambient fill that
## the sky alone cannot reach into (every preset asks for REFLECTION_SOURCE_SKY, so
## anything not seeing open sky currently gets nothing). Unlike SDFGI it is anchored to
## world space, not the camera, so it is immune to the orthographic camera's habit of
## moving far away as camera.size grows. These cover the box the probe is given.

const MARGIN := LevelEnvironmentManager.PROBE_MARGIN_FACTOR
const MIN_HEIGHT := LevelEnvironmentManager.PROBE_MIN_HEIGHT


func test_probe_box_encloses_the_whole_map() -> void:
	var map := AABB(Vector3(-25.0, -1.0, -25.0), Vector3(50.0, 12.0, 50.0))

	var box := LevelEnvironmentManager.compute_probe_box(map)

	assert_true(box.encloses(map), "probe box should cover every map mesh")


func test_probe_box_is_centred_on_the_map() -> void:
	var map := AABB(Vector3(10.0, 0.0, -30.0), Vector3(40.0, 20.0, 60.0))

	var box := LevelEnvironmentManager.compute_probe_box(map)

	assert_almost_eq(box.get_center().x, map.get_center().x, 0.001)
	assert_almost_eq(box.get_center().y, map.get_center().y, 0.001)
	assert_almost_eq(box.get_center().z, map.get_center().z, 0.001)


func test_margin_expands_the_box_beyond_the_map_edges() -> void:
	var map := AABB(Vector3(-25.0, -1.0, -25.0), Vector3(50.0, 12.0, 50.0))

	var box := LevelEnvironmentManager.compute_probe_box(map)

	assert_almost_eq(box.size.x, 50.0 * (1.0 + MARGIN * 2.0), 0.001)
	assert_almost_eq(box.size.z, 50.0 * (1.0 + MARGIN * 2.0), 0.001)


## A perfectly flat map (an unsculpted plane with no props) has zero Y extent, and a
## probe with a zero-height box captures nothing at all.
func test_a_flat_map_still_gets_a_usable_height() -> void:
	var map := AABB(Vector3(-25.0, 0.0, -25.0), Vector3(50.0, 0.0, 50.0))

	var box := LevelEnvironmentManager.compute_probe_box(map)

	assert_gte(box.size.y, MIN_HEIGHT, "flat map must still get a volume")
	assert_almost_eq(box.get_center().y, 0.0, 0.001, "and stay centred on the ground")


func test_probe_is_sized_and_placed_from_the_map_bounds() -> void:
	var map := AABB(Vector3(-25.0, -1.0, -25.0), Vector3(50.0, 12.0, 50.0))
	var probe := ReflectionProbe.new()
	autofree(probe)

	LevelEnvironmentManager.configure_reflection_probe(probe, map)

	var box := LevelEnvironmentManager.compute_probe_box(map)
	assert_almost_eq(probe.size.x, box.size.x, 0.001)
	assert_almost_eq(probe.size.y, box.size.y, 0.001)
	assert_almost_eq(probe.size.z, box.size.z, 0.001)
	assert_almost_eq(probe.position.x, box.get_center().x, 0.001)
	assert_almost_eq(probe.position.y, box.get_center().y, 0.001)
	assert_almost_eq(probe.position.z, box.get_center().z, 0.001)


## The map is static once loaded, so the capture is a one-off at load rather than a
## per-frame re-render -- that is what keeps this affordable.
func test_probe_bakes_once_rather_than_every_frame() -> void:
	var probe := ReflectionProbe.new()
	autofree(probe)

	LevelEnvironmentManager.configure_reflection_probe(
		probe, AABB(Vector3(-5.0, 0.0, -5.0), Vector3(10.0, 5.0, 10.0))
	)

	assert_eq(probe.update_mode, ReflectionProbe.UPDATE_ONCE)


## interior = true would cut the sky out of the capture; the sky is the main ambient
## source in 10 of the 11 outdoor presets, so it has to keep contributing.
func test_probe_does_not_cut_the_sky_out_of_the_capture() -> void:
	var probe := ReflectionProbe.new()
	autofree(probe)

	LevelEnvironmentManager.configure_reflection_probe(
		probe, AABB(Vector3(-5.0, 0.0, -5.0), Vector3(10.0, 5.0, 10.0))
	)

	assert_false(probe.interior)


func _rooted(node: Node3D) -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	root.add_child(node)
	return root


func test_map_bounds_union_mesh_instances_in_world_space() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	mesh_inst.position = Vector3(10.0, 0.0, 0.0)
	var root := _rooted(mesh_inst)

	var bounds := LevelEnvironmentManager.compute_map_bounds(root)

	assert_almost_eq(bounds.get_center().x, 10.0, 0.01)
	assert_almost_eq(bounds.size.x, 1.0, 0.01)


## Scattered foliage is deliberately excluded: headless keeps no MultiMesh instance data
## (buffer empty, get_instance_transform reads back identity), so any bounds derived from
## it would differ silently between CI and a real renderer. Geometry outside the probe box
## just keeps the sky reflection it already has. Pinned so the exclusion stays a decision
## rather than drifting back in untested.
func test_map_bounds_exclude_multimesh_foliage() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var root := _rooted(mmi)

	var bounds := LevelEnvironmentManager.compute_map_bounds(root)

	assert_eq(bounds.size, Vector3.ZERO, "foliage alone yields no bounds")


func test_map_bounds_are_empty_when_there_is_no_geometry() -> void:
	var root := Node3D.new()
	add_child_autofree(root)

	var bounds := LevelEnvironmentManager.compute_map_bounds(root)

	assert_eq(bounds.size, Vector3.ZERO, "no meshes means no usable bounds")


class FakeGameMap:
	extends Node

	var map_container: Node3D


func _fake_map_with_geometry() -> FakeGameMap:
	var fake := FakeGameMap.new()
	add_child_autofree(fake)
	fake.map_container = Node3D.new()
	fake.add_child(fake.map_container)
	var terrain := MeshInstance3D.new()
	terrain.mesh = BoxMesh.new()
	fake.map_container.add_child(terrain)
	return fake


func test_a_probe_is_added_to_the_world_viewport() -> void:
	var mgr := LevelEnvironmentManager.new()
	mgr.setup(_fake_map_with_geometry())
	var viewport := Node3D.new()
	add_child_autofree(viewport)

	mgr.apply_reflection_probe(viewport)

	var probes := viewport.find_children("*", "ReflectionProbe", true, false)
	assert_eq(probes.size(), 1, "exactly one probe for the level")


func test_no_probe_is_added_for_a_map_with_no_geometry() -> void:
	var fake := FakeGameMap.new()
	add_child_autofree(fake)
	fake.map_container = Node3D.new()
	fake.add_child(fake.map_container)
	var mgr := LevelEnvironmentManager.new()
	mgr.setup(fake)
	var viewport := Node3D.new()
	add_child_autofree(viewport)

	mgr.apply_reflection_probe(viewport)

	assert_eq(viewport.find_children("*", "ReflectionProbe", true, false).size(), 0)


## Re-applying (a preset change mid-session) must not stack probes.
func test_reapplying_reuses_the_same_probe() -> void:
	var mgr := LevelEnvironmentManager.new()
	mgr.setup(_fake_map_with_geometry())
	var viewport := Node3D.new()
	add_child_autofree(viewport)

	mgr.apply_reflection_probe(viewport)
	mgr.apply_reflection_probe(viewport)

	assert_eq(viewport.find_children("*", "ReflectionProbe", true, false).size(), 1)


## _game_map is an untyped Node, so the manager cannot assume it exposes map_container
## (LevelEnvironmentManager has other callers and stubs that do not).
func test_no_probe_when_the_game_map_has_no_map_container() -> void:
	var bare := Node.new()
	add_child_autofree(bare)
	var mgr := LevelEnvironmentManager.new()
	mgr.setup(bare)
	var viewport := Node3D.new()
	add_child_autofree(viewport)

	mgr.apply_reflection_probe(viewport)

	assert_eq(viewport.find_children("*", "ReflectionProbe", true, false).size(), 0)
