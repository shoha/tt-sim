extends GutTest

## The shipped Beasts and Farm Animals token pack (builtin_packs/beasts/, built by
## tools/roster/build_beasts.gd from Quaternius's CC0 Farm Animals): its manifest and credit, that
## every animal's model and icon exist and load, that each stands at its real-world height on y = 0,
## that the clips the token animation tree plays are present and the idle loops, and that the
## Licences page carries the credit. The source download is not in the repo, so the build is not
## rebuilt here.

const SkinnedBounds := preload("res://tools/roster/skinned_bounds.gd")
const BeastRecipes := preload("res://tools/roster/beast_recipes.gd")
const PACK_PATH := "res://builtin_packs/beasts/"
const MAX_MODEL_BYTES := 600_000


func _pack() -> AssetPack:
	return BuiltinPacks.load_pack(PACK_PATH, "beasts")


func _load(asset_id: String) -> Node3D:
	var bytes := FileAccess.get_file_as_bytes(PACK_PATH + "models/%s.glb" % asset_id)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(doc.append_from_buffer(bytes, "", state), OK, "%s parses" % asset_id)
	return doc.generate_scene(state) as Node3D


func test_manifest_declares_the_credit_and_the_cc0_licence() -> void:
	var pack := _pack()
	assert_not_null(pack, "the pack loads")
	assert_eq(BuiltinPacks.problems(pack, "beasts"), PackedStringArray())
	assert_eq(pack.display_name, "Beasts and Farm Animals")
	assert_eq(pack.author, "Quaternius")
	assert_eq(pack.license, "CC0-1.0")
	assert_eq(pack.credit_line(), "Animals by Quaternius (CC0)")
	assert_true(pack.source_url.contains("quaternius.com/packs/"))
	assert_eq(pack.obtained, "2026-11-01")
	assert_eq(pack.assets.size(), BeastRecipes.ANIMALS.size(), "one asset per recipe")


func test_every_model_and_icon_exists_and_carries_a_keep_sidecar() -> void:
	for asset_id in _pack().assets:
		for kind in ["models/%s.glb", "icons/%s.png"]:
			var path: String = PACK_PATH + kind % asset_id
			assert_true(FileAccess.file_exists(path), "%s exists" % path)
			var sidecar := FileAccess.get_file_as_string(path + ".import")
			assert_true(sidecar.contains('importer="keep"'), "%s has a keep sidecar" % path)


func test_every_animal_is_one_skinned_mesh_standing_at_its_real_height() -> void:
	for asset_id in _pack().assets:
		var path: String = PACK_PATH + "models/%s.glb" % asset_id
		assert_lt(FileAccess.get_file_as_bytes(path).size(), MAX_MODEL_BYTES, "%s is small" % asset_id)
		var root := _load(asset_id)
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		assert_eq(meshes.size(), 1, "%s is one mesh" % asset_id)
		assert_eq(root.find_children("*", "Skeleton3D", true, false).size(), 1, "%s is rigged" % asset_id)
		for surface in (meshes[0] as MeshInstance3D).mesh.get_surface_count():
			var material := (meshes[0] as MeshInstance3D).mesh.surface_get_material(surface)
			assert_not_null(material, "%s surface %d has its material" % [asset_id, surface])
		var box := SkinnedBounds.of(root)
		var box_in_world := root.transform * box
		var want: float = BeastRecipes.ANIMALS[asset_id]["height_m"]
		assert_almost_eq(box_in_world.size.y, want, want * 0.03, "%s stands %.1f m" % [asset_id, want])
		assert_almost_eq(box_in_world.position.y, 0.0, 0.02, "%s stands on y = 0" % asset_id)
		assert_gt(box_in_world.size.z, box_in_world.size.x, "%s is longer than it is wide" % asset_id)
		root.free()


func test_animals_are_different_token_sizes() -> void:
	var heights := {}
	for asset_id in _pack().assets:
		var root := _load(asset_id)
		heights[asset_id] = (root.transform * SkinnedBounds.of(root)).size.y
		root.free()
	assert_gt(heights["horse"], heights["cow"], "a horse is taller than a cow")
	assert_gt(heights["cow"], heights["sheep"], "a cow is taller than a sheep")
	assert_gt(heights["sheep"], heights["pug"], "a sheep is taller than a pug")


func test_the_clips_the_token_animation_tree_plays_are_present() -> void:
	for asset_id in _pack().assets:
		var root := _load(asset_id)
		var players := root.find_children("*", "AnimationPlayer", true, false)
		assert_eq(players.size(), 1, "%s has an animation player" % asset_id)
		var player := players[0] as AnimationPlayer
		assert_true(player.has_animation("battlewait01"), "%s has an idle" % asset_id)
		assert_true(player.has_animation("damage01"), "%s has a hit clip" % asset_id)
		if asset_id in ["cow", "horse", "zebra"]:
			assert_true(player.has_animation("down01_start"), "%s has a death clip" % asset_id)
			assert_true(player.has_animation("down01"), "%s holds the down pose" % asset_id)
		root.free()


func test_the_animation_tree_loops_the_idle_of_a_glb_model() -> void:
	var root := _load("cow")
	add_child_autofree(root)
	var player := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var idle := player.get_animation("battlewait01")
	assert_eq(idle.loop_mode, Animation.LOOP_NONE, "glTF has no loop flag")
	var tree := BoardTokenAnimationTreeFactory.create()
	tree.anim_player = player
	root.add_child(tree)
	assert_engine_error("No BoardToken ancestor", "the bare tree has no token above it")
	assert_eq(player.get_animation("battlewait01").loop_mode, Animation.LOOP_LINEAR)


func test_every_icon_is_128_px_with_a_transparent_corner() -> void:
	for asset_id in _pack().assets:
		var image := Image.new()
		var bytes := FileAccess.get_file_as_bytes(PACK_PATH + "icons/%s.png" % asset_id)
		assert_eq(image.load_png_from_buffer(bytes), OK, "%s icon loads" % asset_id)
		assert_eq(image.get_size(), Vector2i(128, 128), asset_id)
		assert_eq(image.get_pixel(1, 1).a, 0.0, "%s icon has a transparent background" % asset_id)
		assert_gt(image.get_pixel(64, 64).a, 0.0, "%s icon has the animal in the middle" % asset_id)


func test_the_licences_page_credits_the_pack() -> void:
	var found := false
	for entry in LicenceCatalog.pack_entries():
		if entry["id"] == "tokens_beasts":
			found = true
			assert_eq(entry["credit"], "Animals by Quaternius (CC0)")
			assert_eq(entry["licence"], "CC0-1.0")
	assert_true(found, "a Token packs entry for the beasts")


func test_the_provenance_record_exists_beside_the_licences() -> void:
	var record := FileAccess.get_file_as_string("res://docs/licences/builtin_packs/beasts.md")
	assert_string_contains(record, "CC0")
	assert_string_contains(record, "Obtained 2026-11-01")
	assert_string_contains(record, "SHA-256")


func test_clip_names_map_to_the_trees_names_and_drop_the_rest() -> void:
	assert_eq(BeastRecipes.clip_name("Armature|Idle"), "battlewait01")
	assert_eq(BeastRecipes.clip_name("Armature|Death"), "down01_start")
	assert_eq(BeastRecipes.clip_name("Armature|Walk"), "", "walk is dropped")
