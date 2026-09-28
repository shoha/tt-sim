extends RefCounted

## Shared fixtures for test_map_document_io.gd and test_map_document_validation.gd (not a
## test file itself: GUT only collects test_*.gd). Preload it as a const.

const TREE_ID := "birch_woodland_summer_s1/Tree_Small"
const ROCK_ID := "birch_woodland_summer_s1/Rock_Small"
const BIOME_A := "birch_woodland_summer_s1"
const BIOME_B := "boreal_taiga_summer_s2"
## Samples per axis of a 20 x 20 cell map at the defaults.
const GRID := 123
const IDENTITY_ROW := "[0,0,0,0,0,0,1,1,1,1]"
const RIVER_ID := 3
const POND_ID := 7


## A 20 x 20 cell document with something in every field.
static func full_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_alpine", "ad44aa5", 123456789)
	doc.has_base_map = true
	doc.tier_height_m = 0.762
	var heights := doc.heights.duplicate()
	for i in heights.size():
		heights[i] = sin(i * 0.01) * 3.0 - 0.5
	doc.heights = heights
	var tree := PackedFloat32Array([1.5, 0.0, -2.25, 0.0, 0.3826834, 0.0, 0.9238795])
	tree.append_array(PackedFloat32Array([1.1, 1.1, 1.1]))
	var rocks := PackedFloat32Array([-10.125, 0.1, 5.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.25, 0.5])
	rocks.append_array(PackedFloat32Array([12.0, -0.05, -14.9, 0.1, 0.2, 0.3, 0.9273618]))
	rocks.append_array(PackedFloat32Array([2.0, 2.0, 2.0]))
	doc.scatter = {TREE_ID: tree, ROCK_ID: rocks}
	doc.props = {"unknown_pkg/Hero_Statue": PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])}
	var count := doc.sample_count()
	var erase := PackedByteArray()
	erase.resize(count)
	for i in range(0, count, 7):
		erase[i] = 255
	doc.erase_mask = erase
	doc.biome_ids = PackedStringArray([BIOME_A, BIOME_B])
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(count)
	density.resize(count)
	for i in count:
		slots[i] = i % 3
		density[i] = i % 256
	doc.biome_slots = slots
	doc.biome_density = density
	add_water(doc)
	add_crossings(doc)
	return doc


## A plank bridge and a line of stepping stones over the river of add_water().
static func add_crossings(doc: MapDocument) -> void:
	doc.crossings.append(
		Crossing.make(
			2,
			Crossing.Kind.PLANK,
			Vector2(-3.25, -2.5),
			Vector2(-1.5, 3.75),
			Vector3(0.125, 0.5, 0.25),
			1.5,
			BIOME_A
		)
	)
	doc.crossings.append(
		Crossing.make(
			5,
			Crossing.Kind.STONES,
			Vector2(4.5, -1.0),
			Vector2(3.0, 5.5),
			Vector3(0, -0.6, 0),
			0.75
		)
	)


## A river (upstream at -X), a pond over a box of samples, and the baked flow map.
static func add_water(doc: MapDocument) -> void:
	var line := PackedVector2Array([Vector2(-12, -3), Vector2(-2, 0.5), Vector2(9.25, 4)])
	var widths := PackedFloat32Array([1.0, 1.5, 2.0])
	var river := WaterBody.river(RIVER_ID, line, widths, WaterBody.Depth.WAIST, -0.75, 0.8)
	doc.water_bodies.append(river)
	doc.water_bodies.append(WaterBody.pond(POND_ID, WaterBody.Depth.DEEP, -1.25))
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in range(80, 100):
		for x in range(10, 40):
			mask[doc.sample_index(x, z)] = POND_ID
	doc.pond_mask = mask
	doc.water_flow_size = WaterFlowBaker.resolution_for(doc.extent_m())
	doc.water_flow = WaterFlowBaker.bake(doc, doc.water_flow_size)


## A manifest for a 20 x 20 map at the defaults, with `overrides` merged in.
static func manifest(overrides: Dictionary) -> PackedByteArray:
	var fields := {
		"format": 1,
		"palette_version": "v",
		"map_seed": 1,
		"size_cells": [20, 20],
		"cell_size_m": 1.524,
		"sample_spacing_m": 0.25,
		"tier_height_m": 1.524,
		"base_surface": "grass_alpine",
		"has_base_map": false,
	}
	fields.merge(overrides, true)
	return JSON.stringify(fields).to_utf8_buffer()


## Minimal valid entries for a flat 20 x 20 document, plus `extra`.
static func minimal_entries(extra: Dictionary = {}) -> Dictionary:
	var heights := PackedFloat32Array()
	heights.resize(GRID * GRID)
	var entries := {"manifest.json": manifest({}), "height.bin": heights.to_byte_array()}
	entries.merge(extra, true)
	return entries


static func rows_entry(text: String) -> Dictionary:
	return minimal_entries({"scatter.json": text.to_utf8_buffer()})


static func mask_png(size: Vector2i, format: Image.Format) -> PackedByteArray:
	return Image.create_empty(size.x, size.y, false, format).save_png_to_buffer()


static func has_warning(result: Dictionary, fragment: String) -> bool:
	for warning in result["warnings"]:
		if fragment in warning:
			return true
	return false
