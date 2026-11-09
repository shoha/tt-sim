class_name FoliageBudget
extends RefCounted

## Two pure helpers of the scatter pipeline: the triangle count of one instance of a mesh, and
## the deterministic shuffled order a chunk's instances are written in. Pure statics only -- no
## node access and no side effects, so both are unit-testable without a scene tree or a renderer.
##
## History: this class used to hold the player's foliage primitive budget (PRIMITIVE_BUDGET, 8M
## triangles, a Settings slider from 2M to 24M) and the allocator that thinned each species to
## it. The performance audit of 2026-11 found that the budget counted triangles, which are not
## what foliage costs (a lit ground-cover card is a fragment cost; halving every class's
## triangles saved 0.06 ms), and that it never engaged on a reference map (the largest has 7.05M
## against 8M). It was replaced by zoom-keyed thinning of ground cover only
## (FoliageDensityController, docs/PERFORMANCE.md "Zoom-keyed ground thinning"); the name stays
## because the shuffled order is the same ordering that thinning draws a prefix of.

# FNV-1a 32-bit parameters. GDScript ints are 64-bit, so every step masks back to 32.
const _FNV_OFFSET_BASIS: int = 0x811c9dc5
const _FNV_PRIME: int = 16777619
const _UINT32_MASK: int = 0xffffffff

## Triangles in one instance of `mesh`, summed over its triangle surfaces.
##
## Two paths because the cheap one does not exist on every Mesh: surface_get_array_*()
## and surface_get_primitive_type() are ArrayMesh methods, and calling them on a
## PrimitiveMesh fails outright. Imported glTF meshes are ArrayMesh, where reading the
## index length avoids copying any vertex data; BoxMesh and friends fall back to
## get_faces(), which materialises the whole face array but only ever runs on small
## fixtures. A mesh whose primitive count cannot be determined counts as 0.
static func primitives_per_instance(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return mesh.get_faces().size() / 3
	var total := 0
	for surface in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var index_length := array_mesh.surface_get_array_index_len(surface)
		if index_length > 0:
			total += index_length / 3
		else:
			total += array_mesh.surface_get_array_len(surface) / 3
	return total


## A deterministic shuffled ordering of `count` instance indices.
##
## This IS the order instances are written into a chunk's MultiMesh, which makes any
## PREFIX of it a spatially even sample of that chunk -- the property
## MultiMesh.visible_instance_count depends on to act as a density dial. Ordering them by
## position instead would make a prefix carve a bald patch out of one side of the cell.
##
## Deterministic by construction: the seed comes only from `seed_source`, never from time
## or engine RNG state, so a map looks the same across loads on one machine and instances
## appear and disappear predictably as the thinning moves rather than reshuffling.
##
## WARNING: changing the seeding or the shuffle changes which instances a user sees under any
## thinning, in every map. A Godot RNG change on an engine upgrade has exactly the same effect as
## a deliberate edit here; test_shuffled_order_pins_the_current_algorithm is what catches either
## case.
static func shuffled_order(count: int, seed_source: String) -> PackedInt32Array:
	if count <= 0:
		return PackedInt32Array()
	var order := PackedInt32Array()
	order.resize(count)
	for i in count:
		order[i] = i
	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_hash(seed_source)
	# Full Fisher-Yates: every slot is settled, because any prefix length may be drawn.
	for i in count - 1:
		var j := rng.randi_range(i, count - 1)
		var swapped := order[i]
		order[i] = order[j]
		order[j] = swapped
	return order


## FNV-1a over `text`'s UTF-8 bytes. Deliberately not Godot's built-in hash(): this value
## decides which instances survive a thinning in every imported map, so it has to stay identical
## across engine versions and platforms, and hash() is an engine implementation detail
## under no such guarantee.
static func _stable_hash(text: String) -> int:
	var hash_value := _FNV_OFFSET_BASIS
	for byte in text.to_utf8_buffer():
		hash_value = (hash_value ^ byte) & _UINT32_MASK
		hash_value = (hash_value * _FNV_PRIME) & _UINT32_MASK
	return hash_value
