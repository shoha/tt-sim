extends GutTest

## PipelineWarmer (utils/pipeline_warmer.gd): where a warm-up instance goes, and that a
## headless run (which draws nothing) never warms, so AuthoredScatter tests see no extra
## node.


func test_view_ground_point_is_where_the_view_centre_meets_the_ground() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	camera.look_at_from_position(Vector3(10, 10, 10), Vector3(2, 0, -1), Vector3.UP)
	var size := Vector2(1920, 1080)
	var at := PipelineWarmer.view_ground_point(camera, size, 0.0)
	assert_almost_eq(at.y, 0.0, 1e-3, "on the ground plane")
	var origin := camera.project_ray_origin(size * 0.5)
	var toward := (at - origin).normalized()
	assert_almost_eq(
		toward.dot(camera.project_ray_normal(size * 0.5)), 1.0, 1e-3, "on the view centre's ray"
	)


func test_a_headless_run_never_warms() -> void:
	var node := Node3D.new()
	add_child_autofree(node)
	assert_false(PipelineWarmer.available(node), "no renderer to compile for")
	var scatter := AuthoredScatter.create()
	add_child_autofree(scatter)
	await wait_process_frames(2)
	assert_null(scatter.get_node_or_null("PipelineWarmer"), "no warm-up child in tests")


func test_a_headless_run_never_warms_a_plain_mesh() -> void:
	var warmer := PipelineWarmer.new()
	add_child_autofree(warmer)
	warmer.warm_mesh(BoxMesh.new(), "box")
	assert_eq(warmer.pending_count(), 0, "nothing to draw headless")
	assert_eq(warmer.get_child_count(), 0, "no warm-up child")
