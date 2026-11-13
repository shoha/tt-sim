extends GutTest

## The manner probe behind PainterBuildings.manner_mode (card painter-manner; docs/systems/
## painter.md "Buildings", "Manner probe"): off by default and then nothing changes; the mesh build
## is deterministic, cuts only what wanders, keeps the recipe topology for the shadow and adds a
## thatch eave's teeth; an installed candidate is put back exactly.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}

var _container: Node3D = null


func before_each() -> void:
	PainterSheet.clear_cache()
	_container = Node3D.new()
	add_child_autofree(_container)


## A 4 x 2 m thatch roof slope record over the quad `_quad()` makes (map frame).
func _roof() -> Dictionary:
	return {
		"id": "roof/slope0",
		"kind": "roof_slope",
		"material": "thatch",
		"origin": Vector3(0, 2, 0),
		"u": Vector3.RIGHT,
		"v": Vector3(0, 0.6, -0.8),
		"n": Vector3(0, 0.8, 0.6),
		"down": Vector3(0, -0.6, 0.8),
		"u_len": 4.0,
		"v_len": 2.0,
		"fringe": 0.2,
		"accent": 0.3,
		"edges":
		[
			{"a": Vector3(0, 2, 0), "b": Vector3(4, 2, 0), "kind": "eave"},
			{"a": Vector3(0, 3.2, -1.6), "b": Vector3(4, 3.2, -1.6), "kind": "ridge"}
		]
	}


func _quad() -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(0, 2, 0), Vector3(4, 2, 0), Vector3(4, 3.2, -1.6), Vector3(0, 3.2, -1.6)]
	)
	var n := Vector3(0, 0.8, 0.6)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([n, n, n, n])
	var eave := Color(0.6, 0.5, 0.3, 0)
	var ridge := Color(0.6, 0.5, 0.3, 1)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([eave, eave, ridge, ridge])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	return arrays


func _opts() -> Dictionary:
	return {"amp": 0.14, "phase": PainterMannerMesh.phase_of(56), "foot": 0.0, "eave": 2.0}


func _build() -> Dictionary:
	var table := PackedStringArray(["roof/slope0"])
	return PainterMannerMesh.build(
		_quad(), PackedInt32Array([0, 0, 0, 0]), table, {"roof/slope0": _roof()}, _opts()
	)


func test_the_switch_is_off_by_default_and_then_no_mesh_changes() -> void:
	assert_eq(PainterBuildings.manner_mode, "", "A3b is the default")
	StructureRecipes.ensure_served()
	var map := Node3D.new()
	map.name = "LevelMap"
	_container.add_child(map)
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var plan := PackedVector2Array(
		[Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)]
	)
	doc.structures.append(Structure.make(1, "core:thatched_cottage", plan, 5))
	var structures := AuthoredStructures.create(doc)
	map.add_child(structures)
	var before := {}
	for node: Node in structures.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		before[node] = [mi.mesh, mi.cast_shadow, node.get_child_count()]
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(map, STATE))
	assert_null(buildings.manner, "no manner host while the switch is off")
	for node: MeshInstance3D in before:
		assert_eq(node.mesh, before[node][0], "%s keeps its mesh" % node.name)
		assert_eq(node.cast_shadow, before[node][1])
		assert_eq(node.get_child_count(), before[node][2])
	buildings.release()


func test_the_mesh_build_is_deterministic_cut_and_keeps_the_shadow_topology() -> void:
	var a := _build()
	var b := _build()
	assert_eq(a.draw[Mesh.ARRAY_VERTEX], b.draw[Mesh.ARRAY_VERTEX], "same inputs, same vertices")
	assert_eq(a.draw[Mesh.ARRAY_INDEX], b.draw[Mesh.ARRAY_INDEX])
	assert_eq(a.draw[Mesh.ARRAY_CUSTOM0], b.draw[Mesh.ARRAY_CUSTOM0])
	var tris: Array = a.triangles
	assert_eq(int(tris[0]), 2)
	assert_gt(int(tris[1]), 8, "a 4 m slope is cut every metre along the eave, plus its teeth")
	assert_eq(int(tris[2]), 2, "the shadow keeps the recipe's triangles")
	assert_eq(a.shadow[Mesh.ARRAY_INDEX], _quad()[Mesh.ARRAY_INDEX])
	var custom: PackedFloat32Array = a.draw[Mesh.ARRAY_CUSTOM0]
	var teeth := 0
	for k in range(2, custom.size(), 4):
		teeth += int(custom[k] == float(PainterMannerMesh.CODE_FRINGE))
	assert_between(teeth, 19 * 3, 20 * 3, "about twenty teeth along the 4 m eave")


func test_the_wander_keeps_the_foot_and_is_a_function_of_the_point() -> void:
	var opts := _opts()
	assert_eq(PainterMannerMesh.wander_at(Vector3(3, 0, 2), opts), Vector3.ZERO, "the foot stays")
	var p := Vector3(1.5, 4.0, -2.0)
	assert_eq(PainterMannerMesh.wander_at(p, opts), PainterMannerMesh.wander_at(p, opts))
	assert_lt(PainterMannerMesh.wander_at(p, opts).length(), 0.14 * 2.5)


func test_an_installed_candidate_is_put_back_exactly() -> void:
	var structure := Node3D.new()
	structure.name = "Structure_1"
	_container.add_child(structure)
	var mi := MeshInstance3D.new()
	mi.name = "roof_thatch"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad())
	mi.mesh = mesh
	structure.add_child(mi)
	var buildings := PainterBuildings.new()
	var host := PainterMannerHost.new(buildings)
	var job := {"node": structure.get_instance_id(), "generation": 0, "key": -1, "mode": "b"}
	host._install({"job": job, "parts": {"roof_thatch": _build()}, "eval_ms": 0.0, "image": null})
	assert_ne(mi.mesh, mesh, "the wandered shadow mesh is in")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(mi.get_child_count(), 1, "the drawn mesh is a child")
	assert_eq(host.stats.size(), 1)
	host.restore_all()
	assert_eq(mi.mesh, mesh, "the very same mesh is back")
	assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(mi.get_child_count(), 0, "what it added is gone")
