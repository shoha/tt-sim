extends Node3D

## Test scene: simulates what a client sees when the host starts a game
## but has NOT loaded a map yet.
##
## Run this scene directly (F6) to see the empty GameMap with placeholder
## visuals. Use the control panel on the right to toggle options and
## experiment with different looks for the "waiting for map" state.
##
## Placeholder options:
##   - Ground plane (grid or solid)
##   - World environment (sky, color, gradient)
##   - Ambient light
##   - "Waiting for DM" overlay text
##   - Fog / atmosphere
##   - Gentle camera idle animation
##
## Set "show_editor" to false in the inspector to disable the control panel
## and all built-in placeholders, giving you a clean GameMap canvas to build
## your own visuals on top of.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")

## When true, shows the control panel and creates all placeholder visuals.
## When false, only the bare GameMap is instantiated — a clean slate.
@export var show_editor: bool = true

# --- Placeholder nodes (injected into the GameMap viewport) ---
var _game_map: GameMap = null
var _ground_plane: MeshInstance3D = null
var _grid_plane: MeshInstance3D = null
var _world_env: WorldEnvironment = null
var _ambient_light: DirectionalLight3D = null
var _viewport_root: SubViewport = null

# --- UI references ---
var _drawer_canvas: CanvasLayer = null
var _drawer: DrawerContainer = null
var _waiting_label_canvas: CanvasLayer = null
var _waiting_label: Label = null
var _waiting_sublabel: Label = null

# --- Animation state ---
var _idle_bob_enabled: bool = true
var _idle_time: float = 0.0


func _ready() -> void:
	_setup_game_map()

	if show_editor:
		_setup_placeholders()
		_build_control_panel()
		_build_waiting_overlay()
		_apply_preset_cozy()


func _process(delta: float) -> void:
	if not show_editor:
		return
	if _idle_bob_enabled and _game_map:
		_idle_time += delta
		# Gentle sine-wave bob on the camera holder
		var holder = _game_map.cameraholder_node
		if holder:
			var base_y = 0.0
			holder.position.y = base_y + sin(_idle_time * 0.4) * 0.15


# ============================================================================
# GameMap Setup
# ============================================================================


func _setup_game_map() -> void:
	_game_map = GAME_MAP_SCENE.instantiate()
	add_child(_game_map)

	# Grab the SubViewport so we can inject 3D placeholder nodes
	_viewport_root = _game_map.world_viewport


# ============================================================================
# Placeholder 3D Elements
# ============================================================================


func _setup_placeholders() -> void:
	if not _viewport_root:
		return

	_create_ground_plane()
	_create_grid_plane()
	_create_world_environment()
	_create_ambient_light()


func _create_ground_plane() -> void:
	_ground_plane = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	_ground_plane.mesh = plane_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.16, 0.22)
	mat.roughness = 0.95
	_ground_plane.material_override = mat
	_ground_plane.position = Vector3.ZERO

	_viewport_root.add_child(_ground_plane)


func _create_grid_plane() -> void:
	# A second plane slightly above the ground with a grid pattern
	_grid_plane = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(60, 60)
	plane_mesh.subdivide_width = 60
	plane_mesh.subdivide_depth = 60
	_grid_plane.mesh = plane_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.32, 0.42, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Use wireframe rendering for grid lines
	mat.wireframe = true
	_grid_plane.material_override = mat
	_grid_plane.position = Vector3(0, 0.005, 0)

	_viewport_root.add_child(_grid_plane)


func _create_world_environment() -> void:
	_world_env = WorldEnvironment.new()

	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.07, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.22, 0.32)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	env.fog_light_color = Color(0.15, 0.13, 0.2)
	env.fog_density = 0.02

	_world_env.environment = env
	_viewport_root.add_child(_world_env)


func _create_ambient_light() -> void:
	_ambient_light = DirectionalLight3D.new()
	_ambient_light.light_color = Color(0.9, 0.85, 1.0)
	_ambient_light.light_energy = 0.4
	_ambient_light.rotation_degrees = Vector3(-45, -30, 0)
	_ambient_light.shadow_enabled = false

	_viewport_root.add_child(_ambient_light)


# ============================================================================
# "Waiting for DM" Overlay
# ============================================================================


