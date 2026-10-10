extends RefCounted

## Render-job probe (`call` op) for the painted backdrop (PaintedBackdrop) in the UI tour
## (jobs/ui_tour.json): the title in each curated mood, chosen the real way, by selecting a
## map whose environment preset paints it, over a staged library. Nothing is written to disk:
## the title's grid reads a staged list (the tour's test level and four sample maps with no
## folder, which paint their placeholders) until `restore`. `action`:
## - `stage` (`folder`): the title's grid shows `folder` (the tour's test level, read from
##   disk) and SAMPLE_MAPS.
## - `select` (`mood`): click the staged card whose preset paints `mood` (morning, golden_hour,
##   dusk or night), as a player's click does; the backdrop cross-fades to it.
## - `empty`: the title over an empty library.
## - `restore`: the title's grid reads the real library again, the newest map selected.
## - `report`: log the backdrop's moods and how far its cross-fade has run.
## - `room_mood` (`preset`): on ui_room.gd's staged room, give the second sample map `preset`
##   and select it, so the room's backdrop takes that map's mood.
## - `gpu_start`, `gpu_stop` (`name`): sample the window's GPU render time every frame between
##   the two, and log its median, p10 and p90 under `name` (the first 10 frames dropped). The
##   window's own viewport, which the title's canvas draws into: the `gpu` op samples the 3D
##   world's.
## - `shown` (`on`): show or hide the title's backdrop, for the A/B of its cost.

## Sample maps by the mood their preset paints: name and preset. Their paths name no folder.
const SAMPLE_MAPS := {
	"morning": ["Willow Green", "forest"],
	"golden_hour": ["Lantern Bay", "outdoor_sunset"],
	"dusk": ["Violet Fen", "ethereal"],
	"night": ["Moonwell", "outdoor_night"],
}
const SAMPLE_PREFIX := "user://levels/_backdrop_sample_"


static func run(base: Node, step: Dictionary) -> String:
	var title: TitleScreen = base.get("_title_screen")
	match String(step.get("action", "")):
		"stage":
			return _stage(title, String(step.get("folder", "")))
		"select":
			return _select(title, String(step.get("mood", "")))
		"empty":
			return _provide(title, func() -> Array[Dictionary]: return [])
		"restore":
			title.grid.provider = LevelManager.get_saved_levels
			title.grid.refresh()
			title._preselect_most_recent()
			title._refresh_actions()
			return "real library, %s selected" % title.selected_level().get("name", "nothing")
		"report":
			return _report(title)
		"room_mood":
			return _room_mood(base, String(step.get("preset", "")))
		"gpu_start":
			return _gpu_start(base)
		"gpu_stop":
			return _gpu_stop(base, String(step.get("name", "gpu")))
		"shown":
			title.backdrop.visible = bool(step.get("on", true))
			return "title backdrop %s" % ("shown" if title.backdrop.visible else "hidden")
	return "unknown action %s" % step.get("action", "")


static func _gpu_start(base: Node) -> String:
	# The vsync_off op needs a map's world viewport; the title has none.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rid := base.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var samples: Array[float] = []
	var sample := func() -> void:
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	base.get_tree().process_frame.connect(sample)
	base.set_meta(&"backdrop_gpu", [sample, samples])
	return "sampling the window's GPU time"


static func _gpu_stop(base: Node, label: String) -> String:
	var held: Array = base.get_meta(&"backdrop_gpu", [])
	if held.is_empty():
		return "not sampling"
	base.get_tree().process_frame.disconnect(held[0])
	base.remove_meta(&"backdrop_gpu")
	var samples: Array = (held[1] as Array).slice(10)
	if samples.is_empty():
		return "no samples"
	samples.sort()
	var at := func(share: float) -> float: return samples[int(share * (samples.size() - 1))]
	return "gpu %s: median %.3f ms, p10 %.3f, p90 %.3f, %d frames" % [
		label, at.call(0.5), at.call(0.1), at.call(0.9), samples.size()
	]


static func _stage(title: TitleScreen, folder: String) -> String:
	if title == null:
		return "no title"
	var levels: Array[Dictionary] = []
	var real := LevelManager.folder_info(folder)
	if not real.is_empty():
		levels.append(real)
	var modified := 1000
	for mood: String in SAMPLE_MAPS:
		var sample: Array = SAMPLE_MAPS[mood]
		var key := SAMPLE_PREFIX + mood
		levels.append(
			{
				"path": key + "/",
				"folder": key.get_file(),
				"is_folder_based": true,
				"name": sample[0],
				"token_count": 0,
				"modified_at": modified,
				"environment_preset": sample[1],
				"thumbnail": "",
			}
		)
		modified -= 1
	return _provide(title, func() -> Array[Dictionary]: return levels)


static func _provide(title: TitleScreen, levels: Callable) -> String:
	if title == null:
		return "no title"
	title.grid.provider = levels
	title.grid.refresh()
	return "%d maps; %s" % [title.grid.card_count(), _report(title)]


static func _select(title: TitleScreen, mood: String) -> String:
	if title == null or not SAMPLE_MAPS.has(mood):
		return "no title, or no sample map for %s" % mood
	var map_name: String = SAMPLE_MAPS[mood][0]
	for card: LevelCard in title.grid._cards:
		if card.level_info.get("name", "") == map_name:
			card._on_pressed()
			return "selected %s; %s" % [map_name, _report(title)]
	return "no card %s (stage first)" % map_name


static func _report(title: TitleScreen) -> String:
	if title == null:
		return "no title"
	var paint := title.backdrop.material as ShaderMaterial
	var moods := PaintedBackdrop.Mood.keys()
	return "backdrop %s -> %s at %.2f, %d zones" % [
		moods[int(paint.get_shader_parameter(&"mood_from"))],
		moods[int(paint.get_shader_parameter(&"mood_to"))],
		float(paint.get_shader_parameter(&"blend")),
		int(paint.get_shader_parameter(&"zone_count")),
	]


static func _room_mood(base: Node, preset: String) -> String:
	var room := base.get_node_or_null("UiTourRoom") as RoomScreen
	if room == null:
		return "no staged room"
	var panel := room.panel
	var sample: String = panel._shelf[2].folder
	panel._pictures[sample] = {"texture": null, "mood": preset}
	panel.select(sample)
	var mood: int = room.backdrop.mood()
	return "room selects %s (%s): backdrop %s" % [
		sample, preset, PaintedBackdrop.Mood.keys()[mood]
	]
