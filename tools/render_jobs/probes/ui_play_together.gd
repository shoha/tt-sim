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
## - `sessions` (`count`, default 2): Resume lists `count` sample sessions, the newest played
##   yesterday evening; 0 reads the real list again.

## Sample saved sessions, newest first: name, maps, days before now.
const SAMPLE_SESSIONS := [
	["Old Mill", 3, 1],
	["Oak's Lab", 1, 4],
	["Fen Crossing", 2, 12],
]
const DAY_S := 86400
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
	return "unknown action %s" % step.get("action", "")


static func _card(title: TitleScreen, state: String, step: Dictionary) -> String:
	var card := title.play_together
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
		_:
			return "unknown card state %s" % state
	return "card %s: hot %s, joining %s, status '%s'" % [
		state,
		PlayTogetherCard.Face.keys()[card.hot],
		str(card.joining),
		card.status_label.text if card.status_row.visible else "",
	]


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
