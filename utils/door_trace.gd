class_name DoorTrace
extends RefCounted

## The title's doors clicked during a first launch's graphics warm-up, as a player clicks them
## (card firstlaunch2, 2026-11-09): real mouse events at each control's centre, through the
## window's own input path, so an overlay over the title takes the click as it would. Off unless
## the command line asks for it (BootTrace's `--boot-trace-doors=<plan>`), loaded only then.
##
## A plan is steps joined by "+", each `<door>@<when>`. The doors: host (Play together's Host),
## join (Join, a code typed, Join), resume (the saved session's Resume), play (the first map of
## the player's own selected, then Play), edit (the same, then Edit map), build (New map's
## Generate, then the dialog's Create a second later) and close (the window's close button).
## When: seconds after the title's _ready, `draw` (the frame the warm-up reaches its DRAW phase,
## the last few frames before it ends) or `done` (the first frame after it is done).
##
##   godot --main-pack <game.pck> -- --boot-trace --boot-trace-doors=host@1.5+join@1.7
##
## The result (merged into BootTrace's JSON line): per step the time it ran, then the end the plan
## waited for (the last door's destination: the room, a table loaded, authoring open, the join's
## answer on the card or a host error), its time after the last click and after the warm-up was
## done, the frames from the first click to the end (worst, over 100 and 250 ms), and the bar:
## when it first showed after a click, how many times its value moved, and the longest still
## stretch while it showed.

const TIMEOUT_S := 150.0
const HITCH_MS := 100.0
const FROZEN_MS := 250.0
## A code no room has (LobbyCode decodes only base 36).
const JOIN_CODE := "FL2!"
## How long the new-map dialog stays up before Create, as a player looks at it.
const DIALOG_S := 1.0
## Root.State's numbers (fixed: Root's enum comment).
const STATE_ROOM := 1
const STATE_PLAYING := 3
const STATE_AUTHORING := 5
## Where the close door leaves its time (unix seconds), for the launcher to time the quit.
const CLOSE_STAMP := "user://door_trace_close.txt"

static var _frame_ms := PackedFloat64Array()
static var _last_us: int = 0
static var _bar_seen_us: int = 0
static var _bar_moves: int = 0
static var _bar_value: float = -1.0
static var _bar_moved_us: int = 0
static var _bar_still_ms: float = 0.0
static var _done_us: int = 0
static var _draw_us: int = 0
static var _states: PackedStringArray = []
static var _watch := Callable()
## The pipeline compiles seen after the warm-up was done and before the first click, by frame
## ("<ms>:<kinds>"): what still compiles in the background behind a finished warm-up.
static var _tail := PackedStringArray()
static var _tail_counts := PackedInt64Array()
static var _clicked := false


## Runs `plan_text` (see the class doc), then hands its result to BootTrace.finish_doors().
static func run(tree: SceneTree, plan_text: String) -> void:
	var root: Node = tree.current_scene
	var title_us := Time.get_ticks_usec()
	_last_us = title_us
	_watch = _on_frame.bind(root)
	tree.process_frame.connect(_watch)
	var steps: Array[Dictionary] = []
	for part in plan_text.split("+", false):
		steps.append({"door": part.get_slice("@", 0), "when": part.get_slice("@", 1)})
	var out := {"doors_plan": plan_text, "doors": []}
	var first_click_frame := -1
	var last_click_us := 0
	for step in steps:
		while not _due(String(step.when), title_us):
			if Time.get_ticks_usec() - title_us > int(TIMEOUT_S * 1000000.0):
				_end(tree, out, "timed out before " + String(step.door))
				return
			await tree.process_frame
		if first_click_frame < 0:
			first_click_frame = _frame_ms.size()
		_clicked = true
		last_click_us = Time.get_ticks_usec()
		BootTrace.mark("doors: " + String(step.door))
		var ran: String = await _open(tree, root, String(step.door))
		(out.doors as Array).append(
			{
				"door": step.door,
				"at_ms": snappedf((last_click_us - title_us) / 1000.0, 0.1),
				"warm": _done_us > 0,
				"ran": ran,
			}
		)
	var last: String = String(steps[-1].door) if not steps.is_empty() else ""
	while not _arrived(root, last):
		if Time.get_ticks_usec() - last_click_us > int(TIMEOUT_S * 1000000.0):
			_end(tree, out, "timed out waiting for " + last)
			return
		await tree.process_frame
	var end_us := Time.get_ticks_usec()
	BootTrace.mark("doors: arrived (%s)" % last)
	out["arrived_ms"] = snappedf((end_us - last_click_us) / 1000.0, 0.1)
	if _done_us > 0:
		out["after_warm_ms"] = snappedf((end_us - _done_us) / 1000.0, 0.1)
	out["frames"] = _report(maxi(first_click_frame, 0), _frame_ms.size())
	_end(tree, out, "")


