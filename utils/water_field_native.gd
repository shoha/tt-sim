class_name WaterFieldNative
extends RefCounted

## The native twins of WaterField's hot passes (card painter-water-latency): the spill relaxation,
## the buried rings, depth, slope and energy pass, the shore, and RiverProfile.field's course
## raster, run in the scatter library (native/src/water_field.cpp, ScatterNative.CAPABILITY_WFIELD)
## and give every array the GDScript gives bit for bit (test_water_field_native). Each wrapper takes
## the field, packs the arrays and constants the C++ reads by name (so the constants stay in
## WaterField), and stores what comes back. instance() is null without the library (or with
## `ScatterNative.force_gdscript_wfield`), and the callers then run their GDScript, which stays the
## reference. RiverProfile.field talks to the library itself (see ScatterNative.wfield_instance).


## The library's instance when it has the passes and they are not forced off, else null.
static func instance() -> Object:
	return ScatterNative.wfield_instance()


## WaterField._spill_pass: sets `f._base`, returns the bounds of the samples that may have changed.
static func spill(native: Object, f: WaterField, rect: Rect2i, was: PackedByteArray) -> Rect2i:
	var out: Dictionary = native.call(
		"water_spill",
		{
			"size": f.size,
			"rect": rect,
			"raw": f._raw,
			"spill": f.spill,
			"was": was,
			"ground": f.ground,
			"base": f._base,
			"step_x": f.step.x,
			"step_y": f.step.y,
			"diag": f.step.length(),
			"inflow_slope": WaterField.INFLOW_SLOPE,
			"bank_slope": WaterField.BANK_SPILL_SLOPE,
			"spill_bank": WaterField.SPILL_BANK,
			"tuck": WaterField.TUCK_M,
		}
	)
	f._base = out.base
	return out.bounds


## WaterField._derive over `inner`: sets w, ew, depth, steep and energy.
static func derive(native: Object, f: WaterField, inner: Rect2i) -> void:
	var out: Dictionary = native.call(
		"water_derive",
		{
			"size": f.size,
			"inner": inner,
			"base": f._base,
			"ground": f.ground,
			"spill": f.spill,
			"calm": f.calm,
			"stroke_energy": f._stroke_energy,
			"w": f.w,
			"ew": f.ew,
			"depth": f.depth,
			"steep": f.steep,
			"energy": f.energy,
			"exact": WaterField.exact_shore,
			"tuck": WaterField.TUCK_M,
			"edge_min": WaterField.EDGE_MIN,
			"step_x": f.step.x,
			"step_y": f.step.y,
			"steep_lo": WaterField.STEEP.x,
			"steep_hi": WaterField.STEEP.y,
			"white_lo": WaterField.SLOPE_WHITE.x,
			"white_hi": WaterField.SLOPE_WHITE.y,
			"ramp_keep": WaterField.RAMP_KEEP,
			"ramp_flat": WaterField.RAMP_FLAT_M,
			"spill_pond": WaterField.SPILL_POND,
		}
	)
	f.w = out.w
	f.ew = out.ew
	f.depth = out.depth
	f.steep = out.steep
	f.energy = out.energy


## WaterField._shore over `outer`: sets shore.
static func shore(native: Object, f: WaterField, outer: Rect2i) -> void:
	var out: Dictionary = native.call(
		"water_shore",
		{
			"size": f.size,
			"outer": outer,
			"w": f.w,
			"depth": f.depth,
			"ew": f.ew,
			"ground": f.ground,
			"shore": f.shore,
			"exact": WaterField.exact_shore,
			"origin": f.origin,
			"step": f.step,
			"margin": WaterField.SHORE_MARGIN,
			"shore_far": WaterField.SHORE_FAR,
			"exact_m": WaterField.EXACT_M,
		}
	)
	f.shore = out.shore


