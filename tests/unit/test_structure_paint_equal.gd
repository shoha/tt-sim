extends GutTest

## The faster StructurePaint.paint and StructureGeometry.split_surface (topic perf4) give the
## same meshes, byte for byte, as the implementations they replaced. The old ones are kept below as
## the reference; every one of the 100 core structures and the 72 prop draws is split and painted
## both ways (and painted with two palettes, the street row path), and every array and tag must
## match.
## The pinned digests (test_structure_build, test_library_props) prove the same through the build.

const PROP_SEEDS := 4

var _doc: MapDocument = null
var _usec_old := {"split": 0, "paint": 0}
var _usec_new := {"split": 0, "paint": 0}


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func after_each() -> void:
	StructureGeometry.textured = true


## The structure `ref` at plan `plan` evaluated as StructureGeometry.build_one does: its geometry
## and the role of every tag, and the recipe's palette hints.
func _evaluate(ref: String, plan: PackedVector2Array) -> Dictionary:
	var structure := Structure.make(1, ref, plan, 5)
	var recipe := StructureRecipes.document(structure.recipe)
	StructureOrnaments.apply(recipe, structure.params, structure.seed_value)
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(
		recipe, StructureGeometry.inputs_for(_doc, structure, recipe), true
	)
	if plant == null or not evaluator.errors.is_empty():
		return {}
	var geometry: PlantGeometry = plant["lods"][0]
	var roles := PackedStringArray()
	for path in geometry.tag_table:
		roles.append(StructureLook.role_of_path(recipe, path))
	return {
		"geometry": geometry,
		"roles": roles,
		"palette": StructurePaint.palette_of(
			structure.seed_value, structure.id, StructureLook.palette_hints(recipe)
		),
	}


func _cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ref in StructureRecipes.core_refs():
		var plan := StructurePlacement.pin_plan(LibraryStructureStore.structure(ref))
		out.append({"ref": ref, "plan": plan})
	for row in LibraryStructureStore.props("core"):
		var size: Array = row["default_size_m"]
		var plan := ProcgenProps.footprint(Vector2(float(size[0]), float(size[1])))
		for k in PROP_SEEDS:
			var draw := LibraryStructureStore.prop(String(row["id"]), k)
			out.append({"ref": String(draw["ref"]), "plan": plan})
	return out


func _same(a: Array, b: Array) -> int:
	var moved := 0
	if a.size() != b.size():
		return maxi(a.size(), b.size())
	for k in a.size():
		var x: Dictionary = a[k]
		var y: Dictionary = b[k]
		if x.kind != y.kind or x.role != y.role or x.tags != y.tags or x.arrays != y.arrays:
			moved += 1
	return moved


func _split(geometry: PlantGeometry, roles: PackedStringArray, legacy: bool) -> Array:
	var meshes: Array = []
	for surface in geometry.merged_by_kind():
		if legacy:
			meshes.append_array(_legacy_split(surface, roles))
		else:
			meshes.append_array(StructureGeometry.split_surface(surface, roles))
	return meshes


func test_split_and_paint_equal_the_old_implementations_on_every_structure_and_prop() -> void:
	var cases := _cases()
	assert_eq(cases.size(), 172, "100 structures and 72 prop draws")
	var split_moved := 0
	var paint_moved := 0
	var groups_moved := 0
	var meshes_seen := 0
	for item in cases:
		var made := _evaluate(String(item.ref), item.plan)
		assert_false(made.is_empty(), String(item.ref))
		if made.is_empty():
			continue
		var geometry: PlantGeometry = made.geometry
		var roles: PackedStringArray = made.roles
		var t0 := Time.get_ticks_usec()
		var old_meshes := _split(geometry, roles, true)
		var t1 := Time.get_ticks_usec()
		var new_meshes := _split(geometry, roles, false)
		var t2 := Time.get_ticks_usec()
		_usec_old.split += t1 - t0
		_usec_new.split += t2 - t1
		split_moved += _same(old_meshes, new_meshes)
		meshes_seen += new_meshes.size()
		# One palette: the building path.
		var old_painted := _copy(old_meshes)
		var new_painted := _copy(new_meshes)
		t0 = Time.get_ticks_usec()
		_legacy_paint(old_painted, PackedInt32Array(), [made.palette])
		t1 = Time.get_ticks_usec()
		StructurePaint.paint(new_painted, PackedInt32Array(), [made.palette])
		t2 = Time.get_ticks_usec()
		_usec_old.paint += t1 - t0
		_usec_new.paint += t2 - t1
		paint_moved += _same(old_painted, new_painted)
		# Two palettes with the tags split between them: the street row path.
		var second: Dictionary = made.palette.duplicate()
		second["roof"] = Color(0.2, 0.3, 0.9)
		second["lean"] = Color(0.8, 0.9, 1.0)
		var group_of_tag := PackedInt32Array()
		for tag in (geometry.tag_table as PackedStringArray).size():
			group_of_tag.append(tag % 2)
		var old_rows := _copy(old_meshes)
		var new_rows := _copy(new_meshes)
		_legacy_paint(old_rows, group_of_tag, [made.palette, second])
		StructurePaint.paint(new_rows, group_of_tag, [made.palette, second])
		groups_moved += _same(old_rows, new_rows)
	assert_gt(meshes_seen, 400)
	assert_eq(split_moved, 0, "split_surface meshes that differ from the old ones")
	assert_eq(paint_moved, 0, "painted meshes (one palette) that differ from the old ones")
	assert_eq(groups_moved, 0, "painted meshes (two palettes) that differ from the old ones")
	gut.p(
		"split old %.0f ms new %.0f ms; paint old %.0f ms new %.0f ms (172 builds, main thread)"
		% [
			_usec_old.split / 1000.0,
			_usec_new.split / 1000.0,
			_usec_old.paint / 1000.0,
			_usec_new.paint / 1000.0
		]
	)


