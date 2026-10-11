extends RefCounted

## Render-job probe (`call` op) for the painted backdrop (PaintedBackdrop) in the UI tour
## (jobs/ui_tour.json): the title in each curated mood, chosen the real way, by selecting a
## map whose environment preset paints it, over a staged library. Nothing is written to disk:
## the title's grid reads a staged list (the tour's test level and six sample maps with no
## folder, which paint their placeholders) until `restore`. `action`:
## - `stage` (`folder`, `count`): the title's grid shows `folder` (the tour's test level, read
##   from disk) and SAMPLE_MAPS (the first `count` of them in their order, all six by
##   default), each edited a day or more before the last.
## - `select` (`mood`): click the staged card whose preset paints `mood` (morning, midday,
##   golden_hour, dusk, overcast or night), as a player's click does; the backdrop fades to it.
## - `fade` (`from`, `to`, `at`): select the card of mood `from` at once, then click the card of
##   mood `to` and hold the change at `at` (0 to 1) of the way, for a capture of the mix.
## - `settle`: end a change held part way by `fade`, the backdrop at rest in the mood it was
##   changing to (a held change otherwise stays held through every later select of that map).
## - `drift` (`held`): PaintedBackdrop.hold_drift, as Reduce motion calls it (the gradient does
##   not move, so the captures either side show the same sky).
## - `empty`: the title over an empty library.
## - `restore`: the title's grid reads the real library again, the newest map selected.
## - `report`: log the backdrop's mood, its map and how far its change has run.
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
	"midday": ["Hayfield Rise", "outdoor_day"],
	"golden_hour": ["Lantern Bay", "outdoor_sunset"],
	"dusk": ["Violet Fen", "ethereal"],
	"overcast": ["Misty Tarn", "outdoor_overcast"],
	"night": ["Moonwell", "outdoor_night"],
}
const DAY_S := 86400
const SAMPLE_PREFIX := "user://levels/_backdrop_sample_"


static func run(base: Node, step: Dictionary) -> String:
	var title: TitleScreen = base.get("_title_screen")
	match String(step.get("action", "")):
		"stage":
			return _stage(title, String(step.get("folder", "")), int(step.get("count", 6)))
		"settle":
			title.backdrop.show_mood(title.backdrop.mood(), true)
			return "settled; %s" % _report(title)
		"select":
			return _select(title, String(step.get("mood", "")))
		"fade":
			return _fade(title, step)
		"drift":
			title.backdrop.hold_drift(bool(step.get("held", false)))
			return "drift %s" % ("held" if step.get("held", false) else "free")
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
	return (
		"gpu %s: median %.3f ms, p10 %.3f, p90 %.3f, %d frames"
		% [label, at.call(0.5), at.call(0.1), at.call(0.9), samples.size()]
	)


static func _stage(title: TitleScreen, folder: String, count: int) -> String:
	if title == null:
		return "no title"
	var levels: Array[Dictionary] = []
	var real := LevelManager.folder_info(folder)
	if not real.is_empty():
		levels.append(real)
	# Edited over the last week or so, a day or more apart (the newest first), never 1970.
	var modified := int(Time.get_unix_time_from_system()) - DAY_S
	for mood: String in SAMPLE_MAPS.keys().slice(0, count):
		var sample: Array = SAMPLE_MAPS[mood]
		var key := SAMPLE_PREFIX + mood
		(
			levels
			. append(
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
		)
		modified -= DAY_S + 3600 * (levels.size() * 5 % 11)
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


## Click the card of mood `from` and let it settle at once, then click the card of mood `to`
## and hold the change at `at` of the way.
static func _fade(title: TitleScreen, step: Dictionary) -> String:
	if title == null:
		return "no title"
	_select(title, String(step.get("from", "")))
	var backdrop := title.backdrop
	backdrop.show_mood(backdrop.mood(), true)
	_select(title, String(step.get("to", "")))
	if backdrop._fade and backdrop._fade.is_valid():
		backdrop._fade.kill()
	backdrop._set_blend(float(step.get("at", 0.5)))
	var mid: Vector3 = (backdrop.material as ShaderMaterial).get_shader_parameter(&"mid_lch")
	return "%s; middle stop L %.3f C %.3f h %.3f" % [_report(title), mid.x, mid.y, mid.z]


static func _report(title: TitleScreen) -> String:
	if title == null:
		return "no title"
	var backdrop := title.backdrop
	return (
		"backdrop %s, map %s, at %.2f"
		% [PaintedBackdrop.Mood.keys()[backdrop.mood()], backdrop.key(), backdrop.blend()]
	)


static func _room_mood(base: Node, preset: String) -> String:
	var room := base.get_node_or_null("UiTourRoom") as RoomScreen
	if room == null:
		return "no staged room"
	var panel := room.panel
	var sample: String = panel._shelf[2].folder
	panel._pictures[sample] = {"texture": null, "mood": preset}
	panel.select(sample)
	var mood: int = room.backdrop.mood()
	return "room selects %s (%s): backdrop %s" % [sample, preset, PaintedBackdrop.Mood.keys()[mood]]
