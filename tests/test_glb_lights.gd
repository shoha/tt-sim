extends Control
## Test scene for verifying GLB light imports
## Run this scene directly (F6 in editor) to test

@onready var path_input: LineEdit = %PathInput
@onready var load_button: Button = %LoadButton
@onready var output_text: RichTextLabel = %OutputText
@onready var viewport_3d: SubViewport = %Viewport3D
@onready var preview_container: Node3D = %PreviewContainer
@onready var intensity_slider: HSlider = %IntensitySlider
@onready var intensity_label: Label = %IntensityLabel

var loaded_scene: Node3D = null
var original_light_energies: Dictionary = {} # Light node -> original energy


func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	intensity_slider.value_changed.connect(_on_intensity_changed)
	
	# Set default test path
	path_input.text = "user://levels/test_lights/map.glb"
	
	# Initialize intensity label
	_update_intensity_label()
	
	_log("[b]GLB Light Import Test[/b]")
	_log("Enter a path to a GLB file and click 'Load & Test'")
	_log("")
	_log("[i]Tip: In Blender, use 'Unitless' lighting mode for 1:1 intensity matching[/i]")
	_log("[i]For 'Standard' mode exports, use lower scale values (0.001 - 0.01)[/i]")
	_log("")


func _on_load_pressed() -> void:
	var path = path_input.text.strip_edges()
	if path.is_empty():
		_log("[color=red]Error: Please enter a GLB path[/color]")
		return
	
	_log("")
	_log("=" .repeat(50))
	_log("[b]Loading: %s[/b]" % path)
	_log("=" .repeat(50))
	
	# Check if file exists
	if not FileAccess.file_exists(path):
		_log("[color=red]Error: File not found: %s[/color]" % path)
		_log("")
		_log("For user:// paths, the full path is:")
		_log("  %s" % ProjectSettings.globalize_path(path))
		return
	
	# Clean up previous scene
	if loaded_scene:
		loaded_scene.queue_free()
		loaded_scene = null
	
	# Load the GLB
	var scene = GlbUtils.load_glb(path)
	if not scene:
		_log("[color=red]Error: Failed to load GLB[/color]")
		return
	
	_log("[color=green]GLB loaded successfully![/color]")
	_log("")
	
	# Analyze the scene
	var stats = _analyze_scene(scene)
	
	# Print results
	_log("[b]--- Node Tree ---[/b]")
	_print_node_tree(scene, 0)
	
	_log("")
	_log("[b]--- Summary ---[/b]")
	_log("Total nodes: %d" % stats.total_nodes)
	_log("MeshInstance3D: %d" % stats.mesh_instances)
	_log("Cameras: %d" % stats.cameras)
	_log("AnimationPlayers: %d" % stats.animation_players)
	
	if stats.lights.size() > 0:
		_log("")
		_log("[color=green][b]*** LIGHTS FOUND (%d) ***[/b][/color]" % stats.lights.size())
		for light_info in stats.lights:
			_log("  [color=yellow]%s[/color]" % light_info)
		_log("")
		_log("[color=green]SUCCESS: GLB light import is working![/color]")
	else:
		_log("")
		_log("[color=orange][b]*** NO LIGHTS FOUND ***[/b][/color]")
		_log("")
		_log("If your GLB should have lights, check:")
		_log("  1. Blender: 'Punctual Lights' enabled in glTF export")
		_log("  2. The GLB uses KHR_lights_punctual extension")
		_log("  3. Lights exist in the Blender scene before export")
	
	# Add to 3D preview
	loaded_scene = scene
	preview_container.add_child(scene)
	
	# Store original light energies for intensity scaling
	_store_original_light_energies(scene)
	
	# Apply current intensity scale
	_apply_intensity_scale(intensity_slider.value)
	
	# Center camera on scene
	_center_camera_on_scene(scene)
	
	if stats.lights.size() > 0:
		_log("")
		_log("[i]Use the Intensity Scale slider to adjust light brightness.[/i]")
		_log("[i]Note the value when it looks correct - use that in level.json[/i]")


func _analyze_scene(node: Node, stats: Dictionary = {}) -> Dictionary:
	if stats.is_empty():
		stats = {
			"total_nodes": 0,
			"mesh_instances": 0,
			"lights": [],
			"cameras": 0,
			"animation_players": 0
		}
	
	stats.total_nodes += 1
	
	if node is Light3D:
		var light_type = node.get_class()
		var light_desc = "%s '%s' (color: %s, energy: %.2f)" % [
			light_type, 
			node.name, 
			node.light_color,
			node.light_energy
		]
		stats.lights.append(light_desc)
	elif node is MeshInstance3D:
		stats.mesh_instances += 1
	elif node is Camera3D:
		stats.cameras += 1
	elif node is AnimationPlayer:
		stats.animation_players += 1
	
	for child in node.get_children():
		_analyze_scene(child, stats)
	
	return stats


func _print_node_tree(node: Node, depth: int) -> void:
	var indent = "  ".repeat(depth)
	var node_class = node.get_class()
	var extra = ""
	
	if node is Light3D:
		extra = " [color=yellow]** LIGHT **[/color]"
	elif node is MeshInstance3D:
		extra = " [color=cyan](mesh)[/color]"
	
	_log("%s%s (%s)%s" % [indent, node.name, node_class, extra])
	
	for child in node.get_children():
		_print_node_tree(child, depth + 1)


func _center_camera_on_scene(scene: Node3D) -> void:
	# Get AABB of the scene
	var aabb = _get_combined_aabb(scene)
	if aabb.size == Vector3.ZERO:
		return
	
	var center = aabb.get_center()
	var scene_size = aabb.size.length()
	
	# Position camera to view the scene
	var camera = viewport_3d.get_node_or_null("Camera3D") as Camera3D
	if camera:
		camera.position = center + Vector3(scene_size * 0.5, scene_size * 0.5, scene_size * 0.5)
		camera.look_at(center)


func _get_combined_aabb(node: Node, aabb: AABB = AABB()) -> AABB:
	if node is MeshInstance3D and node.mesh:
		var mesh_aabb = node.mesh.get_aabb()
		mesh_aabb = node.global_transform * mesh_aabb
		if aabb.size == Vector3.ZERO:
			aabb = mesh_aabb
		else:
			aabb = aabb.merge(mesh_aabb)
	
	for child in node.get_children():
		aabb = _get_combined_aabb(child, aabb)
	
	return aabb


func _log(text: String) -> void:
	output_text.append_text(text + "\n")
	# Also print to console for debugging
	print(text.replace("[b]", "").replace("[/b]", "").replace("[color=green]", "").replace("[color=red]", "").replace("[color=yellow]", "").replace("[color=orange]", "").replace("[color=cyan]", "").replace("[/color]", "").replace("[i]", "").replace("[/i]", ""))


func _update_intensity_label() -> void:
	var value = intensity_slider.value
	intensity_label.text = "Intensity Scale: %.4f" % value


func _on_intensity_changed(value: float) -> void:
	_update_intensity_label()
	_apply_intensity_scale(value)


func _apply_intensity_scale(intensity_scale: float) -> void:
	# Apply the scale factor to all lights relative to their original energies
	for light in original_light_energies:
		if is_instance_valid(light):
			light.light_energy = original_light_energies[light] * intensity_scale


func _store_original_light_energies(node: Node) -> void:
	original_light_energies.clear()
	_find_and_store_lights(node)


func _find_and_store_lights(node: Node) -> void:
	if node is Light3D:
		original_light_energies[node] = node.light_energy
	
	for child in node.get_children():
		_find_and_store_lights(child)
