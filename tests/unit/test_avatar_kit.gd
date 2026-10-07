extends GutTest

## AvatarKit, the avatar kit consumer (docs/ASSET_PIPELINE.md section 10), against the
## installed kit (res://assets/avatar_kit) and fixtures written by figurine's reference code
## (figurine/scripts/consumer_fixtures.py: build_palette and bone_maps for two of
## render_figures.py's recipes), so palette and proportions are checked for parity, not just
## for plausibility.

const FIXTURES := "res://tests/fixtures/avatar_kit"
const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}

var _kit: AvatarKit


func before_each() -> void:
	_kit = AvatarKit.load_kit()


func _fixture(n: int) -> Dictionary:
	var text := FileAccess.get_file_as_string("%s/proportions_%d.json" % [FIXTURES, n])
	return JSON.parse_string(text)


func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _free_later(node: Node) -> Node:
	add_child_autofree(node)
	return node


func test_kit_loads_with_its_parts_skeleton_and_stances() -> void:
	assert_not_null(_kit)
	assert_eq(_kit.errors.size(), 0, "no load errors: %s" % str(_kit.errors))
	assert_eq(_kit.parts_by_slot.get("body"), ["body_a"])
	# 22 body bones, 12 finger bones, 38 helpers (the crisp-joints card), 33 secondary chain
	# bones (the foundation card).
	assert_eq(_kit.bone_names.size(), 105)
	for bone in ["LeftThumbMetacarpal", "RightMiddleIntermediate", "LeftElbowHelper3"]:
		assert_true(_kit.bone_names.has(bone), "%s in the skeleton" % bone)
	assert_true(bool(_kit.manifest.skeleton.LeftElbowHelper2.get("helper", false)))
	assert_true(_kit.stances.has("stance_ready") and _kit.stances.has("stance_relaxed"))
	for stance in ["stance_heroic", "stance_casting", "stance_cheerful"]:
		assert_true(_kit.stances.has(stance), "%s in the kit (the look pass's stances)" % stance)
	assert_not_null(_kit.face_sheet)
	assert_not_null(_kit.face_mask)
	for id in _kit.parts_by_id:
		assert_eq(String(_kit.load_part(id).error), "", "part %s binds to the kit" % id)


func test_kit_sidecars_keep_the_install_settings() -> void:
	# tools/install_avatar_kit.gd writes these before the first import (section 9's way).
	var glbs := ["skeleton.glb"]
	for id in _kit.parts_by_id:
		glbs.append(String(_kit.parts_by_id[id].glb))
	for glb in glbs:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load("%s/%s.import" % [AvatarKit.DEFAULT_ROOT, glb]), OK, "%s sidecar" % glb)
		assert_eq(cfg.get_value("params", "gltf/embedded_image_handling"), 3, glb)
		assert_eq(cfg.get_value("params", "meshes/generate_lods"), false, glb)
	for png in ["faces/face_sheet.png", "faces/face_mask.png"]:
		var cfg := ConfigFile.new()
		assert_eq(cfg.load("%s/%s.import" % [AvatarKit.DEFAULT_ROOT, png]), OK, "%s sidecar" % png)
		assert_eq(cfg.get_value("params", "compress/mode"), 0, png)
		assert_eq(cfg.get_value("params", "mipmaps/generate"), true, png)


func test_detail_textures_get_mipmaps() -> void:
	var with_detail := 0
	for id in _kit.parts_by_id:
		var detail: Texture2D = _kit.load_part(id).detail
		if not bool((_kit.parts_by_id[id] as Dictionary).get("detail", true)):
			# A part may carry no detail overlay (the witch hat is palette faces alone).
			assert_null(detail, "%s declares no detail texture" % id)
			continue
		with_detail += 1
		assert_not_null(detail, "%s has a detail texture" % id)
		assert_true(detail.get_image().has_mipmaps(), "%s detail is mipmapped" % id)
	assert_gt(with_detail, 0, "the body, head and hair carry detail")


func test_palette_matches_figurine_byte_for_byte() -> void:
	for n in [1, 2]:
		var expected := Image.load_from_file(
			ProjectSettings.globalize_path("%s/palette_%d.png" % [FIXTURES, n])
		)
		expected.convert(Image.FORMAT_RGB8)
		var built := AvatarPalette.build_image(_kit.manifest.colour_sets, _fixture(n).colours)
		assert_eq(built.get_width(), 8)
		assert_eq(built.get_height(), 64)
		assert_eq(built.get_data(), expected.get_data(), "palette %d matches build_palette" % n)


