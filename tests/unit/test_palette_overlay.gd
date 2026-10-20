extends GutTest

## PaletteLibrary.overlay_package and PaletteOverlay (utils/palette_overlay.gd): a built
## package laid over an installed palette replaces exactly its biomes' assets, parses only the
## GLBs whose bytes differ from the installed ones, keeps the rest on the installed load
## path, and leaves other biomes and a failed overlay's caches alone.
##
## Fixture, built on the fly under user://: an installed palette with a meadow (Bell, Daisy,
## Old) and a forest (Oak), and a package with the meadow only: Bell byte-identical, Daisy
## rebuilt with two surfaces, Old gone, New added; and another package whose Bell has four.

const BASE := "user://test_palette_overlay/base"
const PACKAGE := "user://test_palette_overlay/package"
const OTHER := "user://test_palette_overlay/other"
const MEADOW := "meadow_summer_s1"
const FOREST := "forest_summer_s1"


func before_all() -> void:
	_write_glb(BASE, MEADOW, "Bell", _card_mesh(1))
	_write_glb(BASE, MEADOW, "Daisy", _card_mesh(1))
	_write_glb(BASE, MEADOW, "Old", _card_mesh(1))
	_write_glb(BASE, FOREST, "Oak", _card_mesh(1))
	_write_document(BASE, [_biome(MEADOW, ["Bell", "Daisy", "Old"]), _biome(FOREST, ["Oak"])])
	DirAccess.make_dir_recursive_absolute(PACKAGE.path_join("assets").path_join(MEADOW))
	var bell := "assets/%s/Bell.glb" % MEADOW
	DirAccess.copy_absolute(BASE.path_join(bell), PACKAGE.path_join(bell))
	_write_glb(PACKAGE, MEADOW, "Daisy", _card_mesh(2))
	_write_glb(PACKAGE, MEADOW, "New", _card_mesh(3))
	_write_document(PACKAGE, [_biome(MEADOW, ["Bell", "Daisy", "New"])])
	_write_glb(OTHER, MEADOW, "Bell", _card_mesh(4))
	_write_document(OTHER, [_biome(MEADOW, ["Bell"])])


func after_all() -> void:
	PaletteLibrary.clear_cache()
	_remove_tree("user://test_palette_overlay")


func before_each() -> void:
	PaletteLibrary.clear_cache()


func _card_mesh(surface_count: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in surface_count:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		# Not flat in any axis: a zero-thickness bound leaves a surface uncompressed.
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
			[Vector3(0, 0, 0), Vector3(0.5, 0, 0.2), Vector3(0, 2, 0.1)]
		)
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
		# Tangents and UVs, as treecube's GLBs carry: without them nothing is compressed.
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(0, 0)])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(
			[Color(0, 0, 0.2), Color(0, 0, 0.4), Color(1, 1, 0.6)]
		)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, StandardMaterial3D.new())
	return mesh


func _write_glb(root_path: String, biome_id: String, object_name: String, mesh: Mesh) -> void:
	DirAccess.make_dir_recursive_absolute(root_path.path_join("assets").path_join(biome_id))
	var root := Node3D.new()
	root.name = "Root"
	var node := MeshInstance3D.new()
	node.name = object_name
	node.mesh = mesh
	root.add_child(node)
	node.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	var path := root_path.path_join("assets/%s/%s.glb" % [biome_id, object_name])
	document.write_to_filesystem(state, path)
	root.free()


func _biome(biome_id: String, names: Array) -> Dictionary:
	var ids: Array = names.map(func(n: String) -> String: return "%s/%s" % [biome_id, n])
	return {
		"id": biome_id,
		"biome": biome_id.get_slice("_", 0),
		"season": "summer",
		"seed": 1,
		"name": biome_id,
		"climate": "temperate",
		"thumbnail": "thumbnails/%s.jpg" % biome_id,
		"ground_surface": "grass",
		"species":
		[
			{
				"key": "flower",
				"kind": "flower",
				"size_class": "small",
				"density_per_m2": 0.5,
				"min_spacing_m": 0.3,
				"slope_max_deg": 35.0,
				"scale_spread": 0.3,
				"yaw_random_deg": 360.0,
				"align": "upright",
				"near": [],
				"avoid": [],
				"assets": ids,
			}
		],
	}


