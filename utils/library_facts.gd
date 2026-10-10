class_name LibraryFacts
extends RefCounted

## What the library says about a map, derived from its files on disk and the local indexes,
## never stored in the level: where it came from (the detail strip's source chip), how big it
## is, how many tokens it sets out and when it was last played here, and the library's order.
##
## The source is read from which map files the level names (LevelManager's info carries
## "map_path" and "map_document"): a map.glb alone came from Blender, a map.glb with a document
## over it is a Blender map dressed here, a document alone was made here, and a map.glb shipped
## inside the game (a res:// path) is Bundled. The order is the most recently played or edited
## first (LibraryPlays, the info's modified_at; a map made a minute ago leads even unplayed),
## with the Bundled maps last, in a row of their own.

const SOURCE_BLENDER := &"blender"
const SOURCE_DRESSED := &"dressed"
const SOURCE_MADE := &"made"
const SOURCE_BUNDLED := &"bundled"
const SOURCE_LABELS := {
	SOURCE_BLENDER: "From Blender",
	SOURCE_DRESSED: "Blender, dressed here",
	SOURCE_MADE: "Made here",
	SOURCE_BUNDLED: "Bundled",
}
const NEVER_PLAYED := "Not played yet"
const METRES_PER_FOOT := 0.3048


## The source of the map `info` describes (SOURCE_*). Pure.
static func source_of(info: Dictionary) -> StringName:
	var map_path := String(info.get("map_path", ""))
	if map_path.begins_with("res://"):
		return SOURCE_BUNDLED
	if map_path != "":
		return SOURCE_DRESSED if String(info.get("map_document", "")) != "" else SOURCE_BLENDER
	return SOURCE_MADE


static func is_bundled(info: Dictionary) -> bool:
	return source_of(info) == SOURCE_BUNDLED


## `levels` in the library's order, each a copy with "played_at" (unix seconds, 0 when never)
## from `plays` ({folder: unix seconds}, LibraryPlays.all(); an entry's own "played_at" when
## `plays` lacks its folder): the latest of played and modified first, the Bundled maps after
## every other. Pure.
static func ordered(levels: Array, plays: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in levels:
		var info := entry.duplicate()
		var folder := String(info.get("folder", ""))
		info["played_at"] = int(plays.get(folder, info.get("played_at", 0)))
		out.append(info)
	out.sort_custom(_comes_first)
	return out


static func _comes_first(a: Dictionary, b: Dictionary) -> bool:
	var bundled_a := is_bundled(a)
	if bundled_a != is_bundled(b):
		return not bundled_a
	return last_touched(a) > last_touched(b)


## When the map was last played or edited, whichever is later (unix seconds). Pure.
static func last_touched(info: Dictionary) -> int:
	return maxi(int(info.get("played_at", 0)), int(info.get("modified_at", 0)))


## "Played 3 days ago", or NEVER_PLAYED. Pure.
static func played_text(played_at: int, now_unix: int) -> String:
	if played_at <= 0:
		return NEVER_PLAYED
	return "Played " + LevelCard.relative_time(now_unix - played_at, played_at)


## "No tokens", "1 token", "4 tokens". Pure.
static func tokens_text(count: int) -> String:
	if count <= 0:
		return "No tokens"
	return "1 token" if count == 1 else "%d tokens" % count


## "150 x 100 ft" for a footprint in feet, each side to the nearest 5 ft square; "" for none.
## Pure.
static func size_text(feet: Vector2) -> String:
	if feet.x <= 0.0 or feet.y <= 0.0:
		return ""
	return "%d x %d ft" % [_squares(feet.x), _squares(feet.y)]


static func _squares(feet: float) -> int:
	return maxi(roundi(feet / 5.0), 1) * 5


## The map's footprint in feet (X by Z), or Vector2.ZERO when it cannot be read: a Blender
## map's from its map.glb (the import check reads only the GLB's JSON chunk), a map made here
## from its document's manifest (never the heights).
static func footprint_ft(info: Dictionary) -> Vector2:
	var folder := String(info.get("folder", ""))
	var map_path := String(info.get("map_path", ""))
	if map_path != "":
		var glb := map_path if map_path.begins_with("res://") else LevelManager.map_path(folder)
		if folder == "" and not map_path.begins_with("res://"):
			return Vector2.ZERO
		var report := GlbCheck.check(glb)
		if report.error == "" and report.has_bounds:
			return report.footprint_ft
		return Vector2.ZERO
	if folder == "" or String(info.get("map_document", "")) == "":
		return Vector2.ZERO
	return document_size_m(LevelManager.map_document_path(folder)) / METRES_PER_FOOT


## The size in metres of the map.ttmap at `path`, from its manifest alone, or Vector2.ZERO.
static func document_size_m(path: String) -> Vector2:
	if not FileAccess.file_exists(path):
		return Vector2.ZERO
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return Vector2.ZERO
	var text := ""
	if zip.get_files().has(MapDocumentIO.MANIFEST_ENTRY):
		text = zip.read_file(MapDocumentIO.MANIFEST_ENTRY).get_string_from_utf8()
	zip.close()
	var parser := JSON.new()
	if text == "" or parser.parse(text) != OK or not parser.data is Dictionary:
		return Vector2.ZERO
	var manifest: Dictionary = parser.data
	var cells: Variant = manifest.get("size_cells")
	var cell: Variant = manifest.get("cell_size_m", LevelData.DEFAULT_GRID_CELL_SIZE)
	if not (cells is Array and (cells as Array).size() == 2) or not (cell is float or cell is int):
		return Vector2.ZERO
	return Vector2(float(cells[0]), float(cells[1])) * float(cell)
