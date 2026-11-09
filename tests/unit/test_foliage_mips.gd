extends GutTest

## FoliageMips: the mip chain a library asset's textures get after the runtime glTF parse (which
## builds none), and the alpha coverage a cutout keeps down that chain.


## A 64 x 64 card of 60 scattered 3 x 3 specks (a seeded layout, about 12 percent of the texels
## opaque): a plain box filter averages a speck into a texel of alpha 14 percent at level 3, below
## the cutoff, so the cutout empties as the chain goes down.
func _blades() -> Image:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.4, 0.1, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for speck in 60:
		var at := Vector2i(rng.randi_range(0, 61), rng.randi_range(0, 61))
		for dy in 3:
			for dx in 3:
				image.set_pixel(at.x + dx, at.y + dy, Color(0.2, 0.7, 0.2, 1.0))
	return image


func test_a_chain_is_built_for_a_plain_texture() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 0.5, 1.0))
	var chained := FoliageMips.with_mips(image, FoliageMips.Role.DATA)
	assert_true(chained.has_mipmaps())
	assert_eq(chained.get_mipmap_count(), 5, "32 -> 1 is five more levels")
	assert_false(image.has_mipmaps(), "the source is not modified")


func test_the_base_level_is_never_touched() -> void:
	var image := _blades()
	var chained := FoliageMips.with_mips(image, FoliageMips.Role.ALBEDO)
	var size := image.get_data().size()
	assert_eq(chained.get_data().slice(0, size), image.get_data())


func test_a_plain_chain_loses_coverage_and_the_cutout_chain_keeps_it() -> void:
	var image := _blades()
	var plain := image.duplicate() as Image
	plain.generate_mipmaps()
	var base := FoliageMips.coverage(image)
	assert_between(base, 0.08, 0.2)
	assert_lt(FoliageMips.coverage(plain, 3), base * 0.5, "the box filter thins the specks out")

	var kept := FoliageMips.with_mips(image, FoliageMips.Role.ALBEDO)
	for level in [1, 2, 3]:
		assert_almost_eq(FoliageMips.coverage(kept, level), base, 0.06, "level %d" % level)


func test_an_opaque_albedo_gets_the_plain_chain() -> void:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.6, 0.2, 1.0))
	var chained := FoliageMips.with_mips(image, FoliageMips.Role.ALBEDO)
	assert_true(chained.has_mipmaps())
	assert_eq(FoliageMips.coverage(chained, 2), 1.0)


func test_an_image_that_already_has_mips_is_left_as_it_is() -> void:
	var image := _blades()
	image.generate_mipmaps()
	var again := FoliageMips.with_mips(image, FoliageMips.Role.ALBEDO)
	assert_eq(again.get_data(), image.get_data())


func test_apply_replaces_each_texture_once_and_keeps_shared_ones_shared() -> void:
	var mesh := QuadMesh.new()
	var material := StandardMaterial3D.new()
	var albedo := ImageTexture.create_from_image(_blades())
	var packed := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	packed.fill(Color(1.0, 0.5, 0.0, 1.0))
	var orm := ImageTexture.create_from_image(packed)
	material.albedo_texture = albedo
	material.ao_texture = orm
	material.roughness_texture = orm
	material.metallic_texture = orm
	mesh.material = material

	var stats := FoliageMips.apply(mesh)
	assert_eq(stats["textures"], 2, "the albedo and the one ORM image")
	assert_eq(stats["cutouts"], 1)
	assert_gt(stats["bytes_after"], stats["bytes_before"])
	assert_lt(float(stats["bytes_after"]), float(stats["bytes_before"]) * 1.4, "a chain adds a third")
	assert_true(material.albedo_texture.get_image().has_mipmaps())
	assert_same(material.ao_texture, material.roughness_texture)
	assert_same(material.ao_texture, material.metallic_texture)
	assert_true(material.ao_texture.get_image().has_mipmaps())

	var second := FoliageMips.apply(mesh)
	assert_eq(second["textures"], 0, "a second pass finds nothing to do")


func test_a_null_mesh_is_ignored() -> void:
	assert_eq(FoliageMips.apply(null)["textures"], 0)