func test_palette_column_runs_shadow_at_the_bottom_to_highlight_at_the_top() -> void:
	var sets: Dictionary = _kit.manifest.colour_sets
	var img := AvatarPalette.build_image(sets, {})
	var skin: Array = sets.skin[0]
	var top := img.get_pixel(0, 0)
	var bottom := img.get_pixel(0, 63)
	var high := Color(String(skin[2]))
	var shadow := Color(String(skin[1]))
	assert_almost_eq(top.r, high.r, 0.01, "row 0 is the highlight")
	assert_almost_eq(bottom.g, shadow.g, 0.01, "row 63 is the shadow")


func test_proportions_match_figurine_bone_maps() -> void:
	for n in [1, 2]:
		var fixture := _fixture(n)
		var maps := AvatarProportions.bone_maps(
			_kit.manifest.skeleton, _kit.manifest.proportions, fixture.proportions
		)
		for bone in fixture.bones:
			var want: Dictionary = fixture.bones[bone]
			var got: Dictionary = maps[bone]
			assert_lt(
				(got.new_head as Vector3).distance_to(_vec(want.new_head)),
				2e-5,
				"recipe %d %s new head" % [n, bone]
			)
			var r: Basis = got.r
			for row in 3:
				for col in 3:
					assert_almost_eq(
						r[col][row],
						float(want.r[row][col]),
						1e-5,
						"%s R[%d][%d]" % [bone, row, col]
					)


func test_figure_skeleton_rests_on_the_reshaped_heads() -> void:
	var fixture := _fixture(2)
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = fixture.proportions
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	var sk := figure.get_node("Skeleton3D") as Skeleton3D
	for bone in fixture.bones:
		var b := sk.find_bone(bone)
		assert_lt(
			sk.get_bone_global_rest(b).origin.distance_to(_vec(fixture.bones[bone].new_head)),
			2e-5,
			"%s rest origin" % bone
		)


func test_reshaped_binds_carry_the_bone_map() -> void:
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = {"height": 1.0, "build": 0.0, "head": 1.0}
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	var sk := figure.get_node("Skeleton3D") as Skeleton3D
	var head := figure.find_child("head_round", true, false) as MeshInstance3D
	var original: Skin = _kit.load_part("head_round").skin
	var maps := AvatarProportions.bone_maps(
		_kit.manifest.skeleton, _kit.manifest.proportions, recipe.proportions
	)
	assert_ne(head.skin, original, "the skin is a per-figure copy")
	var point := Vector3(0.03, 1.4, 0.05)
	for i in head.skin.get_bind_count():
		var name := String(head.skin.get_bind_name(i))
		var rest := sk.get_bone_global_rest(sk.find_bone(name))
		# A mesh-space point the original bind puts at `point` lands, through the new rest and
		# bind, where the bone's map sends it.
		var to_mesh := (_old_global_rest(name) * original.get_bind_pose(i)).affine_inverse()
		var skinned := rest * head.skin.get_bind_pose(i) * to_mesh * point
		var mapped := AvatarProportions.bone_map_transform(maps[name]) * point
		assert_lt(skinned.distance_to(mapped), 1e-4, "bind %s maps a rest point" % name)


func _old_global_rest(bone: String) -> Transform3D:
	var b := _kit.bone_names.find(bone)
	var xf := _kit.bone_rests[b]
	var parent := _kit.bone_parents[b]
	while parent >= 0:
		xf = _kit.bone_rests[parent] * xf
		parent = _kit.bone_parents[parent]
	return xf


func test_stance_is_set_as_the_pose() -> void:
	var figure := _free_later(_kit.build_figure(RECIPE)) as Node3D
	var sk := figure.get_node("Skeleton3D") as Skeleton3D
	var stance: Dictionary = _kit.stances.stance_ready
	assert_gt(stance.size(), 0)
	for bone in stance:
		var got := sk.get_bone_pose_rotation(sk.find_bone(bone))
		assert_lt(got.angle_to(stance[bone]), 1e-4, "%s posed" % bone)
	# The pose reaches the global transforms the skin uses (a skeleton posed before it enters
	# the tree kept its rest pose until AvatarKit re-posed it on entering).
	var hand := sk.find_bone("LeftHand")
	assert_gt(
		sk.get_bone_global_pose(hand).origin.distance_to(sk.get_bone_global_rest(hand).origin),
		0.1,
		"the hand hangs down in the stance, not out in the A-pose"
	)
	# The clip's Hips drop (the solve at the kit's proportions) lowers the root below its
	# rest, so the bent knees keep the planted sole on the ground.
	var hips := sk.find_bone("Hips")
	var drop: float = (
		(_kit.stance_offsets.get("stance_ready", {}).get("Hips", Vector3.ZERO) as Vector3).y
	)
	assert_lt(drop, -0.005, "stance_ready drops the hips (%f)" % drop)
	# At this figure's proportions the ground rule re-solves the height; the lowest contact
	# lands on the ground.
	var dropped := sk.get_bone_pose_position(hips).y - sk.get_bone_rest(hips).origin.y
	assert_lt(dropped, -0.005, "the figure's own drop is applied (%f)" % dropped)
	assert_almost_eq(dropped, drop, 0.01, "close to the kit's drop at near-default proportions")


