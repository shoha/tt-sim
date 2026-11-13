extends GutTest

## The hand-drawn manner (PainterBuildings.hand_drawn; docs/systems/painter.md "Buildings"):
## switched off nothing changes; build_one records procgen's manner data in its own evaluation
## without changing the parts (card painter-manner-c); the mesh build is deterministic, cuts only
## what wanders, keeps the recipe topology for the shadow and adds a thatch eave's teeth; an
## install is put back exactly.

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


func test_the_manner_is_the_default_and_switched_off_no_mesh_changes() -> void:
	assert_true(PainterBuildings.hand_drawn, "the hand-drawn manner is the Painted default")
	PainterBuildings.hand_drawn = false
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
	PainterBuildings.hand_drawn = true


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


## The parts build_one makes, minus what the records may change (the tags) and the records.
func _comparable(parts: Dictionary) -> Dictionary:
	var meshes: Array = []
	for mesh: Dictionary in parts.meshes:
		meshes.append([mesh.role, mesh.kind, mesh.arrays])
	var mill: Dictionary = parts.get("mill", {})
	return {
		"digest": StructureGeometry.digest_of(parts),
		"meshes": meshes,
		"walkable": parts.walkable,
		"collision": parts.collision,
		"top": parts.top,
		"mill": mill.keys(),
		"glow": (parts.glow as Array).size()
	}


func test_build_one_records_in_one_pass_and_changes_nothing_else() -> void:
	# card painter-manner-c: the records come from build_one's own evaluation while the painted
	# manner is on; roles, walkable faces, cloth, mills and the mesh read the node ids only.
	StructureRecipes.ensure_served()
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var plan := PackedVector2Array(
		[Vector2(-3.5, -2.5), Vector2(3.5, -2.5), Vector2(3.5, 2.5), Vector2(-3.5, 2.5)]
	)
	var recipes := [
		"core:thatched_cottage",
		"core:half_timber_house",
		"core:house_hip",
		"core:house_flat",
		"core:inn_gallery",
		"core:dormered_house",
		"core:windmill_dutch",
		"core:market_hall"
	]
	assert_false(StructureGeometry.manner_records, "off unless the painted manner is on")
	for k in recipes.size():
		var structure := Structure.make(k + 1, recipes[k], plan, 11 + k)
		var off := StructureGeometry.build_one(doc, structure)
		StructureGeometry.manner_records = true
		var on := StructureGeometry.build_one(doc, structure)
		StructureGeometry.manner_records = false
		assert_eq(str(off.get("problem", "")), "", "%s builds" % recipes[k])
		assert_false(off.has("manner"), "no records while off")
		assert_eq(_comparable(on), _comparable(off), "%s: the same parts" % recipes[k])
		var feed := PainterMannerSource.of_parts(on)
		assert_false(feed.is_empty(), "%s: records with the parts" % recipes[k])
		if not feed.is_empty():
			assert_false((feed.building as Dictionary).is_empty(), "the building record")


func test_the_wander_keeps_the_foot_and_is_a_function_of_the_point() -> void:
	var opts := _opts()
	assert_eq(PainterMannerMesh.wander_at(Vector3(3, 0, 2), opts), Vector3.ZERO, "the foot stays")
	var p := Vector3(1.5, 4.0, -2.0)
	assert_eq(PainterMannerMesh.wander_at(p, opts), PainterMannerMesh.wander_at(p, opts))
	assert_lt(PainterMannerMesh.wander_at(p, opts).length(), 0.14 * 2.5)


func _part(structure: Node3D, part_name: String, cast: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad())
	mi.mesh = mesh
	mi.cast_shadow = cast
	structure.add_child(mi)
	return mi


