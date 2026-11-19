extends GutTest

## The painted flowers' blooms (PainterFlowerHue, card painter-flowers): each core flower's bloom
## surface takes the accent of its own colour, its stems and leaves none, its cards' centres are
## found for the growth, the sheet carries the six accents in every mood, and the hand-placed props'
## layer is marked so it is never thinned.

const DIR := "res://libraries/core/assets/flower/"
## Core flower GLBs and the accent their blooms take (the colours measured on 2026-11-18: poppy
## bf452f, bloom mound c3668f and c7a42c, daisy ceccbf, buttercup cead35, bluebell 405ab8 and
## 566cbf, bellflower 7d61b8, lavender 8555c5).
const EXPECTED := {
	"Flower_Poppy_v0_grassland_meadow": PainterFlowerHue.RED,
	"Flower_BloomMound_v0_grassland_meadow": PainterFlowerHue.ROSE,
	"Flower_BloomMound_v1_alpine_meadow": PainterFlowerHue.GOLD,
	"Flower_Daisy_v0_grassland_meadow": PainterFlowerHue.WHITE,
	"Flower_Daisy_v2": PainterFlowerHue.GOLD,
	"Flower_BellCluster_v0_alpine_meadow": PainterFlowerHue.BLUE,
	"Flower_BellCluster_v0_temperate_forest": PainterFlowerHue.BLUE,
	"Flower_BellCluster_v2": PainterFlowerHue.VIOLET,
	"Flower_LavenderMound_v0": PainterFlowerHue.VIOLET,
}


func test_class_of_sorts_the_core_bloom_colours() -> void:
	var cases := {
		"bf452f": PainterFlowerHue.RED,
		"c3668f": PainterFlowerHue.ROSE,
		"873a46": PainterFlowerHue.ROSE,
		"c7a42c": PainterFlowerHue.GOLD,
		"cead35": PainterFlowerHue.GOLD,
		"ceccbf": PainterFlowerHue.WHITE,
		"405ab8": PainterFlowerHue.BLUE,
		"566cbf": PainterFlowerHue.BLUE,
		"7d61b8": PainterFlowerHue.VIOLET,
		"8555c5": PainterFlowerHue.VIOLET,
	}
	for hex: String in cases:
		assert_eq(PainterFlowerHue.class_of(Color(hex)), cases[hex], hex)


func test_core_blooms_take_their_own_accent() -> void:
	for stem: String in EXPECTED:
		var root := GlbUtils.load_glb(DIR + stem + ".glb")
		assert_not_null(root, stem)
		if root == null:
			continue
		var mesh := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var entry := PainterPlantRoles.of("x/" + stem, "grass", true)
		var blooms := 0
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			var surface := PainterPlantRoles.for_surface(entry, material, mesh, i)
			if material.resource_name.ends_with("_LeafB"):
				blooms += 1
				assert_eq(surface["petal"], EXPECTED[stem], stem + " blooms")
				assert_true(surface["dab"], stem + " drawn as dabs")
				var box: Vector4 = surface["dab_box"]
				assert_between(box.z, 0.1, 0.5, stem + " dab half width")
				assert_between(box.w, 0.3, 0.5, stem + " dab half height")
				_assert_centres(surface["centres"] as ImageTexture, mesh, i, stem)
			else:
				assert_eq(surface["petal"], PainterFlowerHue.NONE, stem + " stems and leaves")
				assert_false(surface["dab"], stem + " no dabs on " + material.resource_name)
		assert_eq(blooms, 1, stem + " has one bloom surface")
		root.free()