func test_stance_matches_figurine_with_helpers_and_fingers() -> void:
	# figurine's stance_ready over fixture 2's proportions, stood by the ground rule
	# (consumer_fixtures.py stance_2.json): every posed bone head, helpers and fingers too.
	var fixture: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/stance_2.json" % FIXTURES)
	)
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = fixture.proportions
	recipe.stance = fixture.stance
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	var sk := figure.get_node("Skeleton3D") as Skeleton3D
	assert_eq(fixture.heads.size(), sk.get_bone_count())
	for bone in fixture.heads:
		var got := sk.get_bone_global_pose(sk.find_bone(bone)).origin
		assert_lt(got.distance_to(_vec(fixture.heads[bone])), 2e-4, "%s posed head" % bone)
	# A helper really turns: the elbow helper takes half the elbow's fold.
	var elbow := sk.get_bone_pose_rotation(sk.find_bone("RightLowerArm"))
	var helper := sk.get_bone_pose_rotation(sk.find_bone("RightElbowHelper2"))
	var rest := sk.get_bone_rest(sk.find_bone("RightLowerArm")).basis.get_rotation_quaternion()
	assert_gt(rest.angle_to(elbow), 0.5, "the right elbow folds in stance_ready")
	assert_almost_eq(rest.angle_to(helper), rest.angle_to(elbow) * 0.5, 0.05, "half the fold")


func test_chain_bones_follow_figurine_in_the_blended_stance() -> void:
	# stance_2.json: stance_ready blended halfway toward stance_ready_plus (build 0.75); a
	# chain bone's own rotation shows only in its posed tail.
	var fixture: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("%s/stance_2.json" % FIXTURES)
	)
	assert_almost_eq(float(fixture.plus_weight), 0.5, 1e-6)
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = fixture.proportions
	recipe.stance = fixture.stance
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	var sk := figure.get_node("Skeleton3D") as Skeleton3D
	var maps: Dictionary = _kit.cache.shape(_kit.resolve(recipe).proportions).maps
	var checked := 0
	for bone in fixture.chain_tails:
		var b := sk.find_bone(bone)
		var spec: Dictionary = _kit.manifest.skeleton[bone]
		var entry: Dictionary = maps[bone]
		var tail_rest: Vector3 = AvatarProportions.bone_map_transform(entry) * _vec(spec.tail)
		var pose := sk.get_bone_global_pose(b)
		var got := pose * (sk.get_bone_global_rest(b).affine_inverse() * tail_rest)
		assert_lt(got.distance_to(_vec(fixture.chain_tails[bone])), 3e-4, "%s posed tail" % bone)
		checked += 1
	assert_eq(checked, 33)
	assert_eq(String(_kit.manifest.skeleton.SkirtFront1.attach), "Hips")


func test_chain_bones_take_their_attach_bones_map() -> void:
	var maps := AvatarProportions.bone_maps(
		_kit.manifest.skeleton, _kit.manifest.proportions, {"height": 1.0, "build": 1.0}
	)
	for bone in ["Ponytail2", "SkirtBack3", "LeftCloak1"]:
		var attach := String(_kit.manifest.skeleton[bone].attach)
		var p := Vector3(0.1, 0.9, 0.05)
		var a := AvatarProportions.bone_map_transform(maps[bone]) * p
		var b := AvatarProportions.bone_map_transform(maps[attach]) * p
		assert_lt(a.distance_to(b), 1e-5, "%s maps as %s" % [bone, attach])