func _build_waiting_overlay() -> void:
	_waiting_label_canvas = CanvasLayer.new()
	_waiting_label_canvas.layer = 5
	add_child(_waiting_label_canvas)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_waiting_label_canvas.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_waiting_label = Label.new()
	_waiting_label.text = "Waiting for DM to load a map..."
	_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_label.add_theme_font_size_override("font_size", 28)
	_waiting_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.85, 0.8))
	_waiting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_waiting_label)

	_waiting_sublabel = Label.new()
	_waiting_sublabel.text = "You can move the camera with WASD and scroll to zoom"
	_waiting_sublabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting_sublabel.add_theme_font_size_override("font_size", 16)
	_waiting_sublabel.add_theme_color_override("font_color", Color(0.55, 0.5, 0.65, 0.5))
	_waiting_sublabel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_waiting_sublabel)


# ============================================================================
# Control Panel
# ============================================================================


func _build_control_panel() -> void:
	_drawer_canvas = CanvasLayer.new()
	_drawer_canvas.layer = 10
	add_child(_drawer_canvas)

	# Full-rect host so the drawer can calculate positions from screen size
	var host = Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_canvas.add_child(host)

	# Use the project's DrawerContainer for a proper slide-in/out panel
	_drawer = DrawerContainer.new()
	_drawer.edge = DrawerContainer.DrawerEdge.RIGHT
	_drawer.drawer_width = 270.0
	_drawer.tab_icon = preload("res://assets/icons/ui/Sun.svg")
	_drawer.start_revealed = true
	_drawer.start_open = true
	_drawer.play_sounds = false
	_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(_drawer)  # _ready() fires, content_container is now available

	# Wrap content in a ScrollContainer so all controls are reachable
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer.content_container.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# --- Title ---
	var title = Label.new()
	title.text = "Placeholder Visuals"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Client waiting state"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	# --- Presets ---
	_add_section_label(vbox, "Presets")
	var preset_box = HBoxContainer.new()
	preset_box.add_theme_constant_override("separation", 6)
	vbox.add_child(preset_box)

	_add_button(preset_box, "Cozy", _apply_preset_cozy)
	_add_button(preset_box, "Void", _apply_preset_void)
	_add_button(preset_box, "Parchment", _apply_preset_parchment)

	vbox.add_child(HSeparator.new())

	# --- Ground ---
	_add_section_label(vbox, "Ground Plane")
	_add_checkbox(vbox, "Show ground", true, _on_ground_toggled)
	_add_checkbox(vbox, "Show grid", true, _on_grid_toggled)
	_add_color_picker(vbox, "Ground color", Color(0.18, 0.16, 0.22), _on_ground_color_changed)

	vbox.add_child(HSeparator.new())

	# --- Environment ---
	_add_section_label(vbox, "Environment")
	_add_color_picker(vbox, "Background", Color(0.08, 0.07, 0.12), _on_bg_color_changed)
	_add_color_picker(vbox, "Ambient light", Color(0.25, 0.22, 0.32), _on_ambient_color_changed)
	_add_slider(vbox, "Ambient energy", 0.0, 2.0, 0.6, _on_ambient_energy_changed)
	_add_slider(vbox, "Light energy", 0.0, 2.0, 0.4, _on_light_energy_changed)

	vbox.add_child(HSeparator.new())

	# --- Fog ---
	_add_section_label(vbox, "Fog")
	_add_checkbox(vbox, "Enable fog", false, _on_fog_toggled)
	_add_color_picker(vbox, "Fog color", Color(0.15, 0.13, 0.2), _on_fog_color_changed)
	_add_slider(vbox, "Fog density", 0.0, 0.1, 0.02, _on_fog_density_changed)

	vbox.add_child(HSeparator.new())

	# --- Overlay ---
	_add_section_label(vbox, "Overlay")
	_add_checkbox(vbox, "Show waiting text", true, _on_waiting_text_toggled)
	_add_checkbox(vbox, "Camera idle bob", true, _on_idle_bob_toggled)

	vbox.add_child(HSeparator.new())

	# --- Lo-fi ---
	_add_section_label(vbox, "Lo-fi Filter")
	_add_checkbox(vbox, "Lo-fi enabled", true, _on_lofi_toggled)


# ============================================================================
# Presets
# ============================================================================


func _apply_preset_cozy() -> void:
	# Dark cozy purple tone
	_set_ground_color(Color(0.18, 0.16, 0.22))
	_set_bg_color(Color(0.08, 0.07, 0.12))
	_set_ambient(Color(0.25, 0.22, 0.32), 0.6)
	_set_light(Color(0.9, 0.85, 1.0), 0.4)
	_set_fog(false, Color(0.15, 0.13, 0.2), 0.02)
	_show_ground(true)
	_show_grid(true)


