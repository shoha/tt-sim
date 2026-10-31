extends GutTest

## The halo round a lantern (utils/structure_glow.gd, shaders/structure_glow.gdshader; topic looks3,
## 2026-10-31) and the cloth strips a flag's ripple needs: one halo quad per lantern kept beside the
## meshes (digest and budget unchanged), grown with the prop in a settlement bake, drawn by its own
## material; and a pennant that has corners between its pole and its tip to bend.

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	LibraryRegistry.official_root = LibraryRegistry.OFFICIAL_ROOT
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(PaletteLibrary.DEFAULT_ROOT)


func _prop(prop_name: String, seed_value: int = 0) -> Dictionary:
	var row := LibraryStructureStore.prop(prop_name, seed_value)
	if row.is_empty():
		return {}
	var size: Array = row["default_size_m"]
	var plan := ProcgenProps.footprint(Vector2(float(size[0]), float(size[1])))
	return StructureGeometry.build_one(_doc, Structure.make(1, String(row["ref"]), plan, 5))


## The glass boxes of a prop's meshes, found the way the host finds them.
func _lanterns(parts: Dictionary) -> int:
	var count := 0
	for mesh: Dictionary in parts.meshes:
		if mesh.role == StructureLook.PROP and mesh.kind == StructureLook.GLASS_KIND:
			count += StructureGlow.boxes_of(mesh.arrays).size()
	return count


func test_a_lamp_post_gets_one_halo_quad_per_lantern_outside_the_meshes() -> void:
	var seen := 0
	for seed_value in 6:
		var parts := _prop("lamp_post", seed_value)
		if parts.is_empty():
			continue
		var lanterns := _lanterns(parts)
		assert_gt(lanterns, 0, "a lamp post has a lantern (seed %d)" % seed_value)
		var glow: Array = parts.glow
		assert_eq(glow.size(), 1, "one glow mesh")
		var mesh: Dictionary = glow[0]
		assert_eq(mesh.kind, StructureGlow.KIND)
		assert_eq(mesh.role, StructureLook.PROP)
		var arrays: Array = mesh.arrays
		assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 6 * lanterns, "two tris each")
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for q in lanterns:
			for k in 4:
				assert_eq(vertices[q * 4 + k], vertices[q * 4], "the corners share the pane's centre")
				assert_gt(uv2[q * 4 + k].x, 0.1, "a halo is more than a hand wide")
				assert_lt(uv2[q * 4 + k].x, 2.0, "and less than a house")
		for m: Dictionary in parts.meshes:
			assert_ne(m.kind, StructureGlow.KIND, "not in meshes: the digest and budget do not move")
		seen += lanterns
	assert_gt(seen, 0, "a lantern was found")


func test_a_building_without_lanterns_has_no_glow() -> void:
	var parts := _prop("barrel")
	assert_true((parts.glow as Array).is_empty())
	assert_true(StructureGlow.of([]).is_empty())


func test_the_halo_is_two_and_a_half_panes_or_more_across() -> void:
	var box := PackedVector3Array(
		[
			Vector3(0, 0, 0), Vector3(0.24, 0, 0), Vector3(0.24, 0.34, 0), Vector3(0, 0.34, 0),
			Vector3(0, 0, 0.24), Vector3(0.24, 0, 0.24), Vector3(0.24, 0.34, 0.24), Vector3(0, 0.34, 0.24)
		]
	)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = box
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 7, 0, 7, 3])
	var found := StructureGlow.boxes_of(arrays)
	assert_eq(found.size(), 1, "one box")
	assert_almost_eq((found[0].centre as Vector3).y, 0.17, 0.001)
	var made := StructureGlow.of(
		[{"kind": StructureLook.GLASS_KIND, "role": StructureLook.PROP, "arrays": arrays, "tags": []}]
	)
	var half: float = (made[0].arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[0].x
	assert_gt(half * 2.0, 2.5 * 0.34, "the visible halo is at least two and a half panes")


func test_a_baked_halo_grows_with_the_prop_and_stays_its_own_surface() -> void:
	var parts := _prop("lamp_post", 1)
	var surfaces: Array = []
	for mesh: Dictionary in (parts.meshes as Array) + (parts.glow as Array):
		surfaces.append(
			{
				"key": "%s:%s" % [mesh.role, mesh.kind],
				"role": mesh.role,
				"kind": mesh.kind,
				"arrays": mesh.arrays
			}
		)
	var sources := {"lamp": {"surfaces": surfaces}}
	var small := SettlementBake.bake(
		[{"variant": "lamp", "transform": Transform3D(Basis.IDENTITY, Vector3.ZERO)}], sources
	)
	var big := SettlementBake.bake(
		[
			{
				"variant": "lamp",
				"transform": Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 2.0), Vector3.ZERO)
			}
		],
		sources
	)
	var halo_small := _surface_of(small, StructureGlow.KIND)
	var halo_big := _surface_of(big, StructureGlow.KIND)
	assert_false(halo_small.is_empty(), "the halo is its own surface")
	var ratio: float = (
		(halo_big.arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[0].x
		/ (halo_small.arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[0].x
	)
	assert_almost_eq(ratio, 2.0, 0.001, "a scaled prop's halo scales")
	assert_ne(
		_surface_of(small, StructureLook.GLASS_KIND).get("key", ""), "", "the pane keeps its surface"
	)


func _surface_of(surfaces: Array[Dictionary], kind: String) -> Dictionary:
	for surface in surfaces:
		if surface.kind == kind:
			return surface
	return {}


func test_the_glow_has_its_own_material_and_a_lantern_keeps_its_pane() -> void:
	var halo := StructureMaterials.make(StructureGlow.KIND, StructureLook.PROP, "", "")
	assert_eq((halo as ShaderMaterial).shader, StructureMaterials.GLOW_SHADER)
	var pane := StructureMaterials.make("glass", StructureLook.PROP, "", "") as ShaderMaterial
	assert_eq(pane.shader, StructureMaterials.LANTERN_SHADER)


func test_a_pennant_has_corners_between_its_pole_and_its_tip_to_bend() -> void:
	var parts := StructureGeometry.build_one(
		_doc,
		Structure.make(
			1,
			"core:bartizan_keep",
			PackedVector2Array([Vector2(0, 0), Vector2(8, 0), Vector2(8, 8), Vector2(0, 8)]),
			3
		)
	)
	var table: PackedStringArray = parts.tag_table
	assert_eq(parts.problem, "", "the keep builds")
	var found := 0
	for mesh: Dictionary in parts.meshes:
		if mesh.kind != StructureCloth.KIND:
			continue
		var vertices: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = mesh.arrays[Mesh.ARRAY_TEX_UV2]
		var tags: PackedInt32Array = mesh.tags
		var reaches := {}
		for v in vertices.size():
			if tags[v] >= 0 and table[tags[v]].ends_with("/cloth") and uv2[v].y > 0.9:
				reaches[snappedf(uv2[v].x, 0.05)] = true
		if not reaches.is_empty():
			found += 1
			assert_gt(reaches.size(), 5, "a pennant's weights step along its length (%d)" % reaches.size())
	assert_gt(found, 0, "a pennant was found on the keep")