func test_build_drives_the_plus_blend_shape() -> void:
	for n in [1, 2]:
		var fixture := _fixture(n)
		var weights := _kit.shape_weights(fixture.proportions)
		for shape in fixture.shape_weights:
			assert_almost_eq(
				float(weights[shape]), float(fixture.shape_weights[shape]), 1e-6, "%s" % shape
			)
	assert_almost_eq(float(_kit.shape_weights({"build": 1.0}).build_plus), 1.0, 1e-6)
	assert_almost_eq(float(_kit.shape_weights({"build": 0.3}).build_plus), 0.0, 1e-6)
	var recipe := RECIPE.duplicate(true)
	recipe.proportions = {"height": 0.5, "build": 1.0, "head": 0.5}
	# Hidden regions keep the blend shape too (mesh_without rebuilds the mesh).
	(_kit.parts_by_id.hair_bun as Dictionary).hides = ["thighs"]
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	(_kit.parts_by_id.hair_bun as Dictionary).hides = []
	for id in ["body_a", "head_round", "hair_bun"]:
		var mi := figure.find_child(id, true, false) as MeshInstance3D
		var index := mi.find_blend_shape_by_name(&"build_plus")
		assert_gt(index, -1, "%s carries build_plus" % id)
		assert_almost_eq(mi.get_blend_shape_value(index), 1.0, 1e-6, "%s at full weight" % id)


func test_a_plus_build_stands_in_the_plus_variant() -> void:
	assert_true(_kit.stances.has("stance_relaxed_plus"))
	var weights := {"build_plus": 1.0}
	var full: Array = _kit.stance_pose("stance_relaxed", weights)
	var plus: Dictionary = _kit.stances.stance_relaxed_plus
	var base: Dictionary = _kit.stances.stance_relaxed
	var q: Quaternion = full[0].LeftUpperArm
	assert_lt(q.angle_to(plus.LeftUpperArm), 1e-4, "full weight plays the plus clip")
	var none: Array = _kit.stance_pose("stance_relaxed", {"build_plus": 0.0})
	assert_lt((none[0].LeftUpperArm as Quaternion).angle_to(base.LeftUpperArm), 1e-6)
	assert_gt(
		(base.LeftUpperArm as Quaternion).angle_to(plus.LeftUpperArm), 0.01, "the hand moves out"
	)


func test_surprise_draws_builds_over_the_whole_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var low := 0
	var high := 0
	for i in 400:
		var build := float(AvatarSurprise.shape(_kit, rng).build)
		low += 1 if build <= 0.1 else 0
		high += 1 if build >= 0.9 else 0
	# Three of the 21 steps at each end (0, 0.05, 0.1 and 0.9, 0.95, 1): about 57 draws each.
	assert_between(low, 30, 90)
	assert_between(high, 30, 90)


func test_figure_uses_the_figure_shader_with_palette_and_face() -> void:
	var figure := _free_later(_kit.build_figure(RECIPE)) as Node3D
	var parts := AvatarKit.figure_parts(figure)
	assert_eq(parts.size(), 3)
	for mi in parts:
		var mat := mi.material_override as ShaderMaterial
		assert_not_null(mat, "%s has the figure material" % mi.name)
		assert_eq(mat.shader, AvatarKit.FIGURE_SHADER)
		assert_not_null(mat.get_shader_parameter("palette"))
		assert_true(mat.get_shader_parameter("has_detail"))
	var head := (figure.find_child("head_round", true, false) as MeshInstance3D).material_override
	assert_true(head.get_shader_parameter("has_face"))
	var cells: PackedVector2Array = head.get_shader_parameter("face_cells")
	# Composition order marks, mouths, eyes, brows; eyes cell 1 of 7 columns, row 0.
	assert_almost_eq(cells[2].x, 1.0 / 7.0, 1e-6)
	assert_almost_eq(cells[2].y, 0.0, 1e-6)
	assert_almost_eq(cells[3].y, 0.25, 1e-6, "brows are the second row")
	var hair := (figure.find_child("hair_bun", true, false) as MeshInstance3D).material_override
	assert_ne(hair.get_shader_parameter("has_face"), true, "only the head composes a face")


func test_resolution_falls_back_and_notes_it() -> void:
	var recipe := {
		"format": 1,
		"parts": {"hair": "hair_from_the_future", "cloak": "cloak_x"},
		"colours": {"skin": 99, "hair": 2},
		"face": {"eyes": 40, "brows": 2},
		"proportions": {"height": 4.0},
		"stance": "stance_dab",
	}
	var r := _kit.resolve(recipe)
	assert_eq(r.parts, {"body": "body_a", "hair": "hair_bun", "head": "head_round"})
	assert_eq(r.colours.skin, 0)
	assert_eq(r.colours.hair, 2)
	assert_eq(r.face.eyes, 0)
	assert_eq(r.face.brows, 2)
	assert_eq(r.proportions.height, 1.0)
	assert_eq(r.proportions.build, 0.5)
	assert_eq(r.stance, "stance_ready")
	var notes := "\n".join(r.fallbacks)
	assert_string_contains(
		notes, "part 'hair_from_the_future' for hair not in kit; using 'hair_bun'"
	)
	assert_string_contains(notes, "part None for body not in kit; using 'body_a'")
	# The cloak slot is optional (card B1): a cloak the kit lacks means none.
	assert_string_contains(notes, "part 'cloak_x' for cloak not in kit; left empty")
	assert_string_contains(notes, "colour skin=99 outside its set of 6; using 0")
	assert_string_contains(notes, "face eyes=40 outside the sheet's 7; using 0")
	assert_string_contains(notes, "stance 'stance_dab' not in kit; using 'stance_ready'")


