extends GutTest

## The render jobs' `wind freeze` (tools/render_jobs/steady.gd): it zeroes the sway and flutter
## speeds of the plant materials AND the painted trees' `wind_strength`, so two frames of one state
## are pixel-identical outside animated tokens (card painter-perf-cold; the painted trees have no
## speeds, they read TIME times the global wind times wind_strength, and used to move under a
## frozen wind). And the lo-fi grain's clock every capture pins (card painter-pixel-noise).

const Steady := preload("res://tools/render_jobs/steady.gd")
const TREE_SHADERS: Array[String] = [
	PainterTrees.STROKE_SHADER,
	PainterTrees.BLOCKIN_SHADER,
	PainterTrees.STROKE_BARE_SHADER,
	PainterTrees.BLOCKIN_BARE_SHADER,
]

var _root: Node3D = null
var _saved := {}


func before_each() -> void:
	_root = Node3D.new()
	_saved = {}


func after_each() -> void:
	Steady.thaw_wind(_saved)
	_root.free()


func _material(path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(path) as Shader
	return material


func _hold(material: ShaderMaterial) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = BoxMesh.new()
	instance.material_override = material
	_root.add_child(instance)
	return instance


func test_every_painted_tree_shader_declares_wind_strength() -> void:
	for path in TREE_SHADERS:
		var shader := load(path) as Shader
		assert_true(Steady.WIND_SPEEDS.has("wind_strength"), "the freeze names it")
		assert_true(Steady._has_uniform(shader, "wind_strength"), "%s has wind_strength" % path)


func test_freeze_zeroes_a_painted_trees_wind_strength_and_thaw_restores_it() -> void:
	var tree := _material(PainterTrees.STROKE_SHADER)
	tree.set_shader_parameter("wind_strength", 0.16)
	_hold(tree)
	assert_eq(Steady.freeze_wind(_root, _saved), 1)
	assert_eq(float(tree.get_shader_parameter("wind_strength")), 0.0)
	assert_eq(Steady.thaw_wind(_saved), 1)
	assert_eq(float(tree.get_shader_parameter("wind_strength")), 0.16)


func test_freeze_still_zeroes_the_plant_speeds() -> void:
	var plant := ShaderMaterial.new()
	plant.shader = Shader.new()
	plant.shader.code = (
		"shader_type spatial;\nuniform float sway_speed = 1.0;\nuniform float flutter_speed = 2.0;\n"
		+ "void fragment() { ALBEDO = vec3(sway_speed * flutter_speed); }\n"
	)
	plant.set_shader_parameter("sway_speed", 1.0)
	plant.set_shader_parameter("flutter_speed", 2.0)
	_hold(plant)
	Steady.freeze_wind(_root, _saved)
	assert_eq(float(plant.get_shader_parameter("sway_speed")), 0.0)
	assert_eq(float(plant.get_shader_parameter("flutter_speed")), 0.0)
	Steady.thaw_wind(_saved)
	assert_eq(float(plant.get_shader_parameter("sway_speed")), 1.0)
	assert_eq(float(plant.get_shader_parameter("flutter_speed")), 2.0)


func test_the_lofi_shader_declares_the_grain_clock_on_time_by_default() -> void:
	var shader := load("res://shaders/lofi_canvas.gdshader") as Shader
	assert_true(Steady._has_uniform(shader, Steady.GRAIN_CLOCK))
	assert_string_contains(shader.code, "uniform float grain_clock = -1.0;", "the game follows TIME")


func test_pin_grain_holds_the_lofi_grain_clock_for_a_capture() -> void:
	var container := Control.new()
	var lofi := _material("res://shaders/lofi_canvas.gdshader")
	container.material = lofi
	assert_true(Steady.pin_grain(container))
	assert_eq(float(lofi.get_shader_parameter(Steady.GRAIN_CLOCK)), Steady.GRAIN_PIN)
	container.material = null
	assert_false(Steady.pin_grain(container), "no material")
	assert_false(Steady.pin_grain(null), "no container")
	container.free()


func test_a_material_without_wind_uniforms_is_left_alone() -> void:
	var plain := ShaderMaterial.new()
	plain.shader = Shader.new()
	plain.shader.code = (
		"shader_type spatial;\nuniform float other = 3.0;\n"
		+ "void fragment() { ALBEDO = vec3(other); }\n"
	)
	plain.set_shader_parameter("other", 3.0)
	_hold(plain)
	assert_eq(Steady.freeze_wind(_root, _saved), 0)
	assert_eq(float(plain.get_shader_parameter("other")), 3.0)
