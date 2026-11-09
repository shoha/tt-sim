extends GutTest

## The performance budget (topic perfguard): every counter of tools/perf_budget_counters.gd is
## within its limit. The counters are deterministic (bytes, surfaces, nodes, tiles, what a shader
## writes or fetches, settings), so a failure is a real change in the code, never a slow machine:
## the message names the counter, its value, its budget, the value it read when the guard was set
## and the audit finding and commit it holds (docs/PERFORMANCE.md "Performance audit 2026-11").
## Raising a limit is a decision: measure the cost it stands for first.

const Counters := preload("res://tools/perf_budget_counters.gd")

var _old_scene: Node = null
var _scene: Node = null


## DraggingObject3D waits on the current scene when it enters the tree: a bare node stands in.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "PerfBudgetTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


func _assert_within(rows: Array[Dictionary]) -> void:
	assert_gt(rows.size(), 0, "the group has counters")
	for row in rows:
		assert_true(Counters.ok(row), Counters.message(row))


func test_net_bytes_are_within_budget() -> void:
	_assert_within(Counters.net_rows())


func test_token_counts_are_within_budget() -> void:
	_assert_within(Counters.token_rows(_scene))
	assert_gt(LoadPacing.COVERED_MAX_FPS, 0, "the covered load keeps a frame cap")


func test_authoring_counts_are_within_budget() -> void:
	_assert_within(Counters.authoring_rows())


func test_map_document_rows_are_within_budget() -> void:
	_assert_within(Counters.document_rows())


func test_render_settings_and_shader_outputs_are_within_budget() -> void:
	_assert_within(Counters.render_rows())


## The shader counters read zero because the shipped code has none of what they count, not
## because the reader misses it: the probe-only path that ran the blend in the pre-pass, the
## canopy foliage shader and a skirt without the render mode all show up.
func test_the_shader_reader_sees_what_it_guards() -> void:
	var ground := "res://shaders/authored_ground.gdshader"
	var shipped := Counters.function_body(Counters.active_code(ground), "fragment")
	assert_gt(shipped.length(), 1000, "the ground's fragment() is read")
	assert_eq(Counters.assignments(shipped, "ROUGHNESS").size(), 1, "the wet-line roughness")
	var old := Counters.function_body(
		Counters.active_code(ground, {"GROUND_PREPASS_FULL": true}), "fragment"
	)
	assert_eq(Counters.assignments(old, "NORMAL").size(), 1, "the old path wrote NORMAL")
	assert_eq(Counters.assignments(old, "ROUGHNESS"), PackedStringArray([" roughness"]))
	var canopy := Counters.active_code("res://shaders/wind_foliage.gdshader")
	assert_gt(Counters.sampler_fetches(canopy, ["orm_texture"]), 0, "the canopy fetches its ORM")
	var cover := Counters.active_code("res://shaders/wind_foliage_ground.gdshader")
	assert_gt(Counters.sampler_fetches(cover, ["albedo_texture"]), 0, "the cover reads albedo")
	var plain := Counters.active_code("res://shaders/authored_ground.gdshader")
	assert_false(Counters.render_modes(plain).has("shadows_disabled"), "the map ground has shadows")
	for path in Counters.SKIRT_SHADERS:
		var outer := Counters.render_modes(Counters.active_code(path))
		assert_true(outer.has("shadows_disabled"), "the outer skirt %s receives none" % path)
	for path in Counters.SKIRT_RING_SHADERS:
		var ring := Counters.render_modes(Counters.active_code(path))
		assert_false(ring.has("shadows_disabled"), "the inner ring %s receives them" % path)
