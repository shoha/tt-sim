extends GutTest

## StructureLoadInfo (staged_load2): the decor library info, the plant plans and the keys a loader's
## worker hands AuthoredStructures.create equal what create made itself on the main thread.

const KINDS: Array = ["ivy", "flower_boxes", "banner", "vane"]
const REFS: Array = [
	"core:cottage", "core:townhouse_trimmed", "core:castle_keep", "core:tudor_townhouse"
]

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()
	for k in 6:
		var at := Vector2((float(k % 3) - 1.0) * 10.0, (float(k / 3) - 0.5) * 12.0)
		var plan := PackedVector2Array(
			[at + Vector2(-3, -2), at + Vector2(3, -2), at + Vector2(3, 2), at + Vector2(-3, 2)]
		)
		var params := StructureOrnaments.with_kinds({}, KINDS)
		_doc.structures.append(Structure.make(k + 1, REFS[k % REFS.size()], plan, 5 + k, params))


func test_the_info_equals_the_one_made_through_the_dressed_meshes() -> void:
	var holder := AuthoredStructures.new()
	var info := StructureLoadInfo.info_of(PaletteLibrary.DEFAULT_ROOT)
	assert_false((info.rows as Array).is_empty(), "the core library serves decor")
	for row: Dictionary in info.rows:
		var tris := int(holder._decor_entry(row).get("tris", 0))
		assert_eq(
			info.cost[row.id],
			tris,
			"%s: the source mesh and its dressed copy cost the same" % row.id
		)
		assert_eq(info.by_id[row.id], row)
	assert_eq(info.sig, hash([info.rows, info.cost]))
	holder.free()


func test_prepared_parts_keys_and_plans_equal_a_create_that_made_them_itself() -> void:
	var decor := StructureDecor.available()
	var prepared := StructureLoadInfo.prepare(_doc, PaletteLibrary.DEFAULT_ROOT, true)
	assert_eq(prepared.keys, StructureGeometry.keys_of(_doc, decor), "the worker's keys")
	assert_true(prepared.has("info"))
	var planned := 0
	for k in _doc.structures.size():
		var parts: Dictionary = prepared.structures[k]
		if (parts.anchors as Array).is_empty():
			continue
		planned += 1
		assert_true(parts.has("decor_plan"), "structure %d is planned on the worker" % (k + 1))
		assert_eq(parts.decor_plan.sig, prepared.info.sig)
	assert_gt(planned, 0, "some structure has plants")
	var from_worker := AuthoredStructures.create(_doc, prepared)
	var alone := AuthoredStructures.create(_doc, StructureGeometry.build(_doc, true, decor))
	assert_eq(from_worker.keys(), alone.keys(), "keys")
	assert_eq(from_worker.get_child_count(), alone.get_child_count(), "nodes")
	for k in _doc.structures.size():
		var id: int = _doc.structures[k].id
		assert_eq(
			_decor_shape(from_worker, id), _decor_shape(alone, id), "structure %d plants" % id
		)
	from_worker.free()
	alone.free()


func test_a_staged_create_from_prepared_parts_makes_the_same_nodes() -> void:
	var prepared := StructureLoadInfo.prepare(_doc, PaletteLibrary.DEFAULT_ROOT, true)
	var nodes := AuthoredStructures.create(_doc, prepared, PaletteLibrary.DEFAULT_ROOT, true)
	assert_eq(nodes.pending_count(), _doc.structures.size())
	assert_eq(nodes.flush(), _doc.structures.size())
	assert_eq(nodes.keys(), StructureGeometry.keys_of(_doc, StructureDecor.available()))
	nodes.free()


func test_a_prepare_without_info_leaves_the_library_to_create() -> void:
	var prepared := StructureLoadInfo.prepare(_doc, PaletteLibrary.DEFAULT_ROOT, false)
	assert_false(prepared.has("info"))
	assert_eq(prepared.keys, StructureGeometry.keys_of(_doc, StructureDecor.available()))
	for parts: Dictionary in prepared.structures:
		assert_false(parts.has("decor_plan"), "no plan without the library info")
	var nodes := AuthoredStructures.create(_doc, prepared)
	for parts: Dictionary in prepared.structures:
		if not (parts.anchors as Array).is_empty():
			assert_true(parts.has("decor_plan"), "create plans them")
	nodes.free()


func test_info_for_takes_the_workers_only_while_it_matches_the_library() -> void:
	var root := PaletteLibrary.DEFAULT_ROOT
	var prepared := StructureLoadInfo.prepare(_doc, root, true)
	assert_same(StructureLoadInfo.info_for(prepared, root), prepared.info, "reused")
	var other := prepared.duplicate()
	other["root"] = "elsewhere"
	assert_not_same(
		StructureLoadInfo.info_for(other, root), prepared.info, "another palette: read again"
	)
	var stale := prepared.duplicate()
	var changed: Dictionary = (prepared.info as Dictionary).duplicate()
	changed["rows"] = [] as Array[Dictionary]
	stale["info"] = changed
	assert_eq(
		StructureLoadInfo.info_for(stale, root).sig, prepared.info.sig, "stale rows: read again"
	)
	assert_eq(StructureLoadInfo.info_for({}, root).sig, prepared.info.sig, "nothing held")


func test_keys_for_takes_the_workers_only_for_the_same_structures() -> void:
	var decor := StructureDecor.available()
	var keys := StructureGeometry.keys_of(_doc, decor)
	assert_eq(StructureLoadInfo.keys_for(_doc, {"keys": keys}, decor), keys)
	var wrong := {"keys": {99: 1}}
	assert_eq(StructureLoadInfo.keys_for(_doc, wrong, decor), keys, "another set: computed here")
	assert_eq(StructureLoadInfo.keys_for(_doc, {}, decor), keys)


func test_the_loaders_worker_hands_over_keys_and_where_it_may_the_library_info() -> void:
	var merged := AuthoredLoadPrep.start(_doc).finish()
	var built: Dictionary = merged[AuthoredLoadPrep.STRUCTURES]
	assert_eq(built.keys, StructureGeometry.keys_of(_doc, StructureDecor.available()))
	assert_eq(
		built.has("info"), GlbUtils.threaded_loads_safe(), "the info comes where GLBs read safely"
	)
	var direct := AuthoredLoadPrep.compute(_doc)[AuthoredLoadPrep.STRUCTURES] as Dictionary
	assert_true(direct.has("info"), "the calling thread always reads it")
	for k in _doc.structures.size():
		assert_eq(
			StructureGeometry.digest_of(built.structures[k]),
			StructureGeometry.digest_of(direct.structures[k]),
			"structure %d" % (k + 1)
		)


## The baked plant vertices of structure `id`'s node, per surface ([] without plants).
func _decor_shape(nodes: AuthoredStructures, id: int) -> Array:
	var baked := (
		nodes.get_structure_node(id).get_node_or_null(AuthoredStructures.DECOR_NODE)
		as MeshInstance3D
	)
	var out: Array = []
	if baked != null:
		for s in baked.mesh.get_surface_count():
			out.append(baked.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out
