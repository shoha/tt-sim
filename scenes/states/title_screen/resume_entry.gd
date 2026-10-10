class_name ResumeEntry
extends VBoxContainer

## The title's quiet Resume, under the Play together card (a session remembers its tables
## across nights, user verdict 2026-10-09). It shows only when saved sessions exist
## (SessionFile.list(), the last played first): the newest is named in a quiet Ghost button by
## the day it was last played ("Resume Friday's session"), over a caption naming its maps
## ("Old Mill and 2 more"); the older ones, named the same way, are in a small menu beside it.
## Choosing one asks Root to resume it (resume_requested; SessionKeeper.resume()), which opens
## a new room with the session's shelf, its kept tables and its party.

## Resume the saved session `id`.
signal resume_requested(id: String)

## How many older sessions the menu lists.
const MAX_OLDER := 8
const ICON := "player-play"
const OLDER_ICON := "dots-vertical"
const OLDER := "Older sessions"
## The button's words, by how long ago the session was last played (when_of()).
const RESUME := "Resume %s session"
const RESUME_UNDATED := "Resume your last session"
const RESUME_DATED := "Resume the session from %s"
## A session's maps: its name (the first map it shelved) and how many more.
const MAPS_ONE := "%s"
const MAPS_MORE := "%s and %d more"
const MONTHS := [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
]
const WEEKDAYS := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const DAY_S := 86400

## The saved sessions, the last played first; tests and the UI tour replace it.
var provider: Callable = SessionFile.list
## Now, in unix seconds; tests replace it.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())
## The local time zone's offset from UTC in minutes; tests replace it.
var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))

var resume_button: Button
var caption: Label
var older_button: MenuButton

var _sessions: Array[Dictionary] = []
## Held out of the way while Join in place is open (hold()).
var _held := false


func _ready() -> void:
	theme_type_variation = &"BoxContainerTight"
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"BoxContainerSpaced"
	add_child(row)
	resume_button = Button.new()
	resume_button.name = "Resume"
	resume_button.theme_type_variation = &"Ghost"
	resume_button.icon = IconButton.load_icon(ICON)
	resume_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	resume_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resume_button.pressed.connect(_on_resume_pressed)
	row.add_child(resume_button)
	older_button = MenuButton.new()
	older_button.name = "Older"
	older_button.flat = false
	older_button.theme_type_variation = &"Ghost"
	older_button.icon = IconButton.load_icon(OLDER_ICON)
	older_button.tooltip_text = OLDER
	older_button.accessibility_name = OLDER
	older_button.focus_mode = Control.FOCUS_ALL
	older_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	older_button.get_popup().id_pressed.connect(_on_older_chosen)
	row.add_child(older_button)
	caption = Label.new()
	caption.name = "Maps"
	caption.theme_type_variation = &"Caption"
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(caption)
	refresh()


## Read the saved sessions again and show the newest (hidden with none).
func refresh() -> void:
	_sessions = provider.call()
	visible = not _held and not _sessions.is_empty()
	if _sessions.is_empty():
		return
	var now: int = clock.call()
	var newest: Dictionary = _sessions[0]
	resume_button.text = button_text(newest, now, bias_minutes)
	resume_button.tooltip_text = resume_button.text
	caption.text = maps_line(newest)
	caption.visible = caption.text != ""
	var popup := older_button.get_popup()
	popup.clear()
	var older := _sessions.slice(1, 1 + MAX_OLDER)
	for i in older.size():
		popup.add_item(menu_text(older[i], now, bias_minutes), i + 1)
	older_button.visible = not older.is_empty()


## Hold Resume out of the way (`on`) while Join in place is open on the card above: the join's
## line takes its place, so a long failure under the card never pushes the column off a short
## canvas, and a player joining a friend's room has no use for their own sessions meanwhile.
func hold(on: bool) -> void:
	_held = on
	visible = not _held and not _sessions.is_empty()


## The session ids listed, newest first.
func session_ids() -> Array[String]:
	var ids: Array[String] = []
	for session in _sessions:
		ids.append(str(session.get("id", "")))
	return ids


## The button's words for `session` at `now` (unix s) in a zone `bias` minutes from UTC:
## "Resume today's session", "Resume yesterday's session", "Resume Friday's session" within
## the week, "Resume the session from 2 October" before it. Pure.
static func button_text(session: Dictionary, now: int, bias: int) -> String:
	var when := when_of(int(session.get("last_played", 0)), now, bias)
	if when == "":
		return RESUME_UNDATED
	if when.ends_with("'s"):
		return RESUME % when
	return RESUME_DATED % when


## A menu line for an older session: the button's words and its maps, "Thursday's session:
## Oak's Lab and 1 more". Pure.
static func menu_text(session: Dictionary, now: int, bias: int) -> String:
	var words := button_text(session, now, bias).trim_prefix("Resume ")
	words = words[0].to_upper() + words.substr(1)
	var maps := maps_line(session)
	return words if maps == "" else "%s: %s" % [words, maps]


## How long ago `last_played` was, as the button says it: "today's", "yesterday's",
## "Friday's" (two to six days back), or a date, "2 October"; "" when unknown. Days are the
## local zone's (`bias` minutes from UTC). Pure.
static func when_of(last_played: int, now: int, bias: int) -> String:
	if last_played <= 0:
		return ""
	var offset := bias * 60
	var days := floori(float(now + offset) / DAY_S) - floori(float(last_played + offset) / DAY_S)
	if days <= 0:
		return "today's"
	if days == 1:
		return "yesterday's"
	var date := Time.get_datetime_dict_from_unix_time(last_played + offset)
	if days < 7:
		return "%s's" % WEEKDAYS[int(date.weekday)]
	return "%d %s" % [int(date.day), MONTHS[int(date.month) - 1]]


## The session's maps: its name (the first map it shelved) and how many more, "Old Mill and
## 2 more"; "" with no name. Pure.
static func maps_line(session: Dictionary) -> String:
	var name := str(session.get("name", "")).strip_edges()
	if name == "":
		return ""
	var more := int(session.get("maps", 0)) - 1
	return MAPS_MORE % [name, more] if more > 0 else MAPS_ONE % name


func _on_resume_pressed() -> void:
	if not _sessions.is_empty():
		resume_requested.emit(str(_sessions[0].get("id", "")))


func _on_older_chosen(index: int) -> void:
	if index > 0 and index < _sessions.size():
		resume_requested.emit(str(_sessions[index].get("id", "")))
