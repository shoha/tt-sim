class_name AssetModelCache

## In-memory cache for loaded model scenes.
##
## Extracted from AssetManager to give the model instance API (get,
## preload, cache) a dedicated home.  The cache stores either a Node3D
## template (for GLB files) or a PackedScene (for .tscn/.scn), and
## hands out duplicates/instances so every caller gets a unique tree.
##
## Requires a Node reference for `get_tree()` and coroutine yielding.

var _model_cache: Dictionary = {}  # cache_key -> Node3D | PackedScene
var _loading_models: Dictionary = {}  # cache_key -> true (in-flight guard)
var _owner: Node  # parent node (for get_tree())


func _init(owner: Node) -> void:
	_owner = owner


# =========================================================================
# Async API
# =========================================================================


## Get a model instance from a resolved path (async, uses cache).
## Returns a *new* Node3D each call (duplicated from the cached template).
func get_instance_from_path(path: String, create_static_bodies: bool = false) -> Node3D:
	var cache_key = _cache_key(path, create_static_bodies)

	# Check cache first
	if _model_cache.has(cache_key):
		return _get_from_cache(cache_key)

	# Wait if another call is already loading this model
	while _loading_models.has(cache_key):
		await _owner.get_tree().process_frame
		if _model_cache.has(cache_key):
			return _get_from_cache(cache_key)

	# Mark as loading
	_loading_models[cache_key] = true

	var model: Node3D = null

	if path.ends_with(".glb"):
		var result = await GlbUtils.load_glb_with_processing_async(path, create_static_bodies)
		if result.success:
			model = result.scene
		else:
			# Delete corrupted/invalid GLB from disk so the cache manager
			# will drop it from its index on the next lookup, allowing a
			# fresh download.
			if FileAccess.file_exists(path):
				push_warning("AssetModelCache: Removing corrupted cache file: %s" % path)
				DirAccess.remove_absolute(path)
	else:
		# Non-GLB resource — use threaded resource loading
		var load_status = ResourceLoader.load_threaded_request(path)
		if load_status == OK:
			while (
				ResourceLoader.load_threaded_get_status(path)
				== ResourceLoader.THREAD_LOAD_IN_PROGRESS
			):
				await _owner.get_tree().process_frame
			var resource = ResourceLoader.load_threaded_get(path)
			if resource is PackedScene:
				_model_cache[cache_key] = resource
				_loading_models.erase(cache_key)
				return resource.instantiate() as Node3D

	# Cache the loaded model as a template
	if model:
		_model_cache[cache_key] = model
		_loading_models.erase(cache_key)
		return model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D

	_loading_models.erase(cache_key)
	return null


## Preload multiple models asynchronously (for batch loading before spawning).
## [param paths] Array of Dictionaries with "path" and "create_static_bodies" keys.
## [param progress_callback] Optional callback(loaded: int, total: int).
## Returns the number of models successfully loaded.
func preload_from_paths(
	paths: Dictionary,  # cache_key -> path
	create_static_bodies: bool = false,
	progress_callback: Callable = Callable(),
) -> int:
	var total = paths.size()
	var loaded = 0

	for cache_key in paths:
		var path = paths[cache_key]

		if _model_cache.has(cache_key):
			loaded += 1
			if progress_callback.is_valid():
				progress_callback.call(loaded, total)
			continue

		var model = await get_instance_from_path(path, create_static_bodies)
		if model:
			model.queue_free()
			loaded += 1

		if progress_callback.is_valid():
			progress_callback.call(loaded, total)

		await _owner.get_tree().process_frame

	return loaded


# =========================================================================
# Sync API
# =========================================================================


## Get a model instance from a path synchronously (blocks main thread).
func get_instance_from_path_sync(path: String, create_static_bodies: bool = false) -> Node3D:
	var cache_key = _cache_key(path, create_static_bodies)

	if _model_cache.has(cache_key):
		return _get_from_cache(cache_key)

	var model: Node3D = null

	if path.ends_with(".glb"):
		model = GlbUtils.load_glb_with_processing(path, create_static_bodies)
	else:
		if ResourceLoader.exists(path):
			var resource = load(path)
			if resource is PackedScene:
				_model_cache[cache_key] = resource
				return resource.instantiate() as Node3D

	if model:
		_model_cache[cache_key] = model
		return model.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D

	return null


# =========================================================================
# Cache management
# =========================================================================


## Check if a model is already in the cache.
func is_cached(path: String, create_static_bodies: bool = false) -> bool:
	return _model_cache.has(_cache_key(path, create_static_bodies))


## Clear the entire cache, freeing Node3D templates.
func clear() -> void:
	for cache_key in _model_cache:
		var cached = _model_cache[cache_key]
		if cached is Node3D and is_instance_valid(cached):
			cached.free()

	_model_cache.clear()
	_loading_models.clear()
	print("AssetModelCache: Cache cleared")


# =========================================================================
# Internal
# =========================================================================


func _cache_key(path: String, create_static_bodies: bool) -> String:
	return path + ("_static" if create_static_bodies else "")


func _get_from_cache(cache_key: String) -> Node3D:
	var cached = _model_cache[cache_key]

	if cached is PackedScene:
		return cached.instantiate() as Node3D

	if cached is Node3D and is_instance_valid(cached):
		return cached.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D

	_model_cache.erase(cache_key)
	return null
