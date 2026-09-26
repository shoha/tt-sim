extends GutTest

## ScatterGlbUtils.build_scatter() with a caller-supplied resolver, independent of both
## the GLB wrapper (test_glb_utils_scatter_instances.gd) and PaletteLibrary
## (test_palette_library.gd).

const ROW := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]


func test_the_resolver_is_called_once_per_buildable_key_only() -> void:
	var parent := Node3D.new()
	var calls: Array[String] = []
	var resolve := func(key: String) -> Dictionary:
		calls.append(key)
		return {"mesh": BoxMesh.new(), "wind_category": ""}
	var groups := {
		"Good": [ROW, ROW],
		"OnlyMalformed": [["bad"]],
		"Empty": [],
		"NotAnArray": "rows",
	}
	var built := ScatterGlbUtils.build_scatter(parent, groups, resolve)
	assert_eq(calls.size(), 1)
	assert_eq(calls[0], "Good")
	assert_eq(built.size(), 1)
	parent.free()


func test_an_empty_or_meshless_template_skips_the_species() -> void:
	var parent := Node3D.new()
	var resolve := func(key: String) -> Dictionary:
		match key:
			"Skip":
				return {}
			"NoMesh":
				return {"mesh": "not a mesh", "wind_category": "grass"}
		return {"mesh": BoxMesh.new(), "wind_category": "grass"}
	var groups := {"Skip": [ROW], "NoMesh": [ROW], "Kept": [ROW]}
	ScatterGlbUtils.build_scatter(parent, groups, resolve)
	assert_eq(parent.get_child_count(), 1)
	assert_not_null(parent.get_node_or_null("Kept_MultiMesh"))
	parent.free()


func test_the_category_is_taken_from_the_resolver_not_the_name() -> void:
	# "OakTree" would classify as "tree"; the resolver's word wins.
	var parent := Node3D.new()
	var resolve := func(_key: String) -> Dictionary:
		return {"mesh": BoxMesh.new(), "wind_category": "grass"}
	ScatterGlbUtils.build_scatter(parent, {"OakTree": [ROW]}, resolve)
	var chunk := parent.get_node_or_null("OakTree_MultiMesh") as MultiMeshInstance3D
	assert_eq(chunk.get_meta("wind_foliage_category"), "grass")
	parent.free()


func test_the_node_stem_defaults_to_a_node_safe_key() -> void:
	var parent := Node3D.new()
	var resolve := func(_key: String) -> Dictionary:
		return {"mesh": BoxMesh.new(), "wind_category": ""}
	ScatterGlbUtils.build_scatter(parent, {"pack_s1/Rock.001": [ROW]}, resolve)
	assert_not_null(parent.get_node_or_null("pack_s1_Rock_001_MultiMesh"))
	parent.free()