static func _due(when: String, title_us: int) -> bool:
	match when:
		"draw":
			return _draw_us > 0
		"done":
			return _done_us > 0
	return Time.get_ticks_usec() - title_us >= int(float(when) * 1000000.0)


## Clicks `door` and returns what it did ("" when its control was not there).
static func _open(tree: SceneTree, root: Node, door: String) -> String:
	var title: Node = root.get("_title_screen")
	if door == "close":
		var f := FileAccess.open(CLOSE_STAMP, FileAccess.WRITE)
		if f:
			f.store_string(str(Time.get_unix_time_from_system()))
			f.close()
		tree.root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		tree.root.close_requested.emit()
		return "close requested"
	if title == null or not is_instance_valid(title):
		return "no title"
	var card: Node = title.get("play_together")
	match door:
		"host":
			return await _click(tree, card.get("host_face"))
		"join":
			var clicked: String = await _click(tree, card.get("join_face"))
			await tree.process_frame
			var edit: LineEdit = card.get("code_edit")
			edit.text = JOIN_CODE
			edit.text_changed.emit(JOIN_CODE)
			await tree.process_frame
			return clicked + ", " + await _click(tree, card.get("join_button"))
		"resume":
			var entry: Node = title.get("resume_entry")
			return await _click(tree, entry.get("resume_button") if entry != null else null)
		"play", "edit":
			var grid: Node = title.get("grid")
			var cards: Array = grid.get("_cards")
			var own: Control = cards[0] if int(grid.call("own_card_count")) > 0 else null
			var picked: String = await _click(tree, own)
			await tree.process_frame
			var panel: Node = title.get("map_panel")
			var button := "play_button" if door == "play" else "edit_button"
			return picked + ", " + await _click(tree, panel.get(button))
		"build":
			var new_map: Node = title.get("new_map_card")
			var opened: String = await _click(tree, new_map.get("generate_button"))
			var dialog: Node = null
			var asked := Time.get_ticks_usec()
			while dialog == null and Time.get_ticks_usec() - asked < 10000000:
				await tree.process_frame
				dialog = root.get("_new_map_dialog")
			if dialog == null:
				return opened + ", no dialog"
			var shown := Time.get_ticks_usec()
			while Time.get_ticks_usec() - shown < int(DIALOG_S * 1000000.0):
				await tree.process_frame
			BootTrace.mark("doors: build: create")
			return opened + ", " + await _click(tree, dialog.get("create_button"))
	return "unknown door"


## A click at `control`'s centre as the OS would send it: a motion, then press and release on
## frames of their own (validation_bridge.gd _inject_click has why). Returns what it clicked.
static func _click(tree: SceneTree, control: Control) -> String:
	if control == null or not is_instance_valid(control) or not control.is_visible_in_tree():
		return "not shown"
	var at: Vector2 = (
		control.get_viewport().get_final_transform() * control.get_global_rect().get_center()
	)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await tree.process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed:
			await tree.process_frame
	return "clicked " + String(control.name)


