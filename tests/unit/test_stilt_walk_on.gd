extends GutTest

## A token walks onto a stilt house's deck and its stair, and off again (check G1, 2026-10-31). The
## structure's walk-on collision (StructureWalkable, docs/systems/structures.md "Collision") is the
## only thing that holds a token up there, so this builds a real stilt house over a ground slab and
## asks a real avatar token where it would rest (TokenGrounding.resting_position, the drop's own
## landing) at spots along the stair, on the deck and beside the house.

const STILT := "core:stilt_house"
const CAST_TOP := 60.0
const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}

var _old_scene: Node = null
var _scene: Node3D = null
var _doc: MapDocument = null
var _parts: Dictionary = {}
var _token: BoardToken = null


func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node3D.new()
	_scene.name = "StiltWalkTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	var ground := StaticBody3D.new()
	ground.collision_layer = WaterSurface.TERRAIN_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	ground.add_child(shape)
	_scene.add_child(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	var plan := PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])
	_doc.structures.append(Structure.make(1, STILT, plan, 5))
	_parts = StructureGeometry.build_one(_doc, _doc.structures[0])
	_scene.add_child(AuthoredStructures.create(_doc))
	_token = AvatarTokenFactory.create(RECIPE, "Scout")
	_scene.add_child(_token)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


## Centroids of the upward triangles of the build whose tag path ends with `suffix`.
func _tops(suffix: String, up_only: bool = true) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var table: PackedStringArray = _parts.tag_table
	for mesh: Dictionary in _parts.meshes:
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh.arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = mesh.arrays[Mesh.ARRAY_INDEX]
		var tags: PackedInt32Array = mesh.tags
		for t in indices.size() / 3:
			var a := indices[t * 3]
			if (
				tags[a] < 0
				or not table[tags[a]].ends_with(suffix)
				or (up_only and normals[a].y < 0.9)
			):
				continue
			out.append(
				(vertices[a] + vertices[indices[t * 3 + 1]] + vertices[indices[t * 3 + 2]]) / 3.0
			)
	return out


## Where the token would rest, as a height above the ground slab, with the token's feet placed over
## world XZ `xz` at `from_y` (its top is then a body's height above that).
func _rest_height(xz: Vector2, from_y: float) -> float:
	_token.rigid_body.global_position = Vector3(xz.x, from_y, xz.y)
	var rest := TokenGrounding.resting_position(_token, CAST_TOP)
	assert_ne(rest, Vector3.INF, "something is under the token at %s" % str(xz))
	return rest.y - _ground_rest()


## The token's resting y on the bare slab (far from the house), the zero of the heights.
func _ground_rest() -> float:
	_token.rigid_body.global_position = Vector3(25.0, 3.0, 25.0)
	var rest := TokenGrounding.resting_position(_token, CAST_TOP)
	assert_ne(rest, Vector3.INF, "the slab holds a token")
	return rest.y


func test_a_token_rests_on_the_deck_at_the_decks_height() -> void:
	var decks := _tops("stilt/deck")
	assert_gt(decks.size(), 0, "the stilt house has a deck")
	var deck: Vector3 = decks[0]
	assert_gt(deck.y, 0.5, "the deck is raised")
	var height := _rest_height(Vector2(deck.x, deck.z), deck.y + 0.02)
	gut.p("deck surface %.3f m, token rests %.3f m above the ground" % [deck.y, height])
	assert_almost_eq(height, deck.y, 0.03, "on the deck, not the ground below")


func test_a_token_climbs_the_stair_tread_by_tread_and_drops_off_its_side() -> void:
	var rises: Array[float] = []
	var first := Vector3.INF
	var seen := 0
	for k in 14:
		for tread in _tops("stilt/stair/tread%d" % k):
			seen += 1
			var height := _rest_height(Vector2(tread.x, tread.z), tread.y + 0.02)
			if first == Vector3.INF:
				first = tread
			assert_almost_eq(
				height, tread.y, 0.03, "tread %d holds the token at its own height" % k
			)
			rises.append(height)
	assert_gt(seen, 2, "the stair has treads")
	var lowest := rises.min() as float
	var highest := rises.max() as float
	assert_gt(highest - lowest, 0.3, "the treads climb (%.2f to %.2f m)" % [lowest, highest])
	# Well clear of the house the token falls back to the ground.
	var away := Vector2(first.x, first.z) + Vector2(0.0, 12.0)
	assert_almost_eq(_rest_height(away, highest + 0.02), 0.0, 0.01, "off the house: the ground")
