class_name MultiMeshCpu
extends RefCounted

## A MultiMesh whose instance data stays readable on the CPU (cards painter-terrain-edge,
## painter-mm-readback; docs/PERFORMANCE.md "Never read a MultiMesh back on the main thread").
##
## A MultiMesh given only a buffer keeps its instances on the GPU alone, so the first later read
## of it on the main thread (MultiMesh.buffer, get_instance_transform, get_instance_custom_data)
## is a GPU readback that stalls the frame: 27 to 35 ms a call for a scatter chunk read in a
## window (RTX 3080), and 11 to 19 ms in one frame for the first avatar shade ray after a load,
## which walked the painted trees' 983 nodes. One per-instance write BEFORE the buffer makes the
## RenderingServer keep its CPU copy (allocated, not read back, while no buffer is set), and the
## buffer assignment then fills that copy too: the same reads take about 0.01 ms and return the
## same floats. The cost is one more copy of the buffer in RAM (0.3 MB for the painted trees of
## a 320 ft forest map). The headless dummy renderer keeps no per-instance data at all, so there
## get_instance_transform() still answers the identity.


## Sets the instances of `multimesh` (TRANSFORM_3D, its instance_count already the buffer's) to
## `buffer` and keeps them readable on the CPU. An empty buffer or count leaves it as it is.
static func set_buffer(multimesh: MultiMesh, buffer: PackedFloat32Array) -> void:
	if multimesh.instance_count <= 0 or buffer.is_empty():
		return
	multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	multimesh.buffer = buffer
