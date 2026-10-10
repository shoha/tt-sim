extends RefCounted

## Render-job probe (`call` op) for the title's Play together card (PlayTogetherCard) and its
## Resume entry (ResumeEntry), for the UI tour and jobs/play_together.json. Nothing is hosted
## or joined: the card's states are set as its own input would set them, and the saved
## sessions Resume lists are staged (the title's resume entry reads a sample list instead of
## SessionFile.list(), so nothing is written to user://sessions/). `action`:
## - `card` (`state`): put the card in a state, from rest first:
##   - `rest`: seam centred, nothing picked, Join closed.
##   - `hover_host`, `hover_join`: a face picked as the pointer over it picks it (the seam
##     swings away from it over MOTION_WASH; the OS cursor is not moved).
##   - `focus`: keyboard focus on the pill, as Tab gives it (Host picked, the card's ring).
##   - `join` (`code`, optional): Join in place, the code typed into the field.
##   - `connecting` (`code`): Join in place with the join under way (field and Join locked).
##   - `error` (`code`, `message`, default SessionFlow.NO_ROOM): a failed join in place.
##   - `version`: a failed join with the version gate's message (the longest copy).
##   - `flood` (`at`, seconds): Host pressed, its squash and flood held `at` into their
##     easings (for a filmstrip; held short of the flood's end, so no room is asked for).
##   - `opening` (`at`): Join in place opening, held `at` into its easings.
##   - `older`: Resume's older-sessions menu open.
## - `words` (`shown`, default true): show or hide the faces' words and icons, so `contrast`
##   reads the wash itself under them.
## - `contrast`: read the window's last frame under each face's words (the card's words_rect(),
##   which the shader never lightens) and log the lightest wash pixel there and paper's
##   contrast against it (4.5:1 is the bar), with the lightest pixel of the whole face beside
##   it. Hide the words first and wait a frame.
## - `crop` (`name`): save the window's last frame cut to the card, at the window's pixels,
##   as CROPS/<name>.png (the card up close; follow a capture or a wait).
## - `sessions` (`count`, default 2): Resume lists `count` sample sessions, the newest played
##   yesterday evening; 0 reads the real list again.

## Sample saved sessions, newest first: name, maps, days before now.
const SAMPLE_SESSIONS := [
	["Old Mill", 3, 1],
	["Oak's Lab", 1, 4],
	["Fen Crossing", 2, 12],
]
const DAY_S := 86400
## Where `crop` saves.
const CROPS := "user://render_jobs/play_together/crops"
## A room code in the real format (ui_room.gd's sample lobby id, 11 characters).
const SAMPLE_CODE := "u0w2r1nyrrh"


static func run(base: Node, step: Dictionary) -> String:
	var title := base.get("_title_screen") as TitleScreen
	if title == null:
		return "no title"
	match String(step.get("action", "")):
		"card":
			return _card(title, String(step.get("state", "rest")), step)
		"sessions":
			return _sessions(title, int(step.get("count", 2)))
		"words":
			return _words(title.play_together, bool(step.get("shown", true)))
		"contrast":
			return _contrast(title.play_together)
		"crop":
			return _crop(title.play_together, String(step.get("name", "card")))
	return "unknown action %s" % step.get("action", "")


## Save the window's last frame cut to the card (eyebrow, pill and slot, 16 px round) at the
## window's own pixels, as CROPS/<name>.png: the card up close for a look, at a fraction of a
## full capture's size.
static func _crop(card: PlayTogetherCard, crop_name: String) -> String:
	var viewport := card.get_viewport()
	var image := viewport.get_texture().get_image()
	var to_screen := viewport.get_final_transform() * card.get_global_transform_with_canvas()
	var rect := Rect2i((to_screen * Rect2(Vector2.ZERO, card.size)).grow(16.0))
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CROPS))
	var path := "%s/%s.png" % [CROPS, crop_name]
	var error := image.get_region(rect).save_png(path)
	return "crop %s %s -> %s (%s)" % [crop_name, rect, ProjectSettings.globalize_path(path), error]


