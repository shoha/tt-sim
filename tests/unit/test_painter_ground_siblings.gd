extends GutTest

## The painted ground's three materials (PainterSurfaces.siblings(), card
## painter-terrain-dabs-split): the chunks', the skirt's and the small stones' dabs'. The dabs are
## drawn with their own shader (the ground's body with PAINTER_DAB), so the ground's has none of
## their code, and a dab's pixel is the ground at that place only while the dabs' material holds
## every parameter the ground's does.
## This enumerates the ground shader's uniforms and compares the skirt's and the dabs' value of each
## with the ground's (textures by identity) after a paint, a sculpt, a paint stroke, a sun change, a
## mood change (the cliffs' snow) and a biome change. The skirt differs in `skirt` alone.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const BIOMES := ["temperate_forest_summer_s1", "savanna_summer_s1", "rocky_badlands_summer_s1"]
const SURFACES := ["dirt_road_packed", "cliff_rock", "sand_beach", "ash"]
const NAMES := ["ground", "skirt", "dabs"]


func before_each() -> void:
	PainterSheet.clear_cache()


## A 20 m document with biomes and painted surfaces, every sample of them from `rng`.
func _doc(rng: RandomNumberGenerator) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_meadow", "test", 7)
	var n := doc.samples_x() * doc.samples_z()
	doc.biome_ids = PackedStringArray(BIOMES)
	doc.surface_ids = PackedStringArray(SURFACES)
	doc.biome_slots.resize(n)
	doc.biome_density.resize(n)
	doc.surface_weights.resize(n * MapDocument.SURFACE_BYTES)
	_paint(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()), rng, true)
	return doc


## Rewrites the painted surfaces of `rect` at random, and with `biomes` its biome slots and density.
func _paint(doc: MapDocument, rect: Rect2i, rng: RandomNumberGenerator, biomes: bool) -> void:
	var sx := doc.samples_x()
	var n := sx * doc.samples_z()
	var slots := doc.biome_slots
	var density := doc.biome_density
	var weights := doc.surface_weights
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := z * sx + x
			if biomes:
				slots[i] = rng.randi_range(0, BIOMES.size())
				density[i] = rng.randi_range(0, 255)
			for e in 4:
				weights[i * 4 + e] = rng.randi_range(0, SURFACES.size())
				weights[n * 4 + i * 4 + e] = rng.randi_range(0, 255) * (rng.randi() % 2)
	doc.biome_slots = slots
	doc.biome_density = density
	doc.surface_weights = weights


## The uniforms of the ground's shader whose skirt or dabs value is not the ground's.
func _mismatches(surfaces: PainterSurfaces) -> PackedStringArray:
	var siblings := surfaces.siblings()
	var ground := siblings[0]
	var out := PackedStringArray()
	for uniform: Dictionary in ground.shader.get_shader_uniform_list():
		var key := StringName(uniform["name"])
		var want: Variant = ground.get_shader_parameter(key)
		for k in [1, 2]:
			if k == 1 and key == &"skirt":
				continue
			var have: Variant = siblings[k].get_shader_parameter(key)
			var same: bool = (
				is_same(want, have) if want is Object or have is Object else want == have
			)
			if not same:
				out.append("%s %s" % [NAMES[k], key])
	return out


## Brings the ground up to the document after an edit of `rect`, as a frame would.
func _edited(surfaces: PainterSurfaces, terrain: AuthoredTerrain, rect: Rect2i) -> void:
	terrain.ground_edited.emit(rect)
	surfaces._rebuild_zone()
	surfaces.occlusion().call("rebuild")


func test_the_ground_shader_has_no_dab_code_and_the_dabs_have_every_ground_uniform() -> void:
	var names := func(path: String) -> Array:
		return (load(path) as Shader).get_shader_uniform_list().map(
			func(u: Dictionary) -> String: return str(u["name"])
		)
	var ground: Array = names.call(PainterSurfaces.GROUND_SHADER)
	var dab: Array = names.call(PainterSurfaces.DAB_SHADER)
	assert_gt(ground.size(), 50, "the ground's uniforms are listed")
	assert_false(ground.has(String(PainterDabs.LOBES_PARAM)), "the ground's shader has no dab code")
	assert_false(dab.has("dab_line"), "the shade's contact line switch is gone (card dabcost)")
	var extra := dab.filter(func(u: String) -> bool: return not ground.has(u))
	var missing := ground.filter(func(u: String) -> bool: return not dab.has(u))
	extra.sort()
	assert_eq(extra, [String(PainterDabs.LOBES_PARAM)], "the dabs' shader adds its lobes alone")
	assert_eq(missing, [], "and has every uniform of the ground's")


func test_the_skirt_and_the_dabs_hold_every_ground_parameter_through_each_kind_of_change() -> void:
	var container := Node3D.new()
	add_child_autofree(container)
	var map := Node3D.new()
	map.name = "LevelMap"
	container.add_child(map)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var doc := _doc(rng)
	var terrain := AuthoredTerrain.create(doc)
	map.add_child(terrain)
	var surfaces := PainterSurfaces.new()
	assert_true(surfaces.paint(map, STATE))
	var siblings := surfaces.siblings()
	assert_eq(siblings.size(), 3)
	assert_eq(siblings[0], surfaces.ground_material(), "the chunks' first")
	assert_eq(siblings[2], surfaces.dab_material(), "the dabs' last")
	assert_eq(siblings[2].shader.resource_path, PainterSurfaces.DAB_SHADER)
	assert_true(siblings[2] in surfaces.ground_materials(), "the occlusion's writes reach the dabs")
	surfaces.occlusion().call("rebuild")
	assert_eq(_mismatches(surfaces), PackedStringArray(), "painted")
	# A sculpt: a hill in one corner.
	var heights := doc.heights
	var rect := Rect2i(4, 4, 12, 10)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			heights[z * doc.samples_x() + x] += 0.8 + 0.1 * x
	doc.heights = heights
	_edited(surfaces, terrain, rect)
	assert_eq(_mismatches(surfaces), PackedStringArray(), "after a sculpt")
	# A paint stroke (the surfaces alone).
	rect = Rect2i(20, 8, 9, 7)
	_paint(doc, rect, rng, false)
	_edited(surfaces, terrain, rect)
	assert_eq(_mismatches(surfaces), PackedStringArray(), "after a paint stroke")
	# The sun lower, then a winter mood (the cliffs' snow and every tone).
	surfaces.paint(map, {"sheet": "core", "mood": "summer", "elevation": 12.0})
	assert_eq(_mismatches(surfaces), PackedStringArray(), "after a sun change")
	surfaces.paint(map, {"sheet": "core", "mood": "winter", "elevation": 30.0})
	assert_eq(_mismatches(surfaces), PackedStringArray(), "after a mood (snow) change")
	# A biome change over the whole map.
	_paint(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()), rng, true)
	_edited(surfaces, terrain, Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	assert_eq(_mismatches(surfaces), PackedStringArray(), "after a biome change")
	assert_ne(surfaces.dab_material().get_shader_parameter(&"skirt"), true, "the dabs are no skirt")
	surfaces.release()
