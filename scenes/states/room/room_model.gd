class_name RoomModel
extends RefCounted

## What the room shows, from a session summary (SessionChannel.summary(), which host and
## clients both keep) and who is looking. RoomPanel draws it; these rules live here, pure, so
## they are tested without a scene:
##
## - Players: only those here now (a player who left keeps a session entry with peer 0 so a
##   rejoin maps back, but is not in the room), the GM (peer 1) first, then by name.
## - The shelf, oldest first, each map with its name and whether it is on the table; the GM's
##   rows also say whether the map changed this session (shelf_caption()).
## - The one action, the GM's only: Add a map while the shelf is empty, then Set out this map
##   once a shelf map is selected (nothing with a shelf but no selection) in the room; in the
##   drawer, Move the table to the selected map by name, shown only on a map that is not
##   already out (a caption says what to do instead). Only a live action takes the screen's
##   one accent fill.
## - Readiness is download state: "3 of 4 have it", and a player reads their own first ("You
##   and 2 others have it", "You are getting it · 40% · 2 of 4 have it"). Each player's state
##   for a map (download_state()) is has it, getting it with a percent, waiting (behind another
##   map or for their turn at the host), or at the table (not fetching it). Set out never
##   waits for it.
## - A shelf map the GM's own holdings lack is gone: the host counts itself as holding every
##   shelf map it has the files of (SessionChannel.get_holdings()), so one it lacks is a map
##   Resume found missing from its library. Nobody can get it (GONE on every row), a player's
##   room says the GM no longer has it, and it cannot be set out.

const SET_OUT := "Set out this map"
## The drawer's action, naming the map the table moves to (W6: one sentence, a placeholder).
const MOVE_TABLE := "Move the table to %s"
const ADD_MAP := "Add a map"
## A shelf row's caption parts (shelf_caption()).
const ON_TABLE := "On the table"
const CHANGED := "Changed this session"
## What Resume found of a shelf map (SessionKeeper.notes()): its map files changed since the
## session was kept (its live edits were dropped), or its folder is gone from this library.
## The GM's row says it on a line of its own (note_text()), over the caption.
const SINCE_CHANGED := "Changed since last time"
const MISSING := "Missing from your library"
## A player's room for a map gone from the GM's library: its shelf caption and the line under
## its picture.
const GM_LACKS := "The GM no longer has this map"
## A player's download state for one map (download_state()).
const HAS := &"has"
const GETTING := &"getting"
const WAITING := &"waiting"
const TABLE := &"table"
const GONE := &"gone"


## The players here, GM first then by name: {"id", "name", "gm", "you", "holds", "progress"},
## where "holds" lists the ref keys of the shelf maps that player has and "progress" maps the
## keys of those they are getting to a percent (0 while they wait).
static func players(summary: Dictionary, local_id: String) -> Array[Dictionary]:
	var holdings: Dictionary = summary.get("holdings", {})
	var progress: Dictionary = summary.get("progress", {})
	var out: Array[Dictionary] = []
	var listed: Dictionary = summary.get("players", {})
	for id: String in listed:
		var entry: Dictionary = listed[id]
		var peer := int(entry.get("peer_id", 0))
		if peer <= 0:
			continue
		var player_name := str(entry.get("name", "")).strip_edges()
		out.append(
			{
				"id": id,
				"name": player_name if player_name != "" else "Player",
				"gm": peer == 1,
				"you": id == local_id,
				"holds": holdings.get(id, []),
				"progress": progress.get(id, {}),
			}
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.gm != b.gm:
				return a.gm
			return str(a.name).naturalcasecmp_to(str(b.name)) < 0
	)
	return out


