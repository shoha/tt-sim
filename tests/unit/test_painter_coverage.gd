extends GutTest

## Card painter-coverage (docs/systems/painter.md "Coverage"): the wall layers (drawn walls, wall
## rows, the streets' lots, the villages' boundaries) wear the painted structure shader and give
## it back exactly; the trees the painter does not grow (acacia, palm, dead tree) and the desert
## plants are painted by surface; the toon styles' trim has a stand-in.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}

var _container: Node3D = null
var _map: Node3D = null


func before_each() -> void:
	PainterSheet.clear_cache()
	_container = Node3D.new()
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)


func _wall_layer(layer_name: String) -> Node3D:
	var layer := Node3D.new()
	layer.name = layer_name
	_map.add_child(layer)
	return layer


## A `Wall_<id>` node holding one part per name in `names`.
func _wall(layer: Node3D, id: int, names: Array[String]) -> Node3D:
	var wall := Node3D.new()
	wall.name = "Wall_%d" % id
	for part_name in names:
		var instance := MeshInstance3D.new()
		instance.name = part_name
		instance.mesh = BoxMesh.new()
		wall.add_child(instance)
	layer.add_child(wall)
	return wall


func test_a_wall_layers_parts_are_painted_by_name_and_glass_stays_classic() -> void:
	var layer := _wall_layer("AuthoredWalls")
	var names: Array[String] = ["Stone", "Masonry", "Wood", "Roof", "Glass"]
	names.append_array(["Wall_plaster", "Roof_slate", "Door_wood"])
	var wall := _wall(layer, 1, names)
	var before := {}
	for node: Node in wall.get_children():
		before[node] = (node as MeshInstance3D).material_override
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(_map, STATE))
	for node: Node in wall.get_children():
		var override := (node as MeshInstance3D).material_override
		if str(node.name) == "Glass":
			assert_eq(override, before[node], "glass keeps Classic")
			continue
		assert_not_null(override, "%s painted" % node.name)
		assert_true(override.has_meta(PainterBuildings.META), "%s carries the meta" % node.name)
	assert_same(
		(wall.get_node("Wall_plaster") as MeshInstance3D).material_override,
		buildings.material_of("wall_plaster"),
		"a wall's plaster is the structures' plaster stand-in"
	)
	buildings.release()
	for node: Node in wall.get_children():
		assert_eq((node as MeshInstance3D).material_override, before[node], "%s restored" % node.name)
	assert_false(buildings.is_active())


func test_a_wall_built_later_and_a_boundary_layer_are_followed() -> void:
	var buildings := PainterBuildings.new()
	buildings.paint(_map, STATE)
	var layer := _wall_layer("AuthoredWalls")
	var later := _wall(layer, 2, ["Masonry", "Roof_tile"])
	for node: Node in later.get_children():
		assert_not_null((node as MeshInstance3D).material_override, "%s painted by the event" % node.name)
	var crossings := _wall_layer("AuthoredCrossings")
	var plank := _wall(crossings, 4, ["Wood", "Stones"])
	for node: Node in plank.get_children():
		assert_not_null((node as MeshInstance3D).material_override, "crossing %s painted" % node.name)
	var boundaries := _wall_layer("AuthoredBoundaries")
	var piers := _wall(boundaries, 3, ["Masonry"])
	assert_not_null((piers.get_child(0) as MeshInstance3D).material_override, "the boundary layer too")
	buildings.release()
	assert_null((later.get_child(0) as MeshInstance3D).material_override)
	assert_null((piers.get_child(0) as MeshInstance3D).material_override)


