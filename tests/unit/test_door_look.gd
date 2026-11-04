extends GutTest

## A building's doors (card streetdoors, 2026-11-03): the glazing node's door pieces are the DOOR
## role, drawn by the prop material so their paint is kept, never the pane shader that settled a
## blue or green leaf into sky. A door still in the glass kind (an older procgen) stays an opening.


func test_a_glazing_doors_pieces_are_the_door_role() -> void:
	for slot in [
		"front0/door0/leaf",
		"front0/door0/leaf/panel",
		"front0/door0/leaf/panel1",
		"front0/door0/leaf/handle",
		"front0/floor0/bay1/door/case/jamb0",
		"front0/floor0/bay1/door/case/head",
	]:
		assert_eq(StructureLook.role_of_slot("glazing", slot), StructureLook.DOOR, slot)
	for slot in [
		"front0/floor1/bay2/window/pane",
		"front0/floor1/bay2/window/frame/jamb0",
		"front0/floor1/bay2/window/sill",
		"side1/window2/muntin",
	]:
		assert_eq(StructureLook.role_of_slot("glazing", slot), StructureLook.OPENING, slot)
	# A street row's lot path reaches the same role.
	assert_eq(
		StructureLook.role_of_tag_path("street_row_2/left/lot0/glazing_5/front0/door0/leaf"),
		StructureLook.DOOR
	)


func test_a_windows_shutters_are_drawn_like_a_door_and_the_rest_of_the_trim_is_trim() -> void:
	# Card streetprops: a shutter is a painted louvred leaf (its own paint, lit), not a wood board.
	for slot in ["front0/win1/shutter0", "front0/win1/shutter1", "side2/win0/shutter1"]:
		assert_eq(StructureLook.role_of_slot("facade_trim", slot), StructureLook.DOOR, slot)
	var plain: Array[String] = ["front0/win1/sill", "front0/win1/lintel", "front0/door0/step"]
	for slot in plain:
		assert_eq(StructureLook.role_of_slot("facade_trim", slot), StructureLook.TRIM, slot)
	assert_eq(
		StructureLook.role_of_tag_path("street_row_2/left/lot0/facade_trim_4/front0/win1/shutter0"),
		StructureLook.DOOR
	)


func test_a_plank_wall_gets_painted_boards_and_its_trim_does_not() -> void:
	var wall := StructureMaterials.make("wood", StructureLook.WALL, "", "") as ShaderMaterial
	assert_eq(float(wall.get_shader_parameter("board_m")), StructureMaterials.BOARD_M)
	assert_eq(float(wall.get_shader_parameter("board_tex_keep")), StructureMaterials.BOARD_TEX_KEEP)
	var trim := StructureMaterials.make("wood", StructureLook.TRIM, "", "") as ShaderMaterial
	assert_null(trim.get_shader_parameter("board_m"), "trim keeps the plain planks")
	# No palette root here, so the first timber material logs that the palette is empty.
	assert_engine_error(1, "the empty palette is logged once")


func test_a_door_in_the_glass_kind_stays_an_opening() -> void:
	assert_eq(
		StructureLook.material_role(StructureLook.GLASS_KIND, StructureLook.DOOR),
		StructureLook.OPENING,
		"an older procgen's glass leaf keeps its role, so no digest moves"
	)
	for kind in ["wood", "metal"]:
		assert_eq(StructureLook.material_role(kind, StructureLook.DOOR), StructureLook.DOOR, kind)
	assert_eq(StructureLook.ROLES.back(), StructureLook.DOOR, "the new role is last")


func test_a_door_is_drawn_lit_with_its_own_paint() -> void:
	for kind in ["wood", "metal"]:
		var material := StructureMaterials.make(kind, StructureLook.DOOR, "", "") as ShaderMaterial
		assert_not_null(material, kind)
		assert_eq(material.shader, StructureMaterials.ORNAMENT_SHADER, "%s: lit, not a pane" % kind)
		assert_eq(
			material.get_shader_parameter("saturation"), StructureMaterials.DOOR_SATURATION, kind
		)
		assert_eq(material.get_shader_parameter("paint_srgb"), true, "%s: sRGB paint" % kind)
	var prop := StructureMaterials.make("wood", StructureLook.PROP, "", "") as ShaderMaterial
	assert_eq(prop.get_shader_parameter("paint_srgb"), null, "a prop keeps its tuned look")
	var handle := StructureMaterials.make("metal", StructureLook.DOOR, "", "") as ShaderMaterial
	assert_eq(handle.get_shader_parameter("tone"), StructureMaterials.METAL_TONE, "a warm handle")


func test_a_doors_paint_is_kept() -> void:
	# StructurePaint leaves a door's colours as procgen painted them (a wall would be repainted).
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.UP, Vector3.RIGHT])
	var blue := Color(0.23, 0.31, 0.5)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([blue, blue, blue])
	var mesh := {
		"kind": "wood",
		"role": StructureLook.DOOR,
		"arrays": arrays,
		"tags": PackedInt32Array([0, 0, 0]),
	}
	var meshes: Array = [mesh]
	StructurePaint.paint(meshes, PackedInt32Array(), [StructurePaint.palette_of(5, 1)])
	var out: PackedColorArray = (mesh.arrays as Array)[Mesh.ARRAY_COLOR]
	assert_eq(out[0], blue, "the door keeps its blue")
