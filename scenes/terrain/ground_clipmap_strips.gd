class_name GroundClipmapStrips
extends RefCounted

## The ground clipmap's strip viewports (split from GroundClipmap, card clipmap4): a column and a
## row viewport per bake pass, each TILE_PX by GroundClipmapPlan.PART_TILES tiles, holding a copy
## of every chunk mesh on a copy of the map's ground material with the bake shader
## (authored_ground_bake*.gdshader, the ground include with GROUND_BAKE_OUT; pass 0 lit albedo and
## AO, pass 1 normal and roughness). A strip's part is drawn by pointing both passes' cameras at
## it and rendering once; GroundClipmap then copies the drawn texels into its windows.
##
## A 3D viewport costs its render target plus the renderer's buffers (a strip-sized one measured
## 12 MB at 256 x 2048 and 6 MB at 256 x 1024, 2 MB of it the target; clipmap4), so the viewports
## are half a window long and live only while strips are drawn: make() when a job needs them,
## free_all() when the clipmap has been idle (GroundClipmap.STRIPS_IDLE_S). They are not the
## record of what is baked (the windows are), so making them again needs no rebake; they copy the
## live material when made, and sync_inputs() brings an older copy up to it before a patch.

const BAKE_SHADER := preload("res://shaders/authored_ground_bake.gdshader")
const BAKE_LOOKED_SHADER := preload("res://shaders/authored_ground_bake_looked.gdshader")

## [kind][pass] -> SubViewport, empty while not made.
var viewports: Array = []
var materials: Array[ShaderMaterial] = []
var copies: Array[MeshInstance3D] = []
## Microseconds the last make() took on the CPU (materials, viewports, chunk copies).
var last_make_usec: int = 0
## Times make() ran.
var makes: int = 0


## True while the viewports exist.
func is_made() -> bool:
	return not viewports.is_empty()


## Makes the four viewports as children of `owner` from `terrain`'s chunks and the current state
## of its ground material (nothing without one); with `measure`, GPU timing is on for them.
func make(owner: Node, terrain: AuthoredTerrain, measure: bool) -> void:
	free_all()
	var started := Time.get_ticks_usec()
	var source := terrain.get_material()
	if source == null:
		return
	var look_present: Variant = source.get_shader_parameter("look_present")
	var looked: bool = look_present != null and int(look_present) != 0
	var shader: Shader = BAKE_LOOKED_SHADER if looked else BAKE_SHADER
	for p in 2:
		var mat := source.duplicate() as ShaderMaterial
		mat.shader = shader
		mat.render_priority = 0
		mat.set_shader_parameter("bake_pass", p)
		materials.append(mat)
	var px := GroundClipmapPlan.TILE_PX
	var long_px := GroundClipmapPlan.TILE_PX * GroundClipmapPlan.PART_TILES
	for kind in 2:
		var size := Vector2i(long_px, px)
		if kind == GroundClipmapPlan.Kind.COLUMN:
			size = Vector2i(px, long_px)
		var pair: Array = []
		for p in 2:
			var vp := _viewport("ClipStrip%d%d" % [kind, p], size)
			for cell in terrain.chunk_cells():
				var src := terrain.get_chunk(cell)
				if src == null or src.mesh == null:
					continue
				var mi := MeshInstance3D.new()
				mi.mesh = src.mesh
				mi.material_override = materials[p]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				vp.add_child(mi)
				mi.set_meta("cell", cell)
				copies.append(mi)
			owner.add_child(vp)
			(vp.get_child(0) as Camera3D).current = true
			pair.append(vp)
		viewports.append(pair)
	set_measure(measure)
	makes += 1
	last_make_usec = Time.get_ticks_usec() - started


## Frees the viewports (the next make() starts over from the live ground).
func free_all() -> void:
	for pair: Array in viewports:
		for vp: SubViewport in pair:
			vp.queue_free()
	viewports.clear()
	materials.clear()
	copies.clear()


## Brings the copies up to the live ground: the uniforms of the map's material (its textures are
## shared, but arrays and scalars were copied) and the chunks' current meshes (a rebuilt chunk is a
## new mesh).
func sync_inputs(terrain: AuthoredTerrain) -> void:
	var source := terrain.get_material()
	if source == null or source.shader == null or materials.is_empty():
		return
	for u: Dictionary in source.shader.get_shader_uniform_list():
		var uniform_name := String(u.name)
		if uniform_name.begins_with("clip_") or uniform_name == "bake_pass":
			continue
		var value: Variant = source.get_shader_parameter(uniform_name)
		for mat in materials:
			mat.set_shader_parameter(uniform_name, value)
	for mi: MeshInstance3D in copies:
		var src := terrain.get_chunk(mi.get_meta("cell"))
		if src != null and src.mesh != null and mi.mesh != src.mesh:
			mi.mesh = src.mesh


## Points both passes' cameras of `kind` at `rect` (map-frame metres, a part's PART_TILES tiles)
## from height `cam_y`, and with `draw` renders them once in this frame's draw.
func frame(kind: int, rect: Rect2, cam_y: float, draw: bool) -> void:
	var centre := rect.get_center()
	for vp: SubViewport in viewports[kind]:
		var cam := vp.get_child(0) as Camera3D
		cam.size = rect.size.y
		cam.position = Vector3(centre.x, cam_y, centre.y)
		if draw:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Pass `p` of the `kind` strip, as the windows' sprites read it.
func texture(kind: int, p: int) -> Texture2D:
	return (viewports[kind][p] as SubViewport).get_texture()


## Every viewport's update mode (measurement holds them drawing).
func set_update(mode: SubViewport.UpdateMode) -> void:
	for pair: Array in viewports:
		for vp: SubViewport in pair:
			vp.render_target_update_mode = mode


## GPU timing on or off for every viewport.
func set_measure(on: bool) -> void:
	for pair: Array in viewports:
		for vp: SubViewport in pair:
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), on)


## The measured GPU milliseconds of both passes of the `kind` strip (0 while not made).
func gpu_ms(kind: int) -> float:
	var ms := 0.0
	if kind < viewports.size():
		for vp: SubViewport in viewports[kind]:
			ms += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
	return ms


func _viewport(vp_name: String, size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = vp_name
	vp.own_world_3d = true
	vp.size = size
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.use_debanding = false
	vp.positional_shadow_atlas_size = 0
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 400.0
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	cam.environment = env
	vp.add_child(cam)
	return vp
