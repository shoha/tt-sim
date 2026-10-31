extends GutTest

## The toon styles in the host (topic toon_look, 2026-10-30): the Roof Cap's roles, the `trim`
## surface kind (the accent tone from palette_accent, drawn by the plaster material), the palette
## lists read from the Output node, saturated roofs that stay saturated, and the eight core rows
## (regional, the two round ones carrying `sides`).
## Summary: docs/systems/structures.md "Toon styles".

const TOONS: Array[String] = [
	"toon_clinic",
	"toon_shop",
	"toon_gym",
	"toon_lab",
	"toon_cafe",
	"toon_cottage",
	"toon_lighthouse",
	"toon_hall",
]

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _hints(id: String) -> Dictionary:
	return StructureLook.palette_hints(StructureRecipes.document("core:" + id))


func test_the_roof_cap_takes_its_role_from_the_slot() -> void:
	assert_eq(StructureLook.role_of_type("roof_cap"), StructureLook.TRIM)
	assert_eq(StructureLook.role_of_slot("roof_cap", "cap/dome"), StructureLook.ROOF)
	assert_eq(StructureLook.role_of_slot("roof_cap", "cap/cone"), StructureLook.ROOF)
	assert_eq(StructureLook.role_of_slot("roof_cap", "cap/inner"), StructureLook.WALL)
	assert_eq(StructureLook.role_of_slot("roof_cap", "cap/glass"), StructureLook.OPENING)
	assert_eq(StructureLook.role_of_slot("roof_cap", "cap/disc"), StructureLook.TRIM)
	assert_eq(StructureLook.role_of_tag_path("a/roof_cap_3/cap/dome"), StructureLook.ROOF)


func test_the_world_gap_nodes_take_their_roles_from_the_slot() -> void:
	# Round Court (tulou): timber that keeps its tone, the panes an opening, the wall a wall.
	assert_eq(StructureLook.role_of_slot("round_court", "court/gallery"), StructureLook.FRAME)
	assert_eq(StructureLook.role_of_slot("round_court", "court/rail"), StructureLook.FRAME)
	assert_eq(StructureLook.role_of_slot("round_court", "court/door"), StructureLook.FRAME)
	assert_eq(StructureLook.role_of_slot("round_court", "court/window"), StructureLook.OPENING)
	assert_eq(StructureLook.role_of_slot("round_court", "court/wall"), StructureLook.WALL)
	# Courtyard Paving fountain: the pool and jet are water, the basin and pillar stay paving.
	assert_eq(StructureLook.role_of_slot("courtyard_yard", "fountain/water"), StructureLook.WATER)
	assert_eq(StructureLook.role_of_slot("courtyard_yard", "fountain/jet"), StructureLook.WATER)
	assert_eq(StructureLook.role_of_slot("courtyard_yard", "fountain/basin"), StructureLook.WALL)
	# Tree Core: the crown is its own material, trunk and rope are painted ornaments.
	assert_eq(StructureLook.role_of_slot("tree_core", "tree/canopy"), StructureLook.CANOPY)
	assert_eq(StructureLook.role_of_slot("tree_core", "tree/trunk"), StructureLook.ORNAMENT)
	assert_eq(StructureLook.material_role("bark", StructureLook.ORNAMENT), StructureLook.ORNAMENT)
	assert_true(StructureMaterials.make("glass", StructureLook.WATER, "", "") is ShaderMaterial)
	assert_true(StructureMaterials.make("leaf", StructureLook.CANOPY, "", "") is ShaderMaterial)


func test_the_palette_lists_are_read_whole() -> void:
	var hints := _hints("toon_clinic")
	assert_eq((hints["roof"] as Array).size(), 3, "the whole roof list")
	assert_eq((hints["accent"] as Array).size(), 2, "the whole accent list")
	assert_eq((hints["wall"] as Array).size(), 3, "every wall tone stays in the list")


