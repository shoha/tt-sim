extends GutTest

## The painted look's village (PainterVillage, painter_prop.gdshader, and the village's field plants
## drawn by PainterSurfaces and PainterTrees; docs/systems/painter.md "Village furnishings"):
## painting puts a stand-in on every prop surface of the baked settlement cells and releasing puts
## the very same materials back, lights and water stay Classic, a cell baked later is painted by the
## event, the tones are the sheet's and follow the mood and the sun, the baked decor plants of a
## structure wear the plants' stand-ins, the village's field plants are drawn like a scatter's, and
## a map never painted is never touched.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}
const WINTER := {"sheet": "core", "mood": "winter", "elevation": 14.0}

var _container: Node3D = null
var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	PainterSheet.clear_cache()
	StructureRecipes.ensure_served()
	_container = Node3D.new()
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _street(editor: AuthoringEditor, from: float = 0.0) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, from),
		Vector3(12, 0, from),
		-1.0,
		{"seed": 5, "side": 2, "preset": 3}
	)


## A market street dressed and baked; the layer.
func _dressed(
	editor: AuthoringEditor, from: float = 0.0, kit: String = "market_town"
) -> AuthoredSettlements:
	var id := editor.settlements.dress(_street(editor, from), kit)
	assert_gt(id, 0)
	var layer := _map.get_node_or_null(NodePath(AuthoredSettlements.NODE_NAME)) as AuthoredSettlements
	assert_not_null(layer, "the layer exists")
	layer.flush()
	return layer


## Every baked surface of `layer`: [mesh, surface, material, its `<role>:<kind>` key].
func _surfaces(layer: AuthoredSettlements) -> Array:
	var out: Array = []
	for child in layer.get_children():
		var cell := child as MeshInstance3D
		if cell == null or not cell.has_meta(AuthoredSettlements.META):
			continue
		for i in cell.mesh.get_surface_count():
			var material := cell.mesh.surface_get_material(i)
			out.append([cell.mesh, i, material, str(material.get_meta(AuthoredSettlements.PART_META, ""))])
	return out


func _is_painted_part(key: String) -> bool:
	var part := key.split(":")
	var classic := PainterVillage.CLASSIC_KINDS.has(part[1]) if part.size() == 2 else true
	return part.size() == 2 and part[0] == StructureLook.PROP and not classic


# --- the furnishings ------------------------------------------------------------------------


func test_painting_puts_stand_ins_on_the_prop_surfaces_and_release_restores_them_exactly() -> void:
	var layer := _dressed(_editor())
	var before := _surfaces(layer)
	assert_gt(before.size(), 4, "a market street has several surfaces")
	var village := PainterVillage.new()
	assert_true(village.paint(_map, STATE))
	var painted := 0
	var kept := 0
	for entry: Array in before:
		var now: Material = (entry[0] as Mesh).surface_get_material(entry[1])
		if _is_painted_part(entry[3]):
			var stand_in := now as ShaderMaterial
			assert_not_null(stand_in, "%s painted" % entry[3])
			var shader := (
				PainterVillage.GLOW_SHADER
				if str(entry[3]).ends_with(StructureGlow.KIND)
				else PainterVillage.PROP_SHADER
			)
			assert_eq(stand_in.shader.resource_path, shader)
			assert_true(stand_in.has_meta(PainterVillage.META))
			painted += 1
		else:
			assert_same(now, entry[2], "%s keeps Classic" % entry[3])
			kept += 1
	assert_gt(painted, 2, "wood, cloth, stone and thatch are painted")
	assert_eq(village.painted_count(false), painted)
	assert_gt(kept, 0, "a lantern's glass keeps Classic")
	village.release()
	for entry: Array in before:
		assert_same(
			(entry[0] as Mesh).surface_get_material(entry[1]), entry[2], "%s restored" % entry[3]
		)
	assert_false(village.is_active())
	assert_eq(village.painted_count(false), 0)


