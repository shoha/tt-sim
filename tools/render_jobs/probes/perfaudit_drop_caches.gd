extends Node

## What the static caches and the render state hold at the title (perfaudit_system.gd
## `drop_caches`, split out of it in wave 2): clears them one at a time (four frames apart, so freed
## RIDs are gone from the monitors) and logs the texture, buffer and static memory each released.
## Run at the title after a map; the next map rebuilds whatever it needs. The last steps shrink the
## root viewport's 3D state and the shadow atlases and then put them back.

var steps: Array = [
	["SurfaceStore.clear_memory", func() -> void: SurfaceStore.clear_memory()],
	["AssetStore.clear_meshes", func() -> void: AssetStore.clear_meshes()],
	["AssetThumbnails.clear", func() -> void: AssetThumbnails.clear()],
	["WindFoliage.reset_caches", func() -> void: WindFoliage.reset_caches()],
	["PaletteLibrary.clear_cache", func() -> void: PaletteLibrary.clear_cache()],
	["EnvironmentPresets sky cache", func() -> void: EnvironmentPresets._sky_cache.clear()],
	["MasonryTextures", func() -> void: MasonryTextures._set.clear()],
	["UI thumbnails (swatch, structure, biome)", func() -> void: _drop_thumbnails()],
	["village and ground-mass materials", func() -> void: _drop_village()],
	["root viewport disable_3d", func() -> void: _root().disable_3d = true],
	["root positional shadow atlas 0", func() -> void: _root().positional_shadow_atlas_size = 0],
	["directional shadow atlas 256", func() -> void: _directional_atlas(256)],
	["restore 3d and shadow atlases", func() -> void: _restore_render()],
]
var index := -1
var wait := 4
var last := Vector3.ZERO
var rows := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	last = _read()
	rows.append("start tex %.1f buf %.1f static %.1f MB" % [last.x, last.y, last.z])


func _process(_delta: float) -> void:
	wait -= 1
	if wait > 0:
		return
	wait = 4
	if index >= 0:
		var now := _read()
		var d := now - last
		rows.append("%s tex %+.1f buf %+.1f static %+.1f" % [steps[index][0], d.x, d.y, d.z])
		last = now
	index += 1
	if index < steps.size():
		(steps[index][1] as Callable).call()
		return
	rows.append("end tex %.1f buf %.1f static %.1f MB" % [last.x, last.y, last.z])
	var line := "drop_caches | " + ", ".join(rows)
	for node in get_tree().root.get_children():
		if node.has_method("log_line"):
			node.call("log_line", line)
			break
	queue_free()


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _drop_thumbnails() -> void:
	SwatchTextures._cache.clear()
	StructureThumbnail._cache.clear()
	BiomeThumbnail._cache.clear()


static func _drop_village() -> void:
	VillageSwatch._paving.clear()
	VillagePlazas._grounds.clear()
	GroundMassStamps._materials.clear()


static func _directional_atlas(size: int) -> void:
	RenderingServer.directional_shadow_atlas_set_size(size, true)


static func _restore_render() -> void:
	var key := "rendering/lights_and_shadows/"
	_root().disable_3d = false
	_root().positional_shadow_atlas_size = int(
		ProjectSettings.get_setting(key + "positional_shadow/atlas_size", 4096)
	)
	_directional_atlas(int(ProjectSettings.get_setting(key + "directional_shadow/size", 4096)))


static func _read() -> Vector3:
	return Vector3(
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0,
		OS.get_static_memory_usage() / 1048576.0
	)
