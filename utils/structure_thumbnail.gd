class_name StructureThumbnail
extends RefCounted

## A structure's picture for its palette tile (StructureToolPane): the library's rendered tile
## (`thumbnails/structures/<id>.jpg`, a row's `thumb` as an absolute path), read once per file
## and size and cached. A structure with no readable tile gets a plain paper square, so a tile
## is never a hole.
##
## The pane builds on the tool's first show and lists every served structure (100 in core), and
## decoding their pictures there was the tool's first open: one frame of about 700 ms (card
## structopen; 650 ms of it the JPG decodes and the Lanczos scale). So an authoring open starts
## them on workers as it begins (warm_start) and collects them before its sheet drops
## (warm_finish_async), as the Paint swatches are (SwatchTextures); the pane then finds every
## picture cached. picture() is the one maker of the image, on either thread, so a warmed
## picture is the one of() would have made.

## The rendered tiles are wider than tall: the middle is kept, cut to a square.
static var _cache := {}
## Pictures made by of() itself on the main thread (a cache miss), for tests and diagnostics.
static var made_on_main := 0


## The picture of palette row `row` (LibraryStructureStore.structure) at `size` px square.
static func of(row: Dictionary, size: int) -> Texture2D:
	var key := _key(row, size)
	if _cache.has(key):
		return _cache[key]
	made_on_main += 1
	var texture := ImageTexture.create_from_image(picture(String(row.get("thumb", "")), size))
	_cache[key] = texture
	return texture


## True when of(row, size) is cached (it makes nothing).
static func has(row: Dictionary, size: int) -> bool:
	return _cache.has(_key(row, size))


## The square picture of the tile file `path` at `size` px: the middle of the file cut to a
## square and scaled down, or the paper square when the file is missing or unreadable. Reads
## only its own objects, so a worker may call it.
static func picture(path: String, size: int) -> Image:
	var image: Image = null
	if path != "" and FileAccess.file_exists(path):
		var bytes := FileAccess.get_file_as_bytes(path)
		image = Image.new()
		var error := image.load_jpg_from_buffer(bytes)
		if error != OK:
			error = image.load_png_from_buffer(bytes)
		if error != OK or image.is_empty():
			image = null
	if image == null:
		image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		image.fill(Color.from_rgba8(199, 189, 168))
	else:
		var side := mini(image.get_width(), image.get_height())
		var offset := Vector2i(image.get_width() - side, image.get_height() - side) / 2
		image = image.get_region(Rect2i(offset, Vector2i(side, side)))
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return image


## Starts making the pictures `wanted` ([row, size] pairs) that are not cached, on worker threads,
## all at once (a group task). Returns the job for warm_finish_async() (or drop()). Main thread.
static func warm_start(wanted: Array) -> Dictionary:
	var paths := PackedStringArray()
	var sizes := PackedInt32Array()
	var keys: Array[String] = []
	for pair: Array in wanted:
		var key := _key(pair[0], int(pair[1]))
		if _cache.has(key) or keys.has(key):
			continue
		paths.append(String((pair[0] as Dictionary).get("thumb", "")))
		sizes.append(int(pair[1]))
		keys.append(key)
	var images: Array = []
	images.resize(paths.size())
	var lock := Mutex.new()
	var task := -1
	if not paths.is_empty():
		task = WorkerThreadPool.add_group_task(
			func(i: int) -> void:
				var image := picture(paths[i], sizes[i])
				lock.lock()
				images[i] = image
				lock.unlock(),
			paths.size(),
			-1,
			false,
			"Structure pictures"
		)
	return {"task": task, "keys": keys, "images": images}


## Waits out the workers of a warm-up `job` (warm_start's, or {}) that will not be finished.
## Blocks the calling thread for at most the job's last pictures.
static func drop(job: Dictionary) -> void:
	if int(job.get("task", -1)) >= 0:
		WorkerThreadPool.wait_for_group_task_completion(int(job["task"]))


## Ends the warm-up `job` (warm_start's): its workers are waited for a frame at a time (the main
## thread never blocks on pool work), then the pictures become textures, cached, a few a frame
## within the load's frame budget. When `is_superseded` (func() -> bool) says so the pictures
## are dropped.
static func warm_finish_async(job: Dictionary, tree: SceneTree, is_superseded: Callable) -> void:
	var task := int(job.get("task", -1))
	if task < 0:
		return
	while not WorkerThreadPool.is_group_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_group_task_completion(task)
	var keys: Array[String] = job["keys"]
	var started := Time.get_ticks_usec()
	for i in keys.size():
		if is_superseded.call():
			return
		if Time.get_ticks_usec() - started >= MapSourceLoader.frame_budget_usec():
			await tree.process_frame
			started = Time.get_ticks_usec()
		if not _cache.has(keys[i]):
			_cache[keys[i]] = ImageTexture.create_from_image(job["images"][i])


static func _key(row: Dictionary, size: int) -> String:
	return "%s:%d" % [String(row.get("thumb", "")), size]
