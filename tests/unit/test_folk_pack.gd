extends GutTest

## The shipped Folk token pack (builtin_packs/folk/, built by tools/roster/build_folk.gd from
## Quaternius's CC0 packs): its manifest and credit, that every figure's model and icon exist
## and load, that a figure reads as a clothed person at human scale, that the Licences page
## carries the credit, and that the GLB writer the build uses is deterministic. The source
## downloads are not in the repo, so the build itself is not rebuilt here.

const FolkGlb := preload("res://tools/roster/folk_glb.gd")
const FolkBake := preload("res://tools/roster/folk_bake.gd")
const PACK_PATH := "res://builtin_packs/folk/"
const FIGURES := 16
const MAX_MODEL_BYTES := 800_000


func _pack() -> AssetPack:
	return BuiltinPacks.load_pack(PACK_PATH, "folk")


func test_manifest_declares_the_credit_and_the_cc0_licence() -> void:
	var pack := _pack()
	assert_not_null(pack, "the pack loads")
	assert_eq(BuiltinPacks.problems(pack, "folk"), PackedStringArray())
	assert_eq(pack.display_name, "Folk")
	assert_eq(pack.author, "Quaternius")
	assert_eq(pack.license, "CC0-1.0")
	assert_eq(pack.credit_line(), "People by Quaternius (CC0)")
	assert_true(pack.source_url.contains("quaternius.com/packs/universalbasecharacters"))
	assert_true(pack.source_url.contains("quaternius.com/packs/modularcharacteroutfitsfantasy"))
	assert_eq(pack.obtained, "2026-11-01")
	assert_eq(pack.assets.size(), FIGURES)


func test_every_model_and_icon_exists_and_carries_a_keep_sidecar() -> void:
	for asset_id in _pack().assets:
		for kind in ["models/%s.glb", "icons/%s.png"]:
			var path: String = PACK_PATH + kind % asset_id
			assert_true(FileAccess.file_exists(path), "%s exists" % path)
			var sidecar := FileAccess.get_file_as_string(path + ".import")
			assert_true(sidecar.contains('importer="keep"'), "%s has a keep sidecar" % path)


func test_every_model_loads_as_one_clothed_person_at_human_scale() -> void:
	for asset_id in _pack().assets:
		var path: String = PACK_PATH + "models/%s.glb" % asset_id
		var bytes := FileAccess.get_file_as_bytes(path)
		assert_lt(bytes.size(), MAX_MODEL_BYTES, "%s is small enough to ship" % asset_id)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		assert_eq(doc.append_from_buffer(bytes, "", state), OK, "%s parses" % asset_id)
		var root := doc.generate_scene(state)
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		assert_eq(meshes.size(), 1, "%s is one rigid mesh" % asset_id)
		assert_eq(root.find_children("*", "Skeleton3D", true, false).size(), 0, "%s is baked" % asset_id)
		var mesh := (meshes[0] as MeshInstance3D).mesh
		# Skin, hair and eyes plus an outfit; a hooded figure has no hair surface.
		assert_gte(mesh.get_surface_count(), 3, "%s has an outfit, skin and eyes" % asset_id)
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			assert_not_null(material.albedo_texture, "%s surface %d is textured" % [asset_id, surface])
		var box := mesh.get_aabb()
		assert_between(box.size.y, 1.6, 1.85, "%s stands about 1.7 m" % asset_id)
		assert_between(box.size.x, 0.6, 1.1, "%s is an A-pose, not a T-pose" % asset_id)
		assert_almost_eq(box.position.y, 0.0, 0.01, "%s stands on y = 0" % asset_id)
		root.free()


func test_every_icon_is_128_px_with_a_transparent_corner() -> void:
	for asset_id in _pack().assets:
		var image := Image.new()
		var bytes := FileAccess.get_file_as_bytes(PACK_PATH + "icons/%s.png" % asset_id)
		assert_eq(image.load_png_from_buffer(bytes), OK, "%s icon loads" % asset_id)
		assert_eq(image.get_size(), Vector2i(128, 128), asset_id)
		assert_eq(image.get_pixel(1, 1).a, 0.0, "%s icon has a transparent background" % asset_id)
		assert_gt(image.get_pixel(64, 64).a, 0.0, "%s icon has the figure in the middle" % asset_id)


func test_the_licences_page_credits_the_pack() -> void:
	var found := false
	for entry in LicenceCatalog.pack_entries():
		if entry["id"] == "tokens_folk":
			found = true
			assert_eq(entry["credit"], "People by Quaternius (CC0)")
			assert_eq(entry["licence"], "CC0-1.0")
	assert_true(found, "a Token packs entry for Folk")


func test_the_provenance_record_exists_beside_the_licences() -> void:
	var record := FileAccess.get_file_as_string("res://docs/licences/builtin_packs/folk.md")
	assert_string_contains(record, "CC0 1.0 Universal")
	assert_string_contains(record, "Obtained 2026-11-01")


func test_the_glb_writer_is_deterministic_and_reloads() -> void:
	var group := FolkBake.Group.new()
	group.append(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]),
		PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK]),
		PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]),
		PackedInt32Array([0, 1, 2, 2, 1, 3]),
		PackedByteArray([1, 0])
	)
	assert_eq(group.triangle_count(), 1, "the keep mask dropped the second triangle")
	assert_eq(group.verts.size(), 3, "and its unused vertex")
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.6, 0.4, 0.3))
	group.material = StandardMaterial3D.new()
	group.material.resource_name = "outfit"
	group.material.albedo_texture = ImageTexture.create_from_image(image)
	group.material.albedo_color = Color(0.5, 0.5, 0.5)
	var first := FolkGlb.encode("probe", [group], 0.8, "test")
	var second := FolkGlb.encode("probe", [group], 0.8, "test")
	assert_eq(first, second, "the same input writes the same bytes")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert_eq(doc.append_from_buffer(first, "", state), OK)
	var root := doc.generate_scene(state)
	var mesh := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size(), 3)
	var material := mesh.surface_get_material(0) as BaseMaterial3D
	assert_almost_eq(material.albedo_color.r, 0.5, 0.01, "the tint survives")
	assert_not_null(material.albedo_texture, "the WebP texture reloads")
	root.free()