func test_the_lights_and_the_water_of_a_prop_stay_classic_and_the_halo_is_painted() -> void:
	var layer := _dressed(_editor())
	var before := _surfaces(layer)
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	var seen := 0
	var halos := 0
	for entry: Array in before:
		var key: String = entry[3]
		var now := (entry[0] as Mesh).surface_get_material(entry[1])
		if key.ends_with(StructureGlow.KIND):
			# The lantern's halo gets its own painted shader (painter_glow), not the prop's.
			assert_true(now.has_meta(PainterVillage.META), "the halo is painted")
			assert_eq((now as ShaderMaterial).shader.resource_path, PainterVillage.GLOW_SHADER)
			halos += 1
		elif key == "prop:glass" or key.begins_with("water:"):
			assert_false(now.has_meta(PainterVillage.META), "%s is a light or water" % key)
			seen += 1
	assert_gt(seen, 0, "the street has a lantern or a well")
	assert_gt(halos, 0, "the street's lanterns carry a halo")
	village.release()


func test_a_props_wood_is_the_timbers_lifted_toward_honey() -> void:
	var timber := Vector3(0.45, 0.075, 52.0)
	var wood := PainterVillage.prop_wood_middle(timber)
	assert_gt(wood.x, timber.x * 1.3, "lighter")
	assert_gt(wood.y, timber.y, "richer")
	assert_gt(wood.z, timber.z, "turned toward honey")
	var cap := PainterVillage.WOOD_MAX_L + 0.0001
	assert_lte(wood.x, cap, "never past the cap")
	assert_lte(PainterVillage.prop_wood_middle(Vector3(0.9, 0.05, 350.0)).x, cap)
	assert_between(PainterVillage.prop_wood_middle(Vector3(0.3, 0.02, 355.0)).z, 0.0, 360.0)
	assert_lt(
		PainterVillage.prop_wood_middle(Vector3(0.24, 0.015, 30.0)).x,
		wood.x,
		"relative: grimdark's timber stays darker"
	)


func test_a_map_never_painted_keeps_its_classic_materials() -> void:
	var layer := _dressed(_editor())
	for entry: Array in _surfaces(layer):
		var material: Material = entry[2]
		assert_false(material.has_meta(PainterVillage.META), "%s is the layer's own" % entry[3])
		if material is ShaderMaterial:
			assert_ne((material as ShaderMaterial).shader.resource_path, PainterVillage.PROP_SHADER)
	assert_false(PainterVillage.new().is_active())


func test_a_cell_baked_after_the_paint_is_painted_by_the_event() -> void:
	var editor := _editor()
	var layer := _dressed(editor)
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	var count := village.painted_count(false)
	_dressed(editor, 20.0, "farming_hamlet")
	assert_gt(village.painted_count(false), count, "the second street's props are painted")
	for entry: Array in _surfaces(layer):
		if _is_painted_part(entry[3]):
			var now := (entry[0] as Mesh).surface_get_material(entry[1])
			assert_true(now.has_meta(PainterVillage.META), "%s painted" % entry[3])
	village.release()


func test_a_layer_made_after_the_first_paint_is_found() -> void:
	var editor := _editor()
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	assert_eq(village.painted_count(false), 0, "nothing baked yet")
	_dressed(editor)
	assert_gt(village.painted_count(false), 0, "the map's new AuthoredSettlements is followed")
	village.release()


func test_stone_and_thatch_parts_force_their_tone_and_the_rest_follow_the_paint() -> void:
	_dressed(_editor())
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	var made := village.prop_materials()
	assert_true(made.has("free"), "wood and cloth are toned by their paint")
	for key: String in made:
		var want := int(PainterVillage.FORCED.get(key, -1))
		assert_eq((made[key] as ShaderMaterial).get_shader_parameter(&"force_tone"), want, key)
	village.release()


