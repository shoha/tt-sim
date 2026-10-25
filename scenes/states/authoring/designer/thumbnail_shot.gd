class_name ThumbnailShot
extends RefCounted

## The runtime half of the biome thumbnails (docs/systems/library.md "Biome thumbnails"): puts
## the open authoring map into the state its picture is taken in and takes the frame, for the
## render-job harness (`tools/render_library_thumbnails.gd`) and the biome designer's "Update
## thumbnail". The map is the standard scene `LibraryThumbnailer` describes; this class holds
## the plants still (the wind speeds at 0, the close-zoom canopy fade off, the play-zoom fade
## off) and the camera on the map's centre at the standard zoom, so two takes of one document
## on one machine draw the same pixels. `restore` puts everything back.

const WIND_SPEEDS: Array[String] = ["sway_speed", "flutter_speed", "gust_speed"]


## Freezes the wind and the canopy fades of `game_map` and frames the camera. Returns what
## `restore` needs. Call it once the scatter has settled, then wait a few frames and `grab`.
static func prepare(
	game_map: GameMap,
	zoom: float = LibraryThumbnailer.CAMERA_ZOOM,
	at: Vector2 = LibraryThumbnailer.LOOK_AT
) -> Dictionary:
	var held := {"fade": CanopyFade.enabled, "parts": {}, "winds": {}}
	CanopyFade.enabled = false
	freeze(game_map, held)
	game_map.get_camera_controller().frame_ground(at, zoom)
	return held


## Freezes the materials of `game_map` that have not been frozen yet (a cell that grew in after
## `prepare` brings new ones), adding them to `held`. Returns how many were new.
static func freeze(game_map: GameMap, held: Dictionary) -> int:
	var fresh := 0
	var parts: Dictionary = held["parts"]
	var winds: Dictionary = held["winds"]
	for material in WindFoliage.collect_foliage_shader_materials(game_map.map_container):
		var part: Variant = material.get_shader_parameter("canopy_part")
		if part is int and int(part) != 0 and not parts.has(material):
			parts[material] = int(part)
		if part is int:
			material.set_shader_parameter("canopy_part", 0)
		if not winds.has(material):
			var speeds := {}
			for uniform in WIND_SPEEDS:
				speeds[uniform] = material.get_shader_parameter(uniform)
			winds[material] = speeds
			fresh += 1
		for uniform in WIND_SPEEDS:
			material.set_shader_parameter(uniform, 0.0)
	return fresh


## Puts back what `prepare` and `freeze` changed (not the camera).
static func restore(held: Dictionary) -> void:
	CanopyFade.enabled = bool(held.get("fade", CanopyFade.enabled))
	var parts: Dictionary = held.get("parts", {})
	for material: Variant in parts:
		if is_instance_valid(material):
			(material as ShaderMaterial).set_shader_parameter("canopy_part", parts[material])
	var winds: Dictionary = held.get("winds", {})
	for material: Variant in winds:
		if is_instance_valid(material):
			var speeds: Dictionary = winds[material]
			for uniform: String in speeds:
				(material as ShaderMaterial).set_shader_parameter(uniform, speeds[uniform])


## The world viewport's current frame (the 3D view alone, no interface), or null without a map.
## Call it after the frame has drawn (RenderingServer.frame_post_draw).
static func grab(game_map: GameMap) -> Image:
	if game_map == null or not is_instance_valid(game_map):
		return null
	return game_map.world_viewport.get_texture().get_image()
