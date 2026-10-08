extends GutTest

## The body-template kit in the consumer (docs/ASSET_PIPELINE.md section 10 "Regions and
## hiding", "Shape keys", "Recipe"): a hidden body region keeps its one-ring buffer runs at
## every boundary where a neighbour still shows and loses the rest, the five body attributes
## drive their signed shape keys from the recipe (0.5, the modelled body, when a recipe omits
## them), and the builder's Shape pane shows a slider per attribute that Surprise me draws.

const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
const ATTRIBUTES: Array[String] = ["frame", "shoulders", "hips", "chest", "waist"]
## Slider label and end hints per attribute (AvatarBuilder.SHAPE_ROWS).
const SLIDERS := {
	"frame": ["Frame", "Slender", "Broad"],
	"shoulders": ["Shoulders", "Narrow", "Broad"],
	"hips": ["Hips", "Narrow", "Wide"],
	"chest": ["Chest", "Flat", "Full"],
	"waist": ["Waist", "Straight", "Defined"],
}

var _kit: AvatarKit
var _old_scene: Node = null
var _scene: Node = null


func before_each() -> void:
	_kit = AvatarKit.load_kit()
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "AvatarBodyTemplateTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


func _free_later(node: Node) -> Node:
	add_child_autofree(node)
	return node


func _rings() -> Dictionary:
	return _kit.parts_by_id.body_a.region_rings


## The index buffer of the surface whose region is `region`, or empty when the mesh has none.
func _surface_index(mesh: ArrayMesh, region: String) -> PackedInt32Array:
	for s in mesh.get_surface_count():
		if AvatarKit._surface_region(mesh, s) == region:
			return mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
	return PackedInt32Array()


## The triangles of `runs` ([start, count]) of region `region`'s whole index buffer.
func _slices(region: String, runs: Array) -> PackedInt32Array:
	var whole := _surface_index(_kit.load_part("body_a").mesh, region)
	return AvatarKit.filter_index(whole, runs)


# --- the hide buffer ---------------------------------------------------------------------------


func test_the_body_regions_and_their_runs_cover_every_triangle() -> void:
	var mesh: ArrayMesh = _kit.load_part("body_a").mesh
	var entry: Dictionary = _kit.parts_by_id.body_a
	assert_eq(mesh.get_surface_count(), 15)
	var regions := PackedStringArray()
	for s in mesh.get_surface_count():
		regions.append(AvatarKit._surface_region(mesh, s))
	assert_eq(Array(regions), entry.regions, "a surface per region, in the kit's order")
	for region in regions:
		var runs: Array = _rings()[region].runs
		var next := 0
		for run in runs:
			assert_eq(int(run[0]), next, "%s runs are consecutive from 0" % region)
			next += int(run[1])
		var triangles := _surface_index(mesh, region).size() / 3
		assert_eq(next, triangles, "%s runs cover its %d triangles" % [region, triangles])


func test_a_hidden_upper_arm_keeps_its_armhole_and_elbow_runs() -> void:
	var mesh := _kit.mesh_without("body_a", ["upper_arm_l"])
	var ring: Dictionary = _rings().upper_arm_l
	var runs: Array = ring.runs
	assert_eq(mesh.get_surface_count(), 15, "the surface stays, reduced to its buffer")
	# keep: run 0 while torso shows, the last run while forearm_l shows; both do.
	assert_eq(AvatarKit.kept_runs(ring, PackedStringArray(["upper_arm_l"])), [runs[0], runs[12]])
	var kept := _surface_index(mesh, "upper_arm_l")
	assert_eq(kept.size() / 3, int(runs[0][1]) + int(runs[12][1]))
	assert_eq(kept, _slices("upper_arm_l", [runs[0], runs[12]]), "exactly those triangles")
	# An unhidden surface keeps every triangle.
	var whole: ArrayMesh = _kit.load_part("body_a").mesh
	for region in ["torso", "forearm_l", "upper_arm_r"]:
		assert_eq(_surface_index(mesh, region), _surface_index(whole, region), region)
	# Blend shapes come along (the built mesh declares all six).
	assert_eq(mesh.get_blend_shape_count(), 6)


