class_name AuthoredFieldPlants
extends Node3D

## The plants of the document's village fields as nodes (the orchard trees, the garden's flowers
## and shrubs; VillageFields.plants_of) and of its hedged village boundaries
## (VillageBoundary.hedge_of): a derived layer like AuthoredSettlements beside it, so
## nothing here is saved or sent and every peer derives the same plants from the records. The
## plants are library assets drawn through the scatter's own builder (ScatterGlbUtils.build_scatter,
## PaletteLibrary.resolve), one MultiMesh per species, stood on the ground; a plant on water is
## left out. A refresh rebuilds only when the plants or the ground under them moved (a key of both).
## No collision: walk-through, as the scatter is. The species' wind materials are not registered
## with the level's wind re-tuning (the default preset holds).
##
## For the Painted look the layer answers the way a scatter does (rows_by_asset, resolved_species,
## and the two signals), so PainterSurfaces and PainterTrees draw its orchard trees, bushes and
## flowers with the painted trees' and plants' own machinery; Classic reads none of it.

## Emitted after every rebuild (the cells are not tracked: the list is empty), as a scatter's
## cells_applied: the painted look paints the species not yet painted and syncs its trees.
signal cells_applied(cells: Array[Vector2i])
## Never emitted (a field's species resolve at once); the painted look follows it on a scatter.
signal species_added(materials: Array[ShaderMaterial])

const NODE_NAME := "AuthoredFieldPlants"
## The prefix of a hedge bush's key for the painted look (PainterTreeSpecies: species bush_hedge).
const HEDGE_KEY := "hedge:"

## Plants standing after the last build.
var placed: int = 0
var builds: int = 0

var _key: String = ""
var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
## The plants of the last build (plants_of) and the species it resolved: asset id -> {"mesh",
## "wind_category", "height", "flower"} (the meshes every chunk node of the asset draws).
var _plants: Dictionary = {}
var _species: Dictionary = {}


## The layer under map root `root` brought up to `doc` (created only when a field has plants).
static func refresh_map(
	root: Node3D, doc: MapDocument, palette_root: String = PaletteLibrary.DEFAULT_ROOT
) -> AuthoredFieldPlants:
	var layer := root.get_node_or_null(NODE_NAME) as AuthoredFieldPlants
	var plants := plants_of(doc)
	if layer == null:
		if plants.is_empty():
			return null
		layer = AuthoredFieldPlants.new()
		layer.name = NODE_NAME
		root.add_child(layer)
	layer._palette_root = palette_root
	layer.refresh(doc, plants)
	return layer


## Every plant of `doc`'s fields that stands on dry ground: {asset: [scatter rows]} (the
## tt_scatter_instances shape, map frame). Pure.
static func plants_of(doc: MapDocument) -> Dictionary:
	var items: Array[Dictionary] = []
	for settlement in doc.settlements:
		items.append_array(VillageFields.plants_of(settlement))
		# A hedged village's boundary (VillageBoundary.hedge_of) is the same meadow bushes.
		if settlement.boundary == VillageBoundary.HEDGE:
			var planned := VillageBoundary.plan(doc, settlement)
			items.append_array(VillageBoundary.hedge_of(planned, settlement.seed_value))
	var out := {}
	if items.is_empty():
		return out
	var points := PackedVector2Array()
	for item in items:
		points.append(item["at"])
	var heights := WaterGeometry.grounds_at(doc, points)
	for k in items.size():
		var item := items[k]
		var at: Vector2 = item["at"]
		if WaterGeometry.is_wet_at(doc, at):
			continue
		var turn := Quaternion(Vector3.UP, float(item["yaw"]))
		var scale := float(item["scale"])
		var row := [at.x, heights[k] - 0.05, at.y, turn.x, turn.y, turn.z, turn.w, scale, scale, scale]
		if not out.has(item["asset"]):
			out[item["asset"]] = []
		(out[item["asset"]] as Array).append(row)
	return out


## Rebuilds the plants when `plants` (plants_of) differ from the last build.
func refresh(_doc: MapDocument, plants: Dictionary) -> void:
	var key := var_to_str(plants).md5_text()
	if key == _key:
		return
	_key = key
	for child in get_children():
		remove_child(child)
		child.queue_free()
	placed = 0
	for rows: Array in plants.values():
		placed += rows.size()
	_plants = plants
	_species = {}
	if not plants.is_empty():
		ScatterGlbUtils.build_scatter(self, plants, _resolve)
	builds += 1
	cells_applied.emit([] as Array[Vector2i])


## The plants as a scatter lists its rows: asset id -> flat rows of MapDocument.ROW_STRIDE floats
## (x, y, z, rotation quaternion, scale x y z). A hedge bush is listed under paint_key (HEDGE_KEY
## before its id), so the painted look draws it as a hedge.
func rows_by_asset() -> Dictionary:
	var out := {}
	for asset: String in _plants:
		var flat := PackedFloat32Array()
		for row: Array in _plants[asset]:
			flat.append_array(PackedFloat32Array(row))
		out[paint_key(asset)] = flat
	return out


## Every resolved species as a scatter lists them (paint_key -> {"mesh", "wind_category", "height",
## "flower", "crop"}); the meshes are the ones the chunk nodes draw, so a material set on a surface
## shows on every plant of the asset.
func resolved_species() -> Dictionary:
	var out := {}
	for asset: String in _species:
		out[paint_key(asset)] = _species[asset]
	return out


## The painted look's key of `asset_id`: HEDGE_KEY + the id for a hedge bush (VillageFields'
## hedgerows and a hedged boundary use only HEDGE_SHRUBS), the id itself otherwise.
static func paint_key(asset_id: String) -> String:
	return HEDGE_KEY + asset_id if VillageFields.HEDGE_SHRUBS.has(asset_id) else asset_id


## PaletteLibrary.resolve for build_scatter, keeping the species it hands out (resolved_species).
func _resolve(asset_id: String) -> Dictionary:
	var template := PaletteLibrary.resolve(asset_id, _palette_root)
	var mesh := template.get("mesh") as Mesh
	if mesh != null:
		_species[asset_id] = {
			"mesh": mesh,
			"wind_category": template.get("wind_category", ""),
			"height": maxf(mesh.get_aabb().end.y, 0.0),
			"flower": template.get("flower", false) == true,
			"crop": is_crop(asset_id),
		}
	return template


## True for a crop plant (VillageCrops.PLANT_ASSETS): the painted look tones it as its crop.
static func is_crop(asset_id: String) -> bool:
	for assets: Array in VillageCrops.PLANT_ASSETS.values():
		if assets.has(asset_id):
			return true
	return false
