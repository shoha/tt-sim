class_name LibraryGroups
extends RefCounted

## The palette's biomes grouped by the library that supplies them, for the New map dialog's
## biome picker (and any later list that should show where a place comes from). Pure: it is
## given the biome entries (PaletteLibrary.biomes) and the library list (LibraryRegistry.list)
## and returns the groups in display order: `core` first, then the other libraries
## alphabetically by name (ties by id), each group's biomes in palette order with the library's
## default biome first and, when a library has several seasons of one biome, the season shown
## after a name that would otherwise repeat. A biome belongs to the library its id names
## (LibraryIds.library_of); a library the list does not know is shown by its id.

## group(biomes, libraries) -> Array of {id, name, version, author, official, default_biome (a
## runtime biome id), biomes: Array[Dictionary] (the palette entries), labels: {biome id: the
## name to show}}.
static func group(
	biomes: Array[Dictionary], libraries: Array[Dictionary]
) -> Array[Dictionary]:
	var info_of := {}
	for item in libraries:
		if not info_of.has(item["id"]) or item["status"] == LibraryResolver.OK:
			info_of[item["id"]] = item
	var by_library := {}
	for biome in biomes:
		var library := LibraryIds.library_of(String(biome.get("id", "")))
		var held: Array = by_library.get(library, [])
		held.append(biome)
		by_library[library] = held
	var groups: Array[Dictionary] = []
	for library: String in by_library:
		var info: Dictionary = info_of.get(library, {})
		var members: Array = by_library[library]
		var default_biome := String(info.get("default_biome", ""))
		# Core keeps the palette's order (the dialog has always shown it so); another library
		# shows its default biome first.
		var typed: Array[Dictionary] = []
		for member: Dictionary in members:
			if member["id"] == default_biome and library != LibraryContracts.CORE_ID:
				typed.append(member)
		for member: Dictionary in members:
			if not (member["id"] == default_biome and library != LibraryContracts.CORE_ID):
				typed.append(member)
		groups.append(
			{
				"id": library,
				"name": String(info.get("name", library)),
				"version": String(info.get("version", "")),
				"author": String(info.get("author", "")),
				"official": bool(info.get("official", library == LibraryContracts.CORE_ID)),
				"default_biome": default_biome,
				"biomes": typed,
				"labels": _labels(typed),
			}
		)
	groups.sort_custom(_before)
	return groups


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var a_core: bool = a["id"] == LibraryContracts.CORE_ID
	var b_core: bool = b["id"] == LibraryContracts.CORE_ID
	if a_core != b_core:
		return a_core
	var left := String(a["name"]).to_lower()
	var right := String(b["name"]).to_lower()
	if left != right:
		return left < right
	return String(a["id"]) < String(b["id"])


## The label of each biome: its name, with the season in brackets when two biomes of the group
## share a name.
static func _labels(biomes: Array[Dictionary]) -> Dictionary:
	var counts := {}
	for biome in biomes:
		counts[biome["name"]] = int(counts.get(biome["name"], 0)) + 1
	var out := {}
	for biome in biomes:
		var text := String(biome["name"])
		if counts[biome["name"]] > 1 and String(biome.get("season", "")) != "":
			text += " (%s)" % biome["season"]
		out[String(biome["id"])] = text
	return out