func test_a_shared_boundary_goes_when_both_regions_are_hidden() -> void:
	var mesh := _kit.mesh_without("body_a", ["upper_arm_l", "forearm_l"])
	var arm: Array = _rings().upper_arm_l.runs
	var forearm: Array = _rings().forearm_l.runs
	# The upper arm keeps only its armhole run (torso shows); its elbow run goes with the
	# forearm. The forearm keeps only its wrist run (hand_l shows).
	assert_eq(_surface_index(mesh, "upper_arm_l"), _slices("upper_arm_l", [arm[0]]))
	assert_eq(_surface_index(mesh, "forearm_l"), _slices("forearm_l", [forearm[8]]))
	assert_eq(mesh.get_surface_count(), 15)


func test_the_head_counts_as_visible_and_nothing_kept_drops_the_surface() -> void:
	var neck: Dictionary = _rings().neck
	# neck keeps run 0 while the torso shows and run 1 while the head shows: with the torso
	# hidden too, the head side alone stays.
	assert_eq(AvatarKit.kept_runs(neck, PackedStringArray(["neck", "torso"])), [neck.runs[1]])
	assert_eq(AvatarKit.kept_runs({}, PackedStringArray(["neck"])), [], "no entry keeps nothing")
	var entry: Dictionary = _kit.parts_by_id.body_a
	var rings: Dictionary = entry.region_rings
	entry.region_rings = {}
	var mesh := _kit.mesh_without("body_a", ["hand_l"])
	entry.region_rings = rings
	assert_eq(mesh.get_surface_count(), 14, "a kit without rings drops the region whole")
	assert_eq(_surface_index(mesh, "hand_l").size(), 0)


func test_a_worn_top_hides_the_upper_arms_down_to_their_buffer() -> void:
	var top: Array = _kit.parts_by_slot.get("top", [])
	if top.is_empty():
		pass_test("the kit has no top")
		return
	var recipe := RECIPE.duplicate(true)
	recipe.parts.top = String(top[0])
	var hides: Array = _kit.parts_by_id[top[0]].hides
	assert_true(hides.has("upper_arm_l") and hides.has("upper_arm_r"), "%s" % str(hides))
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	var body := (figure.find_child("body_a", true, false) as MeshInstance3D).mesh
	var runs: Array = _rings().upper_arm_r.runs
	var expect := 0
	for run in AvatarKit.kept_runs(_rings().upper_arm_r, PackedStringArray(hides)):
		expect += int(run[1])
	assert_gt(expect, 0)
	assert_eq(_surface_index(body, "upper_arm_r").size() / 3, expect)
	assert_lt(expect, int(runs[runs.size() - 1][0]) + int(runs[runs.size() - 1][1]))


# --- shape keys --------------------------------------------------------------------------------


func test_attribute_controls_drive_signed_shape_weights() -> void:
	var low := _kit.shape_weights({"frame": 0.0, "chest": 0.0, "waist": 0.0, "build": 0.45})
	assert_almost_eq(float(low.frame), -1.0, 1e-6)
	assert_almost_eq(float(low.chest), -0.35, 1e-6)
	assert_almost_eq(float(low.waist), -0.6, 1e-6)
	assert_almost_eq(float(low.shoulders), 0.0, 1e-6, "omitted: the modelled body")
	assert_almost_eq(float(low.hips), 0.0, 1e-6)
	var high := _kit.shape_weights({"frame": 1.0, "hips": 0.75, "shoulders": 1.0})
	assert_almost_eq(float(high.frame), 1.0, 1e-6)
	assert_almost_eq(float(high.hips), 0.5, 1e-6)
	assert_almost_eq(float(high.shoulders), 1.0, 1e-6)
	var old := _kit.shape_weights(RECIPE.proportions)
	for name in ATTRIBUTES:
		assert_almost_eq(float(old[name]), 0.0, 1e-6, "%s at 0 without the attributes" % name)
	assert_almost_eq(float(old.build_plus), 0.0, 1e-6, "build_plus as before")
	assert_almost_eq(float(_kit.shape_weights({"build": 0.75}).build_plus), 0.5, 1e-6)


