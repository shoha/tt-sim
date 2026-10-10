class_name RoomModel
extends RefCounted

## What the room shows, from a session summary (SessionChannel.summary(), which host and
## clients both keep) and who is looking. RoomPanel draws it; these rules live here, pure, so
## they are tested without a scene:
##
## - Players: only those here now (a player who left keeps a session entry with peer 0 so a
##   rejoin maps back, but is not in the room), the GM (peer 1) first, then by name.
## - The shelf, oldest first, each map with its name and whether it is on the table.
## - The one action: Set out this map in the room, Move the table here in the drawer, the GM's
##   only. It is live only with a map selected (and, in the drawer, not the one already out),
##   and only a live action takes the screen's one accent fill.
## - Readiness is download state: "3 of 4 have it". Set out never waits for it.

const SET_OUT := "Set out this map"
const MOVE_TABLE := "Move the table here"


## The players here, GM first then by name: {"id", "name", "gm", "you", "holds"}, where
## "holds" lists the ref keys of the shelf maps that player has.
static func players(summary: Dictionary, local_id: String) -> Array[Dictionary]:
	var holdings: Dictionary = summary.get("holdings", {})
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
			}
		)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a.gm != b.gm:
				return a.gm
			return str(a.name).naturalcasecmp_to(str(b.name)) < 0
	)
	return out


## The shelf, oldest first: {"key", "folder", "name", "on_table"}. A map with no name shows
## its folder.
static func shelf(summary: Dictionary) -> Array[Dictionary]:
	var table := str(summary.get("table", ""))
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
			}
		)
	return out


## The GM's name, or "" when the GM is not listed.
static func gm_name(player_list: Array[Dictionary]) -> String:
	for player in player_list:
		if player.gm:
			return str(player.name)
	return ""


## The one action: {"text", "shown", "enabled"}. Only the GM has it.
static func action(in_drawer: bool, is_gm: bool, selected: String, table: String) -> Dictionary:
	if not is_gm:
		return {"text": "", "shown": false, "enabled": false}
	if in_drawer:
		return {"text": MOVE_TABLE, "shown": true, "enabled": selected != "" and selected != table}
	return {"text": SET_OUT, "shown": true, "enabled": selected != ""}


## How many of the players here have the map `key`: "Everyone has it", "3 of 4 have it", or
## "" with no map or nobody else here.
static func readiness_text(player_list: Array[Dictionary], key: String) -> String:
	if key == "" or player_list.size() <= 1:
		return ""
	var holding := player_list.filter(func(p: Dictionary) -> bool: return key in p.holds).size()
	if holding == player_list.size():
		return "Everyone has it"
	return "%d of %d have it" % [holding, player_list.size()]


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


## What the centre says with no map selected.
static func empty_stage_text(is_gm: bool, shelf_size: int) -> String:
	if not is_gm:
		return "The GM is choosing a map"
	return "Add a map to the shelf" if shelf_size == 0 else "Choose a map from the shelf"
