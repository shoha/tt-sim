extends GutTest

## The painted look's buildings (PainterBuildings, painter_structure.gdshader; docs/systems/
## painter.md "Buildings"): painting puts a stand-in on every wall, roof, timber and stone part
## and releasing puts the very same overrides back with the shared Classic materials untouched; a
## new elevation re-tones the same materials; a structure built later is painted by the event;
## leaving Painted through PainterSurfaces restores everything; a map never painted is never
## touched; a tile roof chooses among the sheet's roof tones and every tone is the sheet's.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}
const HOUSES: Array[String] = [
	"core:thatched_cottage", "core:stone_house", "core:half_timber_house"
]

var _container: Node3D = null
var _map: Node3D = null
var _doc: MapDocument = null


func before_each() -> void:
	PainterSheet.clear_cache()
	StructureRecipes.ensure_served()
	_container = Node3D.new()
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)


func _plan(at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in [Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)]:
		out.append(p + at)
	return out


## The three village houses built under the map (AuthoredStructures, built at once).
func _village() -> AuthoredStructures:
	for i in HOUSES.size():
		_doc.structures.append(Structure.make(i + 1, HOUSES[i], _plan(Vector2(i * 9.0 - 9.0, 0)), 5))
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	return structures


## Every MeshInstance3D under `structures`: node -> [its override, its surface material].
func _parts(structures: Node) -> Dictionary:
	var out := {}
	for node: Node in structures.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		out[mi] = [mi.material_override, mi.mesh.surface_get_material(0)]
	return out


func test_painting_swaps_the_parts_and_release_restores_them_exactly() -> void:
	var structures := _village()
	var before := _parts(structures)
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(_map, STATE))
	var painted := 0
	var kept := 0
	for mi: MeshInstance3D in before:
		var surface: Material = before[mi][1]
		assert_eq(mi.mesh.surface_get_material(0), surface, "the shared surface stays")
		if PainterBuildings.kind_of(str(mi.name)).is_empty():
			assert_eq(mi.material_override, before[mi][0], "%s keeps Classic" % mi.name)
			kept += 1
			continue
		var stand_in := mi.material_override as ShaderMaterial
		assert_not_null(stand_in, "%s painted" % mi.name)
		assert_true(stand_in.has_meta(PainterBuildings.META))
		assert_eq(stand_in.shader.resource_path, PainterBuildings.SHADER)
		painted += 1
	assert_gt(painted, 12, "walls, roofs, timber and stone of three houses")
	assert_gt(kept, 6, "panes, door metal, dressing keep Classic")
	for key in ["wall_plaster", "roof_thatch", "roof_tile", "roof_wood", "frame_wood"]:
		assert_not_null(buildings.material_of(key), "%s has a stand-in" % key)
	buildings.release()
	for mi: MeshInstance3D in before:
		assert_eq(mi.material_override, before[mi][0], "%s restored" % mi.name)
		assert_eq(mi.mesh.surface_get_material(0), before[mi][1])
	assert_false(buildings.is_active())


func test_a_new_elevation_retones_the_same_materials() -> void:
	_village()
	var buildings := PainterBuildings.new()
	buildings.paint(_map, STATE)
	var plaster := buildings.material_of("wall_plaster")
	var noon: PackedVector3Array = plaster.get_shader_parameter(&"ramps")
	buildings.paint(_map, {"sheet": "core", "mood": "summer", "elevation": -8.0})
	assert_same(buildings.material_of("wall_plaster"), plaster, "the same material")
	var night: PackedVector3Array = plaster.get_shader_parameter(&"ramps")
	assert_ne(night[1], noon[1], "the mid tone moved with the sun")
	assert_lt(night[1].length(), noon[1].length(), "a night wall is darker than a noon one")
	buildings.release()


func test_a_structure_built_later_is_painted_by_the_event() -> void:
	var structures := _village()
	var buildings := PainterBuildings.new()
	buildings.paint(_map, STATE)
	var count := buildings.painted().size()
	_doc.structures.append(Structure.make(9, "core:stone_house", _plan(Vector2(0, 12)), 7))
	structures.refresh(_doc)
	structures.flush()
	var later := structures.get_structure_node(9)
	assert_not_null(later, "the new structure is built")
	var wall := later.get_node("wall_masonry") as MeshInstance3D
	assert_eq(wall.material_override, buildings.material_of("wall_masonry"), "painted at once")
	assert_gt(buildings.painted().size(), count)
	buildings.release()
	assert_null(wall.material_override, "and released")


