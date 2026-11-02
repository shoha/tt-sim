class_name TokenPortraits
extends Node

## The pictures on the token pins (TokenMarkers): one small portrait per token model, kept in
## a single atlas texture so every pin is drawn with one material and one draw call.
##
## The atlas is GRID x GRID cells of CELL_PX pixels (1024 px square, 256 pictures); a picture is
## PICTURE_PX square, premultiplied, centred in its cell with a transparent gutter. A picture
## comes from the first of these that exists, by the token's identity (identity_key), and is
## made once and kept:
## - an avatar: AvatarThumbnails' picture of its recipe (the figure on the builder's stage),
##   cropped to the head and chest;
## - a pack token whose pack ships an icon (the roster icons of the built-in folk and beasts
##   packs, a user pack's icons folder): that icon, cropped in a little;
## - any other token (an imported model, a pack without icons): a portrait drawn once from the
##   token's own meshes, orthographic at the game camera's angle and lit like the roster icons
##   (tools/roster/render_icons.gd: one soft key light, a pale ambient), in a small private
##   SubViewport.
## Jobs run one a frame from a queue (the cheap icon decodes a few a frame inside a time budget,
## the draws one at a time), so a map full of tokens never hitches. A token whose picture is not
## ready, failed (no renderer in a headless run, a missing file) or did not fit in the atlas has
## cell_of() -1, and its pin shows the plain disc in the token's colour.
##
## The node is local: nothing here is saved or synced.

enum Kind { ICON, AVATAR, MODEL }

const CELL_PX := 64
const PICTURE_PX := 56
const GRID := 16
const ATLAS_PX := CELL_PX * GRID
## The private viewport's side, drawn at about 3x the picture and reduced.
const RENDER_PX := 160
## The camera of a model portrait: the game camera's azimuth and home pitch, as the roster icons.
const AZIMUTH_RAD := PI / 4.0
const PITCH_RAD := deg_to_rad(21.6)
const MARGIN := 1.12
## How a picture is cropped (portrait_rect): a figure taller than TALL_RATIO of its width is
## cut to a square of HEAD_FRACTION of its height from the top (a roster icon shows the whole
## person, a pin only has room for the face and chest); any other is kept whole with WHOLE_AIR
## round it. SCAN_PX is the size the picture is reduced to for finding the figure.
const TALL_RATIO := 1.12
const HEAD_FRACTION := 0.46
const WHOLE_AIR := 1.04
const SCAN_PX := 48
## Icon jobs per frame stop once they have used this much time, microseconds.
const ICON_BUDGET_US := 2000

## The atlas the pin shader samples.
var atlas: ImageTexture = null

var _image: Image = null
var _dirty := false
var _cells: Dictionary = {}
var _failed: Dictionary = {}
var _queued: Dictionary = {}
var _queue: Array[Dictionary] = []
var _next_cell := 0
var _busy := false
var _stage_viewport: SubViewport = null
var _stage_camera: Camera3D = null


func _init() -> void:
	name = "TokenPortraits"
	_image = Image.create_empty(ATLAS_PX, ATLAS_PX, false, Image.FORMAT_RGBA8)
	atlas = ImageTexture.create_from_image(_image)


# --- pure rules ---


## The key a token's picture is cached under: avatars by their recipe, pack tokens by the pack's
## ids, anything else by its mesh resource (`mesh_id`).
static func identity_key(
	pack_id: String, asset_id: String, variant_id: String, recipe: Dictionary, mesh_id: int
) -> String:
	if not recipe.is_empty():
		return "avatar:" + AvatarThumbnails.key_of(recipe)
	if pack_id != "" and asset_id != "":
		return "pack:%s/%s/%s" % [pack_id, asset_id, variant_id]
	return "mesh:%d" % mesh_id


## The rectangle of `image`'s pixels at least `threshold` opaque (found on a reduced copy, so
## it costs the same for any size; the soft floor shadow of an avatar thumbnail does not count).
## Empty for a picture with none.
static func visible_rect(image: Image, threshold: float = 0.5) -> Rect2i:
	var size := image.get_size()
	var scale := float(SCAN_PX) / float(maxi(size.x, size.y))
	if scale >= 1.0:
		return _opaque_rect(image, threshold, 1.0)
	var reduced := image.duplicate() as Image
	reduced.resize(maxi(1, roundi(size.x * scale)), maxi(1, roundi(size.y * scale)))
	return _opaque_rect(reduced, threshold, 1.0 / scale)