func test_missing_part_and_cell_still_build_a_figure() -> void:
	var recipe := RECIPE.duplicate(true)
	recipe.parts.hair = "hair_missing"
	recipe.face.mouths = 77
	var figure := _free_later(_kit.build_figure(recipe)) as Node3D
	assert_eq(AvatarKit.figure_parts(figure).size(), 3)
	assert_not_null(figure.find_child("hair_bun", true, false))
	var head := (figure.find_child("head_round", true, false) as MeshInstance3D).material_override
	var cells: PackedVector2Array = head.get_shader_parameter("face_cells")
	assert_almost_eq(cells[1].x, 0.0, 1e-6, "mouth fell back to cell 0")


func test_hides_turn_off_the_covered_body_regions() -> void:
	var entry: Dictionary = _kit.parts_by_id.hair_bun
	entry.hides = ["torso", "upper_arms"]
	var figure := _free_later(_kit.build_figure(RECIPE)) as Node3D
	var body := (figure.find_child("body_a", true, false) as MeshInstance3D).mesh
	var regions := PackedStringArray()
	for s in body.get_surface_count():
		regions.append(body.surface_get_material(s).resource_name)
	assert_eq(body.get_surface_count(), 6)
	assert_false(regions.has("torso"))
	assert_false(regions.has("upper_arms"))
	assert_true(regions.has("hands"))
	entry.hides = []
	var plain := _free_later(_kit.build_figure(RECIPE)) as Node3D
	var whole := (plain.find_child("body_a", true, false) as MeshInstance3D).mesh
	assert_eq(whole.get_surface_count(), 8)


func test_a_part_with_a_different_armature_is_rejected_by_name() -> void:
	var scene := (
		(load("res://assets/avatar_kit/parts/hair/hair_bun.glb") as PackedScene).instantiate()
	)
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	assert_eq(_kit.armature_mismatch(sk), "", "the real part matches")
	sk.set_bone_name(sk.find_bone("LeftHand"), "LeftPaw")
	var result := {}
	var error: String = _kit._read_part("hair_odd", scene, result)
	assert_string_contains(error, "hair_odd rejected")
	assert_string_contains(error, "LeftPaw")
	scene.free()


func test_a_moved_rest_is_rejected_too() -> void:
	var scene := (
		(load("res://assets/avatar_kit/parts/head/head_round.glb") as PackedScene).instantiate()
	)
	var sk := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var b := sk.find_bone("Neck")
	var rest := sk.get_bone_rest(b)
	rest.origin.y += 0.01
	sk.set_bone_rest(b, rest)
	assert_string_contains(_kit.armature_mismatch(sk), "Neck")
	scene.free()


func test_shade_and_hidden_fade_are_instance_values_on_every_part() -> void:
	var figure := _free_later(_kit.build_figure(RECIPE)) as Node3D
	AvatarKit.set_shade(figure, 1.0)
	AvatarKit.set_hidden_fade(figure, 0.5)
	for mi in AvatarKit.figure_parts(figure):
		assert_eq(mi.get_instance_shader_parameter("shade"), 1.0)
		assert_eq(mi.get_instance_shader_parameter("hidden_fade"), 0.5)


func test_shade_ray_finds_a_canopy_overhead() -> void:
	var root := _free_later(Node3D.new()) as Node3D
	var tree := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 6.0, 4.0)
	tree.mesh = box
	root.add_child(tree)
	tree.global_position = Vector3(0.0, 3.0, 0.0)
	var sun_up := Vector3(0.2, 1.0, 0.1).normalized()
	assert_eq(AvatarShade.shade_at(root, Vector3.ZERO, sun_up), 1.0, "under the crown")
	assert_eq(AvatarShade.shade_at(root, Vector3(10.0, 0.0, 0.0), sun_up), 0.0, "in the open")
	var low := Vector3(-1.0, -0.1, 0.0).normalized()
	assert_eq(
		AvatarShade.shade_at(root, Vector3(10.0, 0.0, 0.0), low), 1.0, "sun below the horizon"
	)