func _write_document(root_path: String, biomes: Array) -> void:
	var assets := {}
	for biome: Dictionary in biomes:
		for asset_id: String in biome["species"][0]["assets"]:
			assets[asset_id] = {
				"file": "assets/%s.glb" % asset_id,
				"node": asset_id.get_slice("/", 1),
				"wind_category": "grass",
				"size_class": "small",
				"dimensions_m": [0.5, 2.0, 0.1],
			}
	var surface := {
		"albedo": "surfaces/grass/grass_albedo.png",
		"normal": "surfaces/grass/grass_normal.png",
		"orm": "surfaces/grass/grass_orm.png",
		"height": "surfaces/grass/grass_height.png",
		"tile_m": 2.0,
		"kind": "grass",
		"role": "ground",
	}
	var document := {
		"format": 1,
		"palette_version": root_path.get_file(),
		"surfaces": {"grass": surface},
		"biomes": biomes,
		"assets": assets,
	}
	var file := FileAccess.open(root_path.path_join("palette.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _surfaces(asset_id: String) -> int:
	var resolved := PaletteLibrary.resolve(asset_id, BASE)
	return (resolved["mesh"] as Mesh).get_surface_count() if not resolved.is_empty() else -1


func test_the_overlay_parses_exactly_the_changed_glbs_and_keeps_the_rest() -> void:
	var forest_oak := PaletteLibrary.resolve(FOREST + "/Oak", BASE)
	assert_false(forest_oak.is_empty(), "the installed forest loads")
	var report := PaletteLibrary.overlay_package(PACKAGE, BASE)
	assert_true(report["ok"], str(report["error"]))
	assert_eq(report["biomes"], [MEADOW])
	assert_eq(report["kept"], [MEADOW + "/Bell"], "byte-identical: the installed load path")
	assert_eq(report["parsed"], [MEADOW + "/Daisy", MEADOW + "/New"], "only the changed bytes")
	assert_eq(report["failed"], [])
	var assets := PaletteLibrary.get_palette(BASE)["assets"] as Dictionary
	assert_false(assets.has(MEADOW + "/Old"), "the installed meadow's own assets went")
	assert_true(assets.has(MEADOW + "/New"))
	assert_true(assets.has(FOREST + "/Oak"), "another biome is left alone")
	assert_eq(_surfaces(MEADOW + "/Daisy"), 2, "the package's rebuilt daisy")
	assert_eq(_surfaces(MEADOW + "/New"), 3)
	assert_eq(_surfaces(MEADOW + "/Bell"), 1)
	var species := PaletteLibrary.species(MEADOW, BASE)
	assert_eq(species[0]["assets"], [MEADOW + "/Bell", MEADOW + "/Daisy", MEADOW + "/New"])
	# Compressed as the installed asset is: this root's runtime parse compresses its one daisy
	# surface, so the rebuilt daisy's first surface is compressed and its second, new, is not.
	assert_eq(_compressed(FOREST + "/Oak"), [true], "this root's runtime parse compresses")
	assert_eq(_compressed(MEADOW + "/Daisy"), [true, false])
	assert_eq(_compressed(MEADOW + "/New"), [false, false, false], "a new asset: uncompressed")


## Per surface of the resolved asset, whether its vertex attributes are compressed.
func _compressed(asset_id: String) -> Array:
	var mesh := PaletteLibrary.resolve(asset_id, BASE)["mesh"] as Mesh
	var out := []
	for s in mesh.get_surface_count():
		out.append((mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0)
	return out


func test_a_kept_asset_reloads_from_the_root_after_an_earlier_overlay() -> void:
	# A Bell parsed by one round's overlay must not stay cached when the next one keeps it.
	var first := PaletteLibrary.overlay_package(OTHER, BASE)
	assert_eq(first["parsed"], [MEADOW + "/Bell"])
	assert_eq(_surfaces(MEADOW + "/Bell"), 4, "the other package's bell")
	var again := PaletteLibrary.overlay_package(PACKAGE, BASE)
	assert_eq(again["kept"], [MEADOW + "/Bell"])
	assert_eq(_surfaces(MEADOW + "/Bell"), 1, "the installed bell again")
	assert_eq(_surfaces(MEADOW + "/Daisy"), 2)


func test_a_package_that_cannot_be_read_changes_nothing() -> void:
	var before := PaletteLibrary.get_palette(BASE)
	var report := PaletteLibrary.overlay_package(PACKAGE + "_missing", BASE)
	assert_false(report["ok"])
	assert_string_contains(String(report["error"]), "palette.json")
	assert_same(PaletteLibrary.get_palette(BASE), before)
	var none := PaletteLibrary.overlay_package(PACKAGE, BASE, ["no_such_biome"])
	assert_false(none["ok"], "none of the asked biomes")
	assert_same(PaletteLibrary.get_palette(BASE), before)


func test_same_bytes_compares_contents() -> void:
	var bell := "assets/%s/Bell.glb" % MEADOW
	var daisy := "assets/%s/Daisy.glb" % MEADOW
	assert_true(PaletteOverlay.same_bytes(BASE.path_join(bell), PACKAGE.path_join(bell)))
	assert_false(PaletteOverlay.same_bytes(BASE.path_join(daisy), PACKAGE.path_join(daisy)))
	assert_false(PaletteOverlay.same_bytes(BASE.path_join(bell), PACKAGE.path_join("nope.glb")))
