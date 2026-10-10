class_name DressingReconcile
extends RefCounted

## Keep dressing: what Replace map (and Reload from Blender) does to a dressed level's
## document (MapDocument.has_base_map) when a new map.glb arrives under it, so the author's
## painting carries over to the new ground.
##
## - Heights are not touched here. A dressing document's heights are the GLB's ground,
##   sampled from its collision every time authoring opens the level and at every play load
##   (MapSourceLoader.fit_dressing_ground_async), which also sets the generated rows down on
##   the new ground; the next open refits them to the new map.
## - Hand-placed props and generated rows whose position falls outside the new map's
##   footprint (the import check's bounds, in X and Z) are dropped and counted: there is no
##   ground under them any more. The painted biome cover outside it is cleared too, so a
##   later regeneration grows nothing over the void.
## - When the new map reaches past the document, the document grows to cover it (the same
##   size rule as a new dressing, NewMap.dressing_cells, never smaller than before) and every
##   per-sample layer is carried across by position (regrid()). The baked flow map spans the
##   old extent, so it is cleared; it is baked again on the next water edit.
##
## Props keep their saved height: a prop is bedded on the ground when placed, and nothing
## re-beds it, so a prop on ground that Blender raised or lowered needs a nudge by hand.

## Rows and samples this close outside the footprint still count as on it.
const EDGE_TOLERANCE_M := 0.01


## Keeps `doc` (edited in place, or replaced by a grown copy) over a new map whose geometry
## spans `footprint` (metres, the map root's frame). Returns {"document": the document to
## save, "props_dropped": int, "scatter_dropped": int, "grown": bool}.
static func keep(doc: MapDocument, footprint: AABB) -> Dictionary:
	var needed := NewMap.dressing_cells(footprint, doc.cell_size_m)
	var cells := Vector2i(maxi(doc.size_cells.x, needed.x), maxi(doc.size_cells.y, needed.y))
	var grown := cells != doc.size_cells
	var out := regrid(doc, cells) if grown else doc
	var area := Rect2(
		Vector2(footprint.position.x, footprint.position.z),
		Vector2(footprint.size.x, footprint.size.z)
	)
	area = area.grow(EDGE_TOLERANCE_M)
	var props := rows_inside(out.props, area)
	var scatter := rows_inside(out.scatter, area)
	out.props = props.rows
	out.scatter = scatter.rows
	clear_cover_outside(out, area)
	return {
		"document": out,
		"props_dropped": props.dropped,
		"scatter_dropped": scatter.dropped,
		"grown": grown,
	}


## The rows of `rows_by_asset` (asset id -> flat rows) whose X and Z fall inside `area`, an
## asset left with none dropped. Returns {"rows": the kept rows, "dropped": rows removed}.
## Pure.
@warning_ignore("integer_division")
static func rows_inside(
	rows_by_asset: Dictionary[String, PackedFloat32Array], area: Rect2
) -> Dictionary:
	var stride := MapDocument.ROW_STRIDE
	var kept: Dictionary[String, PackedFloat32Array] = {}
	var dropped := 0
	for asset_id in rows_by_asset:
		var rows: PackedFloat32Array = rows_by_asset[asset_id]
		var inside := PackedFloat32Array()
		for r in rows.size() / stride:
			var b := r * stride
			if area.has_point(Vector2(rows[b], rows[b + 2])):
				inside.append_array(rows.slice(b, b + stride))
			else:
				dropped += 1
		if not inside.is_empty():
			kept[asset_id] = inside
	return {"rows": kept, "dropped": dropped}


## Clears the painted biome cover (slot and density) of every sample of `doc` outside `area`.
static func clear_cover_outside(doc: MapDocument, area: Rect2) -> void:
	if doc.biome_slots.size() != doc.sample_count():
		return
	var slots := doc.biome_slots
	var density := doc.biome_density
	for z in doc.samples_z():
		for x in doc.samples_x():
			if not area.has_point(doc.sample_to_world(Vector2(x, z))):
				var index := doc.sample_index(x, z)
				slots[index] = 0
				if index < density.size():
					density[index] = 0
	doc.biome_slots = slots
	doc.biome_density = density


## A copy of `doc` `cells` in size, every per-sample layer (heights, erase, biome, surface
## and pond masks) carried across by position: each new sample takes the nearest old one's
## value, or nothing (0) off the old grid. Rows, water bodies and crossings are in map
## metres and carry over as they are; the flow map spans the old extent and is cleared.
static func regrid(doc: MapDocument, cells: Vector2i) -> MapDocument:
	var out := MapDocument.new()
	out.palette_version = doc.palette_version
	out.map_seed = doc.map_seed
	out.size_cells = cells
	out.cell_size_m = doc.cell_size_m
	out.sample_spacing_m = doc.sample_spacing_m
	out.tier_height_m = doc.tier_height_m
	out.base_surface = doc.base_surface
	out.has_base_map = doc.has_base_map
	out.scatter = doc.scatter
	out.props = doc.props
	out.biome_ids = doc.biome_ids
	out.surface_ids = doc.surface_ids
	out.water_bodies = doc.water_bodies
	out.crossings = doc.crossings
	var nearest := nearest_samples(doc, out)
	var heights := PackedFloat32Array()
	heights.resize(nearest.size())
	for i in nearest.size():
		if nearest[i] >= 0 and nearest[i] < doc.heights.size():
			heights[i] = doc.heights[nearest[i]]
	out.heights = heights
	out.erase_mask = remap_bytes(doc.erase_mask, nearest, doc.sample_count(), 1)
	out.biome_slots = remap_bytes(doc.biome_slots, nearest, doc.sample_count(), 1)
	out.biome_density = remap_bytes(doc.biome_density, nearest, doc.sample_count(), 1)
	out.pond_mask = remap_bytes(doc.pond_mask, nearest, doc.sample_count(), 1)
	out.surface_weights = remap_bytes(
		doc.surface_weights, nearest, doc.sample_count(), MapDocument.SURFACE_CHANNELS
	)
	return out


## For every sample of `to`, the index of the nearest sample of `from` at the same map
## position, or -1 off `from`'s grid. Pure.
static func nearest_samples(from: MapDocument, to: MapDocument) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(to.sample_count())
	var columns := from.samples_x()
	var rows := from.samples_z()
	for z in to.samples_z():
		for x in to.samples_x():
			var at := from.world_to_sample(to.sample_to_world(Vector2(x, z)))
			var ox := roundi(at.x)
			var oz := roundi(at.y)
			var inside := ox >= 0 and oz >= 0 and ox < columns and oz < rows
			out[to.sample_index(x, z)] = oz * columns + ox if inside else -1
	return out


## A per-sample byte layer `source` of `old_count` samples carried onto the samples `nearest`
## names (nearest_samples()), in planes of `channels` bytes per sample: `source` holds
## size / (old_count * channels) such planes one after another (surface weights hold two of
## four channels), and so does the result. Empty stays empty (a layer the document lacks).
## Pure.
@warning_ignore("integer_division")
static func remap_bytes(
	source: PackedByteArray, nearest: PackedInt32Array, old_count: int, channels: int
) -> PackedByteArray:
	if source.is_empty() or old_count <= 0:
		return PackedByteArray()
	var old_plane := old_count * channels
	var new_plane := nearest.size() * channels
	var planes := source.size() / old_plane
	var out := PackedByteArray()
	out.resize(new_plane * planes)
	for plane in planes:
		for i in nearest.size():
			var o := nearest[i]
			if o < 0:
				continue
			for c in channels:
				out[plane * new_plane + i * channels + c] = source[plane * old_plane + o * channels + c]
	return out
