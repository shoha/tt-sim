class_name SwatchTextures
extends RefCounted

## Small textures that show what a choice does: a sky preset's tile and preview
## (the shipped PNGs for HDRI skies, painted gradients otherwise), a lighting
## preset's background colour over its ambient colour, and a water palette's
## deep colour over its shallows colour for the respective preset pickers.
## Loaded or painted once per name and cached for the process; unknown names
## paint a neutral grey.

const SKY_SIZE := 24
const PREVIEW_WIDTH := 280
const PREVIEW_HEIGHT := 70
const SWATCH_SIZE := 16
const WATER_SWATCH_SIZE := 24
const FALLBACK := Color(0.3, 0.3, 0.3)

static var _cache: Dictionary = {}


## 24x24 tile: the shipped tile PNG for an HDRI sky, else sky over ground bands.
static func sky_gradient(preset_name: String) -> Texture2D:
	return _sky_texture("sky:", preset_name, "tile", SKY_SIZE, SKY_SIZE, int(SKY_SIZE * 2 / 3))


## 280x70 preview strip: the shipped preview PNG for an HDRI sky, else painted.
static func sky_preview(preset_name: String) -> Texture2D:
	return _sky_texture(
		"preview:",
		preset_name,
		"preview",
		PREVIEW_WIDTH,
		PREVIEW_HEIGHT,
		int(PREVIEW_HEIGHT * 2 / 3)
	)


static func preset_swatch(preset_name: String) -> ImageTexture:
	var key := "preset:" + preset_name
	if _cache.has(key):
		return _cache[key]
	var lookup := preset_name if EnvironmentPresets.PRESETS.has(preset_name) else ""
	var config := EnvironmentPresets.get_environment_config(lookup, {}, {})
	var background: Color = config.get("background_color", FALLBACK)
	var ambient: Color = config.get("ambient_light_color", FALLBACK)
	var image := Image.create(SWATCH_SIZE, SWATCH_SIZE, false, Image.FORMAT_RGBA8)
	var split := SWATCH_SIZE / 2
	for y in range(SWATCH_SIZE):
		var color := background if y < split else ambient
		for x in range(SWATCH_SIZE):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## 24x24 tile for a water palette: deep color over shallows color, opaque (the
## palette alphas are shader blend weights, not something to show in a swatch).
static func water_swatch(palette_name: String) -> ImageTexture:
	var key := "water:" + palette_name
	if _cache.has(key):
		return _cache[key]
	var palette: Dictionary = WaterPresets.PALETTES.get(palette_name, {})
	var deep: Color = palette.get("water_color", FALLBACK)
	var shallows: Color = palette.get("shore_color", FALLBACK)
	deep.a = 1.0
	shallows.a = 1.0
	var image := Image.create(WATER_SWATCH_SIZE, WATER_SWATCH_SIZE, false, Image.FORMAT_RGBA8)
	var split := WATER_SWATCH_SIZE / 2
	for y in range(WATER_SWATCH_SIZE):
		var color := deep if y < split else shallows
		for x in range(WATER_SWATCH_SIZE):
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## A `size` x `size` tile of a palette image (a biome thumbnail, or a ground surface's
## albedo for "bare ground" and the Paint swatches), `relative_path` being relative to the
## palette root, centre-cropped square and scaled down once. A library surface's map is its
## decoded file (SurfaceStore.picture_image), never a bake: a swatch neither waits for nor
## queues the 200 ms compression a cold albedo costs (card coldopen). A missing image paints the
## neutral grey.
static func palette_thumbnail(
	relative_path: String, size: int, root: String = PaletteLibrary.DEFAULT_ROOT
) -> Texture2D:
	var key := _palette_key(relative_path, size, root)
	if _cache.has(key):
		return _cache[key]
	var image: Image = null
	if relative_path != "":
		image = SurfaceStore.picture_image(root, relative_path)
	var texture := ImageTexture.create_from_image(square_tile(image, size))
	_cache[key] = texture
	return texture


static func _palette_key(relative_path: String, size: int, root: String) -> String:
	return "palette:%s:%s:%d" % [root, relative_path, size]


## `image` (uncompressed) centre-cropped square and scaled to `size` px (Lanczos), or the neutral
## grey when it is null or empty. Pure: workers call it.
static func square_tile(image: Image, size: int) -> Image:
	if image == null or image.is_empty():
		var grey := Image.create(size, size, false, Image.FORMAT_RGBA8)
		grey.fill(FALLBACK)
		return grey
	var side := mini(image.get_width(), image.get_height())
	var offset := Vector2i(image.get_width() - side, image.get_height() - side) / 2
	var tile := image.get_region(Rect2i(offset, Vector2i(side, side)))
	tile.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return tile


