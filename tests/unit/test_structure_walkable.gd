extends GutTest

## StructureWalkable: the decks, stair treads, platforms and piles a structure's collision gets on
## top of procgen's wall hull (docs/systems/structures.md "Collision"). The pure helpers are tested
## on hand-made meshes; the integration cases build the core stilt houses and the porch cottage and
## drop a ray (what a token's drop does, WaterSurface.landing_below) onto the deck, a stair tread
## and a pile.

var _map: Node3D = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _plan() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])


func _parts_of(ref: String) -> Dictionary:
	return StructureGeometry.build_one(_doc, Structure.make(1, ref, _plan(), 5))


## A hand-made mesh entry: one triangle per `tags` element, each lying flat facing `up`.
func _mesh(tags: Array[int], up: bool) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var vertex_tags := PackedInt32Array()
	var indices := PackedInt32Array()
	for k in tags.size():
		var y := float(k)
		vertices.append_array(
			PackedVector3Array([Vector3(0, y, 0), Vector3(1, y, 0), Vector3(0, y, 1)])
		)
		for i in 3:
			normals.append(Vector3.UP if up else Vector3.DOWN)
			vertex_tags.append(tags[k])
			indices.append(k * 3 + i)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "tags": vertex_tags}


# --- classification ----------------------------------------------------------------------


func test_deck_stair_slab_porch_balcony_and_gallery_pieces_are_walkable() -> void:
	for path in [
		"stilts/stilt/slab/0",
		"stilts/stilt/slab/3",
		"stilts/stilt/deck",
		"stilts/stilt/stair/tread4",
		"gallery2/porch/deck",
		"gallery2/porch/plinth",
		"gallery/balcony1/deck",
		"gallery/gallery/deck",
	]:
		assert_true(StructureWalkable.is_walkable(path), path)


func test_rails_posts_braces_stringers_rungs_and_hoods_are_not_walkable() -> void:
	for path in [
		"stilts/stilt/deck/post0",
		"stilts/stilt/deck/rail/0/top",
		"stilts/stilt/bearer/0",
		"stilts/stilt/brace/f1/0/0",
		"stilts/stilt/stair/stringer0",
		"stilts/stilt/ladder/rung3",
		"gallery/porch/hood/roof",
		"gallery/balcony0/bracket0",
		"gallery/balcony0/rail/0/top",
		"gallery/gallery/roof",
		"walls/front0",
	]:
		assert_false(StructureWalkable.is_walkable(path), path)


func test_piles_pads_and_caps_block_and_nothing_else_does() -> void:
	for path in ["stilts/stilt/pile/3", "stilts/stilt/pad/3", "stilts/stilt/cap/11"]:
		assert_true(StructureWalkable.is_blocking(path), path)
		assert_false(StructureWalkable.is_walkable(path), path)
	for path in ["stilts/stilt/slab/0", "stilts/stilt/brace/f1/0/0", "walls/front0"]:
		assert_false(StructureWalkable.is_blocking(path), path)


func test_the_node_id_is_dropped_whatever_it_is_called() -> void:
	assert_eq(StructureWalkable.slot_path("stilts3/stilt/deck"), "stilt/deck")
	assert_eq(StructureWalkable.slot_path("deck"), "deck")


# --- faces -------------------------------------------------------------------------------


func test_walkable_pieces_give_their_upward_faces_only() -> void:
	var table := PackedStringArray(["n/stilt/deck", "n/stilt/deck/post0"])
	assert_eq(StructureWalkable.faces([_mesh([0, 1, 0] as Array[int], true)], table).size(), 6)
	assert_eq(
		StructureWalkable.faces([_mesh([0, 1, 0] as Array[int], false)], table).size(),
		0,
		"an underside is not a floor"
	)


func test_blocking_pieces_give_every_face() -> void:
	var table := PackedStringArray(["n/stilt/pile/0", "n/stilt/slab/0"])
	assert_eq(StructureWalkable.faces([_mesh([0, 0] as Array[int], false)], table).size(), 6)
	assert_eq(StructureWalkable.faces([_mesh([1] as Array[int], false)], table).size(), 0)


func test_untagged_and_unlisted_vertices_give_nothing() -> void:
	var table := PackedStringArray(["n/front0"])
	assert_true(StructureWalkable.faces([_mesh([0, -1, 7] as Array[int], true)], table).is_empty())
	assert_true(StructureWalkable.faces([], table).is_empty())


func test_the_same_meshes_give_the_same_faces() -> void:
	var table := PackedStringArray(["n/stilt/deck"])
	var mesh := _mesh([0, 0, 0] as Array[int], true)
	assert_eq(
		StructureWalkable.faces([mesh], table).to_byte_array(),
		StructureWalkable.faces([mesh], table).to_byte_array()
	)