static func _card(title: TitleScreen, state: String, step: Dictionary) -> String:
	var card := title.play_together
	title.resume_entry.older_button.get_popup().hide()
	card.reset()
	card.get_viewport().gui_release_focus()
	var code := String(step.get("code", SAMPLE_CODE))
	match state:
		"rest":
			pass
		"hover_host":
			card.set_hot(PlayTogetherCard.Face.HOST)
		"hover_join":
			card.set_hot(PlayTogetherCard.Face.JOIN)
		"focus":
			card.pill.grab_focus()
		"join":
			card.open_join()
			card.code_edit.text = code
			card.code_edit.caret_column = code.length()
		"connecting":
			card.open_join()
			card.code_edit.text = code
			title.show_join_status(SessionFlow.JOIN_CONNECTING)
		"error":
			card.open_join()
			card.code_edit.text = code
			title.show_join_status(
				SessionFlow.JOIN_FAILED, String(step.get("message", SessionFlow.NO_ROOM))
			)
		"version":
			card.open_join()
			card.code_edit.text = code
			var message := VersionGate.mismatch_message("0.2.9", UpdateVersion.get_current())
			title.show_join_status(SessionFlow.JOIN_FAILED, message)
		"flood":
			# Short of the flood's end: its finish asks Root for a room.
			var flood_s := PlayTogetherCard.MOTION_WASH * 1.4
			card.press(PlayTogetherCard.Face.HOST)
			_hold(card, minf(float(step.get("at", 0.0)), flood_s * 0.9))
		"opening":
			card.open_join()
			_hold(card, float(step.get("at", 0.0)))
		"older":
			title.resume_entry.older_button.show_popup()
		_:
			return "unknown card state %s" % state
	return "card %s: hot %s, joining %s, status '%s'" % [
		state,
		PlayTogetherCard.Face.keys()[card.hot],
		str(card.joining),
		card.status_label.text if card.status_row.visible else "",
	]


## Hold every easing of the card `at` seconds in.
static func _hold(card: PlayTogetherCard, at: float) -> void:
	for tween in card.easings():
		tween.pause()
		tween.custom_step(at)


static func _words(card: PlayTogetherCard, shown: bool) -> String:
	for part: String in ["Title", "Caption", "Icon"]:
		for face: String in ["Host", "Join"]:
			(card.pill.get_node(face + part) as Control).visible = shown
	return "words %s" % ("shown" if shown else "hidden")


## Paper's contrast against the lightest wash pixel under each face's words, from the window's
## last frame; and the lightest pixel anywhere on that face's half, for the bloom.
static func _contrast(card: PlayTogetherCard) -> String:
	var viewport := card.get_viewport()
	var image := viewport.get_texture().get_image()
	var to_screen := viewport.get_final_transform() * card.pill.get_global_transform_with_canvas()
	var lines: Array[String] = []
	for face: PlayTogetherCard.Face in [PlayTogetherCard.Face.HOST, PlayTogetherCard.Face.JOIN]:
		var words := _lightest(image, to_screen * card.words_rect(face).grow(-1.0))
		# The face's half less its rim and the seam's light line.
		var half := Rect2(24.0, 12.0, PlayTogetherCard.CARD_SIZE.x * 0.5 - 36.0, 88.0)
		if face == PlayTogetherCard.Face.JOIN:
			half.position.x = PlayTogetherCard.CARD_SIZE.x * 0.5 + 12.0
		var face_top := _lightest(image, to_screen * half)
		lines.append(
			"%s words lightest #%s paper %.2f:1, face lightest #%s" % [
				PlayTogetherCard.Face.keys()[face],
				words.to_html(false),
				_ratio(ThemeColors.PAPER, words),
				face_top.to_html(false),
			]
		)
	return "; ".join(lines)


static func _lightest(image: Image, rect: Rect2) -> Color:
	var best := Color.BLACK
	var area := Rect2i(rect.abs()).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var pixel := image.get_pixel(x, y)
			if _luminance(pixel) > _luminance(best):
				best = pixel
	return best


static func _ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(color: Color) -> float:
	var linear := color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b


static func _sessions(title: TitleScreen, count: int) -> String:
	var entry := title.resume_entry
	if count <= 0:
		entry.provider = SessionFile.list
	else:
		var now := int(Time.get_unix_time_from_system())
		var list: Array[Dictionary] = []
		for i in mini(count, SAMPLE_SESSIONS.size()):
			var sample: Array = SAMPLE_SESSIONS[i]
			list.append(
				{
					"id": "_play_together_sample_%d" % i,
					"name": sample[0],
					"maps": sample[1],
					"last_played": now - int(sample[2]) * DAY_S,
				}
			)
		entry.provider = func() -> Array[Dictionary]: return list
	entry.refresh()
	return "resume: %s / %s, %d older" % [
		entry.resume_button.text if entry.visible else "hidden",
		entry.caption.text,
		entry.older_button.get_popup().item_count,
	]