## The albedos (palette-relative) of the surfaces of `roles` under `root`, in role then palette
## order: the Paint swatches' pictures.
static func paint_albedos(roles: PackedStringArray, root: String) -> PackedStringArray:
	var surfaces := PaletteLibrary.surfaces(root)
	var albedos := PackedStringArray()
	for role in roles:
		for surface in PaletteLibrary.surfaces_with_role(role, root):
			albedos.append(String(surfaces.get(surface, {}).get("albedo", "")))
	return albedos


## palette_thumbnail() of each of `albedos` at `size` under `root` (cached for the process):
## warm_start() then warm_finish_async(). Stops early when `is_superseded` (func() -> bool) says so.
static func warm_async(
	albedos: PackedStringArray,
	size: int,
	root: String,
	tree: SceneTree,
	is_superseded: Callable
) -> void:
	await warm_finish_async(warm_start(albedos, size, root), tree, is_superseded)


## Starts warming the swatches of `albedos` at `size` under `root`: the library maps' files are
## decoded and scaled down on worker threads, all at once (about 10 ms a swatch, card coldopen),
## so an open starts them as it begins and only collects them later. Returns the job for
## warm_finish_async(). Main thread.
static func warm_start(albedos: PackedStringArray, size: int, root: String) -> Dictionary:
	var sources: Array[Dictionary] = []
	var keys: Array[String] = []
	var others := PackedStringArray()
	for albedo in albedos:
		var key := _palette_key(albedo, size, root)
		if albedo == "" or _cache.has(key) or keys.has(key):
			continue
		var source := SurfaceStore.picture_source(root, albedo)
		if source.is_empty():
			others.append(albedo)
			continue
		sources.append(source)
		keys.append(key)
	var tiles: Array = []
	tiles.resize(sources.size())
	var lock := Mutex.new()
	var task := -1
	if not sources.is_empty():
		task = WorkerThreadPool.add_group_task(
			func(i: int) -> void:
				var source: Dictionary = sources[i]
				var tile := square_tile(
					SurfaceStore.decode_picture(String(source["file"]), String(source["kind"])), size
				)
				lock.lock()
				tiles[i] = tile
				lock.unlock(),
			sources.size(),
			-1,
			false,
			"Paint swatches"
		)
	return {
		"task": task, "keys": keys, "tiles": tiles, "others": others, "size": size, "root": root
	}


## Ends the warm-up `job` (warm_start's): the swatches that are not library maps are made a few a
## frame within the load's frame budget, the workers' are waited for a frame at a time (the main
## thread never blocks on pool work) and cached. When `is_superseded` (func() -> bool) says so
## the workers' results are dropped.
static func warm_finish_async(job: Dictionary, tree: SceneTree, is_superseded: Callable) -> void:
	var started := Time.get_ticks_usec()
	for albedo: String in job["others"]:
		if Time.get_ticks_usec() - started >= MapSourceLoader.frame_budget_usec():
			await tree.process_frame
			started = Time.get_ticks_usec()
		palette_thumbnail(albedo, int(job["size"]), String(job["root"]))
	var task := int(job["task"])
	if task >= 0:
		while not WorkerThreadPool.is_group_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_group_task_completion(task)
	if is_superseded.call():
		return
	var keys: Array[String] = job["keys"]
	for i in keys.size():
		if not _cache.has(keys[i]):
			_cache[keys[i]] = ImageTexture.create_from_image(job["tiles"][i])


static func _sky_texture(
	prefix: String,
	preset_name: String,
	shipped_field: String,
	width: int,
	height: int,
	horizon: int
) -> Texture2D:
	var key := prefix + preset_name
	if _cache.has(key):
		return _cache[key]
	var sky: Dictionary = EnvironmentPresets.SKY_PRESETS.get(preset_name, {})
	var shipped: String = sky.get(shipped_field, "")
	var texture: Texture2D = null
	if not shipped.is_empty() and ResourceLoader.exists(shipped):
		texture = load(shipped) as Texture2D
	if texture == null:
		texture = _paint_bands(
			width,
			height,
			horizon,
			sky.get("sky_top_color", FALLBACK),
			sky.get("sky_horizon_color", FALLBACK),
			sky.get("ground_horizon_color", FALLBACK),
			sky.get("ground_bottom_color", FALLBACK)
		)
	_cache[key] = texture
	return texture


## Sky gradient down to horizon_row, ground gradient below it.
static func _paint_bands(
	width: int,
	height: int,
	horizon_row: int,
	top: Color,
	horizon: Color,
	ground_top: Color,
	ground_bottom: Color
) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in range(height):
		var color: Color
		if y < horizon_row:
			color = top.lerp(horizon, float(y) / float(horizon_row - 1))
		else:
			var t := float(y - horizon_row) / float(height - horizon_row - 1)
			color = ground_top.lerp(ground_bottom, t)
		for x in range(width):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
