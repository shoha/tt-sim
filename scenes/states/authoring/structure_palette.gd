class_name StructurePalette
extends RefCounted

## The Building palette's pure logic: which structure rows a search finds, and how the rows group
## and order into family sections. No nodes, so tests call it directly (StructureToolPane draws it).

## The families a newcomer reaches for first, in order; the rest follow alphabetically.
const FIRST_FAMILIES: Array[String] = ["cottage", "house", "townhouse", "inn", "barn"]


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


## The sort rank of a family: its place in FIRST_FAMILIES, or past them all.
static func family_rank(family: String) -> int:
	var at := FIRST_FAMILIES.find(family.to_lower())
	return at if at >= 0 else FIRST_FAMILIES.size()


## The rows `query` finds, grouped by library and family: an Array of {"key", "family", "rows"} in
## display order (FIRST_FAMILIES first, then alphabetical; rows keep their given order).
static func sections(rows: Array, query: String) -> Array[Dictionary]:
	var by_key: Dictionary = {}
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		if not matches(row, query):
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
