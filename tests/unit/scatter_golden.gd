extends RefCounted

## The golden digest of every built-in biome's generated rows (test_scatter_mass.gd): each
## biome of the installed palette generated at GOLDEN_SEED over a square of GOLDEN_HALF_M with
## a varying painted density, and per asset id its row count and the MD5 of its rows' bytes.
## FIXTURE was first written from main's code path (94e18825, before the ground ship's mass
## port) by running dump() once, and re-pinned when the ship palette (treecube 020bbdc) was
## installed (ground ship card 4): only the grass of the six zoned biomes moved (their mass,
## clump and density fields), while boreal_taiga, rocky_badlands and burnt_forest, which carry
## no mass fields, still grow exactly main's rows. Re-pin only after checking that. The
## digests are Windows' bytes (other platforms differ in the last bit), so the test runs there
## only.

const GOLDEN_SEED := 1234
const GOLDEN_HALF_M := 12.0
const FIXTURE := "res://tests/fixtures/scatter_golden_1234.json"


static func _density(p: Vector2) -> float:
	return clampf(0.55 + 0.45 * sin(p.x * 0.21) * cos(p.y * 0.17), 0.0, 1.0)


static func _flat(_p: Vector2) -> float:
	return 0.0


static func _up(_p: Vector2) -> Vector3:
	return Vector3.UP


## {biome id: {asset id: "count:md5"}} for every built-in biome.
static func digest_all() -> Dictionary:
	var out := {}
	var bounds := Rect2(
		-GOLDEN_HALF_M, -GOLDEN_HALF_M, 2.0 * GOLDEN_HALF_M, 2.0 * GOLDEN_HALF_M
	)
	for biome: Dictionary in PaletteLibrary.biomes():
		var biome_id := String(biome.get("id", ""))
		var rows := ScatterGenerator.generate(
			biome_id,
			PaletteLibrary.species(biome_id),
			_density,
			_flat,
			_up,
			GOLDEN_SEED,
			ScatterGenerator.cells_in_bounds(bounds),
			bounds
		)
		var assets := {}
		for asset_id in rows:
			var flat: PackedFloat32Array = rows[asset_id]
			var hashing := HashingContext.new()
			hashing.start(HashingContext.HASH_MD5)
			hashing.update(flat.to_byte_array())
			var count := flat.size() / MapDocument.ROW_STRIDE
			assets[asset_id] = "%d:%s" % [count, hashing.finish().hex_encode()]
		out[biome_id] = assets
	return out


## Writes digest_all() to FIXTURE (tests/fixtures/dump_scatter_golden.gd).
static func dump() -> void:
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	file.store_string(JSON.stringify(digest_all(), "\t", true))
	file.close()


## The pinned digest, or {} when the fixture cannot be read.
static func pinned() -> Dictionary:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	if file == null:
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}
