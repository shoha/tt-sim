extends GutTest

## GraphicsWarmupScreen: the phases run to DONE, the marker is written only on completion,
## empty samples are skipped with a warning, and freeing the screen mid-build joins the
## worker. Headless, so the draw phase has nothing to draw and finishes at once.

const SCENE := preload("res://scenes/states/warmup/graphics_warmup_screen.tscn")
const MARKER := "user://test_graphics_warmup_screen_marker.cfg"


func after_each() -> void:
	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER))


func _screen(source: Callable) -> GraphicsWarmupScreen:
	var screen: GraphicsWarmupScreen = SCENE.instantiate()
	screen.sample_sources = [source]
	screen.marker_path = MARKER
	screen.shader_paths = ["res://shaders/water.gdshader"]
	return screen


func _done(screen: GraphicsWarmupScreen) -> Callable:
	return func() -> bool: return screen.phase == GraphicsWarmupScreen.Phase.DONE


func _triangle_sample(sample_name: String) -> Dictionary:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	return {
		"name": sample_name,
		"primitive": Mesh.PRIMITIVE_TRIANGLES,
		"arrays": arrays,
		"material": GraphicsWarmup.material_for(load("res://shaders/water.gdshader")),
		"multimesh": false,
	}


func test_no_samples_still_finish_and_write_the_marker() -> void:
	var screen := _screen(func() -> Array: return [])
	watch_signals(screen)
	add_child_autofree(screen)
	await wait_until(_done(screen), 10.0, "reaches DONE")
	assert_signal_emitted(screen, "finished")
	assert_eq(GraphicsWarmup.read_marker(MARKER), GraphicsWarmup.cache_key(), "marker written")
	assert_eq(screen.progress(), 1.0)


func test_a_real_sample_is_built() -> void:
	var screen := _screen(func() -> Array: return [_triangle_sample("tri")])
	add_child_autofree(screen)
	await wait_until(_done(screen), 10.0, "reaches DONE")
	assert_eq(screen.built_names(), PackedStringArray(["tri"]))


func test_a_sample_without_geometry_is_skipped_with_a_warning() -> void:
	var empty := _triangle_sample("empty")
	empty["arrays"] = []
	var screen := _screen(func() -> Array: return [empty, _triangle_sample("tri")])
	watch_signals(screen)
	add_child_autofree(screen)
	await wait_until(_done(screen), 10.0, "reaches DONE")
	assert_eq(screen.built_names(), PackedStringArray(["tri"]), "the empty one is skipped")
	assert_engine_error(1, "one warning, pushed on the main thread")
	assert_signal_emitted(screen, "finished")
	assert_eq(GraphicsWarmup.read_marker(MARKER), GraphicsWarmup.cache_key(), "still marked")


func test_texture_blit_shaders_are_queued_for_the_worker() -> void:
	var blit := "res://shaders/texel_copy_blit.gdshader"
	var screen := _screen(func() -> Array: return [])
	screen.shader_paths = ["res://shaders/water.gdshader", blit]
	add_child_autofree(screen)
	await wait_until(_done(screen), 10.0, "reaches DONE")
	assert_eq(screen.worker_shader_paths(), PackedStringArray([blit]))


func test_freed_mid_build_joins_and_writes_no_marker() -> void:
	var slow := func() -> Array:
		OS.delay_msec(500)
		return []
	var screen := _screen(slow)
	add_child(screen)
	await wait_until(
		func() -> bool: return screen.phase == GraphicsWarmupScreen.Phase.BUILD, 10.0, "builds"
	)
	# Not free(): Object.free() refuses while the worker is inside the screen's _build call.
	# queue_free() runs _exit_tree, which joins the worker, before the node is destroyed.
	var screen_id := screen.get_instance_id()
	screen.queue_free()
	await wait_until(func() -> bool: return not is_instance_id_valid(screen_id), 5.0, "freed")
	assert_false(FileAccess.file_exists(MARKER), "an interrupted warm-up runs again next time")


func test_progress_is_weighted_by_phase() -> void:
	const PHASE := GraphicsWarmupScreen.Phase
	assert_eq(GraphicsWarmupScreen.progress_for(PHASE.COMPILE, 0, 10), 0.0)
	assert_almost_eq(GraphicsWarmupScreen.progress_for(PHASE.COMPILE, 10, 10), 0.2, 1e-6)
	assert_almost_eq(GraphicsWarmupScreen.progress_for(PHASE.BUILD, 1, 2), 0.55, 1e-6)
	assert_almost_eq(
		GraphicsWarmupScreen.progress_for(PHASE.BUILD, 0, 0), 0.2, 1e-6, "no samples yet"
	)
	assert_almost_eq(GraphicsWarmupScreen.progress_for(PHASE.DRAW, 0, 1), 0.9, 1e-6)
	assert_eq(GraphicsWarmupScreen.progress_for(PHASE.DONE, 0, 0), 1.0)


func test_build_progress_moves_during_collection_and_never_steps_back() -> void:
	const PHASE := GraphicsWarmupScreen.Phase
	# [collected, sources, built, total], in the order the worker reaches them.
	var steps := [[0, 3, 0, 0], [1, 3, 0, 0], [2, 3, 0, 0], [3, 3, 0, 0], [3, 3, 0, 4]]
	steps.append_array([[3, 3, 1, 4], [3, 3, 4, 4]])
	var last := GraphicsWarmupScreen.progress_for(PHASE.COMPILE, 1, 1)
	for step in steps:
		var now := GraphicsWarmupScreen.build_progress(step[0], step[1], step[2], step[3])
		assert_true(now >= last, "%s does not step back (%f after %f)" % [step, now, last])
		last = now
	assert_gt(
		GraphicsWarmupScreen.build_progress(1, 3, 0, 0),
		GraphicsWarmupScreen.build_progress(0, 3, 0, 0),
		"a collected source moves the bar"
	)
	assert_almost_eq(last, GraphicsWarmupScreen.progress_for(PHASE.DRAW, 0, 1), 1e-6, "meets DRAW")


func test_the_bar_moves_while_a_later_source_is_still_collecting() -> void:
	var gate := Semaphore.new()
	# Bounded, so a failing test cannot leave the worker blocked.
	var held := func() -> Array:
		var deadline := Time.get_ticks_msec() + 5000
		while not gate.try_wait() and Time.get_ticks_msec() < deadline:
			OS.delay_msec(5)
		return []
	var screen := _screen(func() -> Array: return [])
	screen.sample_sources.append(held)
	add_child_autofree(screen)
	var start := GraphicsWarmupScreen.build_progress(0, 2, 0, 0)
	await wait_until(func() -> bool: return screen.progress() > start, 5.0, "moves")
	assert_eq(screen.phase, GraphicsWarmupScreen.Phase.BUILD, "still collecting")
	assert_almost_eq(screen.progress(), GraphicsWarmupScreen.build_progress(1, 2, 0, 0), 1e-6)
	gate.post()
	await wait_until(_done(screen), 10.0, "reaches DONE")
