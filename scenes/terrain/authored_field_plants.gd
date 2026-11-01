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

const NODE_NAME := "AuthoredFieldPlants"

## Plants standing after the last build.
var placed: int = 0
var builds: int = 0

var _key: String = ""
var _palette_root: String = PaletteLibrary.DEFAULT_ROOT


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
	if not plants.is_empty():
		ScatterGlbUtils.build_scatter(self, plants, PaletteLibrary.resolver(_palette_root))
	builds += 1