static func _opaque_rect(image: Image, threshold: float, back: float) -> Rect2i:
	var low := Vector2i(image.get_width(), image.get_height())
	var high := Vector2i(-1, -1)
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= threshold:
				low = Vector2i(mini(low.x, x), mini(low.y, y))
				high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0:
		return Rect2i()
	var origin := Vector2i(Vector2(low) * back)
	var end := Vector2i(Vector2(high + Vector2i.ONE) * back)
	return Rect2i(origin, end - origin)


## The square kept for a pin from a picture whose figure fills `content` (see visible_rect): a
## tall figure (a standing person) is cropped to its head and chest, a square or wide one (an
## animal, a block) is kept whole, with a little air; always inside `size`.
static func portrait_rect(content: Rect2i, size: Vector2i) -> Rect2i:
	if content.size.x <= 0 or content.size.y <= 0:
		return Rect2i(Vector2i.ZERO, size)
	var width := content.size.x
	var height := content.size.y
	var side := 0
	var centre_y := 0
	if float(height) > TALL_RATIO * float(width):
		side = roundi(float(height) * HEAD_FRACTION)
		centre_y = content.position.y + side / 2 - roundi(side * 0.06)
	else:
		side = roundi(float(maxi(width, height)) * WHOLE_AIR)
		centre_y = content.position.y + height / 2
	side = clampi(side, 1, mini(size.x, size.y))
	var centre_x := content.position.x + width / 2
	return Rect2i(
		clampi(centre_x - side / 2, 0, size.x - side),
		clampi(centre_y - side / 2, 0, size.y - side),
		side,
		side
	)


## Cell `index`'s top-left corner in atlas pixels.
static func cell_origin(index: int) -> Vector2i:
	return Vector2i(index % GRID, index / GRID) * CELL_PX


## Where the picture of cell `index` starts, in atlas UV (what the pin shader reads).
static func picture_uv(index: int) -> Vector2:
	var corner := cell_origin(index) + Vector2i.ONE * ((CELL_PX - PICTURE_PX) / 2)
	return Vector2(corner) / float(ATLAS_PX)


# --- the cache ---


## The cell holding the picture for `key`, or -1 while there is none.
func cell_of(key: String) -> int:
	return int(_cells.get(key, -1))


## Whether `key` is known: pictured, failed, or waiting in the queue.
func knows(key: String) -> bool:
	return _cells.has(key) or _failed.has(key) or _queued.has(key)


## Asks for the picture for `key`; `source` is {"kind": Kind.ICON, "path": String},
## {"kind": Kind.AVATAR, "recipe": Dictionary} or {"kind": Kind.MODEL, "token": int} (the
## token's instance id). Nothing happens when the key is already known.
func request(key: String, source: Dictionary) -> void:
	if knows(key):
		return
	if _next_cell >= GRID * GRID:
		_failed[key] = true
		return
	_queued[key] = true
	var job := source.duplicate()
	job["key"] = key
	_queue.append(job)


## Puts `image` (any size, cropped to its portrait_rect) into the next free cell for `key`;
## false (and the key failed) for an empty image.
func store(key: String, image: Image) -> bool:
	_queued.erase(key)
	if image == null or image.is_empty() or _next_cell >= GRID * GRID:
		_failed[key] = true
		return false
	var picture := image.get_region(portrait_rect(visible_rect(image), image.get_size()))
	if picture.get_format() != Image.FORMAT_RGBA8:
		picture.convert(Image.FORMAT_RGBA8)
	picture.resize(PICTURE_PX, PICTURE_PX, Image.INTERPOLATE_LANCZOS)
	picture.premultiply_alpha()
	var index := _next_cell
	_next_cell += 1
	var corner := cell_origin(index) + Vector2i.ONE * ((CELL_PX - PICTURE_PX) / 2)
	_image.blit_rect(picture, Rect2i(0, 0, PICTURE_PX, PICTURE_PX), corner)
	_cells[key] = index
	_dirty = true
	return true


# --- jobs ---


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	while not _queue.is_empty() and not _busy:
		var job: Dictionary = _queue.pop_front()
		match int(job.kind):
			Kind.ICON:
				_do_icon(job)
				if Time.get_ticks_usec() - started > ICON_BUDGET_US:
					break
			Kind.AVATAR:
				_do_avatar(job)
			Kind.MODEL:
				_do_model(job)
	flush()