func test_wall_part_keys() -> void:
	assert_eq(PainterBuildings.wall_part_key("Stone"), "wall_stone")
	assert_eq(PainterBuildings.wall_part_key("Masonry"), "wall_masonry")
	assert_eq(PainterBuildings.wall_part_key("Wood"), "trim_wood")
	assert_eq(PainterBuildings.wall_part_key("Roof"), "roof_wood")
	assert_eq(PainterBuildings.wall_part_key("Wall_brick"), "wall_brick")
	assert_eq(PainterBuildings.wall_part_key("Roof_thatch"), "roof_thatch")
	assert_eq(PainterBuildings.wall_part_key("Door_wood"), "door_wood")
	for part in ["Stones", "Arch", "Ford"]:
		assert_eq(PainterBuildings.wall_part_key(part), "wall_stone", "a crossing's %s" % part)
	assert_eq(PainterBuildings.wall_part_key("Glass"), "")
	assert_eq(PainterBuildings.wall_part_key("Collision"), "")
	assert_eq(PainterBuildings.wall_part_key("Wall_unheard_of"), "")


func test_the_toon_styles_trim_has_a_stand_in_kind() -> void:
	var keys := ["wall_trim", "frame_trim", "door_trim", "trim_plaster", "frame_plaster"]
	keys.append_array(["frame_stone", "ornament_wood", "ornament_bark", "ornament_cloth"])
	keys.append("canopy_leaf")
	for classic in ["ornament_glass", "ornament_metal", "door_metal"]:
		assert_true(PainterBuildings.kind_of(classic).is_empty(), "%s stays Classic" % classic)
	for key in keys:
		assert_false(PainterBuildings.kind_of(key).is_empty(), "%s is painted" % key)


func test_trees_the_painter_does_not_grow_are_painted_by_surface() -> void:
	var acacia := PainterPlantRoles.of("savanna_summer_s1/Tree_Acacia_v0", "tree")
	assert_false(acacia.is_empty(), "an acacia is no longer left Classic")
	assert_true(bool(acacia.get("by_surface", false)))
	var bark := ORMMaterial3D.new()
	bark.resource_name = "Tree_Acacia_v0_Bark"
	var leaf := ORMMaterial3D.new()
	leaf.resource_name = "Tree_Acacia_v0_Leaf"
	assert_eq(PainterPlantRoles.for_surface(acacia, bark)["role"], "bark")
	assert_eq(PainterPlantRoles.for_surface(acacia, bark)["kind"], PainterPlantRoles.KIND_SOLID)
	assert_eq(PainterPlantRoles.for_surface(acacia, leaf)["role"], "leaf")
	assert_eq(PainterPlantRoles.for_surface(acacia, null)["role"], "leaf")
	for id in ["Tree_Palm_v0", "Tree_DeadTree_v0"]:
		var entry := PainterPlantRoles.of("savanna_summer_s1/" + id, "tree")
		assert_true(bool(entry.get("by_surface", false)))
	var oak := PainterPlantRoles.of("grassland_meadow_summer_s1/Tree_Oak_v0", "tree")
	assert_eq(oak, {}, "a grown tree")
	var plain := PainterPlantRoles.of("x/Rock_Medium", "")
	assert_eq(PainterPlantRoles.for_surface(plain, bark), plain, "other entries come back as is")


func test_the_desert_plants_are_not_green_leaf_crowns() -> void:
	var cactus := PainterPlantRoles.of("rocky_badlands_summer_s1/Tree_Cactus_v0", "tree")
	assert_eq(cactus["role"], PainterPlantRoles.CACTUS_ROLE)
	assert_eq(cactus["kind"], PainterPlantRoles.KIND_SOLID)
	var barrel := PainterPlantRoles.of("rocky_badlands_summer_s1/Bush_BarrelCactus_v0", "tree")
	assert_eq(barrel["role"], PainterPlantRoles.CACTUS_ROLE, "a barrel cactus is not a bush")
	var agave := PainterPlantRoles.of("rocky_badlands_summer_s1/Bush_Agave_v0", "tree")
	assert_eq(agave["role"], "cactus")
	var dead := PainterPlantRoles.of("rocky_badlands_summer_s1/Bush_DeadShrub_v0", "tree")
	assert_eq(dead["role"], "bark")
	assert_eq(
		PainterPlantRoles.of("grassland_meadow_summer_s1/Bush_Bush_v0", "tree")["kind"],
		PainterPlantRoles.KIND_CROWN,
		"a real bush stays a crown"
	)
