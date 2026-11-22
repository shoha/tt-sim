extends GutTest

## StructureGeometry.with_ledges: a narrow level face carries its width in UV2.y for the painted
## snow law, a wide or upright one 0, and every surface gets UV2 (one layout for a building).


## A quad of two triangles from `a` along `u` and `v`.
func _quad(a: Vector3, u: Vector3, v: Vector3, into: Dictionary) -> void:
	var vertices: PackedVector3Array = into.vertices
	var indices: PackedInt32Array = into.indices
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, a + u, a + u + v, a + v]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	into.vertices = vertices
	into.indices = indices


func _arrays(into: Dictionary) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = into.vertices
	arrays[Mesh.ARRAY_INDEX] = into.indices
	return arrays


func test_a_batten_top_carries_its_width_and_a_sill_none() -> void:
	var into := {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	# A 5 cm batten top, 0.45 m long, and a 19 cm sill, 1 m long.
	_quad(Vector3.ZERO, Vector3(0.45, 0.0, 0.0), Vector3(0.0, 0.0, 0.05), into)
	_quad(Vector3(0.0, 1.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.19), into)
	# The batten's upright front: no width.
	_quad(Vector3(0.0, 2.0, 0.0), Vector3(0.45, 0.0, 0.0), Vector3(0.0, 0.05, 0.0), into)
	var w := StructureGeometry.ledge_widths(into.vertices, into.indices)
	for v in 4:
		assert_almost_eq(w[v], 0.05, 0.0001, "batten top vertex %d" % v)
		assert_almost_eq(w[4 + v], 0.19, 0.0001, "sill vertex %d" % v)
		assert_eq(w[8 + v], 0.0, "upright vertex %d" % v)


func test_either_winding_is_level() -> void:
	var into := {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	_quad(Vector3.ZERO, Vector3(0.0, 0.0, 0.06), Vector3(0.4, 0.0, 0.0), into)
	var w := StructureGeometry.ledge_widths(into.vertices, into.indices)
	assert_almost_eq(w[0], 0.06, 0.0001)


func test_a_wide_face_and_its_sliver_stay_wide() -> void:
	var into := {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	_quad(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), into)
	var vertices: PackedVector3Array = into.vertices
	var indices: PackedInt32Array = into.indices
	# A sliver sharing two of the wide face's vertices.
	vertices.append(Vector3(1.003, 0.0, 0.004))
	indices.append_array(PackedInt32Array([1, 4, 2]))
	var w := StructureGeometry.ledge_widths(vertices, indices)
	assert_eq(w[1], 0.0, "the wide face's vertex keeps 0")
	assert_eq(w[2], 0.0)


func test_with_ledges_keeps_uv2_x_and_gives_every_surface_uv2() -> void:
	var narrow := {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	_quad(Vector3.ZERO, Vector3(0.45, 0.0, 0.0), Vector3(0.0, 0.0, 0.05), narrow)
	var arrays := _arrays(narrow)
	arrays[Mesh.ARRAY_TEX_UV2] = PackedVector2Array(
		[Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.0)]
	)
	StructureGeometry.with_ledges(arrays)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(uv2[0].x, 1.0, "the house flag stays")
	assert_almost_eq(uv2[0].y, 0.05, 0.0001)
	var wide := {"vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	_quad(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 0.5), wide)
	var plain := _arrays(wide)
	StructureGeometry.with_ledges(plain)
	assert_eq(plain[Mesh.ARRAY_TEX_UV2], PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
