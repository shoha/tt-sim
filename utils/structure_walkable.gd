class_name StructureWalkable
extends RefCounted

## The collision a structure's raised parts add to its wall hull (docs/systems/structures.md
## "Collision"). Procgen's collision is the walls' hull and roof only (the Stilts and Gallery nodes
## "add no collision"), so a token dropped on a stilt house's deck, a lake dwelling's platform or a
## balcony would fall through to the ground. The host adds the missing pieces from the tags every
## vertex already carries (the tag_table: node id, then slot path), with no change to procgen:
##
##  - walkable: the UPWARD faces of the pieces a token can stand on (WALKABLE_RE): the stilt
##    platform's boards, the stilt deck, the stair's treads, a porch's deck and plinth, a balcony's
##    deck, a gallery's deck. Upward faces only, so a token under a deck is not caught by its
##    underside and the cost is a few dozen triangles;
##  - blocking: every face of the piles and their footings and caps (BLOCKING_RE), so a pile is as
##    solid as a wall.
##
## Rails, posts, braces, stringers, rungs and hoods stay visual. Pure: the same meshes give the same
## faces on a worker, in a test and on another peer. The faces ride in the structure's own
## `Collision` body (AuthoredStructures), so the ground tools and the Building tool skip them as
## they skip the walls.

## A slot path (after the node id) of a piece a token can stand on.
const WALKABLE_PATTERN := (
	"^(stilt/(slab/\\d+|deck|stair/tread\\d+)|porch/(deck|plinth)"
	+ "|balcony\\d+/deck|gallery/deck)$"
)
## A slot path of a piece that blocks like a wall.
const BLOCKING_PATTERN := "^stilt/(pile|pad|cap)/\\d+$"
## A face whose normal points up at least this much (normal.y over its length) counts as a top.
const UP_MIN := 0.5

static var _walkable_re: RegEx = null
static var _blocking_re: RegEx = null


## The path with its leading node id dropped ("stilts/stilt/deck" -> "stilt/deck").
static func slot_path(tag_path: String) -> String:
	var at := tag_path.find("/")
	return tag_path.substr(at + 1) if at >= 0 else tag_path


## True when the tag path (node id first) names a piece a token can stand on.
static func is_walkable(tag_path: String) -> bool:
	return _matches(_walkable(), slot_path(tag_path))


## True when the tag path names a pile, footing or cap.
static func is_blocking(tag_path: String) -> bool:
	return _matches(_blocking(), slot_path(tag_path))


## The extra collision faces (a triangle list, three vertices each, map frame) of `meshes`
## (StructureGeometry's mesh entries: "arrays" and per vertex "tags") under `tag_table`.
static func faces(meshes: Array, tag_table: PackedStringArray) -> PackedVector3Array:
	var kinds := PackedByteArray()
	kinds.resize(tag_table.size())
	for k in tag_table.size():
		kinds[k] = 1 if is_walkable(tag_table[k]) else (2 if is_blocking(tag_table[k]) else 0)
	var out := PackedVector3Array()
	for mesh: Dictionary in meshes:
		out.append_array(_mesh_faces(mesh, kinds))
	return out


static func _mesh_faces(mesh: Dictionary, kinds: PackedByteArray) -> PackedVector3Array:
	var out := PackedVector3Array()
	var arrays: Array = mesh.get("arrays", [])
	var tags: PackedInt32Array = mesh.get("tags", PackedInt32Array())
	if arrays.size() <= Mesh.ARRAY_INDEX or arrays[Mesh.ARRAY_VERTEX] == null:
		return out
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var raw: Variant = arrays[Mesh.ARRAY_INDEX]
	var indices: PackedInt32Array = raw if raw is PackedInt32Array else PackedInt32Array()
	for t in indices.size() / 3:
		var a := indices[t * 3]
		var tag := tags[a] if a < tags.size() else -1
		var kind := kinds[tag] if tag >= 0 and tag < kinds.size() else 0
		if kind == 0:
			continue
		if kind == 1 and not (a < normals.size() and faces_up(normals[a])):
			continue
		out.append(vertices[a])
		out.append(vertices[indices[t * 3 + 1]])
		out.append(vertices[indices[t * 3 + 2]])
	return out


## True when a (unit) surface normal points up.
static func faces_up(normal: Vector3) -> bool:
	return normal.y >= UP_MIN


static func _matches(re: RegEx, text: String) -> bool:
	return re.search(text) != null


static func _walkable() -> RegEx:
	if _walkable_re == null:
		_walkable_re = RegEx.create_from_string(WALKABLE_PATTERN)
	return _walkable_re


static func _blocking() -> RegEx:
	if _blocking_re == null:
		_blocking_re = RegEx.create_from_string(BLOCKING_PATTERN)
	return _blocking_re