func test_a_surface_with_short_tags_and_no_triangles_splits_like_the_old_one() -> void:
	var surface := PlantSurface.new()
	surface.kind = "plaster"
	surface.vertices = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)]
	)
	surface.normals = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	surface.uvs = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	surface.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	surface.tags = PackedInt32Array([0, 1])
	surface.indices = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var roles := PackedStringArray([StructureLook.ROOF, StructureLook.TRIM])
	assert_eq(_same(_legacy_split(surface, roles), StructureGeometry.split_surface(surface, roles)), 0)
	surface.indices = PackedInt32Array()
	assert_eq(StructureGeometry.split_surface(surface, roles).size(), 0)


func _copy(meshes: Array) -> Array:
	var out: Array = []
	for mesh: Dictionary in meshes:
		out.append(mesh.duplicate(true))
	return out


# --- the implementations perf4 replaced, as they were -------------------------------------


static func _legacy_split(surface: PlantSurface, roles: PackedStringArray) -> Array:
	var tags := surface.tags
	var indices := surface.indices
	var triangles := indices.size() / 3
	var role_of := PackedByteArray()
	role_of.resize(triangles)
	var present := PackedByteArray()
	present.resize(StructureLook.ROLES.size())
	for t in triangles:
		var first := indices[t * 3]
		var tag := tags[first] if first < tags.size() else -1
		var role := roles[tag] if tag >= 0 and tag < roles.size() else StructureLook.WALL
		var at := StructureLook.ROLES.find(StructureLook.material_role(surface.kind, role))
		role_of[t] = at
		present[at] = 1
	var out: Array = []
	for at in StructureLook.ROLES.size():
		if present[at] == 0:
			continue
		var picked := PackedInt32Array()
		for t in triangles:
			if role_of[t] == at:
				picked.append(indices[t * 3])
				picked.append(indices[t * 3 + 1])
				picked.append(indices[t * 3 + 2])
		out.append(_legacy_mesh_of(surface, StructureLook.ROLES[at], picked))
	return out


static func _legacy_mesh_of(
	surface: PlantSurface, role: String, picked: PackedInt32Array
) -> Dictionary:
	var used := PackedByteArray()
	used.resize(surface.vertices.size())
	for v in picked:
		used[v] = 1
	var remap := PackedInt32Array()
	remap.resize(surface.vertices.size())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var tags := PackedInt32Array()
	for v in surface.vertices.size():
		if used[v] == 0:
			continue
		remap[v] = vertices.size()
		vertices.append(surface.vertices[v])
		normals.append(surface.normals[v])
		uvs.append(surface.uvs[v])
		colors.append(surface.colors[v])
		tags.append(surface.tags[v] if v < surface.tags.size() else -1)
	var indices := PackedInt32Array()
	indices.resize(picked.size())
	for k in picked.size():
		indices[k] = remap[picked[k]]
	return {
		"kind": surface.kind,
		"role": role,
		"arrays": StructureGeometry._arrays(surface.kind, vertices, normals, uvs, colors, indices),
		"tags": tags,
	}


static func _legacy_group(
	group_of_tag: PackedInt32Array, tags: PackedInt32Array, v: int, count: int
) -> int:
	var tag := tags[v] if v < tags.size() else -1
	if tag < 0 or tag >= group_of_tag.size():
		return 0
	return clampi(group_of_tag[tag], 0, count - 1)


