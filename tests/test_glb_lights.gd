extends Control
## Test scene for verifying GLB light imports and environment presets
## Run this scene directly (F6 in editor) to test

@onready var path_input: LineEdit = %PathInput
@onready var load_button: Button = %LoadButton
@onready var output_text: RichTextLabel = %OutputText
@onready var viewport_3d: SubViewport = %Viewport3D
@onready var preview_container: Node3D = %PreviewContainer
@onready var intensity_slider: HSlider = %IntensitySlider
@onready var intensity_label: Label = %IntensityLabel
@onready var preset_dropdown: OptionButton = %PresetDropdown
@onready var world_environment: WorldEnvironment = %WorldEnvironment

# Override controls
@onready var ambient_color_picker: ColorPickerButton = %AmbientColorPicker
@onready var ambient_energy_slider: HSlider = %AmbientEnergySlider
@onready var ambient_energy_label: Label = %AmbientEnergyLabel
@onready var fog_enabled_check: CheckBox = %FogEnabledCheck
@onready var fog_density_slider: HSlider = %FogDensitySlider
@onready var fog_density_label: Label = %FogDensityLabel
@onready var fog_color_picker: ColorPickerButton = %FogColorPicker
@onready var glow_enabled_check: CheckBox = %GlowEnabledCheck
@onready var glow_intensity_slider: HSlider = %GlowIntensitySlider
@onready var glow_intensity_label: Label = %GlowIntensityLabel
@onready var copy_json_button: Button = %CopyJsonButton

var loaded_scene: Node3D = null
var original_light_energies: Dictionary = {} # Light node -> original energy
var current_preset: String = "indoor_neutral"
var current_overrides: Dictionary = {}


func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	intensity_slider.value_changed.connect(_on_intensity_changed)
	preset_dropdown.item_selected.connect(_on_preset_selected)
	
	# Connect override controls
	ambient_color_picker.color_changed.connect(_on_ambient_color_changed)
	ambient_energy_slider.value_changed.connect(_on_ambient_energy_changed)
	fog_enabled_check.toggled.connect(_on_fog_enabled_changed)
	fog_density_slider.value_changed.connect(_on_fog_density_changed)
	fog_color_picker.color_changed.connect(_on_fog_color_changed)
	glow_enabled_check.toggled.connect(_on_glow_enabled_changed)
	glow_intensity_slider.value_changed.connect(_on_glow_intensity_changed)
	copy_json_button.pressed.connect(_on_copy_json_pressed)
	
	# Set default test path
	path_input.text = "user://levels/test_lights/map.glb"
	
	# Initialize labels
	_update_intensity_label()
	_update_override_labels()
	
	# Populate preset dropdown
	_populate_preset_dropdown()
	
	_log("[b]GLB Light & Environment Test[/b]")
	_log("Enter a path to a GLB file and click 'Load & Test'")
	_log("")
	_log("[i]Tip: In Blender, use 'Unitless' lighting mode for 1:1 intensity matching[/i]")
	_log("[i]For 'Standard' mode exports, use lower scale values (0.001 - 0.01)[/i]")
	_log("")


func _populate_preset_dropdown() -> void:
	preset_dropdown.clear()
	var presets = EnvironmentPresets.get_preset_names()
	
	for i in range(presets.size()):
		var preset_name = presets[i]
		var description = EnvironmentPresets.get_preset_description(preset_name)
		preset_dropdown.add_item("%s - %s" % [preset_name, description], i)
		preset_dropdown.set_item_metadata(i, preset_name)
	
	# Select "indoor_neutral" by default
	for i in range(preset_dropdown.item_count):
		if preset_dropdown.get_item_metadata(i) == "indoor_neutral":
			preset_dropdown.select(i)
			current_preset = "indoor_neutral"
			_apply_environment()
			_sync_override_controls_from_environment()
			break


func _on_preset_selected(index: int) -> void:
	var preset_name = preset_dropdown.get_item_metadata(index)
	current_preset = preset_name
	current_overrides.clear()
	_apply_environment()
	_sync_override_controls_from_environment()
	_log("")
	_log("[color=cyan]Applied environment preset: %s[/color]" % preset_name)


func _apply_environment() -> void:
	if is_instance_valid(world_environment):
		EnvironmentPresets.apply_to_world_environment(world_environment, current_preset, current_overrides)


func _sync_override_controls_from_environment() -> void:
	if not is_instance_valid(world_environment) or not world_environment.environment:
		return
	
	var env = world_environment.environment
	
	# Sync controls to current environment values
	ambient_color_picker.color = env.ambient_light_color
	ambient_energy_slider.value = env.ambient_light_energy
	fog_enabled_check.button_pressed = env.fog_enabled
	fog_density_slider.value = env.fog_density
	fog_color_picker.color = env.fog_light_color
	glow_enabled_check.button_pressed = env.glow_enabled
	glow_intensity_slider.value = env.glow_intensity
	
	_update_override_labels()


func _update_override_labels() -> void:
	ambient_energy_label.text = "%.2f" % ambient_energy_slider.value
	fog_density_label.text = "%.4f" % fog_density_slider.value
	glow_intensity_label.text = "%.2f" % glow_intensity_slider.value


# Override control handlers
func _on_ambient_color_changed(color: Color) -> void:
	current_overrides["ambient_light_color"] = color
	_apply_environment()


func _on_ambient_energy_changed(value: float) -> void:
	current_overrides["ambient_light_energy"] = value
	ambient_energy_label.text = "%.2f" % value
	_apply_environment()


func _on_fog_enabled_changed(enabled: bool) -> void:
	current_overrides["fog_enabled"] = enabled
	_apply_environment()


func _on_fog_density_changed(value: float) -> void:
	current_overrides["fog_density"] = value
	fog_density_label.text = "%.4f" % value
	_apply_environment()


func _on_fog_color_changed(color: Color) -> void:
	current_overrides["fog_light_color"] = color
	_apply_environment()


func _on_glow_enabled_changed(enabled: bool) -> void:
	current_overrides["glow_enabled"] = enabled
	_apply_environment()


func _on_glow_intensity_changed(value: float) -> void:
	current_overrides["glow_intensity"] = value
	glow_intensity_label.text = "%.2f" % value
	_apply_environment()


func _on_copy_json_pressed() -> void:
	var json_config = {
		"light_intensity_scale": intensity_slider.value,
		"environment_preset": current_preset,
	}
	
	# Only include overrides if there are any
	if current_overrides.size() > 0:
		json_config["environment_overrides"] = EnvironmentPresets.overrides_to_json(current_overrides)
	
	var json_string = JSON.stringify(json_config, "  ")
	DisplayServer.clipboard_set(json_string)
	
	_log("")
	_log("[color=green]Copied to clipboard![/color]")
	_log("[code]%s[/code]" % json_string)


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