func test_a_bloom_mound_is_a_carpet_and_a_single_head_is_not() -> void:
	var carpets := {}
	for stem: String in EXPECTED:
		var root := GlbUtils.load_glb(DIR + stem + ".glb")
		if root == null:
			continue
		var mesh := (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			if mesh.surface_get_material(i).resource_name.ends_with("_LeafB"):
				var image := PainterFlowerHue.centres(mesh, i, Vector4(0.5, 0.5, 0.5, 0.5)).get_image()
				var carpet := image.get_pixel(0, image.get_height() - 1)
				carpets[stem] = carpet.a
				var verts: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
				gut.p("%s: %d vertices, carpet %.0f, top %.3f" % [stem, verts.size(), carpet.a, carpet.g])
		root.free()
	var mound := "Flower_BloomMound_v0_grassland_meadow"
	assert_eq(carpets.get(mound), 1.0, "the bloom mound is one carpet")
	assert_eq(carpets.get("Flower_BloomMound_v1_alpine_meadow"), 1.0, "both of them")
	assert_eq(carpets.get("Flower_Poppy_v0_grassland_meadow"), 0.0, "a poppy keeps its heads")
	assert_eq(carpets.get("Flower_BellCluster_v2"), 0.0, "and a cluster of bells on stems")
	var pair := PainterFlowerHue.carpet_of([Vector4(2, 1, 0, 2), Vector4(0, 3, 4, 1)])
	assert_almost_eq(Vector3(pair.r, pair.g, pair.b), Vector3(0.5, 3.0, 2.0), Vector3.ONE * 1e-5)
	assert_eq(pair.a, 0.0, "two cards are no carpet")


## Every vertex of a card shares one centre, inside the card's box, with a dab size above zero.
func _assert_centres(texture: ImageTexture, mesh: Mesh, surface: int, stem: String) -> void:
	assert_not_null(texture, stem + " centres")
	if texture == null:
		return
	var image := texture.get_image()
	var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var w := PainterFlowerHue.CENTRE_WIDTH
	var first := image.get_pixel(0, 0)
	for k in 4:
		var c := image.get_pixel(k % w, k / w)
		assert_almost_eq(Vector3(c.r, c.g, c.b), Vector3(first.r, first.g, first.b), Vector3.ONE * 1e-4)
	var mean := (verts[0] + verts[1] + verts[2] + verts[3]) / 4.0
	assert_almost_eq(Vector3(first.r, first.g, first.b), mean, Vector3.ONE * 1e-3, stem + " card 0")
	assert_between(first.a, 0.01, 0.5, stem + " dab size (m)")


func test_unknown_names_keep_the_per_pixel_petals() -> void:
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.2))
	image.fill_rect(Rect2i(0, 0, 8, 8), Color(0.75, 0.27, 0.18))
	var material := StandardMaterial3D.new()
	material.resource_name = "Wildflower_Atlas"
	material.albedo_texture = ImageTexture.create_from_image(image)
	var entry := PainterPlantRoles.of("x/Wildflower_Atlas", "grass", true)
	var surface := PainterPlantRoles.for_surface(entry, material)
	assert_eq(surface["petal"], PainterFlowerHue.RED, "petal pixels' own colour")
	assert_false(surface["dab"], "found per pixel, not dabs")
	var green := StandardMaterial3D.new()
	green.resource_name = "Wildflower_Atlas"
	image.fill(Color(0.2, 0.6, 0.2))
	green.albedo_texture = ImageTexture.create_from_image(image)
	assert_eq(PainterPlantRoles.for_surface(entry, green)["petal"], PainterFlowerHue.NONE)


func test_other_kinds_are_not_touched() -> void:
	var grass := PainterPlantRoles.of("x/Grass_Grass_v1", "grass")
	assert_false(PainterPlantRoles.for_surface(grass, null).has("petal"))


func test_sheet_tones_six_accents_in_every_mood() -> void:
	var sheet := PainterSheet.load_sheet(RenderStyle.DEFAULT_SHEET)
	assert_false(sheet.is_empty(), "the core sheet loads")
	for mood: String in PainterSheet.MOODS:
		for role in PainterFlowerHue.ROLES:
			for elevation in [-8.0, 5.0, 45.0]:
				var c := PainterSheet.tone(sheet, mood, role, elevation)
				assert_true(c.a > 0.0, "%s %s at %s" % [mood, role, elevation])


func test_placed_layer_is_marked() -> void:
	var props := Node3D.new()
	props.name = MapSourceLoader.PROPS_NODE
	var placed := MeshInstance3D.new()
	props.add_child(placed)
	var scatter := Node3D.new()
	scatter.name = "AuthoredScatter"
	var wild := MeshInstance3D.new()
	scatter.add_child(wild)
	add_child_autofree(props)
	add_child_autofree(scatter)
	PainterPlantTone.mark_placed([props, scatter])
	assert_eq(placed.get_instance_shader_parameter(PainterPlantTone.PLACED), 1.0, "placed")
	assert_null(wild.get_instance_shader_parameter(PainterPlantTone.PLACED), "scatter thinned")
