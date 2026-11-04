extends GutTest

## The haystack's rope (procgen props_goods.gd `haystack`, tag prop/haystack/tie: bands round a
## mound's tiers, straps over each bale) keeps its own dark brown through every stage of the village
## dress path: StructureGeometry.build_one (merge by kind, split by role, StructurePaint), then
## AuthoredSettlements' variant and SettlementBake.bake (one surface per look kind, vertex colours
## carried). Card hayrope (2026-11-04) chased "the ropes do not show" and found them intact: the
## mint band at the foot of the drums in the old street frames was a barrel trio's hoop.
## This pins the invariant the chase relied on: a PROP-role surface is never repainted from the
## style's accent, whatever its kind ("wood", "accent" or "trim", the kind StructurePaint repaints
## from the style on a building).

const ROPE_LUMA_MAX := 0.3
const HAY_LUMA_MIN := 0.55
const ROPE_TAG := "/tie"
const HAY_TAG := "/hay"

var _map: Node3D = null
var _layer: AuthoredSettlements = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	StructureRecipes.ensure_served()
	_layer = AuthoredSettlements.of_map(_map)


func _luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


## The mean luma of the vertices of `meshes` whose tag path ends with `suffix`, and how many.
func _tagged(meshes: Array, tag_table: PackedStringArray, suffix: String) -> Dictionary:
	var sum := 0.0
	var count := 0
	for mesh: Dictionary in meshes:
		var tags: PackedInt32Array = mesh["tags"]
		var colors: PackedColorArray = mesh["arrays"][Mesh.ARRAY_COLOR]
		for v in colors.size():
			var tag := tags[v] if v < tags.size() else -1
			if tag >= 0 and tag < tag_table.size() and tag_table[tag].ends_with(suffix):
				sum += _luma(colors[v])
				count += 1
	return {"luma": sum / maxf(count, 1), "count": count}


func _built(seed_value: int) -> Dictionary:
	var row := LibraryStructureStore.prop("haystack", seed_value)
	if row.is_empty():
		return {}
	var ref := String(row["ref"])
	var flat := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var parts := StructureGeometry.build_one(
		flat, Structure.make(1, ref, ProcgenProps.footprint(AuthoredSettlements._default_size(ref)), 5)
	)
	return {"ref": ref, "parts": parts}


func test_the_rope_is_dark_and_the_hay_light_after_the_build_and_the_bake() -> void:
	var checked := 0
	for seed_value in 8:
		var built := _built(seed_value)
		if built.is_empty():
			continue
		var parts: Dictionary = built["parts"]
		var tags: PackedStringArray = parts["tag_table"]
		var rope := _tagged(parts["meshes"], tags, ROPE_TAG)
		var hay := _tagged(parts["meshes"], tags, HAY_TAG)
		assert_gt(int(rope["count"]), 0, "variant %d has a rope" % seed_value)
		assert_lt(float(rope["luma"]), ROPE_LUMA_MAX, "variant %d rope is dark" % seed_value)
		assert_gt(float(hay["luma"]), HAY_LUMA_MIN, "variant %d hay is light" % seed_value)
		# The drawn surfaces: every rope vertex is still there, still dark.
		_layer._build_variant(String(built["ref"]))
		var baked := SettlementBake.bake(
			[{"variant": built["ref"], "transform": Transform3D.IDENTITY}] as Array[Dictionary],
			_layer._variants
		)
		var dark := 0
		var light := 0
		for surface: Dictionary in baked:
			for c: Color in surface["arrays"][Mesh.ARRAY_COLOR]:
				if _luma(c) < ROPE_LUMA_MAX:
					dark += 1
				elif _luma(c) > HAY_LUMA_MIN:
					light += 1
		assert_gte(dark, int(rope["count"]), "variant %d drawn rope vertices" % seed_value)
		assert_gt(light, 0, "variant %d drawn hay vertices" % seed_value)
		checked += 1
	assert_gt(checked, 1, "more than one haystack variant is served")


## build_one's steps with the rope's surface renamed before the merge: the paint keeps the colour
## whatever the kind (ACCENT_KIND "trim" is repainted on a building, never on a prop).
func test_a_prop_rope_keeps_its_colour_whatever_its_kind() -> void:
	var ref := "core:haystack"
	var flat := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var structure := Structure.make(
		1, ref, ProcgenProps.footprint(AuthoredSettlements._default_size(ref)), 5
	)
	for kind in ["wood", "accent", StructureLook.ACCENT_KIND]:
		var recipe := StructureRecipes.document(structure.recipe)
		StructureOrnaments.apply(recipe, structure.params, structure.seed_value)
		var evaluator := PlantGraphEvaluator.new(recipe.registry)
		var plant: Variant = evaluator.evaluate_structure(
			recipe, StructureGeometry.inputs_for(flat, structure, recipe), true
		)
		var geometry: PlantGeometry = plant["lods"][0]
		for surface in geometry.surfaces:
			if surface.kind == "wood":
				surface.kind = kind
		var roles := PackedStringArray()
		for path in geometry.tag_table:
			roles.append(StructureLook.role_of_path(recipe, path))
		var meshes: Array = []
		for surface in geometry.merged_by_kind():
			meshes.append_array(StructureGeometry.split_surface(surface, roles))
		var tags := PackedStringArray(geometry.tag_table)
		var before := _tagged(meshes, tags, ROPE_TAG)
		var palette := StructurePaint.palette_of(
			structure.seed_value, structure.id, StructureLook.palette_hints(recipe)
		)
		StructurePaint.paint(meshes, PackedInt32Array(), [palette])
		var after := _tagged(meshes, tags, ROPE_TAG)
		assert_gt(int(after["count"]), 0, "%s: the rope is there" % kind)
		assert_almost_eq(float(after["luma"]), float(before["luma"]), 0.001, "%s: colour kept" % kind)
		assert_lt(float(after["luma"]), ROPE_LUMA_MAX, "%s: still dark" % kind)
