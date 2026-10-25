extends GutTest

## The library route against the package route (design doc 6.1): savanna_summer_s1 generated at
## seed 1234 over a fixed square through (a) PaletteLibrary.overlay_package with plantgen's
## palette package and (b) LibraryRegistry with the library plantgen exported from the same
## package must give byte-identical rows, and the same species rules. The technique is
## scatter_golden.gd's (a varying painted density, flat ground).
##
## The two folders live outside this repo, so the test reads them from environment variables and
## is pending when they are not set:
##   PLANTGEN_LIB_SLICE      the exported library (plantgen out/lib_slice)
##   PLANTGEN_LIB_SLICE_PKG  the package it was built from (plantgen out/lib_slice_pkg)
## Run (PowerShell):  $env:PLANTGEN_LIB_SLICE='D:/dev/plantgen/out/lib_slice'
##   $env:PLANTGEN_LIB_SLICE_PKG='D:/dev/plantgen/out/lib_slice_pkg'
##   godot --headless --path <project> --script res://addons/gut/gut_cmdln.gd --
##     '-gconfig=tests/.gutconfig.json' -gselect=test_library_row_parity
## The miniature library in tests/fixtures/library_mini proves the compile path without them
## (test_library_compile.gd).

const BIOME := "savanna_summer_s1"
const SEED := 1234
const HALF_M := 16.0
const ENV_LIBRARY := "PLANTGEN_LIB_SLICE"
const ENV_PACKAGE := "PLANTGEN_LIB_SLICE_PKG"


func before_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


func after_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


static func _density(p: Vector2) -> float:
	return clampf(0.55 + 0.45 * sin(p.x * 0.21) * cos(p.y * 0.17), 0.0, 1.0)


static func _flat(_p: Vector2) -> float:
	return 0.0


static func _up(_p: Vector2) -> Vector3:
	return Vector3.UP


## {asset id: "count:md5"} of the biome's rows at the fixed seed over the fixed square.
func _digest() -> Dictionary:
	var bounds := Rect2(-HALF_M, -HALF_M, 2.0 * HALF_M, 2.0 * HALF_M)
	var rows := ScatterGenerator.generate(
		BIOME,
		PaletteLibrary.species(BIOME),
		_density,
		_flat,
		_up,
		SEED,
		ScatterGenerator.cells_in_bounds(bounds),
		bounds
	)
	var out := {}
	for asset_id: String in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_MD5)
		hashing.update(flat.to_byte_array())
		out[asset_id] = (
			"%d:%s" % [flat.size() / MapDocument.ROW_STRIDE, hashing.finish().hex_encode()]
		)
	return out


func _species_json() -> String:
	return JSON.stringify(PaletteLibrary.species(BIOME), "", true)


func test_library_rows_equal_package_rows() -> void:
	var library := OS.get_environment(ENV_LIBRARY)
	var package := OS.get_environment(ENV_PACKAGE)
	if library == "" or package == "":
		pending(
			"set %s and %s to run the package against library parity" % [ENV_LIBRARY, ENV_PACKAGE]
		)
		return
	if OS.get_name() != "Windows":
		pending("row digests are Windows' float bytes")
		return
	var overlay := PaletteLibrary.overlay_package(package, PaletteLibrary.DEFAULT_ROOT, [BIOME])
	assert_true(overlay["ok"], str(overlay["error"]))
	var package_species := _species_json()
	var package_rows := _digest()
	assert_gt(package_rows.size(), 20, "the package route grows plants")
	PaletteLibrary.clear_cache()
	LibraryRegistry.set_dev_override(library)
	var applied := LibraryRegistry.apply()
	assert_true(applied["ok"], str(applied["error"]))
	assert_eq(applied["biomes"], [BIOME])
	assert_eq(applied["report"]["failed"], [], "every GLB parsed")
	assert_eq(applied["warnings"], [], "no read, compile or palette warnings")
	assert_eq(_species_json(), package_species, "the same species rules, height and width included")
	var library_rows := _digest()
	assert_eq(library_rows.keys(), package_rows.keys(), "the same assets grow")
	for asset_id: String in package_rows:
		assert_eq(library_rows[asset_id], package_rows[asset_id], asset_id)
	assert_eq(library_rows, package_rows)