func test_the_tones_are_the_sheets_and_follow_the_mood_and_the_sun() -> void:
	_dressed(_editor())
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	var material := village.prop_materials()["free"] as ShaderMaterial
	var noon: PackedVector3Array = material.get_shader_parameter(&"ramps")
	assert_eq(noon.size(), PainterVillage.RAMP_SLOTS)
	var sheet := PainterSheet.load_sheet("core")
	var beam := PainterSheet.tone_lch(sheet, "summer", "timber", 60.0)
	var middle := PainterVillage.prop_wood_middle(beam)
	var timber := PainterBuildings.ramp(sheet, "summer", "timber", 60.0, "timber", middle)
	assert_eq(noon[1], timber[1], "the wood ramp is the timber's lifted toward honey")
	var plaster := PainterBuildings.ramp(sheet, "summer", "plaster", 60.0, "wall")
	assert_eq(noon[6 * 6 + 1], plaster[1], "the other ramps are the buildings'")
	assert_eq(float(material.get_shader_parameter(&"snow")), 0.0, "no snow in summer")
	village.paint(_map, WINTER)
	assert_same(village.prop_materials()["free"], material, "the same material is re-toned")
	var cold: PackedVector3Array = material.get_shader_parameter(&"ramps")
	assert_ne(cold[1], noon[1], "winter moved the timber")
	assert_gt(float(material.get_shader_parameter(&"snow")), 0.0, "winter lays snow on the up faces")
	village.paint(_map, {"sheet": "core", "mood": "summer", "elevation": -8.0})
	var night: PackedVector3Array = material.get_shader_parameter(&"ramps")
	assert_lt(night[1].length(), noon[1].length(), "a night prop is darker than a noon one")
	village.release()


func test_the_ab_switches_leave_the_props_and_decor_classic() -> void:
	var layer := _dressed(_editor())
	PainterVillage.furnishings = false
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	assert_eq(village.painted_count(false), 0, "furnishings off")
	for entry: Array in _surfaces(layer):
		assert_same((entry[0] as Mesh).surface_get_material(entry[1]), entry[2])
	village.release()
	PainterVillage.furnishings = true


func test_the_prop_paint_rule_sorts_the_recipes_palettes() -> void:
	# The palettes of recipes/props/*.json (wall wood, roof hay, accent, stone, cloth, cream).
	var wood := [Color("#C98B52"), Color("#B97B46"), Color("#D9A261"), Color("#A9714A")]
	for c: Color in wood:
		assert_eq(PainterVillage.tone_of(c), 0, "%s is timber" % c.to_html(false))
	for c: Color in [Color("#EBC45A"), Color("#F2D273"), Color("#E0B04C"), Color("#E8A42B")]:
		assert_eq(PainterVillage.tone_of(c), 2, "%s is thatch" % c.to_html(false))
	for c: Color in [Color("#D8603A"), Color("#C8323C"), Color("#E0707A"), Color("#E0607E")]:
		assert_eq(PainterVillage.tone_of(c), 3, "%s is clay" % c.to_html(false))
	for c: Color in [Color("#4E9E66"), Color("#2E8F5E")]:
		assert_eq(PainterVillage.tone_of(c), 4, "%s is turf" % c.to_html(false))
	for c: Color in [Color("#3F82B8"), Color("#2F63B5"), Color("#8A5CA8"), Color("#1F9AA0")]:
		assert_eq(PainterVillage.tone_of(c), 5, "%s is slate" % c.to_html(false))
	assert_eq(PainterVillage.tone_of(Color("#F6ECD2")), 6, "cream cloth is plaster")
	assert_eq(PainterVillage.tone_of(Color("#8C8C8C")), 1, "grey is stone")


func test_the_shader_loads_with_its_uniforms() -> void:
	var shader := load(PainterVillage.PROP_SHADER) as Shader
	assert_not_null(shader)
	var names := PackedStringArray()
	for uniform: Dictionary in shader.get_shader_uniform_list():
		names.append(str(uniform["name"]))
	for want in ["ramps", "snow", "snow_ramp", "tone_lo", "tone_hi", "force_tone"]:
		assert_true(names.has(want), "uniform %s" % want)
	assert_false(shader.code.contains("discard"), "no discard: a prop's few boxes need none")