func test_a_lot_draws_one_roof_and_one_accent_by_its_seed() -> void:
	var hints := _hints("toon_cottage")
	var accents := {}
	var roofs := {}
	for seed_value in 40:
		var palette := StructurePaint.palette_of(seed_value, 1, hints)
		accents[(palette["accent"] as Color).to_html()] = true
		roofs[(palette["roof"] as Color).to_html(false)] = true
		assert_eq(palette, StructurePaint.palette_of(seed_value, 1, hints), "pure")
	assert_gt(accents.size(), 1, "the seed varies the accent")
	assert_gt(roofs.size(), 3, "and the roof")


func test_an_accent_piece_takes_the_accent_tone_whatever_its_role() -> void:
	var hints := _hints("toon_clinic")
	var palette := StructurePaint.palette_of(5, 1, hints)
	var accent: Color = palette["accent"]
	for role: String in [StructureLook.TRIM, StructureLook.ROOF, StructureLook.WALL]:
		var mesh := _mesh("trim", role, 0.8)
		StructurePaint.paint([mesh], PackedInt32Array(), [palette])
		var painted: Color = (mesh["arrays"][Mesh.ARRAY_COLOR] as PackedColorArray)[0]
		assert_almost_eq(painted.r, minf(accent.r * 0.8, 1.0), 0.001, role)
		assert_almost_eq(painted.b, minf(accent.b * 0.8, 1.0), 0.001, role)


func test_without_a_palette_the_accent_is_a_timber_brown() -> void:
	var palette := StructurePaint.palette_of(5, 1, {})
	var accent: Color = palette["accent"]
	assert_gt(accent.r, accent.b, "warm")


func test_trim_is_drawn_by_the_plaster_material() -> void:
	var material := StructureMaterials.make("trim", StructureLook.TRIM, "", "core")
	assert_true(material is ShaderMaterial)
	assert_eq((material as ShaderMaterial).shader, StructureMaterials.STYLE_WALL_SHADER)
	assert_eq((material as ShaderMaterial).get_shader_parameter("pattern"), 0)
	assert_eq(StructureLook.material_role("trim", StructureLook.ROOF), StructureLook.WALL)


func test_toon_roofs_keep_their_saturation_in_the_painted_mesh() -> void:
	for id in TOONS:
		var ref := "core:" + id
		var plan := _plan(id)
		var parts := StructureGeometry.build_one(_doc, Structure.make(1, ref, plan, 5))
		assert_eq(String(parts["problem"]), "", ref)
		var best := 0.0
		for mesh: Dictionary in parts["meshes"]:
			if mesh["role"] != StructureLook.ROOF or mesh["kind"] != "tile":
				continue
			for c in mesh["arrays"][Mesh.ARRAY_COLOR] as PackedColorArray:
				var srgb := c.linear_to_srgb()
				best = maxf(best, srgb.s * (1.0 if srgb.v > 0.7 else 0.0))
		assert_gt(best, 0.5, "%s keeps a saturated lit roof tone" % ref)


func test_the_rows_are_regional_and_the_round_ones_carry_sides() -> void:
	for id in TOONS:
		var row := LibraryStructureStore.structure("core:" + id)
		assert_false(row.is_empty(), id)
		assert_true("toon" in (row["tags"] as Array), id)
		assert_true(StreetSplit.REGIONAL_TAG in (row["tags"] as Array), "%s is regional" % id)
		assert_true(ProcgenStructureIndex.is_round(row) == (id in ["toon_lab", "toon_lighthouse"]), id)
	assert_eq(ProcgenStructureIndex.sides_of(LibraryStructureStore.structure("core:toon_lab")), 12)
	assert_eq(
		ProcgenStructureIndex.sides_of(LibraryStructureStore.structure("core:toon_lighthouse")), 8
	)


func _plan(id: String) -> PackedVector2Array:
	var row := LibraryStructureStore.structure("core:" + id)
	if ProcgenStructureIndex.is_round(row):
		return StructurePlacement.round_plan(
			Vector2.ZERO, float(row["default_size_m"][0]) * 0.5, 0.0, ProcgenStructureIndex.sides_of(row)
		)
	return StructurePlacement.pin_plan(row)


func _mesh(kind: String, role: String, shade: float) -> Dictionary:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0)])
	var grey := Color(shade, shade, shade)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([grey, grey])
	return {"kind": kind, "role": role, "arrays": arrays, "tags": PackedInt32Array([-1, -1])}
