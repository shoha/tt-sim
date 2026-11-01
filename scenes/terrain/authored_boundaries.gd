class_name AuthoredBoundaries
extends AuthoredWalls

## The stone boundaries of the document's villages as nodes (topic bounds; VillageBoundary): a
## derived layer like AuthoredSettlements beside it, so nothing here is saved or sent and every
## peer derives the same walls from the records. Each village's runs and gate piers are transient
## Wall records (VillageBoundary.walls_of, never in MapDocument.walls) built by WallGeometry like
## a drawn stone wall and merged into ONE node per village (`Wall_<settlement id>`), whose masonry
## wears the street lots' warm painterly material, the yards' walls' look. A refresh rebuilds a
## village's node only when its walls or the ground under them moved (WallGeometry.key_of of each).
## No collision: a boundary is walk-through, like the furnishings (a stone wall drawn with the
## Wall tool is the one to stand on). A hedge is plants (AuthoredFieldPlants), not drawn here.

const BOUNDARY_NODE := "AuthoredBoundaries"

## Per settlement id, the key its node was built from.
var _boundary_keys: Dictionary = {}


## The layer under map root `root` brought up to `doc` (created only when a village has a stone
## boundary).
static func refresh_boundaries(
	root: Node3D, doc: MapDocument, palette_root: String = PaletteLibrary.DEFAULT_ROOT
) -> AuthoredBoundaries:
	var layer := root.get_node_or_null(BOUNDARY_NODE) as AuthoredBoundaries
	if layer == null:
		var any := false
		for settlement in doc.settlements:
			any = any or VillageBoundary.is_stone(settlement.boundary)
		if not any:
			return null
		layer = AuthoredBoundaries.new()
		layer.name = BOUNDARY_NODE
		root.add_child(layer)
	layer._palette_root = palette_root
	layer.sync(doc)
	return layer


## Rebuilds the villages whose boundary walls moved and frees the nodes of those that have none.
func sync(doc: MapDocument) -> void:
	var wanted := {}
	var rebuilt := 0
	for settlement in doc.settlements:
		if not VillageBoundary.is_stone(settlement.boundary):
			continue
		var walls := VillageBoundary.walls_of(VillageBoundary.plan(doc, settlement))
		if walls.is_empty():
			continue
		wanted[settlement.id] = true
		var keys := [settlement.boundary]
		for wall in walls:
			keys.append(WallGeometry.key_of(doc, wall))
		var key := hash(keys)
		if _boundary_keys.get(settlement.id) == key and get_wall_node(settlement.id) != null:
			continue
		var parts := merged(doc, settlement.id, walls)
		_free_wall_node(settlement.id)
		add_child(_wall_node(parts))
		_tops[settlement.id] = float(parts.top)
		_boundary_keys[settlement.id] = key
		rebuilt += 1
	for child in get_children():
		var id := _id_of(child)
		if not wanted.has(id):
			_free_wall_node(id)
			_boundary_keys.erase(id)
			rebuilt += 1
	builds += rebuilt
	last_rebuilt = rebuilt
	if rebuilt > 0:
		_recompute_top()
		version += 1


## The parts of `walls` (WallGeometry.build_one each) merged into one, `id` the settlement's:
## its stone, masonry and wood surfaces concatenated, no collision, the highest top. The kind is
## the street's (Wall.Kind.ROW), so the masonry takes the lots' material.
static func merged(doc: MapDocument, id: int, walls: Array[Wall]) -> Dictionary:
	var out := {
		"id": id,
		"kind": Wall.Kind.ROW,
		"style": "",
		"stone": [],
		"masonry": [],
		"wood": [],
		"collision": PackedVector3Array(),
		"top": WallGeometry.NONE,
	}
	for wall in walls:
		var parts := WallGeometry.build_one(doc, wall)
		for kind in ["stone", "masonry", "wood"]:
			out[kind] = concat(out[kind], parts.get(kind, []))
		out.top = maxf(float(out.top), float(parts.top))
	return out


## Mesh arrays `a` followed by `b` (same layout; `b`'s indices moved past `a`'s vertices). Pure.
static func concat(a: Array, b: Array) -> Array:
	if b.is_empty():
		return a
	if a.is_empty():
		return b.duplicate()
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	var offset := (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for slot in Mesh.ARRAY_MAX:
		if a[slot] == null or b[slot] == null:
			continue
		if slot == Mesh.ARRAY_INDEX:
			var moved := PackedInt32Array(b[slot])
			for k in moved.size():
				moved[k] += offset
			out[slot] = PackedInt32Array(a[slot]) + moved
		else:
			out[slot] = a[slot] + b[slot]
	return out