func test_a_recipe_resolves_the_attributes_clamped_and_defaults_them() -> void:
	var old := _kit.resolve(RECIPE)
	for name in ATTRIBUTES:
		assert_eq(float(old.proportions[name]), 0.5, "%s defaults to the modelled body" % name)
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = {"frame": 1.7, "chest": -0.2, "waist": 0.3}
	var resolved := _kit.resolve(recipe)
	assert_eq(float(resolved.proportions.frame), 1.0)
	assert_eq(float(resolved.proportions.chest), 0.0)
	assert_eq(float(resolved.proportions.waist), 0.3)
	assert_eq(float(resolved.proportions.height), 0.5)
	assert_eq(resolved.fallbacks.size(), 0)
	# shoulders also lengthens the clavicles (kit.json proportions).
	var factors := AvatarProportions.bone_factors(
		_kit.manifest.proportions, {"shoulders": 1.0}, ["LeftShoulder", "RightShoulder"]
	)
	assert_almost_eq(float(factors[0].LeftShoulder), 1.12, 1e-6)
	assert_almost_eq(float(factors[0].RightShoulder), 1.12, 1e-6)


func test_the_built_figure_carries_the_signed_blend_shape_values() -> void:
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = {"height": 0.5, "frame": 0.0, "chest": 0.0, "waist": 1.0, "hips": 0.5}
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	var body := figure.find_child("body_a", true, false) as MeshInstance3D
	var want := {"frame": -1.0, "chest": -0.35, "waist": 1.0, "hips": 0.0, "shoulders": 0.0}
	for name in want:
		var index := body.find_blend_shape_by_name(StringName(name))
		assert_gt(index, -1, "the body carries %s" % name)
		assert_almost_eq(
			body.get_blend_shape_value(index), float(want[name]), 1e-6, "%s unclamped" % name
		)
	var plain := _free_later(_kit.build_figure(RECIPE)) as Node3D
	var old_body := plain.find_child("body_a", true, false) as MeshInstance3D
	for name in ATTRIBUTES:
		var index := old_body.find_blend_shape_by_name(StringName(name))
		assert_almost_eq(old_body.get_blend_shape_value(index), 0.0, 1e-6, "%s old recipe" % name)


# --- the builder -------------------------------------------------------------------------------


func test_the_shape_pane_has_an_attribute_slider_each_that_writes_the_recipe() -> void:
	var builder := AvatarBuilder.open_for_new(_scene, RECIPE, "Plum")
	var values := {"frame": 0.2, "shoulders": 0.8, "hips": 0.35, "chest": 0.9, "waist": 0.1}
	for name in ATTRIBUTES:
		var row := builder._shape_rows.get(name) as PropertyRow
		assert_not_null(row, "a %s slider" % name)
		assert_eq(row.label, SLIDERS[name][0])
		assert_eq(row.hint_low, SLIDERS[name][1])
		assert_eq(row.hint_high, SLIDERS[name][2])
		assert_eq(row.min_value, 0.0)
		assert_eq(row.max_value, 1.0)
		assert_eq(row.value, 0.5, "%s starts at the modelled body" % name)
		row.value_changed.emit(float(values[name]))
	await get_tree().process_frame
	await get_tree().process_frame
	for name in ATTRIBUTES:
		assert_eq(float(builder.recipe.proportions[name]), float(values[name]), name)
	builder.cancel()


func test_surprise_me_draws_every_attribute_independently() -> void:
	var builder := AvatarBuilder.open_for_new(_scene, RECIPE, "Plum")
	builder.surprise()
	for name in ATTRIBUTES:
		assert_true(builder.recipe.proportions.has(name), "surprise sets %s" % name)
		var value := float(builder.recipe.proportions[name])
		assert_between(value, 0.0, 1.0)
		assert_almost_eq(value, AvatarSurprise.quantize(value), 1e-6, "on the step")
	builder.cancel()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var differ := 0
	var ends := 0
	for i in 60:
		var shape := AvatarSurprise.shape(_kit, rng)
		differ += 1 if shape.frame != shape.hips or shape.chest != shape.waist else 0
		for name in ATTRIBUTES:
			ends += 1 if shape[name] <= 0.0 or shape[name] >= 1.0 else 0
	assert_gt(differ, 40, "the attributes are drawn independently")
	assert_gt(ends, 0, "an attribute's ends come up like any other value")
