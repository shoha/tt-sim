extends GutTest

## ScatterGlbUtils.multimesh_from_chunk() keeps a settled node's instance data readable on the
## CPU (card painter-terrain-edge: no GPU readback on an edit). That it costs no readback only a
## window can show (docs/systems/painter.md "Grounding"); what holds everywhere is tested here:
## the multimesh holds exactly the buffer it was given, instance by instance, and the contact
## field baked from it (PainterOcclusion) equals, bit for bit, the one baked from a multimesh
## built the old way, from the buffer alone.
## The headless RenderingServer stores a multimesh's buffer but no per-instance write and answers
## get_instance_transform() with the identity, so there the per-instance asserts compare what the
## server holds, and the later-write test passes without asserting; run in a window (this script
## through gut_cmdln.gd without --headless) every assert reads the real instance data.

const COUNT := 9


## The stand-in for PainterSurfaces that PainterOcclusion._add_solids() asks.
class Surfaces:
	extends RefCounted

	var meshes := {}
	var nodes: Array = []

	func solid_meshes() -> Dictionary:
		return meshes

	func scatters() -> Array:
		return nodes


## COUNT instances turned, scaled and spread, as a TRANSFORM_3D buffer (rows of the 3 x 4 matrix).
func _buffer() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in COUNT:
		var turn := Basis(Vector3.UP, 0.37 * i + 0.11).scaled(Vector3.ONE * (0.6 + 0.17 * i))
		var xf := Transform3D(turn, Vector3(1.3 * i - 5.0, 0.21 * i, 0.77 * i * i - 3.0))
		for row in 3:
			out.append(xf.basis.x[row])
			out.append(xf.basis.y[row])
			out.append(xf.basis.z[row])
			out.append(xf.origin[row])
	return out


func _chunk() -> Dictionary:
	var order := PackedInt32Array()
	for i in COUNT:
		order.append(i)
	return {"buffer": _buffer(), "custom": false, "order": order}


## The multimesh as it was built before: the buffer alone.
func _plain(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = COUNT
	multimesh.buffer = _buffer()
	return multimesh


## The contact field's marks and floats for one scatter node drawing `multimesh`.
func _field(multimesh: MultiMesh) -> Array:
	var scatter := Node3D.new()
	add_child_autofree(scatter)
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.position = Vector3(0.4, 0.0, -0.9)
	scatter.add_child(node)
	var surfaces := Surfaces.new()
	surfaces.meshes = {multimesh.mesh.get_instance_id(): false}
	surfaces.nodes = [scatter]
	var occlusion := PainterOcclusion.new()
	occlusion._surfaces = surfaces
	var marks: Array = []
	occlusion._add_solids(marks)
	occlusion.update(Vector2(-12.0, -12.0), Vector2i(160, 160), marks)
	return [marks, occlusion._data]


func test_the_chunk_multimesh_holds_the_buffer_it_was_given() -> void:
	var mesh := BoxMesh.new()
	var built := ScatterGlbUtils.multimesh_from_chunk(mesh, _chunk())
	var plain := _plain(mesh)
	assert_eq(built.instance_count, COUNT)
	assert_true(built.buffer == _buffer(), "the buffer read is the buffer set")
	assert_true(built.buffer == plain.buffer, "as a multimesh built from the buffer alone")
	for i in COUNT:
		assert_eq(built.get_instance_transform(i), plain.get_instance_transform(i), "instance %d" % i)


func test_an_instance_written_later_reads_back() -> void:
	if DisplayServer.get_name() == "headless":
		pass_test("the headless server keeps no per-instance write")
		return
	var built := ScatterGlbUtils.multimesh_from_chunk(BoxMesh.new(), _chunk())
	var moved := Transform3D(Basis(), Vector3(7.0, 1.0, -2.0))
	built.set_instance_transform(3, moved)
	assert_eq(built.get_instance_transform(3), moved)
	var expected := _buffer()
	for k in 12:
		expected[36 + k] = [1.0, 0.0, 0.0, 7.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0, -2.0][k]
	assert_true(built.buffer == expected, "the other instances keep the buffer's floats")


func test_the_contact_field_is_the_same_bit_for_bit() -> void:
	var mesh := BoxMesh.new()
	var from_chunk := _field(ScatterGlbUtils.multimesh_from_chunk(mesh, _chunk()))
	var from_buffer := _field(_plain(mesh))
	assert_gt((from_chunk[0] as Array).size(), 0, "the solids left marks")
	assert_true(from_chunk[0] == from_buffer[0], "the same marks")
	var a: PackedFloat32Array = from_chunk[1]
	var b: PackedFloat32Array = from_buffer[1]
	assert_gt(a.size(), 0)
	assert_true(a.to_byte_array() == b.to_byte_array(), "the same field, byte for byte")
	var lit := 0
	for value in a:
		if value > 0.0:
			lit += 1
	assert_gt(lit, 0, "and it is not empty")