static func _legacy_paint(
	meshes: Array, group_of_tag: PackedInt32Array, palettes: Array
) -> void:
	if meshes.is_empty() or palettes.is_empty():
		return
	var roof_low := PackedFloat32Array()
	var roof_high := PackedFloat32Array()
	var foot := PackedFloat32Array()
	roof_low.resize(palettes.size())
	roof_low.fill(INF)
	roof_high.resize(palettes.size())
	roof_high.fill(-INF)
	foot.resize(palettes.size())
	foot.fill(INF)
	var moss_peak := PackedFloat32Array()
	moss_peak.resize(palettes.size())
	for mesh: Dictionary in meshes:
		if not StructurePaint._paints(mesh):
			continue
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var source: PackedColorArray = mesh.arrays[Mesh.ARRAY_COLOR]
		var tags: PackedInt32Array = mesh.tags
		var roof := StructurePaint._is_roof(mesh)
		for v in vertices.size():
			var g := _legacy_group(group_of_tag, tags, v, palettes.size())
			var y := vertices[v].y
			if roof:
				roof_low[g] = minf(roof_low[g], y)
				roof_high[g] = maxf(roof_high[g], y)
			else:
				foot[g] = minf(foot[g], y)
				if mesh.role == StructureLook.WALL and v < source.size():
					moss_peak[g] = maxf(moss_peak[g], StructurePaint.moss_of(source[v]))
	for mesh: Dictionary in meshes:
		if not StructurePaint._paints(mesh):
			continue
		var arrays: Array = mesh.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var tags: PackedInt32Array = mesh.tags
		var roof := StructurePaint._is_roof(mesh)
		var accent: bool = mesh.kind == StructureLook.ACCENT_KIND
		var out := PackedColorArray()
		out.resize(vertices.size())
		for v in vertices.size():
			var g := _legacy_group(group_of_tag, tags, v, palettes.size())
			var palette: Dictionary = palettes[g]
			var c: Color = colors[v] if v < colors.size() else Color.WHITE
			if (
				mesh.role == StructureLook.ORNAMENT
				or mesh.role == StructureLook.CANOPY
				or mesh.role == StructureLook.PROP
			):
				var up := vertices[v].y - (foot[g] if foot[g] < INF else 0.0)
				out[v] = Color(c.r, c.g, c.b, clampf(up / StructurePaint.WALL_ALPHA_SPAN_M, 0.0, 1.0))
			elif accent:
				var shade := c.r
				var metres_up := vertices[v].y - (foot[g] if foot[g] < INF else 0.0)
				var a: Color = palette.accent
				out[v] = Color(
					minf(a.r * shade, 1.0),
					minf(a.g * shade, 1.0),
					minf(a.b * shade, 1.0),
					clampf(metres_up / StructurePaint.WALL_ALPHA_SPAN_M, 0.0, 1.0)
				)
			elif roof:
				var span := maxf(roof_high[g] - roof_low[g], 0.1)
				var tone := c.r / StructurePaint.ROOF_REFERENCE_TONE
				var tile: Color = palette.roof
				out[v] = Color(
					minf(tile.r * tone, 1.0),
					minf(tile.g * tone, 1.0),
					minf(tile.b * tone, 1.0),
					clampf((vertices[v].y - roof_low[g]) / span, 0.0, 1.0)
				)
			else:
				var lean: Color = palette.lean
				if mesh.role == StructureLook.TRIM:
					lean = Color.WHITE
				var metres := vertices[v].y - (foot[g] if foot[g] < INF else 0.0)
				var alpha := clampf(metres / StructurePaint.WALL_ALPHA_SPAN_M, 0.0, 1.0)
				if mesh.role == StructureLook.FRAME:
					out[v] = Color(c.r, c.g, c.b, alpha)
				elif mesh.role == StructureLook.WALL and palette.has("wall"):
					var tint: Color = palette.wall
					var tone := c.r / StructurePaint.WALL_REFERENCE_TONE
					if StructurePaint.TEXTURED_KINDS.has(String(mesh.kind)):
						tone *= StructurePaint.TEXTURED_WALL_GAIN
					else:
						tone = 1.0 + (tone - 1.0) * StructurePaint.STYLE_TONE_KEEP
					var moss := StructurePaint.moss_of(c)
					if not StructurePaint.TEXTURED_KINDS.has(String(mesh.kind)):
						moss = maxf(
							moss,
							(
								moss_peak[g]
								* (
									1.0
									- smoothstep(
										StructurePaint.MOSS_FULL_M, StructurePaint.MOSS_CLIMB_M, metres
									)
								)
							)
						)
					var toned := Color(
						tint.r * tone * lerpf(1.0, StructurePaint.MOSS_TINT.r, moss),
						tint.g * tone * lerpf(1.0, StructurePaint.MOSS_TINT.g, moss),
						tint.b * tone * lerpf(1.0, StructurePaint.MOSS_TINT.b, moss),
						alpha
					)
					if moss > 0.0 and not StructurePaint.TEXTURED_KINDS.has(String(mesh.kind)):
						toned = StructurePaint._mossed(toned, moss)
					out[v] = toned
				else:
					out[v] = Color(
						minf(c.r * lean.r, 1.0),
						minf(c.g * lean.g, 1.0),
						minf(c.b * lean.b, 1.0),
						alpha
					)
		arrays[Mesh.ARRAY_COLOR] = out