## The shelf, oldest first: {"key", "folder", "name", "on_table", "gone"}. A map with no name
## shows its folder; "gone" is a map the GM's own holdings lack (see the class doc), false
## when the summary has no holdings of the GM's.
static func shelf(summary: Dictionary) -> Array[Dictionary]:
	var table := str(summary.get("table", ""))
	var gm_holds: Variant = _gm_holdings(summary)
	var out: Array[Dictionary] = []
	for ref: Dictionary in summary.get("shelf", []):
		var key := SessionChannel.ref_key(ref)
		if key == "":
			continue
		var map_name := str(ref.get("name", "")).strip_edges()
		var folder := str(ref.get("folder", ""))
		out.append(
			{
				"key": key,
				"folder": folder,
				"name": map_name if map_name != "" else (folder if folder != "" else key.get_file()),
				"on_table": key == table,
				"gone": gm_holds is Array and not (gm_holds as Array).has(key),
			}
		)
	return out


## The GM's own holdings in `summary` (the player on peer 1), or null when it has none.
static func _gm_holdings(summary: Dictionary) -> Variant:
	var listed: Dictionary = summary.get("players", {})
	var holdings: Dictionary = summary.get("holdings", {})
	for id: String in listed:
		if int((listed[id] as Dictionary).get("peer_id", 0)) == 1 and holdings.has(id):
			return holdings[id]
	return null


## The GM's name, or "" when the GM is not listed.
static func gm_name(player_list: Array[Dictionary]) -> String:
	for player in player_list:
		if player.gm:
			return str(player.name)
	return ""


## The one action: {"text", "shown", "enabled", "add"} ("add": it opens the map picker). Only
## the GM has it. In the drawer it names the selected map (`selected_name`) and shows only
## while it is live: a map that is not already on the table.
static func action(
	in_drawer: bool,
	is_gm: bool,
	selected: String,
	table: String,
	shelf_size: int,
	selected_name := ""
) -> Dictionary:
	var none := {"text": "", "shown": false, "enabled": false, "add": false}
	if not is_gm:
		return none
	if in_drawer:
		if selected == "" or selected == table:
			return none
		return {"text": MOVE_TABLE % selected_name, "shown": true, "enabled": true, "add": false}
	if shelf_size == 0:
		return {"text": ADD_MAP, "shown": true, "enabled": true, "add": true}
	if selected == "":
		return none
	return {"text": SET_OUT, "shown": true, "enabled": true, "add": false}


## A shelf row's caption (the GM's view): the map on the table first ("On the table"), then
## whether it changed this session (`changed`, TableMover.changed_maps()), then `readiness`
## (readiness_text()), joined by middots, the first clause capitalized: "Changed this session
## · 3 of 4 have it", "On the table · changed this session". What Resume found of it (`note`)
## is on its own line (note_text()); a map missing from the library has no caption under that
## line, since nobody can get it from the GM. Pure.
static func shelf_caption(
	on_table: bool, changed: bool, readiness: String, note: StringName = &""
) -> String:
	if note == SessionFile.MISSING:
		return ""
	var parts: Array[String] = []
	if on_table:
		parts.append(ON_TABLE)
	if changed:
		parts.append(CHANGED if parts.is_empty() else CHANGED.to_lower())
	if not on_table and readiness != "":
		parts.append(readiness)
	return " · ".join(PackedStringArray(parts))


## What Resume found of a shelf map, as its row's own line: SessionFile.CHANGED is "Changed
## since last time", SessionFile.MISSING "Missing from your library", anything else "". Pure.
static func note_text(note: StringName) -> String:
	if note == SessionFile.CHANGED:
		return SINCE_CHANGED
	if note == SessionFile.MISSING:
		return MISSING
	return ""


## How many of the players here have the map `key`: "Everyone has it", "3 of 4 have it", or
## "" with no map or nobody else here.
static func readiness_text(player_list: Array[Dictionary], key: String) -> String:
	if key == "" or player_list.size() <= 1:
		return ""
	var holding := player_list.filter(func(p: Dictionary) -> bool: return key in p.holds).size()
	if holding == player_list.size():
		return "Everyone has it"
	return "%d of %d have it" % [holding, player_list.size()]


