extends GutTest

## Ground layers bound ahead of their first use (GroundLayerBinding.prepare, perfaudit card
## authfirst): a picked Paint tile, biome, Water tool or Dress kit uploads its surfaces' maps one
## per step into the slot the next append takes, so the edit's retable appends nothing and reads
## no image; nothing routes to a prepared layer, so the ground's tables stay as they were; a
## retable in the middle restarts the slot; the capacity step is never crossed.

const FOREST := "temperate_forest_summer_s1"
const ROUTING_UNIFORMS: PackedStringArray = ["biome_rules", "biome_extra", "paint_layer"]


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _terrain() -> AuthoredTerrain:
	var doc := MapDocument.create_flat(Vector2i(30, 30), "grass_birch", "test", 5)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(1)
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(255)
	doc.biome_slots = slots
	doc.biome_density = density
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	return terrain


## Runs prepare steps until none is left (bounded).
func _finish(binding: GroundLayerBinding) -> int:
	var steps := 0
	while binding.is_preparing() and steps < 400:
		binding.prepare_step()
		steps += 1
	return steps


func _paint(terrain: AuthoredTerrain, surface: String) -> void:
	var doc := terrain.document
	var id := doc.ensure_surface(surface)
	for z in 6:
		for x in 6:
			doc.set_surface_weight(doc.sample_index(x, z), id, 200)
	terrain.update_ground_region(Rect2i(0, 0, 6, 6))


func _routing(terrain: AuthoredTerrain) -> Array:
	var out := []
	for uniform in ROUTING_UNIFORMS:
		out.append(terrain.get_material().get_shader_parameter(uniform))
	return out


## An unbound surface the palette can draw.
func _unbound(terrain: AuthoredTerrain, skip: PackedStringArray = []) -> String:
	var bound := terrain.ground_layers()
	for surface: String in ["cobblestone", "gravel", "flagstone", "dirt_path", "sand"]:
		if not bound.has(surface) and not skip.has(surface):
			if GroundPalette.surface_available(surface, PaletteLibrary.DEFAULT_ROOT):
				return surface
	return ""


func test_a_prepared_surface_is_bound_before_its_first_dab() -> void:
	var terrain := _terrain()
	var binding := terrain.layer_binding()
	var surface := _unbound(terrain)
	assert_ne(surface, "", "an unbound palette surface")
	var before := terrain.ground_layers()
	var albedo: Texture2DArray = binding.arrays.textures.albedo
	var routing := _routing(terrain)
	terrain.prepare_surfaces(PackedStringArray([surface, surface, before[0], "no_such_surface"]))
	assert_true(binding.is_preparing())
	assert_eq(_finish(binding), GroundLayerArrays.KINDS.size(), "one step per map")
	var prepared := before.duplicate()
	prepared.append(surface)
	assert_eq(terrain.ground_layers(), prepared, "appended once, after the bound list")
	assert_eq(binding.arrays.layers, prepared, "the arrays hold it")
	assert_eq(binding.arrays.textures.albedo, albedo, "uploaded in place")
	assert_eq(_routing(terrain), routing, "nothing routes to it: the ground draws as before")
	_paint(terrain, surface)
	assert_eq(terrain.ground_layers(), prepared, "the first dab appends nothing")
	assert_eq(binding.arrays.layers, prepared, "and reads no image")
	var id := terrain.document.surface_ids.find(surface)
	assert_eq(binding.painted_layer(id), prepared.size() - 1, "the dab draws the prepared layer")


func test_a_retable_mid_preparation_takes_the_slot_and_the_prepare_moves_on() -> void:
	var terrain := _terrain()
	var binding := terrain.layer_binding()
	var first := _unbound(terrain)
	var second := _unbound(terrain, PackedStringArray([first]))
	assert_ne(second, "", "two unbound palette surfaces")
	terrain.prepare_surfaces(PackedStringArray([first]))
	binding.prepare_step()
	binding.prepare_step()
	# The author paints another surface before the prepare is done: its append takes the slot.
	_paint(terrain, second)
	_finish(binding)
	var layers := terrain.ground_layers()
	assert_eq(layers.find(second), layers.size() - 2, "the painted surface first: %s" % layers)
	assert_eq(layers.find(first), layers.size() - 1, "the prepared one after it")
	assert_eq(binding.arrays.layers, layers)


func test_preparing_never_crosses_the_capacity_step() -> void:
	var terrain := _terrain()
	var binding := terrain.layer_binding()
	var albedo: Texture2DArray = binding.arrays.textures.albedo
	var every := PackedStringArray(PaletteLibrary.surfaces(PaletteLibrary.DEFAULT_ROOT).keys())
	terrain.prepare_surfaces(every)
	_finish(binding)
	assert_eq(terrain.ground_layers().size(), binding.arrays.capacity, "filled to the step")
	assert_eq(binding.arrays.capacity, 16, "and no further")
	assert_eq(binding.arrays.textures.albedo, albedo, "never recreated")
	assert_false(binding.is_preparing())


func test_the_water_tool_prepares_the_first_waters_layers() -> void:
	var terrain := _terrain()
	var binding := terrain.layer_binding()
	var doc := terrain.document
	var dry := terrain.ground_layers()
	terrain.prepare_water()
	_finish(binding)
	var prepared := terrain.ground_layers()
	assert_true(prepared.size() > dry.size(), "bed or shore layers prepared: %s" % prepared)
	var albedo: Texture2DArray = binding.arrays.textures.albedo
	var field := PackedByteArray()
	field.resize(doc.sample_count() * WaterDressing.CHANNELS)
	doc.water_dressing = field
	terrain.refresh_water_dressing()
	assert_eq(terrain.ground_layers(), prepared, "the first water appends nothing")
	assert_eq(binding.arrays.textures.albedo, albedo)
	terrain.prepare_water()
	assert_false(binding.is_preparing(), "a map with water prepares none")