func test_structures_made_after_the_first_paint_are_found() -> void:
	var buildings := PainterBuildings.new()
	buildings.paint(_map, STATE)
	assert_eq(buildings.painted().size(), 0, "nothing built yet")
	_village()
	assert_gt(buildings.painted().size(), 0, "the map's new AuthoredStructures is followed")
	buildings.release()


func test_leaving_painted_through_the_surfaces_restores_and_classic_is_untouched() -> void:
	var structures := _village()
	var before := _parts(structures)
	var manager := Node.new()
	manager.add_user_signal(PainterSurfaces.SIGNAL, [{"name": "state", "type": TYPE_DICTIONARY}])
	add_child_autofree(manager)
	var surfaces := PainterSurfaces.new()
	surfaces.attach(manager, _container)
	assert_null(surfaces.buildings(), "never painted: no host made")
	for mi: MeshInstance3D in before:
		assert_eq(mi.material_override, before[mi][0], "Classic untouched")
	manager.emit_signal(PainterSurfaces.SIGNAL, STATE)
	assert_not_null(surfaces.buildings())
	assert_gt((surfaces.buildings() as PainterBuildings).painted().size(), 12)
	manager.emit_signal(PainterSurfaces.SIGNAL, {})
	for mi: MeshInstance3D in before:
		assert_eq(mi.material_override, before[mi][0], "%s restored on leaving" % mi.name)


func test_every_tone_is_the_sheets_and_a_picked_roof_holds_the_roof_tones() -> void:
	var sheet := PainterSheet.load_sheet("core")
	_village()
	var buildings := PainterBuildings.new()
	buildings.paint(_map, STATE)
	var tile: PackedVector3Array = buildings.material_of("roof_tile").get_shader_parameter(
		&"ramps"
	)
	for i in PainterBuildings.PICK_ROLES.size():
		var want := PainterBuildings.ramp(sheet, "summer", PainterBuildings.PICK_ROLES[i], 60.0, "roof")
		assert_eq(tile[i * 6 + 1], want[1], "%s's mid" % PainterBuildings.PICK_ROLES[i])
	var plaster: PackedVector3Array = buildings.material_of("wall_plaster").get_shader_parameter(
		&"ramps"
	)
	assert_eq(plaster[1], PainterBuildings.ramp(sheet, "summer", "plaster", 60.0, "wall")[1])
	var mid := PainterTones.linear(PainterSheet.tone(sheet, "summer", "plaster", 60.0))
	var both := (plaster[1] + plaster[4]) * 0.5
	assert_true(both.distance_to(mid) < 0.05, "the variants' mids sit either side of the role")
	buildings.release()


func test_a_shaded_wall_stays_light_and_timber_never_goes_maroon() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for mood: String in PainterSheet.MOODS:
		for elevation in [60.0, 20.0, 3.0]:
			var ramp := PainterBuildings.ramp(sheet, mood, "plaster", elevation, "wall")
			var wall := PainterSheet.lch_of_color(_srgb(ramp[0]))
			var lit := PainterSheet.lch_of_color(_srgb(ramp[1]))
			assert_gt(
				wall.x / lit.x, 0.58, "%s %d: a shaded lime wash stays light" % [mood, elevation]
			)
			var beam := PainterSheet.lch_of_color(
				_srgb(PainterBuildings.ramp(sheet, mood, "timber", elevation, "timber")[0])
			)
			var hue := beam.z
			assert_true(
				beam.y < 0.03 or (hue > 15.0 and hue < 120.0),
				"%s %d: timber shade h%.0f C%.3f not maroon" % [mood, elevation, hue, beam.y]
			)