## One player's download state for the map `key` (`player` a players() entry): {"state",
## "percent"}, the state GONE (`gone`: the GM no longer has it, so nobody gets it), HAS
## (in their holdings), GETTING (a percent above 0 of it here), WAITING (reported at 0:
## behind another map, or waiting for their turn at the host) or TABLE (not fetching it, so
## the table's load gets it). GONE also says whether the player is the GM ("gm"), whose row
## words it as the one who lacks it.
static func download_state(player: Dictionary, key: String, gone := false) -> Dictionary:
	if gone:
		return {"state": GONE, "percent": 0, "gm": bool(player.get("gm", false))}
	if key in player.get("holds", []):
		return {"state": HAS, "percent": 100}
	var progress: Dictionary = player.get("progress", {})
	if progress.has(key):
		var percent := int(progress[key])
		return {"state": GETTING if percent > 0 else WAITING, "percent": percent}
	return {"state": TABLE, "percent": 0}


## The readiness a player reads under a selected map: their own state first, then the room's,
## each saying what it counts ("You and 2 others have it", "Only you have it", "You are
## getting it · 40% · 2 of 4 have it", "You get it at the table · 2 of 4 have it"), or
## readiness_text() when the player is not listed or everyone has it.
static func own_readiness_text(player_list: Array[Dictionary], key: String) -> String:
	var room := readiness_text(player_list, key)
	var mine := player_list.filter(func(p: Dictionary) -> bool: return p.you)
	if key == "" or mine.is_empty() or room == "Everyone has it" or room == "":
		return room
	if key not in mine[0].holds:
		var own := download_state(mine[0], key)
		match own.state:
			GETTING:
				return "You are getting it · %d%% · %s" % [own.percent, room]
			WAITING:
				return "You are waiting to get it · %s" % room
		return "You get it at the table · %s" % room
	var others := player_list.filter(func(p: Dictionary) -> bool: return key in p.holds).size() - 1
	if others == 0:
		return "Only you have it"
	if others == 1:
		return "You and 1 other have it"
	return "You and %d others have it" % others


## The heading: {"title", "caption"}, from the current state every time, so it never goes stale
## after a return to the room.
static func header(
	in_drawer: bool, is_gm: bool, gm: String, shelf_size: int, table_name: String
) -> Dictionary:
	if in_drawer:
		var on_table := "On the table: %s" % table_name if table_name != "" else ""
		return {"title": "The room", "caption": on_table}
	if is_gm:
		var caption := (
			"Add a map to the shelf, then set it out"
			if shelf_size == 0
			else "Choose a map from the shelf and set it out"
		)
		return {"title": "Your room", "caption": caption}
	var title := "%s's room" % gm if gm != "" else "The room"
	return {"title": title, "caption": "The GM sets out the next map"}


## What the centre says with no map selected, over its painted placeholder: {"title",
## "caption"}. An empty shelf says what goes there and why (I5); the GM's one action is Add a
## map. A player is told what they can do here (look over the shelf) and who sets a map out.
static func empty_stage(is_gm: bool, shelf_size: int) -> Dictionary:
	if not is_gm and shelf_size == 0:
		return {
			"title": "The GM is choosing the maps",
			"caption": "They show on the shelf as the GM adds them",
		}
	if not is_gm:
		return {
			"title": "Look over the maps on the shelf",
			"caption": "Pick one to see it here and whether you have it",
		}
	if shelf_size == 0:
		return {
			"title": "Add a map to the shelf",
			"caption": "The shelf holds the maps you can set out for everyone",
		}
	return {"title": "Choose a map from the shelf", "caption": "Set it out when everyone is here"}


## The drawer's caption where its action would be, when there is none to show: what moves the
## table, for the GM (choose a map, or add one when the shelf holds only the table's) and for
## a player (the GM does). "" when the action is live.
static func drawer_hint(is_gm: bool, selected: String, table: String, shelf_size: int) -> String:
	if not is_gm:
		return "The GM moves the table to the next map"
	if selected != "" and selected != table:
		return ""
	if shelf_size <= 1:
		return "Add a map to the shelf to move the table there"
	return "Choose a map on the shelf to move the table there"
