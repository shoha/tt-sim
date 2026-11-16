extends GutTest

## painter-perf-blockin: the painted trees' crown masses draw with a discard-free camera variant of
## the block-in (PainterTreeFast) and cast their shadow through a twin node. Any discard in a shader
## makes its depth pre-pass and opaque pass run every fragment (no early-z), about 0.6 ms at the
## taiga home view.

const OAK := "temperate_forest_summer_s1/Tree_Oak_v0"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const INCLUDE := "res://painter/shaders/painter_tree.gdshaderinc"
const BLOCKIN_BODY := "res://painter/shaders/painter_tree_blockin_body.gdshaderinc"
const FAST_SHADERS: Array[String] = [PainterTreeFast.SHADER, PainterTreeFast.BARE_SHADER]

var _container: Node3D = null
var _map: Node3D = null
var _fade_before: Array = []


func before_each() -> void:
	PainterSheet.clear_cache()
	_container = Node3D.new()
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)
	_fade_before = [CanopyFade._last_brush, CanopyFade._last_cut]


func after_each() -> void:
	CanopyFade._last_brush = _fade_before[0]
	CanopyFade._last_cut = _fade_before[1]


## A painted oak at (1, 1) in its own cell: the surfaces and the painted trees.
func _painted() -> Array:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	var rows := PackedFloat32Array([1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	scatter.set_cells({Vector2i(0, 0): {OAK: rows}})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var trees := surfaces.trees() as PainterTrees
	trees.complete()
	return [surfaces, trees]


## A shader text with its `#ifndef TREE_FAST ... #endif` regions cut out (and the burn variant's:
## the fast variant is never a burning tree's): what the TREE_FAST variant compiles.
static func _fast_text(text: String) -> String:
	var out := text.replace("\r\n", "\n")
	for marker: String in ["#ifndef TREE_FAST", "#ifdef TREE_BURN"]:
		var from := out.find(marker)
		while from >= 0:
			var to := out.find("#endif", from)
			out = out.substr(0, from) + out.substr(to + 6)
			from = out.find(marker)
	return out


static func _set_window(window: String, value: Vector4) -> void:
	match window:
		"_last_brush":
			CanopyFade._last_brush = value
		_:
			CanopyFade._last_cut = value


func test_the_fast_variants_compile_against_the_tree_uniforms() -> void:
	for path: String in FAST_SHADERS:
		var names: Array = []
		for u: Dictionary in (load(path) as Shader).get_shader_uniform_list():
			names.append(u["name"])
		for wanted: String in ["palette", "role_params", "mass_tex", "tree_tex", "bare", "cast_amount"]:
			assert_has(names, wanted, "%s reads %s" % [path, wanted])


func test_the_fast_block_in_variant_holds_no_discard() -> void:
	var body := _fast_text(FileAccess.get_file_as_string(BLOCKIN_BODY))
	var inc := _fast_text(FileAccess.get_file_as_string(INCLUDE))
	assert_false(body.contains("discard;"), "the body's discards are all in TREE_FAST-off regions")
	assert_false(inc.contains("discard;"), "tree_fades is left out of the fast variant")
	assert_true(
		body.contains("role_params, ivec2(int(v_row + 0.5), 2), 0).w < 0.5"),
		"the disabled-role kill moved to the vertex stage"
	)
	for path: String in FAST_SHADERS:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.contains("discard;"), path)
		assert_true(text.contains("#define TREE_FAST"), path)
	var bare := FileAccess.get_file_as_string(PainterTreeFast.BARE_SHADER)
	assert_true(bare.contains("#define TREE_BARE"), "the bare variant keeps the leaf drop")


## A cell's crown masses draw with the fast material and cast nothing; a twin node over the same
## MultiMesh, SHADOWS_ONLY with the full shader, casts the crown's shadow.
func test_a_cell_draws_its_masses_fast_and_casts_through_a_twin() -> void:
	var made := _painted()
	var trees: PainterTrees = made[1]
	var nodes: Array = trees.cells.values()[0]["nodes"]
	assert_eq(nodes.size(), PainterTreeFast.SHADOW_NODE + 1)
	var camera_node := nodes[0] as MultiMeshInstance3D
	var twin := nodes[PainterTreeFast.SHADOW_NODE] as MultiMeshInstance3D
	assert_eq(camera_node.material_override, trees.fast_material, "the camera masses are fast")
	assert_eq(camera_node.material_override.shader.resource_path, PainterTreeFast.SHADER)
	assert_eq(camera_node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(twin.material_override, trees.materials()[0], "the twin has the full shader")
	assert_eq(twin.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_eq(twin.multimesh, camera_node.multimesh, "one MultiMesh, no second buffer")
	assert_eq(twin.custom_aabb, camera_node.custom_aabb)
	assert_eq(nodes[1].material_override, trees.materials()[1], "the limbs keep the full shader")
	for u: String in ["palette", "role_params", "tree_tex", "mass_tex"]:
		assert_eq(
			trees.fast_material.get_shader_parameter(u),
			trees.materials()[0].get_shader_parameter(u),
			"the fast masses share %s" % u
		)
	made[0].release()


## The fast masses hold no fade discard, so a live canopy fade (an authoring brush's window or
## the Village tool's cut, published with a w above 0) puts the full shader on them, and the
## discard-free one comes back when it ends. Play raises neither, so a play view always draws
## the discard-free masses (the view-centre window that also did was removed 2026-11-16).
func test_a_live_canopy_fade_swaps_the_fast_masses_to_the_full_shader() -> void:
	var made := _painted()
	var trees: PainterTrees = made[1]
	CanopyFade._last_brush = Vector4.ZERO
	CanopyFade._last_cut = Vector4.ZERO
	assert_false(CanopyFade.live(), "no fade live")
	trees.call("_on_frame")
	assert_eq(trees.fast_material.shader.resource_path, PainterTreeFast.SHADER, "play: fast")
	for window: String in ["_last_brush", "_last_cut"]:
		_set_window(window, Vector4(0.0, 0.0, 0.0, 1.0))
		assert_true(CanopyFade.live(), "%s live" % window)
		trees.call("_on_frame")
		assert_eq(trees.fast_material.shader.resource_path, PainterTrees.BLOCKIN_SHADER, window)
		_set_window(window, Vector4.ZERO)
		trees.call("_on_frame")
		assert_eq(trees.fast_material.shader.resource_path, PainterTreeFast.SHADER, window)
	assert_eq(PainterTreeFast.shader_path(true, false), PainterTreeFast.BARE_SHADER)
	assert_eq(PainterTreeFast.shader_path(true, true), PainterTrees.BLOCKIN_BARE_SHADER)
	made[0].release()