func test_a_slate_roofs_lit_variants_stay_one_family() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for mood: String in PainterSheet.MOODS:
		for elevation in [60.0, 20.0, 3.0, -8.0]:
			var ramp := PainterBuildings.ramp(sheet, mood, "roof-slate", elevation, "roof")
			var a := PainterSheet.lch_of_color(_srgb(ramp[2]))
			var b := PainterSheet.lch_of_color(_srgb(ramp[5]))
			var mid := PainterSheet.lch_of_color(_srgb(ramp[1]))
			# Apart in OKLab's colour plane: a turned hue sent them 0.075 apart (teal and pink).
			var apart := (
				Vector2(a.y * cos(deg_to_rad(a.z)), a.y * sin(deg_to_rad(a.z)))
				. distance_to(Vector2(b.y * cos(deg_to_rad(b.z)), b.y * sin(deg_to_rad(b.z))))
			)
			assert_lt(apart, 0.035, "%s %d: lit h%.0f and h%.0f" % [mood, elevation, a.z, b.z])
			assert_gt(a.x, mid.x, "%s %d: lit is lighter than the mid" % [mood, elevation])


func test_a_shaded_lime_wash_stays_warm_by_day() -> void:
	# painter-manner-b: a 1.2 pull read lavender over a facade in shade; a lime wash keeps its hue.
	var sheet := PainterSheet.load_sheet("core")
	for mood: String in ["summer", "dusk", "autumn", "winter"]:
		for elevation in [60.0, 20.0]:
			var ramp := PainterBuildings.ramp(sheet, mood, "plaster", elevation, "wall")
			var shade := PainterSheet.lch_of_color(_srgb(ramp[0]))
			assert_true(
				shade.y < 0.02 or (shade.z > 20.0 and shade.z < 120.0),
				"%s %d: shaded plaster h%.0f C%.3f is not lavender" % [mood, elevation, shade.z, shade.y]
			)


func test_doors_and_shutters_take_the_accents_and_winter_roofs_the_snow() -> void:
	var sheet := PainterSheet.load_sheet("core")
	assert_eq(PainterBuildings.kind_of("door_wood")[3], 3, "a door picks its tone by its paint")
	assert_eq(PainterBuildings.kind_of("opening_wood")[3], 3, "and a shutter")
	_village()
	var buildings := PainterBuildings.new()
	buildings.paint(_map, {"sheet": "core", "mood": "winter", "elevation": 20.0})
	var door := buildings.material_of("door_wood")
	var ramps: PackedVector3Array = door.get_shader_parameter(&"ramps")
	for i in PainterBuildings.ACCENT_ROLES.size():
		var want := PainterBuildings.ramp(
			sheet, "winter", PainterBuildings.ACCENT_ROLES[i], 20.0, "timber"
		)
		assert_eq(ramps[i * 6 + 1], want[1], "%s's mid" % PainterBuildings.ACCENT_ROLES[i])
	var roof := buildings.material_of("roof_thatch")
	assert_gt(float(roof.get_shader_parameter(&"snow")), 0.3, "winter roofs lie under snow")
	assert_eq((roof.get_shader_parameter(&"snow_ramp") as PackedVector3Array).size(), 3)
	buildings.paint(_map, STATE)
	assert_eq(float(roof.get_shader_parameter(&"snow")), 0.0, "no snow in summer")
	buildings.release()


func test_mesh_names_map_to_painted_kinds() -> void:
	assert_eq(PainterBuildings.kind_of("roof_tile")[3], 1, "a tile roof picks its tone")
	assert_eq(PainterBuildings.kind_of("cap_roof_thatch")[0], "roof-thatch", "a mill's cap")
	assert_eq(PainterBuildings.kind_of("roof_plaster")[0], "plaster", "a plaster gable end")
	for classic in ["opening_glass", "door_metal", "ornament_leaf", "dressing_ground", "decor_baked"]:
		assert_true(PainterBuildings.kind_of(classic).is_empty(), "%s keeps Classic" % classic)


func test_the_shader_loads_with_its_uniforms() -> void:
	var shader := load(PainterBuildings.SHADER) as Shader
	assert_not_null(shader)
	var names := []
	for u: Dictionary in shader.get_shader_uniform_list():
		names.append(u["name"])
	for want in ["pattern", "pick", "ramps", "tone_lo", "tone_hi"]:
		assert_has(names, want)


func _srgb(linear: Vector3) -> Color:
	return Color(linear.x, linear.y, linear.z).linear_to_srgb()
