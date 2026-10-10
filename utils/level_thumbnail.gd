class_name LevelThumbnail
extends RefCounted

## The one way a level's card picture is made. A thumbnail is either the frame a viewport
## shows now (capture(): authoring's Save and play's Save level both take the world viewport
## as it is) or, for a map that has never been opened (an import or a replaced map.glb), an
## offscreen render of the map from the table camera's angle (render_glb_async()). Either
## image goes through fit() and LevelManager.save_thumbnail().
##
## fit() scales a frame so it covers 320x180 (LevelManager.THUMBNAIL_SIZE), then crops the
## overflow evenly on both sides, so the centre of the capture is the centre of the card.
##
## The offscreen render needs a real renderer: under the headless dummy renderer (GUT, CI)
## can_render() is false and render_glb_async() returns null, so an import there simply has
## no thumbnail until the level is saved from play or authoring.

## The offscreen render's size: twice the card, so fit() downsamples.
const RENDER_SIZE := Vector2i(640, 360)
## The table camera's angles (game_map.tscn): 45 degrees of yaw, about 22 degrees down.
const YAW_DEG := 45.0
const PITCH_DEG := -22.0
## Room around the map in the offscreen frame, as a factor on its fitted size.
const FRAME_MARGIN := 1.04
## The look of the offscreen stage when the map's extras bring none of their own.
const BACKGROUND := Color(0.62, 0.74, 0.86)
const AMBIENT := Color(0.78, 0.82, 0.9)
const AMBIENT_ENERGY := 0.7
const SUN_COLOR := Color(1.0, 0.96, 0.88)
const SUN_ROTATION_DEG := Vector3(-55.0, 20.0, 0.0)


static func fit(image: Image) -> Image:
	var target := LevelManager.THUMBNAIL_SIZE
	var source := image.duplicate() as Image
	var scale := maxf(
		float(target.x) / float(source.get_width()), float(target.y) / float(source.get_height())
	)
	var scaled_w := maxi(target.x, int(round(source.get_width() * scale)))
	var scaled_h := maxi(target.y, int(round(source.get_height() * scale)))
	source.resize(scaled_w, scaled_h, Image.INTERPOLATE_LANCZOS)
	var origin := Vector2i((scaled_w - target.x) / 2, (scaled_h - target.y) / 2)
	var out := source.get_region(Rect2i(origin, target))
	if out.get_format() != Image.FORMAT_RGB8:
		out.convert(Image.FORMAT_RGB8)
	return out


## The frame `viewport` shows now, or null when there is no viewport, no texture or nothing
## drawn (an empty image, as the dummy renderer gives).
static func capture(viewport: Viewport) -> Image:
	if not is_instance_valid(viewport):
		return null
	var texture := viewport.get_texture()
	if texture == null:
		return null
	var image := texture.get_image()
	return image if image != null and not image.is_empty() else null


## True when this process can draw an offscreen thumbnail (any renderer but the headless
## dummy, GlbUtils.threaded_loads_safe's test).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless"


## Loads the map GLB at `path` (no collision) and renders it offscreen (render_scene_async).
## Null when this process cannot render or the file does not load.
static func render_glb_async(path: String, tree: SceneTree) -> Image:
	if tree == null or not can_render():
		return null
	var loaded := await GlbUtils.load_map_async(path, false)
	if not loaded.success or loaded.scene == null:
		return null
	return await render_scene_async(loaded.scene, tree)


## Renders `map` (a loaded map root, not in the tree; it is freed afterwards) once in its
## own world from the table camera's angle, framed whole, under its own lighting extras or
## a plain daylight stage. Null when nothing was drawn.
static func render_scene_async(map: Node3D, tree: SceneTree) -> Image:
	var viewport := SubViewport.new()
	viewport.name = "LevelThumbnailStage"
	viewport.own_world_3d = true
	viewport.size = RENDER_SIZE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.basis = view_basis()
	viewport.add_child(_environment(GlbUtils.extract_lighting_config(map)))
	viewport.add_child(_sun())
	viewport.add_child(camera)
	viewport.add_child(map)
	tree.root.add_child(viewport)
	# Scatter MultiMeshes and water materials settle as the map enters the tree.
	await tree.process_frame
	# The ground's mesh bounds: the scatter is left out, so the tallest back trees may be
	# cropped at the top (the whole ground reads better than room for every crown).
	var bounds := LevelEnvironmentManager.compute_map_bounds(map)
	var view := frame(bounds, camera.basis, float(RENDER_SIZE.x) / float(RENDER_SIZE.y))
	camera.size = maxf(view.size, 0.1)
	camera.position = view.position
	camera.far = view.far
	camera.current = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := capture(viewport)
	viewport.queue_free()
	return image


## The table camera's rotation (YAW_DEG, PITCH_DEG).
static func view_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(PITCH_DEG), deg_to_rad(YAW_DEG), 0.0))


## Where an orthographic camera with rotation `basis` and `aspect` (width / height) sees all
## of `bounds`: {"size" (the view height), "position", "far"}. Pure.
static func frame(bounds: AABB, basis: Basis, aspect: float) -> Dictionary:
	var right := basis.x.normalized()
	var up := basis.y.normalized()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in 8:
		var corner := bounds.get_endpoint(i)
		var screen := Vector2(corner.dot(right), corner.dot(up))
		low = low.min(screen)
		high = high.max(screen)
	var span := high - low
	var centre := (low + high) * 0.5
	var reach := bounds.size.length() + 10.0
	var depth_centre := bounds.get_center().dot(basis.z.normalized())
	return {
		"size": maxf(span.y, span.x / maxf(aspect, 0.01)) * FRAME_MARGIN,
		"position": right * centre.x + up * centre.y + basis.z.normalized() * (depth_centre + reach),
		"far": reach * 2.0,
	}


static func _environment(lighting: Dictionary) -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = lighting.get("background_color", BACKGROUND)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = lighting.get("ambient_light_color", AMBIENT)
	env.ambient_light_energy = lighting.get("ambient_light_energy", AMBIENT_ENERGY)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = env
	return world


static func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.light_color = SUN_COLOR
	sun.shadow_enabled = true
	sun.rotation_degrees = SUN_ROTATION_DEG
	return sun