## Whether the plan's last door has reached its end.
static func _arrived(root: Node, door: String) -> bool:
	var state := int(root.call("get_current_state"))
	match door:
		"host", "resume":
			return state == STATE_ROOM or (_done_us > 0 and _network_failed(root, 3.0))
		"join":
			var title: Node = root.get("_title_screen")
			if title == null or not is_instance_valid(title):
				return state != 0
			var card: Node = title.get("play_together")
			var status := String((card.get("status_label") as Label).text)
			return _done_us > 0 and not bool(card.get("busy")) and status != ""
		"play":
			var table: Node = root.get("_level_play_controller")
			return (
				state == STATE_PLAYING
				and root.get("pending_level") == null
				and table != null
				and bool(table.call("has_active_level"))
			)
		"edit", "build":
			var controller: Node = root.get("_authoring_controller")
			return (
				state == STATE_AUTHORING
				and controller != null
				and is_instance_valid(controller)
				and bool(controller.get("_is_open"))
			)
	return _done_us > 0


## Hosting ended offline (no Steam, a lobby error) at least `after_s` past the warm-up.
static func _network_failed(_root: Node, after_s: float) -> bool:
	var offline := int(NetworkManager.connection_state) == 0
	return offline and Time.get_ticks_usec() - _done_us > int(after_s * 1000000.0)


static func _on_frame(root: Node) -> void:
	var now := Time.get_ticks_usec()
	_frame_ms.append((now - _last_us) / 1000.0)
	_last_us = now
	var state := "%d" % int(root.call("get_current_state"))
	if _states.is_empty() or _states[-1].get_slice("@", 0) != state:
		_states.append("%s@%.0f" % [state, now / 1000.0])
	var screen: Node = root.get("_warmup_screen")
	if _done_us == 0 and not bool(root.get("_warmup_pending")):
		_done_us = now
		_tail_counts = BootTrace.compile_counts()
	elif _done_us > 0 and not _clicked:
		var counts := BootTrace.compile_counts()
		var text := BootTrace.compile_text(_tail_counts, counts)
		if text != "":
			_tail.append("%.0f:%s" % [(now - _done_us) / 1000.0, text])
		_tail_counts = counts
	if screen == null or not is_instance_valid(screen):
		return
	if _draw_us == 0 and int(screen.get("phase")) >= 2:
		_draw_us = now
	var overlay: CanvasLayer = screen.get("_overlay")
	if overlay == null or not overlay.visible:
		return
	if _bar_seen_us == 0:
		_bar_seen_us = now
		_bar_moved_us = now
	var value := float(overlay.get("_target_progress"))
	if not is_equal_approx(value, _bar_value):
		_bar_moves += 1
		_bar_value = value
		_bar_moved_us = now
	_bar_still_ms = maxf(_bar_still_ms, (now - _bar_moved_us) / 1000.0)


## Frames [from, to): count, worst, over HITCH_MS and FROZEN_MS.
static func _report(from: int, to: int) -> Dictionary:
	var worst := 0.0
	var over := 0
	var frozen := 0
	for i in range(from, to):
		worst = maxf(worst, _frame_ms[i])
		over += 1 if _frame_ms[i] > HITCH_MS else 0
		frozen += 1 if _frame_ms[i] > FROZEN_MS else 0
	return {
		"count": to - from,
		"worst_ms": snappedf(worst, 0.1),
		"over_100": over,
		"over_250": frozen,
	}


static func _end(tree: SceneTree, out: Dictionary, failure: String) -> void:
	if tree.process_frame.is_connected(_watch):
		tree.process_frame.disconnect(_watch)
	if failure != "":
		out["failure"] = failure
		BootTrace.mark("doors: " + failure)
	out["bar"] = {
		"shown_ms": snappedf(_bar_seen_us / 1000.0, 0.1),
		"moves": _bar_moves,
		"longest_still_ms": snappedf(_bar_still_ms, 0.1),
		"last_value": snappedf(_bar_value, 0.001),
	}
	out["warm_done_ms"] = snappedf(_done_us / 1000.0, 0.1)
	out["states"] = _states
	out["tail"] = _tail
	print("door_trace: %s" % JSON.stringify(out))
	BootTrace.finish_doors(out)