## WaterFieldMesh.build's result for `f` (the same Dictionary).
static func mesh(native: Object, f: WaterField) -> Dictionary:
	var out: Dictionary = native.call(
		"water_mesh",
		{
			"size": f.size,
			"origin": f.origin,
			"step": f.step,
			"w": f.w,
			"ew": f.ew,
			"depth": f.depth,
			"ground": f.ground,
			"energy": f.energy,
			"shore": f.shore,
			"steep": f.steep,
			"river": f.river,
			"foot": f.foot,
			"spill": f.spill,
			"calm": f.calm,
			"spill_pond": WaterField.SPILL_POND,
			"spill_bank": WaterField.SPILL_BANK,
			"pond_mark": WaterFieldMesh.SPILL_POND_MARK,
			"bank_mark": WaterFieldMesh.SPILL_BANK_MARK,
			"film_mark": WaterFieldMesh.FILM_MARK,
			"field_flag": WaterFieldMesh.FIELD_FLAG,
			"no_foot": WaterFieldStroke.NO_FOOT,
		}
	)
	var count: int = out.vertices.size()
	if count == 0:
		return {"arrays": [], "aabb": AABB(), "vertices": 0, "triangles": 0}
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out.vertices
	arrays[Mesh.ARRAY_NORMAL] = out.normals
	arrays[Mesh.ARRAY_TEX_UV] = out.uvs
	arrays[Mesh.ARRAY_CUSTOM0] = out.c0
	arrays[Mesh.ARRAY_CUSTOM1] = out.c1
	arrays[Mesh.ARRAY_INDEX] = out.indices
	var indices: PackedInt32Array = out.indices
	return {
		"arrays": arrays,
		"aabb": out.aabb,
		"vertices": count,
		"triangles": indices.size() / 3,
	}


## The two RGBAF texture buffers PainterWaterField uploads (see its _upload_textures), packed from
## `f` over its whole grid: {"a": (depth, energy, shore, steep), "b": (flow coordinate times its
## weight, the weight, foot coordinate times its weight, the weight)} per sample. The depth is
## the surface as the mesh draws it (ew) over the ground on a wet sample, floored at
## `depth_floor`; a pond sample under a fall's plunge has a foot weight without a flow weight.
## Native when the library is loaded, else GDScript (the reference).
static func pack_textures(f: WaterField, depth_floor: float) -> Dictionary:
	var native := instance()
	if native != null:
		return _textures(native, f, depth_floor)
	var n := f.size.x * f.size.y
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	a.resize(n * 4)
	b.resize(n * 4)
	for i in n:
		var d: float = f.depth[i]
		if f.w[i] != WaterGeometry.DRY:
			d = f.ew[i] - f.ground[i]
		a[i * 4] = maxf(d, depth_floor)
		a[i * 4 + 1] = f.energy[i]
		a[i * 4 + 2] = f.shore[i]
		a[i * 4 + 3] = f.steep[i]
		var u: float = f.flow_u[i]
		if u > WaterField.NO_FLOW_U * 0.5:
			b[i * 4] = u
			b[i * 4 + 1] = 1.0
		var ft: float = f.foot[i]
		if ft < WaterFieldStroke.NO_FOOT * 0.5:
			b[i * 4 + 2] = ft
			b[i * 4 + 3] = 1.0
	return {"a": a, "b": b}


static func _textures(native: Object, f: WaterField, depth_floor: float) -> Dictionary:
	return native.call(
		"water_textures",
		{
			"count": f.size.x * f.size.y,
			"w": f.w,
			"ew": f.ew,
			"depth": f.depth,
			"ground": f.ground,
			"energy": f.energy,
			"shore": f.shore,
			"steep": f.steep,
			"flow_u": f.flow_u,
			"foot": f.foot,
			"depth_floor": depth_floor,
			"no_flow_u": WaterField.NO_FLOW_U,
			"no_foot": WaterFieldStroke.NO_FOOT,
		}
	)

