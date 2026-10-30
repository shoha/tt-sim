class_name StructurePalette
extends RefCounted

## The Building palette's pure logic: which structure rows a search finds, and how the rows group
## and order into family sections. No nodes, so tests call it directly (StructureToolPane draws it).

## The families a newcomer reaches for first, in order; the rest follow alphabetically.
const FIRST_FAMILIES: Array[String] = ["cottage", "house", "townhouse", "inn", "barn"]


## The chip groups, in the order shown, each with the small caption above its chips. Chips of one
## group widen the choice (Farm and Inn: both), chips of different groups narrow it (Home and Stone:
## homes of stone).
const GROUPS: Array[Dictionary] = [
	{"id": "kind", "caption": "Kind"},
	{"id": "material", "caption": "Material"},
]

## The filter chips above the tiles: {"id", "label", "group", "families", "tags"}. A building has a
## chip when its family is one of the chip's families or one of its tags is one of the chip's tags.
## Order is the order shown. The "regional" tag is no chip: 85 of 98 buildings carry it, so it
## filtered nothing (it stays a tag, which street picking reads).
const CHIPS: Array[Dictionary] = [
	{
		"id": "home",
		"label": "Home",
		"group": "kind",
		"families": ["cottage", "house", "townhouse", "roundhouse", "stilt_house"],
		"tags": [],
	},
	{
		"id": "farm",
		"label": "Farm",
		"group": "kind",
		"families": ["farm", "granary"],
		"tags": ["farm", "barn", "granary"],
	},
	{"id": "inn", "label": "Inn", "group": "kind", "families": ["inn"], "tags": ["inn", "tavern"]},
	{
		"id": "castle",
		"label": "Castle",
		"group": "kind",
		"families": ["castle"],
		"tags": ["castle", "keep", "gatehouse"],
	},
	{
		"id": "church",
		"label": "Church",
		"group": "kind",
		"families": [],
		"tags": ["church", "chapel", "temple"],
	},
	{
		"id": "shop",
		"label": "Shop",
		"group": "kind",
		"families": [],
		"tags": ["shop", "market", "cafe"],
	},
	{"id": "ruin", "label": "Ruin", "group": "kind", "families": ["ruin"], "tags": ["ruin"]},
	{
		"id": "fantasy",
		"label": "Fantasy",
		"group": "kind",
		"families": ["fantasy"],
		"tags": ["fantasy"],
	},
	{"id": "toon", "label": "Toon", "group": "kind", "families": ["toon"], "tags": ["toon"]},
	{"id": "stone", "label": "Stone", "group": "material", "families": [], "tags": ["stone"]},
	{"id": "timber", "label": "Timber", "group": "material", "families": [], "tags": ["timber"]},
	{"id": "thatch", "label": "Thatch", "group": "material", "families": [], "tags": ["thatch"]},
]

## A tile's pixel sizes: the large tiles read a cottage's roof and walls, the small ones keep a long
## list on one screen. The gap is the TileRow's own between tiles.
const LARGE_THUMB_PX := 80
const SMALL_THUMB_PX := 48
const TILE_GAP_PX := 6.0
## The tile's width beyond its picture (the Tile style's side padding) and height beyond it (the
## label under the picture).
const TILE_PAD_PX := 12.0
const TILE_LABEL_PX := 34.0
const MIN_COLUMNS := 2
## How many tags the hover card lists.
const CARD_TAGS := 4


## True when `row` matches `query`: every word of the query is found in the structure's name, its
## family or one of its tags (case-blind, partial words count). An empty query matches all.
static func matches(row: Dictionary, query: String) -> bool:
	var words := query.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return true
	var haystack := "%s %s" % [String(row.get("name", "")), String(row.get("family", ""))]
	for tag: Variant in row.get("tags", []):
		haystack += " " + String(tag)
	haystack = haystack.to_lower().replace("_", " ")
	for word in words:
		if not haystack.contains(word):
			return false
	return true


## The chip with id `chip_id`, or {}.
static func chip(chip_id: String) -> Dictionary:
	for item in CHIPS:
		if item["id"] == chip_id:
			return item
	return {}


## True when `row` carries chip `chip_id` (its family or one of its tags is the chip's). Pure.
static func chip_matches(row: Dictionary, chip_id: String) -> bool:
	var item := chip(chip_id)
	if item.is_empty():
		return false
	if String(row.get("family", "")).to_lower() in (item["families"] as Array):
		return true
	for tag: Variant in row.get("tags", []):
		if String(tag).to_lower() in (item["tags"] as Array):
			return true
	return false


