class_name TerraWallSync
extends RefCounted
## The wall sync of the terraforming core (card terraform-p2-walls; docs/systems/terraform.md
## "Tools"): with the core on, the map's stone walls and fences stand on pads, and a pad is a wall
## primitive (kind 7, [height, thickness, x0, z0, ...]) of the map's TerraDoc. The wall
## primitives mirror the document's wall list: one per stone wall or fence, in list order, its
## points the wall's (a closed wall repeats its first point), its thickness WallGeometry's. A
## street row adds none. A wall primitive with no wall behind it (one a corpus or an older map
## carried) is dropped, so a pad never stands without its wall.
##
## sync(doc) is pure: it returns the one session edit that makes the primitives mirror the list,
## a splice, or {} when they already do. It keeps the longest run of wall primitives at the front
## that already match and rebuilds the rest under new ids, at the place of the first one it drops
## (at the end of the document when there was none), so the derive re-sets as little as it can.
## TerraEditor.sync_walls applies it inside the wall edit's history group.


## The wall primitive's floats for `wall`, or an empty array for a row (or a line too short).
static func data_of(wall: Wall) -> PackedFloat32Array:
	var thickness := WallGeometry.thickness_m(wall)
	if thickness <= 0.0 or wall.points.size() < 2:
		return PackedFloat32Array()
	var out := PackedFloat32Array([wall.height_m, thickness])
	for p in wall.points:
		out.append(p.x)
		out.append(p.y)
	if wall.closed:
		out.append(wall.points[0].x)
		out.append(wall.points[0].y)
	return out


## The floats of every wall primitive `doc`'s walls make, in list order.
static func wanted(doc: MapDocument) -> Array[PackedFloat32Array]:
	var out: Array[PackedFloat32Array] = []
	for wall in doc.walls:
		var data := data_of(wall)
		if not data.is_empty():
			out.append(data)
	return out


## `terra`'s wall primitives in document order.
static func wall_prims(terra: TerraDoc) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in terra.prims:
		if int(p["kind"]) == TerraCore.WALL:
			out.append(p)
	return out


## The session edit that makes `doc.terra`'s wall primitives mirror `doc.walls` (see the header):
## {"op": "splice", "remove", "insert", "at", "next_id"}, or {} when they already do (or the
## document has no terrain section).
static func sync(doc: MapDocument) -> Dictionary:
	var terra := doc.terra as TerraDoc
	if terra == null:
		return {}
	var want := wanted(doc)
	var have := wall_prims(terra)
	var keep := 0
	while keep < mini(want.size(), have.size()) and _same(have[keep], want[keep]):
		keep += 1
	if keep == want.size() and keep == have.size():
		return {}
	var remove: Array = []
	for k in range(keep, have.size()):
		remove.append(int(have[k]["id"]))
	var at := terra.prims.size() - remove.size()
	if keep < have.size():
		# Every dropped primitive stands at or after the first one, so its place is unchanged.
		at = terra.index_of(int(have[keep]["id"]))
	elif keep > 0:
		at = terra.index_of(int(have[keep - 1]["id"])) + 1
	var insert: Array = []
	var next := terra.next_id
	for k in range(keep, want.size()):
		insert.append({"id": next, "kind": TerraCore.WALL, "flags": 0, "data": want[k]})
		next += 1
	return {"op": "splice", "remove": remove, "insert": insert, "at": at, "next_id": next}


static func _same(prim: Dictionary, data: PackedFloat32Array) -> bool:
	return int(prim["flags"]) == 0 and prim["data"] == data
