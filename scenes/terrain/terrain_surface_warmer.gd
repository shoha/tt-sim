class_name TerrainSurfaceWarmer
extends RefCounted

## Background loads of palette surfaces' ground textures for an AuthoredTerrain (moved out of
## it, clipmap1): request() starts the threaded loads, collect() (the terrain's _process) takes
## the finished ones and holds each texture so the resource cache keeps it for the layer bind.

## Texture paths loading on background threads.
var _warming: Dictionary = {}
## The loaded textures, held until release().
var _held: Array[Resource] = []


## Starts loading the textures of palette surface `surface_name` under `palette_root`. None
## under the headless dummy renderer (GlbUtils.threaded_loads_safe): loaded when bound.
func request(palette_root: String, surface_name: String) -> void:
	var surface: Dictionary = PaletteLibrary.surfaces(palette_root).get(surface_name, {})
	for key in GroundLayerArrays.UNIFORMS if GlbUtils.threaded_loads_safe() else {}:
		var relative: Variant = surface.get(key, "")
		if not relative is String or relative == "":
			continue
		var path := palette_root.path_join(relative)
		if ResourceLoader.has_cached(path) or _warming.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_warming[path] = true


## Collects the finished loads.
func collect() -> void:
	for path in _warming.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_warming.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_held.append(ResourceLoader.load_threaded_get(path))


## True when no load is in flight.
func is_idle() -> bool:
	return _warming.is_empty()


## Drops everything: finishes the loads in flight (the loader wants them taken) and lets go.
func release() -> void:
	for path in _warming.keys():
		ResourceLoader.load_threaded_get(path)
	_warming.clear()
	_held.clear()
