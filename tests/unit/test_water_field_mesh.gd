extends GutTest

## WaterFieldMesh (utils/water_field_mesh.gd): the one painted water surface as mesh arrays, a pure
## function of the WaterField. The canonical fixture is the same document test_water_field.gd uses.

const FIXTURE := "res://tests/fixtures/water_field_canonical.ttmap"

var _doc: MapDocument = null
var _field: WaterField = null


func before_all() -> void:
	_doc = MapDocumentIO.read(FIXTURE).get("document")
	_field = WaterField.build(_doc)


func test_counts_are_consistent() -> void:
	var built := WaterFieldMesh.build(_field)
	assert_gt(built["vertices"], 0, "the canonical map has water")
	var arrays: Array = built["arrays"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), built["vertices"])
	assert_eq(indices.size(), built["triangles"] * 3)
	assert_eq(indices.size() % 3, 0)
	for i in indices:
		assert_true(i >= 0 and i < verts.size(), "every index names a vertex")


func test_vertices_are_shared() -> void:
	var built := WaterFieldMesh.build(_field)
	# A shared-vertex grid has about half as many vertices as triangles; unshared would be 3x.
	assert_lt(built["vertices"], built["triangles"], "vertices are indexed, not duplicated")


func test_custom_arrays_match_vertices() -> void:
	var built := WaterFieldMesh.build(_field)
	var arrays: Array = built["arrays"]
	var c0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var c1: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	assert_eq(c0.size(), built["vertices"] * 4)
	assert_eq(c1.size(), built["vertices"] * 4)
	for v in built["vertices"]:
		assert_eq(c1[v * 4 + 1], WaterFieldMesh.FIELD_FLAG, "every vertex carries the field flag")


func test_build_is_deterministic() -> void:
	var a := WaterFieldMesh.build(_field)
	var b := WaterFieldMesh.build(WaterField.build(_doc))
	assert_eq(a["vertices"], b["vertices"])
	assert_eq(a["triangles"], b["triangles"])
	assert_eq(a["arrays"][Mesh.ARRAY_INDEX], b["arrays"][Mesh.ARRAY_INDEX])
	assert_eq(a["arrays"][Mesh.ARRAY_CUSTOM0], b["arrays"][Mesh.ARRAY_CUSTOM0])


func test_dirty_rect_update_equals_rebuild() -> void:
	var f := WaterField.build(_doc)
	f.update(_doc, Rect2(-12.0, -12.0, 8.0, 8.0))
	var a := WaterFieldMesh.build(f)
	var b := WaterFieldMesh.build(WaterField.build(_doc))
	assert_eq(a["vertices"], b["vertices"])
	assert_eq(a["arrays"][Mesh.ARRAY_VERTEX], b["arrays"][Mesh.ARRAY_VERTEX])
	assert_eq(a["arrays"][Mesh.ARRAY_CUSTOM0], b["arrays"][Mesh.ARRAY_CUSTOM0])
	assert_eq(a["arrays"][Mesh.ARRAY_INDEX], b["arrays"][Mesh.ARRAY_INDEX])


func test_to_mesh_has_one_surface() -> void:
	var mesh := WaterFieldMesh.to_mesh(WaterFieldMesh.build(_field), ShaderMaterial.new())
	assert_not_null(mesh)
	assert_eq(mesh.get_surface_count(), 1)


func test_empty_field_gives_null_mesh() -> void:
	var empty := WaterFieldMesh.to_mesh({"arrays": []}, null)
	assert_null(empty)