func _apply_preset_void() -> void:
	# Pure dark void - minimal
	_set_ground_color(Color(0.05, 0.05, 0.07))
	_set_bg_color(Color(0.02, 0.02, 0.03))
	_set_ambient(Color(0.1, 0.1, 0.15), 0.3)
	_set_light(Color(0.6, 0.6, 0.8), 0.2)
	_set_fog(true, Color(0.03, 0.03, 0.05), 0.015)
	_show_ground(true)
	_show_grid(false)


func _apply_preset_parchment() -> void:
	# Warm parchment / tabletop feel
	_set_ground_color(Color(0.35, 0.3, 0.22))
	_set_bg_color(Color(0.28, 0.24, 0.18))
	_set_ambient(Color(0.45, 0.38, 0.28), 0.8)
	_set_light(Color(1.0, 0.95, 0.85), 0.6)
	_set_fog(false, Color(0.3, 0.26, 0.2), 0.01)
	_show_ground(true)
	_show_grid(true)


# ============================================================================
# Setters (used by both presets and individual controls)
# ============================================================================


func _set_ground_color(color: Color) -> void:
	if _ground_plane and _ground_plane.material_override:
		(_ground_plane.material_override as StandardMaterial3D).albedo_color = color


func _set_bg_color(color: Color) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.background_color = color


func _set_ambient(color: Color, energy: float) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_color = color
		_world_env.environment.ambient_light_energy = energy


func _set_light(color: Color, energy: float) -> void:
	if _ambient_light:
		_ambient_light.light_color = color
		_ambient_light.light_energy = energy


func _set_fog(enabled: bool, color: Color, density: float) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.fog_enabled = enabled
		_world_env.environment.fog_light_color = color
		_world_env.environment.fog_density = density


func _show_ground(should_show: bool) -> void:
	if _ground_plane:
		_ground_plane.visible = should_show


func _show_grid(should_show: bool) -> void:
	if _grid_plane:
		_grid_plane.visible = should_show


# ============================================================================
# Control Panel Callbacks
# ============================================================================


func _on_ground_toggled(enabled: bool) -> void:
	_show_ground(enabled)


func _on_grid_toggled(enabled: bool) -> void:
	_show_grid(enabled)


func _on_ground_color_changed(color: Color) -> void:
	_set_ground_color(color)


func _on_bg_color_changed(color: Color) -> void:
	_set_bg_color(color)


func _on_ambient_color_changed(color: Color) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_color = color


func _on_ambient_energy_changed(value: float) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_energy = value


func _on_light_energy_changed(value: float) -> void:
	if _ambient_light:
		_ambient_light.light_energy = value


func _on_fog_toggled(enabled: bool) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.fog_enabled = enabled


func _on_fog_color_changed(color: Color) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.fog_light_color = color


func _on_fog_density_changed(value: float) -> void:
	if _world_env and _world_env.environment:
		_world_env.environment.fog_density = value


func _on_waiting_text_toggled(enabled: bool) -> void:
	if _waiting_label_canvas:
		_waiting_label_canvas.visible = enabled


func _on_idle_bob_toggled(enabled: bool) -> void:
	_idle_bob_enabled = enabled
	# Reset position when disabling
	if not enabled and _game_map and _game_map.cameraholder_node:
		_game_map.cameraholder_node.position.y = 0.0


func _on_lofi_toggled(enabled: bool) -> void:
	if _game_map:
		_game_map.set_lofi_enabled(enabled)


# ============================================================================
# UI Helpers
# ============================================================================


func _add_section_label(parent: Control, text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	parent.add_child(label)
	return label


func _add_checkbox(parent: Control, text: String, default: bool, callback: Callable) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = text
	cb.button_pressed = default
	cb.toggled.connect(callback)
	parent.add_child(cb)
	return cb


func _add_slider(
	parent: Control, label_text: String, min_val: float, max_val: float, default: float,
	callback: Callable
) -> HSlider:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(label)

	var value_label = Label.new()
	value_label.text = "%.2f" % default
	value_label.custom_minimum_size.x = 40
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(value_label)

	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.01
	slider.value = default
	slider.custom_minimum_size = Vector2(0, 20)
	slider.value_changed.connect(func(val):
		callback.call(val)
		value_label.text = "%.2f" % val
	)
	parent.add_child(slider)

	return slider


func _add_color_picker(
	parent: Control, label_text: String, default: Color, callback: Callable
) -> ColorPickerButton:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(label)

	var picker = ColorPickerButton.new()
	picker.color = default
	picker.custom_minimum_size = Vector2(60, 26)
	picker.edit_alpha = false
	picker.color_changed.connect(callback)
	hbox.add_child(picker)

	return picker


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn
