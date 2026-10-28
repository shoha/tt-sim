extends RefCounted

## Structures for the library tests (not a test file): procgen's recipe documents, index entries
## and a helper that writes a `structures/` folder into a library folder.

const World := preload("res://tests/unit/library_world.gd")


## The recipe text of structure kind `kind` ("cottage", "townhouse" or "stone_house").
static func recipe_text(kind: String = "cottage") -> String:
	match kind:
		"townhouse":
			return ProcgenRecipes.townhouse().to_json()
		"stone_house":
			return ProcgenRecipes.building().to_json()
	return ProcgenRecipes.cottage().to_json()


## An index entry for `id` (a plain 6 by 4 m cottage) with `changes` laid over it.
static func entry(id: String, changes: Dictionary = {}) -> Dictionary:
	var out := {
		"id": id,
		"name": id.capitalize(),
		"family": "house",
		"variant": "Plain",
		"tags": ["house"],
		"file": LibraryStructures.recipe_path(id),
		"default_size_m": [6, 4],
		"min_side_m": 2.5,
		"max_side_m": 14,
		"max_area_m2": 120,
		"plans": ["rect"],
		"expose": ["height"],
		"textured": false,
		"thumb": LibraryStructures.thumb_path(id),
	}
	out.merge(changes, true)
	return out


## The reader's "structures" source for `entries` and a {file name: text} table of recipes.
static func sources(entries: Array, recipes: Dictionary) -> Dictionary:
	return {"index": LibraryStructures.index_text(entries), "recipes": recipes}


## Writes structures `ids` ({id: recipe kind}) into library folder `folder`: the index, the
## recipe files and a one-pixel thumbnail for each.
static func write(folder: String, ids: Dictionary) -> void:
	var entries: Array = []
	for id: String in ids:
		entries.append(entry(id))
		World.write_text(folder.path_join(LibraryStructures.recipe_path(id)), recipe_text(ids[id]))
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(Color(0.6, 0.5, 0.4))
		DirAccess.make_dir_recursive_absolute(
			folder.path_join(LibraryStructures.thumb_path(id)).get_base_dir()
		)
		image.save_jpg(folder.path_join(LibraryStructures.thumb_path(id)))
	World.write_text(
		folder.path_join(LibraryStructures.INDEX_FILE), LibraryStructures.index_text(entries)
	)


## A map document holding one structure of `ref`.
static func map_with(ref: String, extra: Array[Structure] = []) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var plan := PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])
	doc.structures.append(Structure.make(1, ref, plan, 5))
	doc.structures.append_array(extra)
	return doc
