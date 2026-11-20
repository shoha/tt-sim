class_name WaterFieldMesh
extends RefCounted

## The one water surface of a WaterField as mesh arrays, pure (docs/systems/water_field.md). One
## vertex per sample of the document's grid, shared by every cell that uses it, so the surface is
## continuous everywhere by construction: over a reach, a riffle, an inflow ramp, a fall's brink,
## its face and its foot alike (no curtain mesh, no frames, no seams to match). A cell is drawn
## when any corner is wet (depth > 0); one more ring of cells is added round them, whose outer
## corners WaterField put under the ground, so the mesh's edge is always buried and the waterline
## is where the surface meets the ground (the shader fades by the interpolated depth).
##
## Vertex contract (painter_water.gdshader): VERTEX in map space (an identity transform at the map
## origin), UV map-normalised (the flow map's frame), CUSTOM0 = (depth, energy, shore distance,
## steep share), CUSTOM1 = (lateral coordinate (WaterField.lateral), FIELD_FLAG, 1 where the sample
## is within the foot coordinate's range of a fall's foot (WaterField.foot; the shader fetches the
## coordinate only there), the spill mark: 1 a river's ramp into a pond,
## 0.5 a bank's thin spill that is not drawn as a shelf, 0.125 a film). The mesh
## is a function of the field alone, so a field refreshed over a dirty rect draws exactly what a
## fresh build would.

const MESH_NAME := "PaintedWaterField"
const FORMAT := (
	(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
)
## CUSTOM1.y of a field vertex (the shader's FIELD_FLAG): never a half-width, which is >= 0.
const FIELD_FLAG := -7.0
## CUSTOM1.w: 1 on a river's ramp into a lower pond, 0.5 on a bank sample the river's carve does
## not hold (WaterField.spill), 0 elsewhere.
const SPILL_POND_MARK := 1.0
const SPILL_BANK_MARK := 0.5
## CUSTOM1.w on a stroke's film (undermined water the bridge does not span): the shader reads it
## as mid-depth water, not as the few centimetres it is.
const FILM_MARK := 0.125

const _CORNERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]


## {"arrays", "aabb", "vertices", "triangles"} for `f` (see the header); empty arrays when the
## field holds no water.
static func build(f: WaterField) -> Dictionary:
	var native := WaterFieldNative.instance()
	if native != null:
		return WaterFieldNative.mesh(native, f)
	var nx := f.size.x
	var nz := f.size.y
	var cells := PackedByteArray()
	cells.resize(maxi((nx - 1) * (nz - 1), 0))
	for z in nz - 1:
		for x in nx - 1:
			var i := z * nx + x
			if f.depth[i] > 0.0 or f.depth[i + 1] > 0.0 or f.depth[i + nx] > 0.0:
				cells[z * (nx - 1) + x] = 1
			elif f.depth[i + nx + 1] > 0.0:
				cells[z * (nx - 1) + x] = 1
	var ring := cells.duplicate()
	for z in nz - 1:
		for x in nx - 1:
			if cells[z * (nx - 1) + x] != 1:
				continue
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var xx := x + dx
					var zz := z + dz
					if xx < 0 or zz < 0 or xx >= nx - 1 or zz >= nz - 1:
						continue
					var c := zz * (nx - 1) + xx
					if ring[c] == 0 and _defined(f, xx, zz):
						ring[c] = 2
	var index_of := PackedInt32Array()
	index_of.resize(nx * nz)
	index_of.fill(-1)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()
	var indices := PackedInt32Array()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for z in nz - 1:
		for x in nx - 1:
			if ring[z * (nx - 1) + x] == 0:
				continue
			var corner := PackedInt32Array()
			for o in _CORNERS:
				var xx: int = x + o.x
				var zz: int = z + o.y
				var s := zz * nx + xx
				if index_of[s] < 0:
					index_of[s] = verts.size()
					# The surface as drawn (ew) and its depth over the ground: on the first buried ring the
					# surface stands at the neighbour's extended level, so the waterline is exact.
					var wet := f.w[s] != WaterGeometry.DRY
					var y: float = f.ew[s] if wet else f.w[s]
					var d: float = f.ew[s] - f.ground[s] if wet else f.depth[s]
					var p := Vector3(f.origin.x + xx * f.step.x, y, f.origin.y + zz * f.step.y)
					verts.append(p)
					lo = lo.min(p)
					hi = hi.max(p)
					normals.append(_normal(f, xx, zz))
					uvs.append(Vector2(float(xx) / (nx - 1), float(zz) / (nz - 1)))
					c0.append_array([maxf(d, -1.0), f.energy[s], f.shore[s], f.steep[s]])
					var spill := 0.0
					if f.spill[s] == WaterField.SPILL_POND:
						spill = SPILL_POND_MARK
					elif f.spill[s] == WaterField.SPILL_BANK:
						spill = SPILL_BANK_MARK
					elif f.calm[s] != 0:
						spill = FILM_MARK
					var near_foot := 1.0 if f.foot[s] < WaterFieldStroke.NO_FOOT * 0.5 else 0.0
					c1.append_array([f.lateral[s], FIELD_FLAG, near_foot, spill])
				corner.append(index_of[s])
			indices.append_array([corner[0], corner[1], corner[2], corner[1], corner[3], corner[2]])
	if verts.is_empty():
		return {"arrays": [], "aabb": AABB(), "vertices": 0, "triangles": 0}
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = c0
	arrays[Mesh.ARRAY_CUSTOM1] = c1
	arrays[Mesh.ARRAY_INDEX] = indices
	return {
		"arrays": arrays,
		"aabb": AABB(lo, hi - lo),
		"vertices": verts.size(),
		"triangles": indices.size() / 3,
	}


## The mesh of `built` (build()'s result) with `material` on its one surface; null with no water.
static func to_mesh(built: Dictionary, material: Material) -> ArrayMesh:
	var arrays: Array = built.get("arrays", [])
	if arrays.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, FORMAT)
	mesh.surface_set_material(0, material)
	return mesh


## True when all four corners of cell (x, z) have a surface height.
static func _defined(f: WaterField, x: int, z: int) -> bool:
	var nx := f.size.x
	var i := z * nx + x
	for s in [i, i + 1, i + nx, i + nx + 1]:
		if f.w[s] == WaterGeometry.DRY:
			return false
	return true


## The surface normal at sample (x, z) from its neighbours' heights.
static func _normal(f: WaterField, x: int, z: int) -> Vector3:
	var nx := f.size.x
	var src := f.w
	var i := z * nx + x
	var h := src[i]
	var l := src[i - 1] if x > 0 and src[i - 1] != WaterGeometry.DRY else h
	var r := src[i + 1] if x < nx - 1 and src[i + 1] != WaterGeometry.DRY else h
	var d := src[i - nx] if z > 0 and src[i - nx] != WaterGeometry.DRY else h
	var u := src[i + nx] if z < f.size.y - 1 and src[i + nx] != WaterGeometry.DRY else h
	return Vector3((l - r) / (2.0 * f.step.x), 1.0, (d - u) / (2.0 * f.step.y)).normalized()