## Uploads the atlas when a picture was stored since the last upload.
func flush() -> void:
	if _dirty:
		_dirty = false
		atlas.update(_image)


func _do_icon(job: Dictionary) -> void:
	var image := Image.new()
	var path := String(job.path)
	var bytes := FileAccess.get_file_as_bytes(path)
	var error := ERR_FILE_CANT_READ
	if not bytes.is_empty():
		match path.get_extension().to_lower():
			"png":
				error = image.load_png_from_buffer(bytes)
			"jpg", "jpeg":
				error = image.load_jpg_from_buffer(bytes)
			"webp":
				error = image.load_webp_from_buffer(bytes)
	store(String(job.key), image if error == OK else null)


func _do_avatar(job: Dictionary) -> void:
	var key := String(job.key)
	var done := func(texture: Texture2D) -> void:
		store(key, texture.get_image() if texture != null else null)
	var cached := AvatarThumbnails.request(job.recipe, done)
	if cached != null:
		done.call(cached)


func _do_model(job: Dictionary) -> void:
	var token := instance_from_id(int(job.token)) as BoardToken
	if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
		_queued.erase(String(job.key))
		return
	_busy = true
	_draw_model(String(job.key), token)


## Draws a portrait of the token's meshes on the private stage and stores it. The meshes are
## copied (shared mesh and materials, no ghost overlay) turned to face the camera, so the live
## token is not touched.
func _draw_model(key: String, token: BoardToken) -> void:
	var viewport := _stage()
	var holder := Node3D.new()
	holder.rotation.y = AZIMUTH_RAD
	viewport.add_child(holder)
	var inverse := token.rigid_body.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mi in TokenGhost.meshes_of(token.rigid_body):
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		# The mesh's own materials (the original of a painted one), not the token's overrides: a
		# GM-hidden token's fade and the painted look must not be baked into the shared picture.
		for surface in mi.mesh.get_surface_count():
			var original := TokenToon.source_of(mi, surface)
			if original != null:
				copy.set_surface_override_material(surface, original)
		copy.transform = inverse * mi.global_transform
		holder.add_child(copy)
		var bounds := copy.transform * mi.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	if first:
		holder.queue_free()
		store(key, null)
		_busy = false
		return
	_fit(_stage_camera, holder.transform, box)
	await get_tree().process_frame
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	holder.queue_free()
	store(key, image)
	_busy = false


## Centres `camera` on `box` (in the holder's space) and sizes its view to hold it.
static func _fit(camera: Camera3D, holder: Transform3D, box: AABB) -> void:
	camera.basis = Basis.from_euler(Vector3(-PITCH_RAD, AZIMUTH_RAD, 0.0))
	var low := Vector2(INF, INF)
	var high := -low
	for corner in 8:
		var world := holder * box.get_endpoint(corner)
		var on_view := Vector2(world.dot(camera.basis.x), world.dot(camera.basis.y))
		low = low.min(on_view)
		high = high.max(on_view)
	var middle := (low + high) * 0.5
	camera.size = maxf(high.x - low.x, high.y - low.y) * MARGIN
	var depth := (holder * box.get_center()).dot(camera.basis.z)
	camera.position = (
		camera.basis.x * middle.x + camera.basis.y * middle.y + camera.basis.z * (depth + 10.0)
	)


## The private viewport (lit as the roster icons are), made on first use.
func _stage() -> SubViewport:
	if _stage_viewport != null:
		return _stage_viewport
	_stage_viewport = SubViewport.new()
	_stage_viewport.name = "PortraitStage"
	_stage_viewport.size = Vector2i(RENDER_PX, RENDER_PX)
	_stage_viewport.transparent_bg = true
	_stage_viewport.own_world_3d = true
	_stage_viewport.msaa_3d = Viewport.MSAA_4X
	_stage_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_stage_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.82, 0.82, 0.9)
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_stage_viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-52.0), AZIMUTH_RAD + deg_to_rad(28.0), 0.0)
	light.light_energy = 1.0
	_stage_viewport.add_child(light)
	_stage_camera = Camera3D.new()
	_stage_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_stage_viewport.add_child(_stage_camera)
	return _stage_viewport