func test_painting_adds_no_per_frame_work() -> void:
	_dressed(_editor())
	var tree := get_tree()
	var frames := tree.process_frame.get_connections().size()
	var physics := tree.physics_frame.get_connections().size()
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	assert_eq(tree.process_frame.get_connections().size(), frames, "no process_frame hook")
	assert_eq(tree.physics_frame.get_connections().size(), physics, "no physics_frame hook")
	village.release()


# --- the baked decor plants -----------------------------------------------------------------


## A cottage with ivy and flower boxes asked for, so its plants are baked into decor_baked.
func _decorated_structure(structure_id: int, at: Vector2) -> Structure:
	var plan := PackedVector2Array()
	for p: Vector2 in [Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)]:
		plan.append(p + at)
	var params := StructureOrnaments.with_kinds({}, ["ivy", "flower_boxes", "banner", "vane"])
	return Structure.make(structure_id, "core:cottage", plan, 5 + structure_id, params)


func _decorated() -> AuthoredStructures:
	_doc.structures.append(_decorated_structure(1, Vector2.ZERO))
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	return structures


func test_the_baked_decor_wears_the_plants_stand_ins_and_release_restores_it() -> void:
	var structures := _decorated()
	var baked := structures.get_structure_node(1).get_node_or_null(AuthoredStructures.DECOR_NODE)
	assert_not_null(baked, "the cottage carries baked decor")
	var mesh := (baked as MeshInstance3D).mesh
	var before: Array[Material] = []
	for i in mesh.get_surface_count():
		before.append(mesh.surface_get_material(i))
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	assert_eq(village.painted_count(true), mesh.get_surface_count(), "every decor surface is painted")
	for i in mesh.get_surface_count():
		var stand_in := mesh.surface_get_material(i) as ShaderMaterial
		assert_not_null(stand_in)
		assert_eq(stand_in.shader.resource_path, PainterSurfaces.PLANT_SHADER)
		assert_true(stand_in.has_meta(WindFoliage.META_STAND_IN), "the AA swap leaves it alone")
		assert_eq(stand_in.get_meta(WindFoliage.META_STAND_IN), before[i])
		assert_eq(int(stand_in.get_shader_parameter(&"kind")), PainterPlantRoles.KIND_SOLID)
		assert_eq(
			stand_in.get_shader_parameter(&"mesh_height"),
			(before[i] as ShaderMaterial).get_shader_parameter(&"mesh_height"),
			"the wind keeps its values"
		)
	village.release()
	for i in mesh.get_surface_count():
		assert_same(mesh.surface_get_material(i), before[i], "decor surface %d restored" % i)
	assert_eq(village.painted_count(true), 0)


func test_the_decor_follows_the_season_and_a_structure_built_later_is_painted() -> void:
	var structures := _decorated()
	var village := PainterVillage.new()
	village.paint(_map, STATE)
	var stands := village.decor_materials()
	assert_gt(stands.size(), 0)
	assert_eq(float(stands[0].get_shader_parameter(&"frost")), 0.0, "no snow on summer ivy")
	village.paint(_map, WINTER)
	assert_gt(float(stands[0].get_shader_parameter(&"frost")), 0.0, "winter caps the decor with snow")
	var count := village.painted_count(true)
	_doc.structures.append(_decorated_structure(2, Vector2(0, 12)))
	structures.refresh(_doc)
	structures.flush()
	assert_gt(village.painted_count(true), count, "the new structure's decor is painted at once")
	village.release()


func test_decor_roles_read_the_material_name() -> void:
	var bark := ShaderMaterial.new()
	bark.resource_name = "Planter_Bark"
	var leaf := ShaderMaterial.new()
	leaf.resource_name = "Ivy_Leaf"
	assert_eq(PainterVillage.decor_entry(bark)["role"], "bark")
	assert_eq(PainterVillage.decor_entry(leaf)["role"], "leaf")
	assert_eq(PainterVillage.decor_entry(null)["role"], "leaf")
	assert_eq(PainterVillage.decor_entry(leaf)["kind"], PainterPlantRoles.KIND_SOLID)


# --- the field plants ------------------------------------------------------------------------


