class_name AvatarShadeCache
extends RefCounted

## The canopies of a map, collected once so an avatar token's shade ray (AvatarShade) does
## not walk the map on every placement and move. Walking it means every MultiMeshInstance3D
## and MeshInstance3D under the map and, for each tree MultiMesh the ray's box meets, every
## instance transform and its inverse: milliseconds per ray on a scattered map. The cache
## keeps each canopy instance's crown (AvatarShade.crown_of) with its inverse placement and
## its world box, grouped per source node with the group's world box, so a query is a few
## box tests per group the ray passes near.
##
## It answers exactly what AvatarShade.canopy_hit answers for the map as it stood when the
## cache was built (same canopies, same order, same names), so it must be rebuilt when the
## map changes: GameMap drops it on every map load and clear (for_map / clear), and the
## first avatar ray after that builds it again. Figures, being skinned, never count, so
## tokens placed or moved later do not invalidate it.

const WORLD_MARGIN_M := 0.01

## map root instance id -> AvatarShadeCache, one per loaded map (for_map).
static var _by_root: Dictionary = {}

## One entry per canopy source node, in AvatarShade.canopy_hit's order:
## {"bounds": world AABB of its crowns, "crowns": [{"name", "inv", "crown", "world"}]}.
var groups: Array[Dictionary] = []
## Crowns collected (tests and the probe's log).
var crown_count := 0
## How long build took, in milliseconds.
var build_ms := 0.0


## The cache for the map under `root`, built on first use after a clear. While an authored
## map's scatter is still growing or regenerating its plants, a fresh cache is built for
## this ray and not kept, so a token placed early never keeps a half-grown forest.
static func for_map(root: Node) -> AvatarShadeCache:
	var key := root.get_instance_id()
	if _by_root.has(key):
		return _by_root[key]
	var cache := build(root)
	if not _scatter_busy(root):
		_by_root[key] = cache
	return cache


static func _scatter_busy(root: Node) -> bool:
	if not root.is_inside_tree():
		return false
	for node in root.get_tree().get_nodes_in_group(AuthoredScatter.GROUP):
		var scatter := node as AuthoredScatter
		if scatter != null and (scatter.is_growing() or scatter.is_regenerating()):
			return true
	return false


## Drops every map's cache (GameMap calls it when a map loads or is cleared).
static func clear() -> void:
	_by_root.clear()


## Collects the canopies under `root`, as AvatarShade.canopy_hit would find them.
static func build(root: Node) -> AvatarShadeCache:
	var t0 := Time.get_ticks_usec()
	var cache := AvatarShadeCache.new()
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		cache._add_multimesh(node as MultiMeshInstance3D)
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or mi.skin != null or not mi.is_visible_in_tree():
			continue
		var crowns: Array[Dictionary] = []
		_append_crown(crowns, String(mi.name), mi.mesh.get_aabb(), mi.global_transform)
		cache._add_group(crowns)
	cache.build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return cache


func _add_multimesh(mmi: MultiMeshInstance3D) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null or not mmi.is_visible_in_tree():
		return
	var box := mm.mesh.get_aabb()
	if box.size.y < AvatarShade.CANOPY_MIN_HEIGHT * 0.5:
		return
	var xf := mmi.global_transform
	var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	var crowns: Array[Dictionary] = []
	for i in count:
		_append_crown(crowns, "%s #%d" % [mmi.name, i], box, xf * mm.get_instance_transform(i))
	_add_group(crowns)


static func _append_crown(
	crowns: Array[Dictionary], name: String, box: AABB, xf: Transform3D
) -> void:
	if not AvatarShade.counts_as_canopy(box, xf):
		return
	var crown := AvatarShade.crown_of(box)
	# The world box only rejects early; grown a little so a ray grazing the crown, which the
	# exact test in the crown's space may still count, is never rejected by rounding.
	var world := (xf * crown).grow(WORLD_MARGIN_M)
	crowns.append({"name": name, "inv": xf.affine_inverse(), "crown": crown, "world": world})


func _add_group(crowns: Array[Dictionary]) -> void:
	if crowns.is_empty():
		return
	var bounds: AABB = crowns[0].world
	for c in crowns:
		bounds = bounds.merge(c.world)
	groups.append({"bounds": bounds, "crowns": crowns})
	crown_count += crowns.size()


## The canopy the segment meets ("" when none), named as AvatarShade.canopy_hit names it.
func canopy_hit(from: Vector3, to: Vector3) -> String:
	for group in groups:
		if (group.bounds as AABB).intersects_segment(from, to) == null:
			continue
		for c in group.crowns:
			if (c.world as AABB).intersects_segment(from, to) == null:
				continue
			var inv: Transform3D = c.inv
			if (c.crown as AABB).intersects_segment(inv * from, inv * to) != null:
				return c.name
	return ""