## True when `row` passes the `active` chips (ids): for each group that has an active chip, the
## row must carry at least one of that group's active chips. No active chips passes every row.
## `skip_group` leaves one group out (a chip's count asks what its group would add). Pure.
static func passes_chips(row: Dictionary, active: Array, skip_group: String = "") -> bool:
	var needed: Dictionary = {}
	for chip_id: Variant in active:
		var item := chip(String(chip_id))
		if item.is_empty() or item["group"] == skip_group:
			continue
		var group := String(item["group"])
		needed[group] = bool(needed.get(group, false)) or chip_matches(row, String(chip_id))
	for group: Variant in needed:
		if not needed[group]:
			return false
	return true


## The rows `query` and the `active` chips find, in the given order. Pure.
static func filtered(rows: Array, query: String, active: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		if matches(row, query) and passes_chips(row, active):
			out.append(row)
	return out


## How many buildings each chip would show, by chip id: the rows `query` finds, that pass the
## other groups' active chips, and carry the chip (so a chip of a group with a chip on counts what
## it would add). Pure.
static func chip_counts(rows: Array, query: String, active: Array) -> Dictionary:
	var counts: Dictionary = {}
	for item in CHIPS:
		var group := String(item["group"])
		var count := 0
		for row: Dictionary in rows:
			if (
				matches(row, query)
				and passes_chips(row, active, group)
				and chip_matches(row, String(item["id"]))
			):
				count += 1
		counts[String(item["id"])] = count
	return counts


## `active` with chip `chip_id` switched on or off (a new array, in CHIPS order). Pure.
static func toggled(active: Array, chip_id: String, on: bool) -> Array[String]:
	var out: Array[String] = []
	for item in CHIPS:
		var id := String(item["id"])
		if (id in active and id != chip_id) or (id == chip_id and on):
			out.append(id)
	return out


## The pane's count line: how many buildings show of how many the libraries offer ("14 of 72"), or
## "" when no filter is on. Pure.
static func tally(shown: int, total: int, filtering: bool) -> String:
	return "%d of %d" % [shown, total] if filtering else ""


## The words of a structure's hover card: {"title" (its name), "detail" (its family and a few of
## its tags), "size" (the size it starts at, in metres)}. The family and the "regional" tag are not
## repeated among the tags. Pure.
static func card(row: Dictionary) -> Dictionary:
	var family := String(row.get("family", ""))
	var tags := PackedStringArray()
	for tag: Variant in row.get("tags", []):
		var word := String(tag).replace("_", " ")
		if word != family.replace("_", " ") and word != "regional" and tags.size() < CARD_TAGS:
			tags.append(word)
	var detail := family.replace("_", " ").capitalize()
	if not tags.is_empty():
		detail += ": " + ", ".join(tags)
	var start := StructurePlacement.default_size(row)
	return {
		"title": String(row.get("name", "")),
		"detail": detail,
		"size": "About %d x %d m. Drag it out to size it." % [roundi(start.x), roundi(start.y)],
	}


## The tile measures for the pane `width` px wide: {"thumb", "tile" (Vector2), "columns"}. Large
## tiles carry an 80 px picture, small ones 48; the columns are as many tiles as fit the width,
## never fewer than MIN_COLUMNS. Pure.
static func tile_metrics(small: bool, width: float) -> Dictionary:
	var thumb := SMALL_THUMB_PX if small else LARGE_THUMB_PX
	var across := float(thumb) + TILE_PAD_PX
	var columns := maxi(MIN_COLUMNS, floori((width + TILE_GAP_PX) / (across + TILE_GAP_PX)))
	return {"thumb": thumb, "tile": Vector2(across, thumb + TILE_LABEL_PX), "columns": columns}


## The sort rank of a family: its place in FIRST_FAMILIES, or past them all.
static func family_rank(family: String) -> int:
	var at := FIRST_FAMILIES.find(family.to_lower())
	return at if at >= 0 else FIRST_FAMILIES.size()


## The rows `query` finds, grouped by library and family: an Array of {"key", "family", "rows"} in
## display order (FIRST_FAMILIES first, then alphabetical; rows keep their given order).
static func sections(rows: Array, query: String, active: Array = []) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		if not matches(row, query) or not passes_chips(row, active):
			continue
		var key := "%s:%s" % [row["library"], row["family"]]
		if not by_key.has(key):
			var section := {"key": key, "family": String(row["family"]), "rows": []}
			by_key[key] = section
			out.append(section)
		(by_key[key]["rows"] as Array).append(row)
	out.sort_custom(_before)
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ra := family_rank(String(a["family"]))
	var rb := family_rank(String(b["family"]))
	if ra != rb:
		return ra < rb
	return String(a["key"]) < String(b["key"])


## The caption of a family section: its name and how many buildings it holds.
static func section_caption(family: String, count: int) -> String:
	return "%s (%d)" % [family.capitalize(), count]