# --- built structures --------------------------------------------------------------------


func test_a_plain_cottage_gets_no_extra_faces_and_a_porch_or_gallery_gets_a_deck() -> void:
	assert_true((_parts_of("core:cottage").walkable as PackedVector3Array).is_empty())
	assert_gt((_parts_of("core:porch_cottage").walkable as PackedVector3Array).size(), 0)
	assert_gt((_parts_of("core:inn_gallery").walkable as PackedVector3Array).size(), 0)


func test_a_stilt_house_has_a_slab_deck_stair_and_piles_in_its_collision() -> void:
	for ref in ["core:stilt_house", "core:lake_dwelling", "core:stabbur"]:
		var parts := _parts_of(ref)
		assert_eq(parts.problem, "", ref)
		var faces: PackedVector3Array = parts.walkable
		assert_gt(faces.size(), 0, ref)
		assert_eq(faces.size() % 3, 0, ref)
		assert_lt(faces.size() / 3, 400, "%s stays cheap" % ref)
		# Reaches from below the raised floor (piles) up to the platform, not into the roof.
		var lo := INF
		var hi := -INF
		for v in faces:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
		assert_lt(lo, (parts.collision as PackedVector3Array)[0].y + 1.0, ref)
		assert_lt(hi, float(parts.top), ref)


func test_walkable_faces_are_built_the_same_twice() -> void:
	var a := _parts_of("core:stilt_house")
	var b := _parts_of("core:stilt_house")
	assert_eq(
		(a.walkable as PackedVector3Array).to_byte_array(),
		(b.walkable as PackedVector3Array).to_byte_array()
	)


## Centroids of the upward triangles of the built meshes whose tag path ends with `suffix`.
func _tops(parts: Dictionary, suffix: String, up_only: bool = true) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var table: PackedStringArray = parts.tag_table
	for mesh: Dictionary in parts.meshes:
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = mesh.arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = mesh.arrays[Mesh.ARRAY_INDEX]
		var tags: PackedInt32Array = mesh.tags
		for t in indices.size() / 3:
			var a := indices[t * 3]
			if tags[a] < 0 or not table[tags[a]].ends_with(suffix) or (up_only and normals[a].y < 0.9):
				continue
			out.append(
				(vertices[a] + vertices[indices[t * 3 + 1]] + vertices[indices[t * 3 + 2]]) / 3.0
			)
	return out


func test_a_ray_lands_on_the_deck_and_a_stair_tread_and_stops_at_a_pile() -> void:
	_doc.structures.append(Structure.make(1, "core:stilt_house", _plan(), 5))
	var parts := StructureGeometry.build_one(_doc, _doc.structures[0])
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	await get_tree().physics_frame
	var space := _map.get_world_3d().direct_space_state
	var decks := _tops(parts, "stilt/deck")
	assert_gt(decks.size(), 0, "the stilt house has a deck")
	var deck: Vector3 = decks[0]
	var landing := WaterSurface.landing_below(space, deck, deck.y + 0.4)
	assert_ne(landing, Vector3.INF, "a token dropped over the deck lands")
	assert_almost_eq(landing.y, deck.y, 0.02, "on the deck, not on the ground below")
	var stair: Array[Vector3] = []
	for k in 12:
		stair.append_array(_tops(parts, "stilt/stair/tread%d" % k))
	assert_gt(stair.size(), 0, "and a stair")
	for tread in stair:
		var on := WaterSurface.landing_below(space, tread, tread.y + 0.15)
		assert_ne(on, Vector3.INF, "a tread holds a token")
		assert_almost_eq(on.y, tread.y, 0.02, "at the tread's own height")
	var piles: Array[Vector3] = []
	for k in 12:
		piles.append_array(_tops(parts, "stilt/pile/%d" % k, false))
	assert_gt(piles.size(), 0, "piles")
	var pile: Vector3 = piles[0]
	var low := Vector3(pile.x, 0.3, pile.z)
	var query := PhysicsRayQueryParameters3D.create(low - Vector3(1.5, 0, 0), low + Vector3(1.5, 0, 0))
	query.collision_mask = WaterSurface.TERRAIN_LAYER
	query.hit_back_faces = true
	assert_false(space.intersect_ray(query).is_empty(), "a ray through a pile's height hits it")
	var skipped := WaterSurface.cast_down(
		space,
		deck,
		deck.y + 0.4,
		WaterSurface.TERRAIN_LAYER,
		AuthoredStructures.exclude_of(_map)
	)
	assert_true(skipped.is_empty(), "the ground tools and the Building tool see through the deck")
