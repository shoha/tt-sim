class_name DesignerCatalog
extends RefCounted

## The catalog as the designer's asset picker shows it (design doc 4.3, panel 1): the entries of
## the library and its dependencies folded into one tile per GROUP of variants, with the
## filters the picker offers (search, category chips, tag chips, a role's usual category).
## Pure: it is handed LibraryQuery candidates and returns plain dictionaries.

## Tiles the picker draws at most; a longer result says to refine the filter.
const MAX_TILES := 120


## One record per group: {ref (what a query names it by: the asset id when the group has one
## member, else the group key), group, name, category, subtype, tags (the members' union, sorted),
## size_class, triangles (the largest member's), variants, members (their refs), library, thumb
## (an absolute picture file of a member, or "")}. Sorted by category then name.
static func groups(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var by_group := {}
	var order: Array[String] = []
	for candidate in candidates:
		var key := String(candidate["group"])
		if not by_group.has(key):
			by_group[key] = []
			order.append(key)
		(by_group[key] as Array).append(candidate)
	var out: Array[Dictionary] = []
	for key in order:
		out.append(_record(key, by_group[key]))
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["category"] != b["category"]:
				return String(a["category"]) < String(b["category"])
			return String(a["name"]) < String(b["name"])
	)
	return out


## `all` filtered: `search` (case-insensitive text in the name, subtype, library, tags or a
## member's id), `categories` (any of; [] for all), `tags` (all of; [] for any), `role` (keep
## the groups whose members are used as that role in the catalog, or whose category is the
## role's usual one when the catalog lists no roles).
static func filter(
	all: Array[Dictionary], search: String, categories: Array, tags: Array, role: String = ""
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var needle := search.strip_edges().to_lower()
	for record in all:
		if not categories.is_empty() and not record["category"] in categories:
			continue
		var held: Array = record["tags"]
		var has_all := true
		for tag in tags:
			has_all = has_all and tag in held
		if not has_all:
			continue
		if role != "" and not _fits_role(record, role):
			continue
		if needle != "" and not _matches(record, needle):
			continue
		out.append(record)
	return out


## The tags of `all` with how many groups carry each, most common first (ties by name).
static func tag_counts(all: Array[Dictionary]) -> Array[Dictionary]:
	var counts := {}
	for record in all:
		for tag: String in record["tags"]:
			counts[tag] = int(counts.get(tag, 0)) + 1
	var out: Array[Dictionary] = []
	for tag: String in counts:
		out.append({"tag": tag, "count": counts[tag]})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["count"] != b["count"]:
				return int(a["count"]) > int(b["count"])
			return String(a["tag"]) < String(b["tag"])
	)
	return out


## The categories present in `all`, in the contract's order.
static func categories_in(all: Array[Dictionary]) -> Array[String]:
	var present := {}
	for record in all:
		present[String(record["category"])] = true
	var out: Array[String] = []
	for category in LibraryContracts.CATEGORIES:
		if present.has(category):
			out.append(category)
	return out


static func _record(key: String, members: Array) -> Dictionary:
	var first: Dictionary = members[0]
	var entry: Dictionary = first["entry"]
	var tags := {}
	var triangles := 0
	var refs: Array[String] = []
	var thumb := ""
	for member: Dictionary in members:
		var member_entry: Dictionary = member["entry"]
		for tag: Variant in member_entry.get("tags", []):
			tags[String(tag)] = true
		triangles = maxi(triangles, int(member_entry.get("triangles", 0)))
		refs.append(String(member["ref"]))
		var picture: Variant = member_entry.get("thumb")
		if (
			thumb == ""
			and picture is String
			and String(picture) != ""
			and String(member["folder"]) != ""
		):
			thumb = String(member["folder"]).path_join(String(picture))
	var tag_list: Array[String] = []
	tag_list.assign(tags.keys())
	tag_list.sort()
	return {
		"ref": refs[0] if members.size() == 1 else key,
		"group": key,
		"name": String(entry.get("name", String(first["id"]))),
		"category": String(entry.get("category", "other")),
		"subtype": String(entry.get("subtype", "")),
		"tags": tag_list,
		"size_class": String(entry.get("size_class", "")),
		"triangles": triangles,
		"variants": members.size(),
		"members": refs,
		"library": String(first["library"]),
		"thumb": thumb,
	}


static func _fits_role(record: Dictionary, role: String) -> bool:
	return String(record["category"]) == String(DesignerSlots.ROLE_CATEGORY.get(role, ""))


static func _matches(record: Dictionary, needle: String) -> bool:
	for field in ["name", "subtype", "library", "group"]:
		if needle in String(record[field]).to_lower():
			return true
	for tag: String in record["tags"]:
		if needle in tag.to_lower():
			return true
	for ref: String in record["members"]:
		if needle in ref.to_lower():
			return true
	return false
