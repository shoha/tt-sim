extends RefCounted

## A small map GLB that carries the optional painter-role extras (ASSET_PIPELINE.md "Painter roles",
## card painter-glb-roles), for the role tests and the confirmation render job. Written with
## GLTFDocument: Godot's exporter writes a node's, a mesh's and a material's "extras" metadata as
## glTF extras, so no JSON patching is needed. Every prop's material NAME says something else than
## its extra, so a role that comes out of a test came from the extra. Not a test file itself (GUT
## only collects test_*.gd); preload it as a const.

const GLB := preload("res://tests/unit/glb_fixtures.gd")

## The roles a prop test node carries: node name -> [tt_paint_role, the material's own name].
const PROPS := {
	"Prop_roof": ["roof", "Marble_White"],
	"Prop_bark": ["bark", "Marble_White"],
	"Prop_stone": ["stone", "Wood_Plank"],
	"Prop_leaf": ["leaf", "Marble_White"],
	"Prop_keep": ["keep", "Wood_Plank"],
	"Prop_loud": ["  Bark ", "Marble_White"],
}
## Terrain test nodes -> the extra they carry: a ground-* role on the node, tt_ground on the node,
## a role on the mesh.
const GROUNDS := {
	"Ground_Lane": "ground-path",
	"Ground_Pad": "ground-rock",
	"Ground_Meadow": "ground-meadow",
	"Ground_Marked": "tt_ground",
	"Ground_OnMesh": "mesh:ground-path",
}
const STRAY := "Prop_unknown"
const SPLIT := "House_Split"
const NOT_GROUND := "Field_NotGround"
const WIDE := "Field_Plain"
const PLAIN := "Plain_Wood"
const NODE_OVER_MESH := "Node_Over_Mesh"
const MESH_ONLY := "Mesh_Only"
## The side (m) of the wide planes WIDE and NOT_GROUND.
const FIELD_SIZE := 24.0
## The role the unknown prop carries.
const UNKNOWN_VALUE := "wall"


## Writes the map to `path`; OK or the write's error.
static func write(path: String) -> Error:
	var root := Node3D.new()
	root.name = "Map"
	var x := -12.0
	for node_name: String in PROPS:
		var spec: Array = PROPS[node_name]
		var node := _prop(node_name, spec[1], Color(0.5, 0.5, 0.5), Vector3(x, 0.5, -6.0))
		node.set_meta("extras", {"tt_paint_role": spec[0]})
		root.add_child(node)
		x += 3.0
	var stray := _prop(STRAY, "Barrel_Wood", Color(0.5, 0.5, 0.5), Vector3(x, 0.5, -6.0))
	stray.set_meta("extras", {"tt_paint_role": UNKNOWN_VALUE})
	root.add_child(stray)
	var plain := _prop(PLAIN, "Wood_Plank", Color(0.5, 0.5, 0.5), Vector3(x + 3.0, 0.5, -6.0))
	root.add_child(plain)
	# One mesh of two surfaces: the second material states its own role.
	var split := MeshInstance3D.new()
	split.name = SPLIT
	var split_mesh := ArrayMesh.new()
	for i in 2:
		var box := BoxMesh.new()
		var arrays := box.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for j in verts.size():
			verts[j] += Vector3(0.0, 1.5 * i, 0.0)
		arrays[Mesh.ARRAY_VERTEX] = verts
		split_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		split_mesh.surface_set_material(i, _material("Mat_%d" % i, Color(0.5, 0.5, 0.5)))
	split_mesh.surface_get_material(1).set_meta("extras", {"tt_paint_role": "roof"})
	split.mesh = split_mesh
	split.position = Vector3(-12.0, 0.5, -10.0)
	root.add_child(split)
	var over := _prop(NODE_OVER_MESH, "Mat_Over", Color(0.5, 0.5, 0.5), Vector3(-8.0, 0.5, -10.0))
	over.mesh.set_meta("extras", {"tt_paint_role": "stone"})
	over.set_meta("extras", {"tt_paint_role": "leaf"})
	root.add_child(over)
	var mesh_only := _prop(MESH_ONLY, "Mat_Mesh", Color(0.5, 0.5, 0.5), Vector3(-4.0, 0.5, -10.0))
	mesh_only.mesh.set_meta("extras", {"tt_paint_role": "bark"})
	root.add_child(mesh_only)
	var column := 0
	for node_name: String in GROUNDS:
		var ground := _ground(node_name, Vector2(5.0, 5.0), Vector3(-12.0 + column * 6.0, 0.0, 4.0))
		column += 1
		var extra: String = GROUNDS[node_name]
		if extra == "tt_ground":
			ground.set_meta("extras", {"tt_ground": true})
		elif extra.begins_with("mesh:"):
			ground.mesh.set_meta("extras", {"tt_paint_role": extra.trim_prefix("mesh:")})
		else:
			ground.set_meta("extras", {"tt_paint_role": extra})
		root.add_child(ground)
	# A wide, flat, up-facing plane the shape rule takes for ground, and the same with tt_ground false.
	root.add_child(_field(WIDE, Vector3(18.0, 0.0, 20.0)))
	var field := _field(NOT_GROUND, Vector3(-18.0, 0.0, 20.0))
	field.set_meta("extras", {"tt_ground": false})
	root.add_child(field)
	var state := GLTFState.new()
	var gltf := GLTFDocument.new()
	var err := gltf.append_from_scene(root, state)
	if err == OK:
		err = gltf.write_to_filesystem(state, path)
	root.free()
	if err != OK:
		return err
	return GLB.patch_scene_extras(path, {"tt_ambient_light_energy": 0.8})


static func _material(material_name: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = color
	return material


## A one-surface box prop with its own mesh and material.
static func _prop(
	node_name: String, material_name: String, color: Color, at: Vector3
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 1.0, 1.5)
	mesh.material = _material(material_name, color)
	node.mesh = mesh
	node.position = at
	return node


## The surface arrays of a fixture mesh, for PainterGlbMap.surface_arrays (the headless dummy
## renderer keeps none to read back): a wide mesh is the flat plane of _field, any other a box.
static func arrays_of(mesh: Mesh) -> Array:
	if mesh.get_aabb().size.x > FIELD_SIZE * 0.5:
		var plane := PlaneMesh.new()
		plane.size = Vector2(FIELD_SIZE, FIELD_SIZE)
		return plane.get_mesh_arrays()
	return BoxMesh.new().get_mesh_arrays()


## A wide, flat, up-facing plane (so the shape rule reads it as ground), one material.
static func _field(node_name: String, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(FIELD_SIZE, FIELD_SIZE)
	mesh.material = _material("Slab_" + node_name, Color(0.3, 0.5, 0.2))
	node.mesh = mesh
	node.position = at
	return node


## A flat one-surface slab `size` metres on X and Z, its own mesh, a green material.
static func _ground(node_name: String, size: Vector2, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.2, size.y)
	mesh.material = _material("Slab_" + node_name, Color(0.3, 0.5, 0.2))
	node.mesh = mesh
	node.position = at
	return node
