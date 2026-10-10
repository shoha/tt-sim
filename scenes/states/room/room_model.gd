class_name RoomModel
extends RefCounted

## What the room shows, from a session summary (SessionChannel.summary(), which host and
## clients both keep) and who is looking. RoomPanel draws it; these rules live here, pure, so
## they are tested without a scene:
##
## - Players: only those here now (a player who left keeps a session entry with peer 0 so a
##   rejoin maps back, but is not in the room), the GM (peer 1) first, then by name.
## - The shelf, oldest first, each map with its name and whether it is on the table.
## - The one action, the GM's only: Add a map while the shelf is empty, then Set out this map
##   once a shelf map is selected (nothing with a shelf but no selection) in the room; Move the
##   table here in the drawer, live only on a map that is not already out. Only a live action
##   takes the screen's one accent fill.
## - Readiness is download state: "3 of 4 have it", and a player reads their own first ("You
##   have it · 3 of 4"). Set out never waits for it.

const SET_OUT := "Set out this map"
const MOVE_TABLE := "Move the table here"
const ADD_MAP := "Add a map"


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


## The one action: {"text", "shown", "enabled", "add"} ("add": it opens the map picker). Only
## the GM has it.
static func action(
	in_drawer: bool, is_gm: bool, selected: String, table: String, shelf_size: int
) -> Dictionary:
	var none := {"text": "", "shown": false, "enabled": false, "add": false}
	if not is_gm:
		return none
	if in_drawer:
		var live := selected != "" and selected != table
		return {"text": MOVE_TABLE, "shown": true, "enabled": live, "add": false}
	if shelf_size == 0:
		return {"text": ADD_MAP, "shown": true, "enabled": true, "add": true}
	if selected == "":
		return none
	return {"text": SET_OUT, "shown": true, "enabled": true, "add": false}


## How many of the players here have the map `key`: "Everyone has it", "3 of 4 have it", or
## "" with no map or nobody else here.
static func readiness_text(player_list: Array[Dictionary], key: String) -> String:
	if key == "" or player_list.size() <= 1:
		return ""
	var holding := player_list.filter(func(p: Dictionary) -> bool: return key in p.holds).size()
	if holding == player_list.size():
		return "Everyone has it"
	return "%d of %d have it" % [holding, player_list.size()]


## The readiness a player reads under a selected map: their own state first, then the room's
## ("You have it · 3 of 4", "You get it at the table · 2 of 4"), or readiness_text() when the
## player `local_id` is not listed or everyone has it.
static func own_readiness_text(player_list: Array[Dictionary], key: String) -> String:
	var room := readiness_text(player_list, key)
	var mine := player_list.filter(func(p: Dictionary) -> bool: return p.you)
	if key == "" or mine.is_empty() or room == "Everyone has it" or room == "":
		return room
	var holding := player_list.filter(func(p: Dictionary) -> bool: return key in p.holds).size()
	var own := "You have it" if key in mine[0].holds else "You get it at the table"
	return "%s · %d of %d" % [own, holding, player_list.size()]


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
## "caption"}. An empty shelf says what goes there and why (I5); its one action is Add a map.
static func empty_stage(is_gm: bool, shelf_size: int) -> Dictionary:
	if not is_gm:
		return {"title": "The GM is choosing a map", "caption": "It shows here when they pick one"}
	if shelf_size == 0:
		return {
			"title": "Add a map to the shelf",
			"caption": "The shelf holds the maps you can set out for everyone",
		}
	return {"title": "Choose a map from the shelf", "caption": "Set it out when everyone is here"}