func test_an_install_draws_in_place_casts_only_what_cast_and_is_put_back_exactly() -> void:
	var structure := Node3D.new()
	structure.name = "Structure_1"
	_container.add_child(structure)
	var roof := _part(structure, "roof_thatch", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	var shutter := _part(structure, "opening_wood", GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var override := ShaderMaterial.new()
	roof.material_override = override
	var meshes := {roof: roof.mesh, shutter: shutter.mesh}
	var faces := PackedVector3Array(_quad()[Mesh.ARRAY_VERTEX]).slice(0, 3)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "Collision"
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	body.add_child(cs)
	structure.add_child(body)
	var host := PainterMannerHost.new(PainterBuildings.new())
	var job := {
		"node": structure.get_instance_id(), "generation": 0, "key": -1, "faces": faces
	}
	var moved := PainterMannerMesh.collider(faces, _opts())
	host._install(
		{
			"job": job,
			"parts": {"roof_thatch": _build(), "opening_wood": _build()},
			"eval_ms": 0.0,
			"collider": moved
		}
	)
	assert_eq(cs.shape, shape, "the collider waits for its own frame")
	host._install_collider({"job": job, "collider": moved})
	for mi: MeshInstance3D in [roof, shutter]:
		assert_ne(mi.mesh, meshes[mi], "%s draws the cut mesh" % mi.name)
		assert_eq(mi.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_true((mi.material_override as ShaderMaterial).has_meta(PainterBuildings.META))
	assert_eq(roof.get_child_count(), 1, "a part that cast keeps casting, from a child")
	var caster := roof.get_child(0) as MeshInstance3D
	assert_eq(caster.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(caster.mesh.surface_get_array_len(0), 4, "the shadow keeps the recipe's vertices")
	assert_eq(shutter.get_child_count(), 0, "a shutter cast no shadow in Classic and casts none")
	assert_ne(cs.shape, shape, "the collider follows the drawn house")
	assert_eq((cs.shape as ConcavePolygonShape3D).get_faces(), moved)
	assert_eq(host.stats.size(), 1)
	assert_eq(int(host.stats[0].tris.shadow), 2, "only the roof's two triangles cast")
	host.restore_all()
	for mi: MeshInstance3D in [roof, shutter]:
		assert_eq(mi.mesh, meshes[mi], "the very same mesh is back on %s" % mi.name)
		assert_eq(mi.get_child_count(), 0, "what it added is gone")
	assert_eq(roof.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	assert_eq(shutter.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(roof.material_override, override, "the override it had is back")
	assert_null(shutter.material_override)
	assert_eq(cs.shape, shape, "the very same shape is back")


func test_the_manner_shader_loads_with_the_sheet_uniforms() -> void:
	var shader := load(PainterMannerHost.SHADER) as Shader
	assert_not_null(shader)
	var names := []
	for u: Dictionary in shader.get_shader_uniform_list():
		names.append(u["name"])
	for want in ["pattern", "pick", "ramps", "tone_lo", "tone_hi", "snow", "snow_ramp"]:
		assert_has(names, want)


func test_the_collider_follows_the_field_and_is_cut_only_above_the_walls() -> void:
	var opts := {"amp": 0.14, "phase": PainterMannerMesh.phase_of(56), "foot": 0.0, "eave": 3.0}
	var wall := PackedVector3Array([Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(6, 3, 0)])
	var roof := PackedVector3Array([Vector3(0, 3, 0), Vector3(6, 3, 0), Vector3(6, 4.5, -2)])
	var moved_wall := PainterMannerMesh.collider(wall, opts)
	assert_eq(moved_wall.size(), 3, "a wall triangle stays whole, as the drawn wall")
	for k in 3:
		assert_eq(moved_wall[k], wall[k] + PainterMannerMesh.wander_at(wall[k], opts))
	var moved_roof := PainterMannerMesh.collider(roof, opts)
	assert_gt(moved_roof.size(), 3 * 6, "a 6 m roof triangle is cut every metre in plan")
	assert_eq(PainterMannerMesh.collider(roof, opts), moved_roof, "pure")


func test_a_beam_is_brushed_wider_and_a_door_leans() -> void:
	var beam := {
		"id": "frame/beam0",
		"kind": "beam",
		"origin": Vector3(0, 0, 0),
		"u": Vector3.UP,
		"v": Vector3.RIGHT,
		"n": Vector3.BACK,
		"u_len": 3.0,
		"v_len": 0.2,
		"accent": 0.5
	}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(0, 0, 0.1), Vector3(0.2, 0, 0.1), Vector3(0.2, 3, 0.1), Vector3(0, 3, 0.1)]
	)
	var back := Vector3.BACK
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([back, back, back, back])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var opts := {"amp": 0.0, "phase": Vector3.ZERO, "foot": 0.0, "eave": 3.0}
	var built := PainterMannerMesh.build(
		arrays, PackedInt32Array([0, 0, 0, 0]), PackedStringArray(["frame/beam0"]),
		{"frame/beam0": beam}, opts
	)
	assert_between(int(built.triangles[1]), 4, 8, "a 3 m beam face is cut in two: a few triangles")
	var lo := INF
	var hi := -INF
	for p: Vector3 in built.draw[Mesh.ARRAY_VERTEX]:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	var widest := PainterMannerMesh.BEAM_WIDEN_M + PainterMannerMesh.BEAM_WANDER_M + 0.001
	assert_between(-lo, PainterMannerMesh.BEAM_WIDEN_M - 0.001, widest, "brushed wider on one side")
	assert_between(hi - 0.2, PainterMannerMesh.BEAM_WIDEN_M - 0.001, widest, "and on the other")
	var lean := PainterMannerMesh.door_lean(Vector3(0, 2, 0), Vector3.BACK, 0.0, Vector3.ZERO)
	assert_almost_eq(lean.length(), 2.0 * PainterMannerMesh.DOOR_LEAN, 0.0001)
	assert_almost_eq(lean.y, 0.0, 0.0001, "along the wall")
	var at_foot := PainterMannerMesh.door_lean(Vector3.ZERO, Vector3.BACK, 0.0, Vector3.ZERO)
	assert_eq(at_foot, Vector3.ZERO, "a door stands on its sill")