func _fields() -> AuthoredFieldPlants:
	var record := Settlement.make(1, "farming_hamlet", 1, 5)
	record.fields.append({"at": Vector2(0, 0), "radius": 8.0, "kind": "orchard"})
	record.fields.append({"at": Vector2(14, 0), "radius": 6.0, "kind": "garden"})
	_doc.settlements.append(record)
	return AuthoredFieldPlants.refresh_map(_map, _doc)


func test_the_field_plants_answer_like_a_scatter() -> void:
	var layer := _fields()
	assert_not_null(layer)
	assert_gt(layer.placed, 8)
	var rows := layer.rows_by_asset()
	var total := 0
	for asset: String in rows:
		var flat: PackedFloat32Array = rows[asset]
		assert_eq(flat.size() % MapDocument.ROW_STRIDE, 0, "%s rows are whole" % asset)
		total += flat.size() / MapDocument.ROW_STRIDE
	assert_eq(total, layer.placed)
	var species := layer.resolved_species()
	assert_gt(species.size(), 2)
	for asset: String in species:
		assert_true(species[asset]["mesh"] is Mesh)
		assert_true(rows.has(asset))


func test_the_orchard_trees_and_the_garden_are_painted_like_the_scatters() -> void:
	_map.add_child(AuthoredTerrain.create(_doc))
	var layer := _fields()
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(_map, STATE))
	assert_true(layer in surfaces.scatters(), "the field plants are a plant source")
	var wanted := PainterTrees.wanted(surfaces.scatters(), _doc)
	assert_gt(wanted.size(), 3, "orchard trees and bushes are rows of the painted trees")
	var hidden := 0
	var stand_ins := 0
	for child in layer.get_children():
		if PainterTreeSpecies.species_for(str(child.name)) != "":
			assert_false((child as Node3D).visible, "%s is drawn by the painted trees" % child.name)
			hidden += 1
	for asset: String in layer.resolved_species():
		if PainterTreeSpecies.species_for(asset) != "":
			continue
		var mesh: Mesh = layer.resolved_species()[asset]["mesh"]
		for i in mesh.get_surface_count():
			if mesh.surface_get_material(i).has_meta(PainterSurfaces.META):
				stand_ins += 1
	assert_gt(hidden, 0, "the oaks' GLB nodes are hidden")
	assert_gt(stand_ins, 0, "the garden's flowers wear the plants' stand-ins")
	surfaces.release()
	for child in layer.get_children():
		assert_true((child as Node3D).visible, "%s shown again" % child.name)
	for asset: String in layer.resolved_species():
		var mesh: Mesh = layer.resolved_species()[asset]["mesh"]
		for i in mesh.get_surface_count():
			assert_false(mesh.surface_get_material(i).has_meta(PainterSurfaces.META), "restored")


func test_a_rebuilt_field_layer_is_painted_again() -> void:
	_map.add_child(AuthoredTerrain.create(_doc))
	var layer := _fields()
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var before := PainterTrees.wanted(surfaces.scatters(), _doc).size()
	_doc.settlements[0].fields.append({"at": Vector2(-14, 0), "radius": 6.0, "kind": "orchard"})
	AuthoredFieldPlants.refresh_map(_map, _doc)
	assert_gt(
		PainterTrees.wanted(surfaces.scatters(), _doc).size(), before, "the new orchard is a tree source"
	)
	assert_true(layer in surfaces.scatters())
	surfaces.release()


func test_the_field_plants_ab_switch_leaves_them_classic() -> void:
	_map.add_child(AuthoredTerrain.create(_doc))
	var layer := _fields()
	PainterVillage.field_plants = false
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	assert_false(layer in surfaces.scatters(), "not a plant source")
	for child in layer.get_children():
		assert_true((child as Node3D).visible, "%s stays Classic" % child.name)
	surfaces.release()
	PainterVillage.field_plants = true


func test_a_field_layer_never_painted_keeps_its_nodes_shown() -> void:
	var layer := _fields()
	for child in layer.get_children():
		assert_true((child as Node3D).visible)
	assert_eq(layer.get_signal_connection_list(&"cells_applied").size(), 0, "nothing follows it")
