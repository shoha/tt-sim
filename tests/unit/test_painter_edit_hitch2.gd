extends GutTest

## Card painter-edit-hitch2 (docs/PERFORMANCE.md "Authoring edits"): the first water on a map
## builds the painted zone maps whole once, not once at the carve and again at the dressing
## refresh, and the bytes are a whole build's; the painted trees' per-landing listing
## (PainterTrees.sync_cells) lists only the landed cells' rows, and the union of every cell's
## listing is what a whole sync lists.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const TREE_ASSET := "Tree_Oak_Source"


func test_a_first_water_builds_the_zone_maps_once() -> void:
	var container := Node3D.new()
	add_child_autofree(container)
	var map := Node3D.new()
	map.name = "LevelMap"
	container.add_child(map)
	var doc := MapDocument.create_flat(Vector2i(12, 12), "grass_meadow", "test", 7)
	var terrain := AuthoredTerrain.create(doc)
	map.add_child(terrain)
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(map, STATE))
	surfaces._rebuild_zone()
	var builds := surfaces.zones().builds
	# The carve's landing: the heights of a rect and the first wet dressing on the map.
	var n := doc.samples_x() * doc.samples_z()
	var wet := PackedByteArray()
	wet.resize(n * 4)
	for i in range(0, n, 7):
		wet[i * 4] = 200
	doc.water_dressing = wet
	assert_true(terrain.water_dressing_pending(), "the dressing is not uploaded yet")
	terrain.ground_edited.emit(Rect2i(4, 4, 6, 5))
	surfaces._rebuild_zone()
	assert_eq(surfaces.zones().builds, builds, "no whole build before the dressing refresh")
	# The landing's third frame: the refresh re-tables and marks the grid.
	terrain.refresh_water_dressing()
	assert_false(terrain.water_dressing_pending())
	surfaces._rebuild_zone()
	assert_eq(surfaces.zones().builds, builds + 1, "one whole build for the first water")
	assert_eq(
		surfaces.zones().zone.get_data(),
		PainterZoneMaps.zone_image(doc).get_data(),
		"the bytes are a whole build's"
	)
	surfaces.release()


## A stand-in scatter: rows by cell, answering as AuthoredScatter does for the listing.
class CellScatter:
	extends Node3D
	var cells := {}

	func rows_by_asset() -> Dictionary:
		var keys := cells.keys()
		keys.sort()
		var out := {}
		for cell: Vector2i in keys:
			for asset: String in cells[cell]:
				if not out.has(asset):
					out[asset] = PackedFloat32Array()
				var joined: PackedFloat32Array = out[asset]
				joined.append_array(cells[cell][asset])
				out[asset] = joined
		return out

	func cell_rows(cell: Vector2i) -> Dictionary:
		return cells.get(cell, {})

	func cell_keys() -> Array:
		return cells.keys()

	func resolved_species() -> Dictionary:
		return {}


func _row(x: float, z: float) -> PackedFloat32Array:
	var row := PackedFloat32Array()
	row.resize(MapDocument.ROW_STRIDE)
	row[0] = x
	row[2] = z
	row[3] = 1.0
	for k in range(PainterTreeSpecies.SCALE_AT, MapDocument.ROW_STRIDE):
		row[k] = 1.0
	return row


func test_a_cell_listing_is_its_share_of_the_whole_listing() -> void:
	var scatter := CellScatter.new()
	add_child_autofree(scatter)
	for cx in 4:
		for cz in 3:
			var rows := PackedFloat32Array()
			for k in 5:
				rows.append_array(_row(cx * 10.0 + 1.5 + k, cz * 10.0 + 2.0 + k * 1.3))
			var rock := _row(cx * 10.0, cz * 10.0)
			scatter.cells[Vector2i(cx, cz)] = {TREE_ASSET: rows, "Rock_Boulder_A": rock}
	var whole := PainterTrees.wanted([scatter], null)
	assert_eq(whole.size(), 60, "every tree row, no rock")
	var union := {}
	for cell: Vector2i in scatter.cell_keys():
		var one := {}
		PainterTreeRows.want_rows(one, scatter.cell_rows(cell), scatter, null)
		assert_eq(one.size(), 5, "a cell lists its own five rows")
		assert_eq(
			PainterTreeRows.keys_of(scatter.cell_rows(cell)).size(), 5, "the index keys of a cell"
		)
		union.merge(one)
	assert_eq(union.keys().size(), whole.size())
	for key: Vector3i in whole:
		assert_true(union.has(key))
		assert_eq(union[key], whole[key], "the same entry as the whole listing")
